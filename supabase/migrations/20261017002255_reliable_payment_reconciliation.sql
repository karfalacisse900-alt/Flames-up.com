-- REVIEW ONLY. Deploy with matching Worker during the approved checkout gate.
-- All provider calls take place outside these short transactions.
begin;
create table public.app_purchase_reconciliation (
  purchase_id uuid primary key references public.app_purchases(id),
  first_seen_at timestamptz not null default now(),
  next_attempt_at timestamptz not null default now(),
  last_attempt_at timestamptz,
  attempt_count integer not null default 0,
  lease_token uuid,
  lease_until timestamptz,
  last_outcome text check(last_outcome in ('processing','transient_failure','missing_identity','confirmed','released','recovery')),
  completed_at timestamptz,
  needs_attention boolean not null default false
);
alter table public.app_purchase_reconciliation enable row level security;
revoke all on public.app_purchase_reconciliation from public,anon,authenticated;
grant select,insert,update on public.app_purchase_reconciliation to service_role;
create index captro_reconciliation_due on public.app_purchase_reconciliation(next_attempt_at,last_attempt_at)
  where completed_at is null;
create index captro_pending_holds_due on public.app_purchases(hold_expires_at,id) where status='payment_pending';

create function public.captro_claim_purchase_reconciliation(p_limit integer default 40)
returns table(purchase jsonb,token uuid,attempts integer,age_seconds bigint)
language plpgsql set search_path=public as $$
begin
  -- Bounded discovery; a failed old job already has a row, so cannot starve discovery.
  insert into app_purchase_reconciliation(purchase_id,first_seen_at,next_attempt_at)
    select p.id,p.created_at,p.hold_expires_at from app_purchases p
    where p.status='payment_pending' and p.hold_expires_at<=now()
      and not exists(select 1 from app_purchase_reconciliation q where q.purchase_id=p.id)
    order by p.hold_expires_at,p.id limit 400 on conflict do nothing;
  return query with due as (
    select q.purchase_id from app_purchase_reconciliation q
    where q.completed_at is null and q.next_attempt_at<=now()
      and (q.lease_until is null or q.lease_until<=now())
    -- Oldest due time wins. Backoff makes room for new work without allowing a
    -- sustained stream of new purchases to starve an already-due retry.
    order by q.next_attempt_at,q.last_attempt_at nulls first,q.purchase_id
    limit greatest(1,least(coalesce(p_limit,40),40)) for update skip locked
  ), claimed as (
    update app_purchase_reconciliation q set lease_token=gen_random_uuid(),
      lease_until=now()+interval '10 minutes',last_attempt_at=now(),attempt_count=attempt_count+1
    from due where q.purchase_id=due.purchase_id returning q.*
  ) select to_jsonb(p),q.lease_token,q.attempt_count,
    extract(epoch from now()-q.first_seen_at)::bigint
    from claimed q join app_purchases p on p.id=q.purchase_id;
end $$;

create function public.captro_renew_purchase_reconciliation(p_purchase_id uuid,p_token uuid)
returns boolean language sql set search_path=public as $$
  with renewed as(update app_purchase_reconciliation set lease_until=now()+interval '10 minutes'
    where purchase_id=p_purchase_id and lease_token=p_token and lease_until>now() and completed_at is null returning 1)
  select exists(select 1 from renewed);
$$;

create function public.captro_finish_purchase_reconciliation(p_purchase_id uuid,p_token uuid,p_outcome text)
returns boolean language plpgsql set search_path=public as $$
declare q app_purchase_reconciliation%rowtype; p app_purchases%rowtype; terminal boolean; delay_seconds integer;
begin
  select * into q from app_purchase_reconciliation where purchase_id=p_purchase_id for update;
  if not found or q.lease_token is distinct from p_token or q.lease_until<=now() then return false; end if;
  if p_outcome not in ('processing','transient_failure','missing_identity','confirmed','released','recovery') then
    raise exception 'CAPTRO_RECONCILIATION_OUTCOME_INVALID'; end if;
  select * into p from app_purchases where id=p_purchase_id;
  terminal := p_outcome in ('confirmed','released','recovery');
  if (p_outcome='confirmed' and p.status not in ('confirmed','refunded','partially_refunded'))
    or (p_outcome='released' and p.status not in ('expired','cancelled','rejected'))
    or (p_outcome='recovery' and not exists(select 1 from app_payment_recovery where purchase_id=p.id)) then
    raise exception 'CAPTRO_RECONCILIATION_TERMINAL_NOT_VERIFIED'; end if;
  -- Bounded exponential backoff plus deterministic jitter, retained across cron runs.
  delay_seconds := least(21600,120*power(2,least(q.attempt_count-1,8))::integer)
    + abs(hashtextextended(p_purchase_id::text,0)%61)::integer;
  update app_purchase_reconciliation set last_outcome=p_outcome,
    next_attempt_at=now()+make_interval(secs=>delay_seconds),lease_token=null,lease_until=null,
    completed_at=case when terminal then now() else null end,
    needs_attention=(p_outcome='recovery' or (not terminal and (q.attempt_count>=8 or q.first_seen_at<now()-interval '24 hours')))
    where purchase_id=p_purchase_id;
  return true;
end $$;

revoke all on function public.captro_claim_purchase_reconciliation(integer) from public,anon,authenticated;
revoke all on function public.captro_renew_purchase_reconciliation(uuid,uuid) from public,anon,authenticated;
revoke all on function public.captro_finish_purchase_reconciliation(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.captro_claim_purchase_reconciliation(integer) to service_role;
grant execute on function public.captro_renew_purchase_reconciliation(uuid,uuid) to service_role;
grant execute on function public.captro_finish_purchase_reconciliation(uuid,uuid,text) to service_role;
commit;
