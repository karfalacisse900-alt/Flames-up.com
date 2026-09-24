import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const project = process.env.SUPABASE_PROJECT_REF;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const publishableKey = process.env.SUPABASE_ANON_KEY;
const account = process.env.CLOUDFLARE_ACCOUNT_ID;
const streamToken = process.env.CLOUDFLARE_STREAM_TOKEN || process.env.CLOUDFLARE_MEDIA_API_TOKEN || process.env.CLOUDFLARE_API_TOKEN;
assert.ok(project && serviceKey && publishableKey && account && streamToken, 'Production video-test credentials are required');

const supabase = `https://${project}.supabase.co`;
const api = 'https://flames-up-api.karfalacisse900.workers.dev/api';
const admin = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
const scratch = await mkdtemp(join(tmpdir(), 'captro-story-video-'));
let userId = '';
let videoId = '';
let probeVideoId = '';

async function request(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: { 'User-Agent': 'Captro-Video-Status-Diagnostic/1.0', ...init.headers },
    signal: AbortSignal.timeout(60_000),
  });
  const body = response.headers.get('content-type')?.includes('application/json')
    ? await response.json().catch(() => ({})) : {};
  return { response, body };
}

async function remove(url, headers = admin) {
  const { response } = await request(url, { method: 'DELETE', headers });
  if (!response.ok) throw new Error(`Temporary video-test cleanup failed: HTTP ${response.status}`);
}

try {
  const streamAccess = await request(`https://api.cloudflare.com/client/v4/accounts/${account}/stream?per_page=1`, {
    headers: { Authorization: `Bearer ${streamToken}` },
  });
  assert.ok(streamAccess.response.ok && streamAccess.body.success, 'Diagnostic token cannot inspect and clean up Cloudflare Stream');
  const movie = join(scratch, 'video.mp4');
  const generated = spawnSync('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=320x400:rate=24',
    '-t', '1', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', movie,
  ], { encoding: 'utf8' });
  assert.equal(generated.status, 0, 'Could not create synthetic test video');
  const data = await readFile(movie);

  const email = `captro-video-story-smoke-${crypto.randomUUID()}@captro.invalid`;
  const password = crypto.randomUUID() + crypto.randomUUID();
  const created = await request(`${supabase}/auth/v1/admin/users`, {
    method: 'POST', headers: { ...admin, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  assert.ok(created.response.ok && created.body.id, 'Could not create temporary test account');
  userId = created.body.id;
  const session = await request(`${supabase}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: publishableKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  assert.ok(session.response.ok && session.body.access_token, 'Could not sign in temporary test account');
  const bearer = { Authorization: `Bearer ${session.body.access_token}` };
  const profile = await request(`${api}/auth/me`, { headers: bearer });
  assert.equal(profile.response.status, 200, 'Temporary account cannot reach Captro');

  const intent = await request(`${api}/media/upload-intent`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ media_type: 'video', mime_type: 'video/mp4', filename: 'captro-story-smoke.mp4', file_size: data.byteLength, duration_seconds: 1, width: 320, height: 400 }),
  });
  console.log(JSON.stringify({ event: 'video_intent', status: intent.response.status, code: intent.body.code || null }));
  if (intent.response.status === 502) {
    const probe = await request(`https://api.cloudflare.com/client/v4/accounts/${account}/stream/direct_upload`, {
      method: 'POST', headers: { Authorization: `Bearer ${streamToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ maxDurationSeconds: 60, creator: userId, requireSignedURLs: false, meta: { userId, moderation: 'pre_publish', filename: 'captro-story-smoke.mp4' } }),
    });
    probeVideoId = String(probe.body.result?.uid || '');
    const providerMessage = String(probe.body.errors?.[0]?.message || '')
      .replace(/https?:\/\/\S+|[A-Za-z0-9_-]{40,}/g, '[redacted]').slice(0, 160);
    const uploadHost = (() => { try { return new URL(probe.body.result?.uploadURL).hostname; } catch { return null; } })();
    console.log(JSON.stringify({ event: 'stream_direct_probe', status: probe.response.status, success: probe.body.success === true, code: probe.body.errors?.[0]?.code || null, message: providerMessage, uploadHost, uidPresent: !!probeVideoId }));
  }
  assert.equal(intent.response.status, 201, 'Could not create video upload intent');
  const mediaId = intent.body.media_id;
  assert.ok(mediaId && intent.body.upload_url, 'Video intent lacked upload details');
  const asset = await request(`${supabase}/rest/v1/app_media_assets?id=eq.${mediaId}&select=storage_key`, { headers: admin });
  assert.ok(asset.response.ok && asset.body?.[0]?.storage_key, 'Could not identify temporary Stream video for cleanup');
  videoId = asset.body[0].storage_key;
  const form = new FormData();
  form.append('file', new Blob([data], { type: 'video/mp4' }), 'captro-story-smoke.mp4');
  const uploaded = await request(intent.body.upload_url, { method: 'POST', body: form });
  assert.ok(uploaded.response.ok, `Synthetic video upload failed: HTTP ${uploaded.response.status}`);

  let media = { body: { moderation_status: 'uploading' } };
  for (let i = 0; i < 36; i++) {
    media = await request(`${api}/media/complete`, {
      method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
      body: JSON.stringify({ media_id: mediaId, file_size: data.byteLength, duration_seconds: 1, caption: 'Temporary private video status test.' }),
    });
    if (media.body.moderation_status === 'approved' || ['rejected', 'review_required', 'failed'].includes(media.body.moderation_status)) break;
    await delay(5_000);
  }
  console.log(JSON.stringify({ event: 'video_moderation', status: media.response.status, moderation: media.body.moderation_status, code: media.body.rejection_code || null }));
  assert.equal(media.body.moderation_status, 'approved', 'Temporary video was not approved for Status');
  const status = await request(`${api}/media/${mediaId}/status`, { headers: bearer });
  assert.ok(status.response.ok && status.body.public_url, 'Approved video has no publication URL');
  const story = await request(`${api}/statuses`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ content: 'Temporary private video status test.', media_type: 'video', image: status.body.public_url, duration: 15, visibility: 'private' }),
  });
  console.log(JSON.stringify({ event: 'private_video_status', status: story.response.status, code: story.body.code || null, created: !!story.body.id }));
  assert.ok(story.response.ok && story.body.id, 'Could not publish approved video as private Status');
} finally {
  const failures = [];
  if (userId) {
    for (const url of [
      `${supabase}/rest/v1/app_stories?user_id=eq.${userId}`,
      `${supabase}/rest/v1/app_media_assets?user_id=eq.${userId}`,
      `${supabase}/rest/v1/app_users?id=eq.${userId}`,
      `${supabase}/auth/v1/admin/users/${userId}`,
    ]) {
      try { await remove(url); } catch (error) { failures.push(error); }
    }
  }
  if (videoId) {
    try {
      await remove(`https://api.cloudflare.com/client/v4/accounts/${account}/stream/${encodeURIComponent(videoId)}`, { Authorization: `Bearer ${streamToken}` });
    } catch (error) { failures.push(error); }
  }
  if (probeVideoId) {
    try {
      await remove(`https://api.cloudflare.com/client/v4/accounts/${account}/stream/${encodeURIComponent(probeVideoId)}`, { Authorization: `Bearer ${streamToken}` });
    } catch (error) { failures.push(error); }
  }
  await rm(scratch, { recursive: true, force: true });
  assert.equal(failures.length, 0, 'Temporary video, database rows, or account cleanup failed');
  console.log('Temporary private video Status, Stream asset, and test account removed.');
}
