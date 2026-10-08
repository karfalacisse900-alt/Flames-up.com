import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeCreationIntent, normalizeCreationTime, compositionCharacterCount, compositionHeadline, compositionBody } from '../src/creation-intent.ts';
import { readFileSync } from 'node:fs';

test('three ordinary writing intents and Cover; no Post category or phrase injection', () => {
  for (const value of ['want_to','looking_for','concern','cover']) assert.equal(normalizeCreationIntent(value), value);
  for (const value of ['post','business','announcement',null,{},'Want to']) assert.equal(normalizeCreationIntent(value), null);
  assert.equal(compositionHeadline('A designer and developer.\nTo build something.'), 'A designer and developer.');
  const emojiHeadline = compositionHeadline('👨‍👩‍👧‍👦'.repeat(500));
  assert.equal(emojiHeadline, '👨‍👩‍👧‍👦'.repeat(16));
  assert.ok(emojiHeadline.length <= 180);
});
test('500-character counting matches native extended grapheme clusters', () => {
  assert.equal(compositionCharacterCount('👨‍👩‍👧‍👦'), 1);
  assert.equal(compositionCharacterCount('e\u0301'), 1);
  assert.equal(compositionCharacterCount('🇺🇸'.repeat(500)), 500);
  assert.equal(compositionCharacterCount('a'.repeat(501)), 501);
});
test('Concern cannot submit a hidden schedule', () => {
  assert.equal(normalizeCreationTime('2026-10-05T12:00:00Z','concern'), null);
  assert.equal(normalizeCreationTime(null,'want_to'), null);
  assert.equal(normalizeCreationTime('2026-10-05T12:00:00Z','looking_for'), '2026-10-05T12:00:00.000Z');
  assert.throws(() => normalizeCreationTime('tomorrow','want_to'));
});
test('ordinary messages retain punctuation and Unicode as plain text', () => {
  const body = `I'm looking for a designer. "Let's build" <3\n${'👨‍👩‍👧‍👦'.repeat(10)}`;
  assert.equal(compositionBody(body), body);
  assert.equal(compositionBody(' hello\r\nworld\u0000 '), 'hello\nworld');
});
test('new metadata reuses existing columns, moderation, and idempotent publishing', () => {
  const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
  const create = source.slice(source.indexOf("api.post('/posts',"),source.indexOf("api.get('/posts/:postId'"));
  assert.match(create, /supabaseExistingPostByClientRequest/);
  assert.match(create, /screenCaptroText/);
  assert.match(create, /compositionCharacterCount\(rawContent\) > 500/);
  assert.match(create, /visibility = normalizeVisibility\(b\.visibility\)/);
  assert.match(source, /creation_intent: normalizeCreationIntent\(input.creationIntent\)/);
  assert.match(create, /creationIntent \? compositionBody\(rawContent\)/);
  assert.match(source, /normalizeCreationIntent\(input.creationIntent\)\s*\? compositionBody\(input.postContent\)/);
  assert.match(source, /normalizeCreationIntent\(\(metadata as any\)\.creation_intent\)\s*\? compositionBody\(row\?\.content\)/);
});

