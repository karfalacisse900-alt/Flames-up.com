import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

// Tests the real moderated upload -> private post -> PostgreSQL -> API path.
// Never alters customer records, permission rules, or moderation decisions.
const api = 'https://flames-up-api.karfalacisse900.workers.dev/api';
const db = `https://${process.env.SUPABASE_PROJECT_REF}.supabase.co`;
const admin = { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}` };
let owner, appOwner, token, assetID, postID;
async function request(url, method = 'GET', body, headers = {}) {
  const response = await fetch(url, { method, headers: { 'Content-Type': 'application/json', ...headers },
    body: body == null ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(60000) });
  if (!response.ok) throw new Error(`Framing verification ${method} ${new URL(url).pathname}: HTTP ${response.status}`);
  const text = await response.text(); return text ? JSON.parse(text) : null;
}
try {
  const credentials = { email: `captro-framing-${randomUUID()}@captro.invalid`, password: randomUUID() + randomUUID() };
  const user = await request(`${db}/auth/v1/admin/users`, 'POST', { ...credentials, email_confirm: true }, admin);
  owner = user.id; assert.match(owner, /^[a-f0-9-]{36}$/);
  const session = await request(`${api}/auth/login`, 'POST', credentials);
  token = session.access_token; appOwner = session.user.id;
  console.log(`::add-mask::${token}`);
  const auth = { Authorization: `Bearer ${token}` };
  // Licensed temporary landscape/architecture input, private post only.
  const photo = await fetch('https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?fit=crop&w=720&h=1280&fm=jpg&q=85');
  assert.ok(photo.ok); const bytes = await photo.arrayBuffer();
  const intent = await request(`${api}/media/upload-intent`, 'POST', {
    media_type: 'image', filename: 'captro-framing-test.jpg', mime_type: 'image/jpeg', file_size: bytes.byteLength, width: 720, height: 1280,
  }, auth);
  assetID = intent.media_id;
  assert.ok(assetID && intent.upload_url);
  const multipart = new FormData(); multipart.append('file', new Blob([bytes], { type: 'image/jpeg' }), 'captro-framing-test.jpg');
  const upload = await fetch(intent.upload_url, { method: 'POST', body: multipart, signal: AbortSignal.timeout(60000) });
  assert.ok(upload.ok, 'Provider upload failed');
  const completion = { media_id: assetID, file_size: bytes.byteLength, width: 720, height: 1280 };
  let status = await request(`${api}/media/complete`, 'POST', completion, auth);
  for (let attempt = 0; attempt < 40 && status.moderation_status !== 'approved'; attempt++) {
    assert.ok(!['failed', 'rejected', 'review_required'].includes(status.moderation_status), 'Moderation did not approve the test input');
    await delay(1500);
    status = await request(`${api}/media/${assetID}/status`, 'GET', undefined, auth);
  }
  assert.equal(status.moderation_status, 'approved');
  const original = new URL(status.public_url); original.search = ''; original.hash = '';
  const framing = { version: 1, sourceAspectRatio: 9/16, displayAspectRatio: 0.8, cropX: 0.5, cropY: 0.77,
    mediaId: createHash('sha256').update(original.toString()).digest('hex') };
  const posted = await request(`${api}/posts`, 'POST', {
    title: '', content: 'Private media framing verification', visibility: 'private', post_type: 'general',
    image: status.public_url, images: [status.public_url], media_types: ['image'], media_asset_ids: [assetID],
    media_dimensions: [{ width: 720, height: 1280, ratio: 9/16, original_width: 720, original_height: 1280, framing }],
    client_request_id: randomUUID(),
  }, auth);
  postID = posted.id; assert.ok(postID);
  const detail = await request(`${api}/posts/${postID}`, 'GET', undefined, auth);
  const dimensions = typeof detail.media_dimensions === 'string' ? JSON.parse(detail.media_dimensions) : detail.media_dimensions;
  assert.deepEqual(dimensions[0].framing, framing, 'Details must return the exact selected crop');
  assert.equal(dimensions[0].original_width, 720);
  assert.equal(dimensions[0].original_height, 1280);
  const rows = await request(`${db}/rest/v1/app_posts?id=eq.${postID}&select=media_dimensions,visibility,user_id`, 'GET', undefined, admin);
  assert.equal(rows.length, 1); assert.equal(rows[0].user_id, owner); assert.equal(rows[0].visibility, 'private');
  assert.deepEqual(rows[0].media_dimensions[0].framing, framing, 'PostgreSQL must retain crop metadata');
  const feed = await request(`${api}/posts/feed?scope=for_you&limit=50`, 'GET', undefined, auth);
  const item = feed.find(p => p.id === postID); assert.ok(item, 'Owner feed must contain its private test post');
  const feedDimensions = typeof item.media_dimensions === 'string' ? JSON.parse(item.media_dimensions) : item.media_dimensions;
  assert.deepEqual(feedDimensions[0].framing, framing, 'Home and Details must receive identical framing');
  console.log(JSON.stringify({ mediaFraming: 'PASS', moderatedUpload: true, privatePost: true,
    databaseRoundTrip: true, homeDetailsMatch: true, originalDimensionsPreserved: true }));
} finally {
  if (assetID && appOwner) {
    const assets = await request(`${db}/rest/v1/app_media_assets?id=eq.${assetID}&user_id=eq.${appOwner}&select=storage_key`, 'GET', undefined, admin);
    for (const asset of assets) {
      assert.match(asset.storage_key, /^[a-zA-Z0-9-]+$/);
      const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${process.env.CLOUDFLARE_ACCOUNT_ID}/images/v1/${asset.storage_key}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${process.env.CLOUDFLARE_IMAGES_TOKEN || process.env.CLOUDFLARE_API_TOKEN}` } });
      assert.ok(response.ok || response.status === 404, 'Temporary image cleanup failed');
    }
  }
  if (owner) {
    await request(`${db}/rest/v1/app_posts?user_id=eq.${owner}`, 'DELETE', undefined, admin);
    if (appOwner) {
      await request(`${db}/rest/v1/app_media_assets?user_id=eq.${appOwner}`, 'DELETE', undefined, admin);
      await request(`${db}/rest/v1/app_account_identities?user_id=eq.${appOwner}`, 'DELETE', undefined, admin);
      await request(`${db}/rest/v1/app_users?id=eq.${appOwner}`, 'DELETE', undefined, admin);
    }
    if (token) await request(`${db}/auth/v1/logout?scope=global`, 'POST', undefined,
      { apikey: process.env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}` });
    await request(`${db}/auth/v1/admin/users/${owner}`, 'DELETE', undefined, admin);
    console.log('Removed only the disposable framing account, private post and test upload.');
  }
}
