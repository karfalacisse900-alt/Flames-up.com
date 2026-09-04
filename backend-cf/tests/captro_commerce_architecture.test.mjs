import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import {
  captroCommerceTestSupport,
  publicCommercePayload,
  validateCommerceInput,
} from '../src/commerce.ts';

const source = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const worker = source('../src/index.ts');
const migration = source('../../supabase/migrations/20260904193517_captro_commerce_entitlements.sql');
const composer = source('../../ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift');
const editor = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceEditor.swift');
const details = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceDetailViews.swift');
const dashboard = source('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceDashboardViews.swift');

const baseOptions = {
  postType: 'event',
  title: 'Rooftop Party',
  description: 'One shared checkout and entitlement path.',
  visibility: 'public',
  location: 'Westlight Rooftop',
  city: 'Brooklyn',
};

test('all supported commerce post types resolve to one of the shared entitlement kinds', () => {
  assert.deepEqual(
    Object.fromEntries(Object.entries(captroCommerceTestSupport.FULFILLMENT_BY_TYPE)),
    {
      offer: 'order',
      deal: 'redemption',
      club: 'membership',
      group: 'group_access',
      meetup: 'attendance',
      event: 'ticket',
      party: 'ticket',
      ticket: 'ticket',
      access_pass: 'ticket',
      booking: 'reservation',
      reservation: 'reservation',
    },
  );
  assert.deepEqual(
    [...captroCommerceTestSupport.CONTENT_TYPES].sort(),
    Object.keys(captroCommerceTestSupport.FULFILLMENT_BY_TYPE).sort(),
  );
});

test('creator input preserves type-specific public fields but never accepts private access state', () => {
  const config = validateCommerceInput({
    enabled: true,
    contentType: 'club',
    paymentModel: 'paid',
    commerceClass: 'outside_app',
    title: 'NYC Photo Club',
    capacity: 127,
    approvalRequired: true,
    prices: [{ label: 'One-time membership', unitAmount: 800, capacity: 127 }],
    publicData: { benefits: ['Monthly walk'], rules: ['Be kind'] },
    privateConfig: { groupChatId: 'attacker-controlled' },
    entitlement: { status: 'active' },
  }, baseOptions);
  assert.equal(config.purchasable.fulfillment_type, 'membership');
  assert.equal(config.purchasable.payment_model, 'paid');
  assert.equal(config.prices[0].unit_amount, 800);
  assert.deepEqual(config.purchasable.public_data, { benefits: ['Monthly walk'], rules: ['Be kind'] });
  assert.deepEqual(config.purchasable.private_config, {});
  assert.doesNotMatch(JSON.stringify(config), /attacker-controlled|groupChatId/);
});

test('free access is truly zero and paid prices cannot be less than fifty cents', () => {
  const free = validateCommerceInput({
    enabled: true,
    contentType: 'meetup',
    paymentModel: 'free',
    prices: [{ label: 'Join', unitAmount: 9999 }],
  }, baseOptions);
  assert.equal(free.prices[0].unit_amount, 0);
  assert.throws(() => validateCommerceInput({
    enabled: true,
    contentType: 'deal',
    paymentModel: 'paid',
    prices: [{ label: 'Deal', unitAmount: 49 }],
  }, baseOptions), /at least \$0\.50/);
});

test('the Home payload exposes compact commerce facts without private configuration', () => {
  const payload = publicCommercePayload({
    id: 'purchase-config',
    post_id: 'post-id',
    content_type: 'party',
    fulfillment_type: 'ticket',
    payment_model: 'paid',
    commerce_class: 'outside_app',
    title: 'Rooftop Party',
    description: 'Saturday night',
    capacity: 150,
    quantity_committed: 72,
    status: 'active',
    public_data: { ageRequirement: '21+' },
    private_config: { group_chat_id: 'private-chat' },
  }, [{
    id: 'price-id', purchasable_id: 'purchase-config', label: 'General', unit_amount: 2000,
    currency: 'USD', billing_period: 'one_time', capacity: 150, quantity_committed: 72, active: true,
  }]);
  assert.equal(payload.remaining, 78);
  assert.equal(payload.lowestPrice.unitAmount, 2000);
  assert.equal(payload.viewerDestinationId, null);
  assert.doesNotMatch(JSON.stringify(payload), /private-chat|private_config/);
});

test('money, inventory, purchases and access stay out of app_posts and behind service-role RLS', () => {
  for (const table of [
    'app_purchasables', 'app_prices', 'app_booking_slots', 'app_purchases', 'app_payments',
    'app_entitlements', 'app_commerce_tickets', 'app_commerce_memberships', 'app_commerce_orders',
    'app_commerce_bookings', 'app_commerce_redemptions', 'app_commerce_attendance',
  ]) {
    assert.match(migration, new RegExp(`create table public\\.${table} \\(`));
  }
  assert.match(migration, /alter table public\.%I enable row level security/);
  assert.match(migration, /revoke all on table public\.%I from public, anon, authenticated/);
  assert.match(migration, /grant all on table public\.%I to service_role/);
  assert.match(migration, /Commerce configuration linked one-to-one with a Captro post; app_posts never stores payment state/);
});

test('purchase snapshots are immutable inputs and payment confirmation alone issues access', () => {
  assert.match(migration, /item_title, price_label, quantity, unit_amount/);
  assert.match(migration, /price_row\.unit_amount \* p_quantity/);
  assert.match(migration, /if purchase_row\.status <> 'payment_pending' then raise exception 'CAPTRO_PURCHASE_NOT_PAYABLE'/);
  assert.match(migration, /if p_amount <> purchase_row\.total_amount or upper\(p_currency\) <> purchase_row\.currency/);
  assert.match(migration, /perform public\.captro_create_entitlement_for_purchase\(purchase_row\.id\)/);
  assert.match(worker, /verifyStripeWebhookSignature\(rawBody, signature, secret\)/);
  assert.match(worker, /source === 'captro_commerce'[\s\S]*?completeCommercePurchaseFromSession/);
  assert.doesNotMatch(worker, /success_url[\s\S]{0,300}captro_create_entitlement_for_purchase/);
});

test('digital goods cannot enter external card checkout while outside-app goods can', () => {
  assert.match(worker, /purchasable\.payment_model === 'paid' && purchasable\.commerce_class === 'digital'/);
  assert.match(worker, /COMMERCE_STOREKIT_REQUIRED/);
  assert.match(worker, /purchasables\[0\]\?\.commerce_class === 'digital'/);
  assert.match(editor, /In person \/ service/);
  assert.match(editor, /Digital access/);
});

test('booking inventory and QR passes are serialized and cannot be consumed twice', () => {
  assert.match(migration, /unique \(purchasable_id, starts_at\)/);
  assert.match(migration, /where purchasable_id = p_purchasable_id and starts_at = p_starts_at for update/);
  assert.match(migration, /CAPTRO_BOOKING_SLOT_UNAVAILABLE/);
  assert.match(migration, /select \* into ticket_row from public\.app_commerce_tickets where id = p_ticket_id for update/);
  assert.match(migration, /if ticket_row\.status <> 'active' then[\s\S]*?CAPTRO_PASS_ALREADY_USED/);
  assert.match(migration, /select \* into pass_row from public\.app_commerce_redemptions where id = p_redemption_id for update/);
  assert.match(worker, /constantTimeEqualHex\(signature, expected\)/);
});

test('creator, Details and Me surfaces use the shared commerce API without changing Home paging', () => {
  assert.match(composer, /CaptroCommerceEditorFields\(kind: selectedStampKind, draft: \$commerceDraft\)/);
  assert.match(composer, /commerce: commerceInput/);
  assert.match(details, /model\.performCommerceAction/);
  assert.match(details, /ConversationNativeView\([\s\S]*?groupId: destinationId/);
  assert.match(dashboard, /dashboardHeading\("My Stuff"\)/);
  assert.match(dashboard, /dashboardHeading\("Created"\)/);
  assert.match(dashboard, /CaptroPassScannerSheet/);
});
