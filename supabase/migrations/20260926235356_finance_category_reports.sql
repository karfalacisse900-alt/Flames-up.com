-- Accounting projections, not wallets. No Stripe operation or checkout dependency.
create function public.captro_finance_category(kind text) returns text
language sql immutable set search_path=public as $$
 select case when kind in ('event','party','ticket','access_pass') then 'event'
 when kind in ('club','meetup','deal') then kind when kind in ('group','group_access') then 'group_access'
 when kind in ('offer','booking','reservation','local_offer') then 'local_offer' else 'unassigned' end;
$$;

-- Associate new payout movements with source orders FIFO within ONE seller,
-- currency and Stripe mode. The immutable ledger itself retains each allocation.
-- Legacy/unmatched provider funds remain explicitly unassigned, never fabricated.
create or replace function public.captro_append_payout_ledger() returns trigger language plpgsql set search_path=public as $$
declare previous_bucket text:='transferred'; next_bucket text; mode text;
 remaining bigint:=new.amount; portion bigint; allocation record; mutation uuid:=gen_random_uuid();
begin
 select stripe_mode into mode from public.app_connected_accounts where id=new.connected_account_id and user_id=new.creator_id;
 if mode is null then raise exception 'CAPTRO_PAYOUT_OWNER_MISMATCH'; end if;
 next_bucket:=case when new.status='paid' then 'paid_out' when new.status in ('pending','in_transit') then 'payout_pending' else 'transferred' end;
 if tg_op='UPDATE' then
  if old.creator_id<>new.creator_id or old.amount<>new.amount or old.currency<>new.currency or old.connected_account_id<>new.connected_account_id then raise exception 'CAPTRO_PAYOUT_SNAPSHOT_IMMUTABLE'; end if;
  previous_bucket:=case when old.status='paid' then 'paid_out' when old.status in ('pending','in_transit') then 'payout_pending' else 'transferred' end;
 end if;
 if previous_bucket=next_bucket then return new; end if;
 perform pg_advisory_xact_lock(hashtextextended('payout-allocation:'||new.creator_id||':'||new.currency||':'||mode,0));
 for allocation in
  select l.order_id,sum(l.amount)::bigint as available,min(l.created_at) as first_at
  from public.app_marketplace_ledger l left join public.app_purchases p on p.id=l.order_id
  where l.seller_id=new.creator_id and l.currency=new.currency and l.account=previous_bucket
   and coalesce(p.stripe_mode,l.metadata->>'stripe_mode')=mode
   and (previous_bucket='transferred' or l.stripe_object_id=new.provider_payout_id)
  group by l.order_id having sum(l.amount)>0 order by first_at,l.order_id nulls last
 loop
  exit when remaining<=0;
  portion:=least(remaining,allocation.available);
  insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id,metadata) values
   (new.id||':'||mutation||':'||coalesce(allocation.order_id::text,'unassigned')||':debit',allocation.order_id,new.creator_id,'PAYOUT_STATE_CHANGED',previous_bucket,-portion,new.currency,new.provider_payout_id,jsonb_build_object('stripe_mode',mode,'allocation_policy','order_fifo')),
   (new.id||':'||mutation||':'||coalesce(allocation.order_id::text,'unassigned')||':credit',allocation.order_id,new.creator_id,case when new.status='paid' then 'PAYOUT_PAID' else 'PAYOUT_STATE_CHANGED' end,next_bucket,portion,new.currency,new.provider_payout_id,jsonb_build_object('stripe_mode',mode,'allocation_policy','order_fifo'));
  remaining:=remaining-portion;
 end loop;
 if remaining>0 then
  insert into public.app_marketplace_ledger(entry_key,seller_id,event_type,account,amount,currency,stripe_object_id,metadata) values
   (new.id||':'||mutation||':unmatched:debit',new.creator_id,'PAYOUT_STATE_CHANGED',previous_bucket,-remaining,new.currency,new.provider_payout_id,jsonb_build_object('stripe_mode',mode,'reconciliation_required',true)),
   (new.id||':'||mutation||':unmatched:credit',new.creator_id,'PAYOUT_STATE_CHANGED',next_bucket,remaining,new.currency,new.provider_payout_id,jsonb_build_object('stripe_mode',mode,'reconciliation_required',true));
 end if;
 return new;
end; $$;

-- Append gross refund movements; never rewrite an old ledger entry.
create function public.captro_append_refund_finance() returns trigger language plpgsql set search_path=public as $$
declare before_amount bigint:=0; after_amount bigint:=0; delta bigint;
begin
 if tg_op='UPDATE' then
  if old.purchase_id<>new.purchase_id or old.creator_id<>new.creator_id or old.currency<>new.currency or old.amount<>new.amount or old.service_fee_refund_amount<>new.service_fee_refund_amount then raise exception 'CAPTRO_REFUND_SNAPSHOT_IMMUTABLE'; end if;
  if old.status='succeeded' then before_amount:=old.amount; end if;
 end if;
 if new.status='succeeded' then after_amount:=new.amount; end if;
 delta:=after_amount-before_amount;
 if delta=0 then return new; end if;
 insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id)
 values(new.id||':refund:'||gen_random_uuid(),new.purchase_id,new.creator_id,'REFUND','gross',-delta,new.currency,new.provider_refund_id);
 if new.service_fee_refund_amount>0 then
  insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id)
  values(new.id||':fee-refund:'||gen_random_uuid(),new.purchase_id,new.creator_id,'REFUND','platform_fee',case when delta>0 then -new.service_fee_refund_amount else new.service_fee_refund_amount end,new.currency,new.provider_refund_id);
 end if;
 return new;
end; $$;
create trigger app_refunds_finance after insert or update on public.app_refunds for each row execute function public.captro_append_refund_finance();
insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id)
 select id||':refund:opening',purchase_id,creator_id,'REFUND','gross',-amount,currency,provider_refund_id from public.app_refunds where status='succeeded'
 on conflict(entry_key) do nothing;

insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id)
 select id||':fee-refund:opening',purchase_id,creator_id,'REFUND','platform_fee',-service_fee_refund_amount,currency,provider_refund_id from public.app_refunds where status='succeeded' and service_fee_refund_amount>0
 on conflict(entry_key) do nothing;

-- Complete missing opening gross/fee entries from retained order snapshots.
insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id)
 select e.id||':finance-opening:'||x.account,e.purchase_id,e.creator_id,'OPENING_BALANCE',x.account,x.amount,e.currency,e.provider_payment_id
 from public.app_creator_earnings e cross join lateral (values ('gross',e.buyer_total),('platform_fee',e.platform_fee),('processing_fee',e.processing_amount)) x(account,amount)
 where not exists(select 1 from public.app_marketplace_ledger l where l.order_id=e.purchase_id and l.account=x.account and l.event_type in ('CUSTOMER_PAYMENT','CAPTRO_PLATFORM_FEE','PROCESSING_FEE','OPENING_BALANCE'))
 on conflict(entry_key) do nothing;
create view public.app_finance_ledger with (security_invoker=true) as
 select l.*,coalesce(e.processing_cost_known,false) as processing_cost_known,p.buyer_id,p.purchasable_id as object_id,p.item_title,p.content_type,
 public.captro_finance_category(p.content_type) as category,
 coalesce(p.stripe_mode,l.metadata->>'stripe_mode') as stripe_mode,
 p.provider_payment_id as stripe_payment_intent_id,p.provider_transfer_id as stripe_transfer_id
 from public.app_marketplace_ledger l left join public.app_purchases p on p.id=l.order_id left join public.app_creator_earnings e on e.purchase_id=l.order_id;
create view public.app_finance_order_totals with (security_invoker=true) as
 select order_id,seller_id,buyer_id,object_id,item_title,category,currency,stripe_mode,
 min(created_at) as created_at, max(stripe_payment_intent_id) as stripe_payment_intent_id,max(stripe_transfer_id) as stripe_transfer_id,
 coalesce(sum(amount) filter(where account='gross'),0)::bigint as gross,
 coalesce(sum(amount) filter(where account='platform_fee'),0)::bigint as captro_fee,
 case when bool_and(processing_cost_known) then coalesce(sum(amount) filter(where account='processing_fee'),0)::bigint else null end as processing_fee,
 coalesce(sum(amount) filter(where account in ('pending','clearing','held','payout_pending')),0)::bigint as pending,
 coalesce(sum(amount) filter(where account in ('available','transferred')),0)::bigint as available,
 coalesce(sum(amount) filter(where account='paid_out'),0)::bigint as paid_out
 from public.app_finance_ledger group by order_id,seller_id,buyer_id,object_id,item_title,category,currency,stripe_mode;
create view public.app_finance_pool_totals with (security_invoker=true) as
 select category,currency,stripe_mode,count(distinct order_id)::bigint as orders,sum(gross)::bigint as gross,
 sum(captro_fee)::bigint as captro_fee,case when bool_and(processing_fee is not null) then sum(processing_fee)::bigint else null end as processing_fee,
 sum(pending)::bigint as pending,sum(available)::bigint as available,sum(paid_out)::bigint as paid_out
 from public.app_finance_order_totals group by category,currency,stripe_mode;
create view public.app_finance_object_totals with (security_invoker=true) as
 select category,currency,stripe_mode,seller_id,object_id,max(item_title) as title,count(distinct order_id)::bigint as orders,
 sum(gross)::bigint as gross,sum(pending)::bigint as pending,sum(available)::bigint as available,sum(paid_out)::bigint as paid_out
 from public.app_finance_order_totals group by category,currency,stripe_mode,seller_id,object_id;
create view public.app_finance_seller_totals with (security_invoker=true) as
 select seller_id,currency,stripe_mode,sum(pending)::bigint as pending,sum(available)::bigint as available,sum(paid_out)::bigint as paid_out
 from public.app_finance_order_totals group by seller_id,currency,stripe_mode;
revoke all on public.app_finance_ledger,public.app_finance_order_totals,public.app_finance_pool_totals,public.app_finance_object_totals,public.app_finance_seller_totals from public,anon,authenticated;
grant select on public.app_finance_ledger,public.app_finance_order_totals,public.app_finance_pool_totals,public.app_finance_object_totals,public.app_finance_seller_totals to service_role;
revoke all on function public.captro_finance_category(text),public.captro_append_refund_finance() from public,anon,authenticated;
grant execute on function public.captro_finance_category(text),public.captro_append_refund_finance() to service_role;
