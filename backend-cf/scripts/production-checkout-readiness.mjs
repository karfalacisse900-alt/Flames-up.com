// Authenticated production READ checks: no PaymentIntent, order, transfer or charge.
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
const base='https://'+process.env.SUPABASE_PROJECT_REF+'.supabase.co';
const api='https://flames-up-api.karfalacisse900.workers.dev/api';
const service={apikey:process.env.SUPABASE_SERVICE_ROLE_KEY,Authorization:'Bearer '+process.env.SUPABASE_SERVICE_ROLE_KEY,'Content-Type':'application/json'};
const publicHeaders={apikey:process.env.SUPABASE_ANON_KEY,'Content-Type':'application/json'};
async function request(url,headers,method='GET',body){
 const start=performance.now(),requestId=randomUUID();
 const response=await fetch(url,{method,headers:{...headers,'X-Request-ID':requestId},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(30000)});
 const data=await response.json().catch(()=>null);
 if(url.includes('/commerce/posts/'))console.log(JSON.stringify({event:'ordinary_buyer_access_read',status:response.status,requestId:response.headers.get('x-request-id')||requestId,milliseconds:Math.round(performance.now()-start),code:data?.code,availability:data?.commerce?.status}));
 if(!response.ok)throw Error(method+' '+new URL(url).pathname+': HTTP '+response.status+'; '+String(data?.code||'request_failed').replace(/[^A-Z0-9_]/gi,'').slice(0,80));
 return data;
}
let id,session,appUserId;
try{
 const credentials={email:'captro-readiness-'+randomUUID()+'@captro.invalid',password:randomBytes(32).toString('hex')};
 const created=await request(base+'/auth/v1/admin/users',service,'POST',{...credentials,email_confirm:true});
 id=created.id;assert.match(id,/^[0-9a-f-]{36}$/);
 // Use Captro's actual iOS login path, including its account-identity associations.
 session=await request(api+'/auth/login',{'Content-Type':'application/json'},'POST',credentials);
 appUserId=session.user?.id;
 assert.ok(appUserId,'Captro login must return the ordinary app identity');
 const auth={Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'};
 await request(api+'/auth/me',auth);
 const config=await request(api+'/stripe/config',auth);
 assert.equal(config.publishable_key,process.env.STRIPE_PUBLISHABLE_KEY);
 assert.ok(config.publishable_key.startsWith('pk_live_'));
 const capabilities=await request(api+'/commerce/stripe-capabilities',auth);
 assert.equal(capabilities.liveMode,true);assert.equal(capabilities.apiReachable,true);assert.equal(capabilities.webhookConfigured,true);
 const candidates=await request(base+'/rest/v1/app_purchasables?status=eq.active&payment_model=eq.paid&commerce_class=eq.outside_app&select=post_id&limit=10',service);
 let checked=0;
 for(const item of candidates){
   const result=await request(api+'/commerce/posts/'+item.post_id,auth);
   assert.ok(result.commerce?.id);assert.ok(Array.isArray(result.commerce.prices));checked++;
 }
 assert.ok(checked>0,'No eligible access record available for read check');
 console.log(JSON.stringify({event:'production_checkout_readiness',api,mode:'live',matchingPublishableKey:true,workerStripeSecretAccepted:true,webhookConfigured:true,accessRecordsRead:checked,paymentsCreated:0,chargesMade:0}));
}finally{
 if(session)await request(base+'/auth/v1/logout?scope=global',{...publicHeaders,Authorization:'Bearer '+session.access_token},'POST');
 if(id && /^[0-9a-f-]{36}$/.test(id)){
   if(appUserId)await request(base+'/rest/v1/app_account_identities?user_id=eq.'+encodeURIComponent(appUserId),service,'DELETE');
   await request(base+'/rest/v1/app_users?supabase_user_id=eq.'+id,service,'DELETE');
   await request(base+'/auth/v1/admin/users/'+id,service,'DELETE');
   console.log('Removed only disposable readiness account; no customer records modified.');
 }
}
