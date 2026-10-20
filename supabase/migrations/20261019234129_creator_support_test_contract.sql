-- REVIEW ONLY. No production activation. Reuses purchases/payments/earnings and
-- their append-only ledger. No synthetic post, inventory, entitlement or account.
begin;
-- Existing financial projections, not another ledger or an entitlement category.
create or replace function public.captro_finance_category(kind text) returns text
language sql immutable set search_path=public as $$
 select case when kind='creator_support' then 'creator_support'
 when kind in ('event','party','ticket','access_pass') then 'event'
 when kind in ('club','meetup','deal') then kind when kind in ('group','group_access') then 'group_access'
 when kind in ('offer','booking','reservation','local_offer') then 'local_offer' else 'unassigned' end;
$$;
alter table public.app_purchases alter column post_id drop not null,
  alter column purchasable_id drop not null;
alter table public.app_purchases add constraint captro_support_snapshot check (
  (content_type <> 'creator_support' and post_id is not null and purchasable_id is not null)
  or (content_type = 'creator_support' and post_id is null and purchasable_id is null
    and price_id is null and booking_slot_id is null and fulfillment_type = 'none'
    and buyer_id <> creator_id and currency = 'USD' and quantity = 1
    and unit_amount between 200 and 20000 and total_amount = unit_amount
    and item_amount = unit_amount and service_fee_amount = 0
    and platform_fee_amount = 0 and tax_amount = 0
    and settlement_model = 'deferred' and payment_interface = 'checkout'
    and stripe_mode = 'test'));
alter table public.app_creator_earnings alter column post_id drop not null,
  alter column purchasable_id drop not null;
alter table public.app_creator_earnings add constraint captro_support_earning check (
  (content_type <> 'creator_support' and post_id is not null and purchasable_id is not null)
  or (content_type = 'creator_support' and post_id is null and purchasable_id is null
    and currency = 'USD' and platform_fee = 0 and tax_amount = 0));

-- Explicit server-managed enrollment; existing Connect approval is not approval
-- for a new business model. No client or admin-console mutation is introduced.
create table public.app_creator_support_enrollments (
  creator_id uuid primary key references auth.users(id) on delete cascade,
  enabled_for_test boolean not null default false,
  reviewed_by text not null,
  reviewed_at timestamptz not null default now()
);
create table public.app_creator_support_handoffs (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete cascade,
  buyer_app_user_id text not null,
  creator_id uuid not null references auth.users(id) on delete cascade,
  creator_app_user_id text not null,
  request_key uuid not null,
  token_hash text not null unique check(token_hash ~ '^[0-9a-f]{64}$'),
  purchase_id uuid unique references public.app_purchases(id) on delete restrict,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '2 hours',
  unique(buyer_id,request_key),
  check(buyer_id <> creator_id),
  check(expires_at <= created_at + interval '2 hours')
);
alter table public.app_creator_support_enrollments enable row level security;
alter table public.app_creator_support_handoffs enable row level security;
revoke all on public.app_creator_support_enrollments,public.app_creator_support_handoffs from public,anon,authenticated;
grant select,insert,update on public.app_creator_support_enrollments,public.app_creator_support_handoffs to service_role;

-- Preserve the original commerce implementation behind narrow dispatchers.
alter function public.captro_assert_purchase_available(public.app_purchases)
  rename to captro_assert_commerce_purchase_available;
create function public.captro_assert_purchase_available(p_purchase public.app_purchases)
returns void language plpgsql set search_path=public as $$
begin
  if p_purchase.content_type <> 'creator_support' then
    perform public.captro_assert_commerce_purchase_available(p_purchase); return;
  end if;
  if not exists(select 1 from public.app_payment_environment where id and stripe_mode='test')
    or not exists(select 1 from public.app_creator_support_enrollments where creator_id=p_purchase.creator_id and enabled_for_test)
    or not exists(select 1 from public.app_connected_accounts where id=p_purchase.connected_account_id
      and user_id=p_purchase.creator_id and provider_account_id=p_purchase.stripe_destination_account_id
      and stripe_mode='test' and status='ready' and transfers_enabled and payouts_enabled
      and payout_schedule='manual') then raise exception 'CAPTRO_SUPPORT_UNAVAILABLE'; end if;
end $$;
revoke all on function public.captro_assert_purchase_available(public.app_purchases) from public,anon,authenticated;
grant execute on function public.captro_assert_purchase_available(public.app_purchases) to service_role;

-- Existing date trigger remains unchanged for every ordinary purchase.
alter trigger captro_guard_new_purchase_dates on public.app_purchases rename to captro_guard_commerce_purchase_dates;
drop trigger captro_guard_commerce_purchase_dates on public.app_purchases;
create trigger captro_guard_new_purchase_dates before insert on public.app_purchases
  for each row when (new.content_type <> 'creator_support') execute function public.captro_guard_new_purchase_dates();

alter function public.captro_create_entitlement_for_purchase(uuid)
  rename to captro_create_commerce_entitlement_for_purchase;
create function public.captro_create_entitlement_for_purchase(p_purchase_id uuid)
returns uuid language plpgsql set search_path=public as $$
declare p public.app_purchases%rowtype;
begin
  select * into p from public.app_purchases where id=p_purchase_id for update;
  if not found or p.status<>'confirmed' then raise exception 'CAPTRO_PURCHASE_NOT_CONFIRMED'; end if;
  if p.content_type='creator_support' then
    -- Deliberately no access grant and no automatic transfer. Existing audited
    -- release approval, actual processing cost and settlement gates still apply.
    update app_purchases set fulfillment_completed_at=confirmed_at,
      fulfillment_completion_source='creator_support_no_entitlement' where id=p.id;
    return null;
  end if;
  return public.captro_create_commerce_entitlement_for_purchase(p_purchase_id);
end $$;
revoke all on function public.captro_create_entitlement_for_purchase(uuid) from public,anon,authenticated;
grant execute on function public.captro_create_entitlement_for_purchase(uuid) to service_role;

create function public.captro_issue_support_handoff(p_buyer_id uuid,p_buyer_app_user_id text,
  p_creator_id uuid,p_creator_app_user_id text,p_request_key uuid,p_token_hash text)
returns public.app_creator_support_handoffs language plpgsql set search_path=public as $$
declare h public.app_creator_support_handoffs%rowtype;
begin
  if p_buyer_id=p_creator_id or not exists(select 1 from app_payment_environment where id and stripe_mode='test')
    or not exists(select 1 from app_creator_support_enrollments where creator_id=p_creator_id and enabled_for_test)
    then raise exception 'CAPTRO_SUPPORT_UNAVAILABLE'; end if;
  insert into app_creator_support_handoffs(buyer_id,buyer_app_user_id,creator_id,creator_app_user_id,request_key,token_hash)
    values(p_buyer_id,p_buyer_app_user_id,p_creator_id,p_creator_app_user_id,p_request_key,p_token_hash)
    on conflict(buyer_id,request_key) do nothing;
  select * into h from app_creator_support_handoffs where buyer_id=p_buyer_id and request_key=p_request_key for update;
  if h.creator_id<>p_creator_id or h.token_hash<>p_token_hash or h.buyer_app_user_id<>p_buyer_app_user_id
    or h.creator_app_user_id<>p_creator_app_user_id then raise exception 'CAPTRO_IDEMPOTENCY_CONFLICT'; end if;
  if h.expires_at<=now() then raise exception 'CAPTRO_SUPPORT_LINK_EXPIRED'; end if;
  return h;
end $$;

create function public.captro_begin_creator_support(p_token_hash text,p_amount integer,p_connected_account_id uuid)
returns public.app_purchases language plpgsql set search_path=public as $$
declare h public.app_creator_support_handoffs%rowtype; a public.app_connected_accounts%rowtype; p public.app_purchases%rowtype;
begin
  select * into h from app_creator_support_handoffs where token_hash=p_token_hash for update;
  if not found or h.expires_at<=now() then raise exception 'CAPTRO_SUPPORT_LINK_EXPIRED'; end if;
  if p_amount is null or p_amount<200 or p_amount>20000 then raise exception 'CAPTRO_SUPPORT_AMOUNT_INVALID'; end if;
  if h.purchase_id is not null then
    select * into p from app_purchases where id=h.purchase_id;
    if p.total_amount<>p_amount or p.connected_account_id<>p_connected_account_id then raise exception 'CAPTRO_IDEMPOTENCY_CONFLICT'; end if;
    return p;
  end if;
  select * into a from app_connected_accounts where id=p_connected_account_id and user_id=h.creator_id for share;
  if not found then raise exception 'CAPTRO_SUPPORT_UNAVAILABLE'; end if;
  p.id:=gen_random_uuid(); p.buyer_id:=h.buyer_id; p.buyer_app_user_id:=h.buyer_app_user_id;
  p.creator_id:=h.creator_id; p.content_type:='creator_support'; p.connected_account_id:=a.id;
  p.stripe_destination_account_id:=a.provider_account_id;
  perform captro_assert_purchase_available(p);
  insert into app_purchases(id,buyer_id,buyer_app_user_id,creator_id,content_type,fulfillment_type,item_title,price_label,
    quantity,unit_amount,total_amount,currency,status,payment_provider,idempotency_key,hold_expires_at,
    item_amount,service_fee_amount,creator_amount,platform_fee_amount,processing_amount,tax_amount,
    connected_account_id,stripe_destination_account_id,payment_interface,settlement_model,stripe_mode)
  values(p.id,h.buyer_id,h.buyer_app_user_id,h.creator_id,'creator_support','none','Creator support','One-time support',
    1,p_amount,p_amount,'USD','payment_pending','stripe','creator-support:'||h.request_key,now()+interval '35 minutes',
    p_amount,0,p_amount,0,0,0,a.id,a.provider_account_id,'checkout','deferred','test') returning * into p;
  update app_creator_support_handoffs set purchase_id=p.id where id=h.id;
  return p;
end $$;
revoke all on function public.captro_issue_support_handoff(uuid,text,uuid,text,uuid,text),
  public.captro_begin_creator_support(text,integer,uuid) from public,anon,authenticated;
grant execute on function public.captro_issue_support_handoff(uuid,text,uuid,text,uuid,text),
  public.captro_begin_creator_support(text,integer,uuid) to service_role;
commit;
