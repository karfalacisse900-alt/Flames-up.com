-- Captro Supabase Postgres operational schema.
-- Completes the structured data target beyond the first core transfer tables.
-- Clients should still access these records through the Cloudflare Worker API.

create table if not exists public.app_blocks (
  id text primary key,
  blocker_id text not null,
  blocked_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_blocks_unique_pair unique (blocker_id, blocked_id)
);

create index if not exists app_blocks_blocker_idx
  on public.app_blocks (blocker_id, created_at desc);

create index if not exists app_blocks_blocked_idx
  on public.app_blocks (blocked_id, created_at desc);

create table if not exists public.app_notifications (
  id text primary key,
  user_id text not null,
  from_user_id text,
  type text not null default 'general',
  title text not null default '',
  body text not null default '',
  content text not null default '',
  reference_id text,
  data jsonb not null default '{}'::jsonb,
  is_read boolean not null default false,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_notifications_user_created_idx
  on public.app_notifications (user_id, created_at desc);

create index if not exists app_notifications_user_unread_idx
  on public.app_notifications (user_id, is_read, created_at desc);

create table if not exists public.app_reports (
  id text primary key,
  reporter_id text not null,
  target_type text not null,
  target_id text not null,
  target_owner_user_id text,
  reason text not null,
  details text not null default '',
  status text not null default 'open',
  priority text not null default 'normal',
  assigned_to text,
  reviewed_by text,
  action_taken text,
  admin_notes text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  legacy_updated_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_reports_status_priority_idx
  on public.app_reports (status, priority, created_at desc);

create index if not exists app_reports_target_idx
  on public.app_reports (target_type, target_id, created_at desc);

create index if not exists app_reports_reporter_idx
  on public.app_reports (reporter_id, created_at desc);

create table if not exists public.app_messages (
  id text primary key,
  sender_id text not null,
  receiver_id text not null,
  conversation_id text,
  body text not null default '',
  media_url text,
  media_type text,
  media jsonb not null default '{}'::jsonb,
  is_read boolean not null default false,
  status text not null default 'sent',
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_messages_pair_created_idx
  on public.app_messages (sender_id, receiver_id, created_at desc);

create index if not exists app_messages_receiver_read_idx
  on public.app_messages (receiver_id, is_read, created_at desc);

create index if not exists app_messages_conversation_idx
  on public.app_messages (conversation_id, created_at asc);

create table if not exists public.app_group_chats (
  id text primary key,
  name text not null default '',
  created_by text not null,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_group_chat_members (
  id text primary key,
  group_id text not null,
  user_id text not null,
  role text not null default 'member',
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_group_chat_members_unique unique (group_id, user_id)
);

create table if not exists public.app_group_messages (
  id text primary key,
  group_id text not null,
  sender_id text not null,
  body text not null default '',
  media_url text,
  media_type text,
  media jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_group_chat_members_user_idx
  on public.app_group_chat_members (user_id, created_at desc);

create index if not exists app_group_messages_group_idx
  on public.app_group_messages (group_id, created_at asc);

create table if not exists public.app_post_places (
  id text primary key,
  legacy_post_id text not null,
  provider text not null default 'apple_mapkit',
  provider_place_id text,
  name text not null default '',
  formatted_address text not null default '',
  latitude double precision,
  longitude double precision,
  category text,
  city text,
  region text,
  country text,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_post_places_post_provider unique (legacy_post_id, provider)
);

create index if not exists app_post_places_post_idx
  on public.app_post_places (legacy_post_id);

create table if not exists public.app_media_assets (
  id text primary key,
  user_id text not null,
  legacy_post_id text,
  media_type text not null,
  storage_provider text not null,
  storage_key text not null,
  public_url text,
  private_url text,
  mime_type text not null default '',
  file_size bigint not null default 0,
  sha256_hash text not null default '',
  width integer,
  height integer,
  duration_seconds double precision,
  upload_status text not null default 'uploading',
  moderation_status text not null default 'uploading',
  rejection_code text,
  rejection_message text,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_media_assets_user_created_idx
  on public.app_media_assets (user_id, created_at desc);

create index if not exists app_media_assets_status_idx
  on public.app_media_assets (moderation_status, created_at desc);

create index if not exists app_media_assets_hash_idx
  on public.app_media_assets (sha256_hash);

create table if not exists public.app_moderation_results (
  id text primary key,
  media_id text not null,
  model_name text not null,
  adult_explicit_score double precision not null default 0,
  nudity_score double precision not null default 0,
  sexual_context_score double precision not null default 0,
  sexual_solicitation_score double precision not null default 0,
  minor_safety_risk_score double precision not null default 0,
  violence_score double precision not null default 0,
  gore_score double precision not null default 0,
  weapon_score double precision not null default 0,
  hate_symbol_score double precision not null default 0,
  ai_generated_likelihood double precision not null default 0,
  spam_scam_score double precision not null default 0,
  malware_status text not null default 'unknown',
  link_risk_score double precision not null default 0,
  confidence double precision not null default 0,
  decision text not null,
  reasons jsonb not null default '[]'::jsonb,
  raw_result jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists app_moderation_results_media_idx
  on public.app_moderation_results (media_id, created_at desc);

create table if not exists public.app_admin_roles (
  user_id text primary key,
  role text not null,
  created_by text,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_moderation_actions (
  id text primary key,
  actor_admin_user_id text not null,
  actor_role text not null default '',
  action_type text not null,
  target_type text not null,
  target_id text not null,
  target_user_id text,
  reason text not null default '',
  note text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_moderation_actions_target_idx
  on public.app_moderation_actions (target_type, target_id, created_at desc);

create table if not exists public.app_audit_logs (
  id text primary key,
  actor_admin_user_id text not null,
  actor_role text not null default '',
  action_type text not null,
  target_type text not null,
  target_id text not null,
  target_user_id text,
  reason text not null default '',
  internal_note text not null default '',
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  request_id text,
  metadata jsonb not null default '{}'::jsonb,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists app_audit_logs_actor_idx
  on public.app_audit_logs (actor_admin_user_id, created_at desc);

create index if not exists app_audit_logs_target_idx
  on public.app_audit_logs (target_type, target_id, created_at desc);

create table if not exists public.app_push_tokens (
  id text primary key,
  user_id text not null,
  token_hash text not null,
  device_id text,
  bundle_id text,
  environment text not null default 'production',
  platform text not null default 'ios',
  is_active boolean not null default true,
  last_seen_at timestamptz,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_push_tokens_unique unique (user_id, token_hash)
);

create index if not exists app_push_tokens_user_active_idx
  on public.app_push_tokens (user_id, is_active, last_seen_at desc);

create table if not exists public.app_account_identities (
  id text primary key,
  user_id text not null,
  provider text not null,
  provider_user_id text not null,
  email_hash text,
  legacy_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_account_identities_provider_unique unique (provider, provider_user_id)
);

create index if not exists app_account_identities_user_idx
  on public.app_account_identities (user_id);

create index if not exists app_account_identities_email_hash_idx
  on public.app_account_identities (email_hash);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'app_blocks',
    'app_notifications',
    'app_reports',
    'app_messages',
    'app_group_chats',
    'app_group_chat_members',
    'app_group_messages',
    'app_post_places',
    'app_media_assets',
    'app_moderation_results',
    'app_admin_roles',
    'app_moderation_actions',
    'app_audit_logs',
    'app_push_tokens',
    'app_account_identities'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
  end loop;
end $$;

drop trigger if exists app_blocks_set_updated_at on public.app_blocks;
create trigger app_blocks_set_updated_at
before update on public.app_blocks
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_notifications_set_updated_at on public.app_notifications;
create trigger app_notifications_set_updated_at
before update on public.app_notifications
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_reports_set_updated_at on public.app_reports;
create trigger app_reports_set_updated_at
before update on public.app_reports
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_messages_set_updated_at on public.app_messages;
create trigger app_messages_set_updated_at
before update on public.app_messages
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_media_assets_set_updated_at on public.app_media_assets;
create trigger app_media_assets_set_updated_at
before update on public.app_media_assets
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_admin_roles_set_updated_at on public.app_admin_roles;
create trigger app_admin_roles_set_updated_at
before update on public.app_admin_roles
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_moderation_actions_set_updated_at on public.app_moderation_actions;
create trigger app_moderation_actions_set_updated_at
before update on public.app_moderation_actions
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_push_tokens_set_updated_at on public.app_push_tokens;
create trigger app_push_tokens_set_updated_at
before update on public.app_push_tokens
for each row execute function public.set_captro_updated_at();

drop trigger if exists app_account_identities_set_updated_at on public.app_account_identities;
create trigger app_account_identities_set_updated_at
before update on public.app_account_identities
for each row execute function public.set_captro_updated_at();
