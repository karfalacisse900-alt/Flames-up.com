create table if not exists public.app_moderation_jobs (
  id text primary key,
  media_id text not null references public.app_media_assets(id) on delete cascade,
  user_id text not null,
  job_type text not null default 'media_pre_publish',
  status text not null default 'pending',
  attempts integer not null default 0,
  queued_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  last_error text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_moderation_jobs_status_idx
  on public.app_moderation_jobs (status, queued_at desc);

create index if not exists app_moderation_jobs_media_idx
  on public.app_moderation_jobs (media_id, created_at desc);

create table if not exists public.app_moderation_events (
  id text primary key,
  media_id text not null references public.app_media_assets(id) on delete cascade,
  actor_user_id text,
  actor_role text,
  event_type text not null,
  decision text,
  reason text,
  note text,
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  request_id text,
  created_at timestamptz not null default now()
);

create index if not exists app_moderation_events_media_created_idx
  on public.app_moderation_events (media_id, created_at desc);

create index if not exists app_media_assets_storage_idx
  on public.app_media_assets (storage_provider, storage_key);

create index if not exists app_media_assets_post_idx
  on public.app_media_assets (legacy_post_id);

drop trigger if exists app_moderation_jobs_set_updated_at on public.app_moderation_jobs;
create trigger app_moderation_jobs_set_updated_at
before update on public.app_moderation_jobs
for each row execute function public.set_captro_updated_at();

alter table public.app_moderation_jobs enable row level security;
alter table public.app_moderation_events enable row level security;

drop policy if exists "normal users cannot access moderation jobs" on public.app_moderation_jobs;
create policy "normal users cannot access moderation jobs"
on public.app_moderation_jobs
for all
to anon, authenticated
using (false)
with check (false);

drop policy if exists "normal users cannot access moderation events" on public.app_moderation_events;
create policy "normal users cannot access moderation events"
on public.app_moderation_events
for all
to anon, authenticated
using (false)
with check (false);

grant select, insert, update, delete on public.app_moderation_jobs to authenticated;
grant select, insert, update, delete on public.app_moderation_events to authenticated;
