-- Captro stories/statuses on Supabase Postgres.
-- Stories are structured app data. Media binaries stay in Cloudflare Images/Stream.

create extension if not exists pgcrypto;

create table if not exists public.app_stories (
  id text primary key,
  user_id text not null,
  content text not null default '',
  media_url text,
  media_type text not null default '',
  background_color text not null default '#1B4332',
  text_color text not null default '#FFFFFF',
  visibility text not null default 'public',
  status text not null default 'active',
  duration_seconds integer,
  audio jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_stories_visibility_check check (visibility in ('public', 'followers', 'friends', 'private')),
  constraint app_stories_status_check check (status in ('active', 'removed', 'expired'))
);

create index if not exists app_stories_user_created_idx
  on public.app_stories (user_id, created_at desc);

create index if not exists app_stories_visible_idx
  on public.app_stories (status, visibility, expires_at desc, created_at desc);

create index if not exists app_stories_audio_gin_idx
  on public.app_stories using gin (audio);

create table if not exists public.app_story_likes (
  story_id text not null,
  user_id text not null,
  created_at timestamptz not null default now(),
  constraint app_story_likes_pk primary key (story_id, user_id),
  constraint app_story_likes_story_fk foreign key (story_id)
    references public.app_stories(id) on delete cascade
);

create index if not exists app_story_likes_user_idx
  on public.app_story_likes (user_id, created_at desc);

create table if not exists public.app_story_views (
  story_id text not null,
  user_id text not null,
  created_at timestamptz not null default now(),
  constraint app_story_views_pk primary key (story_id, user_id),
  constraint app_story_views_story_fk foreign key (story_id)
    references public.app_stories(id) on delete cascade
);

create index if not exists app_story_views_user_idx
  on public.app_story_views (user_id, created_at desc);

create table if not exists public.app_story_thoughts (
  id text primary key,
  story_id text not null,
  user_id text not null,
  body text not null default '',
  status text not null default 'active',
  removed_at timestamptz,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_story_thoughts_story_fk foreign key (story_id)
    references public.app_stories(id) on delete cascade,
  constraint app_story_thoughts_status_check check (status in ('active', 'removed', 'hidden'))
);

create index if not exists app_story_thoughts_story_created_idx
  on public.app_story_thoughts (story_id, status, created_at asc);

create index if not exists app_story_thoughts_user_created_idx
  on public.app_story_thoughts (user_id, created_at desc);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'app_stories',
    'app_story_likes',
    'app_story_views',
    'app_story_thoughts'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
  end loop;
end $$;

drop trigger if exists app_stories_set_updated_at on public.app_stories;
create trigger app_stories_set_updated_at
before update on public.app_stories
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_story_thoughts_set_updated_at on public.app_story_thoughts;
create trigger app_story_thoughts_set_updated_at
before update on public.app_story_thoughts
for each row execute function public.set_captro_updated_at();

drop policy if exists "users can read visible stories" on public.app_stories;
create policy "users can read visible stories"
on public.app_stories
for select
to authenticated
using (
  user_id::text = private.captro_current_app_user_id()
  or (
    status = 'active'
    and expires_at > now()
    and visibility = 'public'
    and private.captro_user_is_active(user_id::text)
    and private.captro_users_not_blocked(private.captro_current_app_user_id(), user_id::text)
  )
);

drop policy if exists "users can create own stories" on public.app_stories;
create policy "users can create own stories"
on public.app_stories
for insert
to authenticated
with check (
  user_id::text = private.captro_current_app_user_id()
  and status = 'active'
  and expires_at > now()
);

drop policy if exists "users can update own stories" on public.app_stories;
create policy "users can update own stories"
on public.app_stories
for update
to authenticated
using (user_id::text = private.captro_current_app_user_id())
with check (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can delete own stories" on public.app_stories;
create policy "users can delete own stories"
on public.app_stories
for delete
to authenticated
using (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can read story likes" on public.app_story_likes;
create policy "users can read story likes"
on public.app_story_likes
for select
to authenticated
using (
  user_id::text = private.captro_current_app_user_id()
  or exists (
    select 1
    from public.app_stories s
    where s.id::text = app_story_likes.story_id::text
      and (
        s.user_id::text = private.captro_current_app_user_id()
        or (
          s.status = 'active'
          and s.expires_at > now()
          and s.visibility = 'public'
          and private.captro_users_not_blocked(private.captro_current_app_user_id(), s.user_id::text)
        )
      )
  )
);

drop policy if exists "users can create own story likes" on public.app_story_likes;
create policy "users can create own story likes"
on public.app_story_likes
for insert
to authenticated
with check (
  user_id::text = private.captro_current_app_user_id()
  and exists (
    select 1
    from public.app_stories s
    where s.id::text = app_story_likes.story_id::text
      and s.status = 'active'
      and s.expires_at > now()
      and private.captro_users_not_blocked(private.captro_current_app_user_id(), s.user_id::text)
  )
);

drop policy if exists "users can delete own story likes" on public.app_story_likes;
create policy "users can delete own story likes"
on public.app_story_likes
for delete
to authenticated
using (user_id::text = private.captro_current_app_user_id());

drop policy if exists "users can read own or authored story views" on public.app_story_views;
create policy "users can read own or authored story views"
on public.app_story_views
for select
to authenticated
using (
  user_id::text = private.captro_current_app_user_id()
  or exists (
    select 1
    from public.app_stories s
    where s.id::text = app_story_views.story_id::text
      and s.user_id::text = private.captro_current_app_user_id()
  )
);

drop policy if exists "users can create own story views" on public.app_story_views;
create policy "users can create own story views"
on public.app_story_views
for insert
to authenticated
with check (
  user_id::text = private.captro_current_app_user_id()
  and exists (
    select 1
    from public.app_stories s
    where s.id::text = app_story_views.story_id::text
      and s.status = 'active'
      and s.expires_at > now()
      and private.captro_users_not_blocked(private.captro_current_app_user_id(), s.user_id::text)
  )
);

drop policy if exists "users can read visible story thoughts" on public.app_story_thoughts;
create policy "users can read visible story thoughts"
on public.app_story_thoughts
for select
to authenticated
using (
  status = 'active'
  and private.captro_user_is_active(user_id::text)
  and private.captro_users_not_blocked(private.captro_current_app_user_id(), user_id::text)
  and exists (
    select 1
    from public.app_stories s
    where s.id::text = app_story_thoughts.story_id::text
      and (
        s.user_id::text = private.captro_current_app_user_id()
        or (
          s.status = 'active'
          and s.expires_at > now()
          and s.visibility = 'public'
          and private.captro_users_not_blocked(private.captro_current_app_user_id(), s.user_id::text)
        )
      )
  )
);

drop policy if exists "users can create own story thoughts" on public.app_story_thoughts;
create policy "users can create own story thoughts"
on public.app_story_thoughts
for insert
to authenticated
with check (
  user_id::text = private.captro_current_app_user_id()
  and status = 'active'
  and exists (
    select 1
    from public.app_stories s
    where s.id::text = app_story_thoughts.story_id::text
      and s.status = 'active'
      and s.expires_at > now()
      and private.captro_users_not_blocked(private.captro_current_app_user_id(), s.user_id::text)
  )
);

drop policy if exists "users can update own story thoughts" on public.app_story_thoughts;
create policy "users can update own story thoughts"
on public.app_story_thoughts
for update
to authenticated
using (user_id::text = private.captro_current_app_user_id())
with check (user_id::text = private.captro_current_app_user_id());

comment on table public.app_stories is 'Captro story metadata. Story videos/photos live in Cloudflare Images/Stream.';
comment on table public.app_story_likes is 'Supabase-primary unique story likes.';
comment on table public.app_story_views is 'Supabase-primary unique story view records.';
comment on table public.app_story_thoughts is 'Short story reactions/thoughts shown in the story viewer.';
