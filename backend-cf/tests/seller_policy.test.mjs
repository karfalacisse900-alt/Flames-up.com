import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { sellerGateFailure } from '../src/seller-policy.ts';

const source = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const worker = source('../src/index.ts');
const migration = source('../../supabase/migrations/20260925120000_seller_identity_verification.sql');
const earnings = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceDashboardViews.swift');

const ready = {
  connectReady: true, manualScheduleRequired: true, payoutSchedule: 'manual',
  identityRequired: true, identityStatus: 'verified',
};

test('a seller needs separate Identity, Connect, and manual payout readiness', () => {
  assert.equal(sellerGateFailure(ready), null);
  assert.equal(sellerGateFailure({ ...ready, identityStatus: 'processing' }), 'CAPTRO_SELLER_IDENTITY_REQUIRED');
  assert.equal(sellerGateFailure({ ...ready, identityStatus: 'requires_input' }), 'CAPTRO_SELLER_IDENTITY_REQUIRED');
  assert.equal(sellerGateFailure({ ...ready, connectReady: false }), 'CAPTRO_PAYOUTS_NOT_READY');
  assert.equal(sellerGateFailure({ ...ready, payoutSchedule: 'daily' }), 'CAPTRO_PAYOUT_SCHEDULE_REVIEW_REQUIRED');
  assert.equal(sellerGateFailure({ ...ready, identityRequired: false, identityStatus: null }), null);
});

test('buyer checkout is separate from seller identity and free creation', () => {
  const purchase = worker.match(/const beginCommercePurchaseHandler[\s\S]*?api\.post\('\/commerce\/purchases\/[^']+'/)?.[0] || '';
  assert.match(purchase, /buyerAuthId = await supabaseAuthUserIdForAppUserId/);
  assert.match(purchase, /purchasable\.creator_id/);
  assert.doesNotMatch(purchase, /createOrResumeSellerIdentitySession/);
  assert.match(worker, /commerceConfig\?\.purchasable\.payment_model === 'paid'/);
});

test('Identity records are backend-only and only Stripe can approve', () => {
  assert.match(migration, /unique \(user_id, stripe_mode\)/);
  assert.match(migration, /enable row level security/);
  assert.match(migration, /revoke all on table .* from public, anon, authenticated/);
  assert.doesNotMatch(migration, /(?:document_image|selfie_image|id_number|date_of_birth)\s/);
  assert.match(worker, /syncSellerIdentityFromStripe\(c, identity\)/);
  assert.match(worker, /session\?\.metadata\?\.captro_auth_user_id !== row\.user_id/);
  assert.match(worker, /identity\.verification_session\.verified/);
  assert.match(earnings, /Verification submitted\. Stripe is checking your information/);
  assert.doesNotMatch(earnings, /case \.success\(\.submitted\):[\s\S]{0,100}identityProgressMessage = "Identity verified/);
});

test('new seller schedules are manual; existing live schedules are not silently rewritten', () => {
  assert.match(worker, /setNewSellerManualPayoutSchedule\(c, created\.accountId\)/);
  assert.match(worker, /'settings\[payouts\]\[schedule\]\[interval\]': 'manual'/);
  assert.match(worker, /return getStripeConfig\(c\)\.mode === 'test'/);
  assert.match(worker, /if \(failure\) throw new Error\(failure\)/);
});
