import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const worker = read('../src/index.ts');
const native = read('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroPaymentSheetView.swift');
const nativeApiClient = read('../../ios_native/MIRA/Sources/MIRANative/Services/MIRAAPIClient.swift');
const deployWorkflow = read('../../.github/workflows/deploy-worker.yml');
const sandboxWorkflow = read('../../.github/workflows/stripe-sandbox-integration.yml');
const sandboxRuntime = read('../scripts/stripe-sandbox-runtime.mjs');
const connectSmoke = read('../scripts/verify-stripe-connect.mjs');
const paymentEnvironmentMigration = read('../../supabase/migrations/20260905205251_configure_stripe_payment_environment.sql');

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

test('native release and Stripe smoke use the directly deployed production Worker', () => {
  const directWorker = /https:\/\/flames-up-api\.karfalacisse900\.workers\.dev\/api/;
  assert.match(nativeApiClient, directWorker);
  assert.match(connectSmoke, directWorker);
  assert.doesNotMatch(nativeApiClient, /apiBaseURL = URL\(string: "https:\/\/api\.flames-up\.com\/api"/);
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
          STRIPE_EXPECTED_ACCOUNT_ID: 'acct_fixture', STRIPE_SECRET_KEY: 'sk_test_fixture',
          STRIPE_PUBLISHABLE_KEY: 'pk_test_fixture', ...overrides },
        encoding: 'utf8',
      });
      assert.equal(result.status, 1);
      assert.match(result.stderr, /A sandbox (secret|publishable) key is required/);
      assert.ok(!`${result.stdout}${result.stderr}`.includes('do_not_log_this_fixture'));
    }
  }
});

test('protected sandbox acceptance is pinned to its configured test account and exercises real money state', () => {
  assert.match(sandboxWorkflow, /environment: captro-payments-test/);
  assert.match(sandboxWorkflow, /STRIPE_EXPECTED_ACCOUNT_ID: \$\{\{ vars\.STRIPE_EXPECTED_ACCOUNT_ID \}\}/);
  assert.doesNotMatch(sandboxWorkflow, /STRIPE_EXPECTED_ACCOUNT_ID: acct_/);
  assert.match(sandboxRuntime, /stripe\('\/account'\)/);
  assert.match(sandboxRuntime, /pm_card_bypassPending/);
  assert.match(sandboxRuntime, /\}, \[200, 201\]\);/);
  assert.match(sandboxRuntime, /signed payment webhook confirmation/);
  assert.match(sandboxRuntime, /app_commerce_tickets/);
  assert.match(sandboxRuntime, /app_creator_earnings/);
  assert.match(sandboxRuntime, /creator\/payouts\/quote/);
  assert.match(sandboxRuntime, /signed payout webhook confirmation/);
  assert.match(sandboxRuntime, /nativePaymentSheetValidated: false/);
});

test('the production bootstrap binds one Stripe mode and provisions both signed webhook destinations', () => {
  assert.match(paymentEnvironmentMigration, /captro_configure_payment_environment/);
  assert.match(paymentEnvironmentMigration, /STRIPE_DATABASE_MODE_MISMATCH/);
  assert.match(paymentEnvironmentMigration, /grant execute .* to service_role/i);
  const bootstrap = worker.slice(
    worker.indexOf("api.post('/internal/stripe/connect-webhook/bootstrap'"),
    worker.indexOf("api.get('/commerce/payout-account'", worker.indexOf("api.post('/internal/stripe/connect-webhook/bootstrap'"))
  );
  assert.match(bootstrap, /captro_configure_payment_environment/);
  assert.match(bootstrap, /payment_intent\.succeeded/);
  assert.match(bootstrap, /balance\.available/);
  assert.match(bootstrap, /platformSigningSecret/);
  assert.match(bootstrap, /connectSigningSecret/);
  assert.match(deployWorkflow, /Sync Stripe payment API secrets/);
  assert.match(deployWorkflow, /Provision Stripe payment webhooks and bind live database/);
  assert.match(deployWorkflow, /STRIPE_SECRET_KEY/);
  assert.match(deployWorkflow, /STRIPE_PUBLISHABLE_KEY/);
  assert.match(deployWorkflow, /environment: captro-payments-live/);
  assert.match(deployWorkflow, /STRIPE_EXPECTED_ACCOUNT_ID: \$\{\{ vars\.STRIPE_EXPECTED_ACCOUNT_ID \}\}/);
  assert.match(deployWorkflow, /actual_account_id.*STRIPE_EXPECTED_ACCOUNT_ID/s);
  assert.doesNotMatch(deployWorkflow, /STRIPE_EXPECTED_ACCOUNT_ID: acct_/);
});

test('scheduled reconciliation recovers missed payment and payout webhooks from Stripe state', () => {
  assert.match(worker, /intent\.data\.status === 'succeeded'/);
  assert.match(worker, /completeCommercePurchaseFromIntent\(c, `reconcile-payment-\$\{intent\.data\.id\}`/);
  assert.match(worker, /async function reconcileStripeFinancialState/);
  assert.match(worker, /status: postgrestInFilter\(\['pending', 'in_transit'\]\)/);
  assert.match(worker, /stripeApiGet\(c, `\/payouts\/\$\{encodeURIComponent\(payout\.provider_payout_id\)\}`/);
  assert.match(worker, /controller\.cron === '23 \* \* \* \*'/);
});
