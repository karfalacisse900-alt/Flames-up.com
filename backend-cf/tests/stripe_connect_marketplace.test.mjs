import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import {
  STRIPE_ACCOUNTS_V2_VERSION,
  stripeRecipientAccountPayload,
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
const stripeModeMigration = source('../../supabase/migrations/20260908224758_isolate_stripe_connected_accounts_by_mode.sql');
const customPayoutMigration = source('../../supabase/migrations/20260912214322_captro_custom_payout_accounts.sql');
const commerceModels = source('../../ios_native/MIRA/Sources/MIRANative/Models/CaptroCommerce.swift');
const earnings = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceDashboardViews.swift');
const payments = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroPaymentsView.swift');
const paymentSheet = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroPaymentSheetView.swift');
const profile = source('../../ios_native/MIRA/Sources/MIRANative/Screens/ProfileChatVerificationStudio.swift');
const checkout = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceDetailViews.swift');
const composer = source('../../ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift');
const payoutOnboarding = source('../../ios_native/MIRA/Sources/MIRANative/Services/CaptroPayoutOnboardingCoordinator.swift');
const packageManifest = source('../../ios_native/MIRA/Package.swift');
const cache = source('../../ios_native/MIRA/Sources/MIRANative/Services/MIRAAppCacheStore.swift');
const homeStamp = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroFeedPostOverlays.swift');
const homePost = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroFeedPostView.swift');
const details = source('../../ios_native/MIRA/Sources/MIRANative/Screens/PostDetailNativeView.swift');

test('Stripe Connect stores Captro-managed payout accounts without raw card data or hosted account links', () => {
  assert.match(migration, /create table public\.app_connected_accounts \(/);
  assert.match(migration, /provider_account_id text not null unique/);
  assert.match(stripeModeMigration, /app_connected_accounts \(user_id, stripe_mode\)/);
  assert.match(migration, /external_account_last4 text/);
  assert.doesNotMatch(migration, /\b(?:routing_number|account_number|debit_card_number|bank_token)\b/i);
  assert.match(worker, /stripeApiV2Request\(c, '\/core\/accounts'/);
  assert.doesNotMatch(worker, /\/core\/account_links/);
  assert.match(connectV2, /dashboard: 'none'/);
  assert.match(connectV2, /fees_collector: 'application'/);
  assert.match(connectV2, /losses_collector: 'application'/);
  assert.match(connectV2, /stripe_transfers: \{ requested: true \}/);
  assert.match(connectV2, /include: \['configuration\.recipient'/);
  assert.doesNotMatch(connectV2, /account_onboarding/);
  assert.doesNotMatch(worker, /stripeApiRequest\(c, '\/accounts'/);
  assert.doesNotMatch(worker, /\/login_links/);
  assert.doesNotMatch(worker, /payout-account\/debit-card/);
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

test('connected accounts and reusable catalog IDs are isolated by Stripe mode', () => {
  assert.match(stripeModeMigration, /add column if not exists stripe_mode text/);
  assert.match(stripeModeMigration, /app_connected_accounts \(user_id, stripe_mode\)/);
  assert.match(stripeModeMigration, /app_connected_accounts \(app_user_id, stripe_mode\)/);
  assert.match(stripeModeMigration, /stripe_product_mode text/);
  assert.match(stripeModeMigration, /stripe_price_mode text/);
  assert.match(stripeModeMigration, /stripe_mode = current_stripe_mode/);
  assert.match(worker, /user_id: postgrestEqFilter\(authUserId\),[\s\S]{0,120}stripe_mode: postgrestEqFilter\(configuredStripeMode\(c\)\)/);
  assert.match(worker, /stripe_mode: stripeMode,/);
  assert.match(worker, /purchasable\?\.stripe_product_mode !== stripeMode/);
  assert.match(worker, /price\?\.stripe_price_mode !== stripeMode/);
});

test('only an untouched current-mode Express payout profile can migrate to Captro-managed Custom', () => {
  const migration = worker.match(/async function legacyExpressPayoutProfileCanMigrate[\s\S]*?\n}\n\nasync function createRecipientStripeAccount/)?.[0] || '';
  const upgrade = worker.match(/async function migrateUntouchedLegacyExpressPayoutAccount[\s\S]*?\n}\n\nasync function createOrLoadConnectedAccount/)?.[0] || '';
  const connectWebhook = worker.match(/event\.type === 'account\.updated'[\s\S]*?\n    } else if \(event\.type === 'balance\.available'/)?.[0] || '';
  assert.match(migration, /row\?\.stripe_mode !== configuredStripeMode\(c\)/);
  assert.match(migration, /account_type, 20\)\.toLowerCase\(\) !== 'express'/);
  assert.match(migration, /cleanText\(account\?\.type, 20\)\.toLowerCase\(\) === 'express'/);
  assert.match(migration, /connectedAccountDashboard\(account, accountV2\) === 'express'/);
  assert.match(migration, /connectedAccountOwnerIsComplete\(remoteOwner\)/);
  assert.match(migration, /payoutProfileHasLocalSetup\(row\)/);
  assert.match(migration, /legacyConnectedAccountHasFinancialActivity/);
  assert.match(migration, /stripeBalanceIsEmpty\(balanceResult\.data\)/);
  assert.match(migration, /\/transfers\?destination=\$\{encodeURIComponent\(accountId\)\}/);
  assert.match(migration, /\/balance_transactions\?limit=100/);
  assert.match(migration, /\/payouts\?limit=100/);
  assert.match(upgrade, /migratedFromAccountId: legacyAccountId/);
  assert.match(upgrade, /captro-managed-payout-upgrade-/);
  assert.match(upgrade, /captro_upgrade_untouched_payout_account/);
  assert.match(customPayoutMigration, /set search_path = ''/);
  assert.match(customPayoutMigration, /pg_catalog\.left/);
  assert.match(customPayoutMigration, /pg_catalog\.now\(\)/);
  assert.match(customPayoutMigration, /details_submitted is distinct from false/);
  assert.match(customPayoutMigration, /eligible_debit_card_exists is distinct from false/);
  assert.match(customPayoutMigration, /from public\.app_connected_accounts[\s\S]*?for update/);
  assert.match(customPayoutMigration, /app_creator_earnings/);
  assert.match(customPayoutMigration, /app_payouts/);
  assert.match(customPayoutMigration, /app_payout_requests/);
  assert.match(customPayoutMigration, /app_retired_connected_accounts/);
  assert.match(connectWebhook, /activeRows\.length > 0/);
  assert.doesNotMatch(connectWebhook, /\|\| !connectedAccountHasPendingMigration/);
  assert.match(worker, /CAPTRO_PAYOUT_PROFILE_UPGRADE_REQUIRED/);
  assert.match(worker, /CAPTRO_PAYOUT_ACCOUNT_CONFLICT/);
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
  assert.equal(account.dashboard, 'none');
  assert.equal(account.configuration.recipient.capabilities.stripe_balance.stripe_transfers.requested, true);
  assert.equal(account.defaults.responsibilities.fees_collector, 'application');
  assert.equal(account.defaults.responsibilities.losses_collector, 'application');
  assert.equal('merchant' in account.configuration, false);
  const migrationAccount = stripeRecipientAccountPayload({
    contactEmail: 'creator@example.com', displayName: 'Creator', country: 'US',
    authUserId: 'auth-fixture', appUserId: 'app-fixture', migratedFromAccountId: 'acct_legacy',
  });
  assert.equal(migrationAccount.metadata.migrated_from_account_id, 'acct_legacy');
  assert.equal(migrationAccount.metadata.captro_payout_migration_pending, 'acct_legacy');
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
  assert.match(commerceModels, /post\("\/commerce\/payout-account\/session"/);
  assert.doesNotMatch(commerceModels, /payout-account\/onboarding-link/);
  assert.match(worker, /api\.post\('\/commerce\/payout-account\/session'/);
  assert.match(worker, /stripeApiGet\(c, '\/balance\?expand\[\]=instant_available\.net_available', account\.provider_account_id\)/);
  assert.match(worker, /stripeApiGet\(c, '\/payouts\?limit=100', account\.provider_account_id\)/);
  assert.match(earnings, /Text\("Balance unavailable"\)/);
  assert.match(earnings, /Add a payout debit card to receive money from paid posts\./);
  assert.match(earnings, /separate payout debit card/);
  assert.match(commerceModels, /var payoutCardActionTitle: String/);
  assert.doesNotMatch(`${earnings}\n${payments}\n${composer}`, /Set Up Earnings|Connect Stripe Account/i);
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
  assert.match(payments, /billingDetailsCollectionConfiguration\.address = \.full/);
  assert.match(payments, /CustomerSessionClientSecret/);
  assert.doesNotMatch(payments, /TextField\([^\n]*(card number|cvc|expiration)/i);
  assert.match(profile, /systemImage: "creditcard"[\s\S]{0,120}accessibilityLabel: "Payments"/);
});

test('native checkout displays saved buyer cards while payout remains debit-only', () => {
  assert.match(commerceModels, /customerSessionClientSecret: String\?/);
  assert.match(paymentSheet, /settings\.customer = \.init/);
  assert.match(paymentSheet, /customerSessionClientSecret: customerSessionClientSecret/);
  assert.match(paymentSheet, /billingDetailsCollectionConfiguration\.name = \.always/);
  assert.match(paymentSheet, /billingDetailsCollectionConfiguration\.address = \.full/);
  assert.match(payments, /Debit and credit cards saved here are available when you pay in Captro/);
  assert.match(payments, /no Stripe account connection is needed for purchases/);
  assert.match(payments, /Credit cards cannot receive payouts/);
  assert.match(payments, /SELLER PAYOUT CARD/);
  assert.doesNotMatch(payments, /Use .* for Payouts/);
  assert.doesNotMatch(payments, /payoutDebitCardPendingConfirmation/);
  assert.match(packageManifest, /\.product\(name: "StripeConnect"/);
  assert.match(worker, /eligibleDebitCard/);
  const paymentIntent = worker.slice(worker.indexOf('async function createCommercePaymentIntent'), worker.indexOf('async function completeCommercePurchaseFromIntent'));
  assert.match(paymentIntent, /buyerStripeCustomerForUser/);
  assert.match(paymentIntent, /stripeApiRequest\(c, '\/payment_intents'/);
  assert.doesNotMatch(paymentIntent, /stripeAccount|Stripe-Account|on_behalf_of/);
});

test('native payout requests accept Codable snake_case identifiers', () => {
  assert.match(worker, /body\.requestId \|\| body\.request_id/);
  assert.match(worker, /body\.quoteId \|\| body\.quote_id/);
});

test('paid-post onboarding preserves the creator draft and media selection', () => {
  assert.match(cache, /var commerceDraft: CaptroCommerceDraft\? = nil/);
  assert.match(composer, /preparePayoutAccountForPublishing/);
  assert.match(composer, /persistComposerDraft/);
  assert.match(composer, /CaptroPayoutOnboardingCoordinator/);
  assert.match(composer, /payoutOnboarding\.start\(api: api\)/);
});

test('seller payout onboarding stays inside Captro with embedded Stripe collection and no Express link', () => {
  assert.match(packageManifest, /\.product\(name: "StripeConnect"/);
  assert.match(worker, /stripeApiRequest\(c, '\/account_sessions'/);
  assert.match(worker, /'components\[account_onboarding\]\[enabled\]': true/);
  assert.match(worker, /'components\[account_onboarding\]\[features\]\[external_account_collection\]': true/);
  assert.match(worker, /'components\[account_onboarding\]\[features\]\[disable_stripe_user_authentication\]': true/);
  assert.match(worker, /STRIPE_PAYOUT_ACCOUNT_SESSION_VERSION = '2024-10-28\.acacia'/);
  assert.match(worker, /undefined, undefined, STRIPE_PAYOUT_ACCOUNT_SESSION_VERSION/);
  assert.match(worker, /features\?\.external_account_collection !== true/);
  assert.match(worker, /features\?\.disable_stripe_user_authentication !== true/);
  assert.match(payoutOnboarding, /EmbeddedComponentManager/);
  assert.match(payoutOnboarding, /createPayoutAccountSession\(\)/);
  assert.match(payoutOnboarding, /createAccountOnboardingController/);
  assert.match(payoutOnboarding, /AccountOnboardingControllerDelegate/);
  assert.doesNotMatch(worker, /\/core\/account_links|\/login_links/);
  assert.doesNotMatch(worker, /payout-account\/debit-card/);
  assert.doesNotMatch(payoutOnboarding, /ASWebAuthenticationSession|SFSafariViewController|WKWebView/);
});

test('embedded payout onboarding never opens a Stripe-hosted browser or accepts raw card data', () => {
  assert.doesNotMatch(payoutOnboarding, /UIApplication\.shared\.open|captroPayoutOnboardingCallback|applicationDidBecomeActive/);
  assert.doesNotMatch(payoutOnboarding, /STPCardParams|createToken\(withCard|tok_/);
  assert.match(payoutOnboarding, /COMMERCE_PAYOUT_EMAIL_REQUIRED/);
  assert.match(payoutOnboarding, /CAPTRO_PAYOUT_ACCOUNT_CONFLICT/);
  assert.match(payoutOnboarding, /payoutSetupUnavailable/);
  assert.doesNotMatch(payoutOnboarding, /Reference:/);
});

test('payout setup errors are safe for users and never expose database responses', () => {
  const payoutSession = worker.match(/api\.post\('\/commerce\/payout-account\/session'[\s\S]*?\n}\);\n\napi\.post\('\/commerce\/payout-account\/onboarding-link'/)?.[0] || '';
  const payoutOnboardingRoute = worker.match(/api\.post\('\/commerce\/payout-account\/onboarding-link'[\s\S]*?\n}\);\n\napi\.post\('\/commerce\/payout-account\/manage-link'/)?.[0] || '';
  assert.match(worker, /function payoutSetupFailure/);
  assert.match(worker, /CAPTRO_PAYOUT_SETUP_UNAVAILABLE/);
  assert.match(payoutSession, /payoutSetupFailure\(error\)/);
  assert.match(payoutOnboardingRoute, /CAPTRO_PAYOUT_APP_UPDATE_REQUIRED/);
  assert.match(payoutOnboardingRoute, /Update Captro to manage your payout card\./);
  assert.match(payoutOnboardingRoute, /}, 410\);/);
  assert.doesNotMatch(payoutSession, /const code = getErrorCode\(error\)/);
  assert.doesNotMatch(payoutOnboardingRoute, /SUPABASE_|23505|duplicate key/);
});

test('checkout distinguishes seller readiness from temporary Stripe failures', () => {
  assert.match(worker, /Your saved payment card was not charged/);
  assert.match(worker, /commerce_creator_payout_check_failed/);
  assert.match(worker, /code !== 'CAPTRO_PAYOUTS_NOT_READY'/);
});

test('Details removes the lower reaction strip while Home stamps expose a red save control', () => {
  assert.equal((details.match(/reactionRow\(/g) || []).length, 1, 'reactionRow must remain unused except for its private declaration');
  assert.match(details, /detailHeader/);
  assert.match(homeStamp, /Image\(systemName: isSaved \? "bookmark\.fill" : "bookmark"\)/);
  assert.match(homeStamp, /foregroundStyle\(MIRATheme\.Color\.like\)/);
  assert.match(homePost, /isSaved: post\.viewerSaved, onSave: onSave/);
});
