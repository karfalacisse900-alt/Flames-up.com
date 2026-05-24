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

3. Configure vars:
   - `JWT_SECRET`
   - `CLOUDFLARE_ACCOUNT_ID`
   - `CLOUDFLARE_IMAGES_TOKEN`
   - `CLOUDFLARE_STREAM_TOKEN`
   - `MAPBOX_ACCESS_TOKEN`
   - `OWNER_USERNAMES` (comma-separated usernames that can use creator actions before phone verification)
   - `GOOGLE_OAUTH_CLIENT_IDS` (comma-separated Google client IDs)
   - `APPLE_OAUTH_AUDIENCES` (comma-separated Apple audiences, bundle/service IDs)
   - `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_VERIFY_SERVICE_SID` for Twilio Verify phone codes
   - `TWILIO_FROM_PHONE` is only used by the legacy SMS fallback if Verify is not configured
   - `SUPABASE_URL` as a public Worker var, for example `https://your-project-ref.supabase.co`
   - `SUPABASE_SERVICE_ROLE_KEY` as a Worker secret only; never put this in the iOS app or public config
   - `SUPABASE_JWT_ISSUER` only if your Supabase issuer differs from `SUPABASE_URL/auth/v1`

4. Deploy:
   `wrangler deploy`

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
