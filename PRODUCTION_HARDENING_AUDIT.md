# Captro Production Hardening Audit

Date: 2026-06-12

## Executive Status

Captro is closer to production readiness, but it should not be considered fully production-clean until the remaining D1-backed app-data routes are migrated to Supabase Postgres, the protected production reset is executed after backup, and a real-device TestFlight smoke test passes.

This pass fixed three high-risk backend/iOS issues:

- Like/save state now canonicalizes legacy app user ids and Supabase auth ids before reading, counting, deleting, or inserting engagement rows.
- Cloudflare Stream direct uploads no longer force signed/private playback unless `CLOUDFLARE_STREAM_REQUIRE_SIGNED_URLS=true` is explicitly configured.
- iOS Cloudflare Stream playback and prewarm now resolve Stream metadata through an authenticated API request, and `/api/stream/video/:uid` now requires a valid app session.
- Like/save state now also reads, deletes, and counts both legacy text interaction columns and native Supabase UUID interaction columns, preventing drift between `legacy_post_id/app_user_id` and `post_id/user_id`.

## Bugs Fixed In This Pass

### Engagement Persistence

Affected areas:

- Home Feed
- Discover details
- Profile post details
- Bookmarks

Root cause:

The Worker could see the same human user through multiple ids during the D1-to-Supabase transition: old D1 `users.id`, Supabase `auth.users.id`, and `app_users.supabase_user_id`. A like/save could be inserted under one id and later queried under another, making the heart/bookmark state appear off after refresh while the count stayed inflated.

Fix:

- `app_post_interactions` counts now dedupe actors by canonical Supabase auth id when possible.
- Like/save delete paths now remove both app-id and auth-id aliases before inserting the requested state.
- Viewer-state lookup now checks app ids, auth ids, and app ids mapped back from auth ids.
- Native Supabase interaction rows using `post_id/user_id/kind` are now included in state checks, actor counts, and bookmark checks alongside legacy `legacy_post_id/app_user_id/kind` rows.
- D1 engagement rows remain best-effort legacy cache only.

Validation:

- `backend-cf`: `npx.cmd tsc --noEmit` passes.

### Cloudflare Stream Playback

Affected areas:

- Story videos
- Chat video messages
- Any Cloudflare Stream direct-upload playback path

Root cause:

Some direct upload routes created Cloudflare Stream videos with `requireSignedURLs: true`, but the iOS resolver asks `/api/stream/video/:uid` for a normal HLS playback URL. That combination can leave videos stuck as "processing" or unplayable even after Stream finishes encoding.

Fix:

- Added `CLOUDFLARE_STREAM_REQUIRE_SIGNED_URLS`.
- Defaulted it to `false` in development and production Worker vars.
- Video upload intent and direct video upload now use that explicit flag.
- The iOS video player and prewarm manager now share `MIRAStreamPlaybackResolver`, which attaches the Keychain bearer token before calling `/api/stream/video/:uid`.
- `/api/stream/video/:uid` now uses `authMiddleware`.

Validation:

- `backend-cf`: `npx.cmd tsc --noEmit` passes.
- `backend-cf`: `npm.cmd run test:moderation` passes.
- `admin-web`: `npm.cmd --prefix admin-web run build` passes.

Remaining risk:

- Existing videos already uploaded with signed playback may still need re-upload, admin repair, or a signed playback-token implementation.
- `/api/stream/video/:uid` now authenticates the caller, but a future hardening pass should add object-level authorization so only story/chat/post viewers allowed to see that media can resolve the Stream UID.

## Production Readiness Matrix

| Area | Status | Notes |
| --- | --- | --- |
| Supabase Auth | Partial | Supabase Auth is integrated, but the Worker still supports legacy JWT/D1 auth paths. |
| Supabase main database | Partial | Supabase tables/RLS exist, but the Worker still has many D1 route dependencies. |
| Cloudflare media | Partial | Images/Stream are used, Stream signed playback is now opt-in, and R2 backup still exists. |
| RLS | Implemented | Production RLS hardening migrations were applied earlier; Supabase advisor reported no missing RLS on public app tables. |
| Likes/saves | Patched | Alias dedupe and canonical counts added in this pass. Needs real-device refresh/relaunch test. |
| Comments | Needs QA | D1 comment counts are still used in the canonical engagement response. |
| Feed performance | Partial | iOS has URLCache/prewarm infrastructure; still needs Instruments/device proof under slow network. |
| Discover filters | Needs QA | Backend multi-signal category logic exists, but category accuracy needs real production sample review. |
| Chat video | Patched for new Stream uploads | iOS resolver now sends auth. Existing signed videos may remain broken until repaired/reuploaded. |
| Stories video | Patched for new Stream uploads | iOS resolver now sends auth. First-play instant behavior still requires real-device profiling. |
| Moderation | Partial | Pre-publish moderation exists. False-positive review rates need monitoring and admin override workflow. |
| Account deletion | Partial | In-app flow and backend routes exist; provider revocation and full Supabase-only cleanup must be verified. |
| Admin moderation | Partial | Admin app exists; D1-backed moderation storage remains. |
| Crash reporting | Needs implementation/verification | MetricKit/OSLog exist in codebase, but external crash aggregation should be confirmed. |
| Production reset | Not executed | Reset must not run until backup and explicit confirmation. |
| TestFlight/App Store review | Needs fresh run | Local Windows cannot run Xcode; use GitHub Actions and real-device TestFlight. |

## Required Launch Tests

Run these on the latest TestFlight build before App Store submission:

- Sign up, log in, log out, restore session, username onboarding.
- Google/Apple login branding says Captro.
- Create one photo post and one multi-photo carousel.
- Reopen app after liking/saving each post; heart/bookmark state and counts must match.
- Open the same post from Feed, Discover, Profile, and Bookmarks; counts must stay identical.
- Comment, close comments, reopen app; comment count must stay correct.
- Upload a story video, open it immediately, swipe next/back, background/foreground app.
- Send chat text, image, and video; verify ordering and video playback.
- Block a user and verify posts/messages/comments disappear where required.
- Report post/profile/message/story and verify admin queue receives it.
- Delete a post and verify it disappears from Feed, Discover, Profile, and Bookmarks.
- Delete account from Settings and verify the account becomes hidden immediately.
- Slow Wi-Fi/3G test for feed, Discover, chat media, upload failure/retry.
- Dark mode, Settings, legal links, privacy policy, terms, guidelines, safety/reporting.

## Security Notes

- Do not place Supabase service-role key in iOS or admin frontend.
- Keep Supabase service-role key only in Worker/GitHub secret contexts.
- Keep `DATABASE_PRIMARY=supabase_postgres`, but do not remove D1 binding until D1 route references are migrated.
- Preserve rate limits for upload, comments, messages, reports, login, and moderation actions.
- Keep Cloudflare KV only for temporary cache/rate-limit data.
- Before enabling signed Stream playback, implement signed playback URL/token generation and object-level media authorization.

## Production Reset Requirements

Do not delete production data from a local shell.

Safe order:

1. Backup Supabase Postgres.
2. Export/backup media metadata.
3. Run Supabase reset dry-run.
4. Run Cloudflare Images/Stream cleanup dry-run.
5. Review preserved admin/reviewer accounts.
6. Execute only with `CONFIRM_PRODUCTION_RESET=true` or the protected workflow confirmation string required by the reset script.
7. Run real-device smoke tests after reset.

## Remaining Blockers

1. D1 is still heavily used in `backend-cf/src/index.ts`; this blocks the final Supabase-only architecture.
2. Existing Stream videos created with signed playback may still be unplayable without repair.
3. Real-device iOS testing is required for memory leaks, freezes, media prewarm, camera quality, and slow network behavior.
4. Production reset has not been executed.
5. Full App Store readiness cannot be claimed until latest GitHub Actions/TestFlight build is green and smoke tested.
