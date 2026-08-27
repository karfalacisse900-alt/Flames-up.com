-- Re-run canonical interaction repair after Supabase-first rollout.
-- This cleans up any lingering mixed identity rows that can make a single
-- person look unliked on reopen while still inflating counts.

alter table public.app_post_interactions
  add column if not exists actor_key text;

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
    ) as identity_actor_key
  from public.app_account_identities
  group by user_id
),
canonical as (
  select
    i.ctid,
    coalesce(au.id, i.user_id) as canonical_auth_user_id,
    coalesce(
      case when au.id is not null then 'auth:' || au.id::text end,
      case when i.user_id is not null then 'auth:' || i.user_id::text end,
      k.identity_actor_key,
      case when i.app_user_id is not null and i.app_user_id <> '' then 'app:' || i.app_user_id end
    ) as canonical_actor_key
  from public.app_post_interactions i
  left join public.app_users u
    on u.id = i.app_user_id
  left join auth.users au
    on au.id = u.supabase_user_id
  left join identity_keys k
    on k.user_id = i.app_user_id
)
update public.app_post_interactions i
set
  actor_key = c.canonical_actor_key,
  user_id = c.canonical_auth_user_id,
  updated_at = now()
from canonical c
where i.ctid = c.ctid
  and c.canonical_actor_key is not null
  and (
    i.actor_key is distinct from c.canonical_actor_key
    or i.user_id is distinct from c.canonical_auth_user_id
  );

update public.app_post_interactions
set actor_key = 'auth:' || user_id::text,
    updated_at = now()
where actor_key is null
  and user_id is not null;

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
      partition by coalesce(legacy_post_id, post_id::text), kind, actor_key
      order by created_at desc nulls last, legacy_created_at desc nulls last, updated_at desc nulls last
    ) as row_number
  from public.app_post_interactions
  where actor_key is not null
)
delete from public.app_post_interactions i
using ranked r
where i.ctid = r.ctid
  and r.row_number > 1;

with actor_counts as (
  select
    p.id as post_id,
    count(distinct i.actor_key) filter (where i.kind = 'like') as likes_count,
    count(distinct i.actor_key) filter (where i.kind = 'save') as saves_count
  from public.app_posts p
  left join public.app_post_interactions i
    on i.legacy_post_id = p.legacy_post_id
    or i.post_id = p.id
  group by p.id
)
update public.app_posts p
set
  likes_count = coalesce(a.likes_count, 0),
  saves_count = coalesce(a.saves_count, 0),
  updated_at = now()
from actor_counts a
where p.id = a.post_id
  and (
    p.likes_count is distinct from coalesce(a.likes_count, 0)
    or p.saves_count is distinct from coalesce(a.saves_count, 0)
  );

create unique index if not exists app_post_interactions_legacy_actor_unique
  on public.app_post_interactions (legacy_post_id, kind, actor_key)
  where actor_key is not null;

create unique index if not exists app_post_interactions_native_actor_unique
  on public.app_post_interactions (post_id, kind, actor_key)
  where post_id is not null and actor_key is not null;
