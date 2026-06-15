-- Captro protected production data reset for Supabase Postgres.
--
-- Purpose:
--   Remove test/demo/user-generated data before App Store review or public launch
--   while keeping schemas, migrations, configuration, and optional owner/admin
--   accounts intact.
--
-- Required safety gates:
--   SET app.reset_environment = 'production';
--   SET app.confirm_production_reset = 'CONFIRM_PRODUCTION_RESET';
--   SET app.reset_mode = 'dry_run'; -- or 'execute'
--
-- Optional keep lists:
--   SET app.keep_emails = 'owner@example.com,reviewer@example.com';
--   SET app.keep_auth_user_ids = 'uuid-1,uuid-2';
--
-- Run dry-run first. Only run execute after a database backup exists.

begin;

create table if not exists public.production_reset_events (
  id uuid primary key default gen_random_uuid(),
  mode text not null,
  table_name text not null,
  rows_affected bigint not null default 0,
  created_at timestamptz not null default now()
);

do $$
declare
  reset_environment text := coalesce(current_setting('app.reset_environment', true), '');
  confirmation text := coalesce(current_setting('app.confirm_production_reset', true), '');
begin
  if reset_environment <> 'production' then
    raise exception 'Refusing reset: SET app.reset_environment = production is required.';
  end if;

  if confirmation <> 'CONFIRM_PRODUCTION_RESET' then
    raise exception 'Refusing reset: SET app.confirm_production_reset = CONFIRM_PRODUCTION_RESET is required.';
  end if;
end $$;

do $$
declare
  reset_mode text := coalesce(current_setting('app.reset_mode', true), 'dry_run');
  keep_emails text[] := string_to_array(lower(replace(coalesce(current_setting('app.keep_emails', true), ''), ' ', '')), ',');
  keep_auth_user_ids text[] := string_to_array(replace(coalesce(current_setting('app.keep_auth_user_ids', true), ''), ' ', ''), ',');
  table_names text[] := array[
    'app_story_thoughts',
    'app_story_views',
    'app_story_likes',
    'app_stories',
    'app_favorite_sounds',
    'app_hidden_sounds',
    'app_client_events',
    'post_comment_likes',
    'app_moderation_results',
    'app_moderation_jobs',
    'app_moderation_events',
    'app_media_assets',
    'app_moderation_actions',
    'app_audit_logs',
    'app_reports',
    'app_notifications',
    'app_push_tokens',
    'app_account_verification_tokens',
    'app_group_messages',
    'app_group_chat_members',
    'app_group_chats',
    'app_messages',
    'app_friendships',
    'app_friend_requests',
    'app_blocks',
    'app_post_places',
    'post_comments',
    'app_post_interactions',
    'app_follows',
    'app_documents',
    'app_posts'
  ];
  table_name text;
  affected bigint;
begin
  if reset_mode not in ('dry_run', 'execute') then
    raise exception 'Invalid app.reset_mode: %. Use dry_run or execute.', reset_mode;
  end if;

  foreach table_name in array table_names loop
    if to_regclass('public.' || table_name) is null then
      insert into public.production_reset_events(mode, table_name, rows_affected)
      values (reset_mode, table_name || ' (missing)', 0);
      continue;
    end if;

    if reset_mode = 'dry_run' then
      execute format('select count(*) from public.%I', table_name) into affected;
    else
      execute format('delete from public.%I', table_name);
      get diagnostics affected = row_count;
    end if;

    insert into public.production_reset_events(mode, table_name, rows_affected)
    values (reset_mode, table_name, affected);
  end loop;

  keep_emails := array_remove(keep_emails, '');
  keep_auth_user_ids := array_remove(keep_auth_user_ids, '');

  create temporary table if not exists captro_reset_keep_users(id text primary key) on commit drop;
  truncate table captro_reset_keep_users;

  if to_regclass('public.app_users') is not null then
    insert into captro_reset_keep_users(id)
    select distinct u.id
    from public.app_users u
    where (coalesce(lower(u.email), '') = any(keep_emails))
       or (u.supabase_user_id::text = any(keep_auth_user_ids))
    on conflict do nothing;

    if to_regclass('auth.users') is not null then
      insert into captro_reset_keep_users(id)
      select distinct u.id
      from public.app_users u
      join auth.users au on au.id = u.supabase_user_id
      where coalesce(lower(au.email), '') = any(keep_emails)
         or au.id::text = any(keep_auth_user_ids)
      on conflict do nothing;
    end if;

    if to_regclass('public.app_account_identities') is not null then
      if reset_mode = 'dry_run' then
        select count(*) into affected
        from public.app_account_identities i
        where not exists (select 1 from captro_reset_keep_users keep where keep.id = i.user_id);
      else
        delete from public.app_account_identities i
        where not exists (select 1 from captro_reset_keep_users keep where keep.id = i.user_id);
        get diagnostics affected = row_count;
      end if;

      insert into public.production_reset_events(mode, table_name, rows_affected)
      values (reset_mode, 'app_account_identities', affected);
    else
      insert into public.production_reset_events(mode, table_name, rows_affected)
      values (reset_mode, 'app_account_identities (missing)', 0);
    end if;

    if reset_mode = 'dry_run' then
      select count(*) into affected
      from public.app_users u
      where not exists (select 1 from captro_reset_keep_users keep where keep.id = u.id);
    else
      delete from public.app_users u
      where not exists (select 1 from captro_reset_keep_users keep where keep.id = u.id);
      get diagnostics affected = row_count;
    end if;

    insert into public.production_reset_events(mode, table_name, rows_affected)
    values (reset_mode, 'app_users', affected);
  else
    insert into public.production_reset_events(mode, table_name, rows_affected)
    values (reset_mode, 'app_users (missing)', 0);
  end if;
end $$;

do $$
declare
  reset_mode text := coalesce(current_setting('app.reset_mode', true), 'dry_run');
  keep_emails text[] := string_to_array(lower(replace(coalesce(current_setting('app.keep_emails', true), ''), ' ', '')), ',');
  keep_auth_user_ids text[] := string_to_array(replace(coalesce(current_setting('app.keep_auth_user_ids', true), ''), ' ', ''), ',');
  affected bigint := 0;
begin
  if to_regclass('auth.users') is null then
    insert into public.production_reset_events(mode, table_name, rows_affected)
    values (reset_mode, 'auth.users (missing)', 0);
    return;
  end if;

  keep_emails := array_remove(keep_emails, '');
  keep_auth_user_ids := array_remove(keep_auth_user_ids, '');

  if reset_mode = 'dry_run' then
    select count(*) into affected
    from auth.users u
    where not (coalesce(lower(u.email), '') = any(keep_emails))
      and not (u.id::text = any(keep_auth_user_ids));
  else
    delete from auth.users u
    where not (coalesce(lower(u.email), '') = any(keep_emails))
      and not (u.id::text = any(keep_auth_user_ids));
    get diagnostics affected = row_count;
  end if;

  insert into public.production_reset_events(mode, table_name, rows_affected)
  values (reset_mode, 'auth.users', affected);
end $$;

select mode, table_name, rows_affected, created_at
from public.production_reset_events
order by created_at desc, table_name asc
limit 100;

commit;
