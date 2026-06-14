-- Remove engagement rows that point at posts no longer present in Supabase.
-- These rows can make legacy counters and diagnostics confusing, but they
-- should never represent visible app state.

delete from public.app_post_interactions i
where not exists (
    select 1
    from public.app_posts p
    where p.legacy_post_id = i.legacy_post_id
       or p.id = i.post_id
  );

update public.app_post_interactions i
set
  post_id = p.id,
  updated_at = now()
from public.app_posts p
where i.post_id is null
  and i.legacy_post_id is not null
  and p.legacy_post_id = i.legacy_post_id;

with actor_counts as (
  select
    p.legacy_post_id,
    count(distinct coalesce(i.user_id::text, u.supabase_user_id::text, i.app_user_id)) filter (where i.kind = 'like') as likes_count,
    count(distinct coalesce(i.user_id::text, u.supabase_user_id::text, i.app_user_id)) filter (where i.kind = 'save') as saves_count
  from public.app_posts p
  left join public.app_post_interactions i
    on i.legacy_post_id = p.legacy_post_id
    or i.post_id = p.id
  left join public.app_users u
    on u.id = i.app_user_id
    or u.supabase_user_id::text = i.app_user_id
  group by p.legacy_post_id
)
update public.app_posts p
set
  likes_count = coalesce(a.likes_count, 0),
  saves_count = coalesce(a.saves_count, 0),
  updated_at = now()
from actor_counts a
where a.legacy_post_id = p.legacy_post_id
  and (
    p.likes_count is distinct from coalesce(a.likes_count, 0)
    or p.saves_count is distinct from coalesce(a.saves_count, 0)
  );
