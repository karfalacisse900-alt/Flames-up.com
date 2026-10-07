import test from 'node:test';
import assert from 'node:assert/strict';
import { validateMediaWritingOverlays } from '../src/media-writing.ts';
import { PGlite } from '@electric-sql/pglite';
const overlay = () => ({ type: 'media_writing', media_index: 0, writing: {
  schema_version: 1, text: 'FRIDAY NIGHT\nNYC', style: 'bold', alignment: 'left', color: 'white',
  readability: false, x: 0.5, y: 0.2, width: 0.82, size: 'medium', source_aspect_ratio: 0.75,
} });
test('writing round trip preserves exact words, line breaks and source geometry', () => {
  const saved = validateMediaWritingOverlays([overlay()], 1);
  assert.equal(saved[0].writing.text, 'FRIDAY NIGHT\nNYC');
  assert.equal(saved[0].writing.sourceAspectRatio, 0.75);
  assert.deepEqual(validateMediaWritingOverlays(saved, 1), saved);
});
test('one independent overlay per media item; missing and duplicate indices rejected', () => {
  const second = { ...overlay(), media_index: 1 };
  assert.equal(validateMediaWritingOverlays([overlay(), second], 2).length, 2);
  assert.throws(() => validateMediaWritingOverlays([overlay(), overlay()], 1));
  assert.throws(() => validateMediaWritingOverlays([second], 1));
});
test('invalid versions, typography, coordinates, paragraphs fail instead of silent rewriting', () => {
  for (const change of [{ schema_version: 2 }, { text: 'a'.repeat(81) }, { text: '1\n2\n3\n4\n5' },
    { text: ' ' }, { x: NaN }, { y: 1.1 }, { width: 0 }, { style: 'url(font)' }, { source_aspect_ratio: 0 }]) {
    const item = overlay(); Object.assign(item.writing, change);
    assert.throws(() => validateMediaWritingOverlays([item], 1));
  }
});
test('legacy editor metadata is not misinterpreted as unflattened writing', () => {
  assert.deepEqual(validateMediaWritingOverlays([{ type: 'native_editor', hasTextOverlay: true }], 1), []);
});
test('existing JSONB editor_data preserves source-relative writing without flattening', async () => {
  const db = new PGlite();
  try {
    const overlays = validateMediaWritingOverlays([overlay()], 1);
    const result = await db.query("SELECT ($1::jsonb)->'overlays' AS overlays", [JSON.stringify({ overlays })]);
    assert.deepEqual(result.rows[0].overlays, overlays);
  } finally { await db.close(); }
});
