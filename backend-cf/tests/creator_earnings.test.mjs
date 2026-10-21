import test from 'node:test';
import assert from 'node:assert/strict';
import {Hono} from 'hono';
import {registerCreatorEarningsRoutes,creatorPools,poolPayload,earningsPage} from '../src/creator-earnings.ts';
import {supportReadiness} from '../src/support-readiness.ts';

const money={category:'creator_support',currency:'USD',gross_received:'500',refunded:'0',captro_fee:'0',processing_fee:'59',creator_net:'441',pending:'441',available:'0',paid_out:'0',held:'0'};
function fixture() {
  const app=new Hono();let fail=false,readinessFail=false;const requests=[];
  registerCreatorEarningsRoutes(app,async(c,next)=>{
    if(c.req.header('Authorization')!=='creator-a')return c.json({code:'SESSION_INVALID'},401);
    await next();
  },{
    identity:async()=>({sellerId:'trusted-a',mode:'test',currency:'USD'}),limit:async()=>null,eq:v=>'eq.'+v,
    query:async(c,table,options)=>{
      requests.push({table,...options});if(fail)throw Error('private provider details');
      assert.equal(options.filters.seller_id,'eq.trusted-a');assert.equal(options.filters.stripe_mode,'eq.test');
      if(table==='app_creator_finance_pools')return [{...money,transactions:'1'}];
      assert.equal(options.filters.category,'eq.creator_support');assert.equal(options.filters.currency,'eq.USD');
      return Array.from({length:options.limit},(_,i)=>({...money,earning_id:'earning-'+(options.offset+i),order_id:'order-'+i,
        payout_id:'payout-'+i,attributed_amount:441,payout_amount:700,payout_fee:17,status:'pending'}));
    },
    readiness:async()=>{if(readinessFail)throw Error('provider failed');return {status:'blocked',retryable:false,blockers:[]};},
  });
  return {requests,get:(path,auth='creator-a')=>app.request(path,{headers:auth?{Authorization:auth}:{}}),
    fail:()=>fail=true,readinessFail:()=>readinessFail=true};
}
test('owner-only pool API adds Event Club Meetup Support without mixing currencies or treating unknown fees as zero',async()=>{
 const f=fixture();assert.equal((await f.get('/commerce/earnings/pools','')).status,401);
 assert.equal((await f.get('/commerce/earnings/pools','revoked')).status,401);
 const response=await f.get('/commerce/earnings/pools');assert.equal(response.status,200);
 assert.equal(response.headers.get('cache-control'),'private, no-store');
 const data=await response.json();assert.equal(data.payoutScope,'creator_currency_all_categories_fifo');
 assert.deepEqual(data.pools.map(p=>p.category),['event','club','meetup','creator_support']);
 assert.equal(data.pools[3].processingFees,59);assert.equal(data.pools[3].pending,441);
 const currencies=creatorPools([{...money,currency:'CAD',processing_fee:null,creator_net:null}],'USD');
 assert.equal(currencies.find(p=>p.currency==='CAD').creatorNet,null);
 assert.equal(currencies.find(p=>p.category==='creator_support'&&p.currency==='USD').grossReceived,0);
 assert.throws(()=>poolPayload({...money,gross_received:'9007199254740993'}));
});
test('forged seller, mode, malformed paging and unknown categories cannot redirect ownership',async()=>{
 const f=fixture();
 for(const path of ['/commerce/earnings/pools?seller_id=other','/commerce/earnings/pools?stripe_mode=live',
   '/commerce/earnings/pools/creator_support?currency=USD&seller_id=other','/commerce/earnings/pools/unknown?currency=USD',
   '/commerce/earnings/pools/creator_support?currency=USD&limit=51','/commerce/earnings/pools/creator_support?currency=USD&offset=-1'])
   assert.equal((await f.get(path)).status,400,path);
 assert.equal(f.requests.length,0);
 assert.throws(()=>earningsPage({currency:'USD&seller_id=other'}));
});
test('bounded paginated transactions and payouts preserve source attribution, not another balance',async()=>{
 const f=fixture();const page=await(await f.get('/commerce/earnings/pools/creator_support?currency=USD&limit=2&offset=2')).json();
 assert.equal(page.items.length,2);assert.equal(page.nextOffset,4);assert.equal(page.items[0].id,'earning-2');
 const payout=await(await f.get('/commerce/earnings/pools/creator_support?currency=USD&section=payouts&limit=1')).json();
 assert.equal(payout.items.length,1);assert.equal(payout.items[0].attributedAmount,441);assert.equal(payout.items[0].payoutAmount,700);
 assert.equal(payout.items[0].payoutFee,17);assert.equal(f.requests[1].limit,2);
 assert.ok(!JSON.stringify(payout).includes('buyer'));
});
test('query failure never becomes zero funds; independent readiness failure keeps ledger usable',async()=>{
 const f=fixture();f.readinessFail();let r=await f.get('/commerce/earnings/pools');
 assert.equal(r.status,200);const data=await r.json();assert.equal(data.pools[3].grossReceived,500);
 const readiness=await(await f.get('/commerce/earnings/support-readiness')).json();
 assert.equal(readiness.status,'unavailable');f.fail();r=await f.get('/commerce/earnings/pools');
 assert.equal(r.status,503);const body=await r.json();assert.equal(body.code,'EARNINGS_READ_FAILED');
 assert.equal(body.pools,undefined);assert.ok(!JSON.stringify(body).includes('private provider'));
});
const ready={mode:'test',enabled:true,providerVerified:true,enrolled:true,manualRequired:true,identityRequired:false,identityVerified:false,
 account:{status:'ready',details_submitted:true,transfers_enabled:true,payouts_enabled:true,eligible_debit_card_exists:true,
 payout_schedule:'manual',requirements_currently_due:[]}};
test('owner diagnostics distinguish Stripe requirements, Captro gates and unknown provider state without creating accounts',()=>{
 assert.equal(supportReadiness(ready).status,'ready');
 const r=supportReadiness({...ready,mode:'live',enabled:false,account:{...ready.account,payout_schedule:'daily',
  requirements_currently_due:['individual.verification.document'],transfers_enabled:false}});
 assert.ok(r.blockers.some(b=>b.source==='captro'&&b.code==='rollout_disabled'));
 assert.ok(r.blockers.some(b=>b.source==='captro'&&b.code==='manual_schedule_required'));
 assert.ok(r.blockers.some(b=>b.source==='stripe'&&b.code==='transfers_inactive'));
 assert.ok(r.blockers.some(b=>b.source==='stripe'&&b.code==='requirement:individual.verification.document'));
 const unknown=supportReadiness({...ready,providerVerified:false});
 assert.equal(unknown.retryable,true);assert.deepEqual(unknown.blockers.map(b=>b.code),['provider_unavailable']);
 assert.equal(supportReadiness({...ready,account:null}).blockers[0].code,'payout_setup_required');
 assert.equal(supportReadiness({...ready,enrolled:false}).blockers[0].source,'captro');
});
