-- Verification tokens are managed only by the Cloudflare Worker service role.
-- Keep explicit deny-all policies so public clients cannot read or mutate token hashes.

alter table public.app_account_verification_tokens enable row level security;

drop policy if exists "no direct client read verification tokens" on public.app_account_verification_tokens;
create policy "no direct client read verification tokens"
on public.app_account_verification_tokens
for select
to authenticated
using (false);

drop policy if exists "no direct client insert verification tokens" on public.app_account_verification_tokens;
create policy "no direct client insert verification tokens"
on public.app_account_verification_tokens
for insert
to authenticated
with check (false);

drop policy if exists "no direct client update verification tokens" on public.app_account_verification_tokens;
create policy "no direct client update verification tokens"
on public.app_account_verification_tokens
for update
to authenticated
using (false)
with check (false);

drop policy if exists "no direct client delete verification tokens" on public.app_account_verification_tokens;
create policy "no direct client delete verification tokens"
on public.app_account_verification_tokens
for delete
to authenticated
using (false);
