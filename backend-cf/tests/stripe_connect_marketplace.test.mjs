import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import {
  STRIPE_ACCOUNTS_V2_VERSION,
  stripeRecipientAccountPayload,
  stripeRecipientOnboardingPayload,
  stripeV2RecipientTransferStatus,
  stripeV2RecipientTransfersEnabled,
} from '../src/stripe-connect-v2.ts';

const source = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const worker = source('../src/index.ts');
const connectV2 = source('../src/stripe-connect-v2.ts');
const money = source('../src/stripe-money.ts');
const migration = source('../../supabase/migrations/20260904221545_stripe_connect_creator_earnings.sql');
const nativeMigration = source('../../supabase/migrations/20260904231905_stripe_native_payments.sql');
const indexMigration = source('../../supabase/migrations/20260904221847_stripe_connect_fk_indexes.sql');
const buyerCardsMigration = source('../../supabase/migrations/20260908205030_captro_buyer_payment_methods.sql');
const commerceModels = source('../../ios_native/MIRA/Sources/MIRANative/Models/CaptroCommerce.swift');
const earnings = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceDashboardViews.swift');
const payments = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroPaymentsView.swift');
const paymentSheet = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroPaymentSheetView.swift');
const profile = source('../../ios_native/MIRA/Sources/MIRANative/Screens/ProfileChatVerificationStudio.swift');
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
  assert.match(worker, /stripeApiV2Request\(c, '\/core\/accounts'/);
  assert.match(worker, /stripeApiV2Request\(c, '\/core\/account_links'/);
  assert.match(connectV2, /dashboard: 'express'/);
  assert.match(connectV2, /fees_collector: 'application'/);
  assert.match(connectV2, /losses_collector: 'application'/);
  assert.match(connectV2, /stripe_transfers: \{ requested: true \}/);
  assert.match(connectV2, /configurations: \['recipient'\]/);
  assert.match(connectV2, /type: 'account_onboarding'/);
  assert.doesNotMatch(worker, /stripeApiRequest\(c, '\/accounts'/);
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

test('recipient readiness depends on transfers and payouts rather than direct charges', () => {
  assert.match(nativeMigration, /transfers_enabled boolean not null default false/);
  assert.match(nativeMigration, /transfers_enabled = true and payouts_enabled = true and details_submitted = true/);
  assert.match(worker, /row\?\.transfers_enabled === true && row\?\.payouts_enabled === true/);
  assert.doesNotMatch(worker, /row\?\.charges_enabled === true && row\?\.payouts_enabled === true/);
  assert.match(worker, /stripeV2RecipientTransfersEnabled\(accountV2\)/);
  assert.match(worker, /stripeApiV2Get\(c, `\/core\/accounts\/\$\{encodeURIComponent\(providerAccountId\)\}/);
  assert.doesNotMatch(worker, /stripeV1AccountTransfersEnabled/);
});

test('recipient readiness uses the actual Accounts v2 transfer capability', () => {
  const activeRecipient = {
    configuration: {
      recipient: {
        capabilities: {
          stripe_balance: { stripe_transfers: { status: 'active' } },
        },
      },
    },
  };
  const restrictedRecipient = {
    configuration: {
      recipient: {
        capabilities: {
          stripe_balance: { stripe_transfers: { status: 'restricted' } },
        },
      },
    },
  };
  assert.equal(stripeV2RecipientTransferStatus(activeRecipient), 'active');
  assert.equal(stripeV2RecipientTransfersEnabled(activeRecipient), true);
  assert.equal(stripeV2RecipientTransfersEnabled(restrictedRecipient), false);
  assert.equal(stripeV2RecipientTransfersEnabled({ capabilities: { transfers: 'active' } }), false,
    'legacy compatibility fields must not make a v2 recipient ready');
});

test('Accounts v2 payloads use the Captro marketplace recipient configuration', () => {
  assert.equal(STRIPE_ACCOUNTS_V2_VERSION, '2026-08-26.dahlia');
  const account = stripeRecipientAccountPayload({
    contactEmail: 'creator@example.com', displayName: 'Creator', country: 'US',
    authUserId: 'auth-fixture', appUserId: 'app-fixture',
  });
  assert.equal(account.dashboard, 'express');
  assert.equal(account.configuration.recipient.capabilities.stripe_balance.stripe_transfers.requested, true);
  assert.equal(account.defaults.responsibilities.fees_collector, 'application');
  assert.equal(account.defaults.responsibilities.losses_collector, 'application');
  assert.equal('merchant' in account.configuration, false);
  const link = stripeRecipientOnboardingPayload('acct_fixture', 'https://captro.app/refresh', 'https://captro.app/return');
  assert.deepEqual(link.use_case.account_onboarding.configurations, ['recipient']);
  assert.equal(link.use_case.account_onboarding.collection_options.fields, 'eventually_due');
});

test('buyer fees are configurable while the creator receives the full listed item amount', () => {
  assert.match(worker, /CAPTRO_SERVICE_FEE_BPS/);
  assert.match(worker, /CAPTRO_SERVICE_FEE_FIXED_CENTS/);
  assert.match(money, /creatorAmount: cents\(item - creatorDeduction\)/);
  assert.match(money, /buyerTotal: cents\(item \+ serviceFeeAmount/);
  assert.doesNotMatch(worker, /'payment_intent_data\[transfer_data\]\[destination\]'/);
  assert.doesNotMatch(worker, /'payment_intent_data\[transfer_data\]\[amount\]'/);
  assert.match(worker, /stripeApiRequest\(c, '\/transfers'/);
  assert.match(worker, /source_transaction: chargeId/);
  assert.match(worker, /destination: purchase\.stripe_destination_account_id/);
  assert.match(worker, /`transfer:\$\{purchase\.id\}`/);
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
  assert.match(worker, /async function marketplaceSettlementForIntent/);
  assert.match(worker, /\/charges\/\$\{encodeURIComponent\(chargeId\)\}\?expand\[\]=balance_transaction/);
  assert.match(worker, /\/transfers\?transfer_group=\$\{encodeURIComponent\(transferGroup\)\}/);
  assert.match(worker, /stripeExpandableId\(transfer\.source_transaction, 'ch_'\)/);
  assert.match(worker, /'payment_intent_data\[transfer_group\]'/);
  assert.match(worker, /status-reconcile-\$\{intent\.data\.id\}/);
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
  assert.match(worker, /STRIPE_DISPUTE_REVERSAL_REQUIRED/);
  assert.match(worker, /status: 'reversed', disputed_amount: cents\(reversal.data.amount\)/);
  assert.match(worker, /app_payment_reconciliation_issues/);
  assert.match(worker, /status: 'revoked'/);
});

test('creator and admin refunds share one Stripe path with financial authorization and audit', () => {
  assert.match(worker, /async function refundMarketplacePurchase/);
  assert.match(worker, /api\.post\('\/commerce\/purchases\/:purchaseId\/refund'/);
  assert.match(worker, /creator_id: postgrestEqFilter\(creatorAuthId\)/);
  assert.match(worker, /api\.post\('\/admin\/commerce\/purchases\/:purchaseId\/refund'/);
  assert.match(worker, /requireAdminRole\(c, 'payments:refund'\)/);
  assert.match(worker, /'payments:refund'/);
  assert.match(worker, /actionType: 'commerce_purchase_refunded'/);
  assert.match(worker, /writeAdminAuditLog\(c, admin/);
  assert.equal((worker.match(/stripeApiRequest\(c, '\/refunds'/g) || []).length, 1,
    'all commerce refund entry points must use the same Stripe operation');
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

test('Profile payment cards use Stripe CustomerSheet and never store raw card data', () => {
  assert.match(buyerCardsMigration, /create table public\.app_stripe_customers/);
  assert.match(buyerCardsMigration, /unique \(user_id, stripe_mode\)/);
  assert.match(buyerCardsMigration, /enable row level security/);
  assert.match(buyerCardsMigration, /revoke all .* from anon, authenticated/);
  assert.match(buyerCardsMigration, /grant all .* to service_role/);
  assert.doesNotMatch(buyerCardsMigration, /card_number|\bcvc\b|card_token|expiry_month/i);
  assert.match(worker, /api\.post\('\/commerce\/payment-methods\/session'/);
  assert.match(worker, /api\.post\('\/commerce\/payment-methods\/setup-intent'/);
  assert.match(worker, /'components\[customer_sheet\]\[enabled\]': true/);
  assert.match(worker, /'components\[mobile_payment_element\]\[features\]\[payment_method_save\]': 'enabled'/);
  assert.match(worker, /'payment_method_types\[0\]': 'card'/);
  assert.match(worker, /usage: 'on_session'/);
  assert.match(worker, /customer: customerId/);
  assert.match(payments, /CustomerSheet\.IntentConfiguration\(paymentMethodTypes: \["card"\]\)/);
  assert.match(payments, /billingDetailsCollectionConfiguration\.name = \.always/);
  assert.match(payments, /CustomerSessionClientSecret/);
  assert.doesNotMatch(payments, /TextField\([^\n]*(card number|cvc|expiration)/i);
  assert.match(profile, /systemImage: "creditcard"[\s\S]{0,120}accessibilityLabel: "Payments"/);
});

test('native checkout displays saved buyer cards while payout remains debit-only', () => {
  assert.match(commerceModels, /customerSessionClientSecret: String\?/);
  assert.match(paymentSheet, /settings\.customer = \.init/);
  assert.match(paymentSheet, /customerSessionClientSecret: customerSessionClientSecret/);
  assert.match(payments, /Debit and credit cards saved here are available when you pay in Captro/);
  assert.match(payments, /Credit cards cannot receive payouts/);
  assert.match(worker, /eligibleDebitCard/);
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
