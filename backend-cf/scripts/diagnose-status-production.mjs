import assert from 'node:assert/strict';

const project = process.env.SUPABASE_PROJECT_REF;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const publishableKey = process.env.SUPABASE_ANON_KEY;
assert.ok(project && serviceKey && publishableKey, 'Supabase test credentials are required');

const supabase = `https://${project}.supabase.co`;
const api = 'https://flames-up-api.karfalacisse900.workers.dev/api';
const admin = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
const userAgent = { 'User-Agent': 'Captro-Status-Diagnostic/1.0' };
let userId = '';

async function request(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: { ...userAgent, ...init.headers },
    signal: AbortSignal.timeout(30_000),
  });
  const body = response.headers.get('content-type')?.includes('application/json')
    ? await response.json()
    : {};
  return { response, body };
}

async function remove(url) {
  const { response } = await request(url, { method: 'DELETE', headers: admin });
  if (!response.ok) throw new Error(`Temporary test cleanup failed: HTTP ${response.status}`);
}

try {
  const email = `captro-status-smoke-${crypto.randomUUID()}@captro.invalid`;
  const password = crypto.randomUUID() + crypto.randomUUID();
  const created = await request(`${supabase}/auth/v1/admin/users`, {
    method: 'POST', headers: { ...admin, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  assert.ok(created.response.ok, 'Could not create temporary test account');
  userId = created.body.id;
  assert.ok(userId);

  const session = await request(`${supabase}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: publishableKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  assert.ok(session.response.ok, 'Could not sign in temporary test account');
  const bearer = { Authorization: `Bearer ${session.body.access_token}` };
  const profile = await request(`${api}/auth/me`, { headers: bearer });
  assert.equal(profile.response.status, 200, 'Temporary account cannot reach Captro');

  const result = await request(`${api}/statuses`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ content: 'Temporary private status publication check.', media_type: 'text', visibility: 'private' }),
  });
  console.log(JSON.stringify({
    event: 'private_status_diagnostic',
    httpStatus: result.response.status,
    code: result.body.code || null,
    detail: String(result.body.detail || '').slice(0, 180),
    created: !!result.body.id,
  }));
  assert.ok(result.response.ok, 'A harmless private Status was not created');
  assert.ok(result.body.id, 'Successful Status response lacked an ID');
  const threat = await request(`${api}/statuses`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ content: 'I am going to hurt you tonight.', media_type: 'text', visibility: 'private' }),
  });
  console.log(JSON.stringify({ event: 'private_status_threat_check', httpStatus: threat.response.status, created: !!threat.body.id }));
  assert.equal(threat.response.status, 409, 'A synthetic threat must not be published');
  assert.equal(!!threat.body.id, false, 'A synthetic threat unexpectedly created a Status');
} finally {
  if (userId) {
    // The account and its private fixture are created solely for this run.
    await remove(`${supabase}/rest/v1/app_stories?user_id=eq.${userId}`);
    await remove(`${supabase}/rest/v1/app_users?id=eq.${userId}`);
    await remove(`${supabase}/auth/v1/admin/users/${userId}`);
    console.log('Temporary private Status and test account removed.');
  }
}
