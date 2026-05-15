# Governance Mobile

Governance Mobile is a separate Expo app for Flames-Up admins and moderators. It connects to the same Cloudflare Worker API as the main app, but only uses the clean `/api/admin/governance/*` endpoints.

## Run on Windows

```powershell
cd "C:\Users\The-s\Documents\New project\Flames-up.com\governance-mobile"
& "C:\Program Files\nodejs\npm.cmd" install
@"
EXPO_PUBLIC_API_URL=https://api.flames-up.com
"@ | Set-Content -Path .env -Encoding UTF8
& "C:\Program Files\nodejs\npx.cmd" expo start --go --tunnel
```

For local backend testing, change `EXPO_PUBLIC_API_URL` to your Worker dev URL.

## Backend required

Deploy the Cloudflare Worker changes and apply `backend-cf/migrations/0008_governance_mobile.sql` if the production database has not already been upgraded by the Worker runtime.

Admins must log in with an existing Flames-Up account where `users.is_admin = 1`.

## Create your admin login

If you signed up with Apple/Google and do not have a password login yet, run this helper after `wrangler login`:

```powershell
cd "C:\Users\The-s\Documents\New project\Flames-up.com\governance-mobile"
powershell -ExecutionPolicy Bypass -File .\scripts\grant-admin.ps1 -Username "dxhfqhsd5c"
```

Enter a new admin password when prompted. Then open Governance Mobile and log in with the email on that Flames-Up account plus the password you entered.
