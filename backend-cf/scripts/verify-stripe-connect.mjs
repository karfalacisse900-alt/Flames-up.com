import assert from 'node:assert/strict';

const supabase = `https://${process.env.SUPABASE_PROJECT_REF}.supabase.co`;
const api = process.env.CAPTRO_STRIPE_SMOKE_BASE_URL || 'https://flames-up-api.karfalacisse900.workers.dev/api';
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const anonKey = process.env.SUPABASE_ANON_KEY;
const stripeKey = process.env.STRIPE_SECRET_KEY;
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
    const code = typeof payload?.code === 'string' ? payload.code.slice(0, 80) : '';
    const detail = typeof payload?.detail === 'string' ? payload.detail.slice(0, 180) : '';
    const diagnostic = [code, detail].filter(Boolean).join(': ');
    throw new Error(`Stripe Connect smoke returned HTTP ${response.status} at ${new URL(url).pathname}${diagnostic ? ` (${diagnostic})` : ''}`);
  }
  return payload;
}

async function stripeRequest(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${stripeKey}`,
      ...init.headers,
    },
    signal: AbortSignal.timeout(30_000),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const type = typeof payload?.error?.type === 'string' ? payload.error.type.slice(0, 80) : 'stripe_error';
    const code = typeof payload?.error?.code === 'string' ? payload.error.code.slice(0, 80) : '';
    const param = typeof payload?.error?.param === 'string' ? payload.error.param.slice(0, 120) : '';
    throw new Error(`Live payout onboarding probe failed with HTTP ${response.status}: ${[type, code, param].filter(Boolean).join(':')}`);
  }
  return payload;
}

try {
  assert.match(stripeKey || '', /^sk_live_|^rk_live_/, 'Live Stripe key is required for the payout onboarding probe');
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
  assert.equal(payout.account?.payoutCard, null);

  const connectedResponse = await fetch(
    `${supabase}/rest/v1/app_connected_accounts?stripe_mode=eq.live&select=provider_account_id&order=updated_at.desc&limit=1`,
    { headers: adminHeaders, signal: AbortSignal.timeout(30_000) },
  );
  assert.equal(connectedResponse.ok, true, `Could not load the live payout-account probe target (${connectedResponse.status})`);
  const connectedAccounts = await connectedResponse.json();
  if (connectedAccounts.length > 0) {
    const account = connectedAccounts[0].provider_account_id;
    assert.match(account, /^acct_[A-Za-z0-9]+$/);

    const sessionBody = new URLSearchParams({
      account,
      'components[account_onboarding][enabled]': 'true',
      'components[account_onboarding][features][external_account_collection]': 'true',
      'components[account_onboarding][features][disable_stripe_user_authentication]': 'false',
    });
    const accountSession = await stripeRequest('https://api.stripe.com/v1/account_sessions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: sessionBody,
    });
    assert.equal(accountSession.object, 'account_session');
    assert.equal(accountSession.livemode, true);
    assert.ok(typeof accountSession.client_secret === 'string' && accountSession.client_secret.length > 20);

    const accountLink = await stripeRequest('https://api.stripe.com/v2/core/account_links', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Stripe-Version': '2026-08-26.dahlia',
      },
      body: JSON.stringify({
        account,
        use_case: {
          type: 'account_onboarding',
          account_onboarding: {
            collection_options: { fields: 'currently_due' },
            configurations: ['recipient'],
            refresh_url: `${api}/commerce/payout-account/onboarding-refresh`,
            return_url: `${api}/commerce/payout-account/onboarding-complete`,
          },
        },
      }),
    });
    assert.ok(typeof accountLink.url === 'string' && accountLink.url.startsWith('https://'));
    console.log('Live native and hosted payout onboarding sessions were created for an existing Captro recipient account.');
  } else {
    console.log('No live recipient exists yet; payout onboarding creation probe was skipped.');
  }

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
