-- Captro Wall of Notes.
-- Public discovery is served by the authenticated Worker so Ghost ownership is
-- never exposed through the Data API. RLS keeps direct table access owner-only.

create extension if not exists pgcrypto;

create table if not exists public.wall_notes (
  id uuid primary key default gen_random_uuid(),
  wall_id text not null default 'global',
  author_account_id text not null references public.app_users(id) on delete cascade,
  publishing_identity text not null check (publishing_identity in ('ghost', 'author')),
  body text not null check (char_length(body) between 1 and 300),
  category text,
  color_token text not null default 'butter',
  style_token text not null default 'sticky_square',
  world_x double precision not null,
  world_y double precision not null,
  width double precision not null default 184 check (width between 96 and 360),
  height double precision not null default 184 check (height between 96 and 420),
  rotation double precision not null default 0 check (rotation between -3 and 3),
  z_index integer not null default 0,
  approximate_location text,
  moderation_status text not null default 'approved'
    check (moderation_status in ('pending', 'approved', 'review_required', 'rejected', 'removed')),
  status text not null default 'active'
    check (status in ('active', 'hidden', 'removed', 'deleted')),
  save_count integer not null default 0 check (save_count >= 0),
  reaction_count integer not null default 0 check (reaction_count >= 0),
  reply_count integer not null default 0 check (reply_count >= 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists wall_notes_region_idx
  on public.wall_notes (wall_id, world_x, world_y)
  where status = 'active' and moderation_status = 'approved';

create index if not exists wall_notes_recent_idx
  on public.wall_notes (wall_id, created_at desc)
  where status = 'active' and moderation_status = 'approved';

create index if not exists wall_notes_popular_idx
  on public.wall_notes (wall_id, reaction_count desc, save_count desc, created_at desc)
  where status = 'active' and moderation_status = 'approved';

create index if not exists wall_notes_author_idx
  on public.wall_notes (author_account_id, created_at desc);

create index if not exists wall_notes_category_idx
  on public.wall_notes (wall_id, category, created_at desc)
  where status = 'active' and moderation_status = 'approved';

create table if not exists public.wall_note_reactions (
  note_id uuid not null references public.wall_notes(id) on delete cascade,
  app_user_id text not null references public.app_users(id) on delete cascade,
  reaction_type text not null default 'felt_this' check (reaction_type in ('felt_this')),
  created_at timestamptz not null default now(),
  primary key (note_id, app_user_id)
);

create index if not exists wall_note_reactions_user_idx
  on public.wall_note_reactions (app_user_id, created_at desc);

create table if not exists public.wall_note_saves (
  note_id uuid not null references public.wall_notes(id) on delete cascade,
  app_user_id text not null references public.app_users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (note_id, app_user_id)
);

create index if not exists wall_note_saves_user_idx
  on public.wall_note_saves (app_user_id, created_at desc);

create table if not exists public.wall_note_replies (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.wall_notes(id) on delete cascade,
  author_account_id text not null references public.app_users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 300),
  publishing_identity text not null default 'author'
    check (publishing_identity in ('ghost', 'author')),
  moderation_status text not null default 'approved'
    check (moderation_status in ('pending', 'approved', 'review_required', 'rejected', 'removed')),
  status text not null default 'active'
    check (status in ('active', 'hidden', 'removed', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists wall_note_replies_note_idx
  on public.wall_note_replies (note_id, created_at asc)
  where status = 'active' and moderation_status = 'approved';

create index if not exists wall_note_replies_author_idx
  on public.wall_note_replies (author_account_id, created_at desc);

drop trigger if exists wall_notes_set_updated_at on public.wall_notes;
create trigger wall_notes_set_updated_at
before update on public.wall_notes
for each row execute function public.set_captro_updated_at();

drop trigger if exists wall_note_replies_set_updated_at on public.wall_note_replies;
create trigger wall_note_replies_set_updated_at
before update on public.wall_note_replies
for each row execute function public.set_captro_updated_at();

alter table public.wall_notes enable row level security;
alter table public.wall_note_reactions enable row level security;
alter table public.wall_note_saves enable row level security;
alter table public.wall_note_replies enable row level security;

revoke all on public.wall_notes from anon, authenticated;
revoke all on public.wall_note_reactions from anon, authenticated;
revoke all on public.wall_note_saves from anon, authenticated;
revoke all on public.wall_note_replies from anon, authenticated;

grant select, insert, update, delete on public.wall_notes to authenticated;
grant select, insert, update, delete on public.wall_note_reactions to authenticated;
grant select, insert, update, delete on public.wall_note_saves to authenticated;
grant select, insert, update, delete on public.wall_note_replies to authenticated;

drop policy if exists wall_notes_owner_select on public.wall_notes;
create policy wall_notes_owner_select on public.wall_notes
for select to authenticated
using (
  exists (
    select 1 from public.app_users u
    where u.id = wall_notes.author_account_id
      and u.supabase_user_id = (select auth.uid())
  )
);

drop policy if exists wall_notes_owner_insert on public.wall_notes;
create policy wall_notes_owner_insert on public.wall_notes
for insert to authenticated
with check (
  exists (
    select 1 from public.app_users u
    where u.id = wall_notes.author_account_id
      and u.supabase_user_id = (select auth.uid())
  )
);

drop policy if exists wall_notes_owner_update on public.wall_notes;
create policy wall_notes_owner_update on public.wall_notes
for update to authenticated
using (
  exists (
    select 1 from public.app_users u
    where u.id = wall_notes.author_account_id
      and u.supabase_user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.app_users u
    where u.id = wall_notes.author_account_id
      and u.supabase_user_id = (select auth.uid())
  )
);

drop policy if exists wall_notes_owner_delete on public.wall_notes;
create policy wall_notes_owner_delete on public.wall_notes
for delete to authenticated
using (
  exists (
    select 1 from public.app_users u
    where u.id = wall_notes.author_account_id
      and u.supabase_user_id = (select auth.uid())
  )
);

drop policy if exists wall_note_reactions_owner_all on public.wall_note_reactions;
create policy wall_note_reactions_owner_all on public.wall_note_reactions
for all to authenticated
using (
  exists (
    select 1 from public.app_users u
    where u.id = wall_note_reactions.app_user_id
      and u.supabase_user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.app_users u
    where u.id = wall_note_reactions.app_user_id
      and u.supabase_user_id = (select auth.uid())
  )
);

drop policy if exists wall_note_saves_owner_all on public.wall_note_saves;
create policy wall_note_saves_owner_all on public.wall_note_saves
for all to authenticated
using (
  exists (
    select 1 from public.app_users u
    where u.id = wall_note_saves.app_user_id
      and u.supabase_user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.app_users u
    where u.id = wall_note_saves.app_user_id
      and u.supabase_user_id = (select auth.uid())
  )
);

drop policy if exists wall_note_replies_owner_all on public.wall_note_replies;
create policy wall_note_replies_owner_all on public.wall_note_replies
for all to authenticated
using (
  exists (
    select 1 from public.app_users u
    where u.id = wall_note_replies.author_account_id
      and u.supabase_user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.app_users u
    where u.id = wall_note_replies.author_account_id
      and u.supabase_user_id = (select auth.uid())
  )
);

comment on table public.wall_notes is
  'Captro two-dimensional Wall of Notes. Ghost ownership remains private and is exposed only to moderation systems.';
comment on column public.wall_notes.approximate_location is
  'Neighborhood/city-level label only. Never store precise coordinates here.';
