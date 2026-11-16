import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import {
  releaseMigrations, releaseCheckIDs, releaseSchemaSQL, validateReleaseSchema, verifyReleaseSchema,
} from '../../scripts/app-store/verify-professional-release-schema.mjs';

test('catalog gate rejects the actual missing-migration shape and incomplete evidence', async t => {
  const db = new PGlite(); t.after(() => db.close());
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create schema supabase_migrations; create table supabase_migrations.schema_migrations(version text);`);
  const rows = (await db.query(releaseSchemaSQL)).rows;
  assert.equal(rows.length, releaseCheckIDs.length);
  assert.ok(rows.every(row => row.passed === false));
  assert.throws(() => validateReleaseSchema(rows), /TestFlight backend rollout required/);
  assert.throws(() => validateReleaseSchema([]), /incomplete/);
  const green = releaseCheckIDs.map(check_id => ({ check_id, passed: true }));
  assert.equal(validateReleaseSchema(green), releaseCheckIDs.length);
  assert.throws(() => validateReleaseSchema([...green.slice(1), green[1]]), /malformed/);
});

test('catalog gate detects privilege, RLS, RPC and immutable-audit regressions', async t => {
  const db = new PGlite(); t.after(() => db.close());
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create schema supabase_migrations; create table supabase_migrations.schema_migrations(version text);`);
  for (const version of releaseMigrations) await db.query('insert into supabase_migrations.schema_migrations values($1)', [version]);
  for (const id of releaseCheckIDs.filter(v => v.startsWith('table:'))) {
    const table = id.slice(6);
    await db.exec(`create table ${table}(id text); alter table ${table} enable row level security;
      grant select,insert on ${table} to service_role;`);
  }
  await db.exec('create table app_tea_replies(id text); create table app_group_messages(id text);');
  for (const id of releaseCheckIDs.filter(v => v.startsWith('column:'))) {
    const [table, column] = id.slice(7).split('.');
    await db.exec(`alter table ${table} add column ${column} text;`);
  }
  for (const id of releaseCheckIDs.filter(v => v.startsWith('function:'))) {
    const signature = id.slice(9);
    await db.exec(`create function ${signature} returns boolean language sql security invoker as 'select true';
      revoke all on function ${signature} from public; grant execute on function ${signature} to service_role;`);
  }
  const read = async () => (await db.query(releaseSchemaSQL)).rows;
  assert.equal(validateReleaseSchema(await read()), releaseCheckIDs.length);
  for (const [change, undo, failed] of [
    ['grant select on app_studio_sessions to authenticated', 'revoke select on app_studio_sessions from authenticated', 'table:app_studio_sessions'],
    ['alter table app_professional_roles disable row level security', 'alter table app_professional_roles enable row level security', 'table:app_professional_roles'],
    ['grant update on app_professional_audit to service_role', 'revoke update on app_professional_audit from service_role', 'audit:immutable'],
    ['grant execute on function captro_professional_active(text,text) to public', 'revoke execute on function captro_professional_active(text,text) from public', 'function:captro_professional_active(text,text)'],
  ]) {
    await db.exec(change);
    const rows = await read();
    assert.equal(rows.find(row => row.check_id === failed).passed, false);
    assert.throws(() => validateReleaseSchema(rows), /rollout required/);
    await db.exec(undo);
  }
  await db.exec('drop function captro_studio_session(text,text,text,text)');
  const missing = await read();
  assert.equal(missing.find(row => row.check_id.startsWith('function:captro_studio_session')).passed, false);
  assert.throws(() => validateReleaseSchema(missing), /rollout required/);
});

test('release inspection is read-only, bounded and fails closed without exposing provider data', async () => {
  const env = { SUPABASE_PROJECT_REF: 'cclgvxukwccvtgrbcwie', SUPABASE_ACCESS_TOKEN: 'fixture' };
  const green = releaseCheckIDs.map(check_id => ({ check_id, passed: true }));
  assert.equal(await verifyReleaseSchema(env, async (url, options) => {
    assert.equal(new URL(url).hostname, 'api.supabase.com');
    assert.equal(JSON.parse(options.body).read_only, true);
    assert.ok(options.signal); assert.equal(options.redirect, 'error');
    return new Response(JSON.stringify(green));
  }), releaseCheckIDs.length);
  await assert.rejects(verifyReleaseSchema(env, async () => { throw Error('PRIVATE PROVIDER DATA'); }), /inspection unavailable/);
  await assert.rejects(verifyReleaseSchema(env, async () => new Response('PRIVATE PROVIDER DATA', { status: 503 })), /HTTP 503/);
  await assert.rejects(verifyReleaseSchema(env, async () => new Response('invalid')), /Invalid backend/);
});

test('fresh and retry TestFlight uploads both require the new backend schema', () => {
  const workflow = readFileSync(new URL('../../.github/workflows/native-ios-testflight.yml', import.meta.url), 'utf8');
  const retry = workflow.slice(workflow.indexOf('  retry-upload:'), workflow.indexOf('  build-testflight:'));
  const build = workflow.slice(workflow.indexOf('  build-testflight:'), workflow.indexOf('  home-feed-visual-qa:'));
  for (const job of [retry, build]) {
    const gate = job.indexOf('node scripts/app-store/verify-professional-release-schema.mjs');
    assert.ok(gate >= 0 && gate < job.indexOf('--upload-app'));
  }
});
