import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { imageDeliveryVariants, uncroppedHostedImageVariant } from '../src/image-delivery.ts';

// Only versioned Captro variants may be created. Never alter the existing
// public variant, stored originals, permissions, billing or signing settings.
const apply = process.argv.includes('--apply');
const deliveryOnly = process.argv.includes('--check-delivery');
const account = process.env.CLOUDFLARE_ACCOUNT_ID;
const token = process.env.CLOUDFLARE_IMAGES_TOKEN || process.env.CLOUDFLARE_MEDIA_API_TOKEN || process.env.CLOUDFLARE_API_TOKEN;
const apiBase = process.env.CAPTRO_API_BASE || 'https://flames-up-api.karfalacisse900.workers.dev/api';
async function api(path, options = {}) {
  assert.ok(account && token, 'Images account and credential required');
  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}${path}`, {
    ...options, headers: { Authorization: `Bearer ${token}`, ...options.headers }, signal: AbortSignal.timeout(60000),
  });
  const body = await response.json().catch(() => ({}));
  // No raw provider payloads, credentials, URLs or media identifiers in logs.
  assert.ok(response.ok && body.success, `Images API ${options.method || 'GET'} failed: HTTP ${response.status}; code ${body.errors?.[0]?.code || 'unknown'}`);
  return body.result;
}
function verifyVariant(actual, expected) {
  assert.ok(actual, `Missing ${expected.id}`);
  assert.equal(actual.neverRequireSignedURLs, false, `${expected.id} must honor private-image signing`);
  for (const [key, value] of Object.entries(expected.options)) {
    assert.equal(actual.options?.[key], value, `${expected.id}: unexpected ${key}; refusing to overwrite`);
  }
  const allowed = new Set(Object.keys(expected.options));
  assert.ok(Object.keys(actual.options || {}).every(key => allowed.has(key)), 'Unexpected variant transformation; refusing deployment');
}
async function inspectImage(url) {
  const response = await fetch(url, { headers: { Accept: 'image/jpeg,image/png' }, signal: AbortSignal.timeout(60000) });
  assert.ok(response.ok, `Image delivery HTTP ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  const probe = spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=width,height', '-of', 'json', '-i', 'pipe:0'], { input: bytes, maxBuffer: 1024 * 1024 });
  assert.equal(probe.status, 0, 'Image could not be decoded');
  const stream = JSON.parse(probe.stdout).streams?.[0];
  assert.ok(stream?.width > 0 && stream?.height > 0, 'Missing image dimensions');
  return { width: stream.width, height: stream.height, bytes: bytes.length };
}
async function verifyPublicDelivery(requireReturnedVariants) {
  const response = await fetch(`${apiBase}/posts/world-board?limit=12&skip=0`, { signal: AbortSignal.timeout(30000) });
  assert.ok(response.ok, `Public feed HTTP ${response.status}`);
  const payload = await response.json();
  const posts = Array.isArray(payload) ? payload : payload.posts || payload.items || payload.data || [];
  let checked = 0;
  for (const post of posts) {
    const originals = post.images || [];
    if (!Array.isArray(originals)) continue;
    for (let index = 0; index < originals.length && checked < 3; index++) {
      const source = originals[index];
      let parsed;
      try { parsed = new URL(source); } catch { continue; }
      if (parsed.host !== 'imagedelivery.net' || parsed.search) continue;
      const hash = parsed.pathname.split('/').filter(Boolean)[0];
      const original = await inspectImage(source);
      const results = [];
      for (const variant of imageDeliveryVariants) {
        const target = uncroppedHostedImageVariant(source, variant.id, hash);
        assert.ok(target, 'Cannot safely construct configured public variant');
        if (requireReturnedVariants) {
          const field = variant.id === 'captroFeedV1' ? 'feed_media_urls' : 'thumbnail_urls';
          // The current public delivery is already smaller than 1080px. Do not
          // increase ordinary feed downloads just to activate a bigger variant.
          const expected = variant.id === 'captroFeedV1' ? source : target;
          assert.equal(post[field]?.[index], expected, `Unexpected delivery choice in ${field}`);
        }
        const result = await inspectImage(target);
        assert.ok(result.width <= variant.options.width && result.height <= variant.options.height, 'Variant exceeds configured bounds');
        assert.ok(Math.abs(result.width / result.height - original.width / original.height) <= 2 / result.height, 'Variant unexpectedly changed the source aspect ratio');
        results.push({ variant: variant.id, ...result });
      }
      console.log(JSON.stringify({ publicSample: ++checked, existingDelivery: original,
        configuredDerivatives: results, deliveredFeed: requireReturnedVariants ? 'existing-size-preserved' : 'not-checked' }));
    }
    if (checked === 3) break;
  }
  assert.equal(checked, 3, 'Need three public samples for delivery verification');
}

if (!deliveryOnly) {
  const before = await api('/images/v1/variants');
  console.log(JSON.stringify({ existingPublicVariantOptions: before.variants?.public?.options || null }));
  for (const expected of imageDeliveryVariants) {
    const existing = before.variants?.[expected.id];
    if (existing) verifyVariant(existing, expected);
    else {
      assert.ok(apply, `Missing ${expected.id}; --apply authorization required`);
      await api('/images/v1/variants', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(expected) });
    }
  }
  const after = await api('/images/v1/variants');
  for (const expected of imageDeliveryVariants) verifyVariant(after.variants?.[expected.id], expected);
  console.log('PASS: two uncropped variants configured; private signing bypass disabled.');
  // A disposable private fixture proves the variant cannot expose a private
  // image. Delete only the image ID returned by this request in finally.
  if (apply) {
  let fixtureID;
  try {
    const form = new FormData();
    form.append('requireSignedURLs', 'true');
    form.append('metadata', JSON.stringify({ source: 'captro-variant-privacy-smoke', temporary: true }));
    const generated = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
      'testsrc2=size=320x400:rate=1', '-frames:v', '1', '-threads', '1', '-f', 'image2pipe', '-c:v', 'png', 'pipe:1']);
    assert.equal(generated.status, 0, 'Could not generate private image fixture');
    form.append('file', new Blob([generated.stdout], { type: 'image/png' }), 'private-fixture.png');
    const fixture = await api('/images/v1', { method: 'POST', body: form });
    fixtureID = fixture.id;
    assert.ok(fixtureID && fixture.requireSignedURLs, 'Fixture must remain private');
    const sample = fixture.variants?.[0];
    assert.ok(sample, 'Fixture has no delivery path');
    const parsed = new URL(sample);
    const hash = parsed.pathname.split('/').filter(Boolean)[0];
    for (const variant of imageDeliveryVariants) {
      const target = uncroppedHostedImageVariant(sample, variant.id, hash);
      assert.ok(target, 'Private fixture URL unexpectedly signed');
      const denied = await fetch(target, { signal: AbortSignal.timeout(30000) });
      await denied.body?.cancel();
      assert.ok([401, 403, 404].includes(denied.status), 'Unsigned private variant was not denied');
    }
    console.log('PASS: unsigned access denied for both private-image variants.');
  } finally {
    if (fixtureID) {
      await api(`/images/v1/${encodeURIComponent(fixtureID)}`, { method: 'DELETE' });
      console.log('Temporary private fixture removed; no user media changed.');
    }
  }
  }
}
await verifyPublicDelivery(deliveryOnly);
console.log('PASS: image variant dimensions and uncropped proportions verified.');
