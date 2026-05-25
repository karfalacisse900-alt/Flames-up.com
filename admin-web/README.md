# Captro Admin Web

Private moderation dashboard for Captro staff. This is a separate web app from the iOS app and should be deployed as an admin-only Cloudflare Pages project.

## Security Model

- No public signup exists in this app.
- The frontend never decides admin access by itself.
- Every admin request calls the production Worker API and the Worker enforces role-based permissions.
- Recommended extra gate: protect the Pages project with Cloudflare Access for owner/admin/moderator emails.
- Do not put database credentials, Cloudflare API tokens, Apple keys, push keys, or service secrets in this app.

## Roles

Backend roles are enforced by `/api/admin/me` and each `/api/admin/*` endpoint:

- `owner`
- `admin`
- `moderator`
- `support`
- `viewer`

Existing `users.is_admin = 1` accounts are treated as `admin`. Owner usernames configured by the Worker `OWNER_USERNAMES` secret are treated as `owner`. The `admin_roles` table supports explicit roles.

## Local Development

```bash
npm install
npm run dev
```

Use `env.example` as the template. Create `.env.local` only if you need a different API target:

```bash
VITE_CAPTRO_API_BASE=https://api.flames-up.com/api
```

Production CORS should only allow trusted Captro domains such as `https://admin.flames-up.com`.

## Build

```bash
npm run build
```

The output in `dist/` can be deployed to Cloudflare Pages.

## Cloudflare Pages

Suggested settings:

- Framework preset: Vite
- Build command: `npm run build`
- Build output directory: `dist`
- Environment variable: `VITE_CAPTRO_API_BASE=https://api.flames-up.com/api`
- Access policy: require approved Captro admin/moderator identity

Security headers live in `public/_headers`; SPA routing lives in `public/_redirects`.
