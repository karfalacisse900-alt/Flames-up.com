# Captro Production Admin Bootstrap

This document explains how production admin access is granted safely. Do not create demo users, hardcoded passwords, public admin signup, or frontend-only admin checks.

## Owner Access

Captro supports a backend owner allowlist through the Cloudflare Worker environment:

```text
OWNER_EMAILS=karfalacisse900@gmail.com
```

Use `OWNER_USERNAMES` only after the user has a real, chosen Captro username. Do not allowlist generated or temporary usernames.

When an authenticated user calls `GET /api/admin/me`, the Worker loads the user from the production database and checks:

- `OWNER_EMAILS` against the user's normalized account email
- `OWNER_USERNAMES` against the user's normalized username only when intentionally configured
- `admin_roles.user_id` for explicit staff roles
- legacy `users.is_admin = 1` as `admin`

If none match, the backend returns `403 Admin access required`. The admin web app must never show admin data before this backend check completes.

## Setting Owner Email

Use a Cloudflare Worker secret or protected environment variable. The email is not a password, but using the secret mechanism keeps production configuration controlled and auditable.

```powershell
cd backend-cf
"karfalacisse900@gmail.com" | npx.cmd wrangler secret put OWNER_EMAILS --env production
```

Then deploy the Worker:

```powershell
npx.cmd wrangler deploy --env production --keep-vars
```

The GitHub deploy workflow also preserves existing Worker variables/secrets with `--keep-vars`.

## Admin Role Table

The admin moderation schema creates:

```sql
admin_roles (
  user_id TEXT PRIMARY KEY,
  role TEXT NOT NULL,
  created_at TEXT NOT NULL,
  created_by TEXT DEFAULT '',
  updated_at TEXT NOT NULL
)
```

Supported roles:

- `owner`
- `admin`
- `moderator`
- `support`
- `viewer`

Prefer `OWNER_EMAILS` for the first owner bootstrap. Use `admin_roles` later for staff accounts that need narrower permissions.

## Verification

After deploy:

1. Sign in normally through the admin web app with the real Captro account.
2. Confirm `GET https://api.flames-up.com/api/admin/me` returns `role: owner` for the owner account.
3. Confirm a normal non-admin account receives `403 Admin access required`.
4. Open Dashboard, Reports, Users, Posts, Comments, Messages, and Audit Logs.
5. Confirm destructive actions require a reason.
6. Confirm write actions create rows in `audit_logs` and `moderation_actions`.

Do not print auth tokens, passwords, private messages, or secrets in logs.

## Removing or Rotating Owner Access

To remove email owner access, update or delete the Worker variable/secret:

```powershell
cd backend-cf
npx.cmd wrangler secret delete OWNER_EMAILS --env production
```

Then deploy the Worker again if needed:

```powershell
npx.cmd wrangler deploy --env production --keep-vars
```

For `admin_roles`, remove or update the row for the affected `user_id` after confirming the exact account id in D1. Do not guess user ids or run destructive SQL.
