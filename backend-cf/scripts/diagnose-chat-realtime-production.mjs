import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

const project = process.env.SUPABASE_PROJECT_REF;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const publishableKey = process.env.SUPABASE_ANON_KEY;
assert.ok(project && serviceKey && publishableKey, 'Supabase test credentials are required');

const supabase = `https://${project}.supabase.co`;
const api = 'https://flames-up-api.karfalacisse900.workers.dev/api';
const admin = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
const users = [];
const sockets = [];
let messageId = '';

async function request(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: { 'User-Agent': 'Captro-Realtime-Diagnostic/1.0', ...init.headers },
    signal: AbortSignal.timeout(30_000),
  });
  const body = response.headers.get('content-type')?.includes('application/json')
    ? await response.json().catch(() => ({})) : {};
  return { response, body };
}

async function testUser() {
  const email = `captro-realtime-smoke-${crypto.randomUUID()}@captro.invalid`;
  const password = crypto.randomUUID() + crypto.randomUUID();
  const created = await request(`${supabase}/auth/v1/admin/users`, {
    method: 'POST', headers: { ...admin, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  assert.ok(created.response.ok && created.body.id, 'Could not create temporary Realtime user');
  const user = { id: created.body.id, token: '' };
  users.push(user);
  const session = await request(`${supabase}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: publishableKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  assert.ok(session.response.ok && session.body.access_token, 'Could not sign in temporary Realtime user');
  user.token = session.body.access_token;
  const profile = await request(`${api}/auth/me`, { headers: { Authorization: `Bearer ${user.token}` } });
  assert.equal(profile.response.status, 200, 'Temporary Realtime user cannot reach Captro');
  return user;
}

function subscribe(user, receiverId, label) {
  const topic = `realtime:captro-smoke-${label}-${crypto.randomUUID()}`;
  const socket = new WebSocket(`wss://${project}.supabase.co/realtime/v1/websocket?apikey=${encodeURIComponent(publishableKey)}&vsn=1.0.0`);
  sockets.push(socket);
  const events = [];
  let readyResolve;
  let readyReject;
  const ready = new Promise((resolve, reject) => { readyResolve = resolve; readyReject = reject; });
  const timeout = setTimeout(() => readyReject(new Error(`${label} Postgres Changes did not become ready`)), 25_000);
  socket.addEventListener('open', () => {
    socket.send(JSON.stringify({
      topic, event: 'phx_join', ref: '1', join_ref: '1',
      payload: {
        access_token: user.token,
        config: {
          broadcast: { ack: false, self: false }, presence: { enabled: false }, private: false,
          postgres_changes: [{ event: 'INSERT', schema: 'public', table: 'app_messages', filter: `receiver_id=eq.${receiverId}`, select: ['id', 'sender_id', 'receiver_id'] }],
        },
      },
    }));
  });
  socket.addEventListener('message', (event) => {
    let frame;
    try { frame = JSON.parse(String(event.data)); } catch { return; }
    if (frame.event === 'phx_reply' && frame.ref === '1' && frame.payload?.status === 'error') {
      clearTimeout(timeout);
      readyReject(new Error(`${label} Realtime join was rejected`));
    }
    if (frame.event === 'system' && frame.payload?.extension === 'postgres_changes' && frame.payload?.status === 'ok') {
      clearTimeout(timeout);
      readyResolve();
    }
    if (frame.event === 'postgres_changes') {
      const id = frame.payload?.data?.record?.id || frame.payload?.record?.id;
      if (id) events.push({ id, at: performance.now() });
    }
  });
  socket.addEventListener('error', () => readyReject(new Error(`${label} Realtime socket failed`)));
  socket.addEventListener('close', () => readyReject(new Error(`${label} Realtime socket closed`)));
  return { ready, events };
}

async function remove(url) {
  const { response } = await request(url, { method: 'DELETE', headers: admin });
  if (!response.ok) throw new Error(`Temporary Realtime cleanup failed: HTTP ${response.status}`);
}

try {
  const sender = await testUser();
  const receiver = await testUser();
  const outsider = await testUser();
  const recipientChannel = subscribe(receiver, receiver.id, 'recipient');
  const outsiderChannel = subscribe(outsider, receiver.id, 'outsider');
  await Promise.all([recipientChannel.ready, outsiderChannel.ready]);

  messageId = crypto.randomUUID();
  const started = performance.now();
  const inserted = await request(`${supabase}/rest/v1/app_messages`, {
    method: 'POST', headers: { ...admin, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
    body: JSON.stringify({ id: messageId, sender_id: sender.id, receiver_id: receiver.id, body: 'Temporary private Realtime delivery check.' }),
  });
  assert.ok(inserted.response.ok, 'Could not insert temporary private message');

  for (let i = 0; i < 100 && !recipientChannel.events.some((event) => event.id === messageId); i++) await delay(100);
  const arrivals = recipientChannel.events.filter((event) => event.id === messageId);
  assert.equal(arrivals.length, 1, 'Recipient did not receive exactly one authorized Realtime message');
  const latencyMs = Math.round(arrivals[0].at - started);
  const receiverRead = await request(`${supabase}/rest/v1/app_messages?id=eq.${messageId}&select=id`, {
    headers: { apikey: publishableKey, Authorization: `Bearer ${receiver.token}` },
  });
  const outsiderRead = await request(`${supabase}/rest/v1/app_messages?id=eq.${messageId}&select=id`, {
    headers: { apikey: publishableKey, Authorization: `Bearer ${outsider.token}` },
  });
  assert.ok(receiverRead.response.ok && receiverRead.body?.length === 1, 'Recipient cannot read authorized message');
  assert.ok(outsiderRead.response.ok && outsiderRead.body?.length === 0, 'Unrelated account can read private message');
  await delay(1_000);
  assert.equal(outsiderChannel.events.some((event) => event.id === messageId), false, 'Unrelated account received a private Realtime event');
  assert.equal(recipientChannel.events.filter((event) => event.id === messageId).length, 1, 'Realtime duplicated the message');
  console.log(JSON.stringify({ event: 'chat_realtime_diagnostic', authorizedDeliveryMs: latencyMs, recipientEvents: 1, outsiderEvents: 0, recipientRead: true, outsiderRead: false }));
} finally {
  for (const socket of sockets) {
    try { socket.close(); } catch { /* A failed connection still needs database cleanup. */ }
  }
  const failures = [];
  if (messageId) {
    try { await remove(`${supabase}/rest/v1/app_messages?id=eq.${messageId}`); } catch (error) { failures.push(error); }
  }
  for (const user of users) {
    for (const url of [
      `${supabase}/rest/v1/app_users?id=eq.${user.id}`,
      `${supabase}/auth/v1/admin/users/${user.id}`,
    ]) {
      try { await remove(url); } catch (error) { failures.push(error); }
    }
  }
  assert.equal(failures.length, 0, 'Temporary Realtime message or test account cleanup failed');
  console.log('Temporary private message and Realtime test accounts removed.');
}
