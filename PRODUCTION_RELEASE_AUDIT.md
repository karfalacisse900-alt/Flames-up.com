# Captro Production Release Audit

Date: 2026-06-12

## Status

Captro's Supabase security/RLS hardening is applied in production and the app database source of truth is now documented as Supabase Postgres. Captro is not ready to mark as fully production-clean until the protected data/media reset is executed, the remaining legacy D1 route groups are removed or isolated, and a real-device smoke test passes on the latest TestFlight build.

## Verified

- Latest completed TestFlight workflow succeeded for commit `9a171948c6da4050b2e697a26c551d60ab0a935d`.
- Production backend deploy succeeded for commit `9a171948c6da4050b2e697a26c551d60ab0a935d`.
- Production `/api/health` reports `environment = "production"`, `service = "captro-api"`, `primary = "supabase_postgres"`, and `healthy = true`.
- `backend-cf` TypeScript check passes with `npx.cmd tsc --noEmit`.
- Pre-publish moderation tests pass with `npm.cmd run test:moderation`.
- `git diff --check` has no whitespace errors.
- Supabase Postgres production migrations are applied through `20260612093414_harden_supabase_policy_overlap`.
- Worker config sets `DATABASE_PRIMARY = "supabase_postgres"`.
- Cloudflare remains the media layer for Images/R2/Stream.
- Unauthenticated `/api/posts/feed` and `/api/admin/me` return `401`, as expected.
- `admin-web` production build passes.
- Production Supabase RLS policies are applied for app users, posts, likes/saves, comments, follows, blocks, messages, reports, media assets, push tokens, and admin/moderation tables.
- Supabase security advisor no longer reports missing RLS policies or disabled RLS on public app tables. Remaining warnings: `citext` extension in `public`, and Auth leaked-password protection disabled in the dashboard.
- Supabase policy overlap cleanup removed older broad legacy policies for app users, active posts, visible comments, legacy interactions, and legacy follows.
- Worker engagement logic now treats Supabase `app_post_interactions` as canonical for like/save state and counts; D1 engagement rows are best-effort legacy cache only.
- `backend-cf` TypeScript check passes after the Supabase engagement/RLS changes.
- `npm.cmd run test:moderation` passes after the Supabase engagement/RLS changes.
- No Supabase service-role JWT is present in `ios_native/MIRA` or `admin-web`; service-role usage is restricted to Worker/GitHub secret wiring.
- Follow-up hardening on 2026-06-12 added Supabase-auth/app-user alias cleanup for like/save reads, deletes, inserts, and actor counts so one person cannot inflate engagement through legacy id drift.
- Follow-up hardening on 2026-06-12 made Cloudflare Stream signed playback explicit with `CLOUDFLARE_STREAM_REQUIRE_SIGNED_URLS=false` by default, preventing new videos from being uploaded into an unplayable signed-only state before a signed playback resolver exists.

## Blockers

1. Production reset has not been executed.

   Reset tooling exists under `scripts/production-reset`, but it must be run only after backup and final confirmation.

2. Full iOS device QA cannot be completed on this Windows machine.

   TestFlight succeeded through GitHub Actions, but App Store readiness still requires real-device validation for login, upload, feed, Discover, chat, stories, report/block, delete account, and legal links.

3. Production still contains test data.

   Supabase dry-run counts:

   - `auth.users`: 14
   - `app_users`: 6
   - `app_posts`: 26
   - `app_post_interactions`: 28
   - `post_comments`: 1
   - `app_follows`: 1

   Legacy D1 dry-run counts:

   - `users`: 16
   - `posts`: 108
   - `likes`: 142
   - `saved_posts`: 40
   - `comments`: 36
   - `messages`: 46
   - `statuses`: 20
   - `media_assets`: 73

   D1 duplicate like check returned zero duplicate `(user_id, post_id)` pairs.
   Supabase duplicate `app_post_interactions` check returned zero duplicate `(legacy_post_id, app_user_id, kind)` rows.

4. Legacy D1 database code is still present in the Worker.

   Captro's target architecture is Supabase for app data and Cloudflare for media/security only. The codebase still contains many `c.env.DB`/`D1Database` references, so the D1 binding and D1 migration workflow must stay until each route group is cut over and verified.

   Current examples still on D1 include older auth/session helpers, report/block legacy routes, admin legacy routes, media moderation tables, legacy chat/messages, creator/application routes, and production reset D1 cleanup. These must be moved to Supabase before D1 can be removed from `backend-cf/wrangler.toml` and GitHub deploy.

   Current code search still shows over 1,000 D1/`c.env.DB` references in `backend-cf/src/index.ts`; treat D1 as active legacy infrastructure until the route groups are fully cut over.

5. Protected reset workflow is staged on the working branch.

   Added `.github/workflows/production-data-reset.yml`. GitHub will allow manual dispatch after this workflow file is present on the default branch. It supports:

   - dry-run by default
   - exact `CONFIRM_PRODUCTION_RESET` gate for execute mode
   - backup confirmation gate for execute mode
   - Cloudflare Images/Stream cleanup before database row deletion
   - legacy D1 media export so old image assets are included
   - optional legacy D1 row reset after Supabase reset

## Database Reset Scope

The protected Supabase reset script targets user/test/generated data only:

- `app_users`
- `app_posts`
- `post_comments`
- `app_post_interactions`
- `app_follows`
- `app_documents`
- `app_blocks`
- `app_notifications`
- `app_reports`
- `app_messages`
- `app_group_chats`
- `app_group_chat_members`
- `app_group_messages`
- `app_post_places`
- `app_media_assets`
- `app_moderation_results`
- `app_moderation_actions`
- `app_audit_logs`
- `app_push_tokens`
- `app_account_identities`
- matching `auth.users`, except keep-listed accounts

It does not drop schemas, tables, migrations, buckets, Workers, queues, KV, or configuration.

## Storage Reset Scope

The Cloudflare cleanup script reads `app_media_assets` and can delete:

- Cloudflare Images assets
- Cloudflare Stream videos
- legacy D1 `media_assets` rows exported from Wrangler JSON

It dry-runs by default and requires:

- `EXECUTE_DELETE=true`
- `CONFIRM_PRODUCTION_RESET=CONFIRM_PRODUCTION_RESET`

R2 objects need separate cleanup if rows use `storage_provider = r2`.

## Required Next Steps

1. Finish cutting remaining Worker route groups from D1 to Supabase Postgres.
2. Remove D1 app-data migrations and D1 app-data deploy steps after the route cutover is verified.
3. Back up Supabase Postgres.
4. Run Supabase reset dry-run and review row counts.
5. Run Cloudflare media cleanup dry-run and review asset list.
6. Execute reset only after confirming preserved admin/reviewer accounts.
7. Run legacy D1 reset if production can still serve D1 rows.
8. Upload a fresh TestFlight build after any app-code changes.
9. Smoke test the App Store review checklist on a real iPhone.

## App Store Review Checklist

- Sign up, login, username onboarding.
- Google and Apple login show Captro branding.
- Privacy Policy, Terms, Community Guidelines, Safety & Reporting reachable.
- Account deletion reachable and not a dead end.
- Report and block work for posts/profiles/messages.
- Photo post and multi-photo post creation work.
- Stories upload/playback works.
- Like/save/comment states persist after refresh/relaunch and one user cannot like the same post more than once.
- Feed and Discover only show approved, non-deleted content.
- Deleted/removed/admin-hidden posts disappear from Feed, Discover, Profile, and Bookmarks.
- Chat messages keep correct order and video messages play.
- No test/demo content remains after reset.
