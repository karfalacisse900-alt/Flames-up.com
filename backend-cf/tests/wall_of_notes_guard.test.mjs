import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function read(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

test('wall routes are authenticated, regional, and Ghost-safe', async () => {
  const worker = await read('backend-cf/src/index.ts');

  assert.match(worker, /api\.get\('\/wall\/notes', authMiddleware/);
  assert.match(worker, /api\.post\('\/wall\/notes', authMiddleware/);
  assert.match(worker, /world_x\.gte/);
  assert.match(worker, /identity === 'author' \? \{/);
  assert.match(worker, /author_preview: identity === 'author'/);
  assert.match(worker, /enforceRateLimit\(c, 'wall_note_create'/);
  assert.match(worker, /moderateCommunityText\(body\)/);
});

test('wall migration has RLS, spatial indexes, and unique interaction keys', async () => {
  const migration = await read('supabase/migrations/20260712025734_wall_of_notes.sql');

  for (const table of ['wall_notes', 'wall_note_reactions', 'wall_note_saves', 'wall_note_replies']) {
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security`, 'i'));
  }
  assert.match(migration, /primary key \(note_id, app_user_id\)/i);
  assert.match(migration, /wall_notes_region_idx/i);
  assert.match(migration, /char_length\(body\) between 1 and 300/i);
});
