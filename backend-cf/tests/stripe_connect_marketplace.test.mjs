import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const source = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const worker = source('../src/index.ts');
const money = source('../src/stripe-money.ts');
const migration = source('../../supabase/migrations/20260904221545_stripe_connect_creator_earnings.sql');
const indexMigration = source('../../supabase/migrations/20260904221847_stripe_connect_fk_indexes.sql');
const commerceModels = source('../../ios_native/MIRA/Sources/MIRANative/Models/CaptroCommerce.swift');
const earnings = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceDashboardViews.swift');
const checkout = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceDetailViews.swift');
const composer = source('../../ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift');
const cache = source('../../ios_native/MIRA/Sources/MIRANative/Services/MIRAAppCacheStore.swift');
const homeStamp = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroFeedPostOverlays.swift');
const homePost = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroFeedPostView.swift');
const details = source('../../ios_native/MIRA/Sources/MIRANative/Screens/PostDetailNativeView.swift');

test('Stripe Connect stores one account per creator and no raw bank credentials', () => {
  assert.match(migration, /create table public\.app_connected_accounts \(/);
  assert.match(migration, /user_id uuid not null unique/);
  assert.match(migration, /provider_account_id text not null unique/);
  assert.match(migration, /external_account_last4 text/);
  assert.doesNotMatch(migration, /\b(?:routing_number|account_number|debit_card_number|bank_token)\b/i);
  assert.match(worker, /type: 'express'/);
  assert.match(worker, /\/account_links/);
  assert.match(worker, /type: 'account_onboarding'/);
  assert.match(worker, /\/login_links/);
});

test('paid posts create reusable Stripe products and prices only after payout readiness', () => {
  assert.match(migration, /add column if not exists stripe_product_id text/);
  assert.match(migration, /add column if not exists stripe_price_id text/);
  assert.match(worker, /async function ensureStripeProductAndPrice/);
  assert.match(worker, /stripeApiRequest\(c, '\/products'/);
  assert.match(worker, /stripeApiRequest\(c, '\/prices'/);
  assert.match(worker, /PAYOUT_SETUP_REQUIRED/);
  assert.match(worker, /requireReadyConnectedAccount/);
});

test('buyer fees are configurable while the creator receives the full listed item amount', () => {
  assert.match(worker, /CAPTRO_SERVICE_FEE_BPS/);
  assert.match(worker, /CAPTRO_SERVICE_FEE_FIXED_CENTS/);
  assert.match(money, /creatorAmount: cents\(item - creatorDeduction\)/);
  assert.match(money, /buyerTotal: cents\(item \+ serviceFeeAmount/);
  assert.match(worker, /'payment_intent_data\[transfer_data\]\[destination\]'/);
  assert.match(worker, /'payment_intent_data\[transfer_data\]\[amount\]'/);
  assert.match(worker, /'metadata\[captro_tax_amount\]': tax/);
  assert.match(worker, /session\?\.metadata\?\.captro_tax_amount/);
  assert.match(checkout, /amountRow\("Service fee"/);
  assert.match(checkout, /amountRow\("TOTAL"/);
  assert.match(checkout, /amountRow\("You earn"/);
});

test('payment confirmation creates one immutable earning and entitlement server-side', () => {
  for (const table of [
    'app_creator_earnings', 'app_platform_fees', 'app_refunds', 'app_payouts',
    'app_payment_disputes', 'app_payment_webhook_events',
  ]) {
    assert.match(migration, new RegExp(`create table public\\.${table} \\(`));
  }
  assert.match(migration, /purchase_id uuid not null unique references public\.app_purchases/);
  assert.match(migration, /if purchase_row\.status <> 'payment_pending' then raise exception 'CAPTRO_PURCHASE_NOT_PAYABLE'/);
  assert.match(migration, /p_amount <> purchase_row\.total_amount/);
  assert.match(migration, /insert into public\.app_creator_earnings/);
  assert.match(migration, /perform public\.captro_create_entitlement_for_purchase\(purchase_row\.id\)/);
  assert.match(worker, /verifyStripeWebhookSignature\(rawBody, signature, secret\)/);
  assert.doesNotMatch(worker, /success_url[\s\S]{0,260}captro_create_entitlement_for_purchase/);
});

test('marketplace settlement foreign keys have covering indexes', () => {
  for (const indexName of [
    'app_payments_purchase_idx',
    'app_purchases_connected_account_idx',
    'app_creator_earnings_payment_idx',
    'app_creator_earnings_connected_account_idx',
    'app_platform_fees_payment_idx',
    'app_payouts_connected_account_idx',
    'app_payment_disputes_purchase_idx',
  ]) {
    assert.match(indexMigration, new RegExp(`create index if not exists ${indexName}`));
  }
});

test('refunds and disputes preserve the original sale and reverse access and earnings', () => {
  assert.match(worker, /reverse_transfer: true/);
  assert.match(migration, /provider_refund_id text not null unique/);
  assert.match(migration, /refunded_amount = total_creator_reversed/);
  assert.match(migration, /update public\.app_entitlements set status = 'refunded'/);
  assert.match(worker, /charge\.dispute\./);
  assert.match(worker, /status: status === 'lost' \? 'reversed' : 'disputed'/);
  assert.match(worker, /status: 'revoked'/);
});

test('Connect account, payout and purchase events are handled without the app remaining open', () => {
  assert.match(worker, /STRIPE_CONNECT_WEBHOOK_SECRET/);
  assert.match(worker, /STRIPE_CONNECT_BOOTSTRAP_TOKEN/);
  assert.match(worker, /connect: true/);
  assert.match(worker, /api\.post\('\/stripe\/connect-webhook', stripeWebhookHandler\)/);
  assert.match(worker, /'payout\.failed'/);
  assert.match(worker, /new Set\(\[stripe\.webhookSecret, stripe\.connectWebhookSecret\]/);
  assert.match(worker, /event\.type === 'account\.updated'/);
  assert.match(worker, /event\.type\.startsWith\('payout\.'\)/);
  assert.match(worker, /event\.type === 'payment_intent\.payment_failed'/);
  assert.match(worker, /checkout\.session\.async_payment_succeeded/);
  assert.match(worker, /app_payment_webhook_events/);
  assert.match(worker, /recordStripeWebhookEvent\(c, event, 'failed'/);
});

test('Earnings UI is backed by private live endpoints and never invents balances', () => {
  assert.match(commerceModels, /get\("\/commerce\/earnings"\)/);
  assert.match(commerceModels, /get\("\/commerce\/payouts"\)/);
  assert.match(commerceModels, /post\("\/commerce\/payout-account\/onboarding-link"/);
  assert.match(worker, /stripeApiGet\(c, '\/balance\?expand\[\]=instant_available\.net_available', account\.provider_account_id\)/);
  assert.match(worker, /stripeApiGet\(c, '\/payouts\?limit=100', account\.provider_account_id\)/);
  assert.match(earnings, /Text\("Balance unavailable"\)/);
  assert.match(earnings, /"Set Up Earnings"/);
  assert.doesNotMatch(earnings, /Available\s*\$72|Pending\s*\$16|\+ \$8\.00/);
});

test('paid-post onboarding preserves the creator draft and media selection', () => {
  assert.match(cache, /var commerceDraft: CaptroCommerceDraft\? = nil/);
  assert.match(composer, /preparePayoutAccountForPublishing/);
  assert.match(composer, /persistComposerDraft/);
  assert.match(composer, /createPayoutOnboardingLink/);
  assert.match(composer, /payoutSetupDestination/);
});

test('Details removes the lower reaction strip while Home stamps expose a red save control', () => {
  assert.equal((details.match(/reactionRow\(/g) || []).length, 1, 'reactionRow must remain unused except for its private declaration');
  assert.match(details, /detailHeader/);
  assert.match(homeStamp, /Image\(systemName: isSaved \? "bookmark\.fill" : "bookmark"\)/);
  assert.match(homeStamp, /foregroundStyle\(MIRATheme\.Color\.like\)/);
  assert.match(homePost, /isSaved: post\.viewerSaved, onSave: onSave/);
});
