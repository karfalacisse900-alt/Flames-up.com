import test from 'node:test';
import assert from 'node:assert/strict';
import { teaPage, teaDetail, TeaUnavailable, TeaInputError } from '../src/tea.ts';
import { readFeedCursor, FeedCursorError } from '../src/feed-pagination.ts';

const key = 'a-test-key-that-is-not-a-production-secret';
const viewer = 'viewer';
const now = Date.parse('2026-11-11T22:00:00Z');
const id = n => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const at = '2026-11-11T21:00:00.123456+00:00';
const old = '2026-11-11T21:00:00.123455+00:00';

function fixture() {
  const calls = [];
  const postRows = new Map(), owners = new Map(), blocked = new Set();
  const rows = { app_purchasables: [], app_businesses: [] };
  const user = (n, extra = {}) => ({ id: 'user-' + n, supabase_user_id: id(200 + n), is_private: false, metadata: {}, ...extra });
  function activity(n, contentType, overrides = {}) {
    const owner = user(n, overrides.owner);
    owners.set(owner.supabase_user_id, owner);
    const post = { id: id(500 + n), legacy_post_id: 'post-' + n, status: 'active',
      user_id: owner.supabase_user_id, app_user_id: owner.id, visibility: 'public', metadata: {}, ...overrides.post };
    postRows.set(post.id, post);
    const row = { id: id(n), post_id: post.id, creator_id: owner.supabase_user_id, content_type: contentType,
      title: 'Activity ' + n, status: 'active', audience: 'anyone', visibility: 'public',
      created_at: at, city: 'New York', ...overrides.row };
    rows.app_purchasables.push(row);
    return row;
  }
  function business(n, overrides = {}) {
    const owner = user(100 + n, overrides.owner);
    owners.set(owner.supabase_user_id, owner);
    const row = { id: id(n), owner_id: owner.supabase_user_id, name: 'Business ' + n, category: 'coffee_bakery',
      latitude: 40.73, longitude: -73.99, published: true, paused: false, location_updated_at: at, ...overrides.row };
    rows.app_businesses.push(row);
    return row;
  }
  const deps = {
    async query(table, query) {
      calls.push([table, query]);
      const time = table === 'app_purchasables' ? 'created_at' : 'location_updated_at';
      if (query.filters.id) return rows[table].filter(row => 'eq.' + row.id === query.filters.id);
      let results = rows[table];
      if (query.filters.or) {
        const [, timestamp, compare, boundary] = query.filters.or.match(/\((?:created_at|location_updated_at)\.lt\.([^,]+),and\([^.]+\.eq\.[^,]+,id\.(lt|lte)\.([^)]+)\)\)/);
        results = results.filter(row => row[time] < timestamp || (row[time] === timestamp &&
          (compare === 'lte' ? row.id <= boundary : row.id < boundary)));
      }
      return [...results].sort((a,b) => b[time].localeCompare(a[time]) || b.id.localeCompare(a.id)).slice(0, query.limit);
    },
    access: async () => ({ posts: postRows, owners, blocked }),
    isActiveUser: user => (user.metadata.status ?? 'active') === 'active',
    commerce: async row => ({ canonicalID: row.id }),
  };
  return { deps, calls, activity, business, owners, blocked, postRows };
}

test('Tea returns individually addressable public objects; all visibility checks also run for direct details', async () => {
  const f = fixture();
  f.activity(1, 'club');
  f.activity(2, 'event');
  f.activity(3, 'meetup');
  f.activity(4, 'deal', { row: { capacity: 2, quantity_committed: 2 } });
  f.activity(5, 'booking');
  const eligibleShop = f.business(6, { row: { paused: true } });
  const rejected = [
    f.activity(7, 'club', { owner: { is_private: true } }),
    f.activity(8, 'event', { owner: { metadata: { status: 'suspended' } } }),
    f.activity(9, 'event', { post: { visibility: 'private' } }),
    f.activity(10, 'event', { post: { status: 'removed' } }),
    f.activity(11, 'meetup', { row: { ends_at: old } }),
    f.activity(12, 'deal', { row: { expires_at: old } }),
    f.activity(13, 'club', { row: { audience: 'followers' } }),
    f.activity(14, 'club', { row: { status: 'draft' } }),
    f.activity(15, 'club', { post: { metadata: { discover_blocked_at: old } } }),
    f.activity(16, 'club', { post: { user_id: id(999) } }),
    f.activity(17, 'club', { post: { metadata: { moderation_status: 'pending' } } }),
    f.activity(18, 'club', { row: { visibility: 'private' } }),
  ];
  const blocked = f.activity(19, 'deal');
  f.blocked.add(f.owners.get(blocked.creator_id).id);
  rejected.push(blocked);
  const hiddenShop = f.business(20, { row: { published: false } });
  const result = await teaPage(f.deps, key, viewer, {}, now);
  assert.deepEqual(result.items.map(row => row.kind), ['business','reservation','offer','meetup','event','club']);
  assert.equal(result.items[0].status, 'paused');
  assert.equal(result.items[2].status, 'sold_out');
  assert.equal(result.nextCursor, null);
  assert.equal('owner_id' in (await teaDetail(f.deps, 'business', eligibleShop.id, now)).business, false);
  const detail = await teaDetail(f.deps, 'activity', id(2), now);
  assert.equal(detail.commerce.canonicalID, id(2));
  assert.equal(detail.post.id, 'post-2');
  for (const row of rejected) await assert.rejects(teaDetail(f.deps, 'activity', row.id, now), TeaUnavailable);
  await assert.rejects(teaDetail(f.deps, 'business', hiddenShop.id, now), TeaUnavailable);
  await assert.rejects(teaDetail(f.deps, 'post', id(2), now), TeaUnavailable);
});

test('Tea pages preserve cross-source ties, microseconds, and viewer/location bindings', async () => {
  const f = fixture();
  for (let n=1; n<=30; n++) f.activity(n, 'event');
  f.business(11);
  f.business(10, { row: { location_updated_at: old } });
  const first = await teaPage(f.deps, key, viewer, {}, now);
  assert.equal(first.items.length, 20);
  assert.equal(first.items[19].id, 'activity:' + id(11));
  const second = await teaPage(f.deps, key, viewer, { cursor: first.nextCursor }, now);
  assert.equal(second.items[0].id, 'business:' + id(11));
  assert.equal(second.items.at(-1).id, 'business:' + id(10));
  assert.equal(new Set([...first.items, ...second.items].map(row => row.id)).size, 32);
  assert.equal(second.nextCursor, null);
  assert.ok(f.calls.every(([, query]) => query.limit <= 32));
  await assert.rejects(teaPage(f.deps, key, 'different-viewer', { cursor: first.nextCursor }, now), FeedCursorError);
  await assert.rejects(teaPage(f.deps, key, viewer, { cursor: first.nextCursor, city: 'Boston' }, now), FeedCursorError);
  await assert.rejects(teaPage(f.deps, key, viewer, { city: 'New York)*' }, now), TeaInputError);
  await assert.rejects(teaPage(f.deps, key, viewer, { lat: '40.73' }, now), TeaInputError);
});

test('Tea uses coarse locality and handles the pending Business migration without swallowing outages', async () => {
  const f = fixture();
  f.activity(1, 'event');
  f.activity(2, 'meetup', { row: { city: 'Boston' } });
  f.business(3);
  f.business(4, { row: { latitude: 42.36, longitude: -71.05 } });
  const scoped = await teaPage(f.deps, key, viewer, { city: 'New York', lat: '40.73', lon: '-73.99' }, now);
  assert.deepEqual(scoped.items.map(row => row.id), ['business:' + id(3), 'activity:' + id(1)]);
  const query = f.deps.query;
  f.deps.query = async (table, input) => {
    if (table === 'app_businesses') throw new Error('SUPABASE_QUERY_FAILED:app_businesses:404:{"code":"PGRST205"}');
    return query(table, input);
  };
  assert.equal((await teaPage(f.deps, key, viewer, {}, now)).items.length, 2);
  await assert.rejects(teaDetail(f.deps, 'business', id(3), now), TeaUnavailable);
  f.deps.query = async () => { throw new Error('database unavailable'); };
  await assert.rejects(teaPage(f.deps, key, viewer, {}, now), /database unavailable/);
});

test('Tea continues beyond an empty scan window without disclosing a hidden record ID', async () => {
  const f = fixture();
  for (let n=1; n<=99; n++) f.activity(n, 'event', n === 1 ? {} : { owner: { is_private: true } });
  const first = await teaPage(f.deps, key, viewer, {}, now);
  assert.equal(first.items.length, 0);
  assert.ok(first.nextCursor);
  assert.equal(first.nextCursor.includes(id(4)), false);
  const cursor = await readFeedCursor(key, first.nextCursor, { viewer, scope: 'tea', city: '["",null]' }, now);
  assert.equal(cursor.boundary.id, id(4));
  const next = await teaPage(f.deps, key, viewer, { cursor: first.nextCursor }, now);
  assert.deepEqual(next.items.map(row => row.id), ['activity:' + id(1)]);
});
