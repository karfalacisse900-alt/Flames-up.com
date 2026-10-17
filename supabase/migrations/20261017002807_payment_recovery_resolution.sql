-- Prepared only. Recovery actions stay disabled until provider/staging acceptance.
begin;
alter table public.app_payment_recovery
  add column owner_id text,
  add column decision text check(decision in ('fulfill','refund')),
  add column decision_note text,
  add column decision_started_at timestamptz,
  add column attempt_count integer not null default 0,
  add column lease_token uuid,
  add column lease_until timestamptz,
  add column last_attempt_at timestamptz;
create table public.app_payment_recovery_events (
  id bigint generated always as identity primary key,
  purchase_id uuid not null references public.app_payment_recovery(purchase_id),
  operator_id text not null,
  event text not null check(event in ('claimed','fulfilled','refunded')),
  decision text not null,
  note text not null,
  reference text,
  created_at timestamptz not null default now()
);
alter table public.app_payment_recovery_events enable row level security;
revoke all on public.app_payment_recovery_events from public,anon,authenticated;
grant select,insert on public.app_payment_recovery_events to service_role;
grant usage on sequence public.app_payment_recovery_events_id_seq to service_role;

create function public.captro_claim_payment_recovery(p_purchase_id uuid,p_operator text,p_decision text,p_note text)
returns public.app_payment_recovery language plpgsql set search_path=public as $$
declare r app_payment_recovery%rowtype; p app_purchases%rowtype;
begin
  if p_operator is null or length(p_operator)<1 or p_decision not in ('fulfill','refund') or length(trim(coalesce(p_note,'')))<10 then
    raise exception 'CAPTRO_RECOVERY_REVIEW_REQUIRED'; end if;
  select * into p from app_purchases where id=p_purchase_id for update;
  select * into r from app_payment_recovery where purchase_id=p_purchase_id for update;
  if not found then raise exception 'CAPTRO_RECOVERY_NOT_FOUND'; end if;
  if r.status<>'needs_review' then return r; end if;
  if p.status not in ('expired','cancelled','rejected') or p.confirmed_at is not null or p.settlement_model<>'deferred'
    or exists(select 1 from app_entitlements where purchase_id=p.id)
    or exists(select 1 from app_creator_earnings where purchase_id=p.id) then
    raise exception 'CAPTRO_RECOVERY_MANUAL_ACCOUNTING_REQUIRED'; end if;
  if r.lease_until>now() then raise exception 'CAPTRO_RECOVERY_BUSY'; end if;
  -- Once a refund may have been sent, fulfillment is forbidden, even after timeout.
  if r.decision='refund' and p_decision<>'refund' then raise exception 'CAPTRO_RECOVERY_REFUND_IN_FLIGHT'; end if;
  update app_payment_recovery set owner_id=p_operator,decision=p_decision,decision_note=left(p_note,1000),
    decision_started_at=case when decision is distinct from p_decision then now() else coalesce(decision_started_at,now()) end,
    attempt_count=attempt_count+1,last_attempt_at=now(),lease_token=gen_random_uuid(),lease_until=now()+interval '10 minutes'
    where purchase_id=p_purchase_id returning * into r;
  insert into app_payment_recovery_events(purchase_id,operator_id,event,decision,note)
    values(p_purchase_id,p_operator,'claimed',p_decision,left(p_note,1000));
  return r;
end $$;

create function public.captro_resolve_payment_recovery(p_purchase_id uuid,p_operator text,p_token uuid,
  p_outcome text,p_reference text,p_charge_id text,p_processing_amount integer)
returns public.app_payment_recovery language plpgsql set search_path=public as $$
declare r app_payment_recovery%rowtype; p app_purchases%rowtype;
  item app_purchasables%rowtype; price app_prices%rowtype; slot uuid;
begin
  select * into p from app_purchases where id=p_purchase_id for update;
  select * into r from app_payment_recovery where purchase_id=p_purchase_id for update;
  if not found then raise exception 'CAPTRO_RECOVERY_NOT_FOUND'; end if;
  if r.status<>'needs_review' then
    if r.status=p_outcome and r.resolution_reference=p_reference then return r; end if;
    raise exception 'CAPTRO_RECOVERY_ALREADY_RESOLVED';
  end if;
  if r.owner_id is distinct from p_operator or r.lease_token is distinct from p_token or r.lease_until<=now() then
    raise exception 'CAPTRO_RECOVERY_LEASE_LOST'; end if;
  if p.status not in ('expired','cancelled','rejected') or p.confirmed_at is not null
    or exists(select 1 from app_entitlements where purchase_id=p.id)
    or exists(select 1 from app_creator_earnings where purchase_id=p.id)
    or p.settlement_model<>'deferred' or p.total_amount<>r.amount or p.currency<>r.currency then
    raise exception 'CAPTRO_RECOVERY_MANUAL_ACCOUNTING_REQUIRED'; end if;
  if p_outcome='fulfilled' and r.decision='fulfill' then
    if p.currency<>'USD' then raise exception 'CAPTRO_CURRENCY_SETTLEMENT_NOT_SUPPORTED'; end if;
    perform captro_assert_purchase_available(p);
    select * into item from app_purchasables where id=p.purchasable_id for update;
    select * into price from app_prices where id=p.price_id for update;
    if (item.capacity is not null and item.quantity_committed+p.quantity>item.capacity)
      or (price.capacity is not null and price.quantity_committed+p.quantity>price.capacity) then
      raise exception 'CAPTRO_CAPACITY_REACHED'; end if;
    if p.fulfillment_type='reservation' then
      slot := captro_reserve_booking_slot(item.id,(p.selection->>'startsAt')::timestamptz,
        (p.selection->>'endsAt')::timestamptz,p.quantity,item.booking_capacity);
    end if;
    update app_purchasables set quantity_committed=quantity_committed+p.quantity where id=item.id;
    update app_prices set quantity_committed=quantity_committed+p.quantity where id=price.id;
    update app_purchases set status='payment_pending',provider_payment_id=r.provider_payment_id,
      booking_slot_id=slot where id=p.id;
    perform captro_confirm_marketplace_purchase(p.id,'recovery-fulfill-'||p.id,p.provider_checkout_id,r.provider_payment_id,
      p_charge_id,null,r.amount,p_processing_amount,p.tax_amount,r.currency,null,p_reference);
  elsif p_outcome='refunded' and r.decision='refund' then
    if p_reference not like 're\_%' escape '\' then raise exception 'CAPTRO_RECOVERY_REFUND_REFERENCE_REQUIRED'; end if;
    -- Provider has confirmed a full refund of a released, unfulfilled purchase.
    -- Do not create an entitlement or decrement inventory a second time.
    insert into app_payments(purchase_id,provider,provider_event_id,provider_payment_id,status,amount,currency,payload_digest)
      values(p.id,'stripe','recovery-refund-'||p_reference,r.provider_payment_id,'refunded',r.amount,r.currency,p_reference);
    update app_purchases set status='refunded',provider_payment_id=r.provider_payment_id,updated_at=now() where id=p.id;
  else raise exception 'CAPTRO_RECOVERY_DECISION_MISMATCH'; end if;
  update app_payment_recovery set status=p_outcome,resolution_reference=p_reference,resolved_at=now(),
    lease_token=null,lease_until=null where purchase_id=p.id returning * into r;
  insert into app_payment_recovery_events(purchase_id,operator_id,event,decision,note,reference)
    values(p.id,p_operator,p_outcome,r.decision,r.decision_note,p_reference);
  return r;
end $$;
revoke all on function public.captro_claim_payment_recovery(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.captro_resolve_payment_recovery(uuid,text,uuid,text,text,text,integer) from public,anon,authenticated;
grant execute on function public.captro_claim_payment_recovery(uuid,text,text,text) to service_role;
grant execute on function public.captro_resolve_payment_recovery(uuid,text,uuid,text,text,text,integer) to service_role;
commit;
