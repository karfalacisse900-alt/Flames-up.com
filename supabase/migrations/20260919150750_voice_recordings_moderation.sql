-- Captro recorded voice: private, immutable submissions with version-bound moderation.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'captro-voice-private',
  'captro-voice-private',
  false,
  12582912,
  array['audio/mp4', 'audio/x-m4a', 'audio/m4a', 'audio/aac', 'audio/mpeg', 'audio/wav']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.app_voice_recordings (
  id uuid primary key default gen_random_uuid(),
  owner_app_user_id text not null,
  target_type text not null check (target_type in ('post', 'reply')),
  target_id text,
  parent_post_id text,
  parent_comment_id text,
  storage_bucket text not null default 'captro-voice-private',
  storage_object text not null,
  storage_version text not null,
  audio_sha256 text not null check (length(audio_sha256) = 64),
  verified_duration_ms integer not null check (verified_duration_ms > 0),
  byte_size integer not null check (byte_size > 0),
  verified_format text not null,
  waveform jsonb,
  machine_transcript text,
  display_transcript text,
  proposed_transcript text,
  detected_languages text[] not null default '{}',
  processing_state text not null default 'queued'
    check (processing_state in ('uploading', 'queued', 'transcribing', 'screening', 'completed', 'failed')),
  moderation_state text not null default 'pending'
    check (moderation_state in ('pending', 'approved', 'needs_review', 'rejected')),
  publication_state text not null default 'draft'
    check (publication_state in ('draft', 'published', 'removed', 'deleted')),
  content_version integer not null default 1 check (content_version > 0),
  approved_content_version integer,
  caption_snapshot text not null default '',
  transcript_model text,
  moderation_model text,
  context_model text,
  policy_version text not null,
  decision_reason text,
  moderation_evidence jsonb not null default '{}'::jsonb,
  disclosure_version text not null,
  disclosure_accepted_at timestamptz not null,
  submitted_at timestamptz not null default now(),
  review_requested_at timestamptz,
  reviewed_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (storage_bucket, storage_object),
  unique (id, content_version)
);

create index if not exists app_voice_recordings_owner_idx
  on public.app_voice_recordings (owner_app_user_id, created_at desc);
create index if not exists app_voice_recordings_target_idx
  on public.app_voice_recordings (target_type, target_id)
  where target_id is not null and publication_state <> 'deleted';
create index if not exists app_voice_recordings_review_idx
  on public.app_voice_recordings (moderation_state, submitted_at)
  where moderation_state = 'needs_review';

create table if not exists public.app_voice_processing_jobs (
  id uuid primary key default gen_random_uuid(),
  voice_id uuid not null references public.app_voice_recordings(id) on delete cascade,
  content_version integer not null,
  status text not null default 'queued'
    check (status in ('queued', 'running', 'retry', 'completed', 'failed', 'cancelled')),
  attempts integer not null default 0,
  max_attempts integer not null default 4,
  run_after timestamptz not null default now(),
  locked_at timestamptz,
  heartbeat_at timestamptz,
  completed_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (voice_id, content_version)
);

create index if not exists app_voice_jobs_ready_idx
  on public.app_voice_processing_jobs (run_after, created_at)
  where status in ('queued', 'retry');
create index if not exists app_voice_jobs_stale_idx
  on public.app_voice_processing_jobs (heartbeat_at)
  where status = 'running';

create table if not exists public.app_voice_reviews (
  id uuid primary key default gen_random_uuid(),
  voice_id uuid not null references public.app_voice_recordings(id) on delete cascade,
  content_version integer not null,
  action text not null check (action in ('approve', 'reject', 'remove', 'appeal_requested', 'appeal_resolved')),
  actor_app_user_id text,
  actor_role text not null,
  reason_code text,
  note text,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists app_voice_reviews_voice_idx
  on public.app_voice_reviews (voice_id, created_at desc);

alter table public.app_voice_recordings enable row level security;
alter table public.app_voice_processing_jobs enable row level security;
alter table public.app_voice_reviews enable row level security;

revoke all on public.app_voice_recordings from anon, authenticated;
revoke all on public.app_voice_processing_jobs from anon, authenticated;
revoke all on public.app_voice_reviews from anon, authenticated;

drop trigger if exists app_voice_recordings_set_updated_at on public.app_voice_recordings;
create trigger app_voice_recordings_set_updated_at
before update on public.app_voice_recordings
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_voice_processing_jobs_set_updated_at on public.app_voice_processing_jobs;
create trigger app_voice_processing_jobs_set_updated_at
before update on public.app_voice_processing_jobs
for each row execute function public.set_captro_updated_at();

create or replace function public.captro_publish_voice_version(
  p_voice_id uuid,
  p_content_version integer
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v public.app_voice_recordings%rowtype;
begin
  select * into v
  from public.app_voice_recordings
  where id = p_voice_id
  for update;

  if not found
    or v.content_version <> p_content_version
    or v.approved_content_version <> p_content_version
    or v.processing_state <> 'completed'
    or v.moderation_state <> 'approved'
    or v.publication_state in ('removed', 'deleted') then
    return false;
  end if;

  if v.target_type = 'post' then
    update public.app_posts
      set status = 'active',
          metadata = jsonb_set(
            coalesce(metadata, '{}'::jsonb),
            '{voice}',
            jsonb_build_object('id', v.id, 'version', v.content_version, 'duration_ms', v.verified_duration_ms),
            true
          ),
          updated_at = now()
      where (legacy_post_id = v.target_id or id::text = v.target_id)
        and status = 'pending_voice';
  else
    update public.post_comments
      set status = 'active',
          metadata = jsonb_set(
            coalesce(metadata, '{}'::jsonb),
            '{voice}',
            jsonb_build_object('id', v.id, 'version', v.content_version, 'duration_ms', v.verified_duration_ms),
            true
          ),
          updated_at = now()
      where (legacy_comment_id = v.target_id or id::text = v.target_id)
        and status = 'pending_voice';
  end if;

  if not found then return false; end if;

  update public.app_voice_recordings
    set publication_state = 'published', updated_at = now()
    where id = p_voice_id and content_version = p_content_version;
  return true;
end;
$$;

revoke all on function public.captro_publish_voice_version(uuid, integer) from public, anon, authenticated;
grant execute on function public.captro_publish_voice_version(uuid, integer) to service_role;
