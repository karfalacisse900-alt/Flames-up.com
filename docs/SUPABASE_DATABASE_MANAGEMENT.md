# Captro Supabase Database Management

Captro does not use the Supabase Table Editor as the source of truth for production schema. The source of truth is this repository:

- SQL migrations: `supabase/migrations/*.sql`
- Migration workflow: `.github/workflows/supabase-postgres-migrations.yml`
- Schema docs: `docs/SUPABASE_SCHEMA_REPORT.md`
- ERD: `docs/SUPABASE_ERD.md`

Supabase is Captro's production authentication and app database layer. Cloudflare remains the media/security layer: Workers, Images, Stream, WAF, and optional temporary rate-limit/cache KV only.

## Rules

1. Every schema change must be a SQL migration committed to GitHub.
2. Do not make production schema changes in Table Editor, except emergency repair.
3. If an emergency Table Editor change is unavoidable, immediately pull/encode the same change into a migration and commit it.
4. Do not put Supabase `service_role` keys in the iOS app, admin web bundle, screenshots, logs, or docs.
5. iOS uses Supabase Auth/publishable auth only. Privileged writes go through the Cloudflare Worker.
6. RLS stays enabled on every public table.
7. Admin/moderation tables are accessed through backend admin APIs, not public frontend trust.
8. Large images/videos never go in Postgres. Postgres stores metadata and Cloudflare media identifiers/URLs.

## Local Workflow

Install or run the Supabase CLI through `npx`:

```powershell
npx.cmd supabase --version
```

Create a migration:

```powershell
npx.cmd supabase migration new short_descriptive_name
```

If the CLI cannot create a file on Windows because of local path handling, create a timestamped SQL file under `supabase/migrations` and record the issue in the pull request. Do not apply schema changes directly to production to work around a local CLI issue.

Review pending migrations:

```powershell
npx.cmd supabase migration list
```

Apply migrations through GitHub Actions for production. Local `db push` should be used only when intentionally linked to the correct project/environment.

## GitHub Production Workflow

Run:

```text
Supabase Postgres Migrations
```

Required repository secrets:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF`

The workflow requires this manual input:

```text
MIGRATE_SUPABASE_PRODUCTION
```

It then:

1. Checks required secrets.
2. Installs Supabase CLI.
3. Links the project.
4. Shows migration status.
5. Runs `supabase db push`.
6. Shows migration status again.

## Canonical Table Map

| Product area | Canonical Supabase table(s) |
| --- | --- |
| Profiles/users | `app_users`, `app_account_identities` |
| Posts | `app_posts` |
| Post media metadata | `app_media_assets` |
| Comments | `post_comments`, `post_comment_likes` |
| Likes/saves/bookmarks | `app_post_interactions` |
| Follows/friends | `app_follows`, `app_friend_requests`, `app_friendships` |
| Blocks | `app_blocks` |
| Stories | `app_stories`, `app_story_likes`, `app_story_views`, `app_story_thoughts` |
| Direct messages | `app_messages` |
| Group messages | `app_group_chats`, `app_group_chat_members`, `app_group_messages` |
| Notifications | `app_notifications`, `app_push_tokens` |
| Reports | `app_reports` |
| Moderation | `app_moderation_jobs`, `app_moderation_results`, `app_moderation_events`, `app_moderation_actions` |
| Admin/audit | `app_admin_roles`, `app_audit_logs` |
| Account deletion safety | `app_deleted_account_safety_records` |

Legacy compatibility tables may exist during cutover:

- `profiles`
- `follows`
- `post_interactions`

Do not add new app logic to legacy compatibility tables unless a migration explicitly documents why.

## RLS Policy Pattern

Public tables must have RLS enabled. Policies should follow the actual access model:

- Users can read public/allowed content only.
- Users can insert/update/delete only their own rows.
- Messages are visible only to participants.
- Blocks hide feed, discover, comments, profiles, and messages.
- Reports are visible to reporters and admin/moderation roles only.
- Moderation/admin/audit tables deny normal users and rely on backend admin APIs.

Do not use user-editable `raw_user_meta_data` for authorization decisions. Authorization data belongs in server-owned database rows or Supabase app metadata.

## Index Pattern

Indexes should match product queries:

- Feed: active/public posts by `created_at`.
- Discover: category/status/created pagination and lightweight media metadata.
- Profile: user posts by `app_user_id` or `user_id`, status, created time.
- Comments: `post_id`, `created_at`.
- Likes/saves: one canonical actor/post/kind key.
- Messages: conversation/user pair + created time.
- Notifications: recipient + unread/created time.
- Reports/moderation: status/priority, target, reporter.

Do not drop "unused index" advisor findings automatically on a young production app. First confirm traffic patterns and query plans.

## Production Change Checklist

Before merging a database change:

- Migration file exists under `supabase/migrations`.
- Migration is idempotent where practical.
- New public tables have RLS enabled.
- New public tables have explicit policies.
- Foreign keys and delete behavior are intentional.
- Common queries have indexes.
- No media binaries are stored in Postgres.
- No service-role secret is exposed to iOS/admin web.
- Supabase advisors have been reviewed.
- Backend Worker still verifies Supabase JWT for privileged uploads/actions.

Before running production migrations:

- Confirm target project ref.
- Confirm backup/restore posture for risky changes.
- Run the GitHub workflow with the required confirmation phrase.
- Verify migration status after push.
- Smoke test signup/login/feed/profile/post/like/save/comment/report.
