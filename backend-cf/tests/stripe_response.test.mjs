import assert from 'node:assert/strict';
import test from 'node:test';
import { decodeStripeResponse, stripeFailureCode } from '../src/stripe-response.ts';

test('Stripe failures retain correlation without logging sensitive provider content', async t => {
  const lines = [];
  t.mock.method(console, 'warn', line => lines.push(JSON.parse(line)));
  const result = await decodeStripeResponse(Response.json({ error: {
    type: 'invalid_request_error', message: "You can only create new accounts if you've signed up for Connect, which you can do at https://dashboard.stripe.com/connect.",
    request_log_url: 'https://dashboard.stripe.com/private',
  } }, { status: 400, headers: { 'Request-Id': 'req_Test123' } }), '/accounts');
  assert.equal(result.ok, false);
  assert.equal(result.data.error.code, 'STRIPE_CONNECT_ACTIVATION_REQUIRED');
  assert.equal(stripeFailureCode(result.data, 'fallback'), 'STRIPE_CONNECT_ACTIVATION_REQUIRED');
  assert.deepEqual(lines, [{ event: 'stripe_api_failed', status: 400, requestId: 'req_Test123', code: 'STRIPE_CONNECT_ACTIVATION_REQUIRED' }]);
});

test('Malformed Stripe responses fail closed, including successful HTTP responses', async t => {
  t.mock.method(console, 'warn', () => {});
  for (const body of ['not JSON', 'null', '[]', '"secret"']) {
    const result = await decodeStripeResponse(new Response(body, { status: 200 }), '/payment_intents');
    assert.equal(result.ok, false);
    assert.equal(result.data.code, 'STRIPE_INVALID_RESPONSE');
  }
});

test('Stripe successful objects are unchanged and do not emit failure logs', async t => {
  const log = t.mock.method(console, 'warn', () => {});
  const data = { object: 'payment_intent', id: 'pi_fixture' };
  const result = await decodeStripeResponse(Response.json(data), '/payment_intents');
  assert.equal(result.ok, true);
  assert.deepEqual(result.data, data);
  assert.equal(log.mock.callCount(), 0);
});

test('Provider-controlled error fields cannot inject secrets into diagnostics', async t => {
  const lines = [];
  t.mock.method(console, 'warn', line => lines.push(JSON.parse(line)));
  const data = { error: { code: 'sk_test_secret', type: 'card_error', message: 'sensitive payment data' } };
  assert.equal(stripeFailureCode(data, 'fallback'), 'card_error');
  assert.equal(stripeFailureCode({ error: { code: 'card_declined' } }, 'fallback'), 'card_declined');
  assert.equal(stripeFailureCode({ error: { code: 'private@example.com', type: 'private data' } }, 'fallback'), 'fallback');
  await decodeStripeResponse(Response.json(data, { status: 402, headers: { 'Request-Id': 'sk_test_secret' } }), '/payment_intents');
  assert.deepEqual(lines, [{ event: 'stripe_api_failed', status: 402, requestId: null, code: 'card_error' }]);
});
