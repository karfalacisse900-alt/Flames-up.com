-- Optimize Supabase RLS policies that were re-evaluating auth/helper calls for
-- every row. This keeps the same access model but wraps stable auth functions
-- in SELECT subqueries so Postgres can evaluate them once per statement.

create schema if not exists extensions;
alter extension citext set schema extensions;

create or replace function private.captro_current_app_user_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select u.id::text
  from public.app_users u
  where u.supabase_user_id = (select auth.uid())
  limit 1
$$;

drop policy if exists "users can read active profiles and own profile" on public.app_users;
create policy "users can read active profiles and own profile"
on public.app_users
for select
to authenticated
using (
  supabase_user_id::text = (select auth.uid())::text
  or coalesce(metadata->>'status', 'active') = 'active'
);

drop policy if exists "users can insert own profile" on public.app_users;
create policy "users can insert own profile"
on public.app_users
for insert
to authenticated
with check (supabase_user_id::text = (select auth.uid())::text);

drop policy if exists "users can update own profile" on public.app_users;
create policy "users can update own profile"
on public.app_users
for update
to authenticated
using (supabase_user_id::text = (select auth.uid())::text)
with check (supabase_user_id::text = (select auth.uid())::text);

drop policy if exists "users can insert own posts" on public.app_posts;
create policy "users can insert own posts"
on public.app_posts
for insert
to authenticated
with check (
  app_user_id::text = (select private.captro_current_app_user_id())
  and (user_id is null or user_id::text = (select auth.uid())::text)
);

drop policy if exists "users can insert own comments" on public.post_comments;
create policy "users can insert own comments"
on public.post_comments
for insert
to authenticated
with check (
  app_user_id::text = (select private.captro_current_app_user_id())
  and (user_id is null or user_id::text = (select auth.uid())::text)
  and exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id::text = post_comments.legacy_post_id::text
      and p.status = 'active'
      and (
        p.app_user_id::text = (select private.captro_current_app_user_id())
        or (
          p.visibility = 'public'
          and private.captro_users_not_blocked(
            (select private.captro_current_app_user_id()),
            p.app_user_id::text
          )
        )
      )
  )
);

drop policy if exists "users can read own interactions" on public.app_post_interactions;
create policy "users can read own interactions"
on public.app_post_interactions
for select
to authenticated
using (
  app_user_id::text = (select private.captro_current_app_user_id())
  or user_id::text = (select auth.uid())::text
);

drop policy if exists "users can insert own interactions" on public.app_post_interactions;
create policy "users can insert own interactions"
on public.app_post_interactions
for insert
to authenticated
with check (
  kind in ('like', 'save')
  and (
    app_user_id::text = (select private.captro_current_app_user_id())
    or user_id::text = (select auth.uid())::text
  )
);

drop policy if exists "users can delete own interactions" on public.app_post_interactions;
create policy "users can delete own interactions"
on public.app_post_interactions
for delete
to authenticated
using (
  app_user_id::text = (select private.captro_current_app_user_id())
  or user_id::text = (select auth.uid())::text
);

drop policy if exists "public documents or own documents are readable" on public.app_documents;
create policy "public documents or own documents are readable"
on public.app_documents
for select
to public
using (
  visibility = 'public'
  or owner_id = (select auth.uid())
);

do $$
begin
  if to_regclass('public.profiles') is not null then
    execute 'drop policy if exists "users can insert own profile" on public.profiles';
    execute 'create policy "users can insert own profile"
      on public.profiles
      for insert
      to public
      with check ((select auth.uid()) = id)';

    execute 'drop policy if exists "users can update own profile" on public.profiles';
    execute 'create policy "users can update own profile"
      on public.profiles
      for update
      to public
      using ((select auth.uid()) = id)
      with check ((select auth.uid()) = id)';
  end if;

  if to_regclass('public.post_interactions') is not null then
    execute 'drop policy if exists "users can create own interactions" on public.post_interactions';
    execute 'create policy "users can create own interactions"
      on public.post_interactions
      for insert
      to public
      with check ((select auth.uid()) = user_id)';

    execute 'drop policy if exists "users can delete own interactions" on public.post_interactions';
    execute 'create policy "users can delete own interactions"
      on public.post_interactions
      for delete
      to public
      using ((select auth.uid()) = user_id)';
  end if;

  if to_regclass('public.follows') is not null then
    execute 'drop policy if exists "users can create own follows" on public.follows';
    execute 'create policy "users can create own follows"
      on public.follows
      for insert
      to public
      with check ((select auth.uid()) = follower_id)';

    execute 'drop policy if exists "users can delete own follows" on public.follows';
    execute 'create policy "users can delete own follows"
      on public.follows
      for delete
      to public
      using ((select auth.uid()) = follower_id)';
  end if;
end $$;
