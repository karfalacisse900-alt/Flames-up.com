# Captro Production Release Audit

Date: 2026-06-11

## Status

Captro is not ready to mark as production-ready until the backend production deploy blocker is fixed and the reset is run safely.

## Verified

- Latest TestFlight workflow succeeded for commit `b59209e21e96e890ebb8e9e2a86af1f4ac98cb66`.
- `backend-cf` TypeScript check passes with `npx.cmd tsc --noEmit`.
- Pre-publish moderation tests pass with `npm.cmd run test:moderation`.
- `git diff --check` has no whitespace errors.
- Supabase Postgres migrations exist for core app data and operational tables.
- Worker config sets `DATABASE_PRIMARY = "supabase_postgres"`.
- Cloudflare remains the media layer for Images/R2/Stream.

## Blockers

1. Backend production deploy failed.

   GitHub Actions run:
   `https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/27224181931`

   Missing repository secrets:

   - `SUPABASE_ACCESS_TOKEN`
   - `SUPABASE_PROJECT_REF`
   - `SUPABASE_SERVICE_ROLE_KEY`

   Until this is fixed, production may still serve older Worker behavior. That can explain persistent like/save bugs, stale feed data, and media processing behavior after a TestFlight update.

2. Production reset has not been executed.

   Reset tooling now exists under `scripts/production-reset`, but it must be run only after backup and confirmation.

3. Full iOS device QA cannot be completed on this Windows machine.

   TestFlight succeeded through GitHub Actions, but App Store readiness still requires real-device validation for login, upload, feed, Discover, chat, stories, report/block, delete account, and legal links.

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

It dry-runs by default and requires:

- `EXECUTE_DELETE=true`
- `CONFIRM_PRODUCTION_RESET=CONFIRM_PRODUCTION_RESET`

R2 objects need separate cleanup if rows use `storage_provider = r2`.

## Required Next Steps

1. Add missing Supabase GitHub repository secrets.
2. Re-run the backend deploy workflow.
3. Confirm `/api/database/status` reports Supabase Postgres as healthy.
4. Back up Supabase Postgres.
5. Run Supabase reset dry-run and review row counts.
6. Run Cloudflare media cleanup dry-run and review asset list.
7. Execute reset only after confirming preserved admin/reviewer accounts.
8. Run legacy D1 reset if production can still serve D1 rows.
9. Upload a fresh TestFlight build.
10. Smoke test the App Store review checklist on a real iPhone.

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
