-- STAGING FIRST: the native app writes these objects through the authenticated
-- Worker (service_role), not through the public Data API. No data is deleted.
-- Before rollout verify server-managed owner roles and supported client versions.
begin;

-- RLS does not constrain TRUNCATE. No public client needs these DDL-like
-- privileges on any Captro table, even tables outside this focused write audit.
revoke truncate, references, trigger on all tables in schema public
from public, anon, authenticated;
alter default privileges in schema public revoke truncate, references, trigger
on tables from public, anon, authenticated;

revoke insert, update, delete, truncate, references, trigger on
  public.app_users, public.app_posts, public.post_comments,
  public.app_messages, public.app_group_chats, public.app_group_chat_members,
  public.app_group_messages
from public, anon, authenticated;

revoke all privileges on public.app_admin_roles from public, anon, authenticated;

-- Profiles contain email and private account metadata, not just public names.
-- Clients already use the Worker's audience-aware profile projections. Private
-- SECURITY DEFINER helpers below retain their narrowly scoped identity reads.
revoke select on public.app_users from public, anon, authenticated;

-- Authentication mapping must not keep returning banned/deleted accounts.
-- Search paths are fixed; callers cannot supply another user's identity.
create or replace function private.captro_current_app_user_id()
returns text language sql stable security definer
set search_path = ''
as $$
  select u.id::text from public.app_users u
  where u.supabase_user_id = auth.uid()
    and coalesce(u.metadata->>'status', 'active') = 'active'
  limit 1;
$$;
revoke all on function private.captro_current_app_user_id() from public, anon;
grant execute on function private.captro_current_app_user_id() to authenticated;

-- The former member policy queried its own table and could recurse. Resolve
-- only the caller's membership inside a private, narrowly scoped helper.
create or replace function private.captro_is_group_member(target_group text)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.app_group_chat_members m
    where m.group_id::text = target_group
      and m.user_id::text = private.captro_current_app_user_id()
  );
$$;
revoke all on function private.captro_is_group_member(text) from public, anon;
grant execute on function private.captro_is_group_member(text) to authenticated;

drop policy if exists "group members visible to members" on public.app_group_chat_members;
create policy "group members visible to members" on public.app_group_chat_members
for select to authenticated
using (private.captro_is_group_member(group_id::text));

drop policy if exists "group messages visible to members" on public.app_group_messages;
create policy "group messages visible to members" on public.app_group_messages
for select to authenticated
using (private.captro_is_group_member(group_id::text));

drop policy if exists "group chats visible to members" on public.app_group_chats;
create policy "group chats visible to members" on public.app_group_chats
for select to authenticated
using (private.captro_is_group_member(id::text));

-- Remove obsolete mutation policies as defense in depth against later grants.
drop policy if exists "users can create own direct messages" on public.app_messages;
drop policy if exists "users can update own direct messages" on public.app_messages;
drop policy if exists "users can create group chats" on public.app_group_chats;
drop policy if exists "users can join allowed group member rows" on public.app_group_chat_members;
drop policy if exists "members can send group messages" on public.app_group_messages;

commit;
