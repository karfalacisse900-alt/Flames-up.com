create table if not exists public.app_account_verification_tokens (
  id text primary key,
  user_id text not null,
  token_type text not null,
  target text not null,
  token_hash text not null,
  attempts integer not null default 0,
  expires_at timestamptz not null,
  used_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_account_verification_tokens_lookup_idx
  on public.app_account_verification_tokens (token_type, token_hash)
  where used_at is null;

create index if not exists app_account_verification_tokens_user_target_idx
  on public.app_account_verification_tokens (user_id, token_type, target, created_at desc);

alter table public.app_account_verification_tokens enable row level security;

drop trigger if exists app_account_verification_tokens_set_updated_at on public.app_account_verification_tokens;
create trigger app_account_verification_tokens_set_updated_at
before update on public.app_account_verification_tokens
for each row execute function public.set_updated_at();
