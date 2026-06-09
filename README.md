# Captro Production Repo

This repository is now scoped to the production Captro app:

- `ios_native/MIRA` - native iOS app built with Swift, SwiftUI/UIKit, C++, and Rust.
- `backend-cf` - Cloudflare Workers API, Supabase Auth/Postgres production database integration, legacy D1 compatibility migrations, Cloudflare media/upload routes, auth/session support, calls, feed, chat, comments, reporting, and moderation endpoints.
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

Supabase Postgres is Captro's production database for structured app data while Cloudflare Workers remain the secure backend layer. Cloudflare D1 remains only as a legacy compatibility/cache layer while old route groups are migrated. See `SUPABASE_POSTGRES_CUTOVER.md`.

Supabase is PostgreSQL. Do not use MySQL as a second primary database for Captro app data. If a MySQL import or reporting connection is needed, use Cloudflare Hyperdrive as a separate bridge and migrate into Supabase Postgres.
