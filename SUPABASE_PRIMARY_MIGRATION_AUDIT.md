# Supabase Primary Migration Audit

Captro's target production architecture is:

- Supabase Auth: the only source of truth for login, signup, identity, and sessions.
- Supabase Postgres: the only main app database for users, profiles, posts, comments, likes, saves, follows, stories, messages, notifications, reports, moderation, admin roles, and account deletion records.
- Cloudflare Worker: trusted API/security layer for request validation, Supabase JWT verification, upload signing, rate limiting, media moderation, response shaping, and hiding service-role/API secrets from the iOS app.
- Cloudflare Images: photo storage, resizing, optimization, and delivery.
- Cloudflare Stream: video upload, processing, playback, and delivery.
- Cloudflare KV: temporary rate limiting or cache only.
- Cloudflare D1: legacy compatibility during migration only; not the production source of truth.

## Current State

The repository is already halfway through the migration:

- `backend-cf/README.md` says Supabase Postgres is canonical.
- `backend-cf/wrangler.toml` sets `DATABASE_PRIMARY = "supabase_postgres"`.
- `.github/workflows/deploy-worker.yml` pushes Supabase migrations before deploying the Worker.
- Supabase migrations create app tables for users, posts, interactions, follows, comments, messages, stories/statuses, media assets, reports, moderation, admin roles, audit logs, push tokens, and account identities.
- Production Supabase now has explicit RLS policies for the main app tables and deny-by-default policies for admin/moderation/audit tables.
- Production Supabase migrations applied after this audit:
  - `20260612090211_captro_rls_policies`
  - `20260612091132_captro_rls_performance_indexes`

The runtime is not yet fully migrated:

- `backend-cf/src/index.ts` still contains the main D1 dependency surface.
- `backend-cf/wrangler.toml` still binds `DB` in development and production.
- `.github/workflows/deploy-worker.yml` still applies D1 migrations in production.
- `backend-cf/package.json` still exposes D1 migration commands.
- `.github/workflows/production-data-reset.yml` and `scripts/production-reset/*` still contain D1 reset/export logic.

## D1/KV Dependency Count

Command used:

```powershell
rg -c "c\.env\.DB|D1Database|c\.env\.KV|KVNamespace|wrangler d1|d1_databases|kv_namespaces" backend-cf .github supabase scripts
```

Results:

| File | Count |
| --- | ---: |
| `backend-cf/src/index.ts` | 1057 |
| `.github/workflows/deploy-worker.yml` | 10 |
| `backend-cf/README.md` | 8 |
| `backend-cf/package.json` | 5 |
| `backend-cf/wrangler.toml` | 4 |
| `.github/workflows/production-data-reset.yml` | 3 |
| `scripts/production-reset/README.md` | 2 |
| `backend-cf/migrations/0006_privacy_language.sql` | 2 |
| `backend-cf/migrations/0007_group_chats.sql` | 2 |
| `backend-cf/migrations/0008_governance_mobile.sql` | 2 |
| `backend-cf/migrations/0001_init.sql` | 1 |
| `scripts/production-reset/d1-legacy-data-reset.sql` | 1 |

## Runtime Route Groups Still To Cut Over

`backend-cf/src/index.ts` still exposes many route groups that need to use Supabase repositories instead of direct D1 statements:

- Auth/account: `/auth/*`, `/account/*`, `/users/me*`
- Profiles/users: `/users/:userId`, `/users/search/:query`, follow, block, username checks
- Posts/feed: `/posts`, `/posts/feed`, `/posts/:postId`, `/users/:userId/posts`
- Engagement: post likes, saves/bookmarks, comments, comment likes
- Stories/statuses: `/statuses`, likes, views, thoughts, delete
- Chat/messages: conversations, direct messages, group chats/messages, presence/typing
- Notifications: list, unread count, mark-read, device tokens
- Discover: `/discover`, `/discover/feed`, category filters, Discover likes
- Reports/moderation: `/reports`, `/admin/*`, moderation results, audit logs
- Media metadata: upload intents, media completion, media status
- Legacy/extra features: friends, recommendations, people, creators, publisher applications, places, music

## Supabase Schema Coverage

Current migrations create these key tables:

- `app_users`
- `app_posts`
- `post_comments`
- `app_post_interactions`
- `app_follows`
- `app_documents`
- `app_blocks`
- `app_notifications`
- `app_reports`
- `app_messages`
- `app_group_chats`
- `app_group_chat_members`
- `app_group_messages`
- `app_post_places`
- `app_media_assets`
- `app_moderation_results`
- `app_admin_roles`
- `app_moderation_actions`
- `app_audit_logs`
- `app_push_tokens`
- `app_account_identities`

RLS status:

- RLS is enabled across `public`.
- Policies are present for `app_users`, `app_posts`, `post_comments`, `app_post_interactions`, `app_follows`, `app_documents`, `app_blocks`, `app_notifications`, `app_reports`, `app_messages`, group chat tables, `app_post_places`, `app_media_assets`, `app_push_tokens`, and `app_account_identities`.
- Admin/moderation/audit tables have normal-user deny policies and must be accessed through backend admin routes.
- Supabase security advisor no longer reports missing RLS/policy findings. Remaining dashboard-level warnings are `citext` installed in `public` and leaked-password protection disabled.

## Cutover Rules

1. Do not remove the `DB` binding while any production route still calls `c.env.DB`.
2. Do not remove D1 migration workflow steps until runtime D1 dependency is zero.
3. Do not put the Supabase service-role key in iOS, admin-web, GitHub logs, or frontend build output.
4. Do not let the iOS app bypass moderation/upload validation by writing privileged media records directly.
5. Keep KV only for rate limits/cache; never for users, posts, likes, saves, comments, messages, reports, or moderation records.
6. Keep Cloudflare Images/Stream/Worker/WAF/security; only remove Cloudflare database responsibility.

## Removal Gate

D1 can be removed from production config only after this command has no app-runtime/deploy D1 dependency:

```powershell
rg "c\.env\.DB|D1Database|wrangler d1|d1_databases" backend-cf .github scripts
```

KV can remain only if the remaining references are rate-limit/cache-only and documented.

## Safe Migration Order

1. Add shared Supabase helpers and repositories.
2. Make auth middleware accept Supabase JWTs as the primary credential.
3. Move likes/saves/bookmarks first, because duplicate-like bugs are user-visible and already Supabase-canonical.
4. Move feed/discover/profile reads to Supabase so viewer state and counters come from one source. The engagement overlay now uses Supabase interaction rows for like/save viewer state and counts; D1 is best-effort cache only for this path.
5. Move posts/comments/stories/messages/notifications/reports/admin.
6. Add and test RLS policies.
7. Remove D1 migration steps from CI.
8. Remove D1 binding from `wrangler.toml`.
9. Replace D1 reset scripts with Supabase reset scripts.
10. Run production backup, dry-run reset, upload tests, App Store review build, then final guarded reset only after confirmation.

## Current Risk

The biggest risk is a split-brain data path: the Worker can write or read Supabase in some places while old D1 rows still influence response shaping in others. That is exactly how like/save state can appear reset after refresh and then allow count inflation. The migration must make each route group use one canonical source at a time, starting with engagement.
