-- Captro music favorites and hidden sounds on Supabase Postgres.
-- Audio files/streams stay with the provider; Supabase stores user/admin metadata only.

create extension if not exists pgcrypto;

create table if not exists public.app_hidden_sounds (
  provider text not null default 'audius',
  track_id text not null,
  reason text not null default '',
  hidden_by text,
  created_at timestamptz not null default now(),
  constraint app_hidden_sounds_pk primary key (provider, track_id)
);

create index if not exists app_hidden_sounds_created_idx
  on public.app_hidden_sounds (created_at desc);

create table if not exists public.app_favorite_sounds (
  id text primary key default gen_random_uuid()::text,
  user_id text not null,
  provider text not null default 'audius',
  track_id text not null,
  title text not null default '',
  artist text not null default '',
  artist_id text not null default '',
  artist_handle text not null default '',
  artist_profile_image text not null default '',
  artwork_url text not null default '',
  duration integer not null default 0,
  genre text not null default '',
  play_count integer not null default 0,
  favorite_count integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_favorite_sounds_user_track_unique unique (user_id, provider, track_id)
);

create index if not exists app_favorite_sounds_user_created_idx
  on public.app_favorite_sounds (user_id, provider, created_at desc);

alter table public.app_hidden_sounds enable row level security;
alter table public.app_favorite_sounds enable row level security;

grant select, insert, update, delete on public.app_favorite_sounds to authenticated;
grant select on public.app_hidden_sounds to authenticated;

drop trigger if exists app_favorite_sounds_set_updated_at on public.app_favorite_sounds;
create trigger app_favorite_sounds_set_updated_at
before update on public.app_favorite_sounds
for each row execute function public.set_captro_updated_at();

drop policy if exists "clients cannot access hidden sounds directly" on public.app_hidden_sounds;
create policy "clients cannot access hidden sounds directly"
on public.app_hidden_sounds
for all
to authenticated
using (false)
with check (false);

drop policy if exists "users can read own favorite sounds" on public.app_favorite_sounds;
create policy "users can read own favorite sounds"
on public.app_favorite_sounds
for select
to authenticated
using (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can create own favorite sounds" on public.app_favorite_sounds;
create policy "users can create own favorite sounds"
on public.app_favorite_sounds
for insert
to authenticated
with check (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can update own favorite sounds" on public.app_favorite_sounds;
create policy "users can update own favorite sounds"
on public.app_favorite_sounds
for update
to authenticated
using (user_id::text = private.captro_current_app_user_id())
with check (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can delete own favorite sounds" on public.app_favorite_sounds;
create policy "users can delete own favorite sounds"
on public.app_favorite_sounds
for delete
to authenticated
using (user_id::text = private.captro_current_app_user_id());
