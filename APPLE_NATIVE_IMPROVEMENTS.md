# Captro Apple-Native Improvements

Last updated: 2026-05-28

Captro is a native iOS social app backed by the Cloudflare Worker API at `https://api.flames-up.com/api`. The app uses Swift, SwiftUI, UIKit, AVFoundation, PhotosUI, Apple Vision/Core ML, Keychain, APNs, and production Cloudflare services. Feed media defaults to a stable 3:4 layout using optimized 1080 x 1440 feed assets.

This document defines the phased Apple-native production improvements for performance, camera quality, upload experience, Discover categorization, security, push notifications, cache behavior, and diagnostics.

## Current App Status

- Native iOS app lives in `ios_native/MIRA`.
- Production API is `https://api.flames-up.com/api`.
- Feed and Discover use optimized media URLs, thumbnails, posters, and cached/skeleton states.
- Apple Vision/Core ML first-pass category classification exists in `MIRAAutoCategoryService`.
- URLSession request deduplication and cache configuration exist in `MIRAAPIClient`.
- JSON and image caches exist in `MIRAPerformance`.
- Auth token storage uses Keychain through `MIRAKeychainSessionProvider`.
- Push registration is handled by `MIRAPushNotificationService` and `MIRAAppDelegate`.
- AVFoundation camera and PhotosUI picker are implemented in the native composer/camera flows.
- New production diagnostics and background maintenance hooks are now wired in safe phases.

## Phase 1: MetricKit and OSLog Signposts

### What It Improves

- Measures launch, hangs, memory, CPU, battery, and diagnostics from real devices.
- Adds consistent signposts around startup, feed, Discover, profile, chat, media, comments, tab switching, and uploads.
- Gives TestFlight and production diagnostics without logging sensitive data.

### iOS Changes

- `MIRAApplePerformanceLogger` wraps `Logger` and `os_signpost`.
- `MIRAMetricKitSubscriber` subscribes to MetricKit when available.
- `MIRAAppleRuntimeDiagnostics.start()` runs during app launch.
- Existing `MIRAPerformanceTimeline` marks are forwarded to OSLog.
- Upload flows emit:
  - `post_upload_start`
  - `post_upload_complete`
  - `post_upload_failed`
- Media cache emits:
  - `media_cache_hit`
  - `media_cache_miss`

### Backend Changes

- No backend change is required for local OSLog/MetricKit collection.
- Future: add a privacy-safe diagnostics upload endpoint if Captro wants remote aggregation beyond Xcode Organizer/MetricKit.

### Risks

- Excessive logging can add noise.
- Sensitive values must never be logged.

### Rollout

1. Ship signposts in TestFlight.
2. Review Xcode Organizer and device logs.
3. Add only aggregated remote metrics later if needed.

### Acceptance Criteria

- Launch, startup, media, upload, comments, and tab switching events are visible in OSLog/Instruments.
- No tokens, passwords, private messages, secrets, full captions, or full API responses are logged.

## Phase 2: URLSession and URLCache

### What It Improves

- Reduces duplicate API calls.
- Keeps safe GET responses and media responses reusable.
- Makes tab switching and cold starts feel faster.

### iOS Changes

- `MIRAAPIClient.productionSession` uses a configured `URLCache`.
- GET requests are deduplicated by method, URL, and token fingerprint.
- Request timeouts and connectivity waiting are configured.
- Feed, Discover, Profile, and Chat use local cache-first loaders where available.
- Background refresh can update cached data without blocking UI.

### Backend Changes

- Keep response payloads small.
- Use cache headers where safe.
- Keep media immutable and cacheable.
- Continue returning optimized feed media, thumbnails, posters, dimensions, and aspect ratios.

### Risks

- Private data must not be cached in the wrong context.
- Cache keys must include user context when viewer state changes the response.

### Rollout

1. Use cache-first for non-sensitive screen state.
2. Refresh in the background.
3. Watch duplicate request counts and route latency.

### Acceptance Criteria

- Switching tabs does not reload everything.
- Cached content appears quickly.
- Network refresh happens in the background.
- No blank white screens appear while waiting for network.

## Phase 3: AVFoundation Camera Improvements

### What It Improves

- Better photo/video capture quality.
- Stable preview and capture.
- Native tap-to-focus, exposure, white balance, torch/flash, camera flip, and stabilization.

### iOS Changes

- Use AVFoundation capture instead of preview screenshots.
- Capture high-quality originals first.
- Show a 3:4 guide for the default feed composition.
- Generate optimized 1080 x 1440 feed output after capture/upload processing.
- Keep camera work off the main thread where possible.

### Backend Changes

- Store original media safely.
- Generate optimized feed images and thumbnails.
- Generate video posters and playback metadata.

### Risks

- Camera capability varies by device.
- Video stabilization and high-res capture must gracefully fallback.

### Rollout

1. Keep current camera UI stable.
2. Improve capture settings per device capability.
3. Verify on TestFlight devices.

### Acceptance Criteria

- Camera opens quickly.
- Photos are sharp.
- Videos are stable.
- Final feed media uses the 3:4 target without stretching.

## Phase 4: PhotosUI Picker

### What It Improves

- Privacy-friendly gallery access.
- Reliable large photo/video selection.
- Avoids requesting full library permission when PHPicker is enough.

### iOS Changes

- Use PhotosUI/PHPicker for image and video selection.
- Load assets asynchronously.
- Show preview after selection.
- Preserve smooth cancellation and error states.

### Backend Changes

- Validate uploaded media type, size, and duration.
- Process selected assets into optimized feed/poster/thumbnail versions.

### Risks

- Large videos can still take time to transfer from Photos.
- Some formats need server-side transcode or rejection.

### Rollout

1. Keep PhotosUI as default gallery path.
2. Add clearer upload progress and retry states.
3. Monitor upload failures.

### Acceptance Criteria

- Users can select photos/videos reliably.
- Large media does not freeze the app.
- Cancelled picker leaves the composer stable.

## Phase 5: Vision and Core ML Auto Category

### What It Improves

- Users do not have to manually choose Discover categories.
- Discover filters query saved categories instead of running AI on every open.

### iOS Changes

- `MIRAAutoCategoryService` analyzes resized images and selected video frames.
- It sends Apple Vision labels, category guess, and confidence with post creation.
- It does not block the main thread.

### Backend Changes

- Accept Apple Vision labels and confidence.
- Run backend AI only when useful.
- Save:
  - `primary_category`
  - `tags_json`
  - `category_confidence`
  - `category_source`
  - `category_status`
  - `category_signals_json`
- Discover queries saved `primary_category`.
- Admin category changes create audit logs.

### Risks

- Category guesses can be wrong.
- Low confidence should fall back to Lifestyle and be correctable by admins.

### Rollout

1. Use Apple Vision as first-pass.
2. Use backend AI for low-confidence or unclear posts.
3. Allow admin correction.

### Acceptance Criteria

- Food, outfit, outdoor, event, nightlife, travel, art, fitness, pet, car, beauty, photography, and lifestyle posts are saved with Discover categories.
- Low-confidence posts fallback safely to Lifestyle.
- No backend AI keys are exposed in iOS.

## Phase 6: Keychain Token Storage

### What It Improves

- Auth/session tokens are stored securely at rest.
- Logout can clear sensitive local data.

### iOS Changes

- `MIRAKeychainSessionProvider` stores tokens under `com.captro.auth`.
- Legacy `com.mira.auth` tokens are migrated once and removed.
- Logout clears both current and legacy token keys.
- Tokens are not printed to logs.

### Backend Changes

- Continue using expiring, refreshable sessions.
- Handle expired tokens with safe errors.

### Risks

- Token migration must avoid logging or losing valid sessions.

### Rollout

1. Ship migration in TestFlight.
2. Verify existing users stay signed in.
3. Verify logout clears sensitive token state.

### Acceptance Criteria

- Tokens are in Keychain, not UserDefaults.
- Logout clears tokens.
- Missing/expired sessions route cleanly.

## Phase 7: App Attest and DeviceCheck

### What It Improves

- Helps the backend distinguish legitimate Captro app traffic from scripted abuse.
- Adds trust signals to sensitive write/upload endpoints.

### iOS Changes

- `MIRADeviceTrustService` adds monitor-mode headers for sensitive requests.
- DeviceCheck token is attached when available.
- App Attest support is signaled without enforcing production lockout.

### Backend Changes

- Worker CORS allows Captro device trust headers.
- Future backend verification should validate App Attest assertions and DeviceCheck tokens server-side.
- Start in monitor/report-only mode before strict enforcement.

### Risks

- Strict enforcement too early can lock out real users.
- App Attest requires correct Apple capability/provisioning setup.

### Rollout

1. Monitor-only headers in iOS.
2. Add backend verification endpoint/path.
3. Review failure rates.
4. Enforce only on high-risk endpoints after confidence.

### Acceptance Criteria

- Sensitive endpoints can receive trust headers.
- Unsupported devices still work.
- No Apple/team secrets are exposed in iOS.

## Phase 8: BackgroundTasks Cache Refresh

### What It Improves

- Refreshes cached Feed, Discover, and Chat previews when the system allows.
- Cleans old JSON/image cache files.
- Improves perceived speed without blocking startup.

### iOS Changes

- `MIRABackgroundTaskCoordinator` registers:
  - `com.karfala90.frontend.background-refresh`
  - `com.karfala90.frontend.cache-cleanup`
- Background refresh warms:
  - Feed first page
  - Discover All first page
  - Chat conversation previews
- Cache cleanup trims stale JSON and image cache data.

### Backend Changes

- No new route is required.
- Existing lightweight endpoints must remain paginated and small.

### Risks

- iOS decides when tasks run.
- Background work must remain short and battery-safe.

### Rollout

1. Register tasks.
2. Schedule refresh/cleanup on background.
3. Verify no startup dependency on background execution.

### Acceptance Criteria

- App still works if background task never runs.
- Cache cleanup prevents unbounded growth.
- Cached data is fresher when iOS allows background execution.

## Phase 9: UserNotifications and APNs

### What It Improves

- Delivers comments, messages, follows, mentions, moderation alerts, and other user notifications.
- Routes taps to the correct app destination.

### iOS Changes

- Push registration uses `MIRAPushNotificationService`.
- Device token is sent only for the signed-in user.
- Notification open events are posted through `.miraNotificationOpened`.
- Notification interactions are logged without sensitive payloads.

### Backend Changes

- Store device tokens server-side.
- Remove invalid/old tokens.
- Respect privacy preview settings.
- Blocked users should not trigger unwanted notifications.
- Backend controls notification creation.

### Risks

- Notification payloads can leak private content if too detailed.
- Token cleanup must be reliable.

### Rollout

1. Keep registration and token sync stable.
2. Add per-type deep links.
3. Add privacy-safe preview controls.

### Acceptance Criteria

- Push registration works.
- Notification taps open the intended screen.
- No secrets or private data leak in notification payloads.

## Phase 10: Backend AI Integration

### Flow

1. iOS runs Apple Vision/Core ML first.
2. iOS sends labels, category guess, confidence, caption metadata, media type, and optional place/event metadata.
3. Backend AI verifies/refines when needed.
4. Backend saves final category fields.
5. Discover filters query saved categories.

### Rules

- Do not run AI every time Discover opens.
- Do not slow down feed loading.
- Do not put backend AI keys in iOS.
- Use backend AI only through secure Worker routes.

## Testing Plan

Test on GitHub Actions and TestFlight because local Swift builds are not available on this Windows machine.

Required test matrix:

- Cold launch
- Login/session restore
- Feed cache and first content
- Discover cache and category filters
- Profile cache
- Chat list cache
- Camera capture
- Gallery upload
- Post upload success/failure
- Apple Vision category detection
- Push registration
- Notification tap routing
- Logout/token clearing
- Slow network
- Offline mode
- Background/foreground transitions

Tools:

- Xcode Instruments
- Xcode Organizer
- MetricKit
- OSLog signposts
- TestFlight real-device testing
- GitHub Actions TestFlight workflow
- GitHub Actions Security Scans workflow

## Production Acceptance Criteria

- `APPLE_NATIVE_IMPROVEMENTS.md` exists.
- MetricKit and OSLog performance code exists.
- URLSession/URLCache strategy is implemented and documented.
- AVFoundation camera quality improvements are implemented/planned in safe phases.
- PhotosUI picker is used/planned.
- Vision/Core ML first-pass category detection is implemented.
- Keychain token storage is implemented with legacy migration.
- App Attest/DeviceCheck monitor-mode path exists with backend requirements documented.
- BackgroundTasks cache refresh/cleanup is implemented safely.
- UserNotifications/APNs flow is implemented/documented.
- No sensitive data is logged.
- iOS TestFlight workflow remains green.
- Security Scans workflow remains green.
- Worker deploy remains green.
- Production API remains working.
