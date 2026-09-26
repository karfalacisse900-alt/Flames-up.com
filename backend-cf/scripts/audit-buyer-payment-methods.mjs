// Read-only audit: no card details, charges, or consent mutations.
import assert from 'node:assert/strict';
assert.equal(process.env.GITHUB_ACTIONS, 'true');
const key = process.env.STRIPE_SECRET_KEY;
assert.match(key || '', /^(sk|rk)_live_/);
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const db = await fetch('https://'+process.env.SUPABASE_PROJECT_REF+'.supabase.co/rest/v1/app_stripe_customers?stripe_mode=eq.live&select=provider_customer_id&limit=100', {headers:{apikey:service,Authorization:'Bearer '+service}});
assert.ok(db.ok, 'Customer association audit failed');
async function read(path) {
 const response = await fetch('https://api.stripe.com/v1'+path, {headers:{Authorization:'Bearer '+key}});
 const data = await response.json();
 if (!response.ok) {
  console.log(JSON.stringify({event:'buyer_audit_error',status:response.status,code:data.error?.code,type:data.error?.type,requestId:response.headers.get('request-id')}));
  return null;
 }
 return data;
}
for (const mapping of await db.json()) {
 const id=mapping.provider_customer_id; assert.match(id,/^cus_[A-Za-z0-9]+$/);
 const customer=await read('/customers/'+id);
 console.log(JSON.stringify({event:'buyer_customer_audit',customerId:id,exists:!!customer&&!customer.deleted,live:customer?.livemode}));
 if(!customer||customer.deleted)continue;
 // Short-lived session probe only: does not attach, confirm, charge, or change consent.
 const probe=await fetch('https://api.stripe.com/v1/customer_sessions',{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({customer:id,'components[customer_sheet][enabled]':'true','components[customer_sheet][features][payment_method_remove]':'enabled','components[mobile_payment_element][enabled]':'true','components[mobile_payment_element][features][payment_method_save]':'enabled','components[mobile_payment_element][features][payment_method_redisplay]':'enabled','components[mobile_payment_element][features][payment_method_remove]':'enabled'})});
 const probeData=await probe.json();
 console.log(JSON.stringify({event:'buyer_session_probe',customerId:id,status:probe.status,code:probeData.error?.code,param:probeData.error?.param,requestId:probe.headers.get('request-id'),componentEnabled:probeData.components?.mobile_payment_element?.enabled,features:probeData.components?.mobile_payment_element?.features}));
 let cursor='';
 do {
  const page=await read('/payment_methods?customer='+id+'&type=card&limit=100'+(cursor?'&starting_after='+cursor:''));
  if(!page)break;
  for(const method of page.data)console.log(JSON.stringify({event:'buyer_method_audit',customerId:method.customer,paymentMethodId:method.id,type:method.type,allowRedisplay:method.allow_redisplay}));
  cursor=page.has_more?page.data.at(-1).id:'';
 }while(cursor);
}
const recent=await read('/payment_intents?limit=50');
for(const pi of recent?.data||[]) {
 if(pi.metadata?.source!=='captro_commerce')continue;
 console.log(JSON.stringify({event:'buyer_intent_audit',paymentIntentId:pi.id,created:pi.created,customerId:pi.customer,paymentMethodId:pi.payment_method,status:pi.status,amount:pi.amount,live:pi.livemode,errorType:pi.last_payment_error?.type,errorCode:pi.last_payment_error?.code,declineCode:pi.last_payment_error?.decline_code,errorPaymentMethodId:pi.last_payment_error?.payment_method?.id}));
}
const end=Date.now();
const logs=await fetch('https://api.cloudflare.com/client/v4/accounts/'+process.env.CLOUDFLARE_ACCOUNT_ID+'/workers/observability/telemetry/query',{method:'POST',headers:{Authorization:'Bearer '+process.env.CLOUDFLARE_API_TOKEN,'Content-Type':'application/json'},body:JSON.stringify({queryId:'captro-buyer-failure-audit',timeframe:{from:end-86400000,to:end},view:'events',dry:true,limit:100,parameters:{needle:{value:'commerce_purchase_begin_failed',isRegex:false,matchCase:false}}})});
const logData=await logs.json();
console.log(JSON.stringify({event:'checkout_log_query',status:logs.status,success:logData.success,errorCodes:logData.errors?.map(x=>x.code),resultKeys:Object.keys(logData.result||{})}));
// Print only existing structured checkout diagnostics, never arbitrary log bodies.
function inspect(value){
 if(!value)return;
 if(typeof value==='string'&&value.startsWith('{')){try{inspect(JSON.parse(value))}catch{}return;}
 if(typeof value!=='object')return;
 if(value.event==='commerce_purchase_begin_failed'){
  const safe={event:value.event,stage:value.stage,code:value.code,endpoint:value.endpoint};
  console.log(JSON.stringify(safe));return;
 }
 for(const item of Object.values(value))inspect(item);
}
inspect(logData.result);
