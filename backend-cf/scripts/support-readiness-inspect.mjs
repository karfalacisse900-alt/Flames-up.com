// GET-only sandbox diagnostics. No checkout, account mutation or money movement.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {STRIPE_ACCOUNTS_V2_VERSION,stripeV2RecipientTransferStatus} from '../src/stripe-connect-v2.ts';
import {eligibleDebitCard} from '../src/stripe-money.ts';
assert.equal(process.env.GITHUB_ACTIONS,'true');
assert.equal(process.env.STRIPE_MODE,'test');
const key=process.env.STRIPE_SECRET_KEY;
assert.match(key??'',/^(sk|rk)_test_/);
async function read(path,version) {
  const response=await fetch('https://api.stripe.com'+path,{method:'GET',redirect:'error',signal:AbortSignal.timeout(20000),
    headers:{Authorization:'Bearer '+key,...(version?{'Stripe-Version':version}:{})}});
  if(!response.ok)throw Error('Read-only Stripe diagnostic HTTP '+response.status);
  return response.json();
}
const platform=await read('/v1/account');
assert.equal(platform.id,process.env.STRIPE_EXPECTED_ACCOUNT_ID);
console.log(JSON.stringify({check:'platform_identity',mode:'test',expectedAccountMatched:true,
  supportModelApproval:'not established by an account API read',liveAccountsInspected:false}));
let cursor,examined=0,complete=false;
const seen=new Set();
for(let page=0;page<5;page++) {
  const list=await read('/v1/accounts?limit=100'+(cursor?'&starting_after='+encodeURIComponent(cursor):''));
  assert.ok(Array.isArray(list.data));
  for(const a of list.data) {
    assert.match(a.id,/^acct_[A-Za-z0-9]+$/);assert.ok(!seen.has(a.id));seen.add(a.id);examined++;
    let recipientStatus='unverified',providerError=null;
    try {
      const v2=await read('/v2/core/accounts/'+a.id+'?include[0]=configuration.recipient',STRIPE_ACCOUNTS_V2_VERSION);
      assert.equal(v2.id,a.id);assert.equal(v2.livemode,false);
      recipientStatus=stripeV2RecipientTransferStatus(v2)||'not_requested';
    } catch(error) { providerError=String(error.message).startsWith('Read-only Stripe')?error.message:'Recipient identity/mode unverified'; }
    const fields=Array.isArray(a.requirements?.currently_due)?a.requirements.currently_due.map(f=>
      String(f).replace(/person_[A-Za-z0-9]+/g,'person').replace(/[^a-zA-Z0-9_.\[\]-]/g,'').slice(0,120)):null;
    console.log(JSON.stringify({check:'creator_requirements',accountFingerprint:createHash('sha256').update(a.id).digest('hex').slice(0,12),mode:'test',
      stripe:{detailsSubmitted:a.details_submitted===true,payoutsEnabled:a.payouts_enabled===true,recipientTransferStatus:recipientStatus,
        currentlyDue:fields,disabledReason:a.requirements?.disabled_reason||null,providerError},
      captro:{manualScheduleSatisfied:a.settings?.payouts?.schedule?.interval==='manual',
        eligibleDebitCardSatisfied:(a.external_accounts?.data||[]).some(card=>eligibleDebitCard(card,a.default_currency||'usd')),
        enrollment:'not inspected',rollout:'disabled for live'}}));
  }
  if(!list.has_more){complete=true;break;}
  assert.ok(list.data.length);cursor=list.data.at(-1).id;
}
console.log(JSON.stringify({check:'summary',examined,complete,GETOnly:true,accountsCreated:0,charges:0,refunds:0,transfers:0}));
assert.ok(complete,'Bounded diagnostic scan incomplete');
