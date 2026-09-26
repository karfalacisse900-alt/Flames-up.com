-- Captures stay visible for fourteen days unless a linked activity ends sooner.
alter table public.app_stories drop constraint if exists app_stories_max_24h;
alter table public.app_stories add constraint app_stories_max_14d
  check (expires_at <= created_at + interval '14 days');

drop policy if exists "stories cannot outlive 24 hours" on public.app_stories;
create policy "stories cannot outlive 14 days" on public.app_stories
as restrictive for select to authenticated
using (created_at > now() - interval '14 days');

-- Recover recent approved captures shortened by the previous blanket 24h cap.
-- Keep removed/expired records and shorter Event/Meetup windows untouched.
update public.app_stories
set expires_at = created_at + interval '14 days', updated_at = now()
where status = 'active'
  and created_at > now() - interval '14 days'
  and expires_at between created_at + interval '23 hours 59 minutes'
                     and created_at + interval '24 hours'
  and coalesce(metadata->'linked_item'->>'type', '') not in ('event', 'meetup');
