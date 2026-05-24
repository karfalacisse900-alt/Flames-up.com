# Flames-Up Security Operations Notes

## Third-party services in use

- Cloudflare Workers/D1/R2/Images/Stream: backend API, database, private media backup storage, image/video delivery. Server secrets must stay in Cloudflare Worker secrets.
- Supabase: authentication bridge and Postgres sync. The native app may use publishable/anon keys only; service-role keys are backend-only.
- Google OAuth: login identity. Client IDs can be public; OAuth secrets stay in provider/Supabase settings.
- Stripe: wallet coin and Premium checkout. Secret key and webhook secret are backend-only.
- Mapbox: place search/map display. Mobile clients should use only public-scoped tokens; backend proxy routes are preferred for higher-risk/location-heavy flows.
- Audius: public music discovery/stream metadata.
- Twilio Verify/SMS: optional phone verification. Account SID/auth token are backend-only.
- Agora: calls. App certificate is backend-only; the iOS app receives only short-lived generated call tokens.

No analytics/tracker SDK such as Sentry, Segment, Amplitude, Mixpanel, Firebase Analytics, or Meta Pixel was found in the active native app/backend source during this pass.

## Backup and export safety

- Media backups are stored in the Worker `MEDIA_BACKUP` R2 binding and are served through authenticated/visibility-checked API routes.
- Admin backup downloads use `private, no-store` response headers.
- Backups must never be placed in a public bucket.
- Database exports should be performed only by trusted operators from Cloudflare/Supabase dashboards or CLI sessions.
- Backup exports must exclude secrets: API keys, auth tokens, database passwords, JWT secrets, service-role keys, Stripe keys, webhook secrets, and OAuth secrets.
- Production recommendation: enable provider-level database backups and keep export files encrypted at rest in a private admin-only location.

## Production checklist

- Rotate any key that was pasted into chat, terminal logs, or screenshots.
- Set `ABUSE_SIGNAL_SECRET` as a Cloudflare Worker secret so ban-evasion signals are keyed hashes.
- Deploy with the explicit production environment and confirm `ENVIRONMENT=production`.
- Keep CORS production origins limited to `https://flames-up.com` and `https://www.flames-up.com`.
- Keep `.env` files out of git; mobile configuration values committed to the app must be safe to ship publicly.
- Run a database backup before applying new migrations or large admin cleanup jobs.
- Video metadata stripping is not complete in Workers; use a trusted media processing pipeline before public video delivery if location/device metadata is a concern.
