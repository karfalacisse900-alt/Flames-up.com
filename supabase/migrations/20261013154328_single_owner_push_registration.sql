-- APPROVAL REQUIRED: pair with the Worker's atomic device-token registration.
-- Preserve old rows but never deliver different accounts' pushes to one token.
begin;
revoke all privileges on public.app_push_tokens from public, anon, authenticated;
drop policy if exists "users can manage own push tokens" on public.app_push_tokens;

-- A latest timestamp does not prove which account is currently signed in.
-- Disable every ambiguous binding until the device explicitly re-registers.
with ambiguous as (
  select token_hash from public.app_push_tokens where is_active
  group by token_hash having count(*) > 1
)
update public.app_push_tokens p set is_active = false
from ambiguous a where p.token_hash = a.token_hash and p.is_active;

create unique index if not exists app_push_tokens_one_active_owner
  on public.app_push_tokens(token_hash) where is_active;

create or replace function public.captro_register_push_token(
  p_user_id text, p_id text, p_token_hash text, p_token text,
  p_device_id text, p_bundle_id text, p_environment text
) returns void language plpgsql security invoker set search_path = '' as $$
begin
  if nullif(p_user_id, '') is null or nullif(p_token_hash, '') is null
    or nullif(p_token, '') is null then
    raise exception 'INVALID_PUSH_REGISTRATION';
  end if;
  -- Serialize takeover and upsert in ONE transaction; two REST writes race.
  perform pg_advisory_xact_lock(hashtextextended('captro-push:' || p_token_hash, 0));
  update public.app_push_tokens set is_active = false, updated_at = now()
    where token_hash = p_token_hash and user_id <> p_user_id and is_active;
  insert into public.app_push_tokens
    (id, user_id, token_hash, token, device_id, bundle_id, environment,
     platform, is_active, last_seen_at, updated_at)
  values (p_id, p_user_id, p_token_hash, p_token, p_device_id, p_bundle_id,
    p_environment, 'ios', true, now(), now())
  on conflict (user_id, token_hash) do update set
    token = excluded.token, device_id = excluded.device_id,
    bundle_id = excluded.bundle_id, environment = excluded.environment,
    is_active = true, last_seen_at = now(), updated_at = now();
end $$;
revoke all on function public.captro_register_push_token(text,text,text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.captro_register_push_token(text,text,text,text,text,text,text)
  to service_role;
commit;
