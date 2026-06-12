-- Remove legacy broad policies that overlap with the stricter Captro policies.
-- This keeps Supabase as the protected source of truth while preserving the
-- current app access model.

drop policy if exists "app users are readable" on public.app_users;
drop policy if exists "own linked app user can update" on public.app_users;

drop policy if exists "public active posts are readable" on public.app_posts;

drop policy if exists "active comments on readable posts are readable" on public.post_comments;

drop policy if exists "legacy interactions are readable" on public.app_post_interactions;

drop policy if exists "legacy follows are readable" on public.app_follows;

drop policy if exists "users can manage own documents" on public.app_documents;
drop policy if exists "users can insert own documents" on public.app_documents;
drop policy if exists "users can update own documents" on public.app_documents;
drop policy if exists "users can delete own documents" on public.app_documents;

create policy "users can insert own documents"
on public.app_documents
for insert
to authenticated
with check (owner_id::text = (select private.captro_current_app_user_id()));

create policy "users can update own documents"
on public.app_documents
for update
to authenticated
using (owner_id::text = (select private.captro_current_app_user_id()))
with check (owner_id::text = (select private.captro_current_app_user_id()));

create policy "users can delete own documents"
on public.app_documents
for delete
to authenticated
using (owner_id::text = (select private.captro_current_app_user_id()));

drop policy if exists "users can manage own post places" on public.app_post_places;
drop policy if exists "users can insert own post places" on public.app_post_places;
drop policy if exists "users can update own post places" on public.app_post_places;
drop policy if exists "users can delete own post places" on public.app_post_places;

create policy "users can insert own post places"
on public.app_post_places
for insert
to authenticated
with check (
  exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id::text = app_post_places.legacy_post_id::text
      and p.app_user_id::text = (select private.captro_current_app_user_id())
  )
);

create policy "users can update own post places"
on public.app_post_places
for update
to authenticated
using (
  exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id::text = app_post_places.legacy_post_id::text
      and p.app_user_id::text = (select private.captro_current_app_user_id())
  )
)
with check (
  exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id::text = app_post_places.legacy_post_id::text
      and p.app_user_id::text = (select private.captro_current_app_user_id())
  )
);

create policy "users can delete own post places"
on public.app_post_places
for delete
to authenticated
using (
  exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id::text = app_post_places.legacy_post_id::text
      and p.app_user_id::text = (select private.captro_current_app_user_id())
  )
);
