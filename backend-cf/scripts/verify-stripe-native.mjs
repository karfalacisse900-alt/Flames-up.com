// Read-only acceptance evidence after a real PaymentSheet payment and Captro withdrawal.
// This script never confirms a PaymentIntent, fabricates a webhook, or writes ledger rows.
import assert from 'node:assert/strict';
import { setTimeout as sleep } from 'node:timers/promises';

function required(name) {
  const value = process.env[name]?.trim();
  assert.ok(value, `Set ${name} in the protected test environment`);
  return value;
}

async function verify() {
  assert.equal(required('STRIPE_MODE'), 'test', 'This acceptance script cannot run in live mode');
  const secret = required('STRIPE_SECRET_KEY');
  assert.ok(/^(sk|rk)_test_/.test(secret), 'Use a Stripe sandbox key');
  const api = new URL(required('CAPTRO_TEST_API_URL'));
  assert.equal(api.protocol, 'https:');
  assert.ok(!['api.flames-up.com', 'flames-up-api.karfalacisse900.workers.dev'].includes(api.hostname),
    'Do not run acceptance against the production Worker');
  const database = new URL(required('CAPTRO_TEST_SUPABASE_URL'));
  assert.equal(database.protocol, 'https:');
  assert.notEqual(database.hostname, 'cclgvxukwccvtgrbcwie.supabase.co', 'Use an isolated test database');
  const service = required('CAPTRO_TEST_SERVICE_ROLE_KEY');
  const buyer = required('CAPTRO_TEST_BUYER_TOKEN');
  const creator = required('CAPTRO_TEST_CREATOR_TOKEN');
  const purchaseId = required('CAPTRO_TEST_PURCHASE_ID');
  const payoutId = required('CAPTRO_TEST_PAYOUT_ID');
  assert.match(purchaseId, /^[a-f0-9-]{36}$/i);
  assert.match(payoutId, /^po_[a-zA-Z0-9]+$/);

  async function json(url, headers, expected = 200, init = {}) {
    const result = await fetch(url, { ...init, headers, signal: AbortSignal.timeout(30_000), redirect: 'error' });
    assert.equal(result.status, expected, `Unexpected HTTP status at ${new URL(url).pathname}`);
    return result.json();
  }
  const captro = (path, token = buyer) => json(`${api.href.replace(/\/$/, '')}${path}`, { Authorization: `Bearer ${token}` });
  const stripe = (path, account) => json(`https://api.stripe.com/v1${path}`, {
    Authorization: `Bearer ${secret}`, ...(account ? { 'Stripe-Account': account } : {}),
  });
  const rows = (table, filters) => {
    const url = new URL(`/rest/v1/${table}`, database);
    url.search = new URLSearchParams({ select: '*', ...filters }).toString();
    return json(url, { apikey: service, Authorization: `Bearer ${service}` });
  };
  const only = values => { assert.equal(values.length, 1, 'Expected exactly one persisted record'); return values[0]; };

  assert.equal(only(await rows('app_payment_environment', {})).stripe_mode, 'test');
  const capability = await captro('/commerce/stripe-capabilities');
  assert.equal(capability.configured, true);
  assert.equal(capability.liveMode, false);
  assert.equal(capability.connectAvailable, true);
  assert.equal(capability.webhookConfigured, true);
  assert.equal(capability.connectWebhookConfigured, true);
  await json(`${api.href.replace(/\/$/, '')}/stripe/webhook`, { 'Content-Type': 'application/json' }, 400,
    { method: 'POST', body: '{}' });

  const purchase = only(await rows('app_purchases', { id: `eq.${purchaseId}` }));
  assert.equal(purchase.status, 'confirmed');
  assert.equal(purchase.payment_interface, 'native');
  assert.equal(purchase.content_type, 'event');
  assert.equal(purchase.item_amount, 2000);
  assert.equal(purchase.creator_amount, 2000);
  assert.equal(purchase.currency, 'USD');
  assert.equal(purchase.total_amount, purchase.item_amount + purchase.service_fee_amount + purchase.tax_amount);
  assert.equal((await captro(`/payments/purchases/${purchaseId}`)).purchase.status, 'confirmed');
  await json(`${api.href.replace(/\/$/, '')}/payments/purchases/${purchaseId}`,
    { Authorization: `Bearer ${creator}` }, 404);

  const intent = await stripe(`/payment_intents/${purchase.provider_payment_id}`);
  assert.equal(intent.livemode, false);
  assert.equal(intent.status, 'succeeded');
  assert.equal(intent.amount_received, purchase.total_amount);
  assert.equal(intent.transfer_data.amount, 2000);
  assert.equal(intent.transfer_data.destination, purchase.stripe_destination_account_id);
  const payment = only(await rows('app_payments', { purchase_id: `eq.${purchaseId}`, status: 'eq.confirmed' }));
  assert.match(payment.provider_event_id, /^evt_/);
  const event = await stripe(`/events/${payment.provider_event_id}`);
  assert.equal(event.type, 'payment_intent.succeeded');
  assert.equal(event.livemode, false);
  assert.equal(event.data.object.id, intent.id);
  assert.equal(only(await rows('app_payment_webhook_events', { provider_event_id: `eq.${event.id}` })).status, 'processed');

  const entitlement = only(await rows('app_entitlements', { purchase_id: `eq.${purchaseId}` }));
  assert.equal(entitlement.kind, 'ticket');
  assert.equal(entitlement.status, 'active');
  const ticket = only(await rows('app_commerce_tickets', { entitlement_id: `eq.${entitlement.id}` }));
  assert.ok(ticket.id);
  const earning = only(await rows('app_creator_earnings', { purchase_id: `eq.${purchaseId}` }));
  assert.equal(earning.creator_amount, 2000);
  assert.equal(earning.payment_id, payment.id);
  const account = await stripe(`/accounts/${purchase.stripe_destination_account_id}`);
  assert.equal(account.details_submitted, true);
  assert.equal(account.charges_enabled, true);
  assert.equal(account.payouts_enabled, true);
  assert.deepEqual(account.requirements.currently_due, []);
  const earnings = await captro('/commerce/earnings', creator);
  assert.equal(earnings.balance.status, 'available');
  assert.ok(earnings.recent.some(row => row.purchaseId === purchaseId && row.creatorAmount === 2000));
  const balance = await stripe('/balance?expand[]=instant_available.net_available', account.id);
  const usd = list => list.filter(row => row.currency === 'usd').reduce((sum, row) => sum + row.amount, 0);
  assert.equal(earnings.balance.available, usd(balance.available));
  assert.equal(earnings.balance.pending, usd(balance.pending));

  let payout;
  for (let attempt = 0; attempt < 30; attempt++) {
    payout = await stripe(`/payouts/${payoutId}`, account.id);
    assert.equal(payout.livemode, false);
    if (['paid', 'failed', 'canceled'].includes(payout.status)) break;
    await sleep(2000);
  }
  assert.equal(payout.status, 'paid', 'Stripe has not reported a successful test payout');
  assert.equal(payout.method, 'instant');
  assert.match(payout.destination, /^card_/);
  const card = await stripe(`/accounts/${account.id}/external_accounts/${payout.destination}`);
  assert.equal(card.funding, 'debit');
  assert.ok(card.available_payout_methods.includes('instant'));
  const request = only(await rows('app_payout_requests', { provider_payout_id: `eq.${payoutId}` }));
  assert.equal(request.creator_id, purchase.creator_id);
  assert.equal(request.net_amount, payout.amount);
  assert.equal(request.external_account_id, payout.destination);
  const recorded = only(await rows('app_payouts', { provider_payout_id: `eq.${payoutId}` }));
  assert.equal(recorded.status, 'paid');
  assert.equal(recorded.amount, payout.amount);
  const payoutEvents = await stripe(`/events?type=payout.paid&limit=100`, account.id);
  const payoutEvent = payoutEvents.data.find(item => item.data.object.id === payoutId);
  assert.ok(payoutEvent, 'A real payout.paid event is required');
  assert.equal(only(await rows('app_payment_webhook_events', { provider_event_id: `eq.${payoutEvent.id}` })).status, 'processed');
  const history = await captro('/commerce/payouts', creator);
  assert.ok(history.payouts.some(item => item.id === recorded.id && item.status === 'paid'));
  console.log(JSON.stringify({ verified: true, mode: 'test', purchaseId, paymentIntentId: intent.id,
    paymentEventId: event.id, payoutId, payoutEventId: payoutEvent.id,
    note: 'Provider and ledger evidence only. Complete the separate iOS PaymentSheet and ticket scan checks.' }));
}

verify().catch(error => {
  // Never print response objects or request headers containing credentials/client secrets.
  console.error(`Stripe acceptance incomplete: ${error.message}`);
  process.exitCode = 1;
});
