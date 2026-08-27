# Captro Public Site

Static Cloudflare Pages site for:

- `https://captro.app`
- `https://captro.app/legal/privacy`
- `https://captro.app/privacy-choices`
- `https://captro.app/legal/terms`
- `https://captro.app/legal/community-guidelines`
- `https://captro.app/legal/safety`
- `https://captro.app/support`

## Deploy with Cloudflare Pages

Recommended Pages project name:

- `captro-site`

Recommended custom domains:

- `captro.app`
- `www.captro.app`

Recommended DNS:

- `captro.app` -> Cloudflare Pages custom domain
- `www.captro.app` -> redirect or alias to `captro.app`
- `admin.captro.app` -> admin Pages project
- `api.captro.app` -> Worker custom domain

## GitHub Actions

The workflow at `.github/workflows/captro-site-deploy.yml` deploys this folder to Cloudflare Pages.

Required GitHub secrets:

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`

## Local preview

Because this is a plain static site, you can preview it with any static file server.
