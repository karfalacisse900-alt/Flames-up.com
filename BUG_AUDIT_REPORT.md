# Captro Bug Bash Audit Report

Date: 2026-05-27
Branch: `codex/full-bug-bash-audit`
Scope: Native iOS app, Cloudflare Worker API, and admin web app.

## Summary

This pass focused on production-risk bugs across feed interactions, media loading, report/block flows, chat reliability, backend authorization, and admin moderation. Critical/high issues were fixed first. Local Windows validation cannot build the Swift app, so iOS build validation must run through GitHub Actions/TestFlight.

## Fixed Bugs

### 1. Removed reported messages still appeared in normal chat

- Affected area: Chat, reports, moderation, backend API
- Severity: High
- Steps to reproduce:
  1. Admin removes a reported message from the moderation dashboard.
  2. A normal user opens the same conversation.
  3. The chat API returns the original message row.
- Expected behavior: Removed messages should show a neutral "Message removed" placeholder with no private text/media exposed.
- Actual behavior: The normal chat payload could still include the original `content`, `media_url`, `removed_by`, or `removed_reason`.
- Root cause: `messagePayload` signed and returned the row directly without redacting moderation-removed rows.
- Fix made:
  - Added removed-message redaction in `backend-cf/src/index.ts`.
  - Removed moderation internals from normal message payloads.
  - Updated direct and group conversation previews to show "Message removed" instead of original content.
  - Excluded removed messages from direct unread counts.
- Test result:
  - `backend-cf: npx.cmd tsc --noEmit` passed.
  - Covered by static route audit for `/messages/:userId`, `/conversations`, and group chat message responses.

### 2. Voice/media/text message retries could create duplicates

- Affected area: Chat, voice messages, media messages, backend API, iOS client
- Severity: High
- Steps to reproduce:
  1. Send a voice/media message on a slow or flaky network.
  2. The client retries or the user taps send again after a timeout.
  3. Backend creates a second row because media/voice messages had no idempotency key.
- Expected behavior: The same send request should return the already-created message instead of creating a duplicate.
- Actual behavior: Direct messages only had a weak text-only duplicate check. Media/voice and group messages could duplicate.
- Root cause: `SendMessageBody` and `GroupMessageBody` did not include `client_request_id`, and the Worker accepted but did not enforce message idempotency.
- Fix made:
  - Added `client_request_id` columns and unique indexes for direct and group messages.
  - Added direct/group message idempotency lookups before insert.
  - Added unique-conflict recovery that returns the existing message.
  - Added `clientRequestId` to the Swift direct/group message request bodies.
  - Added iOS append-or-replace logic so replayed responses do not duplicate bubbles.
- Test result:
  - `backend-cf: npx.cmd tsc --noEmit` passed.
  - Swift build must be verified by GitHub Actions/TestFlight because Swift/Xcode is not installed on this Windows machine.

### 3. Report sheet could fail to open from menus

- Affected area: Feed, Discover, comments, profile, chat/message report flow
- Severity: High
- Steps to reproduce:
  1. Long-press or open a post/comment/message/profile menu.
  2. Tap Report.
  3. On some iOS presentations, the report bottom sheet can fail to appear because the system menu is still dismissing.
- Expected behavior: Report always opens a smooth bottom sheet after the menu closes.
- Actual behavior: A menu-originated report action could be dropped, making the button feel dead.
- Root cause: SwiftUI can ignore a new sheet/overlay presentation started during `contextMenu`, `Menu`, or `confirmationDialog` dismissal.
- Fix made:
  - Added shared `MIRARunAfterMenuDismiss`.
  - Deferred report presentation from feed post menus, Discover post long-press menus, profile menus, comment menus, and message menus.
- Test result:
  - Static flow audit confirms all target report entry points now defer presentation.
  - Swift build must be verified by GitHub Actions/TestFlight.

### 4. Group chat tables were not self-healing in the Worker

- Affected area: Chat, backend API, production deployment safety
- Severity: Medium
- Steps to reproduce:
  1. Deploy a Worker to an environment where the group chat migration was not applied.
  2. Open group conversations or send group messages.
  3. API fails on missing `group_chats`, `group_chat_members`, or `group_messages`.
- Expected behavior: Existing migration should be applied, and the Worker should safely tolerate schema drift for production bootstrap.
- Actual behavior: Direct messages had an ensure function, but group chat routes assumed the group schema already existed.
- Root cause: Group chat schema was only present in migration files, not in the Worker runtime schema guard.
- Fix made:
  - Added `ensureGroupChatSchema`.
  - Ensured group routes create/update required group chat tables, moderation columns, idempotency column, and indexes.
- Test result:
  - `backend-cf: npx.cmd tsc --noEmit` passed.

## Verified Areas

### Home Feed interactions

- Affected area: Home Feed
- Severity: Medium if regressed
- Steps checked:
  - Avatar and username navigation use `NavigationLink`.
  - Post menu is a real `Button` with 44x44 target.
  - Like/comment/save are real buttons.
  - Media views use `.allowsHitTesting(false)` so image/video layers do not block controls.
  - Debug-only tap logging exists for core feed actions.
- Expected behavior: Every visible post should have working controls and no media overlay should block taps.
- Actual behavior: Static audit shows the recent interaction fixes are present.
- Root cause: Previous issue was likely invisible media/overlay hit testing and menu presentation timing.
- Fix made or recommended fix: No additional feed tap-target code change was needed in this pass beyond the report-menu defer fix.
- Test result:
  - Local static audit passed.
  - Needs GitHub Actions/TestFlight device validation for runtime tap testing.

### Media loading and 3:4 feed sizing

- Affected area: Feed, Discover, media pipeline
- Severity: Medium if regressed
- Steps checked:
  - Home feed reserves media height via `MIRAMediaSizing.mainFeedHeight`.
  - Feed target constants are 1080x1440.
  - `RemoteMediaView` supports placeholder URL, non-white media placeholder color, image cache, and video posters.
  - Feed prefetches nearby thumbnails/posters and next feed images.
  - Backend feed payloads expose optimized `feed_media_urls`, `thumbnail_urls`, and `poster_urls`.
- Expected behavior: No white blink, no full-size original in feed, no layout jump.
- Actual behavior: Static audit shows the placeholder/caching/sizing path is wired.
- Root cause: Prior white blink came from blank media background or missing thumbnail/poster handoff.
- Fix made or recommended fix: No new media patch in this pass; keep validating on TestFlight with slow network.
- Test result:
  - Static audit passed.

### Auth and username onboarding

- Affected area: Auth, Apple/Google signup
- Severity: High if regressed
- Steps checked:
  - Backend detects generated/pending usernames.
  - `/auth/me` exposes `username_required` and `onboarding_required`.
  - iOS root routes users to `ChooseUsernameNativeView` before main app when needed.
- Expected behavior: Users should not enter the main app with random public usernames.
- Actual behavior: Static audit shows the onboarding gate is present.
- Root cause: Previous risk was generated usernames becoming public before onboarding.
- Fix made or recommended fix: No new change in this pass.
- Test result:
  - Static audit passed.

### Report/block/backend integration

- Affected area: Reports, blocks, moderation, admin web
- Severity: High if regressed
- Steps checked:
  - `POST /api/reports` requires auth, validates target existence, blocks duplicate spam reports, calculates priority, and can block the target user.
  - Blocking endpoints exist and prevent self-block.
  - Direct message peer validation rejects blocked-user conversations.
  - Admin report endpoints require backend roles.
  - Admin actions create audit/moderation records.
- Expected behavior: Reports create backend records and appear in admin queues; blocked users cannot message.
- Actual behavior: Static audit shows real backend/report/admin wiring.
- Root cause: Previous risk was visual-only report buttons.
- Fix made or recommended fix: Fixed menu presentation reliability; backend report creation was already present.
- Test result:
  - `backend-cf: npx.cmd tsc --noEmit` passed.

### Admin web media previews and build

- Affected area: Admin web
- Severity: Medium if regressed
- Steps checked:
  - `MediaPreview` normalizes image/video fields from post/report payloads.
  - Tables use thumbnails/posters, detail view supports video controls.
  - Admin pages use protected API calls, not mock data in production.
- Expected behavior: Admin posts/reports show image/video previews before moderation actions.
- Actual behavior: Static audit and production build path are valid.
- Root cause: Previous risk was field-name mismatch between Worker and admin web.
- Fix made or recommended fix: No new admin UI patch in this pass.
- Test result:
  - `admin-web: npm.cmd --prefix admin-web run build` passed.

## Recommended Follow-Up

### Legacy duplicate Worker routes should be removed in a controlled cleanup

- Affected area: Backend API maintainability
- Severity: Medium
- Steps to reproduce:
  1. Search `backend-cf/src/index.ts` for duplicate `/admin/reports` and `/reports` route definitions.
  2. Multiple legacy route blocks still exist after the modern protected admin routes.
- Expected behavior: One canonical implementation per production route.
- Actual behavior: Hono will generally match the first compatible route, but duplicate definitions increase maintenance risk and can confuse future fixes.
- Root cause: Older route blocks were kept while newer production routes were added.
- Fix made or recommended fix: Recommended separate cleanup PR after confirming route order and production traffic. Not changed here to avoid unrelated production API risk.
- Test result:
  - Static audit finding only.

### Runtime iOS bug bash still needs device/TestFlight validation

- Affected area: Native iOS app
- Severity: Medium
- Steps to reproduce:
  1. Attempt local Swift/Xcode build on this Windows machine.
  2. Swift/Xcode toolchain is unavailable.
- Expected behavior: Native iOS runtime tests should run on macOS/Xcode or GitHub Actions.
- Actual behavior: Local Windows environment cannot build/run the iOS app.
- Root cause: Platform limitation, not an app code bug.
- Fix made or recommended fix: Run GitHub Actions/TestFlight validation for this branch and test the listed flows on device.
- Test result:
  - Pending GitHub Actions/TestFlight validation.

## Validation Commands

- Passed: `backend-cf: npx.cmd tsc --noEmit`
- Passed: `admin-web: npm.cmd --prefix admin-web run build`
- Passed with Windows line-ending warnings only: `git diff --check`
- Not run locally: Swift/Xcode build, because this machine is Windows.

