-- A database is explicitly provisioned for exactly one Stripe mode. No default:
-- service-role operations must configure this in the isolated test/live environment.
create table public.app_payment_environment (
  id boolean primary key default true check (id),
  stripe_mode text not null check (stripe_mode in ('test', 'live'))
);
alter table public.app_payment_environment enable row level security;
revoke all on public.app_payment_environment from anon, authenticated;
grant all on public.app_payment_environment to service_role;

alter table public.app_connected_accounts
  add column eligible_debit_card_exists boolean not null default false,
  add column payout_card jsonb;
alter table public.app_purchases
  add column payment_interface text not null default 'checkout' check (payment_interface in ('checkout', 'native'));
-- A charge.refunded event can describe several real refunds.
alter table public.app_refunds drop constraint if exists app_refunds_provider_event_id_key;
create index app_refunds_provider_event_idx on public.app_refunds(provider_event_id);
alter table public.app_payment_disputes add column provider_transfer_reversal_id text;
alter table public.app_payouts
  add column external_account_id text,
  add column card_snapshot jsonb,
  add column fee_amount integer check (fee_amount >= 0),
  add column net_amount integer check (net_amount >= 0),
  add column failed_at timestamptz;
create index app_purchases_native_expiry_idx on public.app_purchases(hold_expires_at)
  where status = 'payment_pending' and payment_interface = 'native';

create table public.app_payout_requests (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references auth.users(id),
  connected_account_id uuid not null references public.app_connected_accounts(id),
  provider_account_id text not null,
  external_account_id text not null check (external_account_id like 'card_%'),
  card_snapshot jsonb not null,
  request_key text not null,
  amount integer not null check (amount > 0),
  fee integer not null check (fee >= 0),
  net_amount integer not null check (net_amount > 0 and net_amount + fee = amount),
  currency text not null check (currency = 'USD'),
  fee_policy text not null,
  status text not null default 'quoted' check (status in ('quoted', 'submitting', 'submitted', 'failed')),
  provider_payout_id text unique,
  expires_at timestamptz not null default now() + interval '5 minutes',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (creator_id, request_key)
);
create index app_payout_requests_creator_idx on public.app_payout_requests(creator_id, created_at desc);
create index app_payout_requests_connected_idx on public.app_payout_requests(connected_account_id);
alter table public.app_payout_requests enable row level security;
revoke all on public.app_payout_requests from anon, authenticated;
grant all on public.app_payout_requests to service_role;

create table public.app_payment_reconciliation_issues (
  provider_reference text primary key,
  purchase_id uuid not null references public.app_purchases(id),
  creator_id uuid not null references auth.users(id),
  reason text not null,
  resolved boolean not null default false,
  updated_at timestamptz not null default now()
);
create index app_payment_reconciliation_creator_idx
  on public.app_payment_reconciliation_issues(creator_id) where not resolved;
create index app_payment_reconciliation_purchase_idx on public.app_payment_reconciliation_issues(purchase_id);
alter table public.app_payment_reconciliation_issues enable row level security;
revoke all on public.app_payment_reconciliation_issues from anon, authenticated;
grant all on public.app_payment_reconciliation_issues to service_role;

create or replace function public.captro_begin_marketplace_purchase_v2(
  p_buyer_id uuid,
  p_buyer_app_user_id text,
  p_purchasable_id uuid,
  p_price_id uuid,
  p_quantity integer,
  p_idempotency_key text,
  p_selection jsonb default '{}'::jsonb,
  p_service_fee_amount integer default 0,
  p_tax_amount integer default 0,
  p_creator_fee_amount integer default 0,
  p_payment_interface text default 'native'
)
returns public.app_purchases
language plpgsql
set search_path = public
as $$
declare
  purchasable_row public.app_purchasables%rowtype;
  price_row public.app_prices%rowtype;
  purchase_row public.app_purchases%rowtype;
  connected_row public.app_connected_accounts%rowtype;
  next_status text;
  v_booking_slot_id uuid;
  v_item_amount integer;
begin
  if p_payment_interface not in ('checkout', 'native') or p_creator_fee_amount < 0 then
    raise exception 'CAPTRO_PURCHASE_INPUT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_buyer_id::text || ':' || p_idempotency_key, 0));
  perform public.captro_release_expired_purchase_holds();
  if p_quantity < 1 or p_quantity > 20 or length(trim(p_idempotency_key)) < 8
     or p_service_fee_amount < 0 or p_tax_amount < 0 then
    raise exception 'CAPTRO_PURCHASE_INPUT_INVALID';
  end if;
  select * into purchase_row from public.app_purchases
    where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then
    if purchase_row.purchasable_id <> p_purchasable_id or purchase_row.price_id <> p_price_id
       or purchase_row.quantity <> p_quantity or purchase_row.selection <> coalesce(p_selection, '{}'::jsonb) then
      raise exception 'CAPTRO_IDEMPOTENCY_CONFLICT';
    end if;
    return purchase_row;
  end if;

  select * into purchasable_row from public.app_purchasables where id = p_purchasable_id for update;
  if not found or purchasable_row.status <> 'active' then raise exception 'CAPTRO_ITEM_UNAVAILABLE'; end if;
  if purchasable_row.expires_at is not null and purchasable_row.expires_at <= now() then
    update public.app_purchasables set status = 'expired', updated_at = now() where id = purchasable_row.id;
    raise exception 'CAPTRO_ITEM_EXPIRED';
  end if;
  if purchasable_row.creator_id = p_buyer_id then raise exception 'CAPTRO_CREATOR_CANNOT_PURCHASE'; end if;

  if purchasable_row.fulfillment_type in ('membership', 'group_access', 'attendance') then
    select * into purchase_row from public.app_purchases
      where buyer_id = p_buyer_id and purchasable_id = p_purchasable_id
        and status in ('approval_pending', 'payment_pending', 'confirmed', 'partially_refunded', 'disputed')
      order by created_at desc limit 1;
    if found then return purchase_row; end if;
  end if;

  select * into price_row from public.app_prices
    where id = p_price_id and purchasable_id = p_purchasable_id and active = true for update;
  if not found then raise exception 'CAPTRO_PRICE_UNAVAILABLE'; end if;
  if price_row.billing_period <> 'one_time' then raise exception 'CAPTRO_SUBSCRIPTIONS_NOT_AVAILABLE'; end if;
  v_item_amount := price_row.unit_amount * p_quantity;

  if p_creator_fee_amount > v_item_amount then raise exception 'CAPTRO_FEE_CONFIGURATION_INVALID'; end if;
  if v_item_amount > 0 then
    select * into connected_row from public.app_connected_accounts
      where user_id = purchasable_row.creator_id and status = 'ready'
        and charges_enabled = true and payouts_enabled = true and details_submitted = true
        and eligible_debit_card_exists = true and jsonb_array_length(requirements_currently_due) = 0 for update;
    if not found then raise exception 'CAPTRO_PAYOUTS_NOT_READY'; end if;
  end if;

  if purchasable_row.capacity is not null and purchasable_row.quantity_committed + p_quantity > purchasable_row.capacity then
    raise exception 'CAPTRO_CAPACITY_REACHED';
  end if;
  if price_row.capacity is not null and price_row.quantity_committed + p_quantity > price_row.capacity then
    raise exception 'CAPTRO_TIER_SOLD_OUT';
  end if;

  next_status := case when purchasable_row.approval_required then 'approval_pending'
    when v_item_amount = 0 then 'confirmed' else 'payment_pending' end;

  if next_status <> 'approval_pending' then
    update public.app_purchasables set quantity_committed = quantity_committed + p_quantity, updated_at = now()
      where id = purchasable_row.id;
    update public.app_prices set quantity_committed = quantity_committed + p_quantity, updated_at = now()
      where id = price_row.id;
    if purchasable_row.fulfillment_type = 'reservation' then
      v_booking_slot_id := public.captro_reserve_booking_slot(
        purchasable_row.id,
        nullif(p_selection->>'startsAt', '')::timestamptz,
        nullif(p_selection->>'endsAt', '')::timestamptz,
        p_quantity,
        coalesce(price_row.capacity, 1)
      );
    end if;
  end if;

  insert into public.app_purchases (
    buyer_id, buyer_app_user_id, creator_id, post_id, purchasable_id, price_id, booking_slot_id,
    content_type, fulfillment_type, item_title, price_label, quantity, unit_amount,
    item_amount, service_fee_amount, creator_amount, platform_fee_amount, processing_amount,
    fee_amount, tax_amount, total_amount, currency, status, idempotency_key, selection,
    connected_account_id, stripe_destination_account_id, hold_expires_at, confirmed_at, payment_interface
  ) values (
    p_buyer_id, p_buyer_app_user_id, purchasable_row.creator_id, purchasable_row.post_id,
    purchasable_row.id, price_row.id, v_booking_slot_id, purchasable_row.content_type, purchasable_row.fulfillment_type,
    purchasable_row.title, price_row.label, p_quantity, price_row.unit_amount,
    v_item_amount, case when v_item_amount > 0 then p_service_fee_amount else 0 end,
    v_item_amount - p_creator_fee_amount, case when v_item_amount > 0 then p_service_fee_amount + p_creator_fee_amount else 0 end, 0,
    0, case when v_item_amount > 0 then p_tax_amount else 0 end,
    v_item_amount + case when v_item_amount > 0 then p_service_fee_amount + p_tax_amount else 0 end,
    price_row.currency, next_status, trim(p_idempotency_key), coalesce(p_selection, '{}'::jsonb),
    connected_row.id, connected_row.provider_account_id,
    case when next_status = 'payment_pending' then now() + interval '35 minutes' else null end,
    case when next_status = 'confirmed' then now() else null end, p_payment_interface
  ) returning * into purchase_row;

  if next_status = 'confirmed' then perform public.captro_create_entitlement_for_purchase(purchase_row.id); end if;
  return purchase_row;
end;
$$;

create or replace function public.captro_confirm_marketplace_purchase(
  p_purchase_id uuid,
  p_provider_event_id text,
  p_provider_checkout_id text,
  p_provider_payment_id text,
  p_provider_charge_id text,
  p_provider_transfer_id text,
  p_amount integer,
  p_processing_amount integer,
  p_tax_amount integer,
  p_currency text,
  p_available_at timestamptz,
  p_payload_digest text
)
returns public.app_purchases
language plpgsql
set search_path = public
as $$
declare
  purchase_row public.app_purchases%rowtype;
  payment_row public.app_payments%rowtype;
  earning_status text;
begin
  select * into purchase_row from public.app_purchases where id = p_purchase_id for update;
  if not found then raise exception 'CAPTRO_PURCHASE_NOT_FOUND'; end if;
  if purchase_row.confirmed_at is not null then
    if purchase_row.provider_payment_id is distinct from p_provider_payment_id
       or p_amount <> purchase_row.total_amount or upper(p_currency) <> purchase_row.currency then
      raise exception 'CAPTRO_PAYMENT_AMOUNT_MISMATCH';
    end if;
    return purchase_row;
  end if;
  if purchase_row.status <> 'payment_pending' then raise exception 'CAPTRO_PURCHASE_NOT_PAYABLE'; end if;
  if length(trim(coalesce(p_provider_event_id, ''))) < 3
     or length(trim(coalesce(p_provider_payment_id, ''))) < 3 then
    raise exception 'CAPTRO_PAYMENT_PROVIDER_REFERENCE_INVALID';
  end if;
  if purchase_row.payment_interface = 'native' and purchase_row.provider_payment_id is distinct from p_provider_payment_id then
    raise exception 'CAPTRO_PAYMENT_PROVIDER_REFERENCE_INVALID';
  end if;
  if purchase_row.payment_interface <> 'native' and purchase_row.provider_checkout_id is distinct from p_provider_checkout_id then
    raise exception 'CAPTRO_PAYMENT_PROVIDER_REFERENCE_INVALID';
  end if;
  if p_processing_amount < 0 or p_tax_amount < 0
     or p_amount <> purchase_row.total_amount
     or p_tax_amount <> purchase_row.tax_amount
     or upper(p_currency) <> purchase_row.currency then
    raise exception 'CAPTRO_PAYMENT_AMOUNT_MISMATCH';
  end if;
  if purchase_row.creator_amount > 0 and purchase_row.connected_account_id is null then
    raise exception 'CAPTRO_PAYOUTS_NOT_READY';
  end if;

  insert into public.app_payments (
    purchase_id, provider, provider_event_id, provider_payment_id, provider_checkout_id,
    status, amount, fee_amount, tax_amount, currency, payload_digest
  ) values (
    purchase_row.id, 'stripe', p_provider_event_id, p_provider_payment_id, p_provider_checkout_id,
    'confirmed', p_amount, greatest(0, p_processing_amount), greatest(0, p_tax_amount), upper(p_currency), p_payload_digest
  ) on conflict (provider, provider_event_id) where provider_event_id is not null do nothing
  returning * into payment_row;
  if payment_row.id is null then
    select * into payment_row from public.app_payments
      where provider = 'stripe' and provider_event_id = p_provider_event_id limit 1;
  end if;
  if payment_row.id is null or payment_row.purchase_id <> purchase_row.id then
    raise exception 'CAPTRO_PAYMENT_EVENT_MISMATCH';
  end if;

  update public.app_purchases set status = 'confirmed', payment_provider = 'stripe',
    provider_checkout_id = p_provider_checkout_id, provider_payment_id = p_provider_payment_id,
    provider_charge_id = p_provider_charge_id, provider_transfer_id = p_provider_transfer_id,
    fee_amount = greatest(0, p_processing_amount), processing_amount = greatest(0, p_processing_amount),
    tax_amount = greatest(0, p_tax_amount), confirmed_at = now(), hold_expires_at = null,
    updated_at = now()
  where id = purchase_row.id returning * into purchase_row;

  earning_status := case when p_available_at is not null and p_available_at <= now() then 'available' else 'pending' end;
  insert into public.app_creator_earnings (
    creator_id, buyer_id, purchase_id, payment_id, connected_account_id, post_id, purchasable_id,
    content_type, currency, item_amount, creator_amount, platform_fee, processing_amount,
    tax_amount, buyer_total, status, provider_payment_id, provider_charge_id, provider_transfer_id, available_at
  ) values (
    purchase_row.creator_id, purchase_row.buyer_id, purchase_row.id, payment_row.id,
    purchase_row.connected_account_id, purchase_row.post_id, purchase_row.purchasable_id,
    purchase_row.content_type, purchase_row.currency, purchase_row.item_amount, purchase_row.creator_amount,
    purchase_row.platform_fee_amount, greatest(0, p_processing_amount), purchase_row.tax_amount,
    purchase_row.total_amount, earning_status, p_provider_payment_id, p_provider_charge_id,
    p_provider_transfer_id, p_available_at
  ) on conflict (purchase_id) do update set
    payment_id = excluded.payment_id,
    processing_amount = excluded.processing_amount,
    provider_charge_id = excluded.provider_charge_id,
    provider_transfer_id = excluded.provider_transfer_id,
    available_at = excluded.available_at,
    status = case when app_creator_earnings.status in ('refunded', 'partially_refunded', 'disputed', 'reversed')
      then app_creator_earnings.status else excluded.status end,
    updated_at = now();

  insert into public.app_platform_fees (purchase_id, payment_id, fee_type, currency, amount)
    values (purchase_row.id, payment_row.id, 'service', purchase_row.currency, purchase_row.platform_fee_amount)
    on conflict (purchase_id, fee_type) do update set amount = excluded.amount, payment_id = excluded.payment_id, updated_at = now();
  insert into public.app_platform_fees (purchase_id, payment_id, fee_type, currency, amount)
    values (purchase_row.id, payment_row.id, 'processing', purchase_row.currency, greatest(0, p_processing_amount))
    on conflict (purchase_id, fee_type) do update set amount = excluded.amount, payment_id = excluded.payment_id, updated_at = now();

  perform public.captro_create_entitlement_for_purchase(purchase_row.id);
  return purchase_row;
end;
$$;

create or replace function public.captro_record_marketplace_refund(
  p_provider_payment_id text,
  p_provider_refund_id text,
  p_refund_amount integer,
  p_creator_reversal_amount integer,
  p_service_fee_refund_amount integer,
  p_provider_event_id text,
  p_status text,
  p_reason text,
  p_payload_digest text
)
returns public.app_purchases
language plpgsql
set search_path = public
as $$
declare
  purchase_row public.app_purchases%rowtype;
  entitlement_row public.app_entitlements%rowtype;
  total_refunded integer;
  total_creator_reversed integer;
  total_service_refunded integer;
  next_status text;
begin
  select * into purchase_row from public.app_purchases
    where provider_payment_id = p_provider_payment_id for update;
  if not found then raise exception 'CAPTRO_PURCHASE_NOT_FOUND'; end if;
  if p_refund_amount <= 0
     or p_creator_reversal_amount < 0
     or p_service_fee_refund_amount < 0
     or p_creator_reversal_amount + p_service_fee_refund_amount > p_refund_amount
     or p_status not in ('pending', 'succeeded', 'failed', 'cancelled') then
    raise exception 'CAPTRO_REFUND_INPUT_INVALID';
  end if;

  insert into public.app_refunds (
    purchase_id, creator_id, buyer_id, provider_refund_id, provider_event_id,
    provider_payment_id, currency, amount, creator_reversal_amount,
    service_fee_refund_amount, status, reason, payload_digest
  ) values (
    purchase_row.id, purchase_row.creator_id, purchase_row.buyer_id, p_provider_refund_id,
    p_provider_event_id, p_provider_payment_id, purchase_row.currency, p_refund_amount,
    greatest(0, p_creator_reversal_amount), greatest(0, p_service_fee_refund_amount),
    p_status, p_reason, p_payload_digest
  ) on conflict (provider_refund_id) do update set
    provider_event_id = coalesce(excluded.provider_event_id, app_refunds.provider_event_id),
    status = case when app_refunds.status = 'succeeded' then app_refunds.status else excluded.status end,
    creator_reversal_amount = greatest(app_refunds.creator_reversal_amount, excluded.creator_reversal_amount),
    service_fee_refund_amount = greatest(app_refunds.service_fee_refund_amount, excluded.service_fee_refund_amount),
    reason = coalesce(excluded.reason, app_refunds.reason),
    payload_digest = excluded.payload_digest,
    updated_at = now();

  if p_status <> 'succeeded' then return purchase_row; end if;

  select coalesce(sum(amount), 0), coalesce(sum(creator_reversal_amount), 0),
         coalesce(sum(service_fee_refund_amount), 0)
    into total_refunded, total_creator_reversed, total_service_refunded
    from public.app_refunds where purchase_id = purchase_row.id and status = 'succeeded';
  total_refunded := least(total_refunded, purchase_row.total_amount);
  total_creator_reversed := least(total_creator_reversed, purchase_row.creator_amount);
  total_service_refunded := least(total_service_refunded, purchase_row.service_fee_amount);
  next_status := case when total_refunded >= purchase_row.total_amount then 'refunded' else 'partially_refunded' end;

  insert into public.app_payments (
    purchase_id, provider, provider_event_id, provider_payment_id, provider_checkout_id,
    status, amount, currency, payload_digest
  ) values (
    purchase_row.id, 'stripe', p_provider_event_id, p_provider_payment_id,
    purchase_row.provider_checkout_id, next_status, p_refund_amount, purchase_row.currency, p_payload_digest
  ) on conflict (provider, provider_event_id) where provider_event_id is not null do nothing;

  update public.app_creator_earnings set
    refunded_amount = total_creator_reversed,
    status = case when next_status = 'refunded' then 'refunded' else 'partially_refunded' end,
    updated_at = now()
    where purchase_id = purchase_row.id;
  update public.app_platform_fees set refunded_amount = least(amount, total_service_refunded), updated_at = now()
    where purchase_id = purchase_row.id and fee_type = 'service';

  if next_status = 'refunded' and purchase_row.status <> 'refunded' then
    update public.app_purchasables set quantity_committed = greatest(0, quantity_committed - purchase_row.quantity), updated_at = now()
      where id = purchase_row.purchasable_id;
    update public.app_prices set quantity_committed = greatest(0, quantity_committed - purchase_row.quantity), updated_at = now()
      where id = purchase_row.price_id;
    update public.app_booking_slots set quantity_committed = greatest(0, quantity_committed - purchase_row.quantity), updated_at = now()
      where id = purchase_row.booking_slot_id;
    update public.app_entitlements set status = 'refunded', updated_at = now()
      where purchase_id = purchase_row.id returning * into entitlement_row;
    if entitlement_row.id is not null then
      update public.app_commerce_tickets set status = 'refunded', updated_at = now() where entitlement_id = entitlement_row.id;
      update public.app_commerce_memberships set status = 'refunded', updated_at = now() where entitlement_id = entitlement_row.id;
      update public.app_commerce_orders set status = 'refunded', updated_at = now() where entitlement_id = entitlement_row.id;
      update public.app_commerce_bookings set status = 'refunded', updated_at = now() where entitlement_id = entitlement_row.id;
      update public.app_commerce_redemptions set status = 'refunded', updated_at = now() where entitlement_id = entitlement_row.id;
      update public.app_commerce_attendance set status = 'refunded', updated_at = now() where entitlement_id = entitlement_row.id;
      if entitlement_row.kind in ('membership', 'group_access') then
        delete from public.app_group_chat_members
        where group_id = (
          select private_config->>'group_chat_id' from public.app_purchasables where id = purchase_row.purchasable_id
        ) and user_id = purchase_row.buyer_app_user_id;
      end if;
      insert into public.app_commerce_access_events (entitlement_id, event_type, metadata)
        values (entitlement_row.id, 'refunded', jsonb_build_object('amount', total_refunded));
    end if;
  end if;
  update public.app_purchases set status = next_status, updated_at = now()
    where id = purchase_row.id returning * into purchase_row;
  return purchase_row;
end;
$$;

create or replace function public.captro_release_expired_purchase_holds()
returns integer
language plpgsql
set search_path = public
as $$
declare
  item record;
  released integer := 0;
begin
  for item in
    select id, purchasable_id, price_id, booking_slot_id, quantity
    from public.app_purchases
    where status = 'payment_pending' and hold_expires_at < now()
      and payment_interface <> 'native'
    for update skip locked
  loop
    update public.app_purchases set status = 'expired', updated_at = now() where id = item.id;
    update public.app_purchasables set quantity_committed = greatest(0, quantity_committed - item.quantity), updated_at = now()
      where id = item.purchasable_id;
    update public.app_prices set quantity_committed = greatest(0, quantity_committed - item.quantity), updated_at = now()
      where id = item.price_id;
    update public.app_booking_slots set quantity_committed = greatest(0, quantity_committed - item.quantity), updated_at = now()
      where id = item.booking_slot_id;
    released := released + 1;
  end loop;
  return released;
end;
$$;

revoke all on function public.captro_begin_marketplace_purchase_v2(uuid,text,uuid,uuid,integer,text,jsonb,integer,integer,integer,text) from public,anon,authenticated;
grant execute on function public.captro_begin_marketplace_purchase_v2(uuid,text,uuid,uuid,integer,text,jsonb,integer,integer,integer,text) to service_role;
