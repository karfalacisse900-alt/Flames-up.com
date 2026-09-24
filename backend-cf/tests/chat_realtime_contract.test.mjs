import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { cloudflareTusCreationHeaders } from '../src/media-upload.ts';

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

test('resumable Stream intent bounds duration and preserves signed playback policy', () => {
  const headers = cloudflareTusCreationHeaders({
    token: 'test-only', fileSize: 10_485_760, maxDurationSeconds: 60,
    requireSignedURLs: true, creatorId: 'owner-1', filename: 'clip.mov',
  });
  assert.equal(headers['Tus-Resumable'], '1.0.0');
  assert.equal(headers['Upload-Length'], '10485760');
  const metadata = Object.fromEntries(headers['Upload-Metadata'].split(',').map((entry) => {
    const [key, value] = entry.split(' ');
    return [key, Buffer.from(value, 'base64').toString('utf8')];
  }));
  assert.deepEqual(metadata, { maxDurationSeconds: '60', requiresignedurls: 'true', name: 'clip.mov' });
  assert.equal(headers['Upload-Creator'], 'owner-1');
  const publicHeaders = cloudflareTusCreationHeaders({
    token: 'test-only', fileSize: 5_242_880, maxDurationSeconds: 60,
    requireSignedURLs: false, creatorId: 'owner-1', filename: 'clip.mov',
  });
  assert.doesNotMatch(publicHeaders['Upload-Metadata'], /requiresignedurls/);
  const unicodeHeaders = cloudflareTusCreationHeaders({
    token: 'test-only', fileSize: 5_242_880, maxDurationSeconds: 60,
    requireSignedURLs: true, creatorId: 'owner-1', filename: 'café.mov',
  });
  const encodedName = unicodeHeaders['Upload-Metadata'].split(',').find((part) => part.startsWith('name ')).split(' ')[1];
  assert.equal(Buffer.from(encodedName, 'base64').toString('utf8'), 'café.mov');
});
