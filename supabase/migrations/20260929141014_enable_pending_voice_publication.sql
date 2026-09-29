-- A recorded post/reply must remain private until the version-bound voice
-- moderation RPC approves it. The original voice migration introduced that
-- state in application code but did not extend these existing checks.
alter table public.app_posts drop constraint if exists app_posts_status_check;
alter table public.app_posts add constraint app_posts_status_check
  check (status in ('active', 'archived', 'removed', 'pending_voice'));

alter table public.post_comments drop constraint if exists post_comments_status_check;
alter table public.post_comments add constraint post_comments_status_check
  check (status in ('active', 'removed', 'hidden', 'pending_voice'));

-- Voice-only replies have no typed caption. Permit an empty body only when
-- it has a bound private voice reference; ordinary empty comments stay invalid.
alter table public.post_comments drop constraint if exists post_comments_body_check;
alter table public.post_comments add constraint post_comments_body_check
  check (
    char_length(body) between 1 and 1200
    or (body = '' and coalesce(metadata #>> '{voice,id}', '') <> '')
  );
