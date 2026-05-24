# Captro Security, Production, and Performance Audit Plan

Last updated: 2026-05-24

This plan defines Captro's repeatable release audit process across the native iOS app, Cloudflare Worker API, database, media pipeline, and production operations.

## Standards Baseline

- **OWASP MASVS / MASTG:** iOS mobile security, data-at-rest, network, platform, privacy, and resilience checks.
- **OWASP ASVS:** backend authentication, access control, validation, error handling, logging, and data protection.
- **OWASP API Security Top 10:** object-level authorization, authentication, authorization, unrestricted resource consumption, mass assignment, SSRF, unsafe API consumption, and security misconfiguration.
- **OWASP SAMM:** long-term security maturity for governance, design, implementation, verification, and operations.
- **NIST SSDF:** secure software development practices from requirements through release and incident response.
- **CIS Controls:** operational basics such as inventory, vulnerability management, access control, secure configuration, logging, monitoring, and incident response.

## Tooling Setup

| Area | Tool | Status | Purpose |
| --- | --- | --- | --- |
| Dependency scanning | Dependabot | Configured in `.github/dependabot.yml` | Weekly update PRs for GitHub Actions, npm, SwiftPM, Cargo, and Gradle dependencies. |
| Code scanning | GitHub CodeQL | Configured in `.github/workflows/security-scans.yml` | JavaScript/TypeScript and Swift code scanning. |
| Secret scanning | Gitleaks | Configured in `.github/workflows/security-scans.yml` and `.gitleaks.toml` | CI secret leak detection with redacted output. |
| Custom rules | Semgrep | Configured in `.github/workflows/security-scans.yml` and `.semgrep.yml` | Captro-specific checks for token storage, insecure URLs, sensitive logs, SQL interpolation, and weak randomness. |
| iOS binary scanning | MobSF | Required before release candidate | Scan signed IPA for MASVS/MASTG issues. |
| API/network testing | Burp Suite or Proxyman | Required before release candidate | Validate auth, TLS, token handling, object-level access control, and privacy of network traffic. |
| Swift static analysis | Xcode Static Analyzer | Required before release candidate | Detect Swift, UIKit/SwiftUI, memory, and platform misuse issues. |
| Performance profiling | Xcode Instruments | Required before release candidate | Measure startup, CPU, memory, leaks, hangs, scroll performance, image/video decode, and main-thread blocking. |
| Production metrics | Xcode Organizer / MetricKit | Required production review | Track launch, hangs, crashes, memory, energy, and responsiveness in the field. |
| Crash monitoring | Sentry or Firebase Crashlytics | Recommended production integration | Crash/error visibility with release and user-impact grouping. |
| Backend monitoring | Cloudflare Analytics/Logs | Required production review | API latency, error rate, WAF/rate-limit events, Worker exceptions, D1/R2 errors, and abusive traffic patterns. |

## Release Gate Checklist

Every TestFlight release candidate should pass this checklist before it is promoted:

- [ ] `backend-cf`: TypeScript build passes with `npx tsc --noEmit`.
- [ ] Native iOS GitHub Action archive/export/upload succeeds.
- [ ] Dependabot alerts reviewed; high/critical dependency issues fixed or risk-accepted.
- [ ] CodeQL scan reviewed with no unresolved high/critical findings.
- [ ] Gitleaks scan passes with no real secrets.
- [ ] Semgrep scan reviewed; Captro custom rules have no unresolved high-confidence findings.
- [ ] GitHub repository secret scanning and push protection are enabled in repo settings where available.
- [ ] MobSF IPA scan completed and high-risk findings triaged.
- [ ] Burp Suite or Proxyman test pass completed for auth, chat, feed, media, comments, reports, blocks, saves, and admin routes.
- [ ] Xcode Static Analyzer completed with no release-blocking findings.
- [ ] Xcode Instruments pass completed for startup, feed scrolling, media loading, chat, comments, camera/story creation, and video playback.
- [ ] Crash monitoring release tag is configured if Sentry/Firebase is enabled.
- [ ] Cloudflare Analytics/Logs checked for abnormal 4xx/5xx spikes, rate limits, Worker errors, and latency regressions.
- [ ] Manual abuse tests pass for blocking, reporting, username abuse, duplicate likes/saves/messages, and admin route access.

## Captro Risk Checklist

### Auth and Session Security

- [ ] Password auth uses bcrypt or stronger password hashing with per-user salts.
- [ ] Apple and Google login tokens are validated server-side.
- [ ] Captro API sessions expire and can be safely invalidated.
- [ ] iOS auth tokens are stored in Keychain, not UserDefaults.
- [ ] Logout clears Keychain tokens and sensitive local session cache.
- [ ] Login, signup, OAuth, username check, phone/OTP, and password flows are rate-limited.
- [ ] Sensitive token/password/email/private-message data is not logged.

### API Authorization and Object Access

- [ ] Backend checks ownership or admin role for every edit/delete action.
- [ ] Users cannot read chats they do not belong to.
- [ ] Users cannot edit or delete another user's posts/comments/messages.
- [ ] Blocked users cannot message or interact where blocking should prevent contact.
- [ ] Admin routes require backend-side admin authorization.
- [ ] Object IDs are sanitized and never trusted without DB permission checks.
- [ ] Unknown fields are rejected on sensitive endpoints to prevent mass assignment.

### Chat Privacy

- [ ] Direct and group messages require participant membership.
- [ ] Push notifications do not include private message text unless an explicit privacy setting permits it.
- [ ] Reported messages can be reviewed by moderation without making private chats public.
- [ ] Voice/video call tokens are short-lived and generated by the backend.
- [ ] VoIP pushes are used only for real call events.

### Media Upload and Delivery

- [ ] Images/videos are validated by content, size, and allowed type.
- [ ] Unsafe files and disguised executables are rejected.
- [ ] Original media is preserved safely, while feed uses optimized derivatives.
- [ ] Unattached/private media requires owner/admin access.
- [ ] Feed does not serve full original media by default.
- [ ] Media URLs are HTTPS or controlled internal references.
- [ ] R2/Cloudflare storage credentials are never exposed to the app.

### Rate Limiting and Abuse

- [ ] Rate limits exist for login, signup, username checks, posting, commenting, liking, saving, following, messaging, reports, and uploads.
- [ ] Duplicate messages/comments/likes/saves are deduped or blocked.
- [ ] Username rules block reserved, impersonation-style, and generated public usernames.
- [ ] Reports support posts, comments, profiles, messages, stories/discover items, and relevant reasons.
- [ ] Blocking protects reporters and prevents harassment loops.

### Database and Backend Integrity

- [ ] D1 queries use prepared statements and bind parameters.
- [ ] Unique constraints protect usernames, follows, blocks, likes, saves, and call/session records where applicable.
- [ ] Soft delete is used where moderation/audit history must remain.
- [ ] Admin actions are audit logged.
- [ ] Stack traces and internal errors are not returned to clients.
- [ ] Request IDs are present in responses and logs.

### Feed and Performance

- [ ] Startup mounts a stable app shell before the splash disappears.
- [ ] Feed, Discover, Profile, and Chat use cached-first loading where possible.
- [ ] First visible media has reserved dimensions before image/video data arrives.
- [ ] Feed media uses optimized 3:4 variants and thumbnails instead of originals.
- [ ] Video playback creates only the necessary AVPlayer instances.
- [ ] Scrolling does not trigger duplicate API calls or full feed rebuilds.
- [ ] Opening comments/share/options/story/profile/chat does not reload the feed.

## Mobile App Testing Plan

Run this on a signed TestFlight or ad hoc IPA before release:

1. **MASVS-STORAGE:** Confirm tokens are only in Keychain. Check app container for auth tokens, passwords, private messages, and secrets.
2. **MASVS-CRYPTO:** Confirm no hardcoded crypto keys, weak random generation for security IDs, or custom crypto where platform APIs should be used.
3. **MASVS-AUTH:** Test login, logout, expired token, invalid token, Apple/Google signup, username onboarding, and blocked/suspended users.
4. **MASVS-NETWORK:** Use Proxyman/Burp to verify HTTPS-only traffic, no secrets in query strings, no private message body in notifications, and correct auth headers.
5. **MASVS-PLATFORM:** Verify app-switcher privacy shield, permission prompts, iOS settings links, notification privacy, and safe URL opening.
6. **MASVS-CODE:** Run Xcode Static Analyzer and review warnings.
7. **MASVS-RESILIENCE:** Confirm Release builds strip symbols/testability and do not expose debug menus/logging.
8. **MASVS-PRIVACY:** Confirm privacy manifest and legal pages match collected data and permissions.
9. **MobSF:** Upload the IPA and review storage, network, binary, privacy, ATS, permissions, and dependency findings.

## API Testing Plan

Use Burp Suite, Proxyman, curl, or a small authenticated test script:

- [ ] Requests without auth token are rejected.
- [ ] Expired/invalid token is rejected.
- [ ] User cannot edit/delete another user's post.
- [ ] User cannot delete another user's comment.
- [ ] User cannot read a chat they are not part of.
- [ ] Blocked user cannot message or call the blocker.
- [ ] Normal user cannot call admin endpoints.
- [ ] Username reserved/invalid/generated patterns are rejected.
- [ ] Upload invalid file type is rejected.
- [ ] Upload oversized media is rejected.
- [ ] Duplicate likes/saves/messages/comments are handled safely.
- [ ] Malformed JSON returns safe errors.
- [ ] SQL injection-style input is treated as text and does not alter queries.
- [ ] Rate limits trigger on spammy login/signup/comment/message/upload/search behavior.

## Performance Profiling Plan

Run Xcode Instruments on a representative device and simulator:

- **Startup:** Time from launch to stable tabs, splash duration, main-thread stalls, initial network waterfall.
- **Feed scroll:** FPS, main-thread work, view updates, image decode, media cache hit rate, AVPlayer count.
- **Comments:** Open/close 20 times, keyboard open/close, long comments, many comments.
- **Discover/Profile:** Tab switch latency, thumbnail loading, duplicate fetches, memory growth.
- **Chat:** Conversation load, voice message playback, media attach/upload, keyboard and bubble layout.
- **Camera/story/post creation:** Capture latency, preview playback, memory spikes, upload processing.
- **Leaks/hangs:** Instruments Leaks, Allocations, Time Profiler, Hangs, and SwiftUI profiling where available.

Target release thresholds:

- No repeated main-thread stalls above 250 ms during normal feed use.
- No feed scroll memory growth that keeps climbing after repeated tab switches.
- No duplicate fetch storm when switching tabs or opening overlays.
- No visible layout jumps from media loading.
- No crash or stuck state after repeated comments/chat/story/post creation flows.

## Production Monitoring Plan

### iOS

- Use Xcode Organizer and MetricKit after each TestFlight/App Store release.
- Track launch time, hangs, memory, disk writes, energy, crashes, and app termination reasons.
- Add Sentry or Firebase Crashlytics for release-aware crash grouping and non-fatal error visibility.
- Scrub PII from crash breadcrumbs and logs before sending events.

### Backend / Cloudflare

- Review Cloudflare Analytics weekly and after each deploy.
- Track Worker 5xx, uncaught exceptions, D1 latency/errors, R2 media errors, upload failures, WAF/rate-limit hits, and suspicious IP/device patterns.
- Alert on spikes in failed logins, media upload failures, reports, blocked actions, and admin errors.
- Keep Worker secrets in Cloudflare only; never ship Cloudflare, Stripe, Supabase service role, APNS, Agora certificate, or database secrets in the app.

## OWASP SAMM / NIST SSDF Operating Rhythm

- **Every PR:** Code review, security scan, dependency scan, secret scan, and object-level authorization review for changed backend routes.
- **Every weekly maintenance window:** Review Dependabot, CodeQL, Gitleaks, Semgrep, Cloudflare logs, and crash metrics.
- **Every release candidate:** Run the release gate checklist, MobSF scan, API abuse tests, and Instruments pass.
- **Every incident:** Record timeline, impact, root cause, remediation, key rotation if needed, and regression tests.
- **Every quarter:** Review threat model for auth, chat, media, calls, Discover, profile, moderation, admin, and payments/wallet if enabled.

## Repo Settings To Enable Manually

These cannot be fully enforced by committed files alone:

- Enable GitHub Dependabot alerts.
- Enable GitHub Dependabot security updates.
- Enable GitHub secret scanning and push protection where available.
- Enable CodeQL/code scanning alerts for this repository.
- Protect `main` with required checks: Gitleaks, Semgrep, CodeQL, backend typecheck, and iOS build.
- Require review before merging changes to auth, admin, database, media upload, chat, calls, or payment/wallet code.
