-- Keep native Supabase UUID interaction rows one-per-user-per-post-per-kind.
-- The legacy text-id uniqueness already protects the current Worker path; this
-- index protects future native post_id/user_id writes without changing schema.
create unique index if not exists app_post_interactions_native_unique
  on public.app_post_interactions (post_id, user_id, kind)
  where post_id is not null and user_id is not null;
