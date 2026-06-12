# Supabase Primary Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Captro's production app data source from Cloudflare D1/KV to Supabase Auth and Supabase Postgres while keeping Cloudflare as the media, Worker, security, upload-signing, and optional rate-limit/cache layer.

**Architecture:** Supabase Auth becomes the only login/session identity source, and Supabase Postgres stores profiles, posts, interactions, comments, stories, chat, reports, moderation, notifications, and deletion state. The Cloudflare Worker remains the trusted backend edge layer that verifies Supabase JWTs, validates requests, signs Cloudflare Images/Stream uploads, writes privileged metadata to Supabase through a service-role key, and enforces rate limits. D1 remains bound only during migration, then is removed after every runtime app-data route no longer depends on it.

**Tech Stack:** Cloudflare Workers + Hono + TypeScript, Supabase Auth/Postgres/RLS, Cloudflare Images, Cloudflare Stream, optional Cloudflare KV for temporary rate limits/cache, native iOS Swift app.

## Current Dependency Map

- `backend-cf/src/index.ts` contains over 1,000 D1/KV references and still performs app-data reads/writes through `c.env.DB.prepare(...)`.
- `backend-cf/wrangler.toml` still binds `DB` and `KV` for both development and production.
- `.github/workflows/deploy-worker.yml` pushes Supabase migrations, then still applies D1 migrations `0019`, `0020`, `0021`, `0022`, `0023`, `0024`, `0025`, `0026`, `0029`, and `0030`.
- `backend-cf/package.json` still exposes D1 migration scripts.
- `supabase/migrations/202606080001_captro_core.sql` and `202606080002_captro_operational.sql` create most canonical Supabase tables, but RLS policies are not yet fully defined.
- `ios_native/MIRA` still uses the Worker API for most app data and should move toward Supabase Auth for identity plus Worker-mediated upload/security flows.

## File Structure

- Modify `backend-cf/src/index.ts`: keep routes deployable while route groups are cut over; shrink direct D1 usage phase by phase.
- Create `backend-cf/src/supabaseClient.ts`: shared Supabase REST helper for service-role requests, JWT user lookup, and typed error mapping.
- Create `backend-cf/src/supabaseData.ts`: repository functions for app users, posts, interactions, comments, follows, stories, messages, reports, moderation, and notifications.
- Create `backend-cf/src/rateLimit.ts`: KV-backed temporary rate-limit helpers; D1 must not be used for rate limiting after cutover.
- Modify `backend-cf/wrangler.toml`: keep media, queue, AI, R2, and optional KV; remove D1 binding only after runtime D1 usage is zero.
- Modify `.github/workflows/deploy-worker.yml`: remove D1 migration steps after all runtime D1 routes are replaced.
- Modify `backend-cf/package.json`: replace D1 migration scripts with Supabase migration/documented commands after runtime D1 removal.
- Create `supabase/migrations/<new>_captro_rls_policies.sql`: RLS policies for user-owned data, public read surfaces, private messages, reports, admin roles, and moderation.
- Modify `ios_native/MIRA/Sources/MIRANative/Services/MIRAAuthSession.swift`: Supabase Auth session is the user identity source.
- Modify `ios_native/MIRA/Sources/MIRANative/Services/MIRAAPIClient.swift`: use Supabase access token for protected Worker calls and remove old custom session dependence.
- Modify `ios_native/MIRA/Sources/MIRANative/Services/MIRAMediaUploadService.swift`: request Cloudflare upload intents from the Worker and read/write metadata through approved Supabase-backed endpoints.
- Create `SUPABASE_PRIMARY_MIGRATION_AUDIT.md`: human-readable D1/KV dependency audit and cutover status.

## Tasks

1. Write the migration audit.
2. Add shared Supabase service helpers.
3. Replace custom auth acceptance with Supabase JWT acceptance.
4. Harden Supabase schema and RLS.
5. Move core engagement routes to Supabase only.
6. Move post, comment, feed, Discover, and profile routes.
7. Move stories, chat, notifications, reports, moderation, and admin routes.
8. Remove D1 from runtime and deploy config after usage reaches zero.
9. Cut the iOS app over to Supabase Auth plus Worker-mediated media upload.
10. Replace D1 reset with guarded Supabase reset and Cloudflare media cleanup after backup.

## Removal Gate

D1 bindings and D1 migration deploy steps must stay until this command has no app-runtime/deploy dependency:

```powershell
rg "c\.env\.DB|D1Database|wrangler d1|d1_databases" backend-cf .github scripts
```

KV can remain only for temporary rate limits/cache. It must not store users, posts, likes, saves, comments, messages, reports, or moderation records.

## Verification

Each phase must pass:

```powershell
npx.cmd tsc --noEmit
git diff --check
```

The iOS release build must be verified through the existing GitHub Actions/TestFlight workflow because this Windows machine does not have Xcode/Swift installed.

## Execution Note

This migration must stay incremental. D1 bindings and deploy migrations should not be removed until route groups have been moved and verified, or the production Worker can lose required tables mid-deploy.
