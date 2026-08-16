import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function read(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

test('feed media defaults to 4:5 while preserving tall and immersive ratios', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const models = await read('ios_native/MIRA/Sources/MIRANative/Models/MIRAModels.swift');
  const sizing = await read('ios_native/MIRA/Sources/MIRANative/Components/MIRAComponents.swift');
  const discover = await read('ios_native/MIRA/Sources/MIRANative/Screens/DiscoverNativeView.swift');
  const detail = await read('ios_native/MIRA/Sources/MIRANative/Screens/PostDetailNativeView.swift');

  assert.match(worker, /const FEED_MEDIA_HEIGHT = 1350;/);
  assert.match(worker, /format: '4:5', feed_width: 1080, feed_height: 1350/);
  assert.match(worker, /format: '9:16', feed_width: 1080, feed_height: 1920/);
  assert.match(worker, /DEFAULT_FEED_MEDIA_RATIO = SUPPORTED_FEED_MEDIA_RATIOS\.find\(\(item\) => item\.format === '4:5'\)/);

  assert.match(models, /case nineSixteen = "9:16"/);
  assert.match(models, /defaultRatio: MIRASupportedPostAspectRatio = \.fourFive/);
  assert.match(models, /case \.nineSixteen: return 1920/);

  assert.match(sizing, /feedPreviewRatio: CGFloat = 5\.0 \/ 4\.0/);
  assert.match(sizing, /feedTargetHeight: CGFloat = 1920/);
  assert.match(sizing, /feedImmersiveRatio: CGFloat = 16\.0 \/ 9\.0/);
  assert.match(sizing, /containsRatio\("9", "16"/);
  assert.match(discover, /MIRAMediaSizing\.mainFeedHeight\(/);
  assert.match(detail, /contentMode: \.fit/);
});
