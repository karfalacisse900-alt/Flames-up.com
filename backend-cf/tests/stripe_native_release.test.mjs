import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const worker = read('../src/index.ts');
const native = read('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroPaymentSheetView.swift');

test('native checkout uses provider UI and only persisted confirmation grants completion', () => {
  assert.match(native, /import StripePaymentSheet/);
  assert.match(native, /\.paymentSheet\(isPresented:/);
  assert.match(native, /response.purchase.status == "confirmed"/);
  assert.doesNotMatch(native, /case \.completed:\s*paid = true/);
  assert.match(native, /CaptroApplePayMerchantIdentifier/);
  const start = worker.slice(worker.indexOf('const beginCommercePurchaseHandler'), worker.indexOf("api.get('/payments/purchases"));
  assert.match(start, /CAPTRO_IDEMPOTENCY_KEY_REQUIRED/);
  assert.match(start, /Number\(price.unit_amount \|\| 0\) \* quantity/);
  assert.doesNotMatch(start, /body\.(amount|creatorAmount|serviceFee|taxAmount)/);
});

test('read-only Stripe acceptance refuses live keys without logging credentials', () => {
  const script = fileURLToPath(new URL('../scripts/verify-stripe-native.mjs', import.meta.url));
  const secret = 'sk_live_do_not_log_this_fixture';
  const result = spawnSync(process.execPath, [script], {
    env: { ...process.env, STRIPE_MODE: 'test', STRIPE_SECRET_KEY: secret }, encoding: 'utf8',
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Use a Stripe sandbox key/);
  assert.ok(!`${result.stdout}${result.stderr}`.includes(secret));
});

test('test acceptance cannot target the production Worker', () => {
  const script = fileURLToPath(new URL('../scripts/verify-stripe-native.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [script], {
    env: { ...process.env, STRIPE_MODE: 'test', STRIPE_SECRET_KEY: 'sk_test_fixture',
      CAPTRO_TEST_API_URL: 'https://api.flames-up.com/api' }, encoding: 'utf8',
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /production Worker/);
});

test('sandbox CI scripts reject mismatched keys without printing them', () => {
  for (const name of ['stripe-sandbox-bootstrap.mjs', 'stripe-sandbox-runtime.mjs']) {
    const script = fileURLToPath(new URL(`../scripts/${name}`, import.meta.url));
    for (const overrides of [
      { STRIPE_SECRET_KEY: 'sk_live_do_not_log_this_fixture' },
      { STRIPE_PUBLISHABLE_KEY: 'pk_live_do_not_log_this_fixture' },
    ]) {
      const result = spawnSync(process.execPath, [script], {
        env: { ...process.env, GITHUB_ACTIONS: 'true', STRIPE_MODE: 'test',
          STRIPE_SECRET_KEY: 'sk_test_fixture', STRIPE_PUBLISHABLE_KEY: 'pk_test_fixture', ...overrides },
        encoding: 'utf8',
      });
      assert.equal(result.status, 1);
      assert.match(result.stderr, /A sandbox (secret|publishable) key is required/);
      assert.ok(!`${result.stdout}${result.stderr}`.includes('do_not_log_this_fixture'));
    }
  }
});
