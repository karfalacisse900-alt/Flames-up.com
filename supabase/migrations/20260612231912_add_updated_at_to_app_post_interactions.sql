-- Repair production databases where app_post_interactions existed before the
-- updated_at trigger column was added. The trigger public.set_captro_updated_at()
-- expects this column on update.
alter table if exists public.app_post_interactions
  add column if not exists updated_at timestamptz default now();

update public.app_post_interactions
set updated_at = coalesce(created_at, legacy_created_at, now())
where updated_at is null;
