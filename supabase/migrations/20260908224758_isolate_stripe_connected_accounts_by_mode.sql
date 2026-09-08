-- Stripe object IDs only exist in the test or live environment that created
-- them. Keep every reusable ID mode-scoped so changing an environment cannot
-- make a live request against an old sandbox object.
alter table public.app_connected_accounts
  add column if not exists stripe_mode text check (stripe_mode in ('test', 'live'));

alter table public.app_connected_accounts
  drop constraint if exists app_connected_accounts_user_id_key,
  drop constraint if exists app_connected_accounts_app_user_id_key;

create unique index if not exists app_connected_accounts_user_mode_uidx
  on public.app_connected_accounts (user_id, stripe_mode)
  where stripe_mode is not null;
create unique index if not exists app_connected_accounts_app_user_mode_uidx
  on public.app_connected_accounts (app_user_id, stripe_mode)
  where stripe_mode is not null;
create index if not exists app_connected_accounts_mode_status_idx
  on public.app_connected_accounts (stripe_mode, status, updated_at);

-- Legacy rows predate mode tracking and cannot be safely adopted into either
-- environment. They remain for audit history but are never eligible for a new
-- payment. The next payout setup creates a current-mode account.
update public.app_connected_accounts
set status = 'disabled',
    charges_enabled = false,
    transfers_enabled = false,
    payouts_enabled = false,
    eligible_debit_card_exists = false,
    disabled_reason = coalesce(disabled_reason, 'stripe_mode_unclassified'),
    updated_at = now()
where stripe_mode is null;

alter table public.app_purchasables
  add column if not exists stripe_product_mode text check (stripe_product_mode in ('test', 'live'));
alter table public.app_prices
  add column if not exists stripe_price_mode text check (stripe_price_mode in ('test', 'live'));

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
  current_stripe_mode text;
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
  select stripe_mode into current_stripe_mode
    from public.app_payment_environment where id = true;
  if current_stripe_mode is null or current_stripe_mode not in ('test', 'live') then
    raise exception 'STRIPE_DATABASE_MODE_MISMATCH';
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
      where user_id = purchasable_row.creator_id
        and stripe_mode = current_stripe_mode
        and status = 'ready'
        and transfers_enabled = true and payouts_enabled = true and details_submitted = true
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
