-- Captro-managed payout recipients replace the former Express dashboard flow.
-- Keep a durable mapping for retired provider accounts so late Stripe webhooks
-- are ignored rather than re-attaching an old account to the active profile.
create table if not exists public.app_retired_connected_accounts (
  provider_account_id text not null,
  stripe_mode text not null check (stripe_mode in ('test', 'live')),
  -- This only records migrations that were proven financially untouched. It
  -- must not add a new permanent-account-deletion blocker.
  user_id uuid not null references auth.users(id) on delete cascade,
  app_user_id text not null,
  account_type text not null check (account_type in ('express', 'standard', 'custom')),
  replacement_provider_account_id text not null,
  migrated_to_connected_account_id uuid not null references public.app_connected_accounts(id) on delete cascade,
  retirement_reason text not null,
  retired_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  primary key (provider_account_id, stripe_mode)
);

create index if not exists app_retired_connected_accounts_user_mode_idx
  on public.app_retired_connected_accounts (user_id, stripe_mode, retired_at desc);

alter table public.app_retired_connected_accounts enable row level security;
revoke all on public.app_retired_connected_accounts from public, anon, authenticated;
grant all on public.app_retired_connected_accounts to service_role;

-- The Stripe replacement is created before this function is called. This
-- transaction is the point at which Captro changes the active mapping, and it
-- refuses to do so if even one local financial record is tied to the old row.
create or replace function public.captro_upgrade_untouched_payout_account(
  p_account_id uuid,
  p_user_id uuid,
  p_app_user_id text,
  p_stripe_mode text,
  p_old_provider_account_id text,
  p_new_provider_account_id text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current public.app_connected_accounts%rowtype;
begin
  if p_stripe_mode not in ('test', 'live')
      or p_old_provider_account_id is null
      or pg_catalog.left(p_old_provider_account_id, 5) <> 'acct_'
      or p_old_provider_account_id !~ '^acct_[A-Za-z0-9]+$'
      or p_new_provider_account_id is null
      or pg_catalog.left(p_new_provider_account_id, 5) <> 'acct_'
      or p_new_provider_account_id !~ '^acct_[A-Za-z0-9]+$'
      or p_old_provider_account_id = p_new_provider_account_id then
    return false;
  end if;

  select * into v_current
  from public.app_connected_accounts
  where id = p_account_id
    and user_id = p_user_id
    and app_user_id = p_app_user_id
    and stripe_mode = p_stripe_mode
    and provider_account_id = p_old_provider_account_id
    and account_type = 'express'
  for update;

  if not found then return false; end if;

  -- This is intentionally stricter than visual readiness. A profile that has
  -- ever accepted details, a card, or a payout capability must be reviewed
  -- instead of being silently moved to a different Stripe account.
  if v_current.status is distinct from 'onboarding'
      or v_current.details_submitted is distinct from false
      or v_current.charges_enabled is distinct from false
      or v_current.transfers_enabled is distinct from false
      or v_current.payouts_enabled is distinct from false
      or v_current.eligible_debit_card_exists is distinct from false
      or v_current.payout_card is not null
      or v_current.external_account_type is not null
      or v_current.external_account_name is not null
      or v_current.external_account_last4 is not null then
    return false;
  end if;

  if exists (
    select 1 from public.app_connected_accounts
    where provider_account_id = p_new_provider_account_id and id <> v_current.id
  ) then
    return false;
  end if;

  if exists (
    select 1 from public.app_purchases purchase
    where purchase.connected_account_id = v_current.id
       or purchase.stripe_destination_account_id = v_current.provider_account_id
  ) or exists (
    select 1 from public.app_creator_earnings earning
    where earning.connected_account_id = v_current.id
  ) or exists (
    select 1 from public.app_payouts payout
    where payout.connected_account_id = v_current.id
  ) or exists (
    select 1 from public.app_payout_requests request
    where request.connected_account_id = v_current.id
       or request.provider_account_id = v_current.provider_account_id
  ) then
    return false;
  end if;

  insert into public.app_retired_connected_accounts (
    provider_account_id, stripe_mode, user_id, app_user_id, account_type,
    replacement_provider_account_id, migrated_to_connected_account_id, retirement_reason
  ) values (
    v_current.provider_account_id, p_stripe_mode, v_current.user_id,
    v_current.app_user_id, v_current.account_type, p_new_provider_account_id,
    v_current.id, 'captro_managed_payout_account_upgrade'
  ) on conflict (provider_account_id, stripe_mode) do nothing;

  if not found then return false; end if;

  update public.app_connected_accounts
  set provider_account_id = p_new_provider_account_id,
      account_type = 'custom',
      status = 'onboarding',
      details_submitted = false,
      charges_enabled = false,
      transfers_enabled = false,
      payouts_enabled = false,
      eligible_debit_card_exists = false,
      requirements_currently_due = '[]'::pg_catalog.jsonb,
      requirements_eventually_due = '[]'::pg_catalog.jsonb,
      disabled_reason = null,
      external_account_type = null,
      external_account_name = null,
      external_account_last4 = null,
      payout_card = null,
      payout_schedule = null,
      last_provider_sync_at = null,
      updated_at = pg_catalog.now()
  where id = v_current.id;

  if not found then return false; end if;

  return true;
end;
$$;

revoke all on function public.captro_upgrade_untouched_payout_account(uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.captro_upgrade_untouched_payout_account(uuid, uuid, text, text, text, text)
  to service_role;

notify pgrst, 'reload schema';
