import test from 'node:test';
import assert from 'node:assert/strict';
import {paymentErrorCode,purchaseFailureMessage} from '../src/purchase-errors.ts';
test('RPC names cannot hide actual capacity or permission exceptions',()=>{
 assert.equal(paymentErrorCode(new Error('SUPABASE_RPC_FAILED:captro_begin_marketplace_purchase_v2:400:CAPTRO_CAPACITY_REACHED')),'CAPTRO_CAPACITY_REACHED');
 assert.equal(paymentErrorCode(new Error('SUPABASE_RPC_FAILED:captro_confirm_marketplace_purchase:400:CAPTRO_PAYMENT_AMOUNT_MISMATCH')),'CAPTRO_PAYMENT_AMOUNT_MISMATCH');
 assert.equal(paymentErrorCode(new Error('SUPABASE_RPC_FAILED:captro_begin_marketplace_purchase_v2:500:connection timeout')),'COMMERCE_REQUEST_FAILED');
 assert.equal(paymentErrorCode(new Error('card_declined')),'STRIPE_CARD_DECLINED');
 assert.match(purchaseFailureMessage('STRIPE_CARD_DECLINED'),/another payment method/);
});
