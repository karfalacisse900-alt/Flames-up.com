-- REVIEW ONLY. Requires the matching provider-aware Worker before enabling new
-- checkout. No price rewrite, provider calls, refunds, or historical deletion.
begin;

-- A single offering is one shared resource across its price tiers. Resource
-- capacity is separate from lifetime ticket/tier inventory. Existing offerings
-- default conservatively to one; review multi-capacity services before rollout.
alter table public.app_purchasables add column booking_capacity integer not null default 1
  check (booking_capacity between 1 and 1000000);

create or replace function public.captro_reserve_booking_slot(
  p_purchasable_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_quantity integer, p_capacity integer
) returns uuid language plpgsql set search_path = public as $$
declare slot_row public.app_booking_slots%rowtype; resource_capacity integer; peak bigint;
begin
  if p_starts_at is null or p_starts_at <= now() or p_ends_at is null
     or p_ends_at <= p_starts_at or p_quantity is null or p_quantity < 1 then
    raise exception 'CAPTRO_BOOKING_TIME_INVALID';
  end if;
  -- This lock serializes all tiers and starts for the same resource. No network
  -- work is performed under it. Cancellation also locks this same item row.
  select booking_capacity into resource_capacity from public.app_purchasables
    where id=p_purchasable_id for update;
  if not found then raise exception 'CAPTRO_ITEM_UNAVAILABLE'; end if;
  -- Half-open intervals: adjacent appointments do not overlap. Measure peak
  -- occupancy, not the sum of disjoint appointments within a long request.
  with points as (
    select p_starts_at as at_time
    union select starts_at from public.app_booking_slots
      where purchasable_id=p_purchasable_id and quantity_committed>0
        and starts_at>p_starts_at and starts_at<p_ends_at
  ) select coalesce(max(occupied),0) into peak from (
    select (select coalesce(sum(s.quantity_committed),0) from public.app_booking_slots s
      where s.purchasable_id=p_purchasable_id and s.starts_at<=p.at_time
        and (s.ends_at is null or s.ends_at>p.at_time)) as occupied from points p
  ) occupancy;
  if peak+p_quantity>resource_capacity then raise exception 'CAPTRO_BOOKING_SLOT_UNAVAILABLE'; end if;
  insert into public.app_booking_slots(purchasable_id,starts_at,ends_at,capacity)
    values(p_purchasable_id,p_starts_at,p_ends_at,resource_capacity)
    on conflict(purchasable_id,starts_at) do nothing;
  select * into slot_row from public.app_booking_slots
    where purchasable_id=p_purchasable_id and starts_at=p_starts_at for update;
  if slot_row.ends_at is distinct from p_ends_at then raise exception 'CAPTRO_BOOKING_TIME_INVALID'; end if;
  update public.app_booking_slots set capacity=resource_capacity,
    quantity_committed=quantity_committed+p_quantity,updated_at=now()
    where id=slot_row.id;
  return slot_row.id;
end $$;
revoke all on function public.captro_reserve_booking_slot(uuid,timestamptz,timestamptz,integer,integer) from public,anon,authenticated;
grant execute on function public.captro_reserve_booking_slot(uuid,timestamptz,timestamptz,integer,integer) to service_role;

create function public.captro_assert_purchase_available(p_purchase public.app_purchases)
returns void language plpgsql set search_path=public as $$
declare item public.app_purchasables%rowtype; price public.app_prices%rowtype;
begin
  select * into item from public.app_purchasables where id=p_purchase.purchasable_id for update;
  if not found or item.status<>'active' then raise exception 'CAPTRO_ITEM_UNAVAILABLE'; end if;
  if item.expires_at<=now() then raise exception 'CAPTRO_ITEM_EXPIRED'; end if;
  if item.content_type in ('event','meetup','party','ticket','access_pass') and item.ends_at<=now() then
    raise exception 'CAPTRO_EVENT_ENDED';
  end if;
  select * into price from public.app_prices where id=p_purchase.price_id for update;
  if not found or not price.active or price.purchasable_id<>item.id
    or price.unit_amount<>p_purchase.unit_amount or price.currency<>p_purchase.currency then
    raise exception 'CAPTRO_PRICE_UNAVAILABLE';
  end if;
  if price.currency not in ('USD','JPY') then raise exception 'CAPTRO_CURRENCY_UNSUPPORTED'; end if;
  if price.unit_amount>0 and price.currency<>'USD' and (item.public_data->>'moneyContractVersion') is distinct from '1' then
    raise exception 'CAPTRO_LEGACY_PRICE_REVIEW_REQUIRED';
  end if;
  if (item.capacity is not null and item.quantity_committed>item.capacity)
    or (price.capacity is not null and price.quantity_committed>price.capacity) then
    raise exception 'CAPTRO_CAPACITY_REACHED';
  end if;
end $$;
revoke all on function public.captro_assert_purchase_available(public.app_purchases) from public,anon,authenticated;
grant execute on function public.captro_assert_purchase_available(public.app_purchases) to service_role;

create function public.captro_guard_purchase_approval() returns trigger
language plpgsql set search_path=public as $$
begin
  if old.status='approval_pending' and new.status in ('payment_pending','confirmed') then
    perform public.captro_assert_purchase_available(new);
  end if;
  return new;
end $$;
revoke all on function public.captro_guard_purchase_approval() from public,anon,authenticated;
create trigger captro_guard_purchase_approval before update of status on public.app_purchases
  for each row execute function public.captro_guard_purchase_approval();

create function public.captro_validate_checkout(p_purchase_id uuid)
returns public.app_purchases language plpgsql set search_path=public as $$
declare purchase public.app_purchases%rowtype;
begin
  select * into purchase from public.app_purchases where id=p_purchase_id for update;
  if not found or purchase.status<>'payment_pending' then raise exception 'CAPTRO_PURCHASE_NOT_PAYABLE'; end if;
  if purchase.hold_expires_at<=now() then raise exception 'CAPTRO_PURCHASE_HOLD_ELAPSED'; end if;
  perform public.captro_assert_purchase_available(purchase);
  return purchase;
end $$;
revoke all on function public.captro_validate_checkout(uuid) from public,anon,authenticated;
grant execute on function public.captro_validate_checkout(uuid) to service_role;

-- Retain the old callable signature for older Workers. Wall-clock time alone is
-- not evidence of nonpayment. Only provider reconciliation may release a hold.
create or replace function public.captro_release_expired_purchase_holds()
returns integer language sql set search_path=public as $$ select 0; $$;
revoke all on function public.captro_release_expired_purchase_holds() from public,anon,authenticated;
grant execute on function public.captro_release_expired_purchase_holds() to service_role;

create table public.app_payment_recovery (
  purchase_id uuid primary key references public.app_purchases(id),
  provider_payment_id text not null unique,
  provider_event_id text not null,
  amount integer not null check(amount>0),
  currency text not null,
  reason text not null,
  status text not null default 'needs_review' check(status in ('needs_review','fulfilled','refunded')),
  resolution_reference text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check(status='needs_review' or (resolved_at is not null and resolution_reference is not null))
);
alter table public.app_payment_recovery enable row level security;
revoke all on public.app_payment_recovery from public,anon,authenticated;
grant select,insert,update on public.app_payment_recovery to service_role;

create function public.captro_record_late_payment(p_purchase_id uuid,p_payment_id text,p_event_id text,p_amount integer,p_currency text)
returns void language plpgsql set search_path=public as $$
declare purchase public.app_purchases%rowtype;
begin
  select * into purchase from public.app_purchases where id=p_purchase_id for update;
  if not found or purchase.total_amount<>p_amount or purchase.currency<>p_currency
    or (purchase.provider_payment_id is not null and purchase.provider_payment_id<>p_payment_id) then
    raise exception 'STRIPE_PAYMENT_MISMATCH';
  end if;
  if purchase.status in ('confirmed','refunded','partially_refunded') then return; end if;
  insert into public.app_payment_recovery(purchase_id,provider_payment_id,provider_event_id,amount,currency,reason)
    values(p_purchase_id,p_payment_id,p_event_id,p_amount,p_currency,'Verified payment after inventory hold released')
    on conflict(purchase_id) do nothing;
end $$;
revoke all on function public.captro_record_late_payment(uuid,text,text,integer,text) from public,anon,authenticated;
grant execute on function public.captro_record_late_payment(uuid,text,text,integer,text) to service_role;
commit;
