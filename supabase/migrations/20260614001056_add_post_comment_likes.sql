-- Supabase-primary persistence for comment likes. D1 comment_likes is legacy
-- cache only; app-visible comment like state should survive refresh/reinstall.

alter table if exists public.post_comments
  drop constraint if exists post_comments_status_check;

alter table if exists public.post_comments
  add constraint post_comments_status_check
  check (status in ('active', 'removed', 'hidden'));

create table if not exists public.post_comment_likes (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid references public.post_comments(id) on delete cascade,
  legacy_comment_id text,
  app_user_id text references public.app_users(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.post_comment_likes
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists comment_id uuid references public.post_comments(id) on delete cascade,
  add column if not exists legacy_comment_id text,
  add column if not exists app_user_id text references public.app_users(id) on delete cascade,
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists legacy_created_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists post_comment_likes_legacy_app_unique
  on public.post_comment_likes (legacy_comment_id, app_user_id);

create unique index if not exists post_comment_likes_native_user_unique
  on public.post_comment_likes (comment_id, user_id);

create index if not exists post_comment_likes_comment_idx
  on public.post_comment_likes (legacy_comment_id, comment_id);

create index if not exists post_comment_likes_user_idx
  on public.post_comment_likes (app_user_id, user_id, created_at desc);

drop trigger if exists post_comment_likes_set_updated_at on public.post_comment_likes;
create trigger post_comment_likes_set_updated_at
before update on public.post_comment_likes
for each row execute function public.set_captro_updated_at();

alter table public.post_comment_likes enable row level security;

drop policy if exists "users can read own comment likes" on public.post_comment_likes;
create policy "users can read own comment likes"
on public.post_comment_likes
for select
to authenticated
using (
  app_user_id::text = private.captro_current_app_user_id()
  or user_id::text = auth.uid()::text
);

drop policy if exists "users can insert own comment likes" on public.post_comment_likes;
create policy "users can insert own comment likes"
on public.post_comment_likes
for insert
to authenticated
with check (
  (
    app_user_id::text = private.captro_current_app_user_id()
    or user_id::text = auth.uid()::text
  )
  and exists (
    select 1
    from public.post_comments c
    join public.app_posts p
      on (
        (c.post_id is not null and p.id = c.post_id)
        or (c.legacy_post_id is not null and p.legacy_post_id::text = c.legacy_post_id::text)
      )
    where c.status = 'active'
      and (
        c.id = post_comment_likes.comment_id
        or c.legacy_comment_id::text = post_comment_likes.legacy_comment_id::text
      )
      and p.status = 'active'
      and (
        p.app_user_id::text = private.captro_current_app_user_id()
        or (
          p.visibility = 'public'
          and private.captro_users_not_blocked(private.captro_current_app_user_id(), p.app_user_id::text)
        )
      )
  )
);

drop policy if exists "users can delete own comment likes" on public.post_comment_likes;
create policy "users can delete own comment likes"
on public.post_comment_likes
for delete
to authenticated
using (
  app_user_id::text = private.captro_current_app_user_id()
  or user_id::text = auth.uid()::text
);
