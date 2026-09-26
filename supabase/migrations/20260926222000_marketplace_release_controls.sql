-- Release is an audited operator decision AFTER completion, never a checkout side effect.
alter table public.app_creator_earnings add column release_approved_at timestamptz, add column release_approved_by text;
create table public.app_earning_releases (
 id uuid primary key default gen_random_uuid(), purchase_id uuid not null unique references public.app_purchases(id),
 creator_id uuid not null references auth.users(id), connected_account_id uuid not null references public.app_connected_accounts(id),
 destination text not null, amount integer not null check(amount>0), currency text not null,
 status text not null default 'transferring' check(status in ('transferring','transferred','reversed','review_required')),
 provider_transfer_id text unique, first_attempt_at timestamptz not null default now(),
 lease_id uuid not null, lease_expires_at timestamptz not null, last_checked_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create index app_earning_releases_recovery_idx on public.app_earning_releases(status,last_checked_at);
alter table public.app_earning_releases enable row level security;
revoke all on public.app_earning_releases from public,anon,authenticated;
grant select,insert,update on public.app_earning_releases to service_role;

create function public.captro_review_earning_release(p_purchase_id uuid,p_admin_id text,p_note text,p_release_after timestamptz)
returns void language plpgsql set search_path=public as $$
declare p public.app_purchases%rowtype; item public.app_purchasables%rowtype; completed timestamptz;
begin
 select * into p from public.app_purchases where id=p_purchase_id for update;
 if p.id is null or p.settlement_model<>'deferred' or p.status<>'confirmed' then raise exception 'CAPTRO_RELEASE_NOT_ELIGIBLE'; end if;
 if length(trim(p_note))<10 or length(trim(p_admin_id))<3 or p_release_after is null then raise exception 'CAPTRO_RELEASE_REVIEW_REQUIRED'; end if;
 select * into item from public.app_purchasables where id=p.purchasable_id;
 if item.status in ('cancelled','canceled') then raise exception 'CAPTRO_ITEM_UNAVAILABLE'; end if;
 completed:=p.fulfillment_completed_at;
 if completed is null and item.content_type in ('event','meetup') and item.ends_at<=now() then completed:=item.ends_at; end if;
 if completed is null or completed>now() then raise exception 'CAPTRO_FULFILLMENT_NOT_COMPLETED'; end if;
 if p.provider_transfer_id is not null then return; end if;
 update public.app_purchases set fulfillment_completed_at=completed,
 fulfillment_completion_source=coalesce(fulfillment_completion_source,'event_ended_operator_review') where id=p.id;
 update public.app_creator_earnings set status='clearing',release_not_before=greatest(completed,p_release_after),
 release_approved_at=now(),release_approved_by=p_admin_id where purchase_id=p.id and status in ('pending','clearing');
end; $$;

create function public.captro_record_processing_cost(p_purchase_id uuid,p_cost integer)
returns void language plpgsql set search_path=public as $$
declare p public.app_purchases%rowtype; net integer;
begin
 select * into p from public.app_purchases where id=p_purchase_id for update;
 if p.id is null or p.settlement_model<>'deferred' or p.provider_transfer_id is not null or p_cost<0 then raise exception 'CAPTRO_PROCESSING_COST_INVALID'; end if;
 if exists(select 1 from public.app_earning_releases where purchase_id=p.id) then return; end if;
 net:=greatest(0,p.item_amount-(p.platform_fee_amount-p.service_fee_amount)-p_cost);
 update public.app_purchases set processing_amount=p_cost,fee_amount=p_cost,creator_amount=net where id=p.id;
 update public.app_creator_earnings set processing_amount=p_cost,creator_amount=net,processing_cost_known=true where purchase_id=p.id;
end; $$;

create function public.captro_claim_earning_transfer(p_purchase_id uuid,p_account_id uuid,p_destination text,p_lease uuid,p_identity_required boolean default true)
returns public.app_earning_releases language plpgsql set search_path=public as $$
declare p public.app_purchases%rowtype; e public.app_creator_earnings%rowtype; a public.app_connected_accounts%rowtype; r public.app_earning_releases%rowtype;
begin
 select * into p from public.app_purchases where id=p_purchase_id for update;
 select * into e from public.app_creator_earnings where purchase_id=p.id for update;
 select * into a from public.app_connected_accounts where id=p_account_id;
 if p.status<>'confirmed' or p.settlement_model<>'deferred' or e.id is null or e.creator_amount<=0 or e.refunded_amount>0 or e.disputed_amount>0
 or not e.processing_cost_known or e.release_approved_at is null or e.release_not_before is null or e.release_not_before>now()
 or p.fulfillment_completed_at is null or p.fulfillment_completed_at>now()
 or a.id is null or a.user_id<>p.creator_id or a.provider_account_id<>p_destination or a.stripe_mode<>p.stripe_mode
 or a.status<>'ready' or not a.details_submitted or a.requirements_currently_due<>'[]'::jsonb or not a.transfers_enabled or not a.payouts_enabled
 then raise exception 'CAPTRO_RELEASE_NOT_ELIGIBLE'; end if;
 if p_identity_required and not exists(select 1 from public.app_seller_identity_verifications where user_id=p.creator_id and stripe_mode=p.stripe_mode and status='verified')
 then raise exception 'CAPTRO_SELLER_IDENTITY_REQUIRED'; end if;
 if exists(select 1 from public.app_payment_reconciliation_issues where purchase_id=p.id and not resolved)
 then raise exception 'CAPTRO_RELEASE_REVIEW_REQUIRED'; end if;
 select * into r from public.app_earning_releases where purchase_id=p.id for update;
 if found then
   if r.destination<>p_destination or r.amount<>e.creator_amount or r.currency<>p.currency then raise exception 'CAPTRO_RELEASE_SNAPSHOT_MISMATCH'; end if;
   if r.status<>'transferring' or r.lease_expires_at>now() then return null; end if;
   update public.app_earning_releases set lease_id=p_lease,lease_expires_at=now()+interval '2 minutes',last_checked_at=now() where id=r.id returning * into r;
 else
   insert into public.app_earning_releases(purchase_id,creator_id,connected_account_id,destination,amount,currency,lease_id,lease_expires_at)
   values(p.id,p.creator_id,a.id,p_destination,e.creator_amount,p.currency,p_lease,now()+interval '2 minutes') returning * into r;
 end if;
 update public.app_creator_earnings set status='available' where id=e.id and status in ('pending','clearing');
 return r;
end; $$;

create function public.captro_finish_earning_transfer(p_purchase_id uuid,p_transfer_id text,p_amount integer,p_destination text)
returns boolean language plpgsql set search_path=public as $$
declare p public.app_purchases%rowtype; r public.app_earning_releases%rowtype; must_reverse boolean;
begin
 select * into p from public.app_purchases where id=p_purchase_id for update;
 select * into r from public.app_earning_releases where purchase_id=p.id for update;
 if r.id is null or r.amount<>p_amount or r.destination<>p_destination or p_transfer_id not like 'tr_%'
 or (r.provider_transfer_id is not null and r.provider_transfer_id<>p_transfer_id) then raise exception 'CAPTRO_RELEASE_SNAPSHOT_MISMATCH'; end if;
 must_reverse:=p.status<>'confirmed' or exists(select 1 from public.app_payment_reconciliation_issues where purchase_id=p.id and not resolved);
 update public.app_earning_releases set provider_transfer_id=p_transfer_id,status=case when must_reverse then 'review_required' else 'transferred' end,last_checked_at=now() where id=r.id;
 update public.app_purchases set provider_transfer_id=p_transfer_id,connected_account_id=r.connected_account_id,stripe_destination_account_id=r.destination where id=p.id;
 update public.app_creator_earnings set provider_transfer_id=p_transfer_id,connected_account_id=r.connected_account_id,
 status=case when must_reverse then status else 'transferred' end where purchase_id=p.id;
 return must_reverse;
end; $$;

-- Ledger balances never combine sandbox and live money.
create or replace function public.captro_ledger_balances(p_seller_id uuid) returns table(currency text,account text,amount bigint)
language sql stable set search_path=public as $$
 select l.currency,l.account,sum(l.amount)::bigint from public.app_marketplace_ledger l
 left join public.app_purchases p on p.id=l.order_id
 left join public.app_connected_accounts a on a.id=p.connected_account_id
 where l.seller_id=p_seller_id and coalesce(p.stripe_mode,a.stripe_mode,l.metadata->>'stripe_mode')=(select stripe_mode from public.app_payment_environment where id=true)
 group by l.currency,l.account;
$$;

-- Payout state changes append reversals plus the new state; repeated webhooks append nothing.
alter table public.app_payouts add column ledger_revision integer not null default 0;
create function public.captro_append_payout_ledger() returns trigger language plpgsql set search_path=public as $$
declare previous_bucket text; next_bucket text; mode text; mutation_id uuid:=gen_random_uuid();
begin
 select stripe_mode into mode from public.app_connected_accounts where id=new.connected_account_id;
 if mode is null then return new; end if;
 next_bucket:=case when new.status='paid' then 'paid_out' when new.status in ('pending','in_transit') then 'payout_pending' else 'transferred' end;
 previous_bucket:='transferred';
 if tg_op='UPDATE' then
   previous_bucket:=case when old.status='paid' then 'paid_out' when old.status in ('pending','in_transit') then 'payout_pending' else 'transferred' end;
   new.ledger_revision:=old.ledger_revision;
   if old.creator_id<>new.creator_id or old.amount<>new.amount or old.currency<>new.currency then raise exception 'CAPTRO_PAYOUT_SNAPSHOT_IMMUTABLE'; end if;
 end if;
 if previous_bucket=next_bucket then return new; end if;
 new.ledger_revision:=new.ledger_revision+1;
 insert into public.app_marketplace_ledger(entry_key,seller_id,event_type,account,amount,currency,stripe_object_id,metadata) values
 (new.id||':payout:'||mutation_id||':debit',new.creator_id,'PAYOUT_STATE_CHANGED',previous_bucket,-new.amount,new.currency,new.provider_payout_id,jsonb_build_object('stripe_mode',mode)),
 (new.id||':payout:'||mutation_id||':credit',new.creator_id,case when new.status='paid' then 'PAYOUT_PAID' else 'PAYOUT_STATE_CHANGED' end,next_bucket,new.amount,new.currency,new.provider_payout_id,jsonb_build_object('stripe_mode',mode));
 return new;
end; $$;
create trigger app_payouts_ledger after insert or update on public.app_payouts for each row execute function public.captro_append_payout_ledger();
revoke all on function public.captro_review_earning_release(uuid,text,text,timestamptz),public.captro_record_processing_cost(uuid,integer),public.captro_claim_earning_transfer(uuid,uuid,text,uuid,boolean),public.captro_finish_earning_transfer(uuid,text,integer,text),public.captro_append_payout_ledger() from public,anon,authenticated;
grant execute on function public.captro_review_earning_release(uuid,text,text,timestamptz),public.captro_record_processing_cost(uuid,integer),public.captro_claim_earning_transfer(uuid,uuid,text,uuid,boolean),public.captro_finish_earning_transfer(uuid,text,integer,text),public.captro_append_payout_ledger() to service_role;

create function public.captro_confirm_fulfillment(p_purchase_id uuid,p_buyer_id uuid) returns boolean language plpgsql set search_path=public as $$
declare p public.app_purchases%rowtype;
begin
 select * into p from public.app_purchases where id=p_purchase_id and buyer_id=p_buyer_id for update;
 if p.id is null or p.status<>'confirmed' then return false; end if;
 update public.app_purchases set fulfillment_completed_at=coalesce(fulfillment_completed_at,now()),
 fulfillment_completion_source=coalesce(fulfillment_completion_source,'buyer_confirmed') where id=p.id;
 return true;
end; $$;
revoke all on function public.captro_confirm_fulfillment(uuid,uuid) from public,anon,authenticated;
grant execute on function public.captro_confirm_fulfillment(uuid,uuid) to service_role;
