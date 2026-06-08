# Captro Production Repo

This repository is now scoped to the production Captro app:

- `ios_native/MIRA` - native iOS app built with Swift, SwiftUI/UIKit, C++, and Rust.
- `backend-cf` - Cloudflare Workers API, legacy D1 migrations, Supabase Auth/Postgres transfer paths, media/upload routes, auth/session support, calls, feed, chat, comments, reporting, and moderation endpoints.
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

## Database Direction

Captro is moving structured app data to Supabase Postgres while keeping Cloudflare Workers as the secure backend layer. D1 remains the legacy/live store until the Supabase schema is pushed, transfer is verified, and read routes are cut over safely. See `SUPABASE_POSTGRES_CUTOVER.md`.

Supabase is PostgreSQL. Do not use MySQL as a second primary database for Captro app data. If a MySQL import or reporting connection is needed, use Cloudflare Hyperdrive as a separate bridge and migrate into Supabase Postgres.
