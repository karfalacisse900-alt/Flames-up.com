import assert from 'node:assert/strict';

const base = `https://${process.env.SUPABASE_PROJECT_REF}.supabase.co`;
const api = 'https://flames-up-api.karfalacisse900.workers.dev/api';
const admin = { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' };
const users = [];
const clientHeaders = { Accept: 'application/json', 'Content-Type': 'application/json', 'User-Agent': 'Captro-Release-Smoke/1.0' };
async function request(url, init = {}, expected = 200) {
  const response = await fetch(url, { ...init, headers: { ...clientHeaders, ...init.headers }, signal: AbortSignal.timeout(60_000) });
  if (response.status !== expected) throw new Error(`Event smoke: HTTP ${response.status} (expected ${expected}) at ${new URL(url).pathname}`);
  if (expected === 204) return null;
  return response.json();
}
async function session() {
  const email = `captro-event-smoke-${crypto.randomUUID()}@captro.invalid`;
  const password = crypto.randomUUID() + crypto.randomUUID();
  const user = await request(`${base}/auth/v1/admin/users`, { method: 'POST', headers: admin, body: JSON.stringify({ email, password, email_confirm: true }) });
  users.push(user.id);
  const auth = await request(`${base}/auth/v1/token?grant_type=password`, { method: 'POST',
    headers: { apikey: process.env.SUPABASE_ANON_KEY }, body: JSON.stringify({ email, password }) });
  const headers = { Authorization: `Bearer ${auth.access_token}` };
  await request(`${api}/auth/me`, { headers });
  return headers;
}
try {
  const owner = await session();
  const stranger = await session();
  const event = { starts_at: '2026-10-10T19:00:00-04:00', ends_at: '2026-10-10T22:00:00-04:00',
    time_zone: 'America/New_York', venue_name: 'Public venue', city: 'New York', price: '12.50', currency: 'USD', attendance_enabled: true };
  const body = { title: 'Private event editor check', content: 'Temporary private release test.', post_type: 'meetup',
    visibility: 'private', images: [], media_types: [], event, client_request_id: `event-smoke:${crypto.randomUUID()}` };
  const create = () => request(`${api}/posts`, { method: 'POST', headers: owner, body: JSON.stringify(body) });
  const post = await create();
  assert.ok(post.id);
  assert.equal(post.detail.event.price, '12.50');
  assert.equal((await create()).id, post.id, 'Duplicate post created on retry');
  const read = () => request(`${api}/posts/${post.id}`, { headers: owner });
  const stored = await read();
  assert.equal(stored.detail.event.startsAt, '2026-10-10T23:00:00.000Z');
  await request(`${api}/posts/${post.id}/attendance`, { method: 'POST', headers: owner, body: '{"going":true}' });
  const edited = { ...event, price: '18.00', starts_at: '2026-10-10T20:00:00-04:00',
    code: 'MUST-NOT-BECOME-A-TICKET', attendees_count: 999, verified: true };
  await request(`${api}/posts/${post.id}/event`, { method: 'PUT', headers: stranger, body: JSON.stringify(edited) }, 403);
  await request(`${api}/posts/${post.id}/event`, { method: 'PUT', headers: owner, body: JSON.stringify({ ...edited, price: '-2' }) }, 400);
  assert.equal((await read()).detail.event.price, '12.50', 'Failed edit changed the post');
  await request(`${api}/posts/${post.id}/event`, { method: 'PUT', headers: owner, body: JSON.stringify(edited) });
  const updated = await read();
  assert.equal(updated.detail.event.price, '18.00');
  assert.equal(updated.detail.event.startsAt, '2026-10-11T00:00:00.000Z');
  assert.equal(updated.detail.event.attendeesCount, 1);
  assert.equal(updated.detail.event.viewerGoing, true);
  assert.equal(updated.visibility, 'private');
  assert.doesNotMatch(JSON.stringify(updated.detail), /MUST-NOT-BECOME|999|verified/);
  assert.equal((await request(`${api}/posts/${post.id}/object`, { headers: owner })).ticket, null);
  await request(`${api}/posts/${post.id}/ticket`, { headers: owner }, 404);
  await request(`${api}/posts/${post.id}`, { headers: stranger }, 404);
  console.log(JSON.stringify({ event: 'event_editor_production_passed', privatePost: true,
    createReadback: true, retryIdempotent: true, ownerEditReadback: true, otherAccountDenied: true,
    invalidEditRejected: true, attendancePreserved: true, noTicketInvented: true }));
} finally {
  const failures = [];
  for (const user of users) {
    // Only this run's temporary accounts and their private posts are touched.
    for (const url of [`${base}/rest/v1/app_posts?user_id=eq.${user}`, `${base}/rest/v1/app_users?id=eq.${user}`, `${base}/auth/v1/admin/users/${user}`]) {
      const response = await fetch(url, { method: 'DELETE', headers: admin, signal: AbortSignal.timeout(30_000) });
      if (!response.ok) failures.push(response.status);
    }
  }
  if (failures.length) throw new Error(`Temporary event cleanup failed: ${failures.join(',')}`);
  console.log('Temporary event users and private posts cleaned up.');
}
