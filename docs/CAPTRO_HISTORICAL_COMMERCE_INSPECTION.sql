-- PREPARED, NOT RUN IN PRODUCTION. Run only after explicit read-only audit approval.
-- No automatic rescaling, default resource capacity, row deletion or hold release.
begin read only;
set local statement_timeout='30s';

-- Stage 1: aggregates only. A missing version is ambiguous, not proof of a wrong price.
select pr.currency,coalesce(p.public_data->>'moneyContractVersion','unknown') contract,
  count(*) prices,min(pr.unit_amount) minimum_provider_units,max(pr.unit_amount) maximum_provider_units
from public.app_prices pr join public.app_purchasables p on p.id=pr.purchasable_id
group by pr.currency,coalesce(p.public_data->>'moneyContractVersion','unknown');

-- Financial snapshots are never rewritten to match a proposed catalog correction.
select currency,status,count(*) purchases,sum(total_amount::bigint) total_provider_units
from public.app_purchases group by currency,status;

-- Existing intervals: include paid commitments AND active/elapsed-but-unreconciled holds.
-- NULL end-times require explicit review; do not guess a duration.
select count(*) committed_slots,count(*) filter(where ends_at is null) unknown_end,
  count(*) filter(where capacity>1) multi_capacity_slots
from public.app_booking_slots where quantity_committed>0;

-- Canonical resource is currently one purchasable across all its price tiers.
-- Whether different offerings share a real-world resource requires owner review.
select a.purchasable_id,count(*) overlapping_pairs
from public.app_booking_slots a join public.app_booking_slots b
  on a.purchasable_id=b.purchasable_id and a.id<b.id
  and a.quantity_committed>0 and b.quantity_committed>0
  and (b.ends_at is null or a.starts_at<b.ends_at)
  and (a.ends_at is null or b.starts_at<a.ends_at)
group by a.purchasable_id;

-- Detect drift before capacity review; do not replace slots from this query.
select s.purchasable_id,s.id slot_id,s.quantity_committed,
  coalesce(sum(p.quantity) filter(where p.status in ('payment_pending','confirmed')),0) snapshot_commitments
from public.app_booking_slots s left join public.app_purchases p on p.booking_slot_id=s.id
group by s.purchasable_id,s.id,s.quantity_committed
having s.quantity_committed<>coalesce(sum(p.quantity) filter(where p.status in ('payment_pending','confirmed')),0);

select payment_interface,status,count(*) purchases,
  count(*) filter(where provider_payment_id is null and provider_checkout_id is null) missing_identity,
  min(created_at) oldest_created_at
from public.app_purchases where status='payment_pending' group by payment_interface,status;
commit;

-- Stage 2, separately approved: review scoped catalog IDs with creator-authored
-- amounts, original request/version, currency exponent, provider receipt, terms,
-- resource capacity and already-promised reservations. No customer card data.
-- Ambiguous non-USD paid catalog entries remain checkout-gated. Correct only
-- explicitly reviewed future catalog versions; retain immutable order snapshots.
-- Unreviewed booking_capacity stays NULL. Explicit operator-approved capacity
-- must cover retained commitments; conflicts require owner/buyer coordination,
-- never silent cancellation, price reinterpretation, or bulk mutation.
