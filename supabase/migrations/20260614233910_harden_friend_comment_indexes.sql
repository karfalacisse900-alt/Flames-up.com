-- Harden Supabase-primary engagement/friend tables for direct authenticated use.
-- D1 remains legacy/cache only; these tables are canonical app data.

create index if not exists post_comment_likes_user_id_fk_idx
  on public.post_comment_likes (user_id)
  where user_id is not null;

grant select, insert, delete on public.post_comment_likes to authenticated;
grant select, insert, update, delete on public.app_friend_requests to authenticated;
grant select, insert, update, delete on public.app_friendships to authenticated;

drop policy if exists "users can read own comment likes" on public.post_comment_likes;
create policy "users can read own comment likes"
on public.post_comment_likes
for select
to authenticated
using (
  app_user_id::text = (select private.captro_current_app_user_id())
  or user_id::text = (select auth.uid())::text
);

drop policy if exists "users can insert own comment likes" on public.post_comment_likes;
create policy "users can insert own comment likes"
on public.post_comment_likes
for insert
to authenticated
with check (
  (
    app_user_id::text = (select private.captro_current_app_user_id())
    or user_id::text = (select auth.uid())::text
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
        p.app_user_id::text = (select private.captro_current_app_user_id())
        or (
          p.visibility = 'public'
          and private.captro_users_not_blocked(
            (select private.captro_current_app_user_id()),
            p.app_user_id::text
          )
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
  app_user_id::text = (select private.captro_current_app_user_id())
  or user_id::text = (select auth.uid())::text
);

drop policy if exists "users can read own friend requests" on public.app_friend_requests;
create policy "users can read own friend requests"
on public.app_friend_requests
for select
to authenticated
using (
  from_user_id::text = (select private.captro_current_app_user_id())
  or to_user_id::text = (select private.captro_current_app_user_id())
);

drop policy if exists "users can create own friend requests" on public.app_friend_requests;
create policy "users can create own friend requests"
on public.app_friend_requests
for insert
to authenticated
with check (
  from_user_id::text = (select private.captro_current_app_user_id())
  and from_user_id::text <> to_user_id::text
  and private.captro_users_not_blocked(from_user_id::text, to_user_id::text)
);

drop policy if exists "users can update received friend requests" on public.app_friend_requests;
create policy "users can update received friend requests"
on public.app_friend_requests
for update
to authenticated
using (
  to_user_id::text = (select private.captro_current_app_user_id())
  or from_user_id::text = (select private.captro_current_app_user_id())
)
with check (
  to_user_id::text = (select private.captro_current_app_user_id())
  or from_user_id::text = (select private.captro_current_app_user_id())
);

drop policy if exists "users can read own friendships" on public.app_friendships;
create policy "users can read own friendships"
on public.app_friendships
for select
to authenticated
using (
  user_id::text = (select private.captro_current_app_user_id())
  or friend_id::text = (select private.captro_current_app_user_id())
);

drop policy if exists "users can create own friendship rows" on public.app_friendships;
create policy "users can create own friendship rows"
on public.app_friendships
for insert
to authenticated
with check (
  user_id::text = (select private.captro_current_app_user_id())
  and user_id::text <> friend_id::text
  and private.captro_users_not_blocked(user_id::text, friend_id::text)
);

drop policy if exists "users can delete own friendships" on public.app_friendships;
create policy "users can delete own friendships"
on public.app_friendships
for delete
to authenticated
using (
  user_id::text = (select private.captro_current_app_user_id())
  or friend_id::text = (select private.captro_current_app_user_id())
);
