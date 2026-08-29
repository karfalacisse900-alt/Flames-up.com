alter table public.scanned_receipts
  add column if not exists source text not null default 'unknown'
    check (source in ('camera', 'photo_library', 'files', 'unknown')),
  add column if not exists reward_amount_cents integer not null default 10
    check (reward_amount_cents > 0 and reward_amount_cents <= 5000),
  add column if not exists perceptual_hash text,
  add column if not exists verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'couldnt_verify'));

alter table public.scanned_receipts
  drop constraint if exists scanned_receipts_status_check;

alter table public.scanned_receipts
  add constraint scanned_receipts_status_check
  check (status in (
    'captured', 'uploading', 'processing', 'review_ready', 'feedback_pending',
    'reward_pending', 'completed', 'duplicate', 'unsupported', 'failed',
    'ready_for_feedback', 'rewarded'
  ));

alter table public.receipt_feedback
  add column if not exists expectations_rating smallint check (expectations_rating between 1 and 5),
  add column if not exists stock_rating smallint check (stock_rating between 1 and 5),
  add column if not exists result_rating smallint check (result_rating between 1 and 5);

alter table public.user_reward_balance
  add column if not exists pending_reward_cents bigint not null default 0
    check (pending_reward_cents >= 0);

alter table public.receipt_rewards
  drop constraint if exists receipt_rewards_amount_cents_check,
  drop constraint if exists receipt_rewards_status_check;

alter table public.receipt_rewards
  add constraint receipt_rewards_amount_cents_check
    check (amount_cents > 0 and amount_cents <= 5000),
  add constraint receipt_rewards_status_check
    check (status in ('pending', 'available', 'reversed', 'withdrawn')),
  add column if not exists available_at timestamptz,
  add column if not exists withdrawal_id uuid references public.receipt_withdrawal_requests(id) on delete set null;

update public.receipt_rewards
set available_at = coalesce(available_at, created_at)
where status = 'available' and available_at is null;

alter table public.receipt_withdrawal_requests
  drop constraint if exists receipt_withdrawal_requests_status_check;

alter table public.receipt_withdrawal_requests
  add constraint receipt_withdrawal_requests_status_check
  check (status in ('requested', 'processing', 'paid', 'failed', 'returned', 'canceled'));

drop function if exists public.captro_begin_receipt_review(uuid, text, text, text, text, text, text);

create function public.captro_begin_receipt_review(
  p_receipt_id uuid,
  p_user_id text,
  p_idempotency_key text,
  p_document_sha256 text,
  p_file_name text,
  p_mime_type text,
  p_detected_type text,
  p_source text default 'unknown',
  p_reward_amount_cents integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing public.scanned_receipts%rowtype;
  v_source text;
  v_reward_amount integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('captro-receipt:' || p_user_id || ':' || p_document_sha256, 0));

  v_source := case
    when p_source in ('camera', 'photo_library', 'files') then p_source
    else 'unknown'
  end;
  v_reward_amount := greatest(1, least(coalesce(p_reward_amount_cents, 10), 5000));

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
          verification_status = 'pending',
          reward_eligible = false,
          source = v_source,
          reward_amount_cents = v_reward_amount,
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

  insert into public.scanned_receipts (
    id, user_id, document_sha256, idempotency_key, original_file_name,
    mime_type, receipt_type, source, reward_amount_cents, status
  ) values (
    p_receipt_id, p_user_id, p_document_sha256, p_idempotency_key, p_file_name,
    p_mime_type, 'unsupported', v_source, v_reward_amount, 'processing'
  );

  return jsonb_build_object(
    'action', 'created',
    'receiptId', p_receipt_id,
    'status', 'processing',
    'rewardEligible', false
  );
end;
$$;

drop function if exists public.captro_submit_receipt_feedback_reward(
  uuid, text, text, smallint, smallint, smallint, smallint, smallint,
  smallint, smallint, smallint, smallint, smallint, text
);

create function public.captro_submit_receipt_feedback_reward(
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
  p_expectations_rating smallint default null,
  p_stock_rating smallint default null,
  p_result_rating smallint default null,
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
  v_amount integer;
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

  if v_receipt.status not in ('feedback_pending', 'ready_for_feedback')
     or v_receipt.verification_status <> 'verified'
     or not v_receipt.reward_eligible then
    raise exception 'RECEIPT_NOT_REWARD_ELIGIBLE';
  end if;

  if p_overall_rating is null or p_overall_rating not between 1 and 5 then
    raise exception 'RECEIPT_OVERALL_RATING_REQUIRED';
  end if;

  v_amount := greatest(1, least(v_receipt.reward_amount_cents, 5000));

  update public.scanned_receipts
  set status = 'reward_pending', updated_at = now()
  where id = p_receipt_id;

  insert into public.receipt_feedback (
    receipt_id, user_id, idempotency_key, category,
    cleanliness_rating, speed_rating, quality_rating, service_rating, value_rating,
    freshness_rating, organization_rating, professionalism_rating, satisfaction_rating,
    expectations_rating, stock_rating, result_rating, overall_rating, note
  ) values (
    p_receipt_id, p_user_id, p_idempotency_key, v_receipt.category,
    p_cleanliness_rating, p_speed_rating, p_quality_rating, p_service_rating, p_value_rating,
    p_freshness_rating, p_organization_rating, p_professionalism_rating, p_satisfaction_rating,
    p_expectations_rating, p_stock_rating, p_result_rating, p_overall_rating,
    nullif(btrim(p_note), '')
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
    user_id, receipt_id, feedback_id, idempotency_key, amount_cents, status, available_at
  ) values (
    p_user_id, p_receipt_id, v_feedback.id, p_idempotency_key, v_amount, 'available', now()
  )
  returning * into v_reward;

  update public.user_reward_balance
  set available_balance_cents = available_balance_cents + v_amount,
      lifetime_earned_cents = lifetime_earned_cents + v_amount,
      updated_at = now()
  where user_id = p_user_id
  returning * into v_balance;

  update public.scanned_receipts
  set status = 'completed',
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

revoke all on function public.captro_begin_receipt_review(
  uuid, text, text, text, text, text, text, text, integer
) from public, anon, authenticated;
revoke all on function public.captro_submit_receipt_feedback_reward(
  uuid, text, text,
  smallint, smallint, smallint, smallint, smallint,
  smallint, smallint, smallint, smallint, smallint,
  smallint, smallint, smallint, text
) from public, anon, authenticated;

grant execute on function public.captro_begin_receipt_review(
  uuid, text, text, text, text, text, text, text, integer
) to service_role;
grant execute on function public.captro_submit_receipt_feedback_reward(
  uuid, text, text,
  smallint, smallint, smallint, smallint, smallint,
  smallint, smallint, smallint, smallint, smallint,
  smallint, smallint, smallint, text
) to service_role;

comment on column public.scanned_receipts.reward_amount_cents is
  'Server-selected reward captured at document processing time.';
comment on table public.receipt_rewards is
  'Private append-only Captro receipt and invoice feedback reward ledger.';
