-- Captro media provenance summary for Cloudflare Images Content Credentials / C2PA.
-- Cloudflare stores and transforms image binaries; Supabase stores only
-- verification status and a small metadata summary for moderation/search.

alter table if exists public.app_media_assets
  add column if not exists has_content_credentials boolean not null default false,
  add column if not exists c2pa_verified boolean not null default false,
  add column if not exists c2pa_creator text,
  add column if not exists c2pa_created_at timestamptz,
  add column if not exists c2pa_ai_used boolean not null default false,
  add column if not exists c2pa_edit_history_summary text,
  add column if not exists media_origin_status text not null default 'not_checked',
  add column if not exists c2pa_metadata jsonb not null default '{}'::jsonb;

do $$
begin
  if to_regclass('public.app_media_assets') is not null
     and not exists (
       select 1
       from pg_constraint
       where conname = 'app_media_assets_media_origin_status_check'
         and conrelid = 'public.app_media_assets'::regclass
     ) then
    alter table public.app_media_assets
      add constraint app_media_assets_media_origin_status_check
      check (
        media_origin_status in (
          'not_checked',
          'not_applicable',
          'missing_credentials',
          'verified_original',
          'verified_edited',
          'ai_generated',
          'invalid',
          'verifier_unavailable'
        )
      );
  end if;
end $$;

create index if not exists app_media_assets_origin_status_idx
  on public.app_media_assets (media_origin_status, created_at desc);

create index if not exists app_media_assets_content_credentials_idx
  on public.app_media_assets (has_content_credentials, c2pa_verified, created_at desc);

comment on column public.app_media_assets.has_content_credentials is
  'True when a server-side C2PA verifier finds Content Credentials in the uploaded image.';

comment on column public.app_media_assets.c2pa_verified is
  'True only when the Content Credentials signature/claim is verified by trusted server-side verification.';

comment on column public.app_media_assets.c2pa_creator is
  'Short creator/claimant summary from verified C2PA metadata, when present.';

comment on column public.app_media_assets.c2pa_created_at is
  'Creation timestamp from verified C2PA metadata, when present.';

comment on column public.app_media_assets.c2pa_ai_used is
  'True when C2PA metadata declares generative AI usage or equivalent synthetic-media signal.';

comment on column public.app_media_assets.c2pa_edit_history_summary is
  'Short safe summary of provenance/edit history. No raw manifests or private metadata.';

comment on column public.app_media_assets.media_origin_status is
  'Provenance state: not_checked, not_applicable, missing_credentials, verified_original, verified_edited, ai_generated, invalid, verifier_unavailable.';

comment on column public.app_media_assets.c2pa_metadata is
  'Small sanitized C2PA summary JSON for admin/debug. Raw C2PA manifests remain outside Supabase.';
