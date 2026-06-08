# Captro Supabase Postgres Cutover

Captro's production data target is Supabase Auth + Supabase Postgres. Cloudflare Workers remain the secure API boundary, and Cloudflare Images/R2/Stream remain the media storage and delivery layer.

Supabase is PostgreSQL. Do not run Supabase Postgres and MySQL as two active primary databases for the same app data. If Captro needs to import data from MySQL, or read a MySQL reporting database later, connect it through Cloudflare Hyperdrive as a separate import/read-only integration.

## Current State

- Live API: `https://api.flames-up.com/api`
- Worker: `backend-cf`
- Current live operational store: Cloudflare D1
- Target structured data store: Supabase Postgres
- Auth target: Supabase Authentication
- Media target: Cloudflare Images/R2 for photos and Cloudflare Stream for videos

The Worker already has:

- Supabase Auth bridging for email/password, Google, Apple, and phone where configured.
- D1 to Supabase transfer endpoint: `POST /api/admin/supabase/transfer`
- Supabase write-through helpers for users, posts, comments, interactions, follows, and bookmarks.
- `/api/database/status` for owner/admin verification.

## What Was Added

Migration:

```text
supabase/migrations/202606080001_captro_core.sql
```

This creates:

- `app_users`
- `app_posts`
- `post_comments`
- `app_post_interactions`
- `app_follows`
- `app_documents`

RLS is enabled on these tables. By default, the iOS app should not read these tables directly. Captro clients should keep using the Cloudflare Worker API, which enforces auth, permissions, blocks, moderation, and response shaping.

## Safe Cutover Order

1. Link the local repo to the production Supabase project.

```powershell
npx.cmd supabase login
npx.cmd supabase link --project-ref cclgvxukwccvtgrbcwie
```

2. Push the Supabase Postgres schema.

```powershell
npx.cmd supabase db push
```

3. Confirm Worker secrets are configured.

```powershell
cd backend-cf
npx.cmd wrangler secret put SUPABASE_SERVICE_ROLE_KEY --env production
npx.cmd wrangler secret put SUPABASE_ANON_KEY --env production
```

Do not print secrets in logs, GitHub Actions, or the app.

4. Verify backend status as an owner/admin.

```powershell
$env:CAPTRO_ADMIN_TOKEN = "<your admin token>"
Invoke-RestMethod `
  -Uri "https://api.flames-up.com/api/database/status" `
  -Headers @{ Authorization = "Bearer $env:CAPTRO_ADMIN_TOKEN" }
```

Expected:

- `supabase_postgres_jsonb.configured = true`
- `supabase_postgres_jsonb.service_role_secret_set = true`
- `supabase_authentication.configured = true`

5. Backfill Supabase Auth users.

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri "https://api.flames-up.com/api/admin/supabase/auth/backfill" `
  -Headers @{ Authorization = "Bearer $env:CAPTRO_ADMIN_TOKEN" } `
  -ContentType "application/json" `
  -Body '{"limit":100,"offset":0}'
```

Repeat with the returned `next_offset` until `processed` is `0`.

6. Transfer D1 structured data to Supabase Postgres.

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri "https://api.flames-up.com/api/admin/supabase/transfer" `
  -Headers @{ Authorization = "Bearer $env:CAPTRO_ADMIN_TOKEN" } `
  -ContentType "application/json" `
  -Body '{"limit":500,"offset":0,"tables":["users","posts","comments","interactions","follows"]}'
```

Repeat with the returned `next_offset` until every table returns zero transferred rows.

7. Validate counts before any read cutover.

Check Supabase rows against D1 counts:

- users vs `app_users`
- posts vs `app_posts`
- comments vs `post_comments`
- likes/saves vs `app_post_interactions`
- follows vs `app_follows`

Also verify:

- Like uniqueness is one row per `legacy_post_id + app_user_id + kind`.
- Deleted/removed/banned content is not visible through Worker feed/discover/profile responses.
- Media URLs still point to Cloudflare Images/R2/Stream, not Supabase storage.

8. Cut reads over only after validation.

The safe production path is:

- Keep D1 live while transfer/write-through is verified.
- Add Supabase read paths behind a Worker env flag.
- Compare D1 and Supabase responses for high-risk routes.
- Switch one route group at a time: profiles, then interactions, then posts/feed, then comments/follows.
- Keep D1 fallback until TestFlight confirms stability.

Do not delete D1 until Supabase has served production traffic safely for a full retention window.

## MySQL Position

Captro should not use MySQL as the main app database while moving to Supabase, because Supabase is PostgreSQL and the Worker already targets Supabase REST/Postgres tables.

Use MySQL only for:

- One-time import from an old database.
- Analytics/reporting outside the core app.
- A temporary legacy read bridge.

If MySQL is needed, create a separate Cloudflare Hyperdrive binding for it and keep writes one-way into Supabase Postgres.

## Google Sign-In Branding

If `accounts.google.com` says `continue with MIRA`, change the Google OAuth project branding, not Swift code.

Update:

1. Google Cloud Console > APIs & Services > OAuth consent screen / Branding
2. App name: `Captro`
3. Support email and developer contact email
4. OAuth clients used by Captro:
   - iOS client for `com.captro.app`
   - Web client used by Supabase Google provider
5. Supabase Dashboard > Authentication > Providers > Google
   - Use the Captro web OAuth client ID/secret
   - Callback URL: `https://cclgvxukwccvtgrbcwie.supabase.co/auth/v1/callback`

The iOS bundle already uses:

- Display name: `Captro`
- Bundle ID: `com.captro.app`

Google may cache old consent branding for a while. If the chooser still says MIRA after updating branding, create fresh Captro OAuth clients and replace the old MIRA client IDs in the Worker secret and iOS `GIDClientID`.
