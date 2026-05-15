create table if not exists public.app_users (
  id text primary key,
  supabase_user_id uuid references auth.users(id) on delete set null,
  email text,
  username text,
  full_name text,
  avatar_url text,
  cover_url text,
  bio text default '',
  city text default '',
  is_private boolean not null default false,
  is_verified boolean not null default false,
  counts jsonb not null default '{}'::jsonb,
  profile jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  legacy_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists app_users_username_lower_idx
  on public.app_users (lower(username))
  where username is not null and username <> '';
create index if not exists app_users_supabase_user_idx
  on public.app_users (supabase_user_id);
create index if not exists app_users_profile_gin_idx
  on public.app_users using gin (profile);
create index if not exists app_users_metadata_gin_idx
  on public.app_users using gin (metadata);

alter table public.app_posts
  alter column user_id drop not null;

alter table public.app_posts
  add column if not exists legacy_created_at timestamptz,
  add column if not exists legacy_updated_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from information_schema.table_constraints
    where constraint_schema = 'public'
      and table_name = 'app_posts'
      and constraint_name = 'app_posts_app_user_id_fkey'
  ) then
    alter table public.app_posts
      add constraint app_posts_app_user_id_fkey
      foreign key (app_user_id) references public.app_users(id) on delete set null;
  end if;
end $$;

create index if not exists app_posts_app_user_created_idx
  on public.app_posts (app_user_id, created_at desc);

alter table public.post_comments
  alter column post_id drop not null,
  alter column user_id drop not null;

alter table public.post_comments
  add column if not exists legacy_comment_id text,
  add column if not exists legacy_post_id text,
  add column if not exists app_user_id text references public.app_users(id) on delete set null,
  add column if not exists legacy_created_at timestamptz;

create unique index if not exists post_comments_legacy_comment_idx
  on public.post_comments (legacy_comment_id)
  where legacy_comment_id is not null and legacy_comment_id <> '';
do $$
begin
  if not exists (
    select 1
    from information_schema.table_constraints
    where constraint_schema = 'public'
      and table_name = 'post_comments'
      and constraint_name = 'post_comments_legacy_comment_unique'
  ) then
    alter table public.post_comments
      add constraint post_comments_legacy_comment_unique unique (legacy_comment_id);
  end if;
end $$;
create index if not exists post_comments_legacy_post_idx
  on public.post_comments (legacy_post_id, legacy_created_at desc);
create index if not exists post_comments_app_user_idx
  on public.post_comments (app_user_id, legacy_created_at desc);

create table if not exists public.app_post_interactions (
  id uuid primary key default gen_random_uuid(),
  legacy_post_id text,
  post_id uuid references public.app_posts(id) on delete cascade,
  app_user_id text references public.app_users(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  kind text not null check (kind in ('like', 'save', 'repost')),
  collection text,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists app_post_interactions_legacy_unique_idx
  on public.app_post_interactions (legacy_post_id, app_user_id, kind)
  where legacy_post_id is not null and app_user_id is not null;
do $$
begin
  if not exists (
    select 1
    from information_schema.table_constraints
    where constraint_schema = 'public'
      and table_name = 'app_post_interactions'
      and constraint_name = 'app_post_interactions_legacy_unique'
  ) then
    alter table public.app_post_interactions
      add constraint app_post_interactions_legacy_unique unique (legacy_post_id, app_user_id, kind);
  end if;
end $$;
create index if not exists app_post_interactions_post_kind_idx
  on public.app_post_interactions (legacy_post_id, kind, legacy_created_at desc);
create index if not exists app_post_interactions_user_kind_idx
  on public.app_post_interactions (app_user_id, kind, legacy_created_at desc);
create index if not exists app_post_interactions_metadata_gin_idx
  on public.app_post_interactions using gin (metadata);

create table if not exists public.app_follows (
  app_follower_id text not null references public.app_users(id) on delete cascade,
  app_following_id text not null references public.app_users(id) on delete cascade,
  follower_id uuid references auth.users(id) on delete set null,
  following_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (app_follower_id, app_following_id),
  check (app_follower_id <> app_following_id)
);

create index if not exists app_follows_following_idx
  on public.app_follows (app_following_id, legacy_created_at desc);
create index if not exists app_follows_metadata_gin_idx
  on public.app_follows using gin (metadata);

drop trigger if exists touch_app_users_updated_at on public.app_users;
create trigger touch_app_users_updated_at
before update on public.app_users
for each row execute function public.touch_updated_at();

alter table public.app_users enable row level security;
alter table public.app_post_interactions enable row level security;
alter table public.app_follows enable row level security;

create policy "app users are readable"
on public.app_users for select
using (true);

create policy "own linked app user can update"
on public.app_users for update
using (auth.uid() = supabase_user_id)
with check (auth.uid() = supabase_user_id);

create policy "legacy interactions are readable"
on public.app_post_interactions for select
using (true);

create policy "legacy follows are readable"
on public.app_follows for select
using (true);
