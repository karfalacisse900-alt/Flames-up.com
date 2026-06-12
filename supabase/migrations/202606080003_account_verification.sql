-- Captro account verification fields for Supabase Postgres.
-- Twilio secrets stay in the Cloudflare Worker; Postgres stores status only.

alter table public.app_users
  add column if not exists phone text,
  add column if not exists phone_verified boolean not null default false,
  add column if not exists email_verified boolean not null default false;

create index if not exists app_users_phone_idx
  on public.app_users (phone)
  where phone is not null;

create index if not exists app_users_contact_verification_idx
  on public.app_users (email_verified, phone_verified);
