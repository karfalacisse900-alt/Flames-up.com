# Captro Site DNS Setup

Use these records after the Cloudflare Pages project for the public site exists.

## Public site

- Project name: `captro-site`
- Pages default hostname: `<your-project>.pages.dev`
- Custom domain: `captro.app`

## DNS records

### Root site

- Type: `CNAME`
- Name: `@`
- Target: `captro-site.pages.dev`
- Proxy status: `Proxied`

If Cloudflare Pages asks to manage the root domain directly, let Pages create the apex binding automatically.

### WWW

- Type: `CNAME`
- Name: `www`
- Target: `captro.app`
- Proxy status: `Proxied`

### Admin

- Type: `CNAME`
- Name: `admin`
- Target: `captro-admin.pages.dev`
- Proxy status: `Proxied`

### API

Configure `api.captro.app` as a Worker custom domain in Cloudflare Workers. That is safer than hand-guessing the final Worker hostname.

## Required live URLs

These should open in the browser before using them in App Store Connect:

- `https://captro.app`
- `https://captro.app/legal/privacy`
- `https://captro.app/privacy-choices`
- `https://captro.app/legal/terms`
- `https://captro.app/legal/community-guidelines`
- `https://captro.app/legal/safety`
- `https://captro.app/support`

## App Store Connect values

- Support URL: `https://captro.app`
- Marketing URL: `https://captro.app`
- Privacy Policy URL: `https://captro.app/legal/privacy`
- User Privacy Choices URL: `https://captro.app/privacy-choices`
