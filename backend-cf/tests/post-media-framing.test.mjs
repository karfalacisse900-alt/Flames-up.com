import test from 'node:test';
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { validatePostMediaFraming as validate } from '../src/post-media-framing.ts';
const frame = { version: 1, sourceAspectRatio: 9/16, displayAspectRatio: 0.8, cropX: 0.3, cropY: 0.8, mediaId: 'a'.repeat(64) };
test('framing keeps original dimensions and explicit user crop through JSONB', async () => {
  const db = new PGlite();
  try {
    const dimension = { width: 1080, height: 1920, source_orientation: 6, framing: validate(frame) };
    const result = await db.query('select $1::jsonb as media', [JSON.stringify(dimension)]);
    assert.deepEqual(result.rows[0].media, dimension);
    assert.deepEqual(validate(result.rows[0].media.framing), frame);
  } finally { await db.close(); }
});
test('all four supported formats and Swift snake-case payloads round trip', () => {
  for (const display of [0.8, 1, 0.75, 16/9]) {
    assert.equal(validate({ ...frame, displayAspectRatio: display }).displayAspectRatio, display);
  }
  assert.deepEqual(validate({ version: 1, source_aspect_ratio: 9/16, display_aspect_ratio: 0.8,
    crop_x: 0.3, crop_y: 0.8, media_id: frame.mediaId }), frame);
  assert.equal(validate(undefined), null);
});
test('malformed crop data is rejected, never silently clipped or coerced', () => {
  for (const change of [{ version: 2 }, { cropY: 2 }, { cropX: -1 }, { sourceAspectRatio: NaN },
    { displayAspectRatio: 9/16 }, { sourceAspectRatio: 0 }, { cropX: '0.5' }, { mediaId: 'private-url' }]) {
    assert.throws(() => validate({ ...frame, ...change }));
  }
});
