-- Supabase-primary friend request and friendship tables.
-- These replace the old D1 friend_requests/friendships app-data path.

create table if not exists public.app_friend_requests (
  id text primary key default gen_random_uuid()::text,
  from_user_id text not null references public.app_users(id) on delete cascade,
  to_user_id text not null references public.app_users(id) on delete cascade,
  status text not null default 'pending',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_friend_requests_not_self check (from_user_id <> to_user_id),
  constraint app_friend_requests_status_check check (status in ('pending', 'accepted', 'rejected', 'cancelled'))
);

create unique index if not exists app_friend_requests_pair_idx
  on public.app_friend_requests (from_user_id, to_user_id);

create index if not exists app_friend_requests_to_status_idx
  on public.app_friend_requests (to_user_id, status, created_at desc);

create index if not exists app_friend_requests_from_status_idx
  on public.app_friend_requests (from_user_id, status, created_at desc);

create table if not exists public.app_friendships (
  user_id text not null references public.app_users(id) on delete cascade,
  friend_id text not null references public.app_users(id) on delete cascade,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_friendships_pk primary key (user_id, friend_id),
  constraint app_friendships_not_self check (user_id <> friend_id)
);

create index if not exists app_friendships_friend_idx
  on public.app_friendships (friend_id, created_at desc);

drop trigger if exists app_friend_requests_set_updated_at on public.app_friend_requests;
create trigger app_friend_requests_set_updated_at
before update on public.app_friend_requests
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_friendships_set_updated_at on public.app_friendships;
create trigger app_friendships_set_updated_at
before update on public.app_friendships
for each row execute function public.set_captro_updated_at();

alter table public.app_friend_requests enable row level security;
alter table public.app_friendships enable row level security;

drop policy if exists "users can read own friend requests" on public.app_friend_requests;
create policy "users can read own friend requests"
on public.app_friend_requests
for select
to authenticated
using (
  from_user_id::text = private.captro_current_app_user_id()
  or to_user_id::text = private.captro_current_app_user_id()
);

drop policy if exists "users can create own friend requests" on public.app_friend_requests;
create policy "users can create own friend requests"
on public.app_friend_requests
for insert
to authenticated
with check (
  from_user_id::text = private.captro_current_app_user_id()
  and from_user_id::text <> to_user_id::text
  and private.captro_users_not_blocked(from_user_id::text, to_user_id::text)
);

drop policy if exists "users can update received friend requests" on public.app_friend_requests;
create policy "users can update received friend requests"
on public.app_friend_requests
for update
to authenticated
using (
  to_user_id::text = private.captro_current_app_user_id()
  or from_user_id::text = private.captro_current_app_user_id()
)
with check (
  to_user_id::text = private.captro_current_app_user_id()
  or from_user_id::text = private.captro_current_app_user_id()
);

drop policy if exists "users can read own friendships" on public.app_friendships;
create policy "users can read own friendships"
on public.app_friendships
for select
to authenticated
using (
  user_id::text = private.captro_current_app_user_id()
  or friend_id::text = private.captro_current_app_user_id()
);

drop policy if exists "users can create own friendship rows" on public.app_friendships;
create policy "users can create own friendship rows"
on public.app_friendships
for insert
to authenticated
with check (
  user_id::text = private.captro_current_app_user_id()
  and user_id::text <> friend_id::text
  and private.captro_users_not_blocked(user_id::text, friend_id::text)
);

drop policy if exists "users can delete own friendships" on public.app_friendships;
create policy "users can delete own friendships"
on public.app_friendships
for delete
to authenticated
using (
  user_id::text = private.captro_current_app_user_id()
  or friend_id::text = private.captro_current_app_user_id()
);

comment on table public.app_friend_requests is 'Captro Supabase-primary friend request state.';
comment on table public.app_friendships is 'Captro Supabase-primary accepted friend relationships, stored bidirectionally.';
