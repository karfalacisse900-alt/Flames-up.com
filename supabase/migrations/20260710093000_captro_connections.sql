-- Captro connection-system upgrade.
-- Keeps the existing app_friend_requests/app_friendships tables, but upgrades them
-- from legacy "friend/follow" wording to private request/accept connection state.

alter table if exists public.app_friend_requests
  add column if not exists note text,
  add column if not exists accepted_at timestamptz,
  add column if not exists responded_at timestamptz,
  add column if not exists expired_at timestamptz,
  add column if not exists cancelled_at timestamptz;

alter table if exists public.app_friend_requests
  drop constraint if exists app_friend_requests_status_check;

alter table if exists public.app_friend_requests
  add constraint app_friend_requests_status_check
  check (status in ('pending', 'accepted', 'declined', 'rejected', 'cancelled', 'expired', 'removed', 'blocked'));

create index if not exists app_friend_requests_active_reverse_idx
  on public.app_friend_requests (to_user_id, from_user_id, status, created_at desc);

create index if not exists app_friend_requests_expiration_idx
  on public.app_friend_requests (status, created_at)
  where status = 'pending';

comment on table public.app_friend_requests is
  'Captro private connection requests. Pending requests are not public follower state.';

comment on table public.app_friendships is
  'Captro accepted connections, stored bidirectionally. Messaging unlocks only through these rows.';
