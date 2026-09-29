-- One reversible, single-choice response per account and post. The Worker is
-- the only writer: it verifies post visibility and the creator's chosen mode.
create table if not exists public.app_post_responses (
  post_id uuid not null references public.app_posts(id) on delete cascade,
  app_user_id text not null,
  actor_key text not null,
  selected_option text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_post_responses_pk primary key (post_id, actor_key),
  constraint app_post_responses_option_length check (char_length(selected_option) between 1 and 80)
);

create index if not exists app_post_responses_post_option_idx
  on public.app_post_responses (post_id, selected_option);

create index if not exists app_post_responses_user_idx
  on public.app_post_responses (app_user_id, updated_at desc);

alter table public.app_post_responses enable row level security;
revoke all on public.app_post_responses from anon, authenticated;
grant select, insert, update, delete on public.app_post_responses to service_role;

-- Aggregate in Postgres rather than downloading every response into the feed.
create or replace view public.app_post_response_counts
with (security_invoker = true) as
select post_id, selected_option, count(*)::bigint as response_count
from public.app_post_responses
group by post_id, selected_option;

revoke all on public.app_post_response_counts from anon, authenticated;
grant select on public.app_post_response_counts to service_role;
