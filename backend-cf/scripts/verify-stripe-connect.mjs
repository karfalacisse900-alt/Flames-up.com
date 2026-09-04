import assert from 'node:assert/strict';

const supabase = `https://${process.env.SUPABASE_PROJECT_REF}.supabase.co`;
const api = 'https://api.flames-up.com/api';
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const anonKey = process.env.SUPABASE_ANON_KEY;
const adminHeaders = {
  apikey: serviceKey,
  Authorization: `Bearer ${serviceKey}`,
  'Content-Type': 'application/json',
};
const clientHeaders = {
  Accept: 'application/json',
  'Content-Type': 'application/json',
  'User-Agent': 'Captro-Release-Smoke/1.0',
};

let userId = '';

async function request(url, init = {}, expected = 200) {
  const response = await fetch(url, {
    ...init,
    headers: { ...clientHeaders, ...init.headers },
    signal: AbortSignal.timeout(60_000),
  });
  const payload = await response.json().catch(() => ({}));
  if (response.status !== expected) {
    throw new Error(`Stripe Connect smoke returned HTTP ${response.status} at ${new URL(url).pathname}`);
  }
  return payload;
}

try {
  const email = `captro-stripe-smoke-${crypto.randomUUID()}@captro.invalid`;
  const password = crypto.randomUUID() + crypto.randomUUID();
  const created = await request(`${supabase}/auth/v1/admin/users`, {
    method: 'POST',
    headers: adminHeaders,
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  userId = created.id;
  assert.ok(userId, 'Temporary Stripe smoke user was not created');

  const session = await request(`${supabase}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: anonKey },
    body: JSON.stringify({ email, password }),
  });
  const authHeaders = { Authorization: `Bearer ${session.access_token}` };
  await request(`${api}/auth/me`, { headers: authHeaders });

  const capabilities = await request(`${api}/commerce/stripe-capabilities`, { headers: authHeaders });
  assert.equal(capabilities.configured, true, 'Production Stripe secret is not configured');
  assert.equal(capabilities.liveMode, true, 'Production is using a Stripe test key instead of a live key');
  assert.equal(capabilities.webhookConfigured, true, 'Production Stripe account webhook signing secret is not configured');
  assert.equal(capabilities.connectWebhookConfigured, true, 'Production Stripe connected-account webhook signing secret is not configured');
  assert.equal(capabilities.apiReachable, true, 'Production Stripe account API is not reachable');
  assert.equal(capabilities.connectAvailable, true, 'Stripe Connect is not available to Captro');

  const webhookProbe = await request(`${api}/stripe/webhook`, {
    method: 'POST',
    body: '{}',
  }, 400);
  assert.equal(webhookProbe.code, 'STRIPE_SIGNATURE_INVALID', 'Stripe webhook route is not enforcing signatures');

  const payout = await request(`${api}/commerce/payout-account`, { headers: authHeaders });
  assert.equal(payout.account?.stripeConfigured, true);
  assert.equal(payout.account?.status, 'not_started');
  assert.equal(payout.account?.bank, null);

  console.log('Production live Stripe and Connect APIs are reachable; account and connected-account webhook secrets are configured; signatures are enforced.');
} finally {
  if (userId) {
    await fetch(`${supabase}/rest/v1/app_users?id=eq.${userId}`, {
      method: 'DELETE', headers: adminHeaders, signal: AbortSignal.timeout(30_000),
    });
    const cleanup = await fetch(`${supabase}/auth/v1/admin/users/${userId}`, {
      method: 'DELETE', headers: adminHeaders, signal: AbortSignal.timeout(30_000),
    });
    if (!cleanup.ok) throw new Error(`Temporary Stripe smoke user cleanup failed with HTTP ${cleanup.status}`);
  }
}
