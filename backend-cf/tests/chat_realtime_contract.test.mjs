import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '../..');
const api = fs.readFileSync(path.join(root, 'backend-cf/src/index.ts'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20260924131730_captro_chat_realtime.sql'), 'utf8');
const native = fs.readFileSync(path.join(root, 'ios_native/MIRA/Sources/MIRANative/Services/MIRAChatRealtime.swift'), 'utf8');

test('chat realtime exposes only publishable configuration after auth', () => {
  const route = api.match(/api\.get\('\/chat\/realtime-config', authMiddleware,[\s\S]*?\n\}\);/)?.[0];
  assert.ok(route);
  assert.match(route, /SUPABASE_PUBLISHABLE_KEY/);
  assert.match(route, /SUPABASE_ANON_KEY/);
  assert.doesNotMatch(route, /SUPABASE_SERVICE_ROLE_KEY/);
});

test('chat replication is scoped to RLS-protected tables', () => {
  for (const table of ['app_messages', 'app_group_messages']) {
    assert.match(migration, new RegExp(`alter publication supabase_realtime add table public\\.${table}`));
  }
  assert.match(native, /filter: \.eq\("sender_id", value: userId\)/);
  assert.match(native, /filter: \.eq\("receiver_id", value: userId\)/);
  assert.match(native, /filter: \.eq\("group_id", value: groupId\)/);
  assert.match(native, /await onChange\(\) \/\/ Recover changes/);
});
