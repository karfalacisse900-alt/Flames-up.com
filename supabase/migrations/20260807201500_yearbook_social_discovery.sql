begin;

-- Yearbook extends the canonical app_users identity. Raw optional fields are
-- owner-only under RLS; the Worker returns a visibility-shaped public payload.
create table if not exists public.yearbook_profiles (
  user_id text primary key references public.app_users(id) on delete cascade,
  discovery_intent text not null default 'friends',
  dating_enabled boolean not null default false,
  age smallint,
  height_cm smallint,
  city text not null default '',
  country text not null default '',
  job text not null default '',
  school text not null default '',
  short_bio text not null default '',
  current_mood text not null default '',
  languages text[] not null default '{}'::text[],
  interests text[] not null default '{}'::text[],
  hobbies text[] not null default '{}'::text[],
  favorites jsonb not null default '{}'::jsonb,
  field_visibility jsonb not null default '{}'::jsonb,
  section_order text[] not null default array['about', 'details', 'interests', 'prompts', 'favorites']::text[],
  theme_id text not null default 'classic_yearbook',
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint yearbook_profiles_intent_check check (
    discovery_intent in ('friends', 'dating', 'friends_and_dating', 'creative_networking', 'just_browsing')
  ),
  constraint yearbook_profiles_theme_check check (
    theme_id in ('classic_yearbook', 'notebook', 'y2k', 'film', 'minimal', 'vintage', 'scrapbook')
  ),
  constraint yearbook_profiles_status_check check (status in ('active', 'hidden')),
  constraint yearbook_profiles_age_check check (age is null or age between 16 and 120),
  constraint yearbook_profiles_dating_age_check check (not dating_enabled or age >= 18),
  constraint yearbook_profiles_height_check check (height_cm is null or height_cm between 90 and 250),
  constraint yearbook_profiles_city_length_check check (char_length(city) <= 120),
  constraint yearbook_profiles_country_length_check check (char_length(country) <= 120),
  constraint yearbook_profiles_job_length_check check (char_length(job) <= 120),
  constraint yearbook_profiles_school_length_check check (char_length(school) <= 160),
  constraint yearbook_profiles_bio_length_check check (char_length(short_bio) <= 320),
  constraint yearbook_profiles_mood_length_check check (char_length(current_mood) <= 80),
  constraint yearbook_profiles_language_count_check check (cardinality(languages) <= 12),
  constraint yearbook_profiles_interest_count_check check (cardinality(interests) <= 20),
  constraint yearbook_profiles_hobby_count_check check (cardinality(hobbies) <= 20),
  constraint yearbook_profiles_section_count_check check (cardinality(section_order) <= 8),
  constraint yearbook_profiles_favorites_shape_check check (
    jsonb_typeof(favorites) = 'object' and octet_length(favorites::text) <= 6000
  ),
  constraint yearbook_profiles_visibility_shape_check check (
    jsonb_typeof(field_visibility) = 'object' and octet_length(field_visibility::text) <= 5000
  )
);

create index if not exists yearbook_profiles_discovery_idx
  on public.yearbook_profiles (status, discovery_intent, updated_at desc);

create index if not exists yearbook_profiles_city_age_idx
  on public.yearbook_profiles (lower(city), age, updated_at desc)
  where status = 'active';

create index if not exists yearbook_profiles_interests_gin_idx
  on public.yearbook_profiles using gin (interests);

create index if not exists yearbook_profiles_languages_gin_idx
  on public.yearbook_profiles using gin (languages);

create table if not exists public.yearbook_prompt_answers (
  id uuid primary key default gen_random_uuid(),
  user_id text not null references public.app_users(id) on delete cascade,
  prompt_key text not null,
  answer text not null,
  position smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint yearbook_prompt_answers_unique unique (user_id, prompt_key),
  constraint yearbook_prompt_key_check check (
    prompt_key ~ '^[a-z0-9_]{3,60}$'
  ),
  constraint yearbook_prompt_answer_check check (char_length(answer) between 1 and 240),
  constraint yearbook_prompt_position_check check (position between 0 and 4)
);

create index if not exists yearbook_prompt_answers_user_position_idx
  on public.yearbook_prompt_answers (user_id, position, created_at);

create table if not exists public.yearbook_signatures (
  id uuid primary key default gen_random_uuid(),
  profile_user_id text not null references public.app_users(id) on delete cascade,
  signer_user_id text not null references public.app_users(id) on delete cascade,
  message text not null default '',
  status text not null default 'visible',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint yearbook_signatures_unique unique (profile_user_id, signer_user_id),
  constraint yearbook_signatures_not_self check (profile_user_id <> signer_user_id),
  constraint yearbook_signatures_message_check check (char_length(message) <= 160),
  constraint yearbook_signatures_status_check check (status in ('visible', 'hidden', 'removed'))
);

create index if not exists yearbook_signatures_profile_created_idx
  on public.yearbook_signatures (profile_user_id, status, created_at desc);

create index if not exists yearbook_signatures_signer_created_idx
  on public.yearbook_signatures (signer_user_id, created_at desc);

-- Rows are intentionally readable only by the sender. The Worker checks the
-- reverse row and reveals a match only after both users opted in.
create table if not exists public.yearbook_interest_signals (
  from_user_id text not null references public.app_users(id) on delete cascade,
  to_user_id text not null references public.app_users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint yearbook_interest_signals_pk primary key (from_user_id, to_user_id),
  constraint yearbook_interest_signals_not_self check (from_user_id <> to_user_id)
);

create index if not exists yearbook_interest_signals_target_idx
  on public.yearbook_interest_signals (to_user_id, created_at desc);

drop trigger if exists yearbook_profiles_set_updated_at on public.yearbook_profiles;
create trigger yearbook_profiles_set_updated_at
before update on public.yearbook_profiles
for each row execute function public.set_captro_updated_at();

drop trigger if exists yearbook_prompt_answers_set_updated_at on public.yearbook_prompt_answers;
create trigger yearbook_prompt_answers_set_updated_at
before update on public.yearbook_prompt_answers
for each row execute function public.set_captro_updated_at();

drop trigger if exists yearbook_signatures_set_updated_at on public.yearbook_signatures;
create trigger yearbook_signatures_set_updated_at
before update on public.yearbook_signatures
for each row execute function public.set_captro_updated_at();

drop trigger if exists yearbook_interest_signals_set_updated_at on public.yearbook_interest_signals;
create trigger yearbook_interest_signals_set_updated_at
before update on public.yearbook_interest_signals
for each row execute function public.set_captro_updated_at();

alter table public.yearbook_profiles enable row level security;
alter table public.yearbook_prompt_answers enable row level security;
alter table public.yearbook_signatures enable row level security;
alter table public.yearbook_interest_signals enable row level security;

revoke all on public.yearbook_profiles from public, anon;
revoke all on public.yearbook_prompt_answers from public, anon;
revoke all on public.yearbook_signatures from public, anon;
revoke all on public.yearbook_interest_signals from public, anon;

grant select, insert, update, delete on public.yearbook_profiles to authenticated;
grant select, insert, update, delete on public.yearbook_prompt_answers to authenticated;
grant select, insert, delete on public.yearbook_signatures to authenticated;
grant select, insert, delete on public.yearbook_interest_signals to authenticated;

drop policy if exists "owners manage raw yearbook profiles" on public.yearbook_profiles;
create policy "owners manage raw yearbook profiles"
on public.yearbook_profiles
for all
to authenticated
using (user_id = (select private.captro_current_app_user_id()))
with check (user_id = (select private.captro_current_app_user_id()));

drop policy if exists "owners manage yearbook prompts" on public.yearbook_prompt_answers;
create policy "owners manage yearbook prompts"
on public.yearbook_prompt_answers
for all
to authenticated
using (user_id = (select private.captro_current_app_user_id()))
with check (user_id = (select private.captro_current_app_user_id()));

drop policy if exists "participants read yearbook signatures" on public.yearbook_signatures;
create policy "participants read yearbook signatures"
on public.yearbook_signatures
for select
to authenticated
using (
  profile_user_id = (select private.captro_current_app_user_id())
  or signer_user_id = (select private.captro_current_app_user_id())
);

drop policy if exists "users sign yearbooks as themselves" on public.yearbook_signatures;
create policy "users sign yearbooks as themselves"
on public.yearbook_signatures
for insert
to authenticated
with check (
  signer_user_id = (select private.captro_current_app_user_id())
  and profile_user_id <> signer_user_id
  and private.captro_users_not_blocked(profile_user_id, signer_user_id)
);

drop policy if exists "users remove their own yearbook signatures" on public.yearbook_signatures;
create policy "users remove their own yearbook signatures"
on public.yearbook_signatures
for delete
to authenticated
using (signer_user_id = (select private.captro_current_app_user_id()));

drop policy if exists "users read only sent yearbook interest" on public.yearbook_interest_signals;
create policy "users read only sent yearbook interest"
on public.yearbook_interest_signals
for select
to authenticated
using (from_user_id = (select private.captro_current_app_user_id()));

drop policy if exists "users send private yearbook interest" on public.yearbook_interest_signals;
create policy "users send private yearbook interest"
on public.yearbook_interest_signals
for insert
to authenticated
with check (
  from_user_id = (select private.captro_current_app_user_id())
  and from_user_id <> to_user_id
  and private.captro_users_not_blocked(from_user_id, to_user_id)
);

drop policy if exists "users remove sent yearbook interest" on public.yearbook_interest_signals;
create policy "users remove sent yearbook interest"
on public.yearbook_interest_signals
for delete
to authenticated
using (from_user_id = (select private.captro_current_app_user_id()));

comment on table public.yearbook_profiles is
  'Optional Yearbook discovery profile fields extending app_users. Raw rows are owner-only; Worker responses enforce per-field visibility.';
comment on table public.yearbook_prompt_answers is
  'A bounded set of optional Yearbook prompt answers ordered by the profile owner.';
comment on table public.yearbook_signatures is
  'One social Yearbook mark per signer and profile. It is distinct from likes and friendships.';
comment on table public.yearbook_interest_signals is
  'Private one-way dating interest. Only the sender can read the raw row; the Worker reveals mutual matches only.';

commit;
