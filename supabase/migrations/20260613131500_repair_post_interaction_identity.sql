-- Backfill native Supabase post/user identity on engagement rows.
-- Likes and saves remain keyed by the stable legacy post id for compatibility,
-- but app_post_interactions.post_id/user_id must be filled so native reads,
-- uniqueness checks, and future Supabase-first writes cannot drift.

update public.app_post_interactions i
set
  post_id = p.id,
  updated_at = now()
from public.app_posts p
where i.post_id is null
  and i.legacy_post_id is not null
  and p.legacy_post_id = i.legacy_post_id;

update public.app_post_interactions i
set
  user_id = u.supabase_user_id,
  updated_at = now()
from public.app_users u
where i.user_id is null
  and i.app_user_id is not null
  and u.id = i.app_user_id
  and u.supabase_user_id is not null;

with actor_counts as (
  select
    coalesce(i.legacy_post_id, p.legacy_post_id) as legacy_post_id,
    count(distinct coalesce(i.user_id::text, i.app_user_id)) filter (where i.kind = 'like') as likes_count,
    count(distinct coalesce(i.user_id::text, i.app_user_id)) filter (where i.kind = 'save') as saves_count
  from public.app_post_interactions i
  left join public.app_posts p on p.id = i.post_id
  where coalesce(i.legacy_post_id, p.legacy_post_id) is not null
  group by coalesce(i.legacy_post_id, p.legacy_post_id)
)
update public.app_posts p
set
  likes_count = coalesce(a.likes_count, 0),
  saves_count = coalesce(a.saves_count, 0),
  updated_at = now()
from actor_counts a
where p.legacy_post_id = a.legacy_post_id
  and (
    p.likes_count is distinct from coalesce(a.likes_count, 0)
    or p.saves_count is distinct from coalesce(a.saves_count, 0)
  );

update public.app_posts p
set
  likes_count = 0,
  saves_count = 0,
  updated_at = now()
where not exists (
    select 1
    from public.app_post_interactions i
    where i.legacy_post_id = p.legacy_post_id
       or i.post_id = p.id
  )
  and (p.likes_count <> 0 or p.saves_count <> 0);
