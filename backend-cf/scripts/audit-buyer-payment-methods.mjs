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
