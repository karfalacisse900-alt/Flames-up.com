// Real Captro Worker, local Supabase Auth/Postgres and real Stripe sandbox APIs.
// The native PaymentSheet UI remains a separate device acceptance check.
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';

const processes = [];
const cleanupAccounts = new Set();
const cleanupPrices = new Set();
const cleanupProducts = new Set();
const STRIPE_ACCOUNTS_V2_VERSION = '2026-08-26.dahlia';

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
  const expectedStatuses = Array.isArray(expected) ? expected : [expected];
  if (!expectedStatuses.includes(response.status)) {
    const code = String(data.code || data.error?.code || data.error?.type || 'unknown').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 100);
    const parsedUrl = new URL(url);
    const providerReason = parsedUrl.hostname === 'api.stripe.com'
      ? String(data.error?.message || '')
        .replace(/https?:\/\/\S+/gi, '[url]')
        .replace(/\b(?:sk|rk|pk|whsec)_(?:test|live)?_?[a-zA-Z0-9]+\b/g, '[credential]')
        .replace(/\b(?:acct|pi|ch|po|pm|card|cus|prod|price|req)_[a-zA-Z0-9]+\b/g, '[provider-id]')
        .replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi, '[email]')
        .replace(/[^\x20-\x7E]/g, ' ')
        .trim()
        .slice(0, 300)
      : '';
    throw new Error(`${parsedUrl.pathname}: HTTP ${response.status}, ${code}${providerReason ? `, ${providerReason}` : ''}`);
  }
  return data;
}

async function stripe(path, { method = 'GET', params, connectedAccount } = {}) {
  const headers = { Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}` };
  if (connectedAccount) headers['Stripe-Account'] = connectedAccount;
  const init = { method, headers };
  if (params) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    init.body = new URLSearchParams(Object.entries(params)
      .filter(([, value]) => value !== undefined && value !== null)
      .map(([key, value]) => [key, String(value)])).toString();
  }
  return json(`https://api.stripe.com/v1${path}`, init);
}

async function stripeV2(path, payload, idempotencyKey) {
  const headers = {
    Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}`,
    'Content-Type': 'application/json',
    'Stripe-Version': STRIPE_ACCOUNTS_V2_VERSION,
  };
  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;
  return json(`https://api.stripe.com/v2${path}`, {
    method: 'POST', headers, body: JSON.stringify(payload),
  });
}

async function stripeV2Get(path, includes = []) {
  const url = new URL(`https://api.stripe.com/v2${path}`);
  includes.forEach((value, index) => url.searchParams.set(`include[${index}]`, value));
  return json(url, {
    headers: {
      Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}`,
      'Stripe-Version': STRIPE_ACCOUNTS_V2_VERSION,
    },
  });
}

function recipientAccountPayload({ email, displayName, dashboard, metadata }) {
  return {
    contact_email: email,
    display_name: displayName,
    dashboard,
    identity: { country: 'us' },
    configuration: {
      recipient: {
        capabilities: {
          stripe_balance: { stripe_transfers: { requested: true } },
        },
      },
    },
    defaults: {
      currency: 'usd',
      responsibilities: { fees_collector: 'application', losses_collector: 'application' },
      locales: ['en-US'],
      profile: { product_description: 'Sales and paid access through Captro' },
    },
    metadata,
    include: ['configuration.recipient', 'identity', 'requirements', 'defaults'],
  };
}

function recipientOnboardingPayload(account, refreshUrl, returnUrl) {
  return {
    account,
    use_case: {
      type: 'account_onboarding',
      account_onboarding: {
        collection_options: { fields: 'eventually_due' },
        configurations: ['recipient'],
        refresh_url: refreshUrl,
        return_url: returnUrl,
      },
    },
  };
}

async function waitFor(label, callback, attempts = 60, delay = 1000) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const result = await callback();
    if (result) return result;
    await sleep(delay);
  }
  throw new Error(`${label.replace(/[^a-zA-Z0-9 _-]/g, '').slice(0, 100)} timed out`);
}

async function probePlatformPaymentIntent() {
  try {
    const intent = await stripe('/payment_intents', {
      method: 'POST',
      params: {
        amount: 2000,
        currency: 'usd',
        'automatic_payment_methods[enabled]': true,
        'metadata[captro_test_run_id]': process.env.GITHUB_RUN_ID,
        'metadata[captro_probe]': 'buyer_payment_intent',
      },
    });
    assert.ok(String(intent.id || '').startsWith('pi_'));
    await stripe(`/payment_intents/${intent.id}/cancel`, { method: 'POST' });
    console.log(JSON.stringify({
      event: 'stripe_platform_payment_probe',
      paymentIntentId: intent.id,
      amount: intent.amount,
      currency: intent.currency,
      created: true,
      canceled: true,
    }));
    return true;
  } catch (error) {
    console.log(JSON.stringify({
      event: 'stripe_platform_payment_probe',
      created: false,
      code: String(error?.message || 'STRIPE_PAYMENT_INTENT_CREATE_FAILED')
        .replace(/[^a-zA-Z0-9_ -]/g, '').slice(0, 120),
    }));
    return false;
  }
}

async function createLocalUser(local, admin, api, label) {
  const suffix = `${process.env.GITHUB_RUN_ID}-${label}-${randomBytes(4).toString('hex')}`;
  const email = `captro-sandbox-${suffix}@example.com`;
  const password = randomBytes(32).toString('hex');
  const authUser = await json(`${local.API_URL}/auth/v1/admin/users`, {
    method: 'POST', headers: admin,
    body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { full_name: `Captro Sandbox ${label}` } }),
  });
  const session = await json(`${local.API_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: local.ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const authorized = { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' };
  await json(`${api}/auth/me`, { headers: authorized });
  const rows = await json(`${local.API_URL}/rest/v1/app_users?supabase_user_id=eq.${authUser.id}&select=*`, { headers: admin });
  assert.equal(rows.length, 1, 'Captro auth must create exactly one app user');
  const username = `sandbox_${label}_${String(process.env.GITHUB_RUN_ID).slice(-8)}_${randomBytes(2).toString('hex')}`;
  const updated = await json(`${local.API_URL}/rest/v1/app_users?id=eq.${encodeURIComponent(rows[0].id)}`, {
    method: 'PATCH', headers: { ...admin, Prefer: 'return=representation' },
    body: JSON.stringify({ username, full_name: `Captro Sandbox ${label}`, phone_verified: true }),
  });
  return { authUser, appUser: updated[0] || rows[0], authorized, email };
}

async function createReadyTestConnectedAccount(creator) {
  const created = await stripeV2('/core/accounts', recipientAccountPayload({
    email: creator.email,
    displayName: 'Captro Sandbox Creator',
    dashboard: 'none',
    metadata: {
      captro_auth_user_id: creator.authUser.id,
      captro_app_user_id: creator.appUser.id,
      captro_test_run_id: process.env.GITHUB_RUN_ID,
    },
  }), `captro-ready-account-${process.env.GITHUB_RUN_ID}-${creator.authUser.id}`);
  assert.ok(created.id?.startsWith('acct_'), 'Stripe must create the disposable payment connected account');
  cleanupAccounts.add(created.id);
  await stripe(`/accounts/${created.id}`, {
    method: 'POST',
    params: {
      email: creator.email,
      business_type: 'individual',
      'business_profile[mcc]': '7299',
      'business_profile[name]': 'Captro Sandbox Creator',
      'business_profile[product_description]': 'Disposable Captro payment integration test',
      'business_profile[support_email]': creator.email,
      'business_profile[support_phone]': '8888675309',
      'business_profile[support_url]': 'https://captro.app',
      'business_profile[url]': 'https://captro.app',
      'individual[first_name]': 'Jenny',
      'individual[last_name]': 'Rosen',
      'individual[email]': creator.email,
      'individual[phone]': '8888675309',
      'individual[dob][day]': 1,
      'individual[dob][month]': 1,
      'individual[dob][year]': 1990,
      'individual[address][line1]': 'address_full_match',
      'individual[address][city]': 'Schenectady',
      'individual[address][state]': 'NY',
      'individual[address][postal_code]': '12345',
      'individual[ssn_last_4]': '0000',
      'individual[id_number]': '000000000',
      'individual[political_exposure]': 'none',
      'tos_acceptance[date]': Math.floor(Date.now() / 1000),
      'tos_acceptance[ip]': '127.0.0.1',
      'tos_acceptance[user_agent]': 'Captro Stripe sandbox integration',
      'settings[payouts][schedule][interval]': 'manual',
      external_account: 'tok_visa_debit_us_transferSuccess',
      'metadata[captro_auth_user_id]': creator.authUser.id,
      'metadata[captro_app_user_id]': creator.appUser.id,
      'metadata[captro_test_run_id]': process.env.GITHUB_RUN_ID,
    },
  });
  let lastReadiness = null;
  for (let attempt = 0; attempt < 90; attempt++) {
    const account = await stripe(`/accounts/${created.id}?expand[]=external_accounts`);
    const accountV2 = await stripeV2Get(`/core/accounts/${created.id}`, [
      'configuration.recipient', 'requirements', 'defaults', 'identity',
    ]);
    const transferCapability = accountV2.configuration?.recipient?.capabilities
      ?.stripe_balance?.stripe_transfers;
    const cards = account.external_accounts?.data || [];
    const debit = cards.find(card => card.object === 'card' && card.funding === 'debit'
      && card.available_payout_methods?.includes('instant'));
    if (account.details_submitted && transferCapability?.status === 'active' && account.payouts_enabled
        && account.requirements?.currently_due?.length === 0 && debit) return { account, debit };
    lastReadiness = {
      detailsSubmitted: account.details_submitted === true,
      transfersEnabled: account.capabilities?.transfers === 'active',
      recipientTransferStatus: String(transferCapability?.status || '').slice(0, 40),
      recipientTransferStatusDetails: (transferCapability?.status_details || [])
        .map(value => String(value?.code || '').slice(0, 80)),
      payoutsEnabled: account.payouts_enabled === true,
      currentlyDue: (account.requirements?.currently_due || []).map(value => String(value).slice(0, 80)),
      pendingVerification: (account.requirements?.pending_verification || []).map(value => String(value).slice(0, 80)),
      disabledReason: String(account.requirements?.disabled_reason || '').slice(0, 80),
      cardAttached: cards.some(card => card.object === 'card' && card.funding === 'debit'),
      instantCardEligible: Boolean(debit),
      capabilities: Object.fromEntries(Object.entries(account.capabilities || {}).map(([key, value]) => [key, String(value).slice(0, 40)])),
    };
    await sleep(1000);
  }
  throw new Error(`Stripe test connected account not ready: ${JSON.stringify(lastReadiness)}`);
}

async function main() {
  assert.equal(process.env.GITHUB_ACTIONS, 'true');
  assert.equal(process.env.STRIPE_MODE, 'test');
  assert.ok(/^acct_[A-Za-z0-9]+$/.test(process.env.STRIPE_EXPECTED_ACCOUNT_ID || ''), 'The expected sandbox account ID is required');
  assert.ok(/^(sk|rk)_test_/.test(process.env.STRIPE_SECRET_KEY || ''), 'A sandbox secret key is required');
  assert.ok(/^pk_test_/.test(process.env.STRIPE_PUBLISHABLE_KEY || ''), 'A sandbox publishable key is required');
  const platformAccount = await stripe('/account');
  assert.equal(platformAccount.id, process.env.STRIPE_EXPECTED_ACCOUNT_ID, 'Stripe credentials target the wrong platform account');
  console.log(JSON.stringify({
    event: 'stripe_platform_verified',
    accountId: platformAccount.id,
    displayName: String(platformAccount.settings?.dashboard?.display_name
      || platformAccount.business_profile?.name || '').slice(0, 120) || null,
    mode: 'test',
  }));
  await probePlatformPaymentIntent();
  assert.equal(process.platform, 'linux');
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

  // Verify Captro's real production onboarding path without automating or bypassing hosted identity collection.
  const onboardingUser = await createLocalUser(local, admin, api, 'onboarding');
  await json(`${api}/commerce/payout-account`, {}, 401);
  const capabilities = await json(`${api}/commerce/stripe-capabilities`, { headers: onboardingUser.authorized });
  assert.equal(capabilities.liveMode, false);
  assert.equal(capabilities.connectAvailable, true);
  await json(`${api}/stripe/webhook`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }, 400);
  const before = await json(`${api}/commerce/payout-account`, { headers: onboardingUser.authorized });
  assert.equal(before.account.ready, false);
  let setup;
  try {
    setup = await json(`${api}/commerce/payout-account/onboarding-link`, {
      method: 'POST', headers: onboardingUser.authorized, body: '{}',
    });
  } catch (error) {
    const failedRows = await json(`${local.API_URL}/rest/v1/app_connected_accounts?user_id=eq.${onboardingUser.authUser.id}`, { headers: admin });
    const failedAccountId = String(failedRows[0]?.provider_account_id || '');
    if (failedAccountId.startsWith('acct_')) {
      cleanupAccounts.add(failedAccountId);
      try {
        await stripeV2('/core/account_links', recipientOnboardingPayload(
          failedAccountId,
          'https://captro.app/earnings/payouts/refresh',
          'https://captro.app/earnings/payouts/complete',
        ));
      } catch (providerError) {
        throw new Error(`${error.message}; Stripe diagnostic: ${providerError.message}`);
      }
    } else {
      try {
        const diagnosticAccount = await stripeV2('/core/accounts', recipientAccountPayload({
          email: onboardingUser.email,
          displayName: 'Captro Sandbox Onboarding',
          dashboard: 'express',
          metadata: {
            captro_test_run_id: process.env.GITHUB_RUN_ID,
            captro_diagnostic: 'connected_account_creation',
          },
        }));
        if (String(diagnosticAccount.id || '').startsWith('acct_')) cleanupAccounts.add(diagnosticAccount.id);
      } catch (providerError) {
        throw new Error(`${error.message}; Stripe diagnostic: ${providerError.message}`);
      }
    }
    throw error;
  }
  assert.equal(new URL(setup.url).protocol, 'https:');
  assert.ok(new Set(['accounts.stripe.com', 'connect.stripe.com']).has(new URL(setup.url).hostname));
  const onboardingRows = await json(`${local.API_URL}/rest/v1/app_connected_accounts?user_id=eq.${onboardingUser.authUser.id}`, { headers: admin });
  assert.equal(onboardingRows.length, 1);
  const onboardingAccount = await stripe(`/accounts/${onboardingRows[0].provider_account_id}`);
  cleanupAccounts.add(onboardingAccount.id);
  assert.equal(onboardingRows[0].account_type, 'express');
  assert.equal(onboardingRows[0].charges_enabled, onboardingAccount.charges_enabled);
  assert.equal(onboardingRows[0].payouts_enabled, onboardingAccount.payouts_enabled);
  assert.equal(onboardingRows[0].details_submitted, onboardingAccount.details_submitted);

  // A disposable platform-controlled v2 recipient lets CI exercise money movement without fabricating hosted onboarding success.
  const creator = await createLocalUser(local, admin, api, 'creator');
  const buyer = await createLocalUser(local, admin, api, 'buyer');
  const readyStripe = await createReadyTestConnectedAccount(creator);
  const connectedRows = await json(`${local.API_URL}/rest/v1/app_connected_accounts?on_conflict=provider_account_id`, {
    method: 'POST', headers: { ...admin, Prefer: 'resolution=merge-duplicates,return=representation' },
    body: JSON.stringify({ user_id: creator.authUser.id, app_user_id: creator.appUser.id,
      provider_account_id: readyStripe.account.id, account_type: 'custom' }),
  }, [200, 201]);
  assert.equal(connectedRows.length, 1);
  const payoutAccount = await json(`${api}/commerce/payout-account`, { headers: creator.authorized });
  assert.equal(payoutAccount.account.ready, true);
  assert.equal(payoutAccount.account.payoutCard?.instantPayoutEligible, true);

  const startsAt = new Date(Date.now() + 7 * 86400_000).toISOString();
  const endsAt = new Date(Date.now() + 7 * 86400_000 + 3 * 3600_000).toISOString();
  const post = await json(`${api}/posts`, {
    method: 'POST', headers: creator.authorized,
    body: JSON.stringify({
      client_request_id: randomUUID(), post_type: 'event', title: 'Captro Sandbox Event',
      content: 'Disposable real Stripe test-mode purchase and payout.', visibility: 'public',
      commerce: { enabled: true, contentType: 'event', paymentModel: 'paid', commerceClass: 'outside_app',
        title: 'Captro Sandbox Event', description: 'Sandbox event', locationName: 'Captro Test Venue',
        city: 'New York', startsAt, endsAt, capacity: 2, passRequired: true,
        prices: [{ label: 'General Admission', unitAmount: 2000, capacity: 2 }] },
    }),
  });
  assert.ok(post.id, 'Captro must create the paid event post');
  const commerce = await json(`${api}/commerce/posts/${encodeURIComponent(post.id)}`, { headers: creator.authorized });
  assert.equal(commerce.commerce.paymentModel, 'paid');
  assert.equal(commerce.commerce.lowestPrice.unitAmount, 2000);
  assert.equal(commerce.commerce.lowestPrice.serviceFeeAmount, 150);
  assert.equal(commerce.commerce.lowestPrice.buyerTotal, 2150);
  const purchasableRows = await json(`${local.API_URL}/rest/v1/app_purchasables?id=eq.${commerce.commerce.id}&select=*`, { headers: admin });
  const priceRows = await json(`${local.API_URL}/rest/v1/app_prices?purchasable_id=eq.${commerce.commerce.id}&select=*`, { headers: admin });
  assert.ok(purchasableRows[0]?.stripe_product_id?.startsWith('prod_'));
  assert.ok(priceRows[0]?.stripe_price_id?.startsWith('price_'));
  cleanupProducts.add(purchasableRows[0].stripe_product_id);
  cleanupPrices.add(priceRows[0].stripe_price_id);
  console.log(JSON.stringify({ event: 'stripe_catalog_fixture_created',
    productId: purchasableRows[0].stripe_product_id, priceId: priceRows[0].stripe_price_id,
    productName: 'Captro Sandbox Event', cleanup: 'archive' }));

  const paymentRequestId = randomUUID();
  const paymentBody = { contentId: post.id, contentType: 'event', quantity: 1,
    selectedPriceId: commerce.commerce.lowestPrice.id, idempotencyKey: paymentRequestId };
  let checkout;
  try {
    checkout = await json(`${api}/payments/create`, {
      method: 'POST', headers: buyer.authorized, body: JSON.stringify(paymentBody),
    });
  } catch (error) {
    const diagnostic = worker.output.split(/\r?\n/)
      .filter(line => line.includes('commerce_purchase_begin_failed'))
      .slice(-1)[0];
    throw new Error(`${error.message}${diagnostic ? `; Worker diagnostic: ${diagnostic}` : ''}`);
  }
  assert.equal(checkout.purchase.itemAmount, 2000);
  assert.equal(checkout.purchase.creatorAmount, 2000);
  assert.equal(checkout.purchase.serviceFeeAmount, 150);
  assert.equal(checkout.purchase.totalAmount, 2150);
  assert.equal(checkout.paymentSheet.mode, 'test');
  assert.ok(checkout.paymentSheet.paymentIntentClientSecret?.startsWith('pi_'));
  const replay = await json(`${api}/payments/create`, {
    method: 'POST', headers: buyer.authorized, body: JSON.stringify(paymentBody),
  });
  assert.equal(replay.purchase.id, checkout.purchase.id, 'Payment request IDs must be idempotent');
  assert.equal(replay.paymentSheet.paymentIntentClientSecret, checkout.paymentSheet.paymentIntentClientSecret);
  const paymentIntentId = checkout.paymentSheet.paymentIntentClientSecret.split('_secret_')[0];
  const confirmedIntent = await stripe(`/payment_intents/${paymentIntentId}/confirm`, {
    method: 'POST', params: { payment_method: 'pm_card_bypassPending', return_url: 'https://captro.app/payments/return' },
  });
  assert.equal(confirmedIntent.status, 'succeeded');

  let purchase;
  try {
    purchase = await waitFor('signed payment webhook confirmation', async () => {
      const rows = await json(`${local.API_URL}/rest/v1/app_purchases?id=eq.${checkout.purchase.id}&select=*`, { headers: admin });
      return rows[0]?.status === 'confirmed' ? rows[0] : null;
    });
  } catch {
    const purchaseRows = await json(`${local.API_URL}/rest/v1/app_purchases?id=eq.${checkout.purchase.id}&select=status,provider_payment_id,stripe_destination_account_id,creator_amount,total_amount,currency`, { headers: admin });
    const webhookRows = await json(`${local.API_URL}/rest/v1/app_payment_webhook_events?select=event_type,status,error_code,provider_event_id&order=created_at.desc&limit=100`, { headers: admin });
    const providerEvents = await stripe('/events?type=payment_intent.succeeded&limit=20');
    const providerEvent = providerEvents.data?.find(event => event.data?.object?.id === paymentIntentId);
    const currentIntent = await stripe(`/payment_intents/${paymentIntentId}?expand[]=latest_charge.balance_transaction`);
    const chargeId = typeof currentIntent.latest_charge === 'string'
      ? currentIntent.latest_charge : currentIntent.latest_charge?.id;
    const currentCharge = chargeId ? await stripe(`/charges/${chargeId}?expand[]=balance_transaction`) : null;
    const transferGroup = currentIntent.transfer_group;
    const groupedTransfers = transferGroup ? await stripe(`/transfers?transfer_group=${encodeURIComponent(transferGroup)}&limit=10`) : null;
    throw new Error(`Payment confirmation evidence: ${JSON.stringify({
      purchase: purchaseRows[0] || null,
      providerEvent: providerEvent ? { id: providerEvent.id, type: providerEvent.type, pendingWebhooks: providerEvent.pending_webhooks } : null,
      intent: { id: currentIntent.id, status: currentIntent.status, transferGroup: transferGroup || null,
        latestChargeId: chargeId || null },
      charge: currentCharge ? { id: currentCharge.id, status: currentCharge.status,
        balanceTransactionId: typeof currentCharge.balance_transaction === 'string'
          ? currentCharge.balance_transaction : currentCharge.balance_transaction?.id || null,
        transferId: typeof currentCharge.transfer === 'string' ? currentCharge.transfer : currentCharge.transfer?.id || null } : null,
      groupedTransfers: (groupedTransfers?.data || []).map(transfer => ({ id: transfer.id,
        destination: typeof transfer.destination === 'string' ? transfer.destination : transfer.destination?.id || null,
        sourceTransaction: typeof transfer.source_transaction === 'string'
          ? transfer.source_transaction : transfer.source_transaction?.id || null,
        amount: transfer.amount, currency: transfer.currency })),
      webhookAudit: webhookRows.filter(row => row.event_type?.startsWith('payment_intent.')).slice(0, 10),
    })}`);
  }
  assert.equal(purchase.provider_payment_id, paymentIntentId);
  assert.equal(purchase.creator_amount, 2000);
  const payments = await json(`${local.API_URL}/rest/v1/app_payments?purchase_id=eq.${purchase.id}&select=*`, { headers: admin });
  const entitlements = await json(`${local.API_URL}/rest/v1/app_entitlements?purchase_id=eq.${purchase.id}&select=*`, { headers: admin });
  const earningsRows = await json(`${local.API_URL}/rest/v1/app_creator_earnings?purchase_id=eq.${purchase.id}&select=*`, { headers: admin });
  assert.equal(payments.filter(row => row.status === 'confirmed').length, 1);
  assert.equal(entitlements.length, 1);
  assert.equal(entitlements[0].kind, 'ticket');
  assert.equal(entitlements[0].status, 'active');
  const tickets = await json(`${local.API_URL}/rest/v1/app_commerce_tickets?entitlement_id=eq.${entitlements[0].id}&select=*`, { headers: admin });
  assert.equal(tickets.length, 1);
  assert.equal(tickets[0].status, 'active');
  assert.equal(earningsRows.length, 1);
  assert.equal(earningsRows[0].creator_amount, 2000);
  assert.ok(['pending', 'available'].includes(earningsRows[0].status));
  const paymentEvents = await json(`${local.API_URL}/rest/v1/app_payment_webhook_events?event_type=eq.payment_intent.succeeded&status=eq.processed&select=*`, { headers: admin });
  assert.ok(paymentEvents.length >= 1, 'The signed Stripe event must be recorded as processed');

  const earnings = await waitFor('Stripe instant balance reconciliation', async () => {
    const result = await json(`${api}/commerce/earnings`, { headers: creator.authorized });
    return result.balance.status === 'available' && result.balance.instantAvailable >= 2000 ? result : null;
  }, 30, 1000);
  assert.ok(earnings.recent.some(row => row.purchaseId === purchase.id && row.creatorAmount === 2000));
  const payoutQuote = await json(`${api}/creator/payouts/quote`, {
    method: 'POST', headers: creator.authorized,
    body: JSON.stringify({ requestId: randomUUID(), amount: 2000 }),
  });
  assert.equal(payoutQuote.amount, 2000);
  assert.equal(payoutQuote.netAmount, 2000);
  const payout = await json(`${api}/creator/payouts`, {
    method: 'POST', headers: creator.authorized, body: JSON.stringify({ quoteId: payoutQuote.id }),
  });
  assert.equal(payout.payout.amount, 2000);
  assert.ok(['pending', 'in_transit', 'paid'].includes(payout.payout.status));
  const paidPayout = await waitFor('signed payout webhook confirmation', async () => {
    const result = await json(`${api}/commerce/payouts`, { headers: creator.authorized });
    return result.payouts.find(row => row.amount === 2000 && row.status === 'paid') || null;
  }, 60, 1000);
  assert.equal(paidPayout.card?.last4, readyStripe.debit.last4);
  const payoutEvents = await waitFor('payout webhook audit record', async () => {
    const rows = await json(`${local.API_URL}/rest/v1/app_payment_webhook_events?event_type=eq.payout.paid&provider_account_id=eq.${readyStripe.account.id}&status=eq.processed&select=*`, { headers: admin });
    return rows.length ? rows : null;
  }, 30, 1000);
  assert.ok(payoutEvents.length >= 1);

  console.log(JSON.stringify({ realWorker: true, realSupabaseAuth: true, unsignedWebhookRejected: true,
    stripeConnectAccountCreated: true, hostedOnboardingLinkCreated: true,
    nativePaymentIntentCreated: true, nativePaymentIntentConfirmed: true, signedPaymentWebhookProcessed: true,
    purchaseConfirmed: true, ticketIssued: true, creatorEarningRecorded: true,
    eligibleDebitCardValidated: true, instantPayoutCreated: true, signedPayoutWebhookProcessed: true,
    nativePaymentSheetValidated: false,
    note: 'Money movement used Stripe test mode. Hosted onboarding and native PaymentSheet UI remain manual acceptance gates.' }));
}

async function cleanupStripeFixtures() {
  if (!/^(sk|rk)_test_/.test(process.env.STRIPE_SECRET_KEY || '')) return;
  for (const priceId of cleanupPrices) {
    await fetch(`https://api.stripe.com/v1/prices/${priceId}`, {
      method: 'POST', headers: { Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'active=false', signal: AbortSignal.timeout(15_000), redirect: 'error',
    }).catch(() => undefined);
  }
  for (const productId of cleanupProducts) {
    await fetch(`https://api.stripe.com/v1/products/${productId}`, {
      method: 'POST', headers: { Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'active=false', signal: AbortSignal.timeout(15_000), redirect: 'error',
    }).catch(() => undefined);
  }
  for (const accountId of cleanupAccounts) {
    await fetch(`https://api.stripe.com/v1/accounts/${accountId}`, {
      method: 'DELETE', headers: { Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}` },
      signal: AbortSignal.timeout(15_000), redirect: 'error',
    }).catch(() => undefined);
  }
}

try { await main(); }
catch (error) {
  console.error(`Stripe API integration incomplete: ${error.message}`);
  process.exitCode = 1;
} finally {
  await cleanupStripeFixtures();
  for (const child of processes.reverse()) {
    if (!child.pid || child.exitCode !== null) continue;
    try { process.kill(-child.pid, 'SIGTERM'); } catch {}
    await Promise.race([new Promise(resolve => child.once('close', resolve)), sleep(5000)]);
    try { process.kill(-child.pid, 'SIGKILL'); } catch {}
  }
}
