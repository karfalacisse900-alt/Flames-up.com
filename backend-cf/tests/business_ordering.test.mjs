import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { Hono } from 'hono';
import { makeBusinessOrdering } from '../src/business-ordering.ts';

const owner = '10000000-0000-4000-8000-000000000001';
const buyer = '10000000-0000-4000-8000-000000000002';
const stranger = '10000000-0000-4000-8000-000000000003';
const coffee = '20000000-0000-4000-8000-000000000001';
const hotdogs = '20000000-0000-4000-8000-000000000002';
const latte = '30000000-0000-4000-8000-000000000001';
const dog = '30000000-0000-4000-8000-000000000002';
const oat = '40000000-0000-4000-8000-000000000001';
const whole = '40000000-0000-4000-8000-000000000002';
const group = '50000000-0000-4000-8000-000000000001';
const realStripe = process.env.CAPTRO_BUSINESS_REAL_STRIPE === '1';

async function sandboxStripe(path, fields, idempotencyKey) {
  const response = await fetch('https://api.stripe.com/v1' + path, {
    method: fields ? 'POST' : 'GET',
    headers: {
      Authorization: 'Bearer ' + process.env.STRIPE_SECRET_KEY,
      ...(fields ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
      ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
    },
    ...(fields ? { body: new URLSearchParams(fields) } : {}),
    signal: AbortSignal.timeout(20000),
  });
  const data = await response.json();
  assert.ok(response.ok, 'Stripe sandbox request failed: ' + response.status + ' ' + (data.error?.code ?? ''));
  assert.notEqual(data.livemode, true, 'Stripe returned a live-mode object');
  return { ok: true, data };
}

test('Captro Business API and Postgres complete a pickup order using isolated Stripe objects', async t => {
  if (realStripe) {
    assert.equal(process.env.STRIPE_MODE, 'test');
    assert.match(process.env.STRIPE_SECRET_KEY ?? '', /^sk_test_/);
    assert.match(process.env.STRIPE_PUBLISHABLE_KEY ?? '', /^pk_test_/);
    assert.match(process.env.STRIPE_EXPECTED_ACCOUNT_ID ?? '', /^acct_[A-Za-z0-9]+$/);
    const account = await sandboxStripe('/account');
    assert.equal(account.data.id, process.env.STRIPE_EXPECTED_ACCOUNT_ID, 'Unexpected sandbox platform account');
  }
  const db = new PGlite();
  t.after(() => db.close());
  const one = async (statement, params = []) => (await db.query(statement, params)).rows[0];
  const migrations = [
    '20260904193517_captro_commerce_entitlements.sql',
    '20260904221545_stripe_connect_creator_earnings.sql',
    '20260904231905_stripe_native_payments.sql',
    '20260908224758_isolate_stripe_connected_accounts_by_mode.sql',
    '20260925120000_seller_identity_verification.sql',
    '20260926214527_deferred_marketplace_settlement.sql',
    '20261112030025_captro_business_ordering.sql',
  ];
  await db.exec('create role anon; create role authenticated; create role service_role; create schema auth; create table auth.users(id uuid primary key); create table app_posts(id uuid primary key);');
  for (const migration of migrations) {
    await db.exec(readFileSync(new URL('../../supabase/migrations/' + migration, import.meta.url), 'utf8'));
  }
  await db.query('insert into auth.users values($1),($2),($3)', [owner, buyer, stranger]);
  await db.query("insert into app_businesses(id,owner_id,name,category,pickup_address,latitude,longitude,tax_bps,published,paused) values($1,$3,'Captro Coffee','coffee_bakery','Sample pickup',40.73,-74,800,true,false),($2,$3,'NYC Hot Dogs','street_food','Sample vendor pickup',40.76,-74,800,true,false)", [coffee, hotdogs, owner]);
  await db.query("insert into app_business_products(id,business_id,name,category,unit_amount,mode,groups) values($1,$3,'Iced Latte','Coffee',490,'CUSTOMIZE',$5),($2,$4,'Hotdog','Food',400,'QUICK_ADD','[]')", [
    latte, dog, coffee, hotdogs,
    JSON.stringify([{ id: group, name: 'Milk', minimum: 1, maximum: 1,
      options: [{ id: oat, name: 'Oat milk', extra: 50 }, { id: whole, name: 'Whole milk', extra: 0 }] }]),
  ]);
  const select = async (_, table, filters, _columns, limit) => {
    const params = [];
    const clauses = Object.entries(filters).map(([key, value]) => {
      if (value === 'is.null') return key + ' is null';
      const pos = params.push(value.slice(value.indexOf('.') + 1));
      return key + (value.startsWith('neq.') ? '<>' : '=') + '$' + pos;
    });
    return (await db.query('select * from ' + table + ' where ' + clauses.join(' and ') + ' limit ' + limit, params)).rows;
  };
  const api = new Hono();
  let creationCount = 0, refundCount = 0;
  const intents = new Map(), charges = new Map(), paymentIds = [];
  const webhook = makeBusinessOrdering(api, async (c, next) => {
    if (!c.req.header('fixture-actor')) return c.json({}, 401);
    await next();
  }, {
    rpc: async (_, name, body) => {
      try {
        const args = Object.values(body).map(v => v && typeof v === 'object' ? JSON.stringify(v) : v);
        return (await one('select ' + name + '(' + args.map((_, i) => '$' + (i + 1)).join(',') + ') result', args)).result;
      } catch (e) { throw new Error('RPC:' + e.message); }
    },
    select,
    query: (c, table, opts) => select(c, table, opts.filters, opts.select, opts.limit),
    insert: async () => { throw new Error('Unexpected fixture insert'); },
    patch: async (_, table, filters, fields) => {
      const [key, value] = Object.entries(fields)[0];
      await db.query('update ' + table + ' set ' + key + '=$2 where id=$1 and ' + key + ' is null',
        [filters.id.slice(3), value]);
    },
    stripe: () => ({ mode: 'test', configured: true, webhookConfigured: true,
      publishableKey: realStripe ? process.env.STRIPE_PUBLISHABLE_KEY : 'pk_test_fixture' }),
    actor: c => c.req.header('fixture-actor'),
    seller: async () => ({ provider_account_id: 'acct_fixture' }),
    media: async () => [],
    limit: async () => null,
    getStripe: async (_, path) => {
      if (realStripe) return sandboxStripe(path);
      const id = path.split('/').pop().split('?')[0];
      const data = path.startsWith('/charges/') ? charges.get(id) : intents.get(id);
      return { ok: Boolean(data), data };
    },
    postStripe: async (_, path, fields, key) => {
      if (realStripe) {
        const result = await sandboxStripe(path, fields, key);
        if (path === '/refunds') {
          refundCount++;
          assert.equal(result.data.payment_intent, fields.payment_intent);
          assert.equal(result.data.status, 'succeeded');
        } else {
          creationCount++;
          paymentIds.push(result.data.id);
        }
        return result;
      }
      if (path === '/refunds') {
        refundCount++;
        const intent = intents.get(fields.payment_intent);
        charges.get(intent.latest_charge).amount_refunded = intent.amount;
        return { ok: true, data: { id: 're_fixture', payment_intent: intent.id } };
      }
      creationCount++;
      const id = 'pi_' + String(creationCount);
      assert.match(key, /^business-payment:/);
      const data = { id, amount: fields.amount, currency: 'usd', livemode: false,
        transfer_group: fields.transfer_group, client_secret: id + '_secret_fixture', status: 'requires_payment_method',
        metadata: { source: fields['metadata[source]'], business_order_id: fields['metadata[business_order_id]'] } };
      intents.set(id, data);
      paymentIds.push(id);
      return { ok: true, data };
    },
  });
  const call = (path, actor, body, enabled = true) => api.request(path, {
    method: body === undefined ? 'GET' : 'POST', headers: {
      'Content-Type': 'application/json', ...(actor ? { 'fixture-actor': actor } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }, { CAPTRO_BUSINESS_TEST_CHECKOUT: enabled ? '1' : '0' });
  const lines = [
    { product_id: latte, quantity: 2, option_ids: [oat], unit_amount: 1 },
    { product_id: latte, quantity: 1, option_ids: [whole] },
  ];
  const checkout = { lines, total: 1696, request_id: '60000000-0000-4000-8000-000000000001' };
  let paidOrder;
  let expectedFee;
  const success = async (id, chargeId) => {
    if (realStripe) {
      const { data: intent } = await sandboxStripe('/payment_intents/' + id + '/confirm', { payment_method: 'pm_card_visa' });
      assert.equal(intent.status, 'succeeded');
      const { data: charge } = await sandboxStripe('/charges/' + intent.latest_charge + '?expand[]=balance_transaction');
      assert.equal(charge.payment_intent, intent.id);
      assert.equal(charge.amount, intent.amount);
      assert.equal(charge.paid, true);
      expectedFee = charge.balance_transaction?.currency === 'usd' ? charge.balance_transaction.fee : undefined;
      return { type: 'payment_intent.succeeded', data: { object: intent } };
    }
    expectedFee = 53;
    const intent = intents.get(id);
    Object.assign(intent, { status: 'succeeded', amount_received: intent.amount, latest_charge: chargeId });
    charges.set(chargeId, { id: chargeId, amount: intent.amount, payment_intent: id, currency: 'usd',
      paid: true, captured: true, amount_refunded: 0, disputed: false, balance_transaction: { currency: 'usd', fee: 53 } });
    return { type: 'payment_intent.succeeded', data: { object: intent } };
  };
  await t.test('public discovery, menu isolation, and server pricing of separate configurations', async () => {
    const directory = await (await call('/businesses?lat=40.73&lon=-74')).json();
    assert.deepEqual(directory.map(shop => shop.name), ['Captro Coffee', 'NYC Hot Dogs']);
    assert.equal(directory[0].owner_id, undefined);
    assert.equal((await (await call('/businesses/' + hotdogs + '/menu')).json())[0].mode, 'QUICK_ADD');
    const quote = await (await call('/businesses/' + coffee + '/quote', buyer, { lines })).json();
    assert.deepEqual([quote.subtotal, quote.tax, quote.total], [1570, 126, 1696]);
    assert.equal(quote.lines[0].unit_amount, 540);
    assert.equal((await call('/businesses/' + coffee + '/quote', buyer, { lines: [{ product_id: dog, quantity: 1, option_ids: [] }] })).status, 409);
    assert.equal((await call('/businesses/' + coffee + '/quote', buyer, { lines: [{ ...lines[0], option_ids: [oat, oat] }] })).status, 409);
    assert.equal((await call('/businesses/' + coffee + '/quote', buyer, { lines: [{ ...lines[0], option_ids: [] }] })).status, 409);
  });
  await t.test('checkout requires authentication, test enablement and a current server total; retries share one intent', async () => {
    assert.equal((await call('/businesses/' + coffee + '/checkout', undefined, checkout)).status, 401);
    assert.equal((await call('/businesses/' + coffee + '/checkout', buyer, checkout, false)).status, 503);
    assert.equal((await call('/businesses/' + coffee + '/checkout', buyer, { ...checkout, total: 500 })).status, 409);
    const first = await (await call('/businesses/' + coffee + '/checkout', buyer, checkout)).json();
    const again = await (await call('/businesses/' + coffee + '/checkout', buyer, checkout)).json();
    assert.equal(first.order.id, again.order.id);
    assert.equal(first.payment.client_secret, again.payment.client_secret);
    assert.equal(creationCount, 1);
    paidOrder = first.order.id;
    assert.equal((await (await call('/business-orders/' + paidOrder + '/verify', buyer, {})).json()).status, 'awaiting_payment');
    assert.equal((await call('/business-orders/' + paidOrder, stranger)).status, 404);
    assert.equal((await call('/business-owner/' + coffee + '/orders', stranger)).status, 404);
  });
  await t.test('trusted provider payment, replay, vendor progression and one-time QR pickup', async () => {
    const event = await success(paymentIds[0], 'ch_fixture1');
    await webhook({}, event);
    await webhook({}, event);
    assert.equal((await (await call('/business-orders/' + paidOrder, buyer)).json()).status, 'received');

    const journal = (await db.query("select seller_id, account, amount::int from app_marketplace_ledger")).rows;
    assert.ok(journal.every(row => row.seller_id === owner));
    assert.equal(journal.find(row => row.account === 'gross').amount, 1696);
    const fees = journal.filter(row => row.account === 'processing_fee');
    assert.ok(fees.length <= 1);
    if (expectedFee !== undefined) assert.equal(fees[0]?.amount, expectedFee);
    assert.ok(fees.every(row => Number.isInteger(row.amount) && row.amount >= 0));
    assert.equal(journal.filter(row => row.account === 'gross').length, 1);
    assert.equal((await call('/business-orders/' + paidOrder + '/action', stranger, { action: 'accept' })).status, 409);
    assert.equal((await call('/business-orders/' + paidOrder + '/action', owner, { action: 'ready' })).status, 409);
    for (const [action, status] of [['accept','accepted'],['prepare','preparing'],['ready','ready']]) {
      assert.equal((await (await call('/business-orders/' + paidOrder + '/action', owner, { action })).json()).status, status);
    }
    const ready = await (await call('/business-orders/' + paidOrder, buyer)).json();
    const code = 'captro-pickup:' + paidOrder + ':' + ready.pickup_token;
    assert.equal((await call('/business-owner/' + hotdogs + '/pickup', owner, { code })).status, 404);
    assert.equal((await call('/business-owner/' + coffee + '/pickup', stranger, { code })).status, 404);
    assert.equal((await (await call('/business-owner/' + coffee + '/pickup', owner, { code })).json()).status, 'completed');
    assert.equal((await call('/business-owner/' + coffee + '/pickup', owner, { code })).status, 409);
    assert.equal((await (await call('/business-orders/' + paidOrder, buyer)).json()).pickup_token, null);
    assert.equal((await one("select count(*)::int n from app_business_order_events where status='completed'")).n, 1);
  });
  await t.test('vendor rejection refunds through Stripe; repeated webhooks preserve the refund journal', async () => {
    const next = await (await call('/businesses/' + hotdogs + '/checkout', buyer, {
      lines: [{ product_id: dog, quantity: 1, option_ids: [] }], total: 432,
      request_id: '60000000-0000-4000-8000-000000000002',
    })).json();
    const event = await success(paymentIds[1], 'ch_fixture2');
    await webhook({}, event);
    const rejection = await call('/business-orders/' + next.order.id + '/action', owner, { action: 'reject' });
    assert.equal((await rejection.json()).status, 'refunded');
    await webhook({}, event);
    assert.equal(refundCount, 1);
    assert.equal((await one("select count(*)::int n from app_marketplace_ledger where event_type='BUSINESS_REFUND'")).n, 1);
  });
  await t.test('PostgREST client roles cannot access business financial tables or settlement functions', async () => {
    for (const role of ['anon', 'authenticated']) {
      await db.exec('set role ' + role);
      await assert.rejects(db.query('select pickup_token from app_business_orders'), /permission denied/);
      await assert.rejects(db.query('select captro_business_transition($1,$2,$3,null)', [paidOrder, owner, 'ready']), /permission denied/);
      await db.exec('reset role');
    }
  });
});
