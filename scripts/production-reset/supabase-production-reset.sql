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
  table_names text[] := array[
    'app_moderation_results',
    'app_media_assets',
    'app_moderation_actions',
    'app_audit_logs',
    'app_reports',
    'app_notifications',
    'app_push_tokens',
    'app_group_messages',
    'app_group_chat_members',
    'app_group_chats',
    'app_messages',
    'app_blocks',
    'app_post_places',
    'post_comments',
    'app_post_interactions',
    'app_follows',
    'app_documents',
    'app_posts',
    'app_account_identities',
    'app_users'
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
