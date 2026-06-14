-- Supabase-primary post creation stores the client idempotency key in
-- app_posts.metadata->>'client_request_id'. Keep retries one-per-user even
-- though app_posts intentionally keeps legacy_post_id for API compatibility.

create unique index if not exists app_posts_user_client_request_unique_idx
  on public.app_posts (app_user_id, ((metadata->>'client_request_id')))
  where app_user_id is not null
    and coalesce(metadata->>'client_request_id', '') <> '';
