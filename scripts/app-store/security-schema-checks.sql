-- Read-only release prerequisite. No application rows or credentials are read.
-- Effective privileges include inherited/PUBLIC and explicit column grants.
with
required_tables(name) as (values
  ('app_users'), ('app_posts'), ('post_comments'), ('app_messages'),
  ('app_group_chats'), ('app_group_chat_members'), ('app_group_messages'),
  ('app_media_assets'), ('app_push_tokens'), ('app_admin_roles'),
  ('app_purchases'), ('app_payments'), ('app_entitlements'), ('app_payment_webhook_events')
),
objects as (
  select name, pg_catalog.to_regclass('public.' || name) as oid from required_tables
),
clients(name) as (values ('anon'), ('authenticated')),
write_tables as (
  select * from objects where name not in ('app_purchases', 'app_payments', 'app_entitlements', 'app_payment_webhook_events')
),
identity_fn as (
  select p.* from pg_catalog.pg_proc p
  where p.oid = pg_catalog.to_regprocedure('private.captro_current_app_user_id()')
),
group_fn as (
  select p.* from pg_catalog.pg_proc p
  where p.oid = pg_catalog.to_regprocedure('private.captro_is_group_member(text)')
),
push_fn as (
  select p.* from pg_catalog.pg_proc p
  where p.oid = pg_catalog.to_regprocedure('public.captro_register_push_token(text,text,text,text,text,text,text)')
),
checks(check_id, passed) as (
  select 'migration_' || v.version, exists (
    select 1 from supabase_migrations.schema_migrations m where m.version = v.version
  ) from (values ('20261006012846'), ('20261013154326'), ('20261013154328')) v(version)
  union all
  select 'required_tables_exist', not exists (select 1 from objects where oid is null)
  union all
  select 'client_writes_denied', not exists (
    select 1 from write_tables t cross join clients r
    where t.oid is null
      or pg_catalog.has_table_privilege(r.name, t.oid, 'INSERT,UPDATE,DELETE')
      or pg_catalog.has_any_column_privilege(r.name, t.oid, 'INSERT,UPDATE,REFERENCES')
  )
  union all
  select 'private_columns_unreadable', not exists (
    select 1 from objects t cross join clients r
    where t.name in ('app_users', 'app_admin_roles', 'app_push_tokens')
      and (t.oid is null or pg_catalog.has_any_column_privilege(r.name, t.oid, 'SELECT'))
  )
  union all
  select 'client_ddl_privileges_denied', not exists (
    select 1 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    cross join clients r where n.nspname = 'public' and c.relkind in ('r', 'p')
      and (pg_catalog.has_table_privilege(r.name, c.oid, 'TRUNCATE,REFERENCES,TRIGGER')
        or pg_catalog.has_any_column_privilege(r.name, c.oid, 'REFERENCES'))
  )
  union all
  select 'required_rls_enabled', not exists (
    select 1 from objects t left join pg_catalog.pg_class c on c.oid = t.oid
    where not coalesce(c.relrowsecurity, false)
  )
  union all
  select 'identity_helper_active_only', exists (
    select 1 from identity_fn p where p.prosecdef
      and 'search_path=""' = any(p.proconfig)
      and position('auth.uid()' in p.prosrc) > 0
      and position('coalesce(u.metadata->>''status'',''active'')=''active''' in regexp_replace(p.prosrc, '\s+', '', 'g')) > 0
      and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
  )
  union all
  select 'group_helper_private', exists (
    select 1 from group_fn p where p.prosecdef
      and 'search_path=""' = any(p.proconfig)
      and position('private.captro_current_app_user_id()' in p.prosrc) > 0
      and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
  )
  union all
  select 'group_select_policies', not exists (
    select 1 from (values ('app_group_chats', 'id'), ('app_group_chat_members', 'group_id'), ('app_group_messages', 'group_id')) t(name, column_name)
    where (select count(*) from pg_catalog.pg_policies p
      where p.schemaname = 'public' and p.tablename = t.name and p.cmd in ('ALL', 'SELECT')) <> 1
      or not exists (
        select 1 from pg_catalog.pg_policies p where p.schemaname = 'public' and p.tablename = t.name
          and p.cmd = 'SELECT' and p.roles = array['authenticated']::name[]
          and regexp_replace(p.qual, '[\s()]', '', 'g') in (
            'private.captro_is_group_member' || t.column_name || '::text',
            'private.captro_is_group_member' || t.column_name
          )
      )
  )
  union all
  select 'push_rpc_service_only', exists (
    select 1 from push_fn p where not p.prosecdef and 'search_path=""' = any(p.proconfig)
      and pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
  )
  union all
  select 'push_unique_active_owner', exists (
    select 1 from pg_catalog.pg_index i
    join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
    where i.indrelid = pg_catalog.to_regclass('public.app_push_tokens')
      and i.indisunique and i.indisvalid and i.indisready and i.indnkeyatts = 1
      and a.attname = 'token_hash'
      and pg_catalog.pg_get_expr(i.indpred, i.indrelid) = 'is_active'
  )
  union all
  select 'payment_tables_server_only', not exists (
    select 1 from objects t cross join clients r
    where t.name in ('app_purchases', 'app_payments', 'app_entitlements', 'app_payment_webhook_events')
      and (t.oid is null or pg_catalog.has_table_privilege(r.name, t.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        or pg_catalog.has_any_column_privilege(r.name, t.oid, 'SELECT,INSERT,UPDATE,REFERENCES'))
  )
)
select check_id, coalesce(passed, false) as passed from checks order by check_id;
