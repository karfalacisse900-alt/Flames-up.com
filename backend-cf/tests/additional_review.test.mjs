import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {decimalProviderUnits, validateCurrencyAmount, currencyFeeUnits} from '../src/currency.ts';
import {validateCommerceInput} from '../src/commerce.ts';
import {saleAmounts} from '../src/stripe-money.ts';
import {AuthRefreshFailure, upstreamRefreshFailure} from '../src/auth-refresh-errors.ts';
import {stripTypeScriptTypes} from 'node:module';
import {reconcileHostedHold} from '../src/hosted-hold.ts';
import {dashboardResults} from '../src/dashboard-results.ts';

test('USD and JPY use the same integer provider contract across draft, price and checkout', () => {
  for (const [currency, decimal] of [['USD','10.00'],['JPY','1000']]) {
    const amount = decimalProviderUnits(decimal, currency);
    assert.equal(amount, 1000);
    const config = validateCommerceInput({enabled:true, contentType:'event', paymentModel:'paid', commerceClass:'outside_app',
      title:'Fixture', currency, moneyContractVersion:1, prices:[{label:'General',unitAmount:amount}]},
      {postType:'event',title:'Fixture',description:'',visibility:'public'});
    assert.equal(config.prices[0].unit_amount, 1000);
    assert.equal(config.prices[0].currency, currency);
    const fee = currencyFeeUnits({CAPTRO_CURRENCY_FEES:'{"JPY":{"fixed":30,"minimum":0}}'},currency);
    assert.equal(saleAmounts(amount,{basisPoints:500,fixedAmount:fee.fixed,minimumAmount:fee.minimum,buyerPaysPlatformFee:true,creatorPaysPlatformFee:false}).buyerTotal,1080);
  }
});
test('invalid precision, unsafe units, unsupported and provider-special currencies fail closed', () => {
  for (const [amount,currency] of [['10.001','USD'],['1000.1','JPY'],['1e3','JPY'],['-10','USD'],['100','ISK'],['100','UGX'],['100','EUR'],['100','USDmore']]) {
    assert.throws(()=>decimalProviderUnits(amount,currency));
  }
  assert.throws(()=>validateCurrencyAmount('1000','USD'));
  assert.throws(()=>validateCurrencyAmount(1000.1,'JPY'));
  assert.throws(()=>currencyFeeUnits({},'JPY'),/NOT_CONFIGURED/);
  assert.throws(()=>validateCommerceInput({enabled:true,contentType:'event',paymentModel:'paid',commerceClass:'outside_app',
    title:'Old draft',currency:'JPY',prices:[{unitAmount:100000}]}, {postType:'event',title:'Old draft',description:'',visibility:'public'}),/Update Captro/);
});
test('refresh invalidation requires an explicit upstream credential rejection', () => {
  for (const status of [400,403,429,500,502,503]) assert.notEqual(upstreamRefreshFailure(status,'unknown').status,401);
  assert.equal(upstreamRefreshFailure(400,'refresh_token_not_found').status,401);
  assert.equal(upstreamRefreshFailure(400,'refresh_token_already_used').status,401);
  assert.equal(upstreamRefreshFailure(429,'over_request_rate_limit','42').retryAfter,'42');
  assert.equal(upstreamRefreshFailure(429,'over_request_rate_limit','secret\nvalue').retryAfter,'30');
});
test('actual refresh endpoint preserves retryability and rotated tokens across identity-read failure',async()=>{
  const source=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
  const route=stripTypeScriptTypes(source.slice(source.indexOf("api.post('/auth/refresh'"),source.indexOf("api.post('/auth/password/reset/request'")));
  const refresh=stripTypeScriptTypes(source.slice(source.indexOf('async function refreshSupabaseSession('),source.indexOf('function passwordResetRedirectTarget(')));
  let handler; let provider; let profileFailure;
  const dependencies={api:{post:(_path,value)=>{handler=value;}},rejectLargeRequest:()=>null,requireSupabasePrimaryDatabase:()=>null,
    enforceRateLimit:async()=>null,clientIp:()=>'',cleanText:v=>String(v??'').trim(),getSupabaseUrl:()=> 'https://fixture.invalid',
    supabasePublicAuthHeaders:()=>({}),fetch:async()=>{if(provider instanceof Error)throw provider;return provider;},
    issueCaptroTokenForSupabaseAccessToken:async()=>{if(profileFailure)throw profileFailure;return {user:{id:'fixture'}};},
    supabaseAuthSessionResponse:(session,user)=>({...session,user}),getErrorCode:e=>e.message,AuthRefreshFailure,upstreamRefreshFailure};
  new Function(...Object.keys(dependencies),refresh+'\n'+route)(...Object.values(dependencies));
  const context=(partial=true)=>({req:{json:async()=>({refresh_token:'fixture-refresh',supports_partial_refresh:partial})},
    header:()=>{},json:(body,status=200)=>({body,status})});
  for(const status of [429,500,503]) {
    provider=new Response(JSON.stringify({code:'temporary'}),{status});
    assert.equal((await handler(context())).status,status===429?429:503);
  }
  provider=new Error('offline');assert.equal((await handler(context())).status,503);
  provider=new Response('not JSON',{status:200});assert.equal((await handler(context())).status,503);
  provider=new Response(JSON.stringify({code:'refresh_token_not_found'}),{status:400});
  assert.equal((await handler(context())).status,401);
  const rotated=()=>new Response(JSON.stringify({access_token:'fixture-new',refresh_token:'fixture-rotated'}));
  profileFailure=new Error('PROFILE_UPSTREAM_UNAVAILABLE');provider=rotated();
  const result=await handler(context());assert.equal(result.status,200);assert.equal(result.body.user,null);
  assert.equal(result.body.refresh_token,'fixture-rotated');
  provider=rotated();assert.equal((await handler(context(false))).status,503);
  profileFailure=new Error('ACCOUNT_DISABLED');provider=rotated();assert.equal((await handler(context())).status,403);
});
function fixture(session, intent='requires_payment_method') {
  const calls=[];
  const io={readSession:async()=>({...session}),expireSession:async()=>{session.status='expired';calls.push('expire');},
    readIntent:async()=>({status:intent}),cancelIntent:async()=>{intent='canceled';calls.push('cancel');},
    confirm:async()=>{calls.push('confirm');},release:async()=>{calls.push('release');}};
  return {io,calls};
}
test('paid hosted checkout with delayed webhook confirms rather than releasing inventory',async()=>{
  const {io,calls}=fixture({status:'complete',payment_status:'paid',payment_intent:'pi_fixture'},'succeeded');
  assert.equal(await reconcileHostedHold(io),'paid');assert.deepEqual(calls,['confirm']);
});
test('completion wins an expiry race; failed expire is followed by a fresh provider read',async()=>{
  const session={status:'open',payment_status:'unpaid'};const {io,calls}=fixture(session);
  io.expireSession=async()=>{session.status='complete';session.payment_status='paid';throw Error('already completed');};
  assert.equal(await reconcileHostedHold(io),'paid');assert.deepEqual(calls,['confirm']);
});
test('processing or succeeded-but-not-yet-propagated intents retain inventory',async()=>{
  for(const intent of ['processing','succeeded']) {
    const {io,calls}=fixture({status:'complete',payment_status:'unpaid',payment_intent:'pi_fixture'},intent);
    assert.equal(await reconcileHostedHold(io),'pending');assert.deepEqual(calls,[]);
  }
});
test('release requires terminal provider evidence, never a network exception',async()=>{
  const {io,calls}=fixture({status:'open',payment_status:'unpaid',payment_intent:'pi_fixture'});
  assert.equal(await reconcileHostedHold(io),'released');assert.deepEqual(calls,['expire','cancel','release']);
  io.readSession=async()=>{throw Error('offline');};
  await assert.rejects(reconcileHostedHold(io),/offline/);assert.equal(calls.filter(c=>c==='release').length,1);
});
test('failed cancellation and still-open checkout remain held',async()=>{
  const {io,calls}=fixture({status:'open',payment_status:'unpaid'});
  io.expireSession=async()=>{throw Error('timeout');};
  assert.equal(await reconcileHostedHold(io),'pending');assert.deepEqual(calls,[]);
  const other=fixture({status:'expired',payment_status:'unpaid',payment_intent:'pi_fixture'});
  other.io.cancelIntent=async()=>{throw Error('timeout');};
  assert.equal(await reconcileHostedHold(other.io),'pending');assert.deepEqual(other.calls,[]);
});
test('dashboard card failure is explicit and does not hide independent results',async()=>{
  const result=await dashboardResults({count:async()=>3,failed:async()=>{throw Error('sensitive SQL');},empty:async()=>0});
  assert.deepEqual(result.values,{count:3,failed:null,empty:0});
  assert.match(result.errors.failed,/unavailable/);assert.doesNotMatch(JSON.stringify(result),/sensitive SQL/);
  const worker=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
  assert.match(worker,/app_users', \{ 'metadata->>status': postgrestEqFilter\('suspended'\)/);
});
