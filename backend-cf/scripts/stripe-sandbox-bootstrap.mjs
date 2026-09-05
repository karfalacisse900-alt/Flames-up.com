// Runs only on an ephemeral GitHub runner. Never connects to Captro production.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

async function main() {
  assert.equal(process.env.GITHUB_ACTIONS, 'true');
  assert.equal(process.env.STRIPE_MODE, 'test');
  assert.ok(/^(sk|rk)_test_/.test(process.env.STRIPE_SECRET_KEY || ''), 'A sandbox secret key is required');
  assert.ok(/^pk_test_/.test(process.env.STRIPE_PUBLISHABLE_KEY || ''), 'A sandbox publishable key is required');
  const local = JSON.parse(await readFile(join(process.env.RUNNER_TEMP, 'supabase-status.json'), 'utf8'));
  const api = new URL(local.API_URL);
  assert.equal(api.protocol, 'http:');
  assert.ok(['localhost', '127.0.0.1'].includes(api.hostname));
  assert.ok(local.SERVICE_ROLE_KEY);
  const headers = { apikey: local.SERVICE_ROLE_KEY, Authorization: `Bearer ${local.SERVICE_ROLE_KEY}` };
  const migration = await fetch(new URL('/rest/v1/app_payment_environment?select=*', api), {
    headers, signal: AbortSignal.timeout(30_000), redirect: 'error',
  });
  assert.equal(migration.status, 200, 'Payment migrations must be applied to the local stack');
  assert.deepEqual(await migration.json(), [], 'A fresh database must not inherit a payment mode or money records');
  const provision = await fetch(new URL('/rest/v1/app_payment_environment', api), {
    method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: true, stripe_mode: 'test' }),
    signal: AbortSignal.timeout(30_000), redirect: 'error',
  });
  assert.equal(provision.status, 201);
  for (const path of ['/account', '/accounts?limit=1']) {
    const result = await fetch(`https://api.stripe.com/v1${path}`, {
      headers: { Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}` },
      signal: AbortSignal.timeout(30_000), redirect: 'error',
    });
    assert.equal(result.status, 200, `Stripe sandbox ${path} must be accessible`);
    const data = await result.json();
    assert.ok(path === '/account' ? data.id?.startsWith('acct_') : Array.isArray(data.data));
  }
  const evidence = {
    isolatedDatabase: true, paymentSchema: true, stripeMode: 'test', stripeAuthenticated: true,
    connectReadAPI: true, paymentCompleted: false, nativePaymentSheetValidated: false,
    note: 'Bootstrap evidence only. No charge, ticket, earning or payout has been created.',
  };
  console.log(JSON.stringify(evidence));
  await writeFile(join(process.env.RUNNER_TEMP, 'stripe-sandbox-bootstrap.json'), JSON.stringify(evidence, null, 2));
}

main().catch(error => {
  // Do not dump provider bodies, environment values or child-process output with credentials.
  console.error(`Sandbox bootstrap incomplete: ${error.message}`);
  process.exitCode = 1;
});
