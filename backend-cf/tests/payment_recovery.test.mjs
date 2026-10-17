import test from 'node:test';
import assert from 'node:assert/strict';
import {resolvePaymentRecovery} from '../src/payment-recovery.ts';
import {runPurchaseReconciliation} from '../src/purchase-reconciliation.ts';

function fixture(decision='refund') {
 const record={status:'needs_review',provider_payment_id:'pi_fixture',amount:1000,currency:'USD',decision,decision_started_at:'2035-01-01T00:00:00Z'};
 const intent={id:'pi_fixture',status:'succeeded',livemode:false,amount_received:1000,currency:'usd',latest_charge:'ch_fixture',metadata:{source:'captro_commerce',captro_purchase_id:'purchase'}};
 const charge={id:'ch_fixture',payment_intent:'pi_fixture',paid:true,status:'succeeded',amount_captured:1000,currency:'usd',amount_refunded:0,balance_transaction:null};
 const refund={id:'re_fixture',payment_intent:'pi_fixture',amount:1000,currency:'usd',status:'succeeded',metadata:{captro_recovery_purchase_id:'purchase'}};
 const calls=[],stored=[];
 const io={purchase:{id:'purchase',total_amount:1000,currency:'USD',stripe_mode:'test',settlement_model:'deferred'},liveMode:false,
  claim:async()=>record,readIntent:async()=>intent,readCharge:async()=>charge,listRefunds:async()=>({data:stored,has_more:false}),now:()=>Date.parse('2035-01-01T00:00:01Z'),
  createRefund:async(id,amount,key)=>{calls.push(['refund',id,amount,key]);stored.push(refund);return refund;},
  resolve:async(_r,status,reference)=>{calls.push(['resolve',status,reference]);return {status};}};
 return {io,record,intent,charge,refund,calls,stored};
}
test('authorized full refund uses a stable key; lost response is reconciled before replay',async()=>{
 const f=fixture();f.io.createRefund=async(id,amount,key)=>{f.calls.push([id,amount,key]);f.stored.push(f.refund);throw Error('lost response');};
 await assert.rejects(resolvePaymentRecovery(f.io),/lost response/);
 assert.equal((await resolvePaymentRecovery(f.io)).status,'refunded');
 assert.equal(f.calls.filter(x=>x[0]==='pi_fixture').length,1);
 assert.deepEqual(f.calls[0],['pi_fixture',1000,'recovery-refund:purchase']);
});
test('processing refund remains unresolved; expired idempotency window cannot create a new refund',async()=>{
 const f=fixture();f.refund.status='pending';
 assert.equal((await resolvePaymentRecovery(f.io)).status,'refund_pending');
 assert.equal(f.calls.some(x=>x[0]==='resolve'),false);
 const old=fixture();old.io.now=()=>Date.parse('2035-01-03T00:00:00Z');
 await assert.rejects(resolvePaymentRecovery(old.io),/MANUAL_ACCOUNTING/);assert.equal(old.calls.length,0);
});
test('wrong buyer purchase, mode, amount, refund or transferred/disputed charge never resolves',async()=>{
 for(const mutate of [f=>f.intent.metadata.captro_purchase_id='other',f=>f.intent.amount_received=999,
   f=>f.intent.livemode=true,f=>f.charge.transfer='tr_other',f=>f.charge.disputed=true,
   f=>f.refund.amount=999,f=>f.refund.payment_intent='pi_other']) {
  const f=fixture();mutate(f);await assert.rejects(resolvePaymentRecovery(f.io));
  assert.equal(f.calls.some(x=>x[0]==='resolve'),false);
 }
});
test('fulfillment never refunds and rejects already-refunded charges',async()=>{
 const f=fixture('fulfill');assert.equal((await resolvePaymentRecovery(f.io)).status,'fulfilled');
 assert.equal(f.calls.some(x=>x[0]==='refund'),false);
 f.charge.amount_refunded=1000;await assert.rejects(resolvePaymentRecovery(f.io),/REFUND_IN_FLIGHT/);
});
test('batch bounds four provider operations and distinguishes processing, missing identity and failure',async()=>{
 const jobs=Array.from({length:40},(_,i)=>({purchase:{id:i,provider_payment_id:i%2?'pi_fixture':null},token:String(i),attempts:1,age_seconds:0}));
 let active=0,peak=0;const outcomes=[];
 const result=await runPurchaseReconciliation({claim:async()=>jobs,renew:async j=>j.purchase.id!==39,
  inspect:async p=>{active++;peak=Math.max(peak,active);await new Promise(r=>setTimeout(r,2));active--;if(p.id%3===0)throw Error('secret not logged');return p.id%3===1?'processing':'confirmed';},
  finish:async(j,outcome)=>{outcomes.push([j.purchase.id,outcome]);return true;}});
 assert.equal(peak,4);assert.equal(outcomes.length,39);assert.equal(result.lostLease,1);
 assert.ok(outcomes.some(x=>x[1]==='missing_identity'));assert.ok(outcomes.some(x=>x[1]==='transient_failure'));
 assert.equal(result.completed,13);assert.equal(result.deferred,26);
});
