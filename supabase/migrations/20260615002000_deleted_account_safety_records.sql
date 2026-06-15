-- Minimal hashed safety records retained after permanent account deletion.
-- Raw email/provider identifiers are not stored here.

create table if not exists public.app_deleted_account_safety_records (
  id text primary key default gen_random_uuid()::text,
  user_id text not null,
  email_hash text,
  provider text,
  provider_user_id_hash text,
  status_at_deletion text not null default 'deletion_pending',
  reason text not null default 'account_deletion',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists app_deleted_account_safety_email_idx
  on public.app_deleted_account_safety_records (email_hash)
  where email_hash is not null;

create index if not exists app_deleted_account_safety_provider_idx
  on public.app_deleted_account_safety_records (provider, provider_user_id_hash)
  where provider_user_id_hash is not null;

alter table public.app_deleted_account_safety_records enable row level security;

drop policy if exists "normal users cannot access deleted account safety records" on public.app_deleted_account_safety_records;
create policy "normal users cannot access deleted account safety records"
on public.app_deleted_account_safety_records
for all
to anon, authenticated
using (false)
with check (false);

