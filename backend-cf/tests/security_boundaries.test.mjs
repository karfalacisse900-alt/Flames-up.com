import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import { PGlite } from '@electric-sql/pglite';

// Execute the actual production functions/handlers with isolated storage. No
// network calls, real user records, credentials or production mutations.
const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const ast = ts.createSourceFile('index.ts', source, ts.ScriptTarget.Latest, true);
function fn(name) {
  const node = ast.statements.find(n => ts.isFunctionDeclaration(n) && n.name?.text === name);
  assert.ok(node, `active function ${name}`);
  return node.getText(ast);
}
function handler(method, path) {
  for (const n of ast.statements) {
    if (!ts.isExpressionStatement(n) || !ts.isCallExpression(n.expression)) continue;
    const call = n.expression;
    if (call.expression.getText(ast) === `api.${method}` && call.arguments[0]?.text === path)
      return `const handler = ${call.arguments.at(-1).getText(ast)};`;
  }
  throw new Error(`Missing active route ${path}`);
}
const clean = value => String(value ?? '').trim();
function run(code, bindings = {}, name = 'handler') {
  const js = ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText;
  return vm.runInNewContext(`${js}\n${name}`, {
    URL, Headers, Response, console: { warn() {}, error() {} },
    publicId: clean, cleanText: clean, cleanMultilineText: clean,
    postgrestEqFilter: v => `eq.${v}`, getErrorCode: () => 'TEST_FAILURE',
    ...bindings,
  });
}
const roles = ['viewer', 'support', 'moderator', 'admin', 'owner'];
const roleCode = fn('normalizeAdminRole') + fn('getAdminContext') + fn('requireOwnerOrAdmin');
function adminResolver(profile, assignments, extra = {}) {
  return run(roleCode, {
    ADMIN_ROLE_ORDER: roles, getUserId: () => 'alice',
    supabasePrimaryConfigured: () => true,
    getSupabaseAppUserRowByAnyId: async () => profile,
    supabaseAppUserToLegacyUser: row => ({ ...row, status: row.metadata?.status || 'active' }),
    isUuidText: () => 'alice-auth', postgrestInFilter: ids => ids,
    supabaseAdminQueryRows: async () => assignments,
    // These deliberately model malicious, previously trusted profile values.
    isOwnerUsername: () => true, isOwnerEmail: () => true, parseJsonObject: v => v,
    ...extra,
  }, 'getAdminContext');
}

test('forged profile admin flags and owner names/emails grant no privileges', async () => {
  for (const metadata of [{ admin_role: 'owner' }, { role: 'admin' }, { is_admin: true }, { is_admin: '1' }]) {
    assert.equal(await adminResolver({ id: 'alice', metadata }, [])({}), null);
  }
});
test('role lookup failure, foreign assignment, conflict and disabled account fail closed', async () => {
  const profile = { id: 'alice', metadata: { admin_role: 'owner' } };
  assert.equal(await adminResolver(profile, [], { supabaseAdminQueryRows: async () => { throw Error('offline'); } })({}), null);
  for (const assignments of [[{ user_id: 'mallory', role: 'owner' }],
    [{ user_id: 'alice', role: 'support' }, { user_id: 'alice-auth', role: 'owner' }]]) {
    assert.equal(await adminResolver(profile, assignments)({}), null);
  }
  for (const status of ['banned', 'suspended', 'deleted', 'deletion_pending'])
    assert.equal(await adminResolver({ id: 'alice', metadata: { status } }, [{ user_id: 'alice', role: 'owner' }])({}), null);
  assert.equal((await adminResolver(profile, [{ user_id: 'alice', role: 'support' }])({})).role, 'support');
});
test('legacy write routes check specific permissions before changing anything', async () => {
  for (const [path, required] of [['/admin/make-admin/:userId', 'roles:write'], ['/admin/remove-post/:postId', 'content:write']]) {
    const route = run(handler('post', path), { requireAdminRole: async (_, permission) => {
      assert.equal(permission, required); throw Error('FORBIDDEN');
    } });
    await assert.rejects(route({}), /FORBIDDEN/);
  }
});
test('reported-message review never fetches surrounding private conversation', async () => {
  const queries = [];
  const route = run(handler('get', '/admin/messages/reported/:reportId'), {
    requireAdminRole: async () => ({ userId: 'moderator' }),
    getAdminReportRow: async () => ({ message_id: 'reported' }), reportTargetType: () => 'message',
    supabasePrimaryConfigured: () => true,
    supabaseAdminQueryRows: async (c, table, query) => {
      queries.push(query); assert.equal(table, 'app_messages');
      assert.equal(query.filters.id, 'eq.reported'); assert.equal(query.limit, 1);
      return [{ id: 'reported', sender_id: 'alice', receiver_id: 'bob', body: 'Selected report only' }];
    },
    writeAdminAuditLog: async () => {}, adminReportDetail: async () => ({}),
    adminReportedMessageContextPayload: row => row,
    governanceError: (_, error) => { throw error; },
  });
  const result = await route({ req: { param: () => 'report-1' }, json: value => value });
  assert.equal(queries.length, 1); assert.equal(result.context.length, 1);
  assert.equal(result.context[0].id, 'reported');
});
test('private backup signing checks uploader ownership even for existing forged messages', async () => {
  let signed = 0;
  const sign = run(fn('mediaBackupIdFromReference') + fn('messageMediaOwnedBy') + fn('signedMessageMediaReference'), {
    signedMediaDeliveryUrl: async () => { signed++; return 'authorized-download'; },
  }, 'signedMessageMediaReference');
  const context = { env: { DB: { prepare: () => ({ bind: () => ({ first: async () => ({ user_id: 'alice' }) }) }) } } };
  const url = '/api/media/private-backup-123';
  assert.equal(await sign(context, url, 'mallory'), '');
  assert.equal(await sign(context, `https://untrusted.example${url}`, 'mallory'), '');
  assert.equal(signed, 0);
  assert.equal(await sign(context, url, 'alice'), 'authorized-download');
  assert.equal(signed, 1);
});

test('private attachment full and range responses override public storage cache metadata', async () => {
  const serve = run(fn('parseByteRange') + fn('serveMediaBackup'), {
    ensureMediaBackupSchema: async () => {}, hasValidMediaAccessToken: async () => true,
    getOptionalUserId: async () => 'alice', enforceRateLimit: async () => null,
  }, 'serveMediaBackup');
  for (const range of [undefined, 'bytes=0-3']) {
    const c = {
      req: { method: 'GET', param: () => 'backup', header: () => range },
      json: (body, status) => Response.json(body, { status }),
      env: {
        DB: { prepare: () => ({ bind: () => ({ first: async () => ({ id: 'backup', r2_key: 'private' }) }) }) },
        MEDIA_BACKUP: {
          head: async () => ({ size: 4, httpEtag: 'etag' }),
          get: async () => ({ body: new Uint8Array([1,2,3,4]), size: 4,
            writeHttpMetadata: h => h.set('cache-control', 'public, max-age=31536000') }),
        },
      },
    };
    const response = await serve(c);
    assert.equal(response.status, range ? 206 : 200);
    assert.equal(response.headers.get('cache-control'), 'private, no-store, max-age=0');
    assert.equal(response.headers.get('cdn-cache-control'), 'no-store');
    assert.equal(response.headers.get('cloudflare-cdn-cache-control'), 'no-store');
    assert.equal(response.headers.get('vary'), 'Authorization, Cookie');
  }
});

test('unattached private media is not visible through an administrator override', async () => {
  const serve = run(fn('serveMediaBackup'), {
    ensureMediaBackupSchema: async () => {}, hasValidMediaAccessToken: async () => false,
    getOptionalUserId: async () => 'administrator', enforceRateLimit: async () => null,
    logSecurityEvent: async () => {},
  }, 'serveMediaBackup');
  const c = {
    req: { param: () => 'backup' }, json: (body, status) => ({ body, status }),
    env: {
      DB: { prepare: sql => {
        assert.match(sql, /^SELECT \* FROM media_backups/);
        return { bind: () => ({ first: async () => ({ id: 'backup', user_id: 'alice' }) }) };
      } },
      MEDIA_BACKUP: { head: () => assert.fail('must not read private object') },
    },
  };
  assert.equal((await serve(c)).status, 404);
});

test('database failures never echo private message rows into error output', async () => {
  const upsert = run(fn('supabaseStorageFailure') + fn('supabaseAdminUpsert'), {
    getSupabaseUrl: () => 'https://database.invalid', getSupabaseServiceRoleKey: () => 'test-only',
    fetch: async () => new Response(JSON.stringify({ code: '23514', message: 'constraint failed',
      details: 'Failing row: private medical conversation', hint: 'private details' }), { status: 400 }),
  }, 'supabaseAdminUpsert');
  for (const table of ['app_messages', 'app_group_messages']) {
    await assert.rejects(upsert({}, table, [{ body: 'private medical conversation' }], 'id'), error => {
      assert.equal(error.message, `SUPABASE_UPSERT_FAILED:${table}:400:23514`); return true;
    });
  }
});
test('duplicate detection works without putting private text into a PostgREST URL', async () => {
  for (const path of ['/messages', '/group-chats/:groupId/messages']) {
    const secretText = 'Private text that must not enter the query URL';
    let queries = 0;
    const route = run(handler('post', path), {
      getUserId: () => 'alice', requireSupabasePrimaryDatabase: () => null,
      enforceRateLimit: async () => null, enforceUserRestriction: async () => null,
      rejectLargeRequest: () => null, rejectUnknownFields: () => null,
      safeMediaReference: () => '', normalizedMediaReferenceForStorage: () => '',
      messageMediaOwnedBy: async () => true, validateDirectMessagePeer: async () => null,
      requireGroupMember: async () => true,
      supabaseAdminQueryRows: async (c, table, query) => {
        queries++; assert.equal(JSON.stringify(query).includes(secretText), false);
        assert.equal(query.filters.body, undefined);
        return [{ id: 'duplicate', body: secretText }];
      },
      logSecurityEvent: async () => {},
    });
    const result = await route({ req: { param: () => 'room', json: async () => ({ content: secretText, receiver_id: 'bob' }) },
      json: (body, status) => ({ body, status }) });
    assert.equal(result.status, 429); assert.equal(queries, 1);
  }
});
test('private Story replies retain authorization but are not sent to cloud AI', async () => {
  let stored;
  const route = run(handler('post', '/statuses/:statusId/reply'), {
    getUserId: () => 'alice', requireSupabasePrimaryDatabase: () => null,
    enforceRateLimit: async () => null, enforceUserRestriction: async () => null,
    supabaseGetVisibleStory: async () => ({ user_id: 'bob' }), validateDirectMessagePeer: async () => null,
    screenCaptroText: () => assert.fail('private conversation sent to AI'),
    uuid: () => 'new-message', now: () => '2026-10-06T00:00:00Z',
    supabaseAdminUpsert: async (c, table, rows) => { assert.equal(table, 'app_messages'); stored = rows[0]; },
    logSecurityEvent: async () => {}, runBackgroundTask: () => {},
  });
  const result = await route({ req: { param: () => 'story', json: async () => ({ body: 'Private reply' }) }, json: v => v });
  assert.equal(result.sent, true); assert.equal(stored.receiver_id, 'bob');
  assert.equal(stored.body, 'Replied to your status\nPrivate reply');
});

test('optional viewer authorization cannot reuse a server-revoked session', async () => {
  let setIdentity = false;
  const optionalUser = run(fn('getOptionalUserId'), {
    supabasePrimaryConfigured: () => true,
    resolveSupabaseSessionUser: async () => ({ userId: 'alice',
      payload: { iat: 100 }, user: { status: 'active', session_revoked_at: new Date(200_000).toISOString() } }),
    canonicalSupabaseRequestPayload: () => assert.fail('must not authorize revoked identity'),
  }, 'getOptionalUserId');
  const result = await optionalUser({ req: { header: () => 'Bearer test-only' }, set: () => { setIdentity = true; } });
  assert.equal(result, ''); assert.equal(setIdentity, false);
});

const migration = readFileSync(new URL('../../supabase/migrations/20261006012846_security_backend_write_boundary.sql', import.meta.url), 'utf8');
const baseline = readFileSync(new URL('../../supabase/migrations/20260612090211_captro_rls_policies.sql', import.meta.url), 'utf8');
const mediaBoundary = readFileSync(new URL('../../supabase/migrations/20261013154326_security_media_approval_boundary.sql', import.meta.url), 'utf8');
const pushBoundary = readFileSync(new URL('../../supabase/migrations/20261013154328_single_owner_push_registration.sql', import.meta.url), 'utf8');
test('SQL: unrelated accounts, self-enrollment, forged roles and message rewriting are denied; revocation preserves history', async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create schema private;
      grant usage on schema public, private, auth to authenticated, service_role;
      create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid', true), '')::uuid$$;
      create table app_users(id text primary key, supabase_user_id uuid, metadata jsonb default '{}');
      create table app_admin_roles(user_id text primary key, role text);
      create table app_posts(id text); create table post_comments(id text);
      create table app_messages(id text, sender_id text, receiver_id text, body text);
      create table app_blocks(blocker_id text, blocked_id text);
      create table app_group_chats(id text, created_by text);
      create table app_group_chat_members(id text, group_id text, user_id text, role text);
      create table app_group_messages(id text, group_id text, sender_id text, body text);
      create table app_media_assets(id text, user_id text, moderation_status text, upload_status text, metadata jsonb);
      grant all on all tables in schema public to anon, authenticated, service_role;
      grant update (moderation_status, metadata) on app_media_assets to authenticated;
      grant insert (id, user_id, moderation_status) on app_media_assets to authenticated;
      insert into app_media_assets values ('asset', 'alice', 'pending_moderation', 'uploaded', '{}');
      insert into app_users values ('alice','00000000-0000-0000-0000-000000000001','{}'),
        ('bob','00000000-0000-0000-0000-000000000002','{}'), ('mallory','00000000-0000-0000-0000-000000000003','{}');
      insert into app_messages values ('dm','alice','bob','preserved history');
      insert into app_group_chats values ('room','alice');
      insert into app_group_chat_members values ('membership','room','alice','member');
      insert into app_group_messages values ('gm','room','alice','preserved group history');
      alter table app_messages enable row level security;
      alter table app_group_chats enable row level security;
      alter table app_group_chat_members enable row level security;
      alter table app_group_messages enable row level security;`);
    // Use the repository's real existing DM read policy and helper, not an
    // equivalent policy invented just for this test.
    await db.exec(migration);
    await db.exec(mediaBoundary);
    await db.exec(mediaBoundary); // Safe to retry after an unknown rollout outcome.
    const helper = baseline.match(/create or replace function private\.captro_users_not_blocked[\s\S]*?\$\$;/)[0];
    await db.exec(helper);
    await db.exec(baseline.slice(baseline.indexOf('drop policy if exists "users can read own direct messages"'), baseline.indexOf('drop policy if exists "users can create own direct messages"')));
    const asUser = async id => {
      await db.exec('reset role');
      await db.query("select set_config('test.uid', $1, false)", [`00000000-0000-0000-0000-00000000000${id}`]);
      await db.exec('set role authenticated');
    };
    await asUser(3);
    await assert.rejects(db.exec('select * from app_users'), /permission denied/);
    await assert.rejects(db.exec('select * from app_admin_roles'), /permission denied/);
    assert.equal((await db.query('select * from app_messages')).rows.length, 0);
    assert.equal((await db.query('select * from app_group_messages')).rows.length, 0);
    await assert.rejects(db.exec("insert into app_group_chat_members values ('attack','room','mallory','owner')"), /permission denied/);
    await assert.rejects(db.exec("update app_users set metadata = '{\"admin_role\":\"owner\"}' where id='mallory'"), /permission denied/);
    await assert.rejects(db.exec("insert into app_admin_roles values ('mallory','owner')"), /permission denied/);
    await asUser(2);
    assert.equal((await db.query('select * from app_messages')).rows.length, 1);
    await assert.rejects(db.exec("update app_messages set sender_id='mallory', body='forged' where id='dm'"), /permission denied/);
    for (const table of ['app_users','app_messages','app_group_chat_members','app_posts','post_comments'])
      await assert.rejects(db.exec(`truncate ${table}`), /permission denied/);
    await asUser(1);
    await assert.rejects(db.exec("update app_media_assets set moderation_status='approved' where id='asset'"), /permission denied/);
    await assert.rejects(db.exec("update app_media_assets set metadata='{\"approved\":true}' where id='asset'"), /permission denied/);
    await assert.rejects(db.exec("insert into app_media_assets (id,user_id,moderation_status) values ('forged','alice','approved')"), /permission denied/);
    assert.equal((await db.query('select * from app_group_messages')).rows.length, 1);
    assert.equal((await db.query('select * from app_group_chat_members')).rows.length, 1);
    // Same database connection remains open through server-side revocation.
    await db.exec("reset role; set role service_role; delete from app_group_chat_members where user_id='alice'; reset role; set role authenticated;");
    assert.equal((await db.query('select * from app_group_messages')).rows.length, 0);
    await db.exec("reset role; insert into app_blocks values ('bob','alice'); set role authenticated;");
    assert.equal((await db.query('select * from app_messages')).rows.length, 0);
    await db.exec("reset role; delete from app_blocks; update app_users set metadata='{\"status\":\"banned\"}' where id='alice'; set role authenticated;");
    assert.equal((await db.query('select * from app_messages')).rows.length, 0);
    await db.exec('reset role; set role service_role');
    await db.exec("update app_media_assets set moderation_status='approved' where id='asset'");
    assert.equal((await db.query('select moderation_status from app_media_assets')).rows[0].moderation_status, 'approved');
    assert.equal((await db.query('select body from app_messages')).rows[0].body, 'preserved history');
    assert.equal((await db.query('select body from app_group_messages')).rows[0].body, 'preserved group history');
    await db.exec('reset role; set role anon');
    await assert.rejects(db.exec("update app_messages set body='anonymous'"), /permission denied/);
  } finally { await db.close(); }
});

test('push registration uses authenticated identity and one atomic server operation', async () => {
  let request;
  const route = run(handler('post', '/notifications/device-token'), {
    getUserId: () => 'current-account', requireSupabasePrimaryDatabase: () => null,
    enforceRateLimit: async () => null, rejectLargeRequest: () => null,
    sha256Hex: async value => `hash-${value}`, supabaseAdminRpc: async (_, name, body) => {
      assert.equal(name, 'captro_register_push_token'); request = body;
    },
  });
  const result = await route({ env: {}, req: { json: async () => ({ token: 'a'.repeat(64), user_id: 'forged' }) }, json: value => value });
  assert.equal(result.ok, true);
  assert.equal(request.p_user_id, 'current-account');
});

test('SQL: push takeover, delayed old logout, duplicate registration and client denial', async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create table app_push_tokens(id text primary key, user_id text, token_hash text, token text,
        device_id text, bundle_id text, environment text, platform text, is_active boolean,
        last_seen_at timestamptz, updated_at timestamptz, unique(user_id, token_hash));
      grant all on app_push_tokens to anon, authenticated, service_role;
      insert into app_push_tokens(id,user_id,token_hash,is_active,last_seen_at) values
        ('old','alice','hash',true,'2026-10-01'),('new','bob','hash',true,'2026-10-02');`);
    await db.exec(pushBoundary);
    await db.exec(pushBoundary);
    assert.equal((await db.query('select count(*)::int as n from app_push_tokens where is_active')).rows[0].n, 0);
    await db.exec('set role authenticated');
    await assert.rejects(db.exec("select * from app_push_tokens"), /permission denied/);
    await assert.rejects(db.exec("select captro_register_push_token('mallory','attack','hash','test-only','','','production')"), /permission denied/);
    await db.exec('reset role; set role service_role');
    const register = user => db.query('select captro_register_push_token($1,$2,$3,$4,$5,$6,$7)',
      [user, `${user}-id`, 'hash', 'test-only', 'device', 'app', 'production']);
    await register('alice'); await register('bob'); await register('bob');
    // Logout from A must not unregister B after ownership has changed.
    await db.exec("update app_push_tokens set is_active=false where user_id='alice' and token_hash='hash'");
    assert.deepEqual((await db.query('select user_id from app_push_tokens where is_active')).rows, [{ user_id: 'bob' }]);
    assert.equal((await db.query('select count(*)::int as n from app_push_tokens')).rows[0].n, 2);
    // Unique constraint is defense in depth for any older server direct writer.
    await assert.rejects(db.exec("update app_push_tokens set is_active=true where user_id='alice'"), /duplicate key/);
  } finally { await db.close(); }
});
