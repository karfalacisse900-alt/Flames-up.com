-- Extend the guarded Support contract to Stripe Live without enabling rollout.
-- Creator approvals default off; the Worker also requires an explicit mode-specific flag.
begin;

alter table public.app_creator_support_enrollments
  add column enabled_for_live boolean not null default false;
comment on column public.app_creator_support_enrollments.enabled_for_live is
  'Server-reviewed opt-in for Live creator support; defaults off and does not imply Stripe or storefront eligibility.';

alter table public.app_purchases drop constraint captro_support_snapshot;
alter table public.app_purchases add constraint captro_support_snapshot check (
  (content_type <> 'creator_support' and post_id is not null and purchasable_id is not null)
  or (content_type = 'creator_support' and post_id is null and purchasable_id is null
    and price_id is null and booking_slot_id is null and fulfillment_type = 'none'
    and buyer_id <> creator_id and currency = 'USD' and quantity = 1
    and unit_amount between 200 and 20000 and total_amount = unit_amount
    and item_amount = unit_amount and service_fee_amount = 0
    and platform_fee_amount = 0 and tax_amount = 0
    and settlement_model = 'deferred' and payment_interface = 'checkout'
    and stripe_mode in ('test','live')));

create or replace function public.captro_assert_purchase_available(p_purchase public.app_purchases)
returns void language plpgsql set search_path=public as $$
declare active_mode text;
begin
  if p_purchase.content_type <> 'creator_support' then
    perform public.captro_assert_commerce_purchase_available(p_purchase); return;
  end if;
  select stripe_mode into active_mode from public.app_payment_environment where id;
  if active_mode not in ('test','live') or p_purchase.stripe_mode is distinct from active_mode
    or not exists(select 1 from public.app_creator_support_enrollments e
      where e.creator_id=p_purchase.creator_id
        and ((active_mode='test' and e.enabled_for_test) or (active_mode='live' and e.enabled_for_live)))
    or not exists(select 1 from public.app_connected_accounts a
      where a.id=p_purchase.connected_account_id and a.user_id=p_purchase.creator_id
        and a.provider_account_id=p_purchase.stripe_destination_account_id and a.stripe_mode=active_mode
        and a.status='ready' and a.transfers_enabled and a.payouts_enabled and a.payout_schedule='manual')
    then raise exception 'CAPTRO_SUPPORT_UNAVAILABLE'; end if;
end $$;

create or replace function public.captro_issue_support_handoff(p_buyer_id uuid,p_buyer_app_user_id text,
  p_creator_id uuid,p_creator_app_user_id text,p_request_key uuid,p_token_hash text)
returns public.app_creator_support_handoffs language plpgsql set search_path=public as $$
declare h public.app_creator_support_handoffs%rowtype; active_mode text;
begin
  select stripe_mode into active_mode from app_payment_environment where id;
  if p_buyer_id=p_creator_id or active_mode not in ('test','live')
    or not exists(select 1 from app_creator_support_enrollments e where e.creator_id=p_creator_id
      and ((active_mode='test' and e.enabled_for_test) or (active_mode='live' and e.enabled_for_live)))
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

create or replace function public.captro_begin_creator_support(p_token_hash text,p_amount integer,p_connected_account_id uuid)
returns public.app_purchases language plpgsql set search_path=public as $$
declare h public.app_creator_support_handoffs%rowtype; a public.app_connected_accounts%rowtype;
  p public.app_purchases%rowtype; active_mode text;
begin
  select stripe_mode into active_mode from app_payment_environment where id;
  select * into h from app_creator_support_handoffs where token_hash=p_token_hash for update;
  if not found or h.expires_at<=now() then raise exception 'CAPTRO_SUPPORT_LINK_EXPIRED'; end if;
  if p_amount is null or p_amount<200 or p_amount>20000 then raise exception 'CAPTRO_SUPPORT_AMOUNT_INVALID'; end if;
  if active_mode not in ('test','live')
    or not exists(select 1 from app_creator_support_enrollments e where e.creator_id=h.creator_id
      and ((active_mode='test' and e.enabled_for_test) or (active_mode='live' and e.enabled_for_live)))
    then raise exception 'CAPTRO_SUPPORT_UNAVAILABLE'; end if;
  if h.purchase_id is not null then
    select * into p from app_purchases where id=h.purchase_id;
    if p.total_amount<>p_amount or p.connected_account_id<>p_connected_account_id or p.stripe_mode<>active_mode
      then raise exception 'CAPTRO_IDEMPOTENCY_CONFLICT'; end if;
    return p;
  end if;
  select * into a from app_connected_accounts where id=p_connected_account_id and user_id=h.creator_id
    and stripe_mode=active_mode for share;
  if not found then raise exception 'CAPTRO_SUPPORT_UNAVAILABLE'; end if;
  p.id:=gen_random_uuid(); p.buyer_id:=h.buyer_id; p.buyer_app_user_id:=h.buyer_app_user_id;
  p.creator_id:=h.creator_id; p.content_type:='creator_support'; p.connected_account_id:=a.id;
  p.stripe_destination_account_id:=a.provider_account_id; p.stripe_mode:=active_mode;
  perform captro_assert_purchase_available(p);
  insert into app_purchases(id,buyer_id,buyer_app_user_id,creator_id,content_type,fulfillment_type,item_title,price_label,
    quantity,unit_amount,total_amount,currency,status,payment_provider,idempotency_key,hold_expires_at,
    item_amount,service_fee_amount,creator_amount,platform_fee_amount,processing_amount,tax_amount,
    connected_account_id,stripe_destination_account_id,payment_interface,settlement_model,stripe_mode)
  values(p.id,h.buyer_id,h.buyer_app_user_id,h.creator_id,'creator_support','none','Creator support','One-time support',
    1,p_amount,p_amount,'USD','payment_pending','stripe','creator-support:'||h.request_key,now()+interval '35 minutes',
    p_amount,0,p_amount,0,0,0,a.id,a.provider_account_id,'checkout','deferred',active_mode) returning * into p;
  update app_creator_support_handoffs set purchase_id=p.id where id=h.id;
  return p;
end $$;



-- Owner-reviewed enrollment is mode-specific, optimistic-concurrency protected,
-- and audited atomically with the enrollment change.
create or replace function public.captro_admin_set_creator_support_enrollment(
  p_creator_id uuid, p_mode text, p_enabled boolean, p_admin_id text,
  p_actor_role text, p_expected_reviewed_at timestamptz, p_reason text, p_request_id text
) returns public.app_creator_support_enrollments
language plpgsql security definer set search_path=public as $$
declare current_row public.app_creator_support_enrollments%rowtype;
  updated_row public.app_creator_support_enrollments%rowtype; active_mode text;
  before_state jsonb := '{}'::jsonb; after_state jsonb;
begin
  if p_creator_id is null or p_mode not in ('test','live') or p_enabled is null
    or p_actor_role <> 'owner' or length(btrim(coalesce(p_admin_id,''))) < 1
    or length(btrim(coalesce(p_reason,''))) < 10 or length(p_reason) > 800 then
    raise exception 'CAPTRO_SUPPORT_ENROLLMENT_INPUT_INVALID';
  end if;
  select stripe_mode into active_mode from public.app_payment_environment where id for share;
  if active_mode is distinct from p_mode then raise exception 'CAPTRO_SUPPORT_MODE_MISMATCH'; end if;
  perform pg_advisory_xact_lock(hashtextextended('captro-support-enrollment:'||p_creator_id::text,0));
  select * into current_row from public.app_creator_support_enrollments where creator_id=p_creator_id for update;
  if found then
    if p_expected_reviewed_at is null or current_row.reviewed_at is distinct from p_expected_reviewed_at then
      raise exception 'CAPTRO_SUPPORT_ENROLLMENT_STALE';
    end if;
    before_state=jsonb_build_object('enabled_for_test',current_row.enabled_for_test,'enabled_for_live',current_row.enabled_for_live,
      'reviewed_at',current_row.reviewed_at);
    if p_mode='test' then current_row.enabled_for_test:=p_enabled; else current_row.enabled_for_live:=p_enabled; end if;
    update public.app_creator_support_enrollments set enabled_for_test=current_row.enabled_for_test,
      enabled_for_live=current_row.enabled_for_live,reviewed_by=p_admin_id,reviewed_at=clock_timestamp()
      where creator_id=p_creator_id returning * into updated_row;
  else
    if p_expected_reviewed_at is not null then raise exception 'CAPTRO_SUPPORT_ENROLLMENT_STALE'; end if;
    insert into public.app_creator_support_enrollments(creator_id,enabled_for_test,enabled_for_live,reviewed_by,reviewed_at)
      values(p_creator_id,p_mode='test' and p_enabled,p_mode='live' and p_enabled,p_admin_id,clock_timestamp())
      returning * into updated_row;
  end if;
  after_state=jsonb_build_object('enabled_for_test',updated_row.enabled_for_test,'enabled_for_live',updated_row.enabled_for_live,
    'reviewed_at',updated_row.reviewed_at,'stripe_mode',p_mode);
  insert into public.app_audit_logs(id,actor_admin_user_id,actor_role,action_type,target_type,target_id,target_user_id,
    reason,internal_note,before_state,after_state,request_id,metadata,legacy_created_at,created_at)
  values(gen_random_uuid()::text,p_admin_id,p_actor_role,'creator_support_enrollment_changed','creator_support_enrollment',
    p_creator_id::text,p_creator_id::text,btrim(p_reason),'',before_state,after_state,nullif(btrim(p_request_id),''),
    jsonb_build_object('source','cloudflare_worker_primary'),clock_timestamp(),clock_timestamp());
  return updated_row;
end $$;
revoke all on function public.captro_admin_set_creator_support_enrollment(uuid,text,boolean,text,text,timestamptz,text,text)
  from public,anon,authenticated;
grant execute on function public.captro_admin_set_creator_support_enrollment(uuid,text,boolean,text,text,timestamptz,text,text)
  to service_role;

-- The mode extension must not make a Support payment's original routing or
-- pricing mutable. Provider identifiers, status, fees and lifecycle timestamps
-- remain writable by the existing confirmed-payment/reconciliation functions.
create or replace function public.captro_guard_creator_support_snapshot()
returns trigger language plpgsql set search_path=public as $$
begin
  if old.content_type='creator_support' or new.content_type='creator_support' then
    if old.content_type is distinct from new.content_type
      or row(old.id,old.buyer_id,old.buyer_app_user_id,old.creator_id,old.post_id,old.purchasable_id,
        old.price_id,old.booking_slot_id,old.fulfillment_type,old.item_title,old.price_label,old.quantity,
        old.unit_amount,old.total_amount,old.currency,old.idempotency_key,old.selection,
        old.connected_account_id,old.stripe_destination_account_id,old.payment_interface,old.settlement_model,
        old.stripe_mode,old.item_amount,old.service_fee_amount,old.platform_fee_amount,old.tax_amount,old.created_at)
        is distinct from
      row(new.id,new.buyer_id,new.buyer_app_user_id,new.creator_id,new.post_id,new.purchasable_id,
        new.price_id,new.booking_slot_id,new.fulfillment_type,new.item_title,new.price_label,new.quantity,
        new.unit_amount,new.total_amount,new.currency,new.idempotency_key,new.selection,
        new.connected_account_id,new.stripe_destination_account_id,new.payment_interface,new.settlement_model,
        new.stripe_mode,new.item_amount,new.service_fee_amount,new.platform_fee_amount,new.tax_amount,new.created_at)
    then raise exception 'CAPTRO_SUPPORT_SNAPSHOT_IMMUTABLE'; end if;
  end if;
  return new;
end $$;
create trigger captro_creator_support_snapshot_immutable
  before update on public.app_purchases
  for each row execute function public.captro_guard_creator_support_snapshot();
revoke all on function public.captro_guard_creator_support_snapshot() from public,anon,authenticated;

commit;
