# Captro Apple-Native Verification Report

Last updated: 2026-05-28

This report verifies actual Captro code, not only `APPLE_NATIVE_IMPROVEMENTS.md`. Status values mean:

- `implemented`: production code exists and is wired into the app/backend.
- `partially implemented`: useful code exists, but there are known gaps before it is complete production coverage.
- `documented only`: described in docs but not implemented.
- `not implemented`: no meaningful implementation found.

## 1. MetricKit + OSLog Signposts

Status: implemented

Files changed/verified:

- `ios_native/MIRA/Sources/MIRANative/Services/MIRAPerformance.swift`
- `ios_native/MIRA/AppTarget/MIRAAppDelegate.swift`
- `ios_native/MIRA/AppTarget/MIRAApp.swift`
- `ios_native/MIRA/Sources/MIRANative/Components/MIRAComponents.swift`
- `ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift`
- `ios_native/MIRA/Sources/MIRANative/Screens/MainFeedView.swift`

How it works:

- `MIRAApplePerformanceLogger` wraps `Logger` and `os_signpost`.
- `MIRAMetricKitSubscriber` subscribes to MetricKit when available.
- App launch starts runtime diagnostics in `MIRAAppDelegate`.
- Timeline marks now emit production-safe OSLog events.
- Uploads emit `post_upload_start`, `post_upload_complete`, and `post_upload_failed`.
- Media cache emits `media_cache_hit` and `media_cache_miss`.

How to test:

- Run the TestFlight build on a real device.
- Open Console.app or Instruments and filter the app subsystem/category `performance`.
- Exercise cold launch, feed load, media load, post upload, comments open, tab switch, notification open.
- Verify MetricKit payloads appear later in Xcode Organizer/MetricKit diagnostics.

Production risk:

- Low. Logging is sanitized for sensitive terms.

Remaining work:

- Optional: add a privacy-safe metrics upload endpoint if Captro wants remote aggregated metrics outside Apple/Xcode tooling.

## 2. URLSession + URLCache

Status: implemented

Files changed/verified:

- `ios_native/MIRA/Sources/MIRANative/Services/MIRAAPIClient.swift`
- `ios_native/MIRA/Sources/MIRANative/Services/MIRAPerformance.swift`
- `ios_native/MIRA/Sources/MIRANative/Components/MIRAComponents.swift`
- `ios_native/MIRA/Sources/MIRANative/Services/MIRABackgroundTasks.swift`

How it works:

- `MIRAAPIClient.productionSession` configures `URLSession` with `URLCache`, timeouts, waits-for-connectivity, and connection limits.
- GET requests are deduplicated by method, URL, and auth token fingerprint.
- Image loading uses memory cache, disk cache, URLCache policy, request cancellation through SwiftUI task lifecycle, and background decoding.
- JSON and image caches can now be trimmed by background maintenance.

How to test:

- Launch app, load Feed/Discover/Profile/Chat, switch tabs repeatedly.
- Watch API logs for duplicate GET calls.
- Confirm cached content appears before fresh refresh on repeat opens.
- Use Instruments Network and Time Profiler on a Mac runner/device.

Production risk:

- Low to medium. Private responses rely on token-aware dedupe and local cache keys. Do not add shared/public caching for authenticated payloads without review.

Remaining work:

- Add per-route performance dashboards and duplicate-call counters in production analytics.

## 3. AVFoundation Camera Improvements

Status: implemented

Files changed/verified:

- `ios_native/MIRA/Sources/MIRANative/Components/MIRACameraCaptureView.swift`
- `ios_native/MIRA/Sources/MIRANative/Services/MIRAMediaUploadService.swift`
- `ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift`

How it works:

- Camera uses `AVCaptureSession`, `AVCapturePhotoOutput`, and `AVCaptureMovieFileOutput`.
- Session now prefers 4K capture when supported, then 1080p, then high.
- Photo output enables high-resolution capture and quality prioritization.
- Video capture supports stabilization when the device format supports it.
- Tap-to-focus and tap-to-expose are implemented on the preview.
- The camera overlay now shows a visible 3:4 capture guide with thirds inside the frame.
- Captured photos use `AVCapturePhoto.fileDataRepresentation()`, not a low-quality preview screenshot.
- Feed post image uploads use a feed-post upload target that crops/resizes to 1080 x 1440 JPEG before upload.

How to test:

- Open post creation camera.
- Confirm the 3:4 guide appears over the live preview.
- Capture a photo, confirm review is sharp.
- Capture 15s and 60s video, confirm recording starts/stops and preview thumbnail appears.
- Tap different preview points and confirm the focus ring and exposure/focus behavior.
- Publish an image post and confirm payload dimensions are 1080 x 1440 / 3:4.

Production risk:

- Medium. 4K capture increases camera/media memory pressure on older devices. The code falls back when unsupported.
- Feed image upload now crops post images to 3:4 for feed-post uploads only; chat/profile/general uploads keep the general path.

Remaining work:

- Add device QA on older iPhones for 4K session fallback and memory pressure.
- If Captro needs archival originals, add a separate `originalMediaUrl`/backup flow before feed optimization.
- Video feed transcode/crop is still handled by Stream/backend delivery, not by local client-side 1080 x 1440 video encoding.

## 4. PhotosUI / PHPicker Gallery Upload

Status: partially implemented

Files changed/verified:

- `ios_native/MIRA/Sources/MIRANative/Components/MIRACameraCaptureView.swift`
- `ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift`
- `ios_native/MIRA/Sources/MIRANative/Screens/ConversationNativeView.swift`
- `ios_native/MIRA/Sources/MIRANative/Screens/ProfileChatVerificationStudio.swift`

How it works:

- Camera gallery uses `PHPickerViewController` with image/video filters.
- Post creation uses SwiftUI `PhotosPicker` with images and videos and max 10 items.
- Chat uses `PhotosPicker` for image/video attachments.
- Profile image update uses `PhotosPicker` for images.
- Selected media is previewed before posting.

How to test:

- Open post creation, select multiple photos/videos, preview, and publish.
- Open camera, tap gallery, select a photo and video.
- Open chat and send a selected photo/video.
- Update profile image from gallery.
- Test with large 4K/HEVC videos and large HEIC/JPEG photos.

Production risk:

- Medium. The SwiftUI `PhotosPicker` paths still load selected assets into `Data`, which can increase memory pressure for very large videos.

Remaining work / safe phased plan:

- Phase A: add size/duration checks before upload and show a clear "video too large" state.
- Phase B: move large video picker paths to temporary-file based loading where possible.
- Phase C: add visible per-item upload progress and retry UI.

## 5. Vision / Core ML Auto Discover Category

Status: implemented

Files changed/verified:

- `ios_native/MIRA/Sources/MIRANative/Services/MIRAAutoCategoryService.swift`
- `ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift`
- `ios_native/MIRA/Sources/MIRANative/Models/MIRAModels.swift`
- `backend-cf/src/index.ts`
- `ios_native/MIRA/Sources/MIRANative/Screens/DiscoverNativeView.swift`

How it works:

- iOS uses `VNClassifyImageRequest` on resized image data.
- Videos are sampled by poster/keyframes using `AVAssetImageGenerator`; the whole video is not analyzed.
- iOS sends Apple Vision labels, category guess, and confidence with post creation.
- Backend stores `primary_category`, `category_confidence`, `category_source`, `category_status`, `category_signals_json`, and `tags_json`.
- Backend can refine low-confidence/video posts with Workers AI when the `AI` binding is configured.
- Discover reads saved `primary_category`; it does not run AI when filters are tapped.

How to test:

- Create posts with food, outfits, outdoor, travel, art, fitness, pets, cars, and beauty content.
- Verify post creation payload includes Apple Vision labels/confidence.
- Query `/api/discover?category=food`, `/api/discover?category=outfits`, etc.
- In admin web, verify category metadata and correction actions.

Production risk:

- Medium. Vision labels are broad and can misclassify edge cases. Backend fallback prevents blocking posts.

Remaining work:

- Add real-device category QA dataset.
- Add admin review queue for repeated low-confidence posts.
- Track category correction rates by category.

## 6. Keychain Token Storage

Status: implemented

Files changed/verified:

- `ios_native/MIRA/Sources/MIRANative/Services/MIRAKeychainSessionProvider.swift`
- `ios_native/MIRA/Sources/MIRANative/Services/MIRAAuthSession.swift`
- `ios_native/MIRA/Sources/MIRANative/Services/MIRAAPIClient.swift`

How it works:

- Auth access tokens are stored in Keychain under `com.captro.auth`.
- Existing legacy `com.mira.auth` tokens are migrated once, then removed from the legacy service.
- Logout clears both current and legacy token storage.
- API auth reads the token through `MIRASessionProviding`.

How to test:

- Log in, kill the app, relaunch, verify session restores.
- Log out, relaunch, verify token is gone and app routes to login/onboarding.
- Inspect code paths to confirm no token storage in `UserDefaults`.

Production risk:

- Low. Migration preserves existing logged-in users.

Remaining work:

- Add automated UI/auth regression test on a Mac runner if the CI can run simulator UI tests later.

## 7. App Attest / DeviceCheck

Status: partially implemented

Files changed/verified:

- `ios_native/MIRA/Sources/MIRANative/Services/MIRADeviceTrustService.swift`
- `ios_native/MIRA/Sources/MIRANative/Services/MIRAAPIClient.swift`
- `backend-cf/src/index.ts`

How it works:

- Sensitive non-GET requests attach monitor-mode trust headers.
- DeviceCheck token is attached when supported.
- App Attest support is signaled when supported.
- Backend CORS allows the Captro trust headers.

How to test:

- Send a post/comment/report/upload request from the app and inspect request headers in a safe debug proxy.
- Confirm `X-Captro-Device-Trust-Mode: monitor` appears.
- Confirm unsupported devices still complete requests.

Production risk:

- Low in monitor mode.
- High if strict enforcement is enabled before server verification and Apple provisioning are complete.

Remaining work / safe phased plan:

- Phase A: add Worker endpoint/challenge storage for App Attest key registration.
- Phase B: verify App Attest assertions server-side for sensitive write/upload endpoints.
- Phase C: log monitor results only.
- Phase D: enforce on high-risk endpoints after measuring false negatives.

## 8. BackgroundTasks Cache Refresh

Status: implemented

Files changed/verified:

- `ios_native/MIRA/Sources/MIRANative/Services/MIRABackgroundTasks.swift`
- `ios_native/MIRA/AppTarget/MIRAApp.swift`
- `ios_native/MIRA/AppTarget/MIRAAppDelegate.swift`
- `ios_native/MIRA/AppTarget/Info.plist`
- `ios_native/MIRA/Sources/MIRANative/Services/MIRAPerformance.swift`

How it works:

- App registers app refresh and cache cleanup task identifiers.
- When app backgrounds, it schedules Feed/Discover/Chat cache refresh and cache cleanup.
- Refresh uses Keychain auth and lightweight existing endpoints.
- Cleanup trims stale JSON and image caches.

How to test:

- Install TestFlight build.
- Background the app, wait for iOS to grant background refresh.
- Use OSLog to confirm background refresh/cleanup events.
- Relaunch and confirm cached Feed/Discover/Chat previews appear quickly.

Production risk:

- Low. iOS treats these as best-effort; the app does not depend on them for correctness.

Remaining work:

- Add production metric for background refresh success/failure rate.
- Add user-facing fallback remains cache-first/skeleton when background refresh does not run.

## 9. UserNotifications + APNs

Status: partially implemented

Files changed/verified:

- `ios_native/MIRA/AppTarget/MIRAAppDelegate.swift`
- `ios_native/MIRA/Sources/MIRANative/Services/MIRAPushNotificationService.swift`
- `ios_native/MIRA/Sources/MIRANative/App/MIRANativeRootView.swift`
- `ios_native/MIRA/Sources/MIRANative/Screens/SettingsNativeView.swift`
- `backend-cf/src/index.ts`

How it works:

- iOS registers for remote notifications.
- APNs token is cached locally and sent to `/api/notifications/device-token` after auth.
- Backend stores active iOS push tokens in `push_tokens`.
- Backend has APNs alert sending support for stored tokens and deactivates invalid tokens.
- Notification open events are posted through `.miraNotificationOpened` and logged.
- Settings screen can request notification permission.

How to test:

- On a real device, grant notification permission from Settings.
- Confirm device token registration reaches `/api/notifications/device-token`.
- Trigger a backend notification such as comment/message/follow where implemented.
- Tap notification and verify `.miraNotificationOpened` is emitted.

Production risk:

- Medium. Token registration is implemented, but full deep-link routing from notification payload to exact screen is not complete in the verified code.

Remaining work / safe phased plan:

- Phase A: add typed notification route parser for post/comment/chat/profile payloads.
- Phase B: route `.miraNotificationOpened` into the app navigation model.
- Phase C: add user privacy setting for hidden message previews.
- Phase D: verify blocked users do not trigger notifications for the blocker.

## Extra Change: Profile Wallet Renamed

Status: implemented

Files changed/verified:

- `ios_native/MIRA/Sources/MIRANative/Screens/ProfileChatVerificationStudio.swift`

How it works:

- The Profile toolbar wallet icon was replaced with a trophy icon labeled `Contest prizes`.
- The destination screen title changed from `Wallet` to `Contest prizes`.
- Wallet copy now reads as prize credits/prize perks while keeping the existing backend data model so no production API change is required.

How to test:

- Open Profile.
- Tap the trophy icon.
- Confirm the screen opens as `Contest prizes`.

## Overall Remaining Work

- Run real-device TestFlight QA for camera memory pressure, video recording, PhotosUI large videos, and category accuracy.
- Add App Attest server-side verification before any enforcement.
- Add notification deep-link routing.
- Add large-asset temporary-file picker flow for big videos.
- Add optional archival original media flow if Captro needs both original uploads and optimized 1080 x 1440 feed assets.
