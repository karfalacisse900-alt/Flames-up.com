-- Align older Captro Supabase databases with the production Supabase-primary
-- post identity model. The app keeps legacy_post_id for API compatibility,
-- but new code treats app_posts.id as the canonical Postgres row id.

alter table public.app_posts
  add column if not exists id uuid;

update public.app_posts
set id = gen_random_uuid()
where id is null;

alter table public.app_posts
  alter column id set default gen_random_uuid();

alter table public.app_posts
  alter column id set not null;

do $$
declare
  primary_columns text[];
begin
  select array_agg(a.attname order by a.attnum)
    into primary_columns
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  join unnest(c.conkey) with ordinality keys(attnum, ord) on true
  join pg_attribute a on a.attrelid = t.oid and a.attnum = keys.attnum
  where n.nspname = 'public'
    and t.relname = 'app_posts'
    and c.contype = 'p'
  group by c.oid;

  if primary_columns is null or primary_columns <> array['id'] then
    if exists (
      select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where n.nspname = 'public'
        and t.relname = 'app_posts'
        and c.contype = 'p'
    ) then
      alter table public.app_posts drop constraint app_posts_pkey;
    end if;

    alter table public.app_posts
      add constraint app_posts_pkey primary key (id);
  end if;
end $$;

alter table public.app_posts
  alter column legacy_post_id drop not null;

create unique index if not exists app_posts_legacy_post_id_key
  on public.app_posts (legacy_post_id)
  where legacy_post_id is not null;

