# Captro Production Data Reset

This folder contains protected reset tooling for clearing test/demo/user-generated production data before App Store review or public launch.

It must not delete infrastructure:

- Keep Supabase projects, schemas, migrations, and required configuration.
- Keep Cloudflare Worker, queues, buckets, Images account, Stream account, KV, and R2 infrastructure.
- Delete only data and uploaded media after backup and confirmation.

## Production Data Source

Supabase Postgres is the source of truth for Captro app data. Cloudflare cleanup uses Supabase `app_media_assets` records to find Cloudflare Images and Stream assets that belong to reset data.

Legacy D1 cleanup is optional and must be explicitly enabled only for old compatibility data. Do not use D1 as the app database for new production data.

## Safe Order

1. Put the app/API in a quiet release window.
2. Back up Supabase Postgres from the Supabase dashboard or CLI. The GitHub execute workflow also creates a short-retention pre-reset backup artifact before deleting data.
3. Run `supabase-production-reset.sql` with `app.reset_mode = 'dry_run'`.
4. Review row counts.
5. Run Cloudflare media cleanup in dry-run mode from Supabase media records.
6. Confirm the exact project/account and keep-list.
7. Run Supabase reset with `app.reset_mode = 'execute'`.
8. Run Cloudflare media cleanup with `EXECUTE_DELETE=true`.
9. Run legacy D1 reset only if old compatibility data still exists and you explicitly choose to clear it.
10. Deploy the Worker and upload a fresh TestFlight build.
11. Smoke test login, upload, feed, Discover, report/block, delete account, and legal links.

## Supabase Dry Run

Use the Supabase SQL editor or psql against the production project:

```sql
set app.reset_environment = 'production';
set app.confirm_production_reset = 'CONFIRM_PRODUCTION_RESET';
set app.reset_mode = 'dry_run';
set app.keep_emails = 'karfalacisse900@gmail.com,reviewer@example.com';
\i scripts/production-reset/supabase-production-reset.sql
```

## Supabase Execute

Only after backup:

```sql
set app.reset_environment = 'production';
set app.confirm_production_reset = 'CONFIRM_PRODUCTION_RESET';
set app.reset_mode = 'execute';
set app.keep_emails = 'karfalacisse900@gmail.com,reviewer@example.com';
\i scripts/production-reset/supabase-production-reset.sql
```

If using the Supabase dashboard SQL editor, paste the file contents after the `set` statements.

## Cloudflare Media Dry Run

```powershell
$env:SUPABASE_URL="https://cclgvxukwccvtgrbcwie.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"
$env:CLOUDFLARE_ACCOUNT_ID="<account-id>"
$env:CLOUDFLARE_API_TOKEN="<api-token>"
node scripts/production-reset/cloudflare-media-cleanup.mjs
```

To include legacy D1 media rows during a one-time compatibility cleanup:

```powershell
cd backend-cf
npx.cmd wrangler d1 execute DB --env production --remote --json --command "SELECT id, media_type, storage_provider, storage_key, public_url FROM media_assets;" > ..\legacy-d1-media-assets.json
cd ..
$env:CLOUDFLARE_MEDIA_ASSETS_FILE="legacy-d1-media-assets.json"
node scripts/production-reset/cloudflare-media-cleanup.mjs
```

## Cloudflare Media Execute

```powershell
$env:EXECUTE_DELETE="true"
$env:CONFIRM_PRODUCTION_RESET="CONFIRM_PRODUCTION_RESET"
node scripts/production-reset/cloudflare-media-cleanup.mjs
```

R2 objects may require manual deletion or a dedicated R2 S3 credential flow if media rows use `storage_provider = r2`.

## Legacy D1 Reset

Run only if D1 still contains old test data that the Worker can serve:

```powershell
cd backend-cf
npx.cmd wrangler d1 execute DB --env production --remote --yes --file=../scripts/production-reset/d1-legacy-data-reset.sql
```

## Do Not Run Until

- Supabase backup exists or the protected GitHub execute workflow successfully created its pre-reset backup artifact.
- GitHub production deploy secrets are set.
- Worker deploy is green.
- You know which admin/reviewer accounts must be preserved.
- Cloudflare media dry-run output looks correct.
