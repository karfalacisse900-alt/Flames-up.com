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
   - `GOOGLE_MAPS_API_KEY`
   - `GOOGLE_OAUTH_CLIENT_IDS` (comma-separated Google client IDs)
   - `APPLE_OAUTH_AUDIENCES` (comma-separated Apple audiences, bundle/service IDs)
   - `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_PHONE` for real SMS phone codes

4. Deploy:
   `wrangler deploy`

## Auth Endpoints

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/oauth/google`
- `POST /api/auth/oauth/apple`
- `POST /api/auth/phone/start`
- `POST /api/auth/phone/verify`
- `GET /api/auth/me`

If Twilio is not configured, `/api/auth/phone/start` returns a `dev_code` for local testing instead of sending SMS.
