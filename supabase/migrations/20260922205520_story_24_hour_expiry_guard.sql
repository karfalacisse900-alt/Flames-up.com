-- Existing status records are capped at the same 24-hour lifetime as new posts.
update public.app_stories
set expires_at = least(expires_at, created_at + interval '24 hours')
where expires_at > created_at + interval '24 hours';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'app_stories_max_24h'
  ) then
    alter table public.app_stories
      add constraint app_stories_max_24h
      check (expires_at <= created_at + interval '24 hours');
  end if;
end $$;

drop policy if exists "stories cannot outlive 24 hours" on public.app_stories;
create policy "stories cannot outlive 24 hours"
on public.app_stories
as restrictive
for select
to authenticated
using (created_at > now() - interval '24 hours');
