import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const account = process.env.CLOUDFLARE_ACCOUNT_ID;
const imagesToken = process.env.CLOUDFLARE_IMAGES_TOKEN || process.env.CLOUDFLARE_MEDIA_API_TOKEN || process.env.CLOUDFLARE_API_TOKEN;
const streamToken = process.env.CLOUDFLARE_STREAM_TOKEN || process.env.CLOUDFLARE_MEDIA_API_TOKEN || process.env.CLOUDFLARE_API_TOKEN;
assert.ok(account && imagesToken && streamToken, 'Cloudflare account and Images/Stream credentials are required');
const base = `https://api.cloudflare.com/client/v4/accounts/${account}`;
const temporary = await mkdtemp(join(tmpdir(), 'captro-media-smoke-'));
let imageId;
let videoId;

async function api(path, token, options = {}) {
  const response = await fetch(`${base}${path}`, {
    ...options,
    headers: { Authorization: `Bearer ${token}`, ...options.headers },
    signal: AbortSignal.timeout(60_000),
  });
  const body = await response.json().catch(() => ({}));
  // Never log upload URLs, playback tokens, or raw provider responses.
  assert.ok(response.ok && body.success, `Cloudflare ${options.method || 'GET'} ${path.split('/').slice(0, 3).join('/')} failed: HTTP ${response.status}, code ${body.errors?.[0]?.code || 'unknown'}`);
  return body.result;
}

function fixture(args) {
  const result = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', ...args], { encoding: 'utf8' });
  assert.equal(result.status, 0, 'Could not generate temporary media fixtures with ffmpeg');
}

async function upload(url, file, mime) {
  const data = new FormData();
  data.append('file', new Blob([await readFile(file)], { type: mime }), file.endsWith('.png') ? 'captro-smoke.png' : 'captro-smoke.mp4');
  const response = await fetch(url, { method: 'POST', body: data, signal: AbortSignal.timeout(90_000) });
  assert.ok(response.ok, `Direct ${mime} upload failed: HTTP ${response.status}`);
}

try {
  const photo = join(temporary, 'photo.png');
  const movie = join(temporary, 'video.mp4');
  fixture(['-f', 'lavfi', '-i', 'testsrc2=size=320x400:rate=1', '-frames:v', '1', '-threads', '1', photo]);
  fixture(['-f', 'lavfi', '-i', 'testsrc2=size=320x400:rate=24', '-t', '1', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', movie]);

  const imageIntent = new FormData();
  imageIntent.append('requireSignedURLs', 'true');
  imageIntent.append('metadata', JSON.stringify({ source: 'captro-release-smoke', temporary: true }));
  const image = await api('/images/v2/direct_upload', imagesToken, { method: 'POST', body: imageIntent });
  imageId = image.id;
  assert.ok(imageId && image.uploadURL, 'Images did not return a direct upload intent');
  await upload(image.uploadURL, photo, 'image/png');
  const storedImage = await api(`/images/v1/${imageId}`, imagesToken);
  assert.notEqual(storedImage.draft, true, 'Image upload is still a draft');
  assert.equal(storedImage.requireSignedURLs, true, 'Smoke-test image must remain private');
  console.log('PASS Cloudflare Images: direct upload and stored image confirmed.');

  const video = await api('/stream/direct_upload', streamToken, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ maxDurationSeconds: 60, requireSignedURLs: true, meta: { name: 'Captro temporary release smoke' } }),
  });
  videoId = video.uid;
  assert.ok(videoId && video.uploadURL, 'Stream did not return a direct upload intent');
  await upload(video.uploadURL, movie, 'video/mp4');
  let processed;
  for (let attempt = 0; attempt < 36; attempt++) {
    processed = await api(`/stream/${videoId}`, streamToken);
    assert.notEqual(processed.status?.state, 'error', 'Stream video processing failed');
    if (processed.readyToStream && processed.status?.state === 'ready') break;
    await delay(5_000);
  }
  assert.ok(processed.readyToStream && processed.status?.state === 'ready', 'Stream did not finish encoding in three minutes');
  assert.equal(processed.input.width, 320);
  assert.equal(processed.input.height, 400);
  assert.ok(processed.duration > 0 && processed.duration <= 2);
  assert.equal(processed.requireSignedURLs, true, 'Smoke-test video must remain private');

  const signed = await api(`/stream/${videoId}/token`, streamToken, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 300 }),
  });
  assert.ok(signed.token, 'Stream did not return a playback token');
  const manifest = new URL(processed.playback.hls);
  manifest.pathname = manifest.pathname.replace(`/${videoId}/`, `/${signed.token}/`);
  const playback = await fetch(manifest, { signal: AbortSignal.timeout(30_000) });
  assert.ok(playback.ok && (await playback.text()).startsWith('#EXTM3U'), 'Stream HLS manifest is not playable');
  console.log('PASS Cloudflare Stream: direct upload, encoding, 4:5 dimensions, and signed HLS playback confirmed.');
} finally {
  const cleanup = [];
  if (imageId) cleanup.push(api(`/images/v1/${imageId}`, imagesToken, { method: 'DELETE' }));
  if (videoId) cleanup.push(api(`/stream/${videoId}`, streamToken, { method: 'DELETE' }));
  const results = await Promise.allSettled(cleanup);
  await rm(temporary, { recursive: true, force: true });
  assert.ok(results.every((result) => result.status === 'fulfilled'), 'Cloudflare temporary fixture cleanup failed');
  console.log('Temporary release media deleted; no posts or user content changed.');
}
