import test from 'node:test';
import assert from 'node:assert/strict';
import {reliabilityRolloutBlocks as blocks} from '../src/reliability-rollout.ts';
test('coordinated rollout gates new sales without stopping payment confirmation, webhooks or entitlement reads',()=>{
  for(const path of ['/api/commerce/purchases','/api/checkout/create-payment-intent','/api/commerce/purchases/id/decision','/api/posts']) {
    assert.equal(blocks('maintenance','POST',path),true);
    assert.equal(blocks('ready','POST',path),false);
  }
  for(const [method,path] of [['POST','/api/stripe/webhook'],['POST','/api/commerce/purchases/id/complete'],['GET','/api/commerce/purchases/id'],['POST','/api/auth/login'],['POST','/api/messages']])
    assert.equal(blocks('maintenance',method,path),false);
});
