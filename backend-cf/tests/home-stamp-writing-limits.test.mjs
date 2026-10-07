import test from 'node:test';
import assert from 'node:assert/strict';
import { newMediaStampWritingError } from '../src/creation-intent.ts';
import { validateMediaWritingOverlays } from '../src/media-writing.ts';
const input = { mediaCount: 1, postType: 'general', title: '', caption: '' };
test('new media captions and supplied titles have independent grapheme limits', () => {
  assert.equal(newMediaStampWritingError({ ...input, title: 'a'.repeat(60), caption: 'a'.repeat(220) }), null);
  assert.equal(newMediaStampWritingError({ ...input, caption: 'a'.repeat(221) }).code, 'MEDIA_CAPTION_TOO_LONG');
  assert.equal(newMediaStampWritingError({ ...input, title: 'a'.repeat(61) }).code, 'MEDIA_TITLE_TOO_LONG');
  assert.equal(newMediaStampWritingError({ ...input, caption: '👨‍👩‍👧‍👦'.repeat(220) }), null);
});
test('text-only and full structured descriptions retain their separate limits', () => {
  for (const postType of ['club', 'event', 'meetup', 'deal']) {
    assert.equal(newMediaStampWritingError({ ...input, postType, caption: 'a'.repeat(4000) }), null);
  }
  assert.equal(newMediaStampWritingError({ ...input, mediaCount: 0, title: 'a'.repeat(100), caption: 'a'.repeat(500) }), null);
});
test('rejection never edits the input or a legacy record', () => {
  const legacy = { ...input, title: 'a'.repeat(100), caption: 'Original sentence. '.repeat(50) };
  const original = structuredClone(legacy);
  assert.equal(newMediaStampWritingError(legacy).code, 'MEDIA_TITLE_TOO_LONG');
  assert.deepEqual(legacy, original);
});
test('visual writing accepts 60 graphemes but rejects 61 without rewriting', () => {
  const writing = { schemaVersion: 1, text: '👨‍👩‍👧‍👦'.repeat(60), style: 'clean', alignment: 'left',
    color: 'white', readability: false, x: .5, y: .2, width: .8, size: 'small', sourceAspectRatio: .75 };
  assert.equal(validateMediaWritingOverlays([{ type: 'media_writing', mediaIndex: 0, writing }], 1)[0].writing.text, writing.text);
  assert.throws(() => validateMediaWritingOverlays([{ type: 'media_writing', mediaIndex: 0,
    writing: { ...writing, text: writing.text + 'a' } }], 1));
});
