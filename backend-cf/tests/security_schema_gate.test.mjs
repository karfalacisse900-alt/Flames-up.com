import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { securitySchemaSQL, securityCheckIDs, validateSecuritySchema, verifySecuritySchema } from '../../scripts/app-store/verify-security-schema.mjs';

const good = () => securityCheckIDs.map(check_id => ({ check_id, passed: true }));
test('schema evidence must be complete, unique, boolean, and entirely passed', () => {
  assert.equal(validateSecuritySchema(good()), 14);
  for (const rows of [[], {}, null, good().slice(1), [...good(), good()[0]],
    good().map((row, i) => i ? row : { ...row, passed: 'true' }),
    good().map((row, i) => i ? row : { ...row, check_id: 'unknown' }),
    good().map((row, i) => i ? row : { ...row, passed: false })])
    assert.throws(() => validateSecuritySchema(rows));
});

const env = { SUPABASE_PROJECT_REF: 'a'.repeat(20), SUPABASE_ACCESS_TOKEN: 'fixture-secret-do-not-log' };
test('management request is bounded, read-only, catalog-only, and never follows redirects', async () => {
  let calls = 0;
  assert.equal(await verifySecuritySchema(env, async (url, options) => {
    calls++;
    assert.equal(url, `https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}/database/query`);
    assert.equal(options.method, 'POST');
    assert.equal(options.redirect, 'error');
    assert.ok(options.signal instanceof AbortSignal);
    const body = JSON.parse(options.body);
    assert.equal(body.read_only, true);
    assert.equal(body.query, securitySchemaSQL);
    assert.doesNotMatch(body.query, /\b(?:insert|update|delete|alter|create|drop|revoke|grant)\s+(?:table|into|from|on)\b/i);
    return Response.json(good());
  }), 14);
  assert.equal(calls, 1);
});
test('missing credentials, network failures, and malformed results fail closed without secret output', async () => {
  await assert.rejects(verifySecuritySchema({}, () => assert.fail('network not allowed')), /required/);
  for (const request of [
    async () => { throw Error(env.SUPABASE_ACCESS_TOKEN); },
    async () => new Response(env.SUPABASE_ACCESS_TOKEN, { status: 403 }),
    async () => new Response(env.SUPABASE_ACCESS_TOKEN),
    async () => Response.json([]),
    async () => Response.json([{ check_id: env.SUPABASE_ACCESS_TOKEN, passed: true }]),
  ]) {
    await assert.rejects(verifySecuritySchema(env, request), error => {
      assert.ok(!error.message.includes(env.SUPABASE_ACCESS_TOKEN)); return true;
    });
  }
});

test('actual SQL rejects pre-hardening schema and later privilege, RLS, policy, RPC, index, or migration drift', async () => {
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create schema private; create schema supabase_migrations;
      create table supabase_migrations.schema_migrations(version text primary key);
      grant usage on schema public, private, auth to authenticated, service_role;
      create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
      create table app_users(id text primary key, supabase_user_id uuid, metadata jsonb default '{}');
      create table app_admin_roles(user_id text primary key, role text);
      create table app_posts(id text); create table post_comments(id text);
      create table app_messages(id text, sender_id text, receiver_id text, body text);
      create table app_group_chats(id text, created_by text);
      create table app_group_chat_members(id text, group_id text, user_id text, role text);
      create table app_group_messages(id text, group_id text, sender_id text, body text);
      create table app_media_assets(id text, user_id text, moderation_status text, upload_status text, metadata jsonb);
      create table app_push_tokens(id text primary key, user_id text, token_hash text, token text,
        device_id text, bundle_id text, environment text, platform text, is_active boolean,
        last_seen_at timestamptz, updated_at timestamptz, unique(user_id, token_hash));
      create table app_purchases(id text); create table app_payments(id text);
      create table app_entitlements(id text); create table app_payment_webhook_events(id text);
      grant all on all tables in schema public to anon, authenticated, service_role;
      revoke all on app_purchases, app_payments, app_entitlements, app_payment_webhook_events from anon, authenticated;
    `);
    for (const table of ['app_users', 'app_posts', 'post_comments', 'app_messages', 'app_group_chats',
      'app_group_chat_members', 'app_group_messages', 'app_media_assets', 'app_push_tokens',
      'app_admin_roles', 'app_purchases', 'app_payments', 'app_entitlements', 'app_payment_webhook_events'])
      await db.exec(`alter table ${table} enable row level security`);
    const check = async () => (await db.query(securitySchemaSQL)).rows;
    const before = await check();
    assert.throws(() => validateSecuritySchema(before), /migration_20261006012846/);
    assert.equal(before.find(row => row.check_id === 'client_writes_denied').passed, false);
    for (const filename of ['20261006012846_security_backend_write_boundary.sql',
      '20261013154326_security_media_approval_boundary.sql', '20261013154328_single_owner_push_registration.sql']) {
      await db.exec(readFileSync(new URL(`../../supabase/migrations/${filename}`, import.meta.url), 'utf8'));
      await db.query('insert into supabase_migrations.schema_migrations(version) values ($1)', [filename.split('_')[0]]);
    }
    validateSecuritySchema(await check());
    // Actual disposable-role requests, not only catalog assertions. No customer rows.
    await db.exec(`create or replace function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
      insert into app_users values ('a','00000000-0000-4000-8000-000000000001','{}'),
        ('b','00000000-0000-4000-8000-000000000002','{}'),('c','00000000-0000-4000-8000-000000000003','{}');
      insert into app_group_chats values('private-group','a');
      insert into app_group_chat_members values('m1','private-group','a','owner'),('m2','private-group','b','member');
      insert into app_group_messages values('g1','private-group','a','fixture-only');
      insert into app_messages values('d1','a','b','fixture-only');
      insert into app_media_assets values('asset-a','a','pending','pending','{}');`);
    for(const [uid,expected] of [['00000000-0000-4000-8000-000000000001',1],['00000000-0000-4000-8000-000000000002',1],['00000000-0000-4000-8000-000000000003',0]]) {
      await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);await db.exec('set role authenticated');
      assert.equal((await db.query('select * from app_group_messages')).rows.length,expected);
      for(const query of ["select metadata from app_users where id='b'","update app_users set metadata='{\"status\":\"active\"}' where id='a'",
        "update app_messages set body='forged' where id='d1'","update app_media_assets set moderation_status='approved' where id='asset-a'",
        "insert into app_group_chat_members values('intruder','private-group','c','member')",
        "select captro_register_push_token('c','x','hash','fixture','device','bundle','sandbox')"])
        await assert.rejects(db.exec(query),/permission denied/);
      await db.exec('reset role');
    }
    await db.exec("update app_users set metadata='{\"status\":\"banned\"}' where id='a'");
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",['00000000-0000-4000-8000-000000000001']);
    await db.exec('set role authenticated');assert.equal((await db.query('select * from app_group_messages')).rows.length,0);await db.exec('reset role');
    await db.exec("set role service_role; select captro_register_push_token('a','push-a','same-device','fixture-only','device','bundle','sandbox'); select captro_register_push_token('b','push-b','same-device','fixture-only','device','bundle','sandbox'); reset role;");
    assert.deepEqual((await db.query('select user_id from app_push_tokens where is_active')).rows.map(x=>x.user_id),['b']);
    // Every mutation below affects only this disposable in-memory database.
    for (const [mutation, checkID] of [
      ['grant update (metadata) on app_users to authenticated', 'client_writes_denied'],
      ['grant select (metadata) on app_users to public', 'private_columns_unreadable'],
      ['grant update (moderation_status) on app_media_assets to authenticated', 'client_writes_denied'],
      ['grant truncate on app_messages to anon', 'client_ddl_privileges_denied'],
      ['alter table app_media_assets disable row level security', 'required_rls_enabled'],
      ['create policy bypass on app_group_messages for select to authenticated using (true)', 'group_select_policies'],
      ['grant execute on function captro_register_push_token(text,text,text,text,text,text,text) to public', 'push_rpc_service_only'],
      ['drop function captro_register_push_token(text,text,text,text,text,text,text)', 'push_rpc_service_only'],
      ['drop index app_push_tokens_one_active_owner', 'push_unique_active_owner'],
      ['grant select on app_payments to authenticated', 'payment_tables_server_only'],
      ["delete from supabase_migrations.schema_migrations where version='20261013154326'", 'migration_20261013154326'],
      ["create or replace function private.captro_current_app_user_id() returns text language sql stable security definer set search_path='' as $$select u.id from public.app_users u where u.supabase_user_id=auth.uid() limit 1$$", 'identity_helper_active_only'],
    ]) {
      await db.exec('begin');
      try {
        await db.exec(mutation);
        const result = await check();
        assert.equal(result.find(row => row.check_id === checkID).passed, false, mutation);
        assert.throws(() => validateSecuritySchema(result));
      } finally { await db.exec('rollback'); }
      validateSecuritySchema(await check());
    }
  } finally { await db.close(); }
});

test('fresh and preserved TestFlight uploads both require the live schema check; status reads do not', () => {
  const workflow = readFileSync(new URL('../../.github/workflows/native-ios-testflight.yml', import.meta.url), 'utf8');
  const retry = workflow.slice(workflow.indexOf('  retry-upload:'), workflow.indexOf('  build-testflight:'));
  const build = workflow.slice(workflow.indexOf('  build-testflight:'), workflow.indexOf('  home-feed-visual-qa:'));
  for (const job of [retry, build]) {
    const gate = job.indexOf('node scripts/app-store/verify-security-schema.mjs');
    assert.ok(gate >= 0 && gate < job.indexOf('--upload-app'));
    assert.match(job, /SUPABASE_ACCESS_TOKEN: \$\{\{ secrets\.SUPABASE_ACCESS_TOKEN \}\}/);
    assert.doesNotMatch(job.slice(0, job.indexOf('--upload-app')), /continue-on-error: true/);
  }
  assert.doesNotMatch(workflow.slice(workflow.indexOf('  testflight-status:'), workflow.indexOf('  retry-upload:')), /verify-security-schema/);
});
