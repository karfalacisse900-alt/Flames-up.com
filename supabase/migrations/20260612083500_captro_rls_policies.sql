-- Captro Supabase RLS policies.
--
-- Supabase Auth/Postgres is Captro's app-data source of truth. The iOS app may
-- use authenticated Supabase reads for safe public/user-owned surfaces, while
-- privileged writes, moderation, uploads, and admin actions continue through the
-- Cloudflare Worker service-role layer.

do $$
declare
  table_name text;
begin
  for table_name in
    select tablename
    from pg_tables
    where schemaname = 'public'
  loop
    execute format('alter table public.%I enable row level security', table_name);
  end loop;
end $$;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.captro_current_app_user_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select u.id::text
  from public.app_users u
  where u.supabase_user_id::text = auth.uid()::text
  limit 1
$$;

create or replace function private.captro_user_is_active(app_user_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_users u
    where u.id::text = app_user_id
      and coalesce(u.metadata->>'status', 'active') = 'active'
  )
$$;

create or replace function private.captro_users_not_blocked(left_user_id text, right_user_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select left_user_id is null
    or right_user_id is null
    or left_user_id = ''
    or right_user_id = ''
    or left_user_id = right_user_id
    or not exists (
      select 1
      from public.app_blocks b
      where (b.blocker_id::text = left_user_id and b.blocked_id::text = right_user_id)
         or (b.blocker_id::text = right_user_id and b.blocked_id::text = left_user_id)
    )
$$;

revoke all on function private.captro_current_app_user_id() from public, anon;
revoke all on function private.captro_user_is_active(text) from public, anon;
revoke all on function private.captro_users_not_blocked(text, text) from public, anon;
grant execute on function private.captro_current_app_user_id() to authenticated;
grant execute on function private.captro_user_is_active(text) to authenticated;
grant execute on function private.captro_users_not_blocked(text, text) to authenticated;

drop policy if exists "users can read active profiles and own profile" on public.app_users;
create policy "users can read active profiles and own profile"
on public.app_users
for select
to authenticated
using (
  supabase_user_id::text = auth.uid()::text
  or coalesce(metadata->>'status', 'active') = 'active'
);

drop policy if exists "users can insert own profile" on public.app_users;
create policy "users can insert own profile"
on public.app_users
for insert
to authenticated
with check (supabase_user_id::text = auth.uid()::text);

drop policy if exists "users can update own profile" on public.app_users;
create policy "users can update own profile"
on public.app_users
for update
to authenticated
using (supabase_user_id::text = auth.uid()::text)
with check (supabase_user_id::text = auth.uid()::text);

drop policy if exists "users can read visible posts" on public.app_posts;
create policy "users can read visible posts"
on public.app_posts
for select
to authenticated
using (
  app_user_id::text = private.captro_current_app_user_id()
  or (
    status = 'active'
    and visibility = 'public'
    and private.captro_user_is_active(app_user_id::text)
    and private.captro_users_not_blocked(private.captro_current_app_user_id(), app_user_id::text)
  )
);

drop policy if exists "users can insert own posts" on public.app_posts;
create policy "users can insert own posts"
on public.app_posts
for insert
to authenticated
with check (
  app_user_id::text = private.captro_current_app_user_id()
  and (user_id is null or user_id::text = auth.uid()::text)
);

drop policy if exists "users can update own posts" on public.app_posts;
create policy "users can update own posts"
on public.app_posts
for update
to authenticated
using (app_user_id::text = private.captro_current_app_user_id())
with check (app_user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can delete own posts" on public.app_posts;
create policy "users can delete own posts"
on public.app_posts
for delete
to authenticated
using (app_user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can read visible comments" on public.post_comments;
create policy "users can read visible comments"
on public.post_comments
for select
to authenticated
using (
  status = 'active'
  and private.captro_user_is_active(app_user_id::text)
  and private.captro_users_not_blocked(private.captro_current_app_user_id(), app_user_id::text)
  and exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id::text = post_comments.legacy_post_id::text
      and (
        p.app_user_id::text = private.captro_current_app_user_id()
        or (
          p.status = 'active'
          and p.visibility = 'public'
          and private.captro_users_not_blocked(private.captro_current_app_user_id(), p.app_user_id::text)
        )
      )
  )
);

drop policy if exists "users can insert own comments" on public.post_comments;
create policy "users can insert own comments"
on public.post_comments
for insert
to authenticated
with check (
  app_user_id::text = private.captro_current_app_user_id()
  and (user_id is null or user_id::text = auth.uid()::text)
  and exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id::text = post_comments.legacy_post_id::text
      and p.status = 'active'
      and (
        p.app_user_id::text = private.captro_current_app_user_id()
        or (
          p.visibility = 'public'
          and private.captro_users_not_blocked(private.captro_current_app_user_id(), p.app_user_id::text)
        )
      )
  )
);

drop policy if exists "users can update own comments" on public.post_comments;
create policy "users can update own comments"
on public.post_comments
for update
to authenticated
using (app_user_id::text = private.captro_current_app_user_id())
with check (app_user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can delete own comments" on public.post_comments;
create policy "users can delete own comments"
on public.post_comments
for delete
to authenticated
using (app_user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can read own interactions" on public.app_post_interactions;
create policy "users can read own interactions"
on public.app_post_interactions
for select
to authenticated
using (
  app_user_id::text = private.captro_current_app_user_id()
  or user_id::text = auth.uid()::text
);

drop policy if exists "users can insert own interactions" on public.app_post_interactions;
create policy "users can insert own interactions"
on public.app_post_interactions
for insert
to authenticated
with check (
  kind in ('like', 'save')
  and (
    app_user_id::text = private.captro_current_app_user_id()
    or user_id::text = auth.uid()::text
  )
);

drop policy if exists "users can delete own interactions" on public.app_post_interactions;
create policy "users can delete own interactions"
on public.app_post_interactions
for delete
to authenticated
using (
  app_user_id::text = private.captro_current_app_user_id()
  or user_id::text = auth.uid()::text
);

drop policy if exists "users can read relevant follows" on public.app_follows;
create policy "users can read relevant follows"
on public.app_follows
for select
to authenticated
using (
  app_follower_id::text = private.captro_current_app_user_id()
  or app_following_id::text = private.captro_current_app_user_id()
);

drop policy if exists "users can create own follows" on public.app_follows;
create policy "users can create own follows"
on public.app_follows
for insert
to authenticated
with check (
  app_follower_id::text = private.captro_current_app_user_id()
  and app_follower_id::text <> app_following_id::text
  and private.captro_users_not_blocked(app_follower_id::text, app_following_id::text)
);

drop policy if exists "users can delete own follows" on public.app_follows;
create policy "users can delete own follows"
on public.app_follows
for delete
to authenticated
using (app_follower_id::text = private.captro_current_app_user_id());

drop policy if exists "users can manage own documents" on public.app_documents;
create policy "users can manage own documents"
on public.app_documents
for all
to authenticated
using (owner_id::text = private.captro_current_app_user_id())
with check (owner_id::text = private.captro_current_app_user_id());

drop policy if exists "users can read own blocks" on public.app_blocks;
create policy "users can read own blocks"
on public.app_blocks
for select
to authenticated
using (
  blocker_id::text = private.captro_current_app_user_id()
  or blocked_id::text = private.captro_current_app_user_id()
);

drop policy if exists "users can create own blocks" on public.app_blocks;
create policy "users can create own blocks"
on public.app_blocks
for insert
to authenticated
with check (
  blocker_id::text = private.captro_current_app_user_id()
  and blocker_id::text <> blocked_id::text
);

drop policy if exists "users can delete own blocks" on public.app_blocks;
create policy "users can delete own blocks"
on public.app_blocks
for delete
to authenticated
using (blocker_id::text = private.captro_current_app_user_id());

drop policy if exists "users can read own notifications" on public.app_notifications;
create policy "users can read own notifications"
on public.app_notifications
for select
to authenticated
using (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can update own notifications" on public.app_notifications;
create policy "users can update own notifications"
on public.app_notifications
for update
to authenticated
using (user_id::text = private.captro_current_app_user_id())
with check (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can read own reports" on public.app_reports;
create policy "users can read own reports"
on public.app_reports
for select
to authenticated
using (reporter_id::text = private.captro_current_app_user_id());

drop policy if exists "users can create own reports" on public.app_reports;
create policy "users can create own reports"
on public.app_reports
for insert
to authenticated
with check (reporter_id::text = private.captro_current_app_user_id());

drop policy if exists "users can read own direct messages" on public.app_messages;
create policy "users can read own direct messages"
on public.app_messages
for select
to authenticated
using (
  (sender_id::text = private.captro_current_app_user_id() or receiver_id::text = private.captro_current_app_user_id())
  and private.captro_users_not_blocked(sender_id::text, receiver_id::text)
);

drop policy if exists "users can create own direct messages" on public.app_messages;
create policy "users can create own direct messages"
on public.app_messages
for insert
to authenticated
with check (
  sender_id::text = private.captro_current_app_user_id()
  and sender_id::text <> receiver_id::text
  and private.captro_users_not_blocked(sender_id::text, receiver_id::text)
);

drop policy if exists "users can update own direct messages" on public.app_messages;
create policy "users can update own direct messages"
on public.app_messages
for update
to authenticated
using (sender_id::text = private.captro_current_app_user_id() or receiver_id::text = private.captro_current_app_user_id())
with check (sender_id::text = private.captro_current_app_user_id() or receiver_id::text = private.captro_current_app_user_id());

drop policy if exists "group chats visible to members" on public.app_group_chats;
create policy "group chats visible to members"
on public.app_group_chats
for select
to authenticated
using (
  created_by::text = private.captro_current_app_user_id()
  or exists (
    select 1
    from public.app_group_chat_members m
    where m.group_id::text = app_group_chats.id::text
      and m.user_id::text = private.captro_current_app_user_id()
  )
);

drop policy if exists "users can create group chats" on public.app_group_chats;
create policy "users can create group chats"
on public.app_group_chats
for insert
to authenticated
with check (created_by::text = private.captro_current_app_user_id());

drop policy if exists "group members visible to members" on public.app_group_chat_members;
create policy "group members visible to members"
on public.app_group_chat_members
for select
to authenticated
using (
  user_id::text = private.captro_current_app_user_id()
  or exists (
    select 1
    from public.app_group_chat_members self
    where self.group_id::text = app_group_chat_members.group_id::text
      and self.user_id::text = private.captro_current_app_user_id()
  )
);

drop policy if exists "users can join allowed group member rows" on public.app_group_chat_members;
create policy "users can join allowed group member rows"
on public.app_group_chat_members
for insert
to authenticated
with check (user_id::text = private.captro_current_app_user_id());

drop policy if exists "group messages visible to members" on public.app_group_messages;
create policy "group messages visible to members"
on public.app_group_messages
for select
to authenticated
using (
  exists (
    select 1
    from public.app_group_chat_members m
    where m.group_id::text = app_group_messages.group_id::text
      and m.user_id::text = private.captro_current_app_user_id()
  )
);

drop policy if exists "members can send group messages" on public.app_group_messages;
create policy "members can send group messages"
on public.app_group_messages
for insert
to authenticated
with check (
  sender_id::text = private.captro_current_app_user_id()
  and exists (
    select 1
    from public.app_group_chat_members m
    where m.group_id::text = app_group_messages.group_id::text
      and m.user_id::text = private.captro_current_app_user_id()
  )
);

drop policy if exists "users can read visible post places" on public.app_post_places;
create policy "users can read visible post places"
on public.app_post_places
for select
to authenticated
using (
  exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id::text = app_post_places.legacy_post_id::text
      and (
        p.app_user_id::text = private.captro_current_app_user_id()
        or (
          p.status = 'active'
          and p.visibility = 'public'
          and private.captro_users_not_blocked(private.captro_current_app_user_id(), p.app_user_id::text)
        )
      )
  )
);

drop policy if exists "users can manage own post places" on public.app_post_places;
create policy "users can manage own post places"
on public.app_post_places
for all
to authenticated
using (
  exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id::text = app_post_places.legacy_post_id::text
      and p.app_user_id::text = private.captro_current_app_user_id()
  )
)
with check (
  exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id::text = app_post_places.legacy_post_id::text
      and p.app_user_id::text = private.captro_current_app_user_id()
  )
);

drop policy if exists "users can read own media assets" on public.app_media_assets;
create policy "users can read own media assets"
on public.app_media_assets
for select
to authenticated
using (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can create own media assets" on public.app_media_assets;
create policy "users can create own media assets"
on public.app_media_assets
for insert
to authenticated
with check (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can update own media assets before publish" on public.app_media_assets;
create policy "users can update own media assets before publish"
on public.app_media_assets
for update
to authenticated
using (user_id::text = private.captro_current_app_user_id())
with check (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can manage own push tokens" on public.app_push_tokens;
create policy "users can manage own push tokens"
on public.app_push_tokens
for all
to authenticated
using (user_id::text = private.captro_current_app_user_id())
with check (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can read own account identities" on public.app_account_identities;
create policy "users can read own account identities"
on public.app_account_identities
for select
to authenticated
using (user_id::text = private.captro_current_app_user_id());

drop policy if exists "normal users cannot access moderation results" on public.app_moderation_results;
create policy "normal users cannot access moderation results"
on public.app_moderation_results
for all
to anon, authenticated
using (false)
with check (false);

drop policy if exists "normal users cannot access admin roles" on public.app_admin_roles;
create policy "normal users cannot access admin roles"
on public.app_admin_roles
for all
to anon, authenticated
using (false)
with check (false);

drop policy if exists "normal users cannot access moderation actions" on public.app_moderation_actions;
create policy "normal users cannot access moderation actions"
on public.app_moderation_actions
for all
to anon, authenticated
using (false)
with check (false);

drop policy if exists "normal users cannot access audit logs" on public.app_audit_logs;
create policy "normal users cannot access audit logs"
on public.app_audit_logs
for all
to anon, authenticated
using (false)
with check (false);

do $$
begin
  if to_regclass('public.production_reset_events') is not null then
    execute 'alter table public.production_reset_events enable row level security';
    execute 'drop policy if exists "normal users cannot access production reset events" on public.production_reset_events';
    execute 'create policy "normal users cannot access production reset events"
      on public.production_reset_events
      for all
      to anon, authenticated
      using (false)
      with check (false)';
  end if;
end $$;

alter function public.set_captro_updated_at() set search_path = public;

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'touch_updated_at'
      and pg_get_function_identity_arguments(p.oid) = ''
  ) then
    execute 'alter function public.touch_updated_at() set search_path = public';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'handle_new_auth_user'
      and pg_get_function_identity_arguments(p.oid) = ''
  ) then
    execute 'revoke execute on function public.handle_new_auth_user() from anon, authenticated, public';
  end if;
end $$;

comment on function private.captro_current_app_user_id() is 'Returns the current Supabase-authenticated Captro app user id for RLS policies.';
comment on function private.captro_users_not_blocked(text, text) is 'RLS helper that hides content/messages where either side blocked the other.';
