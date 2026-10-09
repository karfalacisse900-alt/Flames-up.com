import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { join } from 'node:path';

// Protected simulator acceptance setup. Only this script's disposable owner
// and its private posts/assets can be removed. Never logs bearer credentials.
const folder = process.env.COVER_TEST_FOLDER;
assert.ok(folder, 'An isolated test folder is required');
const base = `https://${process.env.SUPABASE_PROJECT_REF}.supabase.co`;
const api = 'https://flames-up-api.karfalacisse900.workers.dev/api';
const admin = { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' };
assert.ok(process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.SUPABASE_ANON_KEY, 'Protected test credentials required');
async function request(url, init = {}) {
  const response = await fetch(url, { ...init, headers: { 'Content-Type': 'application/json', ...init.headers }, signal: AbortSignal.timeout(60_000) });
  if (!response.ok) throw new Error(`Cover test HTTP ${response.status} at ${new URL(url).pathname}`);
  return response.status === 204 ? null : response.json();
}
const sessionFile = join(folder, 'cover-session.json');
const mode = process.argv[2];
if (mode === 'prepare') {
  await mkdir(folder, { recursive: true });
  const email = `captro-cover-runtime-${crypto.randomUUID()}@captro.invalid`;
  const password = crypto.randomUUID() + crypto.randomUUID();
  const user = await request(`${base}/auth/v1/admin/users`, { method: 'POST', headers: admin,
    body: JSON.stringify({ email, password, email_confirm: true }) });
  // Persist cleanup identity immediately, even if later setup fails.
  await writeFile(sessionFile, JSON.stringify({ email, authID: user.id, userID: user.id }), { mode: 0o600 });
  const auth = await request(`${base}/auth/v1/token?grant_type=password`, { method: 'POST',
    headers: { apikey: process.env.SUPABASE_ANON_KEY }, body: JSON.stringify({ email, password }) });
  console.log(`::add-mask::${auth.access_token}`);
  const me = await request(`${api}/auth/me`, { headers: { Authorization: `Bearer ${auth.access_token}` } });
  await writeFile(sessionFile, JSON.stringify({ email, authID: user.id, userID: me.id, token: auth.access_token }), { mode: 0o600 });
  await request(`${base}/rest/v1/app_users?id=eq.${me.id}`, { method: 'PATCH', headers: admin,
    body: JSON.stringify({ full_name: 'Captro Cover QA', username: `cover_qa_${user.id.replaceAll('-', '').slice(0, 10)}` }) });
  // Licensed test input only. Unsplash license: https://unsplash.com/license.
  // These photographs are not bundled in the production app or made public.
  const photographs = {
    'fashion.jpg': 'photo-1483985988355-763728e1935b',
    'nightlife.jpg': 'photo-1514525253161-7a46d19cd819',
    'dining.jpg': 'photo-1414235077428-338989a2e8c0',
    'travel.jpg': 'photo-1496442226666-8d4d0e62e6e9',
    'photography.jpg': 'photo-1470071459604-3b5ec3a7fe05',
  };
  for (const [name, id] of Object.entries(photographs)) {
    const response = await fetch(`https://images.unsplash.com/${id}?auto=format&fit=max&w=1080&q=85&fm=jpg`, { signal: AbortSignal.timeout(60_000) });
    assert.ok(response.ok && response.headers.get('content-type')?.startsWith('image/'), 'Licensed test photograph unavailable');
    await writeFile(join(folder, name), Buffer.from(await response.arrayBuffer()));
  }
  if (process.env.COVER_SIM_DOCUMENTS) {
    for (const name of ['cover-session.json', ...Object.keys(photographs)]) await copyFile(join(folder, name), join(process.env.COVER_SIM_DOCUMENTS, name));
  }
  console.log('Prepared one disposable account and licensed private Cover test inputs.');
} else {
  const session = JSON.parse(await readFile(sessionFile, 'utf8'));
  assert.match(session.email, /^captro-cover-runtime-[a-f0-9-]+@captro\.invalid$/);
  assert.match(session.authID, /^[a-f0-9-]{36}$/);
  const user = await request(`${base}/auth/v1/admin/users/${session.authID}`, { headers: admin });
  assert.equal(user.email, session.email, 'Cleanup identity did not match the account created by this test');
  if (mode === 'verify') {
    const posts = await request(`${base}/rest/v1/app_posts?user_id=eq.${session.userID}&select=metadata,editor_data,visibility`, { headers: admin });
    assert.ok(posts.length >= 7, 'Native app did not publish all seven real Cover examples');
    assert.ok(posts.some(post => post.editor_data?.overlays?.filter(o => o.type === 'media_writing').length === 2),
      'Per-photo carousel overlays were not persisted');
    for (const post of posts) {
      assert.equal(post.visibility, 'private');
      assert.equal(post.metadata.creation_intent, 'cover');
      const overlays = post.editor_data?.overlays;
      assert.ok(overlays?.length, 'Published Cover lost its overlay metadata');
      for (const overlay of overlays.filter(o => o.type === 'media_writing')) {
        assert.equal(overlay.writing.schemaVersion, 2);
        assert.equal(overlay.writing.showsStamp, false);
        assert.ok(overlay.writing.text.length > 0 && overlay.writing.text.length <= 70);
        assert.ok(Math.abs(overlay.writing.y - .46) < .00001,
          'The current slightly-above-center Cover placement changed in persistence');
      }
    }
    console.log(JSON.stringify({ realNativeCoverPublishing: 'PASS', privateExamples: posts.length,
      overlayPersisted: true, coverPlacementPreserved: true, noCompetingStamp: true,
      sourceRevision: process.env.GITHUB_SHA }));
  } else if (mode === 'cleanup') {
    const assets = await request(`${base}/rest/v1/app_media_assets?user_id=eq.${session.userID}&select=storage_provider,storage_key,media_type`, { headers: admin });
    for (const asset of assets) {
      const video = asset.media_type === 'video';
      const token = video ? (process.env.CLOUDFLARE_STREAM_TOKEN || process.env.CLOUDFLARE_API_TOKEN)
        : (process.env.CLOUDFLARE_IMAGES_TOKEN || process.env.CLOUDFLARE_API_TOKEN);
      assert.ok(token && process.env.CLOUDFLARE_ACCOUNT_ID, 'Asset cleanup authorization missing');
      assert.match(asset.storage_key, /^[a-zA-Z0-9-]+$/, 'Unexpected test asset identity');
      await request(`https://api.cloudflare.com/client/v4/accounts/${process.env.CLOUDFLARE_ACCOUNT_ID}/${video ? 'stream' : 'images/v1'}/${asset.storage_key}`,
        { method: 'DELETE', headers: { Authorization: `Bearer ${token}` } });
    }
    for (const path of [`app_posts?user_id=eq.${session.userID}`, `app_media_assets?user_id=eq.${session.userID}`, `app_users?id=eq.${session.userID}`]) {
      await request(`${base}/rest/v1/${path}`, { method: 'DELETE', headers: admin });
    }
    await request(`${base}/auth/v1/admin/users/${session.authID}`, { method: 'DELETE', headers: admin });
    console.log('Removed this test’s private Cover posts, Cloudflare media and disposable account. No customer content changed.');
  } else { throw new Error('Unknown Cover test phase'); }
}
