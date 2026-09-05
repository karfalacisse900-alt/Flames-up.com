// Real Captro Worker, local Supabase Auth/Postgres and real Stripe sandbox APIs.
// This is API integration coverage, NOT native PaymentSheet/onboarding UI acceptance.
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';

const processes = [];
function start(command, args, options = {}) {
  const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'], detached: true, ...options });
  child.output = '';
  for (const stream of [child.stdout, child.stderr]) stream.on('data', bytes => {
    child.output = (child.output + bytes.toString()).slice(-50_000);
  });
  child.on('error', error => { child.startError = error.code; });
  processes.push(child);
  return child;
}

async function json(url, init = {}, expected = 200) {
  const response = await fetch(url, { ...init, redirect: 'error', signal: AbortSignal.timeout(30_000) });
  const data = await response.json().catch(() => ({}));
  if (response.status !== expected) {
    const code = String(data.code || data.error?.code || data.error?.type || 'unknown').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 100);
    throw new Error(`${new URL(url).pathname}: HTTP ${response.status}, ${code}`);
  }
  return data;
}

async function main() {
  assert.equal(process.env.GITHUB_ACTIONS, 'true');
  assert.equal(process.platform, 'linux');
  assert.equal(process.env.STRIPE_MODE, 'test');
  assert.match(process.env.STRIPE_SECRET_KEY || '', /^(sk|rk)_test_/);
  assert.match(process.env.STRIPE_PUBLISHABLE_KEY || '', /^pk_test_/);
  const local = JSON.parse(await readFile(join(process.env.RUNNER_TEMP, 'supabase-status.json'), 'utf8'));
  assert.ok(['127.0.0.1', 'localhost'].includes(new URL(local.API_URL).hostname));
  const api = 'http://127.0.0.1:8788/api';
  const listener = start('stripe', ['listen', '--forward-to', `${api}/stripe/webhook`, '--forward-connect-to', `${api}/stripe/connect-webhook`], {
    env: { ...process.env, STRIPE_API_KEY: process.env.STRIPE_SECRET_KEY },
  });
  let signingSecret;
  for (let i = 0; i < 45; i++) {
    signingSecret = listener.output.match(/whsec_[a-zA-Z0-9]+/)?.[0];
    if (signingSecret) break;
    assert.ok(listener.exitCode === null && !listener.startError, 'Stripe webhook listener failed to start');
    await sleep(1000);
  }
  assert.ok(signingSecret, 'Stripe must supply the real forwarding signature secret');
  const directory = join(process.env.RUNNER_TEMP, 'captro-worker');
  await mkdir(directory);
  const config = {
    name: 'captro-payments-ephemeral', main: resolve('src/index.ts'), compatibility_date: '2024-12-01',
    compatibility_flags: ['nodejs_compat'],
    d1_databases: [{ binding: 'DB', database_name: 'captro-payments-ephemeral', database_id: '00000000-0000-0000-0000-000000000001' }],
    kv_namespaces: [{ binding: 'KV', id: '00000000000000000000000000000001' }],
    vars: { ENVIRONMENT: 'test', STRIPE_MODE: 'test', DATABASE_PRIMARY: 'supabase_postgres', SUPABASE_URL: local.API_URL,
      FRONTEND_URL: 'https://captro.app', CAPTRO_SERVICE_FEE_BPS: '500', CAPTRO_SERVICE_FEE_FIXED_CENTS: '50',
      CAPTRO_PAYOUT_FEE_POLICY: 'platform_absorbs' },
  };
  await writeFile(join(directory, 'wrangler.json'), JSON.stringify(config));
  const secrets = {
    SUPABASE_ANON_KEY: local.ANON_KEY, SUPABASE_SERVICE_ROLE_KEY: local.SERVICE_ROLE_KEY,
    STRIPE_SECRET_KEY: process.env.STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY: process.env.STRIPE_PUBLISHABLE_KEY,
    STRIPE_WEBHOOK_SECRET: signingSecret, STRIPE_CONNECT_WEBHOOK_SECRET: signingSecret,
    CAPTRO_TICKET_SIGNING_SECRET: randomBytes(32).toString('hex'), JWT_SECRET: randomBytes(32).toString('hex'),
  };
  await writeFile(join(directory, '.dev.vars'), Object.entries(secrets).map(([key, value]) => `${key}=${JSON.stringify(value)}`).join('\n'), { mode: 0o600 });
  const worker = start(process.execPath, [resolve('node_modules/wrangler/bin/wrangler.js'), 'dev', '--config', join(directory, 'wrangler.json'), '--local', '--ip', '127.0.0.1', '--port', '8788'], {
    env: { ...process.env, WRANGLER_SEND_METRICS: 'false', CI: 'true' },
  });
  let healthy = false;
  for (let i = 0; i < 60; i++) {
    healthy = await fetch('http://127.0.0.1:8788/', { signal: AbortSignal.timeout(1000) }).then(r => r.ok).catch(() => false);
    if (healthy) break;
    assert.ok(worker.exitCode === null && !worker.startError, 'Isolated Worker failed to start');
    await sleep(1000);
  }
  assert.ok(healthy, 'Isolated Worker must start');
  const admin = { apikey: local.SERVICE_ROLE_KEY, Authorization: `Bearer ${local.SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' };
  const email = `captro-sandbox-${process.env.GITHUB_RUN_ID}@example.com`;
  const password = randomBytes(32).toString('hex');
  const user = await json(`${local.API_URL}/auth/v1/admin/users`, {
    method: 'POST', headers: admin, body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { full_name: 'Captro Sandbox Creator' } }),
  });
  const session = await json(`${local.API_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: local.ANON_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }),
  });
  const authorized = { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' };
  await json(`${api}/auth/me`, { headers: authorized });
  await json(`${api}/commerce/payout-account`, {}, 401);
  const capabilities = await json(`${api}/commerce/stripe-capabilities`, { headers: authorized });
  assert.equal(capabilities.liveMode, false);
  assert.equal(capabilities.connectAvailable, true);
  await json(`${api}/stripe/webhook`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }, 400);
  const before = await json(`${api}/commerce/payout-account`, { headers: authorized });
  assert.equal(before.account.ready, false);
  const setup = await json(`${api}/commerce/payout-account/onboarding-link`, {
    method: 'POST', headers: authorized, body: '{}',
  });
  assert.equal(new URL(setup.url).protocol, 'https:');
  assert.equal(new URL(setup.url).hostname, 'connect.stripe.com');
  const accounts = await json(`${local.API_URL}/rest/v1/app_connected_accounts?user_id=eq.${user.id}`, { headers: admin });
  assert.equal(accounts.length, 1);
  const account = await json(`https://api.stripe.com/v1/accounts/${accounts[0].provider_account_id}`, {
    headers: { Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}` },
  });
  assert.equal(account.type, 'express');
  assert.equal(accounts[0].charges_enabled, account.charges_enabled);
  assert.equal(accounts[0].payouts_enabled, account.payouts_enabled);
  assert.equal(accounts[0].details_submitted, account.details_submitted);
  console.log(JSON.stringify({ realWorker: true, realSupabaseAuth: true, unsignedWebhookRejected: true,
    stripeConnectAccountCreated: true, connectedAccountId: account.id, hostedOnboardingLinkCreated: true,
    payoutsReady: setup.account.ready, requiredFields: account.requirements?.currently_due,
    nativePaymentSheetValidated: false, paymentCompleted: false,
    note: 'Actual Connect onboarding is required. No success flags or money records were fabricated.' }));
  // This empty sandbox account belongs only to this disposable run, not a real creator.
  await json(`https://api.stripe.com/v1/accounts/${account.id}`, {
    method: 'DELETE', headers: { Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}` },
  });
}

try { await main(); }
catch (error) {
  console.error(`Stripe API integration incomplete: ${error.message}`);
  process.exitCode = 1;
} finally {
  for (const child of processes.reverse()) {
    if (!child.pid || child.exitCode !== null) continue;
    try { process.kill(-child.pid, 'SIGTERM'); } catch {}
    await Promise.race([new Promise(resolve => child.once('close', resolve)), sleep(5000)]);
    try { process.kill(-child.pid, 'SIGKILL'); } catch {}
  }
}
