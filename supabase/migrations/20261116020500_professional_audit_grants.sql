-- Supabase default privileges can include DELETE/TRUNCATE even when a migration
-- only explicitly grants SELECT/INSERT/UPDATE. Reset the audit ACL completely.
begin;
revoke all on public.app_professional_audit from public,anon,authenticated,service_role;
grant select,insert on public.app_professional_audit to service_role;
commit;
