-- Captro database governance markers.
--
-- This migration is intentionally non-destructive. It documents the canonical
-- Supabase tables, reinforces RLS on production app tables, and labels legacy
-- compatibility tables so future work does not drift back into Table Editor or
-- D1-era data paths.

alter table if exists public.app_users enable row level security;
alter table if exists public.app_posts enable row level security;
alter table if exists public.app_media_assets enable row level security;
alter table if exists public.post_comments enable row level security;
alter table if exists public.app_post_interactions enable row level security;
alter table if exists public.app_follows enable row level security;
alter table if exists public.app_blocks enable row level security;
alter table if exists public.app_stories enable row level security;
alter table if exists public.app_messages enable row level security;
alter table if exists public.app_group_chats enable row level security;
alter table if exists public.app_group_chat_members enable row level security;
alter table if exists public.app_group_messages enable row level security;
alter table if exists public.app_notifications enable row level security;
alter table if exists public.app_reports enable row level security;
alter table if exists public.app_admin_roles enable row level security;
alter table if exists public.app_moderation_jobs enable row level security;
alter table if exists public.app_moderation_results enable row level security;
alter table if exists public.app_moderation_events enable row level security;
alter table if exists public.app_moderation_actions enable row level security;
alter table if exists public.app_audit_logs enable row level security;
alter table if exists public.app_account_identities enable row level security;
alter table if exists public.app_deleted_account_safety_records enable row level security;

comment on table public.app_users is
  'Captro canonical app profile/account table. Managed by SQL migrations in GitHub; do not change manually in Table Editor.';
comment on table public.app_posts is
  'Captro canonical post table for feed, discover, profile, captions, categories, counters, and media metadata references.';
comment on table public.app_media_assets is
  'Captro canonical media metadata table. Media binaries live in Cloudflare Images/Stream/R2; Postgres stores metadata/status only.';
comment on table public.post_comments is
  'Captro canonical post comments table. Use cursor pagination by post_id/created_at and enforce ownership through RLS/backend checks.';
comment on table public.app_post_interactions is
  'Captro canonical likes, saves, and reposts table. One row per actor/post/kind; counters must be derived from or reconciled with this table.';
comment on table public.app_follows is
  'Captro canonical follow relationship table. Keep app_user_id and Supabase auth identity fields synchronized during legacy cutover.';
comment on table public.app_blocks is
  'Captro canonical block relationship table. Feed, discover, comments, profiles, and messages must respect this table.';
comment on table public.app_stories is
  'Captro canonical stories table. Stores story metadata, Cloudflare media references, audio metadata, visibility, and expiry.';
comment on table public.app_messages is
  'Captro canonical direct messages table. Private message access must stay participant-only through RLS and backend checks.';
comment on table public.app_group_chats is
  'Captro canonical group conversation table.';
comment on table public.app_group_chat_members is
  'Captro canonical group membership table. Membership gates group chat/message access.';
comment on table public.app_group_messages is
  'Captro canonical group messages table. Access is limited to group members.';
comment on table public.app_notifications is
  'Captro canonical notification table. Users may read/update only their own notifications.';
comment on table public.app_reports is
  'Captro canonical user report table. Reporter identity must not be exposed to reported users.';
comment on table public.app_admin_roles is
  'Captro admin role table. Admin permissions must be enforced by backend and RLS; no frontend-only admin trust.';
comment on table public.app_moderation_jobs is
  'Captro moderation job queue metadata. Cloudflare Queues/Workers process media/text moderation and write results here.';
comment on table public.app_moderation_results is
  'Captro moderation result table. Raw model output is private and for backend/admin review only.';
comment on table public.app_moderation_events is
  'Captro moderation event history. Used for admin review and auditability.';
comment on table public.app_moderation_actions is
  'Captro admin moderation actions. Every destructive admin action should have an audit trail.';
comment on table public.app_audit_logs is
  'Captro admin/system audit log. Read access is admin-only.';
comment on table public.app_account_identities is
  'Captro auth identity mapping table for email, Apple, Google, and other providers. Do not rely on email alone for identity.';
comment on table public.app_deleted_account_safety_records is
  'Minimal retained safety records for deleted/banned identity abuse prevention. Do not store full deleted account content here.';

comment on table public.profiles is
  'Legacy/Supabase-auth profile compatibility table. New Captro app profile logic should use public.app_users unless a migration explicitly says otherwise.';
comment on table public.follows is
  'Legacy follow compatibility table. New Captro app follow logic should use public.app_follows.';
comment on table public.post_interactions is
  'Legacy interaction compatibility table. New Captro likes/saves must use public.app_post_interactions.';

comment on column public.app_post_interactions.actor_key is
  'Stable dedupe key for interaction actor identity during auth/app-user cutover. Do not remove until all clients use canonical Supabase user ids.';
comment on column public.app_posts.legacy_post_id is
  'Temporary legacy id mapping for D1/old API cutover. New code should prefer app_posts.id.';
comment on column public.app_posts.media is
  'Lightweight JSON metadata/URLs only. Do not store image or video binaries in Postgres.';
