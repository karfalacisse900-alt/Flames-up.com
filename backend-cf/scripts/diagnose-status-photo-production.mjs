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
const imagesToken = process.env.CLOUDFLARE_IMAGES_TOKEN || process.env.CLOUDFLARE_MEDIA_API_TOKEN;
assert.ok(project && serviceKey && publishableKey && account && imagesToken, 'Production photo-test credentials are required');

const supabase = `https://${project}.supabase.co`;
const api = 'https://flames-up-api.karfalacisse900.workers.dev/api';
const admin = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
const scratch = await mkdtemp(join(tmpdir(), 'captro-story-photo-'));
let userId = '';
let mediaId = '';
let imageId = '';

async function request(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: { 'User-Agent': 'Captro-Photo-Status-Diagnostic/1.0', ...init.headers },
    signal: AbortSignal.timeout(60_000),
  });
  const body = response.headers.get('content-type')?.includes('application/json')
    ? await response.json().catch(() => ({})) : {};
  return { response, body };
}

async function remove(url, headers = admin) {
  const { response } = await request(url, { method: 'DELETE', headers });
  if (!response.ok) throw new Error(`Temporary photo-test cleanup failed: HTTP ${response.status}`);
}

try {
  const email = `captro-photo-story-smoke-${crypto.randomUUID()}@captro.invalid`;
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

  const photo = join(scratch, 'photo.png');
  const generated = spawnSync('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=320x400:rate=1',
    '-frames:v', '1', '-threads', '1', photo,
  ], { encoding: 'utf8' });
  assert.equal(generated.status, 0, 'Could not create synthetic test photo');
  const data = await readFile(photo);
  const intent = await request(`${api}/media/upload-intent`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ media_type: 'image', mime_type: 'image/png', filename: 'captro-story-smoke.png', file_size: data.byteLength, width: 320, height: 400 }),
  });
  console.log(JSON.stringify({ event: 'photo_intent', status: intent.response.status, code: intent.body.code || null }));
  assert.equal(intent.response.status, 201, 'Could not create photo upload intent');
  mediaId = intent.body.media_id;
  assert.ok(mediaId && intent.body.upload_url, 'Photo intent lacked upload details');
  const asset = await request(`${supabase}/rest/v1/app_media_assets?id=eq.${mediaId}&select=storage_key`, { headers: admin });
  assert.ok(asset.response.ok && asset.body?.[0]?.storage_key, 'Could not identify temporary Cloudflare image for cleanup');
  imageId = asset.body[0].storage_key;
  const form = new FormData();
  form.append('file', new Blob([data], { type: 'image/png' }), 'captro-story-smoke.png');
  const uploaded = await request(intent.body.upload_url, { method: 'POST', body: form });
  assert.ok(uploaded.response.ok, `Synthetic photo upload failed: HTTP ${uploaded.response.status}`);
  let media = await request(`${api}/media/complete`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ media_id: mediaId, file_size: data.byteLength, width: 320, height: 400, caption: 'Temporary private photo status test.' }),
  });
  for (let i = 0; i < 12 && ['uploading', 'pending_moderation'].includes(media.body.moderation_status); i++) {
    await delay(3_000);
    media = await request(`${api}/media/${mediaId}/status`, { headers: bearer });
  }
  console.log(JSON.stringify({ event: 'photo_moderation', status: media.response.status, moderation: media.body.moderation_status, code: media.body.rejection_code || null }));
  assert.equal(media.body.moderation_status, 'approved', 'Temporary photo was not approved for Status');
  assert.ok(media.body.public_url, 'Approved photo has no publication URL');
  const story = await request(`${api}/statuses`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ content: 'Temporary private photo status test.', media_type: 'image', image: media.body.public_url, visibility: 'private' }),
  });
  console.log(JSON.stringify({ event: 'private_photo_status', status: story.response.status, code: story.body.code || null, created: !!story.body.id }));
  assert.ok(story.response.ok && story.body.id, 'Could not publish approved photo as private Status');
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
  if (imageId) {
    try {
      await remove(`https://api.cloudflare.com/client/v4/accounts/${account}/images/v1/${encodeURIComponent(imageId)}`, { Authorization: `Bearer ${imagesToken}` });
    } catch (error) { failures.push(error); }
  }
  await rm(scratch, { recursive: true, force: true });
  assert.equal(failures.length, 0, 'Temporary photo, database rows, or account cleanup failed');
  console.log('Temporary private photo Status, provider image, and test account removed.');
}
