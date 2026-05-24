# Captro Production Repo

This repository is now scoped to the production Captro app:

- `ios_native/MIRA` - native iOS app built with Swift, SwiftUI/UIKit, C++, and Rust.
- `backend-cf` - Cloudflare Workers API, D1 migrations, media/upload routes, auth/session support, calls, feed, chat, comments, reporting, and moderation endpoints.
- `.github/workflows` - production deployment, TestFlight, Dependabot, and security scanning automation.

The old Emergent scaffold, Expo/React Native frontend, Python/FastAPI backend, generated test reports, and broken `original_app` submodule were removed from the production tree.

## Production Checks

```bash
cd backend-cf
npm ci
npx tsc --noEmit
```

Security scans run in GitHub Actions with Gitleaks, Semgrep, CodeQL, and Dependabot.

## iOS

The iOS app is generated with XcodeGen from `ios_native/MIRA/project.yml` and uploaded to TestFlight through the `Native iOS TestFlight` workflow.

## Cloudflare

Cloudflare secrets must stay in GitHub/Cloudflare secrets, not in the app or repository. Deployments use:

```bash
cd backend-cf
npx wrangler deploy --keep-vars
```
