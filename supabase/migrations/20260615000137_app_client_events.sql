-- Supabase-primary production telemetry for safe app/client events.
-- This replaces persistent D1 client_events use when Supabase is the database.

create table if not exists public.app_client_events (
  id text primary key,
  user_id text,
  event_name text not null,
  category text not null default '',
  status text not null default '',
  duration_ms integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  app_version text not null default '',
  platform text not null default 'ios',
  created_at timestamptz not null default now()
);

create index if not exists app_client_events_name_created_idx
  on public.app_client_events (event_name, created_at desc);

create index if not exists app_client_events_user_created_idx
  on public.app_client_events (user_id, created_at desc)
  where user_id is not null;

alter table public.app_client_events enable row level security;

grant insert on public.app_client_events to authenticated;

drop policy if exists "users can insert own client events" on public.app_client_events;
create policy "users can insert own client events"
on public.app_client_events
for insert
to authenticated
with check (
  user_id is null
  or user_id = ''
  or user_id::text = (select private.captro_current_app_user_id())
);

drop policy if exists "normal users cannot read client events" on public.app_client_events;
create policy "normal users cannot read client events"
on public.app_client_events
for select
to authenticated
using (false);

comment on table public.app_client_events is 'Production-safe client telemetry written through the Worker. No secrets or private message bodies.';
