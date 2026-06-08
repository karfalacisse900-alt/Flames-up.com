# Captro Supabase Authentication Integration

Captro account creation now goes through Supabase Authentication first. The Cloudflare Worker still keeps the D1 `users` row as the app profile mirror, but the Supabase Auth user id is stored in `users.supabase_user_id`.

## What This Means

- New email/password accounts are created with the Supabase Auth Admin API, then mirrored into D1.
- Email/password login first uses Supabase Auth so Supabase can track provider data and last sign-in.
- Legacy D1-only password accounts are linked into Supabase Auth on the next successful login.
- Google and Apple login routes first try Supabase `signInWithIdToken` so provider identities show in Supabase Authentication.
- If Supabase provider configuration is missing, Captro falls back to the existing verified OAuth flow and mirrors the user into Supabase Auth when a real email is available.
- Phone-verified users are mirrored into Supabase Auth with a confirmed phone number.
- Profile, username, email, password, and phone updates sync back to Supabase Auth where possible.

## Required Worker Secrets

Required:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Recommended for token grant calls:

- `SUPABASE_ANON_KEY`

The service role key must only live in Cloudflare Worker secrets or GitHub Actions secrets. Never put it in the iOS app or admin web frontend.

## Google Account Chooser Branding

If the Google sign-in page says `Choose an account to continue with MIRA`, the fix is in Google/Supabase configuration, not in the Swift login button text.

Local Captro branding is already configured in the iOS app:

- `CFBundleDisplayName = Captro`
- `CFBundleName = Captro`
- `PRODUCT_BUNDLE_IDENTIFIER = com.captro.app`

Update production OAuth branding:

1. Google Cloud Console > APIs & Services > OAuth consent screen / Branding.
2. Set the app name to `Captro`.
3. Confirm the support email and developer contact email.
4. Rename or recreate the iOS OAuth client for bundle ID `com.captro.app`.
5. Rename or recreate the Web OAuth client used by Supabase Authentication.
6. Supabase Dashboard > Authentication > Providers > Google: use the Captro Web OAuth client ID and secret.
7. Keep `GOOGLE_OAUTH_CLIENT_IDS` in the Worker secret in sync with the current Captro OAuth client IDs.

Google can cache old OAuth branding for a short time. If the old name remains after updating branding, create fresh Captro OAuth clients and replace the old MIRA client IDs.

## Legacy User Backfill

Owner/admins can backfill existing D1 users into Supabase Authentication:

```http
POST /api/admin/supabase/auth/backfill
Authorization: Bearer <captro_admin_token>
Content-Type: application/json

{ "limit": 100, "offset": 0 }
```

Run again with the returned `next_offset` until `processed` is `0`.

Notes:

- Existing users without `supabase_user_id` are linked by email or verified phone.
- Existing password users get a Supabase Auth row immediately, and their Supabase password is set on the next successful password login or password update.
- Users with only an Apple/Google subject and no real email are linked when they next sign in through Supabase provider flow.
- The endpoint does not print secrets or tokens.

## Verification

1. Create a new email/password account in Captro.
2. Confirm the user appears in Supabase Dashboard > Authentication > Users.
3. Confirm D1 `users.supabase_user_id` matches the Supabase Auth UID.
4. Log in again and confirm Supabase `last_sign_in_at` updates.
5. Test Google/Apple sign-in and confirm the provider appears in Supabase Auth when the provider is configured in Supabase.
6. Run `/api/database/status` as owner/admin and confirm `supabase_authentication.service_role_secret_set` is true.
