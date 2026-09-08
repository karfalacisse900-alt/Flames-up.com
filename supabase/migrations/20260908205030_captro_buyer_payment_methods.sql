-- One Stripe Customer per authenticated Captro user and Stripe mode. Stripe
-- stores the actual payment methods; Captro stores only this server-side link.

create table public.app_stripe_customers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  app_user_id text not null,
  stripe_mode text not null check (stripe_mode in ('test', 'live')),
  provider_customer_id text not null check (provider_customer_id ~ '^cus_[A-Za-z0-9]+$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, stripe_mode),
  unique (provider_customer_id)
);

create index app_stripe_customers_app_user_mode_idx
  on public.app_stripe_customers (app_user_id, stripe_mode);

alter table public.app_stripe_customers enable row level security;

revoke all on table public.app_stripe_customers from anon, authenticated;
grant all on table public.app_stripe_customers to service_role;

comment on table public.app_stripe_customers is
  'Private server-side mapping between a Captro user and a Stripe Customer. No raw card data is stored here.';
