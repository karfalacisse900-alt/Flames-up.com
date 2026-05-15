create extension if not exists "pgcrypto" with schema "extensions";

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  app_user_id text unique,
  email text,
  username text,
  full_name text,
  avatar_url text,
  bio text default '',
  is_private boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username))
  where username is not null and username <> '';

create index if not exists profiles_metadata_gin_idx
  on public.profiles using gin (metadata);

create table if not exists public.app_posts (
  id uuid primary key default gen_random_uuid(),
  legacy_post_id text unique,
  user_id uuid not null references auth.users(id) on delete cascade,
  app_user_id text,
  title text,
  content text not null default '',
  visibility text not null default 'public'
    check (visibility in ('public', 'followers', 'friends', 'private')),
  status text not null default 'active'
    check (status in ('active', 'archived', 'removed')),
  post_type text not null default 'general',
  category text,
  location text,
  media jsonb not null default '[]'::jsonb,
  media_dimensions jsonb not null default '[]'::jsonb,
  editor_data jsonb not null default '{}'::jsonb,
  product_tags jsonb not null default '[]'::jsonb,
  tagged_users jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  likes_count integer not null default 0 check (likes_count >= 0),
  comments_count integer not null default 0 check (comments_count >= 0),
  saves_count integer not null default 0 check (saves_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_posts_user_created_idx
  on public.app_posts (user_id, created_at desc);
create index if not exists app_posts_public_feed_idx
  on public.app_posts (status, visibility, created_at desc);
create index if not exists app_posts_media_gin_idx
  on public.app_posts using gin (media);
create index if not exists app_posts_editor_data_gin_idx
  on public.app_posts using gin (editor_data);
create index if not exists app_posts_product_tags_gin_idx
  on public.app_posts using gin (product_tags);
create index if not exists app_posts_metadata_gin_idx
  on public.app_posts using gin (metadata);

create table if not exists public.post_interactions (
  post_id uuid not null references public.app_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('like', 'save', 'repost')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id, kind)
);

create index if not exists post_interactions_user_kind_idx
  on public.post_interactions (user_id, kind, created_at desc);

create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.app_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.post_comments(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1200),
  status text not null default 'active' check (status in ('active', 'removed')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists post_comments_post_created_idx
  on public.post_comments (post_id, created_at desc);
create index if not exists post_comments_user_created_idx
  on public.post_comments (user_id, created_at desc);
create index if not exists post_comments_metadata_gin_idx
  on public.post_comments using gin (metadata);

create table if not exists public.follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create index if not exists follows_following_created_idx
  on public.follows (following_id, created_at desc);

create table if not exists public.app_documents (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade,
  collection text not null,
  document_key text,
  visibility text not null default 'private'
    check (visibility in ('public', 'followers', 'friends', 'private')),
  document jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, collection, document_key)
);

create index if not exists app_documents_collection_idx
  on public.app_documents (collection, updated_at desc);
create index if not exists app_documents_document_gin_idx
  on public.app_documents using gin (document);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_profiles_updated_at on public.profiles;
create trigger touch_profiles_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

drop trigger if exists touch_app_posts_updated_at on public.app_posts;
create trigger touch_app_posts_updated_at
before update on public.app_posts
for each row execute function public.touch_updated_at();

drop trigger if exists touch_post_comments_updated_at on public.post_comments;
create trigger touch_post_comments_updated_at
before update on public.post_comments
for each row execute function public.touch_updated_at();

drop trigger if exists touch_app_documents_updated_at on public.app_documents;
create trigger touch_app_documents_updated_at
before update on public.app_documents
for each row execute function public.touch_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, username, full_name, avatar_url, metadata)
  values (
    new.id,
    new.email,
    nullif(new.raw_user_meta_data ->> 'username', ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), nullif(new.raw_user_meta_data ->> 'name', '')),
    coalesce(nullif(new.raw_user_meta_data ->> 'avatar_url', ''), nullif(new.raw_user_meta_data ->> 'picture', '')),
    coalesce(new.raw_user_meta_data, '{}'::jsonb)
  )
  on conflict (id) do update set
    email = excluded.email,
    username = coalesce(public.profiles.username, excluded.username),
    full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
    avatar_url = coalesce(nullif(public.profiles.avatar_url, ''), excluded.avatar_url),
    metadata = public.profiles.metadata || excluded.metadata,
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

alter table public.profiles enable row level security;
alter table public.app_posts enable row level security;
alter table public.post_interactions enable row level security;
alter table public.post_comments enable row level security;
alter table public.follows enable row level security;
alter table public.app_documents enable row level security;

create policy "profiles are readable"
on public.profiles for select
using (true);

create policy "users can insert own profile"
on public.profiles for insert
with check (auth.uid() = id);

create policy "users can update own profile"
on public.profiles for update
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "public active posts are readable"
on public.app_posts for select
using (
  status = 'active'
  and (
    visibility = 'public'
    or user_id = auth.uid()
    or auth.role() = 'service_role'
  )
);

create policy "users can insert own posts"
on public.app_posts for insert
with check (auth.uid() = user_id);

create policy "users can update own posts"
on public.app_posts for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "users can delete own posts"
on public.app_posts for delete
using (auth.uid() = user_id);

create policy "interactions are readable"
on public.post_interactions for select
using (true);

create policy "users can create own interactions"
on public.post_interactions for insert
with check (auth.uid() = user_id);

create policy "users can delete own interactions"
on public.post_interactions for delete
using (auth.uid() = user_id);

create policy "active comments on readable posts are readable"
on public.post_comments for select
using (
  status = 'active'
  and exists (
    select 1
    from public.app_posts p
    where p.id = post_id
      and p.status = 'active'
      and (p.visibility = 'public' or p.user_id = auth.uid())
  )
);

create policy "users can insert own comments"
on public.post_comments for insert
with check (auth.uid() = user_id);

create policy "users can update own comments"
on public.post_comments for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "follows are readable"
on public.follows for select
using (true);

create policy "users can create own follows"
on public.follows for insert
with check (auth.uid() = follower_id);

create policy "users can delete own follows"
on public.follows for delete
using (auth.uid() = follower_id);

create policy "public documents or own documents are readable"
on public.app_documents for select
using (visibility = 'public' or owner_id = auth.uid());

create policy "users can insert own documents"
on public.app_documents for insert
with check (auth.uid() = owner_id);

create policy "users can update own documents"
on public.app_documents for update
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

create policy "users can delete own documents"
on public.app_documents for delete
using (auth.uid() = owner_id);
