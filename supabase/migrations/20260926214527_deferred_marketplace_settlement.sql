-- Platform payment confirmation is independent of seller onboarding and transfer.
alter table public.app_purchases
  add column settlement_model text not null default 'legacy_immediate' check (settlement_model in ('legacy_immediate','deferred')),
  add column stripe_mode text check (stripe_mode in ('test','live')),
  add column fulfillment_completed_at timestamptz,
  add column fulfillment_completion_source text,
  add column receipt_payment_method jsonb;
alter table public.app_creator_earnings
  alter column connected_account_id drop not null,
  add column processing_cost_known boolean not null default true,
  add column release_not_before timestamptz,
  add column ledger_revision integer not null default 0;
alter table public.app_creator_earnings drop constraint app_creator_earnings_status_check;
alter table public.app_creator_earnings add constraint app_creator_earnings_status_check
  check (status in ('pending','clearing','available','transferred','paid','partially_refunded','refunded','disputed','reversed'));

create table public.app_marketplace_ledger (
  id uuid primary key default gen_random_uuid(),
  entry_key text not null unique,
  order_id uuid references public.app_purchases(id),
  seller_id uuid not null references auth.users(id),
  event_type text not null,
  account text not null,
  amount bigint not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  stripe_object_id text,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
create index app_marketplace_ledger_seller_currency_idx on public.app_marketplace_ledger(seller_id,currency,account);
create index app_marketplace_ledger_order_idx on public.app_marketplace_ledger(order_id);
alter table public.app_marketplace_ledger enable row level security;
revoke all on public.app_marketplace_ledger from public,anon,authenticated;
grant select,insert on public.app_marketplace_ledger to service_role;
create function public.captro_immutable_ledger() returns trigger language plpgsql set search_path=public as $$
begin raise exception 'CAPTRO_LEDGER_IMMUTABLE'; end; $$;
create trigger app_marketplace_ledger_immutable before update or delete on public.app_marketplace_ledger
  for each row execute function public.captro_immutable_ledger();

create function public.captro_earning_bucket(p_status text, p_transfer text) returns text
language sql immutable set search_path=public as $$
 select case when p_status='disputed' then 'held'
   when p_status in ('refunded','reversed') then 'closed'
   when p_status='paid' then 'paid_out'
   when p_status='partially_refunded' then case when p_transfer is null then 'pending' else 'transferred' end
   else p_status end;
$$;
create function public.captro_append_earning_ledger() returns trigger language plpgsql set search_path=public as $$
declare old_amount bigint:=0; new_amount bigint; old_bucket text; new_bucket text; entry_type text;
begin
 new_amount:=greatest(0,new.creator_amount-new.refunded_amount);
 new_bucket:=public.captro_earning_bucket(new.status,new.provider_transfer_id);
 if new_bucket='closed' then new_amount:=0; end if;
 if tg_op='UPDATE' then
   if new.creator_id<>old.creator_id or new.purchase_id<>old.purchase_id or new.currency<>old.currency then raise exception 'CAPTRO_LEDGER_OWNER_IMMUTABLE'; end if;
   old_amount:=greatest(0,old.creator_amount-old.refunded_amount);
   old_bucket:=public.captro_earning_bucket(old.status,old.provider_transfer_id);
   if old_bucket='closed' then old_amount:=0; end if;
   new.ledger_revision:=old.ledger_revision;
   if old_amount=new_amount and old_bucket=new_bucket and new.processing_amount=old.processing_amount then return new; end if;
 end if;
 new.ledger_revision:=coalesce(new.ledger_revision,0)+1;
 entry_type:=case when tg_op='INSERT' then 'SELLER_PENDING' when new.status='refunded' or new.refunded_amount>old.refunded_amount then 'REFUND' when new.status='disputed' then 'DISPUTE' when new.status='transferred' then 'TRANSFER_CREATED' when new.status='available' then 'SELLER_RELEASED' else 'EARNING_STATE_CHANGED' end;
 if old_amount>0 then
   insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id)
   values(new.id||':'||new.ledger_revision||':debit',new.purchase_id,new.creator_id,entry_type,old_bucket,-old_amount,new.currency,new.provider_payment_id);
 end if;
 if new_amount>0 then
   insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id)
   values(new.id||':'||new.ledger_revision||':credit',new.purchase_id,new.creator_id,entry_type,new_bucket,new_amount,new.currency,coalesce(new.provider_transfer_id,new.provider_payment_id));
 end if;
 if tg_op='INSERT' then
   insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id) values
   (new.id||':payment',new.purchase_id,new.creator_id,'CUSTOMER_PAYMENT','gross',new.buyer_total,new.currency,new.provider_payment_id),
   (new.id||':platform_fee',new.purchase_id,new.creator_id,'CAPTRO_PLATFORM_FEE','platform_fee',new.platform_fee,new.currency,new.provider_payment_id),
   (new.id||':processing_fee',new.purchase_id,new.creator_id,'PROCESSING_FEE','processing_fee',new.processing_amount,new.currency,new.provider_charge_id);
 elsif new.processing_amount<>old.processing_amount then
   insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id)
   values(new.id||':'||new.ledger_revision||':processing',new.purchase_id,new.creator_id,'PROCESSING_FEE','processing_fee',new.processing_amount-old.processing_amount,new.currency,new.provider_charge_id);
 end if;
 return new;
end; $$;
create trigger app_creator_earnings_ledger before insert or update on public.app_creator_earnings
  for each row execute function public.captro_append_earning_ledger();
-- Opening balances preserve existing accounting; no existing Stripe money moves.
insert into public.app_marketplace_ledger(entry_key,order_id,seller_id,event_type,account,amount,currency,stripe_object_id)
select id||':opening',purchase_id,creator_id,'OPENING_BALANCE',public.captro_earning_bucket(status,provider_transfer_id),
 greatest(0,creator_amount-refunded_amount),currency,provider_payment_id from public.app_creator_earnings
where status not in ('refunded','reversed');
create function public.captro_ledger_balances(p_seller_id uuid) returns table(currency text,account text,amount bigint)
language sql stable set search_path=public as $$
 select l.currency,l.account,sum(l.amount)::bigint from public.app_marketplace_ledger l where l.seller_id=p_seller_id group by l.currency,l.account;
$$;
revoke all on function public.captro_ledger_balances(uuid) from public,anon,authenticated;
grant execute on function public.captro_ledger_balances(uuid) to service_role;
revoke all on function public.captro_immutable_ledger(),public.captro_append_earning_ledger(),public.captro_earning_bucket(text,text) from public,anon,authenticated;
grant execute on function public.captro_immutable_ledger(),public.captro_append_earning_ledger(),public.captro_earning_bucket(text,text) to service_role;

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
    connected_account_id, stripe_destination_account_id, hold_expires_at, confirmed_at, payment_interface, settlement_model, stripe_mode
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
    case when next_status = 'confirmed' then now() else null end, p_payment_interface, 'deferred', current_stripe_mode
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
  if p_processing_amount < -1 or p_tax_amount < 0
     or p_amount <> purchase_row.total_amount
     or p_tax_amount <> purchase_row.tax_amount
     or upper(p_currency) <> purchase_row.currency then
    raise exception 'CAPTRO_PAYMENT_AMOUNT_MISMATCH';
  end if;
  if purchase_row.settlement_model = 'deferred' and p_provider_transfer_id is not null then
    raise exception 'CAPTRO_PREMATURE_TRANSFER';
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
    creator_amount = case when settlement_model = 'deferred' then greatest(0, creator_amount - greatest(0,p_processing_amount)) else creator_amount end,
    tax_amount = greatest(0, p_tax_amount), confirmed_at = now(), hold_expires_at = null,
    updated_at = now()
  where id = purchase_row.id returning * into purchase_row;

  earning_status := case when purchase_row.settlement_model = 'deferred' then 'pending' when p_available_at is not null and p_available_at <= now() then 'available' else 'pending' end;
  insert into public.app_creator_earnings (
    creator_id, buyer_id, purchase_id, payment_id, connected_account_id, post_id, purchasable_id,
    content_type, currency, item_amount, creator_amount, platform_fee, processing_amount,
    tax_amount, buyer_total, status, provider_payment_id, provider_charge_id, provider_transfer_id, available_at, processing_cost_known
  ) values (
    purchase_row.creator_id, purchase_row.buyer_id, purchase_row.id, payment_row.id,
    purchase_row.connected_account_id, purchase_row.post_id, purchase_row.purchasable_id,
    purchase_row.content_type, purchase_row.currency, purchase_row.item_amount, purchase_row.creator_amount,
    purchase_row.platform_fee_amount, greatest(0, p_processing_amount), purchase_row.tax_amount,
    purchase_row.total_amount, earning_status, p_provider_payment_id, p_provider_charge_id,
    p_provider_transfer_id, p_available_at, p_processing_amount >= 0
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
