# Captro Supabase Schema Report

Generated from the connected production Supabase project on 2026-06-15.

## Executive Summary

Captro already has a migration-backed Supabase schema with RLS enabled across every public table inspected. The database is not a Table Editor-only setup: migrations exist in `supabase/migrations`, and production deployment can be run through GitHub Actions.

This pass adds:

- A guarded migration workflow input for production migrations.
- A non-destructive database governance migration.
- Migration-first database management documentation.
- A canonical schema map and ERD.

## Live Database Health Snapshot

| Check | Result |
| --- | ---: |
| Public tables inspected | 39 |
| Public tables with RLS enabled | 39 |
| RLS policies | 95 |
| Indexes | 150 |
| Primary keys | 39 |
| Foreign keys | 32 |
| Unique constraints | 11 |
| Check constraints | 18 |

## Canonical Tables Reviewed

| Required area | Captro table(s) | Status |
| --- | --- | --- |
| profiles/users | `app_users`, `profiles` compatibility | Present, RLS enabled |
| posts | `app_posts` | Present, RLS enabled |
| post media | `app_media_assets` | Present, RLS enabled |
| comments | `post_comments`, `post_comment_likes` | Present, RLS enabled |
| likes/saves | `app_post_interactions` | Present, RLS enabled |
| follows | `app_follows`, `follows` compatibility | Present, RLS enabled |
| stories | `app_stories`, `app_story_likes`, `app_story_views`, `app_story_thoughts` | Present, RLS enabled |
| messages | `app_messages`, `app_group_messages` | Present, RLS enabled |
| conversations | `app_group_chats`, `app_group_chat_members`; direct conversations represented by `app_messages.conversation_id` | Present, RLS enabled |
| notifications | `app_notifications`, `app_push_tokens` | Present, RLS enabled |
| reports | `app_reports` | Present, RLS enabled |
| blocks | `app_blocks` | Present, RLS enabled |
| moderation | `app_moderation_jobs`, `app_moderation_results`, `app_moderation_events`, `app_moderation_actions` | Present, RLS enabled |
| admin | `app_admin_roles`, `app_audit_logs` | Present, RLS enabled |
| account deletion/safety | `app_deleted_account_safety_records`, identity mappings in `app_account_identities` | Present, RLS enabled |

## Security Findings

### Strengths

- RLS is enabled on all 39 public tables inspected.
- User-owned tables have explicit policies for the expected command surfaces.
- Admin/moderation/audit tables are protected by restrictive policies and should be accessed through backend admin APIs.
- `app_post_interactions` has database uniqueness protections to prevent duplicate actor/post/kind rows.
- `app_blocks` has a unique blocker/blocked pair constraint.
- Message and group tables have RLS policies and indexes for participant/member access.
- The repo scan found service-role references only in backend/GitHub secret plumbing and docs, not hardcoded in iOS or admin web.

### Supabase Security Advisor

The connected project reports:

- Warning: leaked password protection is disabled.

Recommended action:

1. Open Supabase Dashboard.
2. Go to Authentication password/security settings.
3. Enable leaked password protection.
4. Keep this as a dashboard/auth configuration task, not an app code change.

Reference: [Supabase password security](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)

## Performance Findings

### Strengths

- Feed/profile/discover query surfaces have indexes on post status/category/user/created time.
- Interaction query surfaces have unique and lookup indexes for actor/post/kind and user/kind.
- Comments have post/created and user/created indexes.
- Stories have visible and user/created indexes.
- Messages have conversation/pair/created and unread indexes.
- Reports/moderation have status, target, media, and queue indexes.

### Supabase Performance Advisor

The connected project reports many `unused_index` informational findings. This is expected on young or recently migrated production apps and should not trigger automatic index deletion.

Recommended action:

1. Keep currently planned indexes through launch.
2. Recheck after real traffic.
3. Only drop indexes after confirming query plans, traffic, and write overhead.
4. Remove unused GIN/metadata indexes first if they remain unused after real production usage.

## Migration System Findings

### Present

- `supabase/migrations` contains committed SQL migrations.
- GitHub workflow `Supabase Postgres Migrations` installs Supabase CLI and runs `supabase db push`.
- Production Worker deploy workflow also pushes Supabase migrations before Worker deployment.
- Migration history in Supabase matches the repository through `20260615103000_supabase_primary_post_identity` before this pass.

### Added

- `supabase/migrations/20260615175500_database_governance_comments.sql`
- Guarded workflow input: `MIGRATE_SUPABASE_PRODUCTION`
- Migration status output before and after push.

### Local CLI Note

`npx supabase --version` works and reports Supabase CLI `2.106.0`. On this Windows path, `npx supabase migration new database_governance_comments` failed to create the file even though the target directory was writable. The migration was therefore created manually in the correct migration directory and should be applied through the GitHub workflow or a working Supabase CLI environment.

## Schema Issues Found

| Issue | Severity | Status |
| --- | --- | --- |
| Table Editor process was not documented as prohibited for production schema | Medium | Fixed in docs |
| Migration workflow could be triggered without a typed production confirmation | Medium | Fixed in workflow |
| Canonical versus legacy compatibility tables were not clearly labeled in schema docs | Medium | Fixed with migration comments and docs |
| Supabase leaked password protection disabled | Medium | Dashboard action required |
| Many unused-index info findings | Low | Documented; do not drop until real traffic confirms |

## Production Readiness Score

Database management workflow: 8.5 / 10

Reasons:

- Strong migration base exists.
- RLS coverage is complete across public tables inspected.
- Index/constraint coverage is broad.
- GitHub migration workflow exists and is now guarded.
- Remaining work is mostly process hardening and continued D1 runtime removal, not missing core schema.

Database security posture: 8 / 10

Reasons:

- RLS is enabled everywhere in `public`.
- Policies are broad and app-specific.
- Service role is not exposed in iOS/admin web from repo scan.
- Supabase Auth leaked password protection still needs to be enabled in the dashboard.

## Required Operating Rule Going Forward

No production schema change is complete unless it has:

1. A migration file in `supabase/migrations`.
2. Git commit history.
3. RLS review.
4. Index/constraint review.
5. Supabase advisor review.
6. GitHub workflow application or documented CLI application.

Supabase is the main database. Cloudflare is storage/security/API edge only.
