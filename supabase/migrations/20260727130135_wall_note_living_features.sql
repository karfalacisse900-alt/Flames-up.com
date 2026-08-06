-- Captro Wall of Notes living-note capabilities.
-- This migration is additive: existing notes and replies remain readable.

create schema if not exists private;

alter table public.wall_notes
  add column if not exists note_type text not null default 'text',
  add column if not exists back_body text,
  add column if not exists back_color_token text,
  add column if not exists back_style_token text,
  add column if not exists allow_contributions boolean not null default false,
  add column if not exists signature_count integer not null default 0,
  add column if not exists contribution_count integer not null default 0,
  add column if not exists voice_media_id text references public.app_media_assets(id) on delete set null,
  add column if not exists voice_duration_seconds double precision,
  add column if not exists voice_waveform jsonb not null default '[]'::jsonb,
  add column if not exists location_label text,
  add column if not exists location_city text,
  add column if not exists location_country text,
  add column if not exists location_cell text,
  add column if not exists location_lat_bucket double precision,
  add column if not exists location_lng_bucket double precision,
  add column if not exists location_visibility boolean not null default false;

alter table public.wall_notes
  drop constraint if exists wall_notes_body_check,
  drop constraint if exists wall_notes_note_type_check,
  drop constraint if exists wall_notes_back_body_check,
  drop constraint if exists wall_notes_signature_count_check,
  drop constraint if exists wall_notes_contribution_count_check,
  drop constraint if exists wall_notes_voice_duration_check,
  drop constraint if exists wall_notes_voice_shape_check,
  drop constraint if exists wall_notes_location_shape_check;

alter table public.wall_notes
  add constraint wall_notes_note_type_check
    check (note_type in ('text', 'photo', 'voice')),
  add constraint wall_notes_body_check
    check (
      char_length(body) <= 300
      and (note_type = 'voice' or char_length(body) >= 1)
    ),
  add constraint wall_notes_back_body_check
    check (back_body is null or char_length(back_body) between 1 and 300),
  add constraint wall_notes_signature_count_check
    check (signature_count >= 0),
  add constraint wall_notes_contribution_count_check
    check (contribution_count >= 0),
  add constraint wall_notes_voice_duration_check
    check (voice_duration_seconds is null or voice_duration_seconds between 0.25 and 60),
  add constraint wall_notes_voice_shape_check
    check (
      jsonb_typeof(voice_waveform) = 'array'
      and jsonb_array_length(voice_waveform) <= 48
      and (
      (note_type = 'voice' and voice_media_id is not null and voice_duration_seconds is not null)
      or
      (note_type <> 'voice' and voice_media_id is null and voice_duration_seconds is null)
      )
    ),
  add constraint wall_notes_location_shape_check
    check (
      location_visibility = false
      or (
        location_label is not null
        and location_cell is not null
        and location_lat_bucket between -90 and 90
        and location_lng_bucket between -180 and 180
      )
    );

create index if not exists wall_notes_voice_media_idx
  on public.wall_notes (voice_media_id)
  where voice_media_id is not null;

create index if not exists wall_notes_nearby_idx
  on public.wall_notes (location_lat_bucket, location_lng_bucket, created_at desc)
  where status = 'active'
    and moderation_status = 'approved'
    and location_visibility = true;

create index if not exists wall_notes_contributions_enabled_idx
  on public.wall_notes (allow_contributions, created_at desc)
  where status = 'active'
    and moderation_status = 'approved'
    and allow_contributions = true;

create table if not exists public.wall_note_signatures (
  note_id uuid not null references public.wall_notes(id) on delete cascade,
  app_user_id text not null references public.app_users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (note_id, app_user_id)
);

create index if not exists wall_note_signatures_note_idx
  on public.wall_note_signatures (note_id, created_at desc);

create index if not exists wall_note_signatures_user_idx
  on public.wall_note_signatures (app_user_id, created_at desc);

create table if not exists public.wall_note_contributions (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.wall_notes(id) on delete cascade,
  author_account_id text not null references public.app_users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 300),
  publishing_identity text not null default 'author'
    check (publishing_identity in ('ghost', 'author')),
  source_reply_id uuid unique,
  moderation_status text not null default 'approved'
    check (moderation_status in ('pending', 'approved', 'review_required', 'rejected', 'removed')),
  status text not null default 'active'
    check (status in ('active', 'hidden', 'removed', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists wall_note_contributions_note_idx
  on public.wall_note_contributions (note_id, created_at asc)
  where status = 'active' and moderation_status = 'approved';

create index if not exists wall_note_contributions_author_idx
  on public.wall_note_contributions (author_account_id, created_at desc);

drop trigger if exists wall_note_contributions_set_updated_at on public.wall_note_contributions;
create trigger wall_note_contributions_set_updated_at
before update on public.wall_note_contributions
for each row execute function public.set_captro_updated_at();

insert into public.wall_note_contributions (
  id,
  note_id,
  author_account_id,
  body,
  publishing_identity,
  source_reply_id,
  moderation_status,
  status,
  created_at,
  updated_at
)
select
  r.id,
  r.note_id,
  r.author_account_id,
  r.body,
  r.publishing_identity,
  r.id,
  r.moderation_status,
  r.status,
  r.created_at,
  r.updated_at
from public.wall_note_replies r
on conflict (id) do nothing;

update public.wall_notes n
set
  allow_contributions = true,
  contribution_count = counts.total,
  reply_count = counts.total
from (
  select note_id, count(*)::integer as total
  from public.wall_note_contributions
  where status = 'active' and moderation_status = 'approved'
  group by note_id
) counts
where n.id = counts.note_id;

create or replace function private.sync_wall_note_signature_count()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_note_id uuid;
begin
  target_note_id := case when tg_op = 'DELETE' then old.note_id else new.note_id end;
  update public.wall_notes
  set signature_count = (
    select count(*)::integer
    from public.wall_note_signatures
    where note_id = target_note_id
  )
  where id = target_note_id;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function private.sync_wall_note_contribution_count()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_note_id uuid;
begin
  target_note_id := case when tg_op = 'DELETE' then old.note_id else new.note_id end;
  update public.wall_notes
  set
    contribution_count = (
      select count(*)::integer
      from public.wall_note_contributions
      where note_id = target_note_id
        and status = 'active'
        and moderation_status = 'approved'
    ),
    reply_count = (
      select count(*)::integer
      from public.wall_note_contributions
      where note_id = target_note_id
        and status = 'active'
        and moderation_status = 'approved'
    )
  where id = target_note_id;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.sync_wall_note_signature_count() from public, anon, authenticated;
revoke all on function private.sync_wall_note_contribution_count() from public, anon, authenticated;

drop trigger if exists wall_note_signatures_sync_count on public.wall_note_signatures;
create trigger wall_note_signatures_sync_count
after insert or delete on public.wall_note_signatures
for each row execute function private.sync_wall_note_signature_count();

drop trigger if exists wall_note_contributions_sync_count on public.wall_note_contributions;
create trigger wall_note_contributions_sync_count
after insert or delete or update of status, moderation_status on public.wall_note_contributions
for each row execute function private.sync_wall_note_contribution_count();

alter table public.wall_note_signatures enable row level security;
alter table public.wall_note_contributions enable row level security;

revoke all on public.wall_note_signatures from anon, authenticated;
revoke all on public.wall_note_contributions from anon, authenticated;
grant select on public.wall_note_signatures to authenticated;
grant select on public.wall_note_contributions to authenticated;

drop policy if exists wall_note_signatures_owner_all on public.wall_note_signatures;
drop policy if exists wall_note_signatures_owner_select on public.wall_note_signatures;
create policy wall_note_signatures_owner_select on public.wall_note_signatures
for select to authenticated
using (
  exists (
    select 1
    from public.app_users u
    where u.id = wall_note_signatures.app_user_id
      and u.supabase_user_id = (select auth.uid())
  )
);

drop policy if exists wall_note_contributions_owner_all on public.wall_note_contributions;
drop policy if exists wall_note_contributions_owner_select on public.wall_note_contributions;
create policy wall_note_contributions_owner_select on public.wall_note_contributions
for select to authenticated
using (
  exists (
    select 1
    from public.app_users u
    where u.id = wall_note_contributions.author_account_id
      and u.supabase_user_id = (select auth.uid())
  )
);

comment on column public.wall_notes.voice_waveform is
  'At most 48 normalized amplitude samples for drawing a static waveform. No audio data.';
comment on column public.wall_notes.location_cell is
  'Coarse server-generated location cell. Never store or expose exact device coordinates.';
comment on column public.wall_notes.location_lat_bucket is
  'Coarse latitude rounded by the Worker for approximate distance filtering only.';
comment on column public.wall_notes.location_lng_bucket is
  'Coarse longitude rounded by the Worker for approximate distance filtering only.';
comment on table public.wall_note_signatures is
  'One durable signature per Captro account and note. Ghost note ownership is never inferred from this table.';
comment on table public.wall_note_contributions is
  'Moderated physical response pieces attached to author-enabled Wall notes.';

