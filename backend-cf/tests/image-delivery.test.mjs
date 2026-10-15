import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { imageDeliveryVariants, uncroppedHostedImageVariant } from '../src/image-delivery.ts';
test('versioned derivatives shrink without cropping and never bypass private signatures', () => {
  assert.deepEqual(imageDeliveryVariants.map(v => v.options.width), [480, 1080]);
  for (const variant of imageDeliveryVariants) {
    assert.equal(variant.options.fit, 'scale-down');
    assert.equal(variant.neverRequireSignedURLs, false);
    assert.equal(uncroppedHostedImageVariant('https://imagedelivery.net/account/image/public', variant.id, 'account'),
      `https://imagedelivery.net/account/image/${variant.id}`);
  }
});
test('publishing keeps the original reference independent of feed variant configuration', () => {
  const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
  const body = source.slice(source.indexOf('function mediaAssetPublicUrl('), source.indexOf('function mediaAssetPreviewUrl('));
  assert.match(body, /cloudflareImageDeliveryUrl\(env, key, 'public'\)/);
  assert.doesNotMatch(body, /CLOUDFLARE_IMAGES_FEED_VARIANT/);
});
test('signed, foreign, invalid and unknown variants are not rewritten', () => {
  for (const source of ['https://imagedelivery.net/account/image/public?sig=private',
    'https://imagedelivery.net/another/image/public', 'http://imagedelivery.net/account/image/public',
    'https://imagedelivery.net.evil.invalid/account/image/public', 'https://other.invalid/image.jpg', 'invalid']) {
    assert.equal(uncroppedHostedImageVariant(source, 'captroFeedV1', 'account'), null);
  }
  assert.equal(uncroppedHostedImageVariant('https://imagedelivery.net/account/image/public', 'unverified', 'account'), null);
  assert.equal(uncroppedHostedImageVariant('https://imagedelivery.net/account/image/public', 'captroFeedV1', ''), null);
});
