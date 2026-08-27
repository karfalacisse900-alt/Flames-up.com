import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  auraCommunityFeedCursorFilter,
  auraCommunityFeedRowCursor,
  collectAuraCommunityCursorPage,
  decodeAuraCommunityFeedCursor,
  encodeAuraCommunityFeedCursor,
  normalizeAuraCommunityCity,
} from '../src/aura-community-pagination.js';

function uuid(index) {
  return `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`;
}

function comesAfterCursor(row, cursor) {
  if (!cursor) return true;
  if (row.created_at !== cursor.createdAt) return row.created_at < cursor.createdAt;
  return row.id < cursor.id;
}

function pageReader(rows, calls) {
  return async (cursor, limit) => {
    calls.push(cursor);
    return rows.filter((row) => comesAfterCursor(row, cursor)).slice(0, limit);
  };
}

function visibleProjector(visibleIds) {
  return async (rows) => rows
    .filter((row) => visibleIds.has(row.id))
    .map((row) => ({ sourceId: row.id, item: { id: row.id } }));
}

test('cursor scanner crosses a sparse raw window larger than 100 until the visible page fills', async () => {
  const start = Date.parse('2026-08-26T12:00:00.000Z');
  const rows = Array.from({ length: 230 }, (_, index) => ({
    id: uuid(1000 - index),
    created_at: new Date(start - index * 1000).toISOString(),
  }));
  const visibleIds = new Set([rows[5].id, rows[140].id, rows[205].id]);
  const calls = [];

  const first = await collectAuraCommunityCursorPage({
    limit: 3,
    chunkSize: 100,
    cursor: null,
    readChunk: pageReader(rows, calls),
    rowCursor: auraCommunityFeedRowCursor,
    projectVisible: visibleProjector(visibleIds),
  });

  assert.deepEqual(first.items.map((item) => item.id), [rows[5].id, rows[140].id, rows[205].id]);
  assert.equal(calls.length, 3);
  assert.deepEqual(first.nextCursor, auraCommunityFeedRowCursor(rows[205]));
  assert.equal(first.hasMore, true);

  const second = await collectAuraCommunityCursorPage({
    limit: 3,
    chunkSize: 100,
    cursor: first.nextCursor,
    readChunk: pageReader(rows, []),
    rowCursor: auraCommunityFeedRowCursor,
    projectVisible: visibleProjector(visibleIds),
  });
  assert.deepEqual(second.items, []);
  assert.equal(second.nextCursor, null);
  assert.equal(second.hasMore, false);
});

test('created-at plus id cursor preserves every equal-timestamp row without duplicates', async () => {
  const createdAt = '2026-08-26T12:00:00.000Z';
  const rows = [5, 4, 3, 2, 1].map((index) => ({ id: uuid(index), created_at: createdAt }));
  const visibleIds = new Set(rows.map((row) => row.id));
  const readChunk = pageReader(rows, []);
  const pages = [];
  let cursor = null;

  for (;;) {
    const page = await collectAuraCommunityCursorPage({
      limit: 2,
      chunkSize: 2,
      cursor,
      readChunk,
      rowCursor: auraCommunityFeedRowCursor,
      projectVisible: visibleProjector(visibleIds),
    });
    pages.push(...page.items.map((item) => item.id));
    if (!page.hasMore) break;
    cursor = page.nextCursor;
  }

  assert.deepEqual(pages, rows.map((row) => row.id));
  assert.equal(new Set(pages).size, rows.length);
  assert.equal(
    auraCommunityFeedCursorFilter(auraCommunityFeedRowCursor(rows[1])),
    `(created_at.lt.${createdAt},and(created_at.eq.${createdAt},id.lt.${rows[1].id}))`
  );
});

test('opaque cursor validation rejects malformed data and round-trips canonical keys', () => {
  const cursor = { createdAt: '2026-08-26T12:00:00Z', id: uuid(42) };
  const encoded = encodeAuraCommunityFeedCursor(cursor);
  assert.ok(encoded);
  assert.deepEqual(decodeAuraCommunityFeedCursor(encoded), {
    createdAt: '2026-08-26T12:00:00.000Z',
    id: uuid(42),
  });
  assert.equal(decodeAuraCommunityFeedCursor('not valid base64!'), null);
  assert.equal(decodeAuraCommunityFeedCursor(encodeAuraCommunityFeedCursor({ ...cursor, id: 'not-a-uuid' })), null);
});

test('New York City aliases and boroughs share one canonical city key', () => {
  for (const alias of [
    'NYC',
    'New York',
    'New York City',
    'New York, NY',
    'New York City, NY',
    'Manhattan',
    'Brooklyn, NY',
    'Bronx',
    'Queens, NY',
    'Staten Island',
  ]) {
    assert.equal(normalizeAuraCommunityCity(alias), 'new york city', alias);
  }
  assert.equal(normalizeAuraCommunityCity('Albany, NY'), 'albany ny');
});
