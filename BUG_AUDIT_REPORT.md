# Captro Bug Audit Report

Date: 2026-05-31

## Fixed In This Pass

### Media tiles can stay stuck on placeholders
- Affected area: Home Feed, Discover, profile grids, post details
- Severity: High
- Steps to reproduce: Open Feed/Discover after media URLs are served through Cloudflare Image Transform URLs and scroll into posts whose transformed URL is unavailable or slow.
- Expected behavior: Media shows from optimized URL, with a fallback instead of a dead placeholder.
- Actual behavior: Some tiles stayed on the neutral placeholder.
- Root cause: The app only tried the transformed URL/fallbacks explicitly supplied by the screen. If the transformed `/cdn-cgi/image/...` URL failed, there was no automatic source URL fallback.
- Fix made: `MIRACachedImage` now derives the original HTTPS source from Cloudflare Image Transform URLs as a last-resort fallback.
- Test result: Local code check pending GitHub iOS build.

### Blank or whitespace media URLs pollute media candidate lists
- Affected area: Feed, Discover, post details, profile grid
- Severity: Medium
- Steps to reproduce: Load posts with empty strings in image/media arrays.
- Expected behavior: Empty media values are ignored.
- Actual behavior: Empty values could become candidates and weaken fallback behavior.
- Root cause: `MIRAPost.uniqueMediaURLs` did not trim or filter empty media strings.
- Fix made: Media URLs are now trimmed, empty values are removed, and duplicates are filtered after normalization.
- Test result: Local code check pending GitHub iOS build.

### Detail page caption fallback shows "MIRA post"
- Affected area: Discover detail and post detail
- Severity: Medium
- Steps to reproduce: Open a post without caption/title.
- Expected behavior: Leave the caption/title area blank.
- Actual behavior: Detail screens could show "MIRA post".
- Root cause: `MIRAPost.titleText` used a hardcoded fallback.
- Fix made: Removed the fallback and hid the title area when empty.
- Test result: Verified no `MIRA post` string remains in iOS source.

### Post detail media used heavier/less reliable media path
- Affected area: Post detail
- Severity: High
- Steps to reproduce: Open a post detail from Feed/Discover.
- Expected behavior: Detail should use optimized feed media and thumbnail/poster placeholders.
- Actual behavior: Detail could use original/media URLs directly and load slower.
- Root cause: `PostDetailNativeView` used `mediaURLs` instead of optimized `feedMediaURLs`.
- Fix made: Added optimized detail media carousel using feed media first, thumbnail/poster placeholders, and safe fallback.
- Test result: Local code check pending GitHub iOS build.

### Like counts can drop to zero after refresh/cache merge
- Affected area: Feed, Discover, detail page
- Severity: High
- Steps to reproduce: Like a post, then let detail refresh or cached feed merge with stale network data.
- Expected behavior: Counts should not visibly collapse to stale zero.
- Actual behavior: Stale network/cache values could replace a visible nonzero count.
- Root cause: Cache merge and detail refresh trusted lower incoming counters too aggressively.
- Fix made: Detail refresh and cache merge now preserve the stronger visible engagement counts when fresh data is stale.
- Test result: Local code check pending GitHub iOS build.

### Avatar/profile picture blinking
- Affected area: Chat list, chat room, comments, profile references
- Severity: High
- Steps to reproduce: Open chat/comments while avatar URLs refresh or are re-resolved.
- Expected behavior: Previous avatar stays visible until the new avatar is ready.
- Actual behavior: Avatar could snap back to placeholder before loading again.
- Root cause: `RemoteAvatar` cleared its current image during URL changes/loading.
- Fix made: `MIRACachedImage` now supports keeping previous image while loading; `RemoteAvatar` uses it and trims blank URLs.
- Test result: Local code check pending GitHub iOS build.

### Chat message ordering can be wrong after sync
- Affected area: Chat room and local chat cache
- Severity: High
- Steps to reproduce: Send local media/text, sync server messages, reopen chat.
- Expected behavior: Messages appear in the server send order, with local date used only for sending/failed messages.
- Actual behavior: Synced messages could still sort by stale `localCreatedAt`.
- Root cause: Sort logic preferred local timestamp over server timestamp for all messages.
- Fix made: Sorting now uses server sequence first, then local timestamp only for local/sending/failed messages, then server `createdAt`.
- Test result: Local code check pending GitHub iOS build.

### Retrying chat media can freeze UI
- Affected area: Chat room media retry
- Severity: Medium
- Steps to reproduce: Retry a failed local image/video message with a large local file.
- Expected behavior: File data loads off the main actor.
- Actual behavior: `Data(contentsOf:)` could run from the main-actor model path.
- Root cause: Synchronous file read in retry path.
- Fix made: Local retry data now loads in a detached utility task.
- Test result: Local code check pending GitHub iOS build.

### Welcome music continues into auth flow
- Affected area: Welcome, login, signup
- Severity: Medium
- Steps to reproduce: Start welcome music, tap Log in or Sign up.
- Expected behavior: Welcome music stops when leaving the welcome experience.
- Actual behavior: Music could continue behind auth UI until the welcome view disappeared.
- Root cause: Login/signup actions did not explicitly stop the welcome audio controller.
- Fix made: Login/signup actions stop welcome audio before presenting auth.
- Test result: Local code check pending GitHub iOS build.

## Remaining Work Recommended

### Real-device media verification
- Affected area: Feed, Discover, Stories
- Severity: High
- Recommended fix: Verify production media URLs from TestFlight logs and ensure Cloudflare Images/Stream URLs return 200 for the exact URLs in feed payloads.

### Real-device Swift crash triage
- Affected area: Whole iOS app
- Severity: High
- Recommended fix: Inspect TestFlight/Crashlytics/Xcode Organizer crash logs. Local Windows cannot symbolicate or run Instruments.

### Story video startup latency
- Affected area: Stories
- Severity: Medium
- Recommended fix: Keep measuring story prewarm hit rate on device and tune Stream poster/player preparation if first playback still lags.

### Feed photo-only backend cleanup
- Affected area: Backend/API and old data
- Severity: Medium
- Recommended fix: Existing video posts are now excluded from Feed/Discover photo grids. Migrate old video feed posts into Stories or hide them from photo-only surfaces to avoid confusing empty categories.
