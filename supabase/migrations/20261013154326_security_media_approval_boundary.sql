-- APPROVAL REQUIRED: deploy after 20261006012846_security_backend_write_boundary.
-- Upload intent, completion, moderation and crop updates already use the Worker.
-- A row-owner policy cannot make moderation_status/upload_status server-owned.
begin;
revoke insert, update, delete, truncate, references, trigger
  on public.app_media_assets from public, anon, authenticated;

-- Explicit column grants survive table-level REVOKE. Remove any historic ones,
-- including metadata and asset URLs which could forge an approved asset.
do $$
declare column_name text;
begin
  for column_name in select a.attname from pg_attribute a
    where a.attrelid = 'public.app_media_assets'::regclass
      and a.attnum > 0 and not a.attisdropped
  loop
    execute format('revoke insert (%I), update (%I), references (%I) on public.app_media_assets from public, anon, authenticated',
      column_name, column_name, column_name);
  end loop;
end $$;

drop policy if exists "users can create own media assets" on public.app_media_assets;
drop policy if exists "users can update own media assets before publish" on public.app_media_assets;
-- Keep the existing owner-only SELECT policy and all original files/rows.
commit;
