import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const workerPath = new URL('../src/index.ts', import.meta.url);

test('guest world board survives a rate-limit store outage', async () => {
  const source = await readFile(workerPath, 'utf8');
  const start = source.indexOf("api.get('/posts/world-board'");
  const end = source.indexOf("api.get('/posts/nearby-feed'", start);
  assert.ok(start >= 0 && end > start, 'world-board route is missing');

  const route = source.slice(start, end);
  assert.match(route, /enforceRateLimit\(c, 'public_world_board'/);
  assert.match(route, /event: 'public_world_board_rate_limit_unavailable'/);
  assert.match(route, /return null;/);
  assert.match(route, /supabaseReadVisiblePosts\(c, viewerId/);
  assert.doesNotMatch(route, /authMiddleware/);
});
