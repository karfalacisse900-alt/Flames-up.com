-- Captro Supabase Postgres core schema.
-- This migration creates Captro's canonical production app tables
-- used by the Cloudflare Worker API. Media binaries remain in
-- Cloudflare Images/R2/Stream; Postgres stores structured data only.

create extension if not exists pgcrypto;
create extension if not exists citext;

create table if not exists public.app_users (
  id text primary key,
  supabase_user_id uuid references auth.users(id) on delete set null,
  email citext,
  username citext,
  full_name text,
  avatar_url text,
  cover_url text,
  bio text not null default '',
  city text not null default '',
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

create unique index if not exists app_users_supabase_user_id_idx
  on public.app_users (supabase_user_id)
  where supabase_user_id is not null;

create unique index if not exists app_users_username_lower_idx
  on public.app_users (lower(username::text))
  where username is not null;

create index if not exists app_users_email_idx
  on public.app_users (email);

create table if not exists public.app_posts (
  legacy_post_id text primary key,
  user_id uuid references auth.users(id) on delete set null,
  app_user_id text,
  title text not null default '',
  content text not null default '',
  visibility text not null default 'public',
  status text not null default 'active',
  post_type text not null default 'media',
  category text not null default '',
  location text not null default '',
  media jsonb not null default '[]'::jsonb,
  media_dimensions jsonb not null default '{}'::jsonb,
  editor_data jsonb not null default '{}'::jsonb,
  product_tags jsonb not null default '[]'::jsonb,
  tagged_users jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  likes_count integer not null default 0,
  comments_count integer not null default 0,
  saves_count integer not null default 0,
  legacy_created_at timestamptz,
  legacy_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_posts_user_created_idx
  on public.app_posts (app_user_id, legacy_created_at desc nulls last, created_at desc);

create index if not exists app_posts_status_created_idx
  on public.app_posts (status, legacy_created_at desc nulls last, created_at desc);

create index if not exists app_posts_category_created_idx
  on public.app_posts (category, legacy_created_at desc nulls last, created_at desc);

create index if not exists app_posts_media_gin_idx
  on public.app_posts using gin (media);

create index if not exists app_posts_metadata_gin_idx
  on public.app_posts using gin (metadata);

create table if not exists public.post_comments (
  legacy_comment_id text primary key,
  legacy_post_id text not null,
  app_user_id text,
  user_id uuid references auth.users(id) on delete set null,
  body text not null default '',
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists post_comments_post_created_idx
  on public.post_comments (legacy_post_id, legacy_created_at asc nulls last, created_at asc);

create index if not exists post_comments_user_created_idx
  on public.post_comments (app_user_id, legacy_created_at desc nulls last, created_at desc);

create table if not exists public.app_post_interactions (
  legacy_post_id text not null,
  app_user_id text not null,
  kind text not null,
  collection text,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_post_interactions_pk primary key (legacy_post_id, app_user_id, kind)
);

create index if not exists app_post_interactions_user_kind_idx
  on public.app_post_interactions (app_user_id, kind, created_at desc);

create index if not exists app_post_interactions_post_kind_idx
  on public.app_post_interactions (legacy_post_id, kind, created_at desc);

create table if not exists public.app_follows (
  app_follower_id text not null,
  app_following_id text not null,
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_follows_pk primary key (app_follower_id, app_following_id)
);

create index if not exists app_follows_following_idx
  on public.app_follows (app_following_id, status, created_at desc);

create table if not exists public.app_documents (
  id uuid primary key default gen_random_uuid(),
  owner_id text,
  collection text not null,
  document_key text not null,
  visibility text not null default 'private',
  document jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_documents_owner_collection_key unique (owner_id, collection, document_key)
);

create index if not exists app_documents_owner_collection_idx
  on public.app_documents (owner_id, collection, updated_at desc);

create index if not exists app_documents_document_gin_idx
  on public.app_documents using gin (document);

create or replace function public.set_captro_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists app_users_set_updated_at on public.app_users;
create trigger app_users_set_updated_at
before update on public.app_users
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_posts_set_updated_at on public.app_posts;
create trigger app_posts_set_updated_at
before update on public.app_posts
for each row execute function public.set_captro_updated_at();

drop trigger if exists post_comments_set_updated_at on public.post_comments;
create trigger post_comments_set_updated_at
before update on public.post_comments
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_post_interactions_set_updated_at on public.app_post_interactions;
create trigger app_post_interactions_set_updated_at
before update on public.app_post_interactions
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_follows_set_updated_at on public.app_follows;
create trigger app_follows_set_updated_at
before update on public.app_follows
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_documents_set_updated_at on public.app_documents;
create trigger app_documents_set_updated_at
before update on public.app_documents
for each row execute function public.set_captro_updated_at();

alter table public.app_users enable row level security;
alter table public.app_posts enable row level security;
alter table public.post_comments enable row level security;
alter table public.app_post_interactions enable row level security;
alter table public.app_follows enable row level security;
alter table public.app_documents enable row level security;

comment on table public.app_users is 'Canonical Captro app profiles keyed by app user id and linked to Supabase Auth.';
comment on table public.app_posts is 'Captro structured post metadata. Media files live in Cloudflare Images/R2/Stream.';
comment on table public.app_post_interactions is 'Canonical Supabase uniqueness layer for likes, saves, and repost-like interactions.';
comment on table public.app_documents is 'Private JSONB document layer for transfer logs and flexible app metadata. Access through Worker service role only by default.';
