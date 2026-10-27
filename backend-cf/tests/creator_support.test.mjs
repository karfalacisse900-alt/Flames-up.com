import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {Hono} from 'hono';
import {supportAmount,supportCheckoutParameters,supportTestEnabled,supportModeEnabled,supportToken,registerCreatorSupportRoutes,SupportError} from '../src/creator-support.ts';
const id='12345678-1234-4234-8234-123456789012';
const base={id,content_type:'creator_support',stripe_mode:'test',payment_interface:'checkout',settlement_model:'deferred',
  service_fee_amount:0,platform_fee_amount:0,tax_amount:0,buyer_id:'buyer-auth',buyer_app_user_id:'buyer',creator_id:'creator-auth',
  total_amount:500,currency:'USD',stripe_destination_account_id:'acct_server',hold_expires_at:'2030-01-01T00:35:00Z',status:'payment_pending'};
test('Support creation requires a matching explicit environment flag and production mode',()=>{
  assert.equal(supportModeEnabled({CAPTRO_CREATOR_SUPPORT:'test',STRIPE_MODE:'test',ENVIRONMENT:'test'}),true);
  assert.equal(supportModeEnabled({CAPTRO_CREATOR_SUPPORT:'live',STRIPE_MODE:'live',ENVIRONMENT:'production'}),true);
  assert.equal(supportTestEnabled({CAPTRO_CREATOR_SUPPORT:'test',STRIPE_MODE:'test',ENVIRONMENT:'test'}),true);
  for(const env of [{},{CAPTRO_CREATOR_SUPPORT:'live',STRIPE_MODE:'live',ENVIRONMENT:'test'},
    {CAPTRO_CREATOR_SUPPORT:'test',STRIPE_MODE:'test',ENVIRONMENT:'production'},
    {CAPTRO_CREATOR_SUPPORT:'test',STRIPE_MODE:'live',ENVIRONMENT:'production'},
    {CAPTRO_CREATOR_SUPPORT:'true',STRIPE_MODE:'live',ENVIRONMENT:'production'}])
    assert.equal(supportModeEnabled(env),false);
  assert.equal(supportTestEnabled({CAPTRO_CREATOR_SUPPORT:'live',STRIPE_MODE:'live',ENVIRONMENT:'production'}),false);
});
test('USD integers, bounded amount, no fee/tax/transfer overrides, canonical return',()=>{
  for(const value of [200,500,1000,2000,20000]) assert.equal(supportAmount(value,'USD'),value);
  for(const value of [null,'500',500.5,0,-1,20100,NaN,Infinity]) assert.throws(()=>supportAmount(value,'USD'));
  assert.throws(()=>supportAmount(500,'JPY'));
  const params=supportCheckoutParameters(base);
  assert.equal(params['line_items[0][price_data][unit_amount]'],500);
  assert.equal(params['payment_intent_data[transfer_group]'],'captro_purchase_'+id.replaceAll('-',''));
  assert.ok(params.success_url.startsWith('https://captro-site.pages.dev/support-creator/return?purchase_id='));
  assert.ok(!Object.keys(params).some(k=>/application_fee|transfer_data|line_items\[1\]|automatic_tax/.test(k)));
  for(const patch of [{platform_fee_amount:1},{stripe_mode:'preview'},{creator_id:'buyer-auth'},{total_amount:500.5}]) assert.throws(()=>supportCheckoutParameters({...base,...patch}));
  const live=supportCheckoutParameters({...base,stripe_mode:'live'});
  assert.equal(live['line_items[0][price_data][unit_amount]'],500);
  assert.ok(!Object.keys(live).some(k=>/application_fee|transfer_data/.test(k)));
});
test('handoff is deterministic per request but isolated by recipient, account and signing key',async()=>{
  const secret='s'.repeat(48),first=await supportToken(secret,'a','b',id);
  assert.match(first,/^[a-f0-9]{64}$/); assert.equal(await supportToken(secret,'a','b',id),first);
  assert.notEqual(await supportToken(secret,'other','b',id),first);
  assert.notEqual(await supportToken(secret,'a','other',id),first);
  await assert.rejects(supportToken('','a','b',id));
});
function fixture() {
 const app=new Hono(); let row=null,h=null,blocked=false,revoked=false,providerFailure=false,paid=false,creates=0;
 const hash=async value=>createHash('sha256').update(value).digest('hex');
 const services={enabled:c=>supportTestEnabled(c.env),mode:c=>c.env.STRIPE_MODE,hash,viewer:c=>c.get('viewer'),limit:async()=>null,
  authorize:async(c,buyer,creator)=>{if(providerFailure)throw new Error('private provider diagnostic');
   if(blocked||buyer!=='buyer'||creator!=='creator')throw new SupportError('CAPTRO_SUPPORT_UNAVAILABLE',403);
   return {buyerId:'buyer-auth',buyerAppId:'buyer',creatorId:'creator-auth',creatorAppId:'creator',accountId:'trusted-account',profile:{id:'creator',username:'fixture',display_name:'Fixture creator',avatar_url:null}};},
  validateBuyer:async()=>{if(revoked)throw new SupportError('CAPTRO_SUPPORT_SESSION_EXPIRED',401);},
  handoff:async(c,tokenHash)=>h?.token_hash===tokenHash?h:null,handoffById:async(c,value)=>h?.id===value?h:null,
  purchase:async(c,value)=>row?.id===value?row:null,
  rpc:async(c,name,args)=>{if(name==='captro_issue_support_handoff') {h ||= {id,...args,token_hash:args.p_token_hash,buyer_id:'buyer-auth',buyer_app_user_id:'buyer',creator_id:'creator-auth',creator_app_user_id:'creator',created_at:new Date().toISOString(),expires_at:new Date(Date.now()+7200000).toISOString()};return h;}
   assert.equal(args.p_connected_account_id,'trusted-account');if(row&&row.total_amount!==args.p_amount)throw new SupportError('CAPTRO_IDEMPOTENCY_CONFLICT');
   row||={...base,total_amount:args.p_amount};h.purchase_id=row.id;return row;},
  checkout:async(c,p)=>{if(providerFailure)throw new Error('provider failed; secret must not escape');creates++;return {url:'https://checkout.stripe.com/c/pay/cs_fixture'};},
  reconcile:async()=>{if(providerFailure)throw new Error('temporary failure');if(paid)row.status='confirmed';},
 };
 const auth=async(c,next)=>{const user=c.req.header('Authorization');if(!user)return c.json({code:'INVALID_TOKEN'},401);c.set('viewer',user);await next();};
 registerCreatorSupportRoutes(app,auth,services);
 const env={CAPTRO_CREATOR_SUPPORT:'test',STRIPE_MODE:'test',ENVIRONMENT:'test',JWT_SECRET:'s'.repeat(48)};
 const send=(path,body,headers={})=>app.request(path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',Origin:'https://captro-site.pages.dev',...headers},...(body?{body:JSON.stringify(body)}:{})},env);
 return {send,get row(){return row;},get h(){return h;},set enabled(v){env.CAPTRO_CREATOR_SUPPORT=v?'test':'blocked';},
  set blocked(v){blocked=v;},set revoked(v){revoked=v;},set paid(v){paid=v;},set providerFailure(v){providerFailure=v;}};
}
async function handoff(f) {
 const response=await f.send('/creator-support/handoffs',{creator_id:'creator',request_key:id,storefront:'USA'},{Authorization:'buyer'});
 assert.equal(response.status,200);const body=await response.json();return new URLSearchParams(new URL(body.url).hash.slice(1)).get('handoff');
}
test('actual route contract: authorization, trustworthy recipient, idempotent request and no redirect success',async()=>{
 const f=fixture();
 assert.equal((await f.send('/creator-support/handoffs',{creator_id:'creator',request_key:id,storefront:'USA'})).status,401);
 const token=await handoff(f);assert.equal(await handoff(f),token);
 assert.equal((await f.send('/creator-support/web/session',{token},{Origin:'https://evil.invalid'})).status,403);
 assert.equal((await f.send('/creator-support/web/session',{token:'f'.repeat(64)})).status,401);
 assert.equal((await f.send('/creator-support/web/checkout',{token,amount:500,currency:'USD',destination:'acct_forged'})).status,400);
 const response=await f.send('/creator-support/web/checkout',{token,amount:500,currency:'USD'});
 assert.equal(response.status,200);assert.equal((await response.json()).purchase.status,'confirming');
 assert.equal(f.row.status,'payment_pending');
 assert.equal((await f.send('/creator-support/purchases/'+id,null,{Authorization:'outsider'})).status,404);
 f.providerFailure=true;
 const failure=await f.send('/creator-support/web/status',{token});assert.equal(failure.status,503);assert.ok(!(await failure.text()).includes('secret'));
 assert.equal(f.row.status,'payment_pending','ambiguous provider response is not cancellation');
 f.providerFailure=false;f.paid=true;
 assert.equal((await (await f.send('/creator-support/web/status',{token})).json()).status,'confirmed');
 f.blocked=true;
 assert.equal((await f.send('/creator-support/web/checkout',{token,amount:500,currency:'USD'})).status,403);
 assert.equal((await f.send('/creator-support/web/status',{token})).status,200,'own payment status survives recipient opt-out');
 f.revoked=true;assert.equal((await f.send('/creator-support/web/status',{token})).status,401);
});
test('expired handoff cannot create/replay checkout; non-US native handoff is denied',async()=>{
 const f=fixture();const token=await handoff(f);f.h.expires_at='2000-01-01T00:00:00Z';
 assert.equal((await f.send('/creator-support/web/checkout',{token,amount:500,currency:'USD'})).status,401);
 assert.equal((await f.send('/creator-support/handoffs',{creator_id:'creator',request_key:id,storefront:'GBR'},{Authorization:'buyer'})).status,400);
});
test('creation kill switch never strands an existing buyer receipt or masks a paid outcome',async()=>{
 const f=fixture(),token=await handoff(f);
 await f.send('/creator-support/web/checkout',{token,amount:500,currency:'USD'});
 f.enabled=false;f.paid=true;
 assert.equal((await f.send('/creator-support/web/checkout',{token,amount:500,currency:'USD'})).status,503);
 for(const [path,body,headers] of [
  ['/creator-support/web/status',{token},{}],
  ['/creator-support/purchases/'+id,null,{Authorization:'buyer'}],
  ['/creator-support/handoffs/'+id+'/status',null,{Authorization:'buyer'}],
 ]) {
  const response=await f.send(path,body,headers);
  assert.equal(response.status,200);
  assert.equal((await response.json()).status,'confirmed');
 }
 assert.equal((await f.send('/creator-support/purchases/'+id,null,{Authorization:'outsider'})).status,404);
 f.revoked=true;
 assert.equal((await f.send('/creator-support/web/status',{token})).status,401);
});
test('eligibility distinguishes disabled/restricted creators from retryable provider failures',async()=>{
 const f=fixture();
 f.providerFailure=true;
 const failed=await f.send('/creator-support/eligibility/creator',null,{Authorization:'buyer'});
 assert.equal(failed.status,503);
 assert.doesNotMatch(await failed.text(),/private provider diagnostic/);
 f.providerFailure=false;f.blocked=true;
 assert.deepEqual(await (await f.send('/creator-support/eligibility/creator',null,{Authorization:'buyer'})).json(),{enabled:false,mode:'test',reason:'creator_unavailable'});
 f.blocked=false;
 assert.equal((await (await f.send('/creator-support/eligibility/creator',null,{Authorization:'buyer'})).json()).enabled,true);
});
