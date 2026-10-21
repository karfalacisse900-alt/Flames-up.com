-- REVIEW ONLY: read models over the existing immutable ledger. No money movement,
-- balance rewrite, payout-policy change, account creation or Support activation.
begin;
create view public.app_creator_finance_orders with (security_invoker=true) as
select e.id as earning_id, f.order_id, f.seller_id, f.category, f.currency, f.stripe_mode,
 f.item_title, e.created_at, p.confirmed_at as purchased_at, e.status,
 f.gross_received, f.refunded, f.captro_fee, f.processing_fee,
 case when f.processing_fee is not null then f.pending+f.available+f.paid_out else null end as creator_net,
 f.pending, f.available, f.paid_out, f.held
from (
 select order_id,seller_id,category,currency,stripe_mode,max(item_title) as item_title,
  coalesce(sum(amount) filter(where account='gross' and event_type<>'REFUND'),0)::bigint as gross_received,
  -coalesce(sum(amount) filter(where account='gross' and event_type='REFUND'),0)::bigint as refunded,
  coalesce(sum(amount) filter(where account='platform_fee'),0)::bigint as captro_fee,
  case when bool_and(processing_cost_known) then coalesce(sum(amount) filter(where account='processing_fee'),0)::bigint else null end as processing_fee,
  coalesce(sum(amount) filter(where account in ('pending','clearing','held','payout_pending')),0)::bigint as pending,
  coalesce(sum(amount) filter(where account in ('available','transferred')),0)::bigint as available,
  coalesce(sum(amount) filter(where account='paid_out'),0)::bigint as paid_out,
  coalesce(sum(amount) filter(where account='held'),0)::bigint as held
 from public.app_finance_ledger
 group by order_id,seller_id,category,currency,stripe_mode
) f join public.app_creator_earnings e on e.purchase_id=f.order_id and e.creator_id=f.seller_id
join public.app_purchases p on p.id=f.order_id;

create view public.app_creator_finance_pools with (security_invoker=true) as
select seller_id,category,currency,stripe_mode,count(*)::bigint as transactions,
 sum(gross_received)::bigint as gross_received,sum(refunded)::bigint as refunded,
 sum(captro_fee)::bigint as captro_fee,
 case when bool_and(processing_fee is not null) then sum(processing_fee)::bigint else null end as processing_fee,
 case when bool_and(creator_net is not null) then sum(creator_net)::bigint else null end as creator_net,
 sum(pending)::bigint as pending,sum(available)::bigint as available,
 sum(paid_out)::bigint as paid_out,sum(held)::bigint as held
from public.app_creator_finance_orders group by seller_id,category,currency,stripe_mode;

-- Existing FIFO payout entries already carry the source order. Attribution is
-- explanatory only: never add these allocations to the account payout balance.
-- MAX per source order avoids counting pending -> paid -> retry as new proceeds.
create view public.app_creator_finance_payouts with (security_invoker=true) as
select a.id as payout_id,a.creator_id as seller_id,l.category,a.currency,l.stripe_mode,
 a.amount as payout_amount,a.fee_amount as payout_fee,a.status,a.created_at,a.paid_at,
 a.arrival_at,a.failed_at,sum(l.portion)::bigint as attributed_amount
from (
 select seller_id,category,currency,stripe_mode,stripe_object_id,order_id,
  max(amount) filter(where amount>0 and account in ('payout_pending','paid_out')) as portion
 from public.app_finance_ledger
 where event_type in ('PAYOUT_STATE_CHANGED','PAYOUT_PAID')
 group by seller_id,category,currency,stripe_mode,stripe_object_id,order_id
) l join public.app_payouts a on a.provider_payout_id=l.stripe_object_id
 and a.creator_id=l.seller_id and a.currency=l.currency
join public.app_connected_accounts c on c.id=a.connected_account_id
 and c.user_id=l.seller_id and c.stripe_mode=l.stripe_mode
where l.portion is not null
group by a.id,l.category,l.stripe_mode;

revoke all on public.app_creator_finance_orders,public.app_creator_finance_pools,
 public.app_creator_finance_payouts from public,anon,authenticated;
grant select on public.app_creator_finance_orders,public.app_creator_finance_pools,
 public.app_creator_finance_payouts to service_role;
commit;
