create table if not exists public.scanned_receipts (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  document_sha256 text not null check (document_sha256 ~ '^[0-9a-f]{64}$'),
  reward_fingerprint text check (reward_fingerprint is null or reward_fingerprint ~ '^[0-9a-f]{64}$'),
  idempotency_key text not null,
  original_file_name text,
  mime_type text,
  receipt_type text not null default 'unsupported'
    check (receipt_type in ('receipt', 'invoice', 'unsupported')),
  merchant_name text,
  category text not null default 'general'
    check (category in ('restaurant_food', 'product_retail', 'grocery', 'service_business', 'general')),
  private_storage_path text,
  extracted_text text,
  extracted_data jsonb not null default '{}'::jsonb,
  total_amount numeric(14, 2),
  currency text,
  purchase_date date,
  purchase_time time without time zone,
  provider text,
  provider_request_id text,
  status text not null default 'processing'
    check (status in ('processing', 'ready_for_feedback', 'rewarded', 'duplicate', 'unsupported', 'failed')),
  reward_eligible boolean not null default false,
  duplicate_of uuid references public.scanned_receipts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (user_id, document_sha256),
  unique (user_id, idempotency_key)
);

create table if not exists public.receipt_feedback (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null unique references public.scanned_receipts(id) on delete cascade,
  user_id text not null,
  idempotency_key text not null,
  category text not null
    check (category in ('restaurant_food', 'product_retail', 'grocery', 'service_business', 'general')),
  cleanliness_rating smallint check (cleanliness_rating between 1 and 5),
  speed_rating smallint check (speed_rating between 1 and 5),
  quality_rating smallint check (quality_rating between 1 and 5),
  service_rating smallint check (service_rating between 1 and 5),
  value_rating smallint check (value_rating between 1 and 5),
  freshness_rating smallint check (freshness_rating between 1 and 5),
  organization_rating smallint check (organization_rating between 1 and 5),
  professionalism_rating smallint check (professionalism_rating between 1 and 5),
  satisfaction_rating smallint check (satisfaction_rating between 1 and 5),
  overall_rating smallint not null check (overall_rating between 1 and 5),
  note text check (char_length(note) <= 800),
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create table if not exists public.user_reward_balance (
  user_id text primary key,
  available_balance_cents bigint not null default 0 check (available_balance_cents >= 0),
  lifetime_earned_cents bigint not null default 0 check (lifetime_earned_cents >= 0),
  lifetime_withdrawn_cents bigint not null default 0 check (lifetime_withdrawn_cents >= 0),
  pending_withdrawal_cents bigint not null default 0 check (pending_withdrawal_cents >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.receipt_rewards (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  receipt_id uuid not null unique references public.scanned_receipts(id) on delete restrict,
  feedback_id uuid not null unique references public.receipt_feedback(id) on delete restrict,
  idempotency_key text not null,
  amount_cents integer not null default 10 check (amount_cents = 10),
  currency text not null default 'USD' check (currency = 'USD'),
  reward_type text not null default 'receipt_feedback' check (reward_type = 'receipt_feedback'),
  status text not null default 'available' check (status in ('available', 'withdrawn', 'reversed')),
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create table if not exists public.receipt_withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  amount_cents bigint not null check (amount_cents > 0),
  currency text not null default 'USD' check (currency = 'USD'),
  status text not null default 'requested'
    check (status in ('requested', 'processing', 'paid', 'failed', 'canceled')),
  payout_provider text,
  payout_reference text,
  failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists scanned_receipts_user_created_idx
  on public.scanned_receipts (user_id, created_at desc);
create index if not exists scanned_receipts_hash_idx
  on public.scanned_receipts (document_sha256);
create unique index if not exists scanned_receipts_reward_fingerprint_uidx
  on public.scanned_receipts (reward_fingerprint)
  where reward_fingerprint is not null;
create index if not exists receipt_feedback_user_created_idx
  on public.receipt_feedback (user_id, created_at desc);
create index if not exists receipt_rewards_user_created_idx
  on public.receipt_rewards (user_id, created_at desc);
create index if not exists receipt_withdrawals_user_created_idx
  on public.receipt_withdrawal_requests (user_id, created_at desc);

alter table public.scanned_receipts enable row level security;
alter table public.receipt_feedback enable row level security;
alter table public.receipt_rewards enable row level security;
alter table public.user_reward_balance enable row level security;
alter table public.receipt_withdrawal_requests enable row level security;

revoke all on public.scanned_receipts from anon, authenticated;
revoke all on public.receipt_feedback from anon, authenticated;
revoke all on public.receipt_rewards from anon, authenticated;
revoke all on public.user_reward_balance from anon, authenticated;
revoke all on public.receipt_withdrawal_requests from anon, authenticated;

grant select, insert, update, delete on public.scanned_receipts to service_role;
grant select, insert, update, delete on public.receipt_feedback to service_role;
grant select, insert, update, delete on public.receipt_rewards to service_role;
grant select, insert, update, delete on public.user_reward_balance to service_role;
grant select, insert, update, delete on public.receipt_withdrawal_requests to service_role;

create or replace function public.captro_begin_receipt_review(
  p_receipt_id uuid,
  p_user_id text,
  p_idempotency_key text,
  p_document_sha256 text,
  p_file_name text,
  p_mime_type text,
  p_detected_type text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing public.scanned_receipts%rowtype;
  v_duplicate public.scanned_receipts%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('captro-receipt:' || p_document_sha256, 0));

  select * into v_existing
  from public.scanned_receipts
  where user_id = p_user_id
    and (idempotency_key = p_idempotency_key or document_sha256 = p_document_sha256)
  order by created_at asc
  limit 1;

  if found then
    if v_existing.status = 'failed' then
      update public.scanned_receipts
      set status = 'processing',
          reward_eligible = false,
          updated_at = now(),
          completed_at = null
      where id = v_existing.id;
      return jsonb_build_object(
        'action', 'retry',
        'receiptId', v_existing.id,
        'status', 'processing',
        'rewardEligible', false
      );
    end if;
    return jsonb_build_object(
      'action', 'existing',
      'receiptId', v_existing.id,
      'status', v_existing.status,
      'rewardEligible', v_existing.reward_eligible
    );
  end if;

  select * into v_duplicate
  from public.scanned_receipts
  where document_sha256 = p_document_sha256
    and user_id <> p_user_id
  order by created_at asc
  limit 1;

  if found then
    insert into public.scanned_receipts (
      id, user_id, document_sha256, idempotency_key, original_file_name, mime_type,
      receipt_type, status, reward_eligible, duplicate_of, completed_at
    ) values (
      p_receipt_id, p_user_id, p_document_sha256, p_idempotency_key, p_file_name, p_mime_type,
      case when p_detected_type in ('receipt', 'invoice') then p_detected_type else 'unsupported' end,
      'duplicate', false, v_duplicate.id, now()
    );
    return jsonb_build_object(
      'action', 'duplicate',
      'receiptId', p_receipt_id,
      'status', 'duplicate',
      'rewardEligible', false
    );
  end if;

  insert into public.scanned_receipts (
    id, user_id, document_sha256, idempotency_key, original_file_name, mime_type, receipt_type
  ) values (
    p_receipt_id,
    p_user_id,
    p_document_sha256,
    p_idempotency_key,
    p_file_name,
    p_mime_type,
    case when p_detected_type in ('receipt', 'invoice') then p_detected_type else 'unsupported' end
  );

  return jsonb_build_object(
    'action', 'created',
    'receiptId', p_receipt_id,
    'status', 'processing',
    'rewardEligible', false
  );
end;
$$;

create or replace function public.captro_submit_receipt_feedback_reward(
  p_receipt_id uuid,
  p_user_id text,
  p_idempotency_key text,
  p_cleanliness_rating smallint default null,
  p_speed_rating smallint default null,
  p_quality_rating smallint default null,
  p_service_rating smallint default null,
  p_value_rating smallint default null,
  p_freshness_rating smallint default null,
  p_organization_rating smallint default null,
  p_professionalism_rating smallint default null,
  p_satisfaction_rating smallint default null,
  p_overall_rating smallint default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt public.scanned_receipts%rowtype;
  v_feedback public.receipt_feedback%rowtype;
  v_reward public.receipt_rewards%rowtype;
  v_balance public.user_reward_balance%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('captro-feedback:' || p_receipt_id::text, 0));

  select * into v_receipt
  from public.scanned_receipts
  where id = p_receipt_id and user_id = p_user_id
  for update;

  if not found then
    raise exception 'RECEIPT_NOT_FOUND';
  end if;

  select * into v_reward
  from public.receipt_rewards
  where receipt_id = p_receipt_id
  limit 1;

  if found then
    select * into v_balance from public.user_reward_balance where user_id = p_user_id;
    return jsonb_build_object(
      'rewarded', false,
      'duplicate', true,
      'rewardId', v_reward.id,
      'amountCents', v_reward.amount_cents,
      'availableBalanceCents', coalesce(v_balance.available_balance_cents, 0),
      'lifetimeEarnedCents', coalesce(v_balance.lifetime_earned_cents, 0)
    );
  end if;

  if v_receipt.status <> 'ready_for_feedback' or not v_receipt.reward_eligible then
    raise exception 'RECEIPT_NOT_REWARD_ELIGIBLE';
  end if;

  if p_overall_rating is null or p_overall_rating not between 1 and 5 then
    raise exception 'RECEIPT_OVERALL_RATING_REQUIRED';
  end if;

  insert into public.receipt_feedback (
    receipt_id, user_id, idempotency_key, category,
    cleanliness_rating, speed_rating, quality_rating, service_rating, value_rating,
    freshness_rating, organization_rating, professionalism_rating, satisfaction_rating,
    overall_rating, note
  ) values (
    p_receipt_id, p_user_id, p_idempotency_key, v_receipt.category,
    p_cleanliness_rating, p_speed_rating, p_quality_rating, p_service_rating, p_value_rating,
    p_freshness_rating, p_organization_rating, p_professionalism_rating, p_satisfaction_rating,
    p_overall_rating, nullif(btrim(p_note), '')
  )
  returning * into v_feedback;

  insert into public.user_reward_balance (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select * into v_balance
  from public.user_reward_balance
  where user_id = p_user_id
  for update;

  insert into public.receipt_rewards (
    user_id, receipt_id, feedback_id, idempotency_key, amount_cents
  ) values (
    p_user_id, p_receipt_id, v_feedback.id, p_idempotency_key, 10
  )
  returning * into v_reward;

  update public.user_reward_balance
  set available_balance_cents = available_balance_cents + 10,
      lifetime_earned_cents = lifetime_earned_cents + 10,
      updated_at = now()
  where user_id = p_user_id
  returning * into v_balance;

  update public.scanned_receipts
  set status = 'rewarded',
      reward_eligible = false,
      updated_at = now(),
      completed_at = now()
  where id = p_receipt_id;

  return jsonb_build_object(
    'rewarded', true,
    'duplicate', false,
    'rewardId', v_reward.id,
    'amountCents', v_reward.amount_cents,
    'availableBalanceCents', v_balance.available_balance_cents,
    'lifetimeEarnedCents', v_balance.lifetime_earned_cents
  );
exception
  when unique_violation then
    select * into v_reward
    from public.receipt_rewards
    where receipt_id = p_receipt_id
    limit 1;
    select * into v_balance
    from public.user_reward_balance
    where user_id = p_user_id;
    if v_reward.id is not null then
      return jsonb_build_object(
        'rewarded', false,
        'duplicate', true,
        'rewardId', v_reward.id,
        'amountCents', v_reward.amount_cents,
        'availableBalanceCents', coalesce(v_balance.available_balance_cents, 0),
        'lifetimeEarnedCents', coalesce(v_balance.lifetime_earned_cents, 0)
      );
    end if;
    raise;
end;
$$;

create or replace function public.captro_claim_receipt_reward_fingerprint(
  p_receipt_id uuid,
  p_user_id text,
  p_reward_fingerprint text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current public.scanned_receipts%rowtype;
  v_duplicate public.scanned_receipts%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('captro-reward-fingerprint:' || p_reward_fingerprint, 0));

  select * into v_current
  from public.scanned_receipts
  where id = p_receipt_id and user_id = p_user_id
  for update;

  if not found then
    raise exception 'RECEIPT_NOT_FOUND';
  end if;

  select * into v_duplicate
  from public.scanned_receipts
  where reward_fingerprint = p_reward_fingerprint
    and id <> p_receipt_id
  order by created_at asc
  limit 1;

  if found then
    update public.scanned_receipts
    set status = 'duplicate',
        reward_eligible = false,
        duplicate_of = v_duplicate.id,
        updated_at = now(),
        completed_at = now()
    where id = p_receipt_id;
    return jsonb_build_object('claimed', false, 'duplicate', true);
  end if;

  update public.scanned_receipts
  set reward_fingerprint = p_reward_fingerprint,
      updated_at = now()
  where id = p_receipt_id;

  return jsonb_build_object('claimed', true, 'duplicate', false);
end;
$$;

revoke all on function public.captro_begin_receipt_review(uuid, text, text, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.captro_submit_receipt_feedback_reward(
  uuid, text, text, smallint, smallint, smallint, smallint, smallint,
  smallint, smallint, smallint, smallint, smallint, text
) from public, anon, authenticated;
revoke all on function public.captro_claim_receipt_reward_fingerprint(uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.captro_begin_receipt_review(uuid, text, text, text, text, text, text)
  to service_role;
grant execute on function public.captro_submit_receipt_feedback_reward(
  uuid, text, text, smallint, smallint, smallint, smallint, smallint,
  smallint, smallint, smallint, smallint, smallint, text
) to service_role;
grant execute on function public.captro_claim_receipt_reward_fingerprint(uuid, text, text)
  to service_role;

comment on table public.scanned_receipts is 'Private receipt and invoice OCR records owned by one Captro account.';
comment on table public.receipt_rewards is 'Immutable ten-cent receipt feedback reward ledger.';
comment on table public.user_reward_balance is 'Private aggregate receipt earnings for the account owner.';
