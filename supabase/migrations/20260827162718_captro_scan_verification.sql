-- Private, server-owned data for Captro Scan.
-- Raw document bytes remain in a private R2 prefix; Postgres stores references,
-- normalized extraction, checks, billing state, and minimal proof summaries.

create table if not exists public.scan_credit_accounts (
  user_id text primary key,
  balance_cents integer not null default 0 check (balance_cents >= 0),
  lifetime_purchased_cents integer not null default 0 check (lifetime_purchased_cents >= 0),
  lifetime_spent_cents integer not null default 0 check (lifetime_spent_cents >= 0),
  lifetime_restored_cents integer not null default 0 check (lifetime_restored_cents >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.scan_storekit_transactions (
  transaction_id text primary key,
  original_transaction_id text,
  user_id text not null,
  product_id text not null,
  credit_cents integer not null check (credit_cents > 0),
  paid_cents integer not null check (paid_cents >= 0),
  currency text not null default 'USD',
  environment text not null check (environment in ('Production', 'Sandbox')),
  status text not null default 'credited' check (status in ('credited', 'refunded', 'revoked')),
  purchased_at timestamptz,
  revoked_at timestamptz,
  payload_sha256 text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists scan_storekit_transactions_user_created_idx
  on public.scan_storekit_transactions (user_id, created_at desc);

create table if not exists public.scan_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  idempotency_key text not null,
  document_sha256 text not null,
  original_file_name text not null default '',
  original_mime_type text not null default '',
  private_storage_key text,
  document_type text not null default 'unknown'
    check (document_type in ('receipt', 'invoice', 'unsupported', 'unknown')),
  status text not null default 'processing'
    check (status in ('processing', 'verified', 'couldnt_verify', 'unsupported', 'failed')),
  provider text,
  provider_request_id text,
  provider_attempted_at timestamptz,
  normalized_business_name text,
  original_address_text text,
  address_street text,
  address_city text,
  address_state text,
  address_postal_code text,
  address_country text,
  normalized_place_id text,
  document_number text,
  transaction_reference text,
  document_date date,
  document_time time,
  total_amount numeric(18, 4),
  currency text,
  extracted_data jsonb not null default '{}'::jsonb,
  checks jsonb not null default '[]'::jsonb,
  duplicate_of uuid references public.scan_verifications(id) on delete set null,
  price_cents integer not null default 10 check (price_cents = 10),
  billing_state text not null default 'pending'
    check (billing_state in ('pending', 'charged', 'not_charged', 'refunded', 'credited')),
  error_code text,
  proof_id uuid,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint scan_verifications_user_idempotency_unique unique (user_id, idempotency_key)
);

create index if not exists scan_verifications_user_created_idx
  on public.scan_verifications (user_id, created_at desc);
create index if not exists scan_verifications_user_hash_idx
  on public.scan_verifications (user_id, document_sha256, created_at desc);
create index if not exists scan_verifications_document_number_idx
  on public.scan_verifications (user_id, document_type, document_number, document_date, total_amount)
  where document_number is not null;

create table if not exists public.scan_credit_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  direction text not null check (direction in ('credit', 'debit')),
  amount_cents integer not null check (amount_cents > 0),
  balance_after_cents integer not null check (balance_after_cents >= 0),
  reason text not null check (reason in ('storekit_purchase', 'verification', 'verification_refund', 'verification_credit')),
  billing_state text not null check (billing_state in ('charged', 'refunded', 'credited')),
  verification_id uuid references public.scan_verifications(id) on delete set null,
  storekit_transaction_id text references public.scan_storekit_transactions(transaction_id) on delete set null,
  idempotency_key text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists scan_credit_ledger_user_created_idx
  on public.scan_credit_ledger (user_id, created_at desc);

create table if not exists public.scan_proofs (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  verification_id uuid not null unique references public.scan_verifications(id) on delete cascade,
  document_type text not null check (document_type in ('receipt', 'invoice')),
  public_summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists scan_proofs_user_created_idx
  on public.scan_proofs (user_id, created_at desc);

drop trigger if exists scan_credit_accounts_set_updated_at on public.scan_credit_accounts;
create trigger scan_credit_accounts_set_updated_at
before update on public.scan_credit_accounts
for each row execute function public.set_captro_updated_at();

drop trigger if exists scan_storekit_transactions_set_updated_at on public.scan_storekit_transactions;
create trigger scan_storekit_transactions_set_updated_at
before update on public.scan_storekit_transactions
for each row execute function public.set_captro_updated_at();

drop trigger if exists scan_verifications_set_updated_at on public.scan_verifications;
create trigger scan_verifications_set_updated_at
before update on public.scan_verifications
for each row execute function public.set_captro_updated_at();

alter table public.scan_credit_accounts enable row level security;
alter table public.scan_storekit_transactions enable row level security;
alter table public.scan_verifications enable row level security;
alter table public.scan_credit_ledger enable row level security;
alter table public.scan_proofs enable row level security;

-- Scan records are intentionally unavailable through client Supabase roles.
-- The authenticated Cloudflare Worker is the only application data boundary.
revoke all on public.scan_credit_accounts from anon, authenticated;
revoke all on public.scan_storekit_transactions from anon, authenticated;
revoke all on public.scan_verifications from anon, authenticated;
revoke all on public.scan_credit_ledger from anon, authenticated;
revoke all on public.scan_proofs from anon, authenticated;
grant all on public.scan_credit_accounts to service_role;
grant all on public.scan_storekit_transactions to service_role;
grant all on public.scan_verifications to service_role;
grant all on public.scan_credit_ledger to service_role;
grant all on public.scan_proofs to service_role;

create or replace function public.captro_credit_storekit_purchase(
  p_user_id text,
  p_transaction_id text,
  p_original_transaction_id text,
  p_product_id text,
  p_credit_cents integer,
  p_paid_cents integer,
  p_currency text,
  p_environment text,
  p_purchased_at timestamptz,
  p_payload_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing_user text;
  v_inserted integer := 0;
  v_balance integer := 0;
begin
  if coalesce(trim(p_user_id), '') = ''
     or coalesce(trim(p_transaction_id), '') = ''
     or coalesce(trim(p_product_id), '') = ''
     or p_credit_cents <= 0
     or p_paid_cents < 0
     or p_environment not in ('Production', 'Sandbox') then
    raise exception 'SCAN_STOREKIT_PURCHASE_INVALID';
  end if;

  select user_id into v_existing_user
  from public.scan_storekit_transactions
  where transaction_id = p_transaction_id;

  if v_existing_user is not null then
    if v_existing_user <> p_user_id then
      raise exception 'SCAN_STOREKIT_TRANSACTION_OWNED_BY_ANOTHER_USER';
    end if;
    select balance_cents into v_balance
    from public.scan_credit_accounts
    where user_id = p_user_id;
    return jsonb_build_object('credited', false, 'duplicate', true, 'balance_cents', coalesce(v_balance, 0));
  end if;

  insert into public.scan_credit_accounts (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  perform 1 from public.scan_credit_accounts where user_id = p_user_id for update;

  insert into public.scan_storekit_transactions (
    transaction_id, original_transaction_id, user_id, product_id,
    credit_cents, paid_cents, currency, environment, purchased_at, payload_sha256
  ) values (
    p_transaction_id, nullif(trim(p_original_transaction_id), ''), p_user_id, p_product_id,
    p_credit_cents, p_paid_cents, upper(p_currency), p_environment, p_purchased_at, p_payload_sha256
  )
  on conflict (transaction_id) do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    select user_id into v_existing_user
    from public.scan_storekit_transactions
    where transaction_id = p_transaction_id;
    if v_existing_user <> p_user_id then
      raise exception 'SCAN_STOREKIT_TRANSACTION_OWNED_BY_ANOTHER_USER';
    end if;
    select balance_cents into v_balance from public.scan_credit_accounts where user_id = p_user_id;
    return jsonb_build_object('credited', false, 'duplicate', true, 'balance_cents', v_balance);
  end if;

  update public.scan_credit_accounts
  set balance_cents = balance_cents + p_credit_cents,
      lifetime_purchased_cents = lifetime_purchased_cents + p_credit_cents
  where user_id = p_user_id
  returning balance_cents into v_balance;

  insert into public.scan_credit_ledger (
    user_id, direction, amount_cents, balance_after_cents, reason,
    billing_state, storekit_transaction_id, idempotency_key
  ) values (
    p_user_id, 'credit', p_credit_cents, v_balance, 'storekit_purchase',
    'credited', p_transaction_id, 'storekit:' || p_transaction_id
  );

  return jsonb_build_object('credited', true, 'duplicate', false, 'balance_cents', v_balance);
end;
$$;

create or replace function public.captro_begin_scan_verification(
  p_verification_id uuid,
  p_user_id text,
  p_idempotency_key text,
  p_document_sha256 text,
  p_file_name text,
  p_mime_type text,
  p_detected_type text,
  p_price_cents integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing public.scan_verifications%rowtype;
  v_balance integer := 0;
begin
  if coalesce(trim(p_user_id), '') = ''
     or coalesce(trim(p_idempotency_key), '') = ''
     or p_document_sha256 !~ '^[a-f0-9]{64}$'
     or p_detected_type not in ('receipt', 'invoice')
     or p_price_cents <> 10 then
    raise exception 'SCAN_VERIFICATION_REQUEST_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id || ':' || p_document_sha256, 0));

  select * into v_existing
  from public.scan_verifications
  where user_id = p_user_id and idempotency_key = p_idempotency_key
  limit 1;

  if found then
    return jsonb_build_object(
      'action', 'existing',
      'verification_id', v_existing.id,
      'billing_state', v_existing.billing_state,
      'status', v_existing.status,
      'duplicate_of', v_existing.duplicate_of
    );
  end if;

  select * into v_existing
  from public.scan_verifications
  where user_id = p_user_id
    and document_sha256 = p_document_sha256
    and status in ('processing', 'verified', 'couldnt_verify')
  order by created_at desc
  limit 1;

  if found then
    return jsonb_build_object(
      'action', 'existing',
      'verification_id', v_existing.id,
      'billing_state', v_existing.billing_state,
      'status', v_existing.status,
      'duplicate_of', v_existing.duplicate_of
    );
  end if;

  insert into public.scan_credit_accounts (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;
  select balance_cents into v_balance
  from public.scan_credit_accounts
  where user_id = p_user_id
  for update;

  if v_balance < p_price_cents then
    raise exception 'SCAN_CREDITS_REQUIRED';
  end if;

  update public.scan_credit_accounts
  set balance_cents = balance_cents - p_price_cents,
      lifetime_spent_cents = lifetime_spent_cents + p_price_cents
  where user_id = p_user_id
  returning balance_cents into v_balance;

  insert into public.scan_verifications (
    id, user_id, idempotency_key, document_sha256, original_file_name,
    original_mime_type, document_type, status, price_cents, billing_state
  ) values (
    p_verification_id, p_user_id, p_idempotency_key, p_document_sha256, coalesce(p_file_name, ''),
    coalesce(p_mime_type, ''), p_detected_type, 'processing', p_price_cents, 'charged'
  );

  insert into public.scan_credit_ledger (
    user_id, direction, amount_cents, balance_after_cents, reason,
    billing_state, verification_id, idempotency_key
  ) values (
    p_user_id, 'debit', p_price_cents, v_balance, 'verification',
    'charged', p_verification_id, 'verification:' || p_idempotency_key
  );

  return jsonb_build_object(
    'action', 'process',
    'verification_id', p_verification_id,
    'billing_state', 'charged',
    'status', 'processing',
    'balance_cents', v_balance
  );
end;
$$;

create or replace function public.captro_restore_scan_credit(
  p_verification_id uuid,
  p_user_id text,
  p_reason text,
  p_billing_state text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_verification public.scan_verifications%rowtype;
  v_balance integer := 0;
  v_ledger_reason text;
begin
  if p_billing_state not in ('refunded', 'credited') then
    raise exception 'SCAN_RESTORE_STATE_INVALID';
  end if;

  select * into v_verification
  from public.scan_verifications
  where id = p_verification_id and user_id = p_user_id
  for update;

  if not found then
    raise exception 'SCAN_VERIFICATION_NOT_FOUND';
  end if;

  if v_verification.billing_state in ('refunded', 'credited', 'not_charged') then
    select balance_cents into v_balance from public.scan_credit_accounts where user_id = p_user_id;
    return jsonb_build_object('restored', false, 'balance_cents', coalesce(v_balance, 0));
  end if;

  if v_verification.billing_state <> 'charged' then
    raise exception 'SCAN_VERIFICATION_NOT_CHARGED';
  end if;

  perform 1 from public.scan_credit_accounts where user_id = p_user_id for update;
  update public.scan_credit_accounts
  set balance_cents = balance_cents + v_verification.price_cents,
      lifetime_restored_cents = lifetime_restored_cents + v_verification.price_cents
  where user_id = p_user_id
  returning balance_cents into v_balance;

  v_ledger_reason := case when p_billing_state = 'refunded' then 'verification_refund' else 'verification_credit' end;
  insert into public.scan_credit_ledger (
    user_id, direction, amount_cents, balance_after_cents, reason,
    billing_state, verification_id, idempotency_key, metadata
  ) values (
    p_user_id, 'credit', v_verification.price_cents, v_balance, v_ledger_reason,
    p_billing_state, p_verification_id, 'restore:' || p_verification_id::text,
    jsonb_build_object('reason', left(coalesce(p_reason, ''), 160))
  ) on conflict (idempotency_key) do nothing;

  update public.scan_verifications
  set billing_state = p_billing_state,
      status = case when p_billing_state = 'refunded' then 'failed' else status end,
      error_code = case when p_billing_state = 'refunded' then left(coalesce(p_reason, ''), 160) else error_code end,
      completed_at = coalesce(completed_at, now())
  where id = p_verification_id;

  return jsonb_build_object('restored', true, 'balance_cents', v_balance);
end;
$$;

revoke all on function public.captro_credit_storekit_purchase(text, text, text, text, integer, integer, text, text, timestamptz, text) from public, anon, authenticated;
revoke all on function public.captro_begin_scan_verification(uuid, text, text, text, text, text, text, integer) from public, anon, authenticated;
revoke all on function public.captro_restore_scan_credit(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.captro_credit_storekit_purchase(text, text, text, text, integer, integer, text, text, timestamptz, text) to service_role;
grant execute on function public.captro_begin_scan_verification(uuid, text, text, text, text, text, text, integer) to service_role;
grant execute on function public.captro_restore_scan_credit(uuid, text, text, text) to service_role;

comment on table public.scan_verifications is 'Private Captro receipt/invoice recognition, verification, duplicate, and billing records.';
comment on table public.scan_credit_ledger is 'Append-only cent-denominated Scan credit ledger. One verification debit is exactly 10 cents.';
comment on table public.scan_proofs is 'Private proof summaries. Raw documents are never stored in this table or exposed publicly.';
