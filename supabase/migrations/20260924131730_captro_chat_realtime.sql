-- Realtime is only a notification channel. Captro continues to load message
-- contents through the authorized Worker cursor API and reconciles on resume.
-- Existing SELECT RLS policies limit Postgres Changes to conversation members.
grant select on public.app_messages, public.app_group_messages to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'app_messages'
  ) then
    alter publication supabase_realtime add table public.app_messages;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'app_group_messages'
  ) then
    alter publication supabase_realtime add table public.app_group_messages;
  end if;
end $$;
