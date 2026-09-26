import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const ui=readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroPaymentSheetView.swift',import.meta.url),'utf8');
const backend=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
test('retry refreshes the same purchase and requires a fresh explicit presentation',()=>{
 assert.match(ui,/continueCommerceCheckout\(purchaseId: purchase.id\)/);
 assert.match(ui,/guard !preparingPayment, !showingPayment, !confirming, !paid/);
 assert.match(ui,/needsFreshSession = true/);
 assert.match(ui,/savePaymentMethodOptInBehavior = .requiresOptIn/);
 assert.match(ui,/response.purchase.status == "confirmed"/);
 assert.doesNotMatch(ui,/confirmPaymentIntent|defaultPaymentMethod/);
});
test('PaymentSheet failures are logged in Release with safe correlation metadata',()=>{
 assert.match(ui,/Logger\(subsystem: "com.captro.app", category: "buyer-checkout"\)/);
 assert.match(ui,/StripeRequestIDKey/);assert.match(ui,/NSUnderlyingErrorKey/);
 assert.doesNotMatch(ui,/#if DEBUG|String\(describing:.*userInfo/);
});
test('intent creation never selects a saved card or seller destination',()=>{
 const flow=backend.split('async function createCommercePaymentIntent')[1].split('async function completeCommercePurchaseFromIntent')[0];
 assert.doesNotMatch(flow,/payment_method:|confirm: true|off_session:|requireReadyConnectedAccount\(/);
});
