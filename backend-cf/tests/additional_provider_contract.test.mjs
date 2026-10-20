import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {createHmac} from 'node:crypto';
import {cents} from '../src/stripe-money.ts';
import {supportCheckoutParameters,SupportError} from '../src/creator-support.ts';
const source=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
function actual(name,next,deps) {
  const code=stripTypeScriptTypes(source.slice(source.indexOf(`async function ${name}(`),source.indexOf(next)));
  return new Function(...Object.keys(deps),`${code}\nreturn ${name};`)(...Object.values(deps));
}
const purchase=(currency='USD')=>({id:'10000000-0000-4000-8000-000000000001',status:'payment_pending',payment_interface:'native',
  stripe_mode:'test',settlement_model:'deferred',currency,total_amount:1080,unit_amount:1000,quantity:1,
  item_amount:1000,service_fee_amount:80,tax_amount:0,price_id:'price-fixture',purchasable_id:'item-fixture',
  buyer_id:'buyer-fixture',hold_expires_at:'2035-01-01T12:35:00Z'});
const base={cents,cleanText:value=>String(value??''),postgrestEqFilter:x=>x,now:()=>new Date().toISOString(),
  requireRetainedPlatform:async()=>{},paymentTrace:()=>{},commerceErrorCode:e=>e.message,
  getStripeConfig:()=>({configured:true,webhookConfigured:true,mode:'test',liveMode:false,publishableKey:'pk_test_fixture'}),
  buyerStripeCustomerForUser:async()=>({provider_customer_id:null}),supabaseAdminPatchRows:async()=>{},
  marketplaceTransferGroup:id=>'fixture-'+id,stripeProviderError:()=>Error('provider rejected')};

test('actual Support checkout bypasses marketplace pricing and retries the same provider operation',async()=>{
  const row={...purchase(),content_type:'creator_support',payment_interface:'checkout',service_fee_amount:0,
    platform_fee_amount:0,total_amount:500,item_amount:500,unit_amount:500,creator_id:'creator',stripe_destination_account_id:'acct_trusted'};
  const calls=[];let fail=true;
  const deps={...base,supportCheckoutParameters,SupportError,requireStripeDatabaseMode:async()=>{},
    supabaseAdminRpc:async()=>{},supabaseAdminSelectRows:async()=>{throw Error('Must not create a synthetic purchasable');},
    stripeApiRequest:async(_c,path,params,key)=>{
      calls.push({path,params,key}); if(fail)throw Error('response lost');
      return {ok:true,data:{id:'cs_support',url:'https://checkout.stripe.com/c/pay/cs_support',livemode:false,mode:'payment',currency:'usd',amount_total:500,
        metadata:{source:'captro_commerce',captro_purchase_id:row.id}}};
    }};
  const create=actual('createCommerceCheckoutSession','function sanitizeCommerceSelection(',deps);
  await assert.rejects(create({env:{}},row),/response lost/);fail=false;await create({env:{}},row);
  assert.equal(calls.length,2);assert.deepEqual(calls[0],calls[1]);
  assert.equal(calls[0].params['line_items[0][price_data][unit_amount]'],500);
  assert.ok(!Object.keys(calls[0].params).some(key=>key.includes('application_fee')||key.includes('line_items[1]')));
});

test('existing webhook verifier checks actual raw bytes, timestamp, signature and secret for support events',async()=>{
  const code=stripTypeScriptTypes(source.slice(source.indexOf('async function hmacSha256Hex('),source.indexOf('function commerceErrorCode(')));
  const verify=new Function(`${code}\nreturn verifyStripeWebhookSignature;`)();
  const secret='whsec_isolated_fixture',timestamp=Math.floor(Date.now()/1000);
  const raw=JSON.stringify({id:'evt_support',type:'checkout.session.completed',livemode:false});
  const header=time=>`t=${time},v1=${createHmac('sha256',secret).update(`${time}.${raw}`).digest('hex')}`;
  assert.equal(await verify(raw,header(timestamp),secret),true);
  assert.equal(await verify(raw+' ',header(timestamp),secret),false);
  assert.equal(await verify(raw,header(timestamp-301),secret),false);
  assert.equal(await verify(raw,header(timestamp),'whsec_wrong_fixture'),false);
  assert.equal(await verify(raw,`t=${timestamp},v1=forged`,secret),false);
});
test('actual native PaymentIntent requests preserve USD and JPY integer totals',async()=>{
  for(const currency of ['USD','JPY']) {
    const row=purchase(currency),calls=[];
    const deps={...base,supabaseAdminRpc:async(_c,name)=>calls.push(name),
      stripeApiRequest:async(_c,path,params,key)=>{
        calls.push(path);assert.equal(params.amount,1080);assert.equal(params.currency,currency.toLowerCase());
        assert.equal(key,'payment:'+row.id);
        return {ok:true,data:{id:'pi_fixture',amount:params.amount,currency:params.currency,livemode:false,
          transfer_group:params.transfer_group,metadata:{captro_purchase_id:row.id},client_secret:'fixture-only'}};
      }};
    const create=actual('createCommercePaymentIntent','async function completeCommercePurchaseFromIntent(',deps);
    await create({env:{}},row);
    assert.deepEqual(calls,['captro_validate_checkout','/payment_intents']);
  }
});
test('actual hosted checkout shares the database hold deadline and validates before provider creation',async()=>{
  const row=purchase('JPY');row.payment_interface='checkout';const calls=[];
  const deps={...base,supabaseAdminRpc:async()=>calls.push('validate'),
    supabaseAdminSelectRows:async(_c,table)=>table==='app_purchasables'?[{id:'item-fixture'}]:[{id:'price-fixture',unit_amount:1000,currency:'JPY'}],
    isUuidText:x=>x,publicId:x=>x,allowedStripeReturnUrl:(_c,_url,path)=>'https://example.invalid'+path,
    ensureStripeProductAndPrice:async(_c,_item,price)=>{assert.equal(price.unit_amount,1000);assert.equal(price.currency,'JPY');return 'price_fixture';},
    stripeApiRequest:async(_c,path,params)=>{
      calls.push(path);assert.equal(params.expires_at,Date.parse(row.hold_expires_at)/1000);
      assert.equal(params['line_items[1][price_data][unit_amount]'],80);
      assert.equal(params['line_items[1][price_data][currency]'],'jpy');
      return {ok:true,data:{id:'cs_fixture',url:'https://example.invalid/checkout'}};
    }};
  const create=actual('createCommerceCheckoutSession','function sanitizeCommerceSelection(',deps);
  await create({env:{}},row);
  assert.deepEqual(calls,['validate','/checkout/sessions']);
  deps.supabaseAdminRpc=async()=>{throw Error('CAPTRO_EVENT_ENDED');};
  await assert.rejects(actual('createCommerceCheckoutSession','function sanitizeCommerceSelection(',deps)({env:{}},row),/EVENT_ENDED/);
  assert.equal(calls.filter(x=>x==='/checkout/sessions').length,1);
});
test('refund integer amount is forwarded without currency rescaling (provider flag compatibility NOT asserted)',async()=>{
  for(const currency of ['USD','JPY']) {
    const row={...purchase(currency),provider_payment_id:'pi_fixture'},calls=[];
    const deps={...base,isUuidText:x=>x,supabaseAdminQueryRows:async()=>[],supabaseAdminSelectRows:async()=>[row],
      recordCommerceRefund:async()=>{},stripeApiRequest:async(_c,path,params)=>{
        calls.push(path);assert.equal(params.amount,1000);return {ok:true,data:{id:'re_fixture'}};
      }};
    await actual('refundMarketplacePurchase','function commerceRefundError(',deps)({},row,{amount:1000});
    assert.deepEqual(calls,['/refunds']);
  }
});
