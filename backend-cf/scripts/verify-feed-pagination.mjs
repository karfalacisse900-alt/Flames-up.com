// Read-only production smoke. Never prints post contents, identities or cursors.
import assert from 'node:assert/strict';

const base = process.env.CAPTRO_API_BASE || 'https://api.flames-up.com/api';
async function get(query) {
  const response = await fetch(`${base}/posts/world-board?${query}`, {
    headers: { Accept: 'application/json', 'Cache-Control': 'no-cache' },
    signal: AbortSignal.timeout(30000),
  });
  assert.equal(response.status, 200, `Feed HTTP ${response.status}`);
  return response.json();
}
const legacy = await get('limit=12&skip=0');
assert.ok(Array.isArray(legacy), 'Existing clients must retain the array response');
const ids = new Set();
const cursors = new Set();
let cursor;
for (let page = 0; page < 6; page++) {
  const result = await get(`pagination=v2&limit=12${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
  assert.ok(Array.isArray(result.posts), 'Cursor endpoint must return posts');
  assert.equal(typeof result.hasMore, 'boolean');
  for (const post of result.posts) {
    assert.equal(typeof post.id, 'string');
    assert.ok(!ids.has(post.id), 'A post repeated across cursor pages');
    ids.add(post.id);
  }
  console.log(JSON.stringify({ page: page + 1, count: result.posts.length,
    uniquePosts: ids.size, hasMore: result.hasMore, legacyArraySupported: true }));
  if (!result.hasMore) break;
  assert.ok(typeof result.nextCursor === 'string' && result.nextCursor.length > 0);
  assert.ok(!cursors.has(result.nextCursor), 'Continuation did not advance');
  cursors.add(result.nextCursor);
  cursor = result.nextCursor;
}
