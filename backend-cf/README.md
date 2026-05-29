# Flames-Up API (Cloudflare Workers)

Backend stack: Hono + D1 + Cloudflare Images/Stream.

## Setup

1. Install dependencies:
   `npm install`

2. Run migrations (remote):
   `wrangler d1 execute flames-up-db --file=./migrations/0001_init.sql --remote`
   `wrangler d1 execute flames-up-db --file=./migrations/0002_additions.sql --remote`
   `wrangler d1 execute flames-up-db --file=./migrations/0003_creators.sql --remote`
   `wrangler d1 execute flames-up-db --file=./migrations/0004_oauth.sql --remote`
   `wrangler d1 execute flames-up-db --file=./migrations/0005_phone_auth.sql --remote`
   `wrangler d1 execute flames-up-db --file=./migrations/0019_production_performance_indexes.sql --remote`
   `wrangler d1 execute DB --env production --remote --yes --file=./migrations/0020_production_readiness.sql`
   `wrangler d1 execute DB --env production --remote --yes --file=./migrations/0021_admin_moderation.sql`

3. Configure vars:
   - `JWT_SECRET`
   - `CLOUDFLARE_ACCOUNT_ID`
   - `CLOUDFLARE_IMAGES_TOKEN` and `CLOUDFLARE_STREAM_TOKEN` as Worker secrets, or a shared `CLOUDFLARE_API_TOKEN` that has Cloudflare Images and Stream permissions
   - `CLOUDFLARE_IMAGES_ACCOUNT_HASH` for `https://imagedelivery.net/...` delivery URLs
   - `MAPBOX_ACCESS_TOKEN`
   - `OWNER_EMAILS` (comma-separated verified account emails that receive owner admin role)
   - `OWNER_USERNAMES` (optional comma-separated real usernames; do not use generated/temp usernames)
   - `GOOGLE_OAUTH_CLIENT_IDS` (comma-separated Google client IDs)
   - `APPLE_OAUTH_AUDIENCES` (comma-separated Apple audiences, bundle/service IDs)
   - `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_VERIFY_SERVICE_SID` for Twilio Verify phone codes
   - `TWILIO_FROM_PHONE` is only used by the legacy SMS fallback if Verify is not configured
   - `SUPABASE_URL` as a public Worker var, for example `https://your-project-ref.supabase.co`
   - `SUPABASE_SERVICE_ROLE_KEY` as a Worker secret only; never put this in the iOS app or public config
   - `SUPABASE_JWT_ISSUER` only if your Supabase issuer differs from `SUPABASE_URL/auth/v1`
- `APNS_PRIVATE_KEY`, `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_BUNDLE_ID`, and `APNS_ENVIRONMENT` for standard iOS push notifications

4. Deploy:
   `wrangler deploy --env production --keep-vars`

Google OAuth requires the same client IDs used by the native app and web auth callback:

```powershell
$ids = "your-web-client-id.apps.googleusercontent.com,your-ios-client-id.apps.googleusercontent.com,your-android-client-id.apps.googleusercontent.com"
$ids | npx wrangler secret put GOOGLE_OAUTH_CLIENT_IDS --env production
npx wrangler deploy --env production
```

## Auth Endpoints

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/oauth/google`
- `POST /api/auth/oauth/apple`
- `POST /api/auth/phone/start`
- `POST /api/auth/phone/verify`
- `GET /api/auth/me`

If Twilio is not configured, `/api/auth/phone/start` returns a `dev_code` for local testing instead of sending SMS.

## Supabase Auth + Postgres/JSONB

Supabase is used for production auth, PostgreSQL tables, and JSONB document storage. The JSONB `app_documents` table is the app's flexible NoSQL-style layer; it is still stored securely inside Postgres with RLS.

Run or push the Supabase migrations from the repository root:

```powershell
cd "C:\Users\The-s\Documents\New project\Flames-up.com"
npx.cmd supabase db push
```

Set the backend service-role secret for Cloudflare Workers:

```powershell
cd "C:\Users\The-s\Documents\New project\Flames-up.com\backend-cf"
npx.cmd wrangler secret put SUPABASE_SERVICE_ROLE_KEY --env production
npx.cmd wrangler deploy --env production
```

The native app should only use public Supabase values:

```text
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
SUPABASE_WEB_REDIRECT_URI=https://flames-up.com/auth/callback
SUPABASE_NATIVE_REDIRECT_URI=captro://auth/callback
```

Google OAuth setup:
- Google Cloud authorized redirect URI should be the Supabase callback: `https://your-project-ref.supabase.co/auth/v1/callback`
- Supabase Auth redirect URLs should include both `https://flames-up.com/auth/callback` and `captro://auth/callback`
- Use the Web OAuth client ID and client secret in the Supabase Google provider. Native iOS/Android IDs can be used by the mobile app, but Supabase's provider secret belongs to the Web client.

Apple native sign-in:
- Enable Sign in with Apple on the iOS App ID `com.karfala90.frontend`.
- Configure the Apple Services ID in Supabase for web OAuth.
- Set `APPLE_OAUTH_AUDIENCES` on the Worker to include both the iOS bundle ID and the Services ID, for example `com.karfala90.frontend,com.karfala90.frontend.auth`.

## Admin Moderation API

The private admin web app uses protected `/api/admin/*` endpoints. These routes require normal Captro authentication plus backend role authorization; frontend checks are never the source of truth.

Admin roles:

- `owner`
- `admin`
- `moderator`
- `support`
- `viewer`

Existing `users.is_admin = 1` accounts are treated as `admin`. Emails listed in `OWNER_EMAILS` are treated as `owner`; real usernames listed in `OWNER_USERNAMES` can also be used when intentionally configured. Use the `admin_roles` table for explicit lower-privilege roles.

Important endpoints:

- `GET /api/admin/me`
- `GET /api/admin/dashboard`
- `GET /api/admin/reports`
- `GET /api/admin/reports/:reportId`
- `POST /api/admin/reports/:reportId/status`
- `POST /api/admin/reports/:reportId/action`
- `POST /api/admin/reports/:reportId/note`
- `GET /api/admin/users`
- `POST /api/admin/users/:userId/warn`
- `POST /api/admin/users/:userId/restrict`
- `POST /api/admin/users/:userId/suspend`
- `POST /api/admin/users/:userId/ban`
- `GET /api/admin/posts`
- `POST /api/admin/posts/:postId/remove`
- `POST /api/admin/posts/:postId/restore`
- `GET /api/admin/comments`
- `POST /api/admin/comments/:commentId/remove`
- `GET /api/admin/messages/reported`
- `GET /api/admin/audit-logs`

Every write/destructive route requires a reason and records an audit log. Reported message detail views are also audit logged and return limited nearby context only.
