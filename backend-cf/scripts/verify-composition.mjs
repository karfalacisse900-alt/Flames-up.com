import assert from 'node:assert/strict';

// Real deployed publishing contract, using only disposable accounts/private posts.
// Credentials are provided by the existing protected deployment environment.
for (const name of ['SUPABASE_PROJECT_REF', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ANON_KEY']) {
  assert.ok(process.env[name], `Missing ${name}`);
}
const base = `https://${process.env.SUPABASE_PROJECT_REF}.supabase.co`;
const api = 'https://flames-up-api.karfalacisse900.workers.dev/api';
const admin = { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' };
const users = [];
async function request(url, init = {}, expected = 200) {
  const response = await fetch(url, { ...init,
    headers: { Accept: 'application/json', 'Content-Type': 'application/json', ...init.headers },
    signal: AbortSignal.timeout(60_000) });
  if (response.status !== expected) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(`Composer contract HTTP ${response.status}, expected ${expected}, `
      + `path=${new URL(url).pathname}, code=${String(payload.code || 'unknown').slice(0, 100)}`);
  }
  return response.status === 204 ? null : response.json();
}
async function session() {
  const email = `captro-composer-smoke-${crypto.randomUUID()}@captro.invalid`;
  const password = crypto.randomUUID() + crypto.randomUUID();
  const user = await request(`${base}/auth/v1/admin/users`, { method: 'POST', headers: admin,
    body: JSON.stringify({ email, password, email_confirm: true }) });
  users.push(user.id);
  const auth = await request(`${base}/auth/v1/token?grant_type=password`, { method: 'POST',
    headers: { apikey: process.env.SUPABASE_ANON_KEY }, body: JSON.stringify({ email, password }) });
  const headers = { Authorization: `Bearer ${auth.access_token}` };
  await request(`${api}/auth/me`, { headers });
  return headers;
}
try {
  const owner = await session();
  const other = await session();
  const capabilities = await request(`${api}/posts/creation-capabilities`, { headers: owner });
  assert.deepEqual(new Set(capabilities.structured_types), new Set(['club', 'event', 'meetup', 'deal']));
  const body = { title: '', content: 'Looking for people who enjoy photography.\nLet us explore the city together.',
    post_type: 'general', visibility: 'private', images: [], media_types: [],
    creation_intent: 'looking_for', creation_time: '2026-10-10T19:00:00Z',
    post_response: { type: 'poll', options: ['Saturday', 'Sunday'] },
    client_request_id: `composer-smoke:${crypto.randomUUID()}` };
  const create = (value, status = 200) => request(`${api}/posts`, {
    method: 'POST', headers: owner, body: JSON.stringify(value) }, status);
  const first = await create(body);
  assert.ok(first.id);
  assert.equal((await create(body)).id, first.id, 'Retry created a duplicate');
  const read = await request(`${api}/posts/${first.id}`, { headers: owner });
  assert.equal(read.visibility, 'private');
  assert.equal(read.content, body.content, 'The message was rewritten');
  await request(`${api}/posts/${first.id}`, { headers: other }, 404);
  const metadata = async (id) => {
    const rows = await request(`${base}/rest/v1/app_posts?legacy_post_id=eq.${encodeURIComponent(id)}&select=metadata,visibility`, { headers: admin });
    assert.equal(rows.length, 1);
    assert.equal(rows[0].visibility, 'private');
    return rows[0].metadata;
  };
  const stored = await metadata(first.id);
  assert.equal(stored.creation_intent, 'looking_for');
  assert.equal(stored.creation_time, '2026-10-10T19:00:00.000Z');
  assert.deepEqual(stored.post_response.options, body.post_response.options);
  const concern = await create({ ...body, content: 'Please keep our public spaces clean.',
    creation_intent: 'concern', post_response: null, client_request_id: `composer-smoke:${crypto.randomUUID()}` });
  assert.equal((await metadata(concern.id)).creation_time, null, 'Hidden Concern schedule was submitted');
  await create({ ...body, content: 'a'.repeat(501), client_request_id: crypto.randomUUID() }, 400);
  await create({ ...body, creation_intent: 'post', client_request_id: crypto.randomUUID() }, 400);
  await create({ ...body, visibility: 'invalid', client_request_id: crypto.randomUUID() }, 400);
  await create({ ...body, content: ' \n ', post_response: null, client_request_id: crypto.randomUUID() }, 400);
  console.log(JSON.stringify({ deployedComposerContract: 'PASS', actualServerPublishing: true,
    retryIdempotent: true, originalMessagePreserved: true, privateVisibilityEnforced: true,
    intentAndTimePersisted: true, concernTimeExcluded: true, customChoicesPersisted: true,
    invalidInputRejected: true, productionCredentialsExposed: false }));
} finally {
  const failures = [];
  for (const user of users) {
    // IDs originate only from users created above; never touch existing users/content.
    for (const url of [`${base}/rest/v1/app_posts?user_id=eq.${user}`,
      `${base}/rest/v1/app_users?id=eq.${user}`, `${base}/auth/v1/admin/users/${user}`]) {
      const response = await fetch(url, { method: 'DELETE', headers: admin, signal: AbortSignal.timeout(30_000) });
      if (!response.ok) failures.push(response.status);
    }
  }
  if (failures.length) throw new Error(`Disposable composer cleanup failed: ${failures.join(',')}`);
  console.log('Disposable composer accounts and private test posts removed. No customer content changed.');
}
