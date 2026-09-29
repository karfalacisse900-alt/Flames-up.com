import assert from 'node:assert/strict';
import test from 'node:test';
import { rankVisibleFeedWindow } from '../src/feed-relevance.ts';

test('feed ranking reuses only the authorized input set and keeps stable IDs', () => {
  const posts = [
    { id: 'a', post_type: 'event', title: 'Dinner tonight' },
    { id: 'b', post_type: 'moment', title: 'Street photography walk', feed_ai_topics: ['photography', 'creative'] },
    { id: 'c', post_type: 'club', title: 'Photo club', feed_ai_topics: ['photography'] },
    { id: 'd', post_type: 'event', title: 'Music event' },
  ];
  const ranked = rankVisibleFeedWindow(posts, ['photography']);
  assert.equal(ranked[0].id, 'b');
  assert.deepEqual(new Set(ranked.map((post) => post.id)), new Set(posts.map((post) => post.id)));
  assert.deepEqual(rankVisibleFeedWindow(posts, []), posts);
});

test('cancelled or sold-out commerce is not boosted by matching AI topics', () => {
  const posts = [
    { id: 'first', post_type: 'moment', title: 'A normal day' },
    { id: 'sold', post_type: 'event', feed_ai_topics: ['photography'], detail: { commerce: { availability: 'sold_out' } } },
    { id: 'good', post_type: 'meetup', feed_ai_topics: ['photography'] },
  ];
  const ranked = rankVisibleFeedWindow(posts, 'photography');
  assert.equal(ranked[0].id, 'good');
  assert.equal(ranked.at(-1).id, 'sold');
});
