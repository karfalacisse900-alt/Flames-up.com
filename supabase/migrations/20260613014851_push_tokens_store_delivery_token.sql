alter table public.app_push_tokens
  add column if not exists token text;

create index if not exists app_push_tokens_token_active_idx
  on public.app_push_tokens (token, is_active)
  where token is not null;
