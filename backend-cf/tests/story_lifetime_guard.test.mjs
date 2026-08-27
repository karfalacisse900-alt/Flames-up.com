import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function readRepoFile(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

test('stories remain eligible for two weeks, not one week', async () => {
  const worker = await readRepoFile('backend-cf/src/index.ts');

  assert.match(
    worker,
    /const storyLifetimeMs = 14 \* 24 \* 60 \* 60 \* 1000;/,
    'new stories must expire after 14 days'
  );
  assert.match(
    worker,
    /s\.created_at >= datetime\('now', '-14 days'\)/,
    'legacy story report validation must allow the full 14-day story window'
  );
  assert.doesNotMatch(
    worker,
    /const storyLifetimeMs = 7 \* 24 \* 60 \* 60 \* 1000;|datetime\('now', '-7 days'\)/,
    'story logic must not keep the old 7-day expiration window'
  );
});
