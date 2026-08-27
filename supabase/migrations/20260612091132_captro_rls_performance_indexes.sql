-- Advisor-driven indexes for RLS-heavy relationship lookups.
-- Column checks keep this safe across the legacy/text and native/UUID transition.

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'app_follows' and column_name = 'follower_id'
  ) then
    execute 'create index if not exists app_follows_follower_id_idx on public.app_follows (follower_id)';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'app_follows' and column_name = 'following_id'
  ) then
    execute 'create index if not exists app_follows_following_id_idx on public.app_follows (following_id)';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'app_follows' and column_name = 'app_follower_id'
  ) then
    execute 'create index if not exists app_follows_app_follower_id_idx on public.app_follows (app_follower_id)';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'app_follows' and column_name = 'app_following_id'
  ) then
    execute 'create index if not exists app_follows_app_following_id_idx on public.app_follows (app_following_id)';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'app_post_interactions' and column_name = 'user_id'
  ) then
    execute 'create index if not exists app_post_interactions_user_id_idx on public.app_post_interactions (user_id) where user_id is not null';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'post_comments' and column_name = 'parent_id'
  ) then
    execute 'create index if not exists post_comments_parent_id_idx on public.post_comments (parent_id) where parent_id is not null';
  end if;
end $$;
