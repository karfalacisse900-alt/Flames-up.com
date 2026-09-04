-- Captro commerce is deliberately separate from app_posts. A post advertises an
-- experience or item; these private tables own money, inventory and access.

create table public.app_purchasables (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null unique references public.app_posts(id) on delete cascade,
  creator_id uuid not null references auth.users(id) on delete restrict,
  creator_app_user_id text not null,
  content_type text not null check (content_type in (
    'offer', 'deal', 'club', 'group', 'meetup', 'event', 'party',
    'ticket', 'access_pass', 'booking', 'reservation'
  )),
  fulfillment_type text not null check (fulfillment_type in (
    'order', 'ticket', 'membership', 'group_access', 'redemption',
    'attendance', 'reservation'
  )),
  payment_model text not null check (payment_model in ('free', 'paid')),
  commerce_class text not null default 'outside_app' check (commerce_class in ('outside_app', 'digital')),
  approval_required boolean not null default false,
  pass_required boolean not null default false,
  status text not null default 'active' check (status in ('draft', 'active', 'paused', 'sold_out', 'expired', 'cancelled')),
  title text not null,
  description text not null default '',
  location_name text,
  address text,
  city text,
  starts_at timestamptz,
  ends_at timestamptz,
  timezone text,
  capacity integer check (capacity is null or capacity > 0),
  quantity_committed integer not null default 0 check (quantity_committed >= 0),
  expires_at timestamptz,
  refund_policy text not null default '',
  visibility text not null default 'public' check (visibility in ('public', 'followers', 'friends', 'private')),
  audience text not null default 'anyone' check (audience in ('anyone', 'followers', 'friends', 'approval')),
  public_data jsonb not null default '{}'::jsonb,
  private_config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at),
  check (capacity is null or quantity_committed <= capacity)
);

create table public.app_prices (
  id uuid primary key default gen_random_uuid(),
  purchasable_id uuid not null references public.app_purchasables(id) on delete cascade,
  label text not null default 'General',
  unit_amount integer not null check (unit_amount >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  billing_period text not null default 'one_time' check (billing_period in ('one_time', 'month')),
  capacity integer check (capacity is null or capacity > 0),
  quantity_committed integer not null default 0 check (quantity_committed >= 0),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (capacity is null or quantity_committed <= capacity)
);

create table public.app_booking_slots (
  id uuid primary key default gen_random_uuid(),
  purchasable_id uuid not null references public.app_purchasables(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz,
  capacity integer not null default 1 check (capacity > 0),
  quantity_committed integer not null default 0 check (quantity_committed >= 0 and quantity_committed <= capacity),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (purchasable_id, starts_at),
  check (ends_at is null or ends_at > starts_at)
);

create table public.app_purchases (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete restrict,
  buyer_app_user_id text not null,
  creator_id uuid not null references auth.users(id) on delete restrict,
  post_id uuid not null references public.app_posts(id) on delete restrict,
  purchasable_id uuid not null references public.app_purchasables(id) on delete restrict,
  price_id uuid references public.app_prices(id) on delete restrict,
  booking_slot_id uuid references public.app_booking_slots(id) on delete restrict,
  content_type text not null,
  fulfillment_type text not null,
  item_title text not null,
  price_label text not null,
  quantity integer not null check (quantity > 0 and quantity <= 20),
  unit_amount integer not null check (unit_amount >= 0),
  fee_amount integer,
  tax_amount integer,
  total_amount integer not null check (total_amount >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  status text not null check (status in (
    'approval_pending', 'payment_pending', 'confirmed', 'rejected',
    'cancelled', 'expired', 'refunded', 'partially_refunded'
  )),
  payment_provider text,
  provider_checkout_id text,
  provider_payment_id text,
  idempotency_key text not null,
  selection jsonb not null default '{}'::jsonb,
  hold_expires_at timestamptz,
  approved_at timestamptz,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (buyer_id, idempotency_key),
  unique (provider_checkout_id)
);

create table public.app_payments (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.app_purchases(id) on delete restrict,
  provider text not null,
  provider_event_id text,
  provider_payment_id text,
  provider_checkout_id text,
  status text not null check (status in ('pending', 'confirmed', 'failed', 'refunded', 'partially_refunded')),
  amount integer not null check (amount >= 0),
  fee_amount integer,
  tax_amount integer,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  payload_digest text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index app_payments_provider_event_key
  on public.app_payments (provider, provider_event_id)
  where provider_event_id is not null;
create unique index app_payments_provider_payment_key
  on public.app_payments (provider, provider_payment_id)
  where provider_payment_id is not null and status = 'confirmed';

create table public.app_entitlements (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null unique references public.app_purchases(id) on delete restrict,
  holder_id uuid not null references auth.users(id) on delete restrict,
  holder_app_user_id text not null,
  post_id uuid not null references public.app_posts(id) on delete restrict,
  purchasable_id uuid not null references public.app_purchasables(id) on delete restrict,
  kind text not null check (kind in ('order', 'ticket', 'membership', 'group_access', 'redemption', 'attendance', 'reservation')),
  status text not null default 'active' check (status in ('active', 'used', 'expired', 'revoked', 'refunded')),
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_commerce_tickets (
  id uuid primary key default gen_random_uuid(),
  entitlement_id uuid not null unique references public.app_entitlements(id) on delete restrict,
  ticket_code text not null unique,
  tier text not null,
  token_version integer not null default 1 check (token_version > 0),
  status text not null default 'active' check (status in ('active', 'checked_in', 'expired', 'revoked', 'refunded')),
  checked_in_at timestamptz,
  checked_in_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_commerce_memberships (
  id uuid primary key default gen_random_uuid(),
  entitlement_id uuid not null unique references public.app_entitlements(id) on delete restrict,
  membership_type text not null check (membership_type in ('club', 'group')),
  status text not null default 'active' check (status in ('active', 'expired', 'revoked', 'refunded')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_commerce_orders (
  id uuid primary key default gen_random_uuid(),
  entitlement_id uuid not null unique references public.app_entitlements(id) on delete restrict,
  status text not null default 'placed' check (status in ('placed', 'accepted', 'ready', 'completed', 'cancelled', 'refunded')),
  fulfillment_method text check (fulfillment_method in ('pickup', 'delivery', 'service', 'digital_delivery')),
  selection jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_commerce_bookings (
  id uuid primary key default gen_random_uuid(),
  entitlement_id uuid not null unique references public.app_entitlements(id) on delete restrict,
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'confirmed' check (status in ('confirmed', 'completed', 'cancelled', 'refunded')),
  selection jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create table public.app_commerce_redemptions (
  id uuid primary key default gen_random_uuid(),
  entitlement_id uuid not null unique references public.app_entitlements(id) on delete restrict,
  redemption_code text not null unique,
  token_version integer not null default 1 check (token_version > 0),
  status text not null default 'active' check (status in ('active', 'used', 'expired', 'revoked', 'refunded')),
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_commerce_attendance (
  id uuid primary key default gen_random_uuid(),
  entitlement_id uuid not null unique references public.app_entitlements(id) on delete restrict,
  status text not null default 'going' check (status in ('going', 'attended', 'cancelled', 'refunded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_commerce_access_events (
  id uuid primary key default gen_random_uuid(),
  entitlement_id uuid not null references public.app_entitlements(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null check (event_type in ('issued', 'checked_in', 'redeemed', 'revoked', 'refunded', 'duplicate_attempt')),
  request_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index app_purchasables_creator_idx on public.app_purchasables (creator_id, created_at desc);
create index app_prices_purchasable_idx on public.app_prices (purchasable_id, sort_order, created_at);
create index app_booking_slots_purchasable_idx on public.app_booking_slots (purchasable_id, starts_at);
create index app_purchases_buyer_idx on public.app_purchases (buyer_id, created_at desc);
create index app_purchases_creator_idx on public.app_purchases (creator_id, created_at desc);
create index app_purchases_purchasable_status_idx on public.app_purchases (purchasable_id, status, created_at desc);
create index app_entitlements_holder_idx on public.app_entitlements (holder_id, created_at desc);
create index app_entitlements_creator_lookup_idx on public.app_entitlements (purchasable_id, status, created_at desc);

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

create or replace function public.captro_reserve_booking_slot(
  p_purchasable_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_quantity integer,
  p_capacity integer
)
returns uuid
language plpgsql
set search_path = public
as $$
declare slot_row public.app_booking_slots%rowtype;
begin
  if p_starts_at is null or p_starts_at <= now() then raise exception 'CAPTRO_BOOKING_TIME_INVALID'; end if;
  insert into public.app_booking_slots (purchasable_id, starts_at, ends_at, capacity)
  values (p_purchasable_id, p_starts_at, p_ends_at, greatest(1, coalesce(p_capacity, 1)))
  on conflict (purchasable_id, starts_at) do nothing;
  select * into slot_row from public.app_booking_slots
    where purchasable_id = p_purchasable_id and starts_at = p_starts_at for update;
  if not found or slot_row.quantity_committed + p_quantity > slot_row.capacity then
    raise exception 'CAPTRO_BOOKING_SLOT_UNAVAILABLE';
  end if;
  update public.app_booking_slots set quantity_committed = quantity_committed + p_quantity, updated_at = now()
    where id = slot_row.id returning * into slot_row;
  return slot_row.id;
end;
$$;

create or replace function public.captro_create_entitlement_for_purchase(p_purchase_id uuid)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  purchase_row public.app_purchases%rowtype;
  purchasable_row public.app_purchasables%rowtype;
  v_entitlement_id uuid;
  code_suffix text;
begin
  select * into purchase_row from public.app_purchases where id = p_purchase_id for update;
  if not found or purchase_row.status <> 'confirmed' then
    raise exception 'CAPTRO_PURCHASE_NOT_CONFIRMED';
  end if;

  select * into purchasable_row from public.app_purchasables where id = purchase_row.purchasable_id;
  insert into public.app_entitlements (
    purchase_id, holder_id, holder_app_user_id, post_id, purchasable_id, kind, starts_at, ends_at
  ) values (
    purchase_row.id, purchase_row.buyer_id, purchase_row.buyer_app_user_id, purchase_row.post_id,
    purchase_row.purchasable_id, purchase_row.fulfillment_type, purchasable_row.starts_at,
    coalesce(purchasable_row.ends_at, purchasable_row.expires_at)
  ) on conflict (purchase_id) do update set updated_at = now()
  returning id into v_entitlement_id;

  code_suffix := upper(substr(replace(v_entitlement_id::text, '-', ''), 1, 8));
  case purchase_row.fulfillment_type
    when 'ticket' then
      insert into public.app_commerce_tickets (entitlement_id, ticket_code, tier)
      values (v_entitlement_id, 'CAP-' || code_suffix, purchase_row.price_label)
      on conflict (entitlement_id) do nothing;
    when 'membership' then
      insert into public.app_commerce_memberships (entitlement_id, membership_type, ends_at)
      values (v_entitlement_id, 'club', purchasable_row.ends_at)
      on conflict (entitlement_id) do nothing;
    when 'group_access' then
      insert into public.app_commerce_memberships (entitlement_id, membership_type, ends_at)
      values (v_entitlement_id, 'group', purchasable_row.ends_at)
      on conflict (entitlement_id) do nothing;
    when 'redemption' then
      insert into public.app_commerce_redemptions (entitlement_id, redemption_code)
      values (v_entitlement_id, 'CAP-' || code_suffix)
      on conflict (entitlement_id) do nothing;
    when 'attendance' then
      insert into public.app_commerce_attendance (entitlement_id)
      values (v_entitlement_id) on conflict (entitlement_id) do nothing;
      if purchasable_row.pass_required then
        insert into public.app_commerce_tickets (entitlement_id, ticket_code, tier)
        values (v_entitlement_id, 'CAP-' || code_suffix, purchase_row.price_label)
        on conflict (entitlement_id) do nothing;
      end if;
    when 'order' then
      insert into public.app_commerce_orders (entitlement_id, fulfillment_method, selection)
      values (v_entitlement_id, nullif(purchase_row.selection->>'fulfillmentMethod', ''), purchase_row.selection)
      on conflict (entitlement_id) do nothing;
    when 'reservation' then
      insert into public.app_commerce_bookings (entitlement_id, starts_at, ends_at, selection)
      values (
        v_entitlement_id,
        nullif(purchase_row.selection->>'startsAt', '')::timestamptz,
        nullif(purchase_row.selection->>'endsAt', '')::timestamptz,
        purchase_row.selection
      ) on conflict (entitlement_id) do nothing;
    else
      raise exception 'CAPTRO_FULFILLMENT_UNSUPPORTED';
  end case;

  if purchase_row.fulfillment_type in ('membership', 'group_access')
     and nullif(purchasable_row.private_config->>'group_chat_id', '') is not null then
    insert into public.app_group_chat_members (
      id, group_id, user_id, role, legacy_created_at, created_at, updated_at
    ) values (
      gen_random_uuid()::text, purchasable_row.private_config->>'group_chat_id',
      purchase_row.buyer_app_user_id, 'member', now(), now(), now()
    ) on conflict (group_id, user_id) do update set updated_at = now();
  end if;

  insert into public.app_commerce_access_events (entitlement_id, event_type)
  select v_entitlement_id, 'issued'
  where not exists (
    select 1 from public.app_commerce_access_events
    where app_commerce_access_events.entitlement_id = v_entitlement_id
      and event_type = 'issued'
  );
  return v_entitlement_id;
end;
$$;

create or replace function public.captro_begin_purchase(
  p_buyer_id uuid,
  p_buyer_app_user_id text,
  p_purchasable_id uuid,
  p_price_id uuid,
  p_quantity integer,
  p_idempotency_key text,
  p_selection jsonb default '{}'::jsonb
)
returns public.app_purchases
language plpgsql
set search_path = public
as $$
declare
  purchasable_row public.app_purchasables%rowtype;
  price_row public.app_prices%rowtype;
  purchase_row public.app_purchases%rowtype;
  next_status text;
  v_booking_slot_id uuid;
begin
  perform public.captro_release_expired_purchase_holds();
  if p_quantity < 1 or p_quantity > 20 or length(trim(p_idempotency_key)) < 8 then
    raise exception 'CAPTRO_PURCHASE_INPUT_INVALID';
  end if;
  select * into purchase_row from public.app_purchases
    where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then return purchase_row; end if;

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
        and status in ('approval_pending', 'payment_pending', 'confirmed', 'partially_refunded')
      order by created_at desc limit 1;
    if found then return purchase_row; end if;
  end if;

  select * into price_row from public.app_prices
    where id = p_price_id and purchasable_id = p_purchasable_id and active = true for update;
  if not found then raise exception 'CAPTRO_PRICE_UNAVAILABLE'; end if;
  if price_row.billing_period <> 'one_time' then raise exception 'CAPTRO_SUBSCRIPTIONS_NOT_AVAILABLE'; end if;

  if purchasable_row.capacity is not null and purchasable_row.quantity_committed + p_quantity > purchasable_row.capacity then
    raise exception 'CAPTRO_CAPACITY_REACHED';
  end if;
  if price_row.capacity is not null and price_row.quantity_committed + p_quantity > price_row.capacity then
    raise exception 'CAPTRO_TIER_SOLD_OUT';
  end if;

  next_status := case when purchasable_row.approval_required then 'approval_pending'
    when price_row.unit_amount = 0 then 'confirmed' else 'payment_pending' end;

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
    fee_amount, tax_amount, total_amount, currency, status, idempotency_key, selection,
    hold_expires_at, confirmed_at
  ) values (
    p_buyer_id, p_buyer_app_user_id, purchasable_row.creator_id, purchasable_row.post_id,
    purchasable_row.id, price_row.id, v_booking_slot_id, purchasable_row.content_type, purchasable_row.fulfillment_type,
    purchasable_row.title, price_row.label, p_quantity, price_row.unit_amount, null, null,
    price_row.unit_amount * p_quantity, price_row.currency, next_status, trim(p_idempotency_key),
    coalesce(p_selection, '{}'::jsonb),
    case when next_status = 'payment_pending' then now() + interval '35 minutes' else null end,
    case when next_status = 'confirmed' then now() else null end
  ) returning * into purchase_row;

  if next_status = 'confirmed' then perform public.captro_create_entitlement_for_purchase(purchase_row.id); end if;
  return purchase_row;
end;
$$;

create or replace function public.captro_decide_purchase(
  p_purchase_id uuid,
  p_creator_id uuid,
  p_approved boolean
)
returns public.app_purchases
language plpgsql
set search_path = public
as $$
declare
  purchase_row public.app_purchases%rowtype;
  purchasable_row public.app_purchasables%rowtype;
  price_row public.app_prices%rowtype;
  v_booking_slot_id uuid;
begin
  select * into purchase_row from public.app_purchases where id = p_purchase_id for update;
  if not found or purchase_row.creator_id <> p_creator_id then raise exception 'CAPTRO_PURCHASE_NOT_FOUND'; end if;
  if purchase_row.status <> 'approval_pending' then return purchase_row; end if;
  if not p_approved then
    update public.app_purchases set status = 'rejected', updated_at = now() where id = purchase_row.id returning * into purchase_row;
    return purchase_row;
  end if;

  select * into purchasable_row from public.app_purchasables where id = purchase_row.purchasable_id for update;
  select * into price_row from public.app_prices where id = purchase_row.price_id for update;
  if purchasable_row.status <> 'active' then raise exception 'CAPTRO_ITEM_UNAVAILABLE'; end if;
  if purchasable_row.capacity is not null and purchasable_row.quantity_committed + purchase_row.quantity > purchasable_row.capacity then
    raise exception 'CAPTRO_CAPACITY_REACHED';
  end if;
  if price_row.capacity is not null and price_row.quantity_committed + purchase_row.quantity > price_row.capacity then
    raise exception 'CAPTRO_TIER_SOLD_OUT';
  end if;
  update public.app_purchasables set quantity_committed = quantity_committed + purchase_row.quantity, updated_at = now()
    where id = purchasable_row.id;
  update public.app_prices set quantity_committed = quantity_committed + purchase_row.quantity, updated_at = now()
    where id = price_row.id;
  if purchasable_row.fulfillment_type = 'reservation' then
    v_booking_slot_id := public.captro_reserve_booking_slot(
      purchasable_row.id,
      nullif(purchase_row.selection->>'startsAt', '')::timestamptz,
      nullif(purchase_row.selection->>'endsAt', '')::timestamptz,
      purchase_row.quantity,
      coalesce(price_row.capacity, 1)
    );
  end if;
  update public.app_purchases set
    status = case when unit_amount = 0 then 'confirmed' else 'payment_pending' end,
    approved_at = now(), confirmed_at = case when unit_amount = 0 then now() else null end,
    hold_expires_at = case when unit_amount > 0 then now() + interval '35 minutes' else null end,
    booking_slot_id = v_booking_slot_id,
    updated_at = now()
  where id = purchase_row.id returning * into purchase_row;
  if purchase_row.status = 'confirmed' then perform public.captro_create_entitlement_for_purchase(purchase_row.id); end if;
  return purchase_row;
end;
$$;

create or replace function public.captro_confirm_paid_purchase(
  p_purchase_id uuid,
  p_provider text,
  p_provider_event_id text,
  p_provider_checkout_id text,
  p_provider_payment_id text,
  p_amount integer,
  p_fee_amount integer,
  p_tax_amount integer,
  p_currency text,
  p_payload_digest text
)
returns public.app_purchases
language plpgsql
set search_path = public
as $$
declare purchase_row public.app_purchases%rowtype;
begin
  select * into purchase_row from public.app_purchases where id = p_purchase_id for update;
  if not found then raise exception 'CAPTRO_PURCHASE_NOT_FOUND'; end if;
  if purchase_row.status = 'confirmed' then return purchase_row; end if;
  if purchase_row.status <> 'payment_pending' then raise exception 'CAPTRO_PURCHASE_NOT_PAYABLE'; end if;
  if p_amount <> purchase_row.total_amount or upper(p_currency) <> purchase_row.currency then
    raise exception 'CAPTRO_PAYMENT_AMOUNT_MISMATCH';
  end if;
  insert into public.app_payments (
    purchase_id, provider, provider_event_id, provider_payment_id, provider_checkout_id,
    status, amount, fee_amount, tax_amount, currency, payload_digest
  ) values (
    purchase_row.id, p_provider, p_provider_event_id, p_provider_payment_id, p_provider_checkout_id,
    'confirmed', p_amount, p_fee_amount, p_tax_amount, upper(p_currency), p_payload_digest
  ) on conflict (provider, provider_event_id) where provider_event_id is not null do nothing;
  update public.app_purchases set status = 'confirmed', payment_provider = p_provider,
    provider_checkout_id = p_provider_checkout_id, provider_payment_id = p_provider_payment_id,
    fee_amount = p_fee_amount, tax_amount = p_tax_amount, confirmed_at = now(), hold_expires_at = null,
    updated_at = now()
  where id = purchase_row.id returning * into purchase_row;
  perform public.captro_create_entitlement_for_purchase(purchase_row.id);
  return purchase_row;
end;
$$;

create or replace function public.captro_cancel_purchase_hold(p_purchase_id uuid, p_checkout_id text)
returns public.app_purchases
language plpgsql
set search_path = public
as $$
declare purchase_row public.app_purchases%rowtype;
begin
  select * into purchase_row from public.app_purchases where id = p_purchase_id for update;
  if not found then raise exception 'CAPTRO_PURCHASE_NOT_FOUND'; end if;
  if purchase_row.status <> 'payment_pending' then return purchase_row; end if;
  if purchase_row.provider_checkout_id is not null and purchase_row.provider_checkout_id <> p_checkout_id then
    raise exception 'CAPTRO_CHECKOUT_MISMATCH';
  end if;
  update public.app_purchasables set quantity_committed = greatest(0, quantity_committed - purchase_row.quantity), updated_at = now()
    where id = purchase_row.purchasable_id;
  update public.app_prices set quantity_committed = greatest(0, quantity_committed - purchase_row.quantity), updated_at = now()
    where id = purchase_row.price_id;
  update public.app_booking_slots set quantity_committed = greatest(0, quantity_committed - purchase_row.quantity), updated_at = now()
    where id = purchase_row.booking_slot_id;
  update public.app_purchases set status = 'expired', hold_expires_at = null, updated_at = now()
    where id = purchase_row.id returning * into purchase_row;
  return purchase_row;
end;
$$;

create or replace function public.captro_refund_purchase(
  p_provider_payment_id text,
  p_refund_amount integer,
  p_provider_event_id text,
  p_payload_digest text
)
returns public.app_purchases
language plpgsql
set search_path = public
as $$
declare purchase_row public.app_purchases%rowtype;
declare entitlement_row public.app_entitlements%rowtype;
declare refund_status text;
begin
  select * into purchase_row from public.app_purchases
    where provider_payment_id = p_provider_payment_id for update;
  if not found then raise exception 'CAPTRO_PURCHASE_NOT_FOUND'; end if;
  if purchase_row.status in ('refunded', 'cancelled', 'expired') then return purchase_row; end if;
  refund_status := case when p_refund_amount >= purchase_row.total_amount then 'refunded' else 'partially_refunded' end;
  insert into public.app_payments (
    purchase_id, provider, provider_event_id, provider_payment_id, provider_checkout_id,
    status, amount, fee_amount, tax_amount, currency, payload_digest
  ) values (
    purchase_row.id, coalesce(purchase_row.payment_provider, 'stripe'), p_provider_event_id,
    p_provider_payment_id, purchase_row.provider_checkout_id, refund_status,
    greatest(0, p_refund_amount), null, null, purchase_row.currency, p_payload_digest
  ) on conflict (provider, provider_event_id) where provider_event_id is not null do nothing;
  update public.app_purchases set status = refund_status, updated_at = now()
    where id = purchase_row.id returning * into purchase_row;
  if refund_status = 'refunded' then
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
        values (entitlement_row.id, 'refunded', jsonb_build_object('amount', p_refund_amount));
    end if;
  end if;
  return purchase_row;
end;
$$;

create or replace function public.captro_consume_ticket(
  p_ticket_id uuid,
  p_creator_id uuid,
  p_token_version integer,
  p_request_id text
)
returns public.app_commerce_tickets
language plpgsql
set search_path = public
as $$
declare ticket_row public.app_commerce_tickets%rowtype;
declare entitlement_row public.app_entitlements%rowtype;
begin
  select * into ticket_row from public.app_commerce_tickets where id = p_ticket_id for update;
  if not found then raise exception 'CAPTRO_PASS_NOT_FOUND'; end if;
  select e.* into entitlement_row from public.app_entitlements e
    join public.app_purchasables p on p.id = e.purchasable_id
    where e.id = ticket_row.entitlement_id and p.creator_id = p_creator_id;
  if not found or ticket_row.token_version <> p_token_version then raise exception 'CAPTRO_PASS_INVALID'; end if;
  if ticket_row.status <> 'active' then
    insert into public.app_commerce_access_events (entitlement_id, actor_id, event_type, request_id)
      values (ticket_row.entitlement_id, p_creator_id, 'duplicate_attempt', p_request_id);
    raise exception 'CAPTRO_PASS_ALREADY_USED';
  end if;
  update public.app_commerce_tickets set status = 'checked_in', checked_in_at = now(), checked_in_by = p_creator_id,
    updated_at = now() where id = ticket_row.id returning * into ticket_row;
  update public.app_entitlements set status = 'used', updated_at = now() where id = ticket_row.entitlement_id;
  insert into public.app_commerce_access_events (entitlement_id, actor_id, event_type, request_id)
    values (ticket_row.entitlement_id, p_creator_id, 'checked_in', p_request_id);
  return ticket_row;
end;
$$;

create or replace function public.captro_consume_redemption(
  p_redemption_id uuid,
  p_creator_id uuid,
  p_token_version integer,
  p_request_id text
)
returns public.app_commerce_redemptions
language plpgsql
set search_path = public
as $$
declare pass_row public.app_commerce_redemptions%rowtype;
declare entitlement_row public.app_entitlements%rowtype;
begin
  select * into pass_row from public.app_commerce_redemptions where id = p_redemption_id for update;
  if not found then raise exception 'CAPTRO_PASS_NOT_FOUND'; end if;
  select e.* into entitlement_row from public.app_entitlements e
    join public.app_purchasables p on p.id = e.purchasable_id
    where e.id = pass_row.entitlement_id and p.creator_id = p_creator_id;
  if not found or pass_row.token_version <> p_token_version then raise exception 'CAPTRO_PASS_INVALID'; end if;
  if pass_row.status <> 'active' then
    insert into public.app_commerce_access_events (entitlement_id, actor_id, event_type, request_id)
      values (pass_row.entitlement_id, p_creator_id, 'duplicate_attempt', p_request_id);
    raise exception 'CAPTRO_PASS_ALREADY_USED';
  end if;
  update public.app_commerce_redemptions set status = 'used', redeemed_at = now(), redeemed_by = p_creator_id,
    updated_at = now() where id = pass_row.id returning * into pass_row;
  update public.app_entitlements set status = 'used', updated_at = now() where id = pass_row.entitlement_id;
  insert into public.app_commerce_access_events (entitlement_id, actor_id, event_type, request_id)
    values (pass_row.entitlement_id, p_creator_id, 'redeemed', p_request_id);
  return pass_row;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'app_purchasables', 'app_prices', 'app_booking_slots', 'app_purchases', 'app_payments', 'app_entitlements',
    'app_commerce_tickets', 'app_commerce_memberships', 'app_commerce_orders',
    'app_commerce_bookings', 'app_commerce_redemptions', 'app_commerce_attendance',
    'app_commerce_access_events'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end $$;

revoke all on function public.captro_release_expired_purchase_holds() from public, anon, authenticated;
revoke all on function public.captro_create_entitlement_for_purchase(uuid) from public, anon, authenticated;
revoke all on function public.captro_reserve_booking_slot(uuid, timestamptz, timestamptz, integer, integer) from public, anon, authenticated;
revoke all on function public.captro_begin_purchase(uuid, text, uuid, uuid, integer, text, jsonb) from public, anon, authenticated;
revoke all on function public.captro_decide_purchase(uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function public.captro_confirm_paid_purchase(uuid, text, text, text, text, integer, integer, integer, text, text) from public, anon, authenticated;
revoke all on function public.captro_cancel_purchase_hold(uuid, text) from public, anon, authenticated;
revoke all on function public.captro_refund_purchase(text, integer, text, text) from public, anon, authenticated;
revoke all on function public.captro_consume_ticket(uuid, uuid, integer, text) from public, anon, authenticated;
revoke all on function public.captro_consume_redemption(uuid, uuid, integer, text) from public, anon, authenticated;

grant execute on function public.captro_release_expired_purchase_holds() to service_role;
grant execute on function public.captro_create_entitlement_for_purchase(uuid) to service_role;
grant execute on function public.captro_reserve_booking_slot(uuid, timestamptz, timestamptz, integer, integer) to service_role;
grant execute on function public.captro_begin_purchase(uuid, text, uuid, uuid, integer, text, jsonb) to service_role;
grant execute on function public.captro_decide_purchase(uuid, uuid, boolean) to service_role;
grant execute on function public.captro_confirm_paid_purchase(uuid, text, text, text, text, integer, integer, integer, text, text) to service_role;
grant execute on function public.captro_cancel_purchase_hold(uuid, text) to service_role;
grant execute on function public.captro_refund_purchase(text, integer, text, text) to service_role;
grant execute on function public.captro_consume_ticket(uuid, uuid, integer, text) to service_role;
grant execute on function public.captro_consume_redemption(uuid, uuid, integer, text) to service_role;

comment on table public.app_purchasables is 'Commerce configuration linked one-to-one with a Captro post; app_posts never stores payment state.';
comment on table public.app_purchases is 'Immutable purchase snapshots. Entitlements are created only after free confirmation or provider-confirmed payment.';
comment on table public.app_entitlements is 'Backend-owned access resulting from a confirmed purchase.';
