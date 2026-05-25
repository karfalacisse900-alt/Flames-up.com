# Captro Production Readiness Checklist

This checklist covers the production work that is not the moderation/admin queue.

## App Store Review

- Verify Terms, Privacy Policy, Community Guidelines, Safety & Reporting, support email, block, report, and delete account are reachable in the app.
- Use a real reviewer account with feed, discover, profile, chat, comments, uploads, notifications, and settings available.
- Confirm no placeholder brands, broken empty states, debug text, or unfinished screens appear in the first session.
- Confirm user-generated-content safety tools exist in the app before submission.

## Device QA

- Fresh install, login, Apple/Google signup, username onboarding, logout, and account deletion.
- Feed scroll, cached startup, Discover filters, profile grid, comments, saves, likes, follows, blocks, and reports.
- Photo upload, video upload, post creation, story creation, upload retry, failed upload state, and slow network.
- Chat list, direct chat, group chat, media messages, voice recording, voice preview, voice send, and voice playback on the receiver device.
- Push permission prompt, device-token registration, foreground notification presentation, and settings toggles.
- Keyboard open/close in comments, chat, profile edit, signup, and settings.
- Background/foreground, privacy shield, app resume, and low-connectivity recovery.

## Production Monitoring

- Watch Cloudflare Worker request rate, error rate, slow-route logs, and D1 query behavior after every deploy.
- Review client event volume for upload failures, push-token registration failures, startup failures, and media playback issues.
- Keep GitHub Security Scans, Worker deploy, and TestFlight workflows green before each release.

## Performance

- Confirm `/api/health` is healthy and `/api/health/check` is not used.
- Confirm feed responses use optimized media URLs and small payloads.
- Confirm startup mounts Feed, Discover, Profile, Chat, and stable placeholders before the splash disappears.
- Confirm tab switching does not refetch everything or reset scroll state.
