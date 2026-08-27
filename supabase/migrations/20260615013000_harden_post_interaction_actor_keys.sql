-- Enforce one like/save per real account, even when an older app user id and a
-- Supabase auth user id both exist for the same person.

alter table public.app_post_interactions
  add column if not exists actor_key text;

update public.app_post_interactions
set actor_key = 'auth:' || user_id::text,
    updated_at = now()
where actor_key is null
  and user_id is not null;

with identity_keys as (
  select
    user_id,
    coalesce(
      min('provider:' || provider || ':' || provider_user_id) filter (
        where provider is not null and provider_user_id is not null and provider <> '' and provider_user_id <> ''
      ),
      min('email:' || email_hash) filter (
        where email_hash is not null and email_hash <> ''
      )
    ) as actor_key
  from public.app_account_identities
  group by user_id
)
update public.app_post_interactions i
set actor_key = k.actor_key,
    updated_at = now()
from identity_keys k
where i.actor_key is null
  and i.app_user_id = k.user_id
  and k.actor_key is not null;

update public.app_post_interactions
set actor_key = 'app:' || app_user_id,
    updated_at = now()
where actor_key is null
  and app_user_id is not null
  and app_user_id <> '';

with ranked as (
  select
    ctid,
    row_number() over (
      partition by legacy_post_id, kind, actor_key
      order by created_at desc nulls last, legacy_created_at desc nulls last, updated_at desc nulls last
    ) as row_number
  from public.app_post_interactions
  where actor_key is not null
)
delete from public.app_post_interactions i
using ranked r
where i.ctid = r.ctid
  and r.row_number > 1;

with ranked as (
  select
    ctid,
    row_number() over (
      partition by post_id, kind, actor_key
      order by created_at desc nulls last, legacy_created_at desc nulls last, updated_at desc nulls last
    ) as row_number
  from public.app_post_interactions
  where actor_key is not null
    and post_id is not null
)
delete from public.app_post_interactions i
using ranked r
where i.ctid = r.ctid
  and r.row_number > 1;

create unique index if not exists app_post_interactions_legacy_actor_unique
  on public.app_post_interactions (legacy_post_id, kind, actor_key)
  where actor_key is not null;

create unique index if not exists app_post_interactions_native_actor_unique
  on public.app_post_interactions (post_id, kind, actor_key)
  where post_id is not null and actor_key is not null;

create index if not exists app_post_interactions_actor_idx
  on public.app_post_interactions (actor_key, kind, created_at desc)
  where actor_key is not null;

with actor_counts as (
  select
    coalesce(i.legacy_post_id, p.legacy_post_id) as legacy_post_id,
    count(distinct coalesce(i.actor_key, 'auth:' || i.user_id::text, 'app:' || i.app_user_id)) filter (where i.kind = 'like') as likes_count,
    count(distinct coalesce(i.actor_key, 'auth:' || i.user_id::text, 'app:' || i.app_user_id)) filter (where i.kind = 'save') as saves_count
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
