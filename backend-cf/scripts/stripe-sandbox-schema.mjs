import assert from 'node:assert/strict';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

assert.equal(process.env.GITHUB_ACTIONS, 'true');
const directory = join(process.env.RUNNER_TEMP, 'captro-sandbox/supabase/migrations');
const files = await readdir(directory);
assert.equal(files.length, 1);
assert.ok(files[0].endsWith('_deployed_schema_and_native_payments.sql'));
const schema = await readFile(join(process.env.RUNNER_TEMP, 'captro-schema.sql'), 'utf8');
assert.ok(schema.includes('app_purchases') && schema.includes('app_connected_accounts'));
assert.ok(!/^COPY /m.test(schema), 'Never copy production data into the payment sandbox');
assert.ok(!schema.includes('CREATE TABLE "public"."app_payment_environment"'),
  'Production baseline changed: review which payment migrations are still pending');
const pendingMigrations = await Promise.all([
  readFile(new URL('../../supabase/migrations/20260904231905_stripe_native_payments.sql', import.meta.url), 'utf8'),
  readFile(new URL('../../supabase/migrations/20260905205251_configure_stripe_payment_environment.sql', import.meta.url), 'utf8'),
]);
// Historical migrations omit the original baseline. Use the actual deployed DDL,
// without rows, and apply the pending migrations to that empty isolated database.
await writeFile(join(directory, files[0]), `${schema}\n${pendingMigrations.join('\n')}`);
console.log('Prepared schema-only snapshot plus pending native-payment migrations. No production rows copied.');
