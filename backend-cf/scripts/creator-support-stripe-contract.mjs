// Real Stripe sandbox API + disposable PostgreSQL contract test, not a completed
// hosted-browser payment. No charge/refund/transfer or Connect account mutation.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID, randomBytes} from 'node:crypto';
import {supportCheckoutParameters} from '../src/creator-support.ts';
import {findSupportSandboxRecipient} from './support-sandbox-recipient.mjs';

assert.equal(process.env.GITHUB_ACTIONS,'true');assert.equal(process.env.STRIPE_MODE,'test');
const key=process.env.STRIPE_SECRET_KEY;
assert.match(key??'',/^(sk|rk)_test_/);
const local=JSON.parse(await readFile(join(process.env.RUNNER_TEMP,'supabase-status.json'),'utf8'));
assert.ok(['localhost','127.0.0.1'].includes(new URL(local.API_URL).hostname));
const dbHeaders={apikey:local.SERVICE_ROLE_KEY,Authorization:'Bearer '+local.SERVICE_ROLE_KEY,'Content-Type':'application/json',Prefer:'return=representation'};
async function request(url,init={}) {
  const r=await fetch(url,{...init,redirect:'error',signal:AbortSignal.timeout(30000)});
  const b=await r.json();
  if(!r.ok)throw Error('Contract request failed HTTP '+r.status+' '+String(b.code||b.error?.code||'unknown').replace(/[^A-Z0-9_-]/gi,''));
  return b;
}
const db=(path,body,method='POST')=>request(local.API_URL+'/rest/v1/'+path,{method,headers:dbHeaders,...(body===undefined?{}:{body:JSON.stringify(body)})});
const first=value=>Array.isArray(value)?value[0]:value;
const rpc=async(name,args)=>first(await db('rpc/'+name,args));
async function stripe(path,body,requestID) {
  return request('https://api.stripe.com/v1'+path,{method:body?'POST':'GET',headers:{Authorization:'Bearer '+key,
    ...(body?{'Content-Type':'application/x-www-form-urlencoded'}:{}),...(requestID?{'Idempotency-Key':requestID}:{})},
    ...(body?{body:new URLSearchParams(Object.entries(body).map(([k,v])=>[k,String(v)]))}:{})});
}
let session;
try {
  const platform=await stripe('/account');assert.equal(platform.id,process.env.STRIPE_EXPECTED_ACCOUNT_ID);
  // Reuse an existing test account only; never create or update a recipient.
  const {recipient,counts}=await findSupportSandboxRecipient(stripe,(path,version)=>request('https://api.stripe.com'+path,{
    headers:{Authorization:'Bearer '+key,'Stripe-Version':version},
  }));
  console.log(JSON.stringify({test:'support_sandbox_recipient_readiness',counts,accountMutation:false}));
  assert.ok(recipient,'No existing ready sandbox recipient; manual sandbox onboarding is required');
  const createUser=()=>request(local.API_URL+'/auth/v1/admin/users',{method:'POST',headers:dbHeaders,
    body:JSON.stringify({email:'support-contract-'+randomUUID()+'@example.com',password:randomBytes(32).toString('hex'),email_confirm:true})});
  const [seller,buyer]=await Promise.all([createUser(),createUser()]);
  const account=first(await db('app_connected_accounts',{user_id:seller.id,app_user_id:'contract-seller',provider_account_id:recipient.id,
    stripe_mode:'test',status:'ready',details_submitted:true,transfers_enabled:true,payouts_enabled:true,payout_schedule:'manual'}));
  await db('app_creator_support_enrollments',{creator_id:seller.id,enabled_for_test:true,reviewed_by:'isolated-contract-fixture'});
  const hash=randomBytes(32).toString('hex');
  const handoffArgs={p_buyer_id:buyer.id,p_buyer_app_user_id:'contract-buyer',p_creator_id:seller.id,p_creator_app_user_id:'contract-seller',p_request_key:randomUUID(),p_token_hash:hash};
  const h=await rpc('captro_issue_support_handoff',handoffArgs);
  assert.equal((await rpc('captro_issue_support_handoff',handoffArgs)).id,h.id);
  const begin={p_token_hash:hash,p_amount:500,p_connected_account_id:account.id};
  const p=await rpc('captro_begin_creator_support',begin);
  assert.equal((await rpc('captro_begin_creator_support',begin)).id,p.id);
  const params=supportCheckoutParameters(p);
  const idempotency='captro-support-contract-'+process.env.GITHUB_RUN_ID+'-'+p.id;
  session=await stripe('/checkout/sessions',params,idempotency);
  assert.equal((await stripe('/checkout/sessions',params,idempotency)).id,session.id);
  assert.equal(session.livemode,false);assert.equal(session.amount_total,500);assert.equal(session.currency,'usd');
  assert.equal(session.payment_status,'unpaid');assert.equal(new URL(session.url).hostname,'checkout.stripe.com');
  assert.equal(session.total_details.amount_tax,0);assert.equal(params.application_fee_amount,undefined);
  await db('app_purchases?id=eq.'+p.id,{provider_checkout_id:session.id},'PATCH');
  assert.equal((await db('app_entitlements?purchase_id=eq.'+p.id,undefined,'GET')).length,0);
  assert.equal((await db('app_creator_earnings?purchase_id=eq.'+p.id,undefined,'GET')).length,0);
  const expired=await stripe('/checkout/sessions/'+session.id+'/expire',{});
  assert.equal(expired.status,'expired');assert.equal(expired.payment_status,'unpaid');
  await rpc('captro_cancel_purchase_hold',{p_purchase_id:p.id,p_checkout_id:session.id});
  assert.equal((await db('app_creator_earnings?purchase_id=eq.'+p.id,undefined,'GET')).length,0);
  session=null;
  console.log(JSON.stringify({test:'support_real_sandbox_contract',postgresMigration:true,checkoutCreated:true,duplicateCheckoutPrevented:true,
    canonicalExpiry:true,amount:500,currency:'USD',platformFee:0,verifiedUnpaidCancellation:true,noEntitlement:true,
    connectAccountCreated:false,chargeCreated:false,refund:false,transfer:false,hostedPaymentCompleted:false,
    remaining:'Manual hosted Checkout completion, signed success webhooks, actual paid processing fees and installed-app return remain acceptance gates.'}));
} finally {
  if(session?.status==='open')await stripe('/checkout/sessions/'+session.id+'/expire',{}).catch(()=>undefined);
}
