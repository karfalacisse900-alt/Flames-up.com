import test from 'node:test';
import assert from 'node:assert/strict';
import { validateMediaWritingOverlays } from '../src/media-writing.ts';
import { normalizeCreationIntent, normalizeCreationTime } from '../src/creation-intent.ts';

const writing = { schemaVersion: 2, text: 'FRIDAY NIGHT\nIN NYC', style: 'handwritten', alignment: 'center',
  color: 'black', readability: true, x: .5, y: .5, width: .78, size: 'medium', sourceAspectRatio: 9 / 16,
  showsStamp: false, homeAspectRatio: .8, cropX: .5, cropY: .7 };
const envelope = (index = 0, value = writing) => ({ type: 'media_writing', mediaIndex: index, writing: value });
test('Cover is ordinary metadata, not a new account tier or hidden schedule', () => {
  assert.equal(normalizeCreationIntent('cover'), 'cover');
  assert.equal(normalizeCreationTime('2026-10-10T20:00:00Z', 'cover'), null);
});
test('Cover persists distinct per-item typography and crop without replacing source media', () => {
  const original = [envelope(), envelope(1, { ...writing, style: 'classic', text: 'LITTLE MOMENTS', cropY: .2 })];
  const saved = validateMediaWritingOverlays(original, 2);
  assert.deepEqual(saved, original);
  assert.notEqual(saved[0].writing.text, saved[1].writing.text);
  for (const style of ['handwritten', 'bold', 'classic']) {
    assert.equal(validateMediaWritingOverlays([envelope(0, { ...writing, style })], 1)[0].writing.style, style);
  }
});
test('Cover has its own 70-grapheme limit, no paragraph or unsupported crop', () => {
  assert.equal(validateMediaWritingOverlays([envelope(0, { ...writing, text: 'a'.repeat(70) })], 1)[0].writing.text.length, 70);
  for (const patch of [{ text: 'a'.repeat(71) }, { text: 'one\ntwo\nthree\nfour\nfive' },
    { homeAspectRatio: 0 }, { cropY: 2 }, { width: 2 }, { style: 'arbitrary-font' }]) {
    assert.throws(() => validateMediaWritingOverlays([envelope(0, { ...writing, ...patch })], 1));
  }
  assert.deepEqual(validateMediaWritingOverlays([envelope(0, { ...writing, text: '' })], 1), [],
    'Blank slide writing is absent, not a visible white rectangle');
});
test('unwritten carousel slides store no label and arbitrary source ratios remain valid', () => {
  const saved = validateMediaWritingOverlays([
    envelope(0, { ...writing, homeAspectRatio: 9 / 16 }),
    envelope(1, { ...writing, text: ' \n ' }),
  ], 2);
  assert.equal(saved.length, 1);
  assert.equal(saved[0].mediaIndex, 0);
  assert.equal(saved[0].writing.homeAspectRatio, 9 / 16);
});
