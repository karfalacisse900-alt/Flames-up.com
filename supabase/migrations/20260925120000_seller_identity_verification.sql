-- Stripe Identity is an optional, separate seller check. Connect eligibility
-- remains authoritative for transfers and payouts. Never store document data.
create table public.app_seller_identity_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  app_user_id text not null,
  stripe_mode text not null check (stripe_mode in ('test', 'live')),
  connected_account_id uuid not null references public.app_connected_accounts(id) on delete restrict,
  provider_session_id text unique check (provider_session_id is null or provider_session_id ~ '^vs_[A-Za-z0-9]+$'),
  status text not null default 'not_started'
    check (status in ('not_started', 'requires_input', 'processing', 'verified', 'canceled')),
  failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, stripe_mode)
);

create index app_seller_identity_account_idx
  on public.app_seller_identity_verifications (connected_account_id, stripe_mode);

alter table public.app_seller_identity_verifications enable row level security;
revoke all on table public.app_seller_identity_verifications from public, anon, authenticated;
grant all on table public.app_seller_identity_verifications to service_role;

comment on table public.app_seller_identity_verifications is
  'Backend-only seller Stripe Identity status and references. Identity images, ID numbers, and selfie data remain with Stripe.';
