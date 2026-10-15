import assert from 'node:assert/strict';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { FeedCursorError, readFeedCursor, writeFeedCursor, feedBoundary, feedKeysetFilters, feedKeysetOrder } from '../src/feed-pagination.ts';

const secret = 'isolated-pagination-fixture-not-a-production-key';
const binding = { viewer: 'test-reader', scope: 'for_you', city: '' };
const now = Date.parse('2026-10-14T12:00:00Z');
const row = { id: '10000000-0000-4000-8000-000000000001', created_at: '2026-10-14T11:59:59.123456+00:00', legacy_created_at: null };

test('cursor is encrypted, authentic, account/scope/city bound and time limited', async () => {
  const cursor = await readFeedCursor(secret, undefined, binding, now);
  cursor.boundary = feedBoundary(row);
  const token = await writeFeedCursor(secret, cursor);
  const raw = Buffer.from(token, 'base64url').toString('utf8');
  assert.ok(!raw.includes(row.id));
  assert.ok(!raw.includes(binding.viewer));
  assert.deepEqual(await readFeedCursor(secret, token, binding, now + 1), cursor);
  for (const other of [{ ...binding, viewer: 'another-account' }, { ...binding, scope: 'following' }, { ...binding, city: 'another-city' }])
    await assert.rejects(readFeedCursor(secret, token, other, now), FeedCursorError);
  await assert.rejects(readFeedCursor(secret, token, binding, now + 86_400_001), FeedCursorError);
  const corrupt = `${token.slice(0, 20)}${token[20] === 'a' ? 'b' : 'a'}${token.slice(21)}`;
  await assert.rejects(readFeedCursor(secret, corrupt, binding, now), FeedCursorError);
  for (const invalid of ['invalid', 'a'.repeat(2049), '(id.gt.anything)', 'not/base64'])
    await assert.rejects(readFeedCursor(secret, invalid, binding, now), FeedCursorError);
});

test('boundary retains timestamp microseconds and refuses non-data filter syntax', () => {
  assert.equal(feedBoundary(row).createdAt, row.created_at);
  for (const patch of [{ id: 'malicious,id.gt.anything' }, { created_at: '2026-10-14),id.gt.anything' }, { legacy_created_at: '' }])
    assert.throws(() => feedBoundary({ ...row, ...patch }), /FEED_ROW_BOUNDARY_INVALID/);
});

function split(value) {
  let depth = 0, begin = 0;
  const items = [];
  for (let i = 0; i < value.length; i++) {
    if (value[i] === '(') depth++;
    if (value[i] === ')') depth--;
    if (value[i] === ',' && !depth) { items.push(value.slice(begin, i)); begin = i + 1; }
  }
  return [...items, value.slice(begin)];
}
function sqlFilter(expression, values) {
  for (const operator of ['or', 'and']) if (expression.startsWith(`${operator}(`))
    return `(${split(expression.slice(operator.length + 1, -1)).map(part => sqlFilter(part, values)).join(` ${operator} `)})`;
  const [, column, operator, value] = expression.match(/^([^.]+)\.([^.]+)\.(.*)$/) || [];
  assert.ok(['id', 'created_at', 'legacy_created_at', 'status'].includes(column));
  if (operator === 'is') { assert.equal(value, 'null'); return `${column} is null`; }
  assert.ok(['lt', 'lte', 'eq'].includes(operator));
  values.push(value);
  return `${column} ${{ lt: '<', lte: '<=', eq: '=' }[operator]} $${values.length}`;
}

test('generated keyset conditions match PostgreSQL ordering with timestamp ties, microseconds and NULL legacy dates', async () => {
  const db = new PGlite();
  try {
    await db.exec(`create table posts(id uuid primary key, status text not null default 'active', legacy_created_at timestamptz, created_at timestamptz not null)`);
    const dates = [
      ['2020-01-02T00:00:00.000001Z', '2020-01-03T00:00:00.000003Z'],
      ['2020-01-02T00:00:00.000001Z', '2020-01-03T00:00:00.000002Z'],
      ['2020-01-02T00:00:00.000001Z', '2020-01-03T00:00:00.000002Z'],
      ['2020-01-02T00:00:00.000000Z', '2020-01-03T00:00:00.000004Z'],
      [null, '2020-01-03T00:00:00.000003Z'],
      [null, '2020-01-03T00:00:00.000002Z'],
      [null, '2020-01-03T00:00:00.000002Z'],
    ];
    for (const [i, [legacy, created]] of dates.entries())
      await db.query('insert into posts(id,legacy_created_at,created_at) values($1,$2,$3)', [`10000000-0000-4000-8000-${String(i).padStart(12, '0')}`, legacy, created]);
    const order = feedKeysetOrder.split(',').map(item => item.replace('.desc', ' desc').replace('.nullslast', ' nulls last')).join(',');
    const expected = (await db.query(`select id from posts order by ${order}`)).rows.map(item => item.id);
    let cursor = await readFeedCursor(secret, undefined, binding, now);
    const actual = [];
    for (let iteration = 0; iteration < 10; iteration++) {
      const values = [];
      const filters = feedKeysetFilters(cursor);
      const where = Object.entries(filters).map(([field, condition]) => sqlFilter(field === 'or' ? `or${condition}` : `${field}.${condition}`, values)).join(' and ');
      const result = await db.query(`select id,
        to_char(legacy_created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as legacy_created_at,
        to_char(created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as created_at
        from posts where ${where} order by ${order} limit 2`, values);
      if (!result.rows.length) break;
      actual.push(...result.rows.map(item => item.id));
      cursor = { ...cursor, boundary: feedBoundary(result.rows.at(-1)) };
    }
    assert.deepEqual(actual, expected);
    assert.equal(new Set(actual).size, dates.length);
  } finally { await db.close(); }
});
