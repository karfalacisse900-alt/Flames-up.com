import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';

const source=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
const ast=ts.createSourceFile('index.ts',source,ts.ScriptTarget.Latest,true);
const purchaseId='11111111-1111-4111-8111-111111111111';
function routeHandler(path){
 for(const n of ast.statements){
  if(!ts.isExpressionStatement(n)||!ts.isCallExpression(n.expression))continue;
  const call=n.expression;
  if(call.expression.getText(ast)==='api.post'&&call.arguments[0]?.text===path)return call.arguments.at(-1).getText(ast);
 }
 throw new Error('Missing '+path);
}
function makeRoute(options={}){
 const calls={permission:null,queries:[],rpc:[],audit:[],release:0};
 const code=ts.transpileModule('const handler='+routeHandler('/admin/commerce/purchases/:purchaseId/release')+';handler',
  {compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const handler=vm.runInNewContext(code,{
  Date,Math,URL,Response,console:{warn(){},error(){}},
  requireAdminRole:async(_c,permission)=>{calls.permission=permission;if(options.denied)throw Error('FORBIDDEN');return {userId:'admin-owner',role:'owner'};},
  requireAdminWriteRateLimit:async()=>null,
  cleanText:value=>String(value??'').trim(),
  isUuidText:value=>typeof value==='string'&&/^[0-9a-f-]{36}$/i.test(value)?value:null,
  postgrestEqFilter:value=>'eq.'+value,
  supabaseAdminSelectRows:async(_c,table,filters,fields,limit)=>{calls.queries.push({table,filters,fields,limit});return options.purchase===null?[]:[options.purchase||{id:purchaseId,content_type:'creator_support',stripe_mode:'test',status:'confirmed'}];},
  supportModeEnabled:env=>env.CAPTRO_CREATOR_SUPPORT===env.STRIPE_MODE&&((env.STRIPE_MODE==='test'&&env.ENVIRONMENT!=='production')||(env.STRIPE_MODE==='live'&&env.ENVIRONMENT==='production')),
  configuredStripeMode:c=>c.env.STRIPE_MODE,
  supabaseAdminRpc:async(_c,name,args)=>{calls.rpc.push({name,args});},
  writeAdminAuditLog:async(_c,_admin,entry)=>calls.audit.push(entry),
  releaseDeferredEarning:async()=>{calls.release++;return {status:'transferred',transferId:'tr_test_support'};},
  commerceErrorCode:error=>String(error?.message||error),
  getErrorCode:error=>String(error?.message||error),
 });
 const responseCapture={body:null,status:200};
 const c={env:options.env||{CAPTRO_CREATOR_SUPPORT:'test',STRIPE_MODE:'test',ENVIRONMENT:'test'},
  req:{param:()=>purchaseId,json:async()=>({releaseAfter:new Date(Date.now()-60000).toISOString(),note:'Reviewed confirmed Support charge and account.'})},
  json:(body,status=200)=>{responseCapture.body=body;responseCapture.status=status;return responseCapture;}};
 return {handler,c,calls,responseCapture};
}
test('Admin Support release authorizes finance role, records audit, and invokes existing Stripe transfer flow once',async()=>{
 const f=makeRoute();await f.handler(f.c);
 assert.equal(f.calls.permission,'payments:release');
 assert.equal(f.calls.queries.length,1);
 assert.deepEqual(f.calls.rpc.map(x=>x.name),['captro_review_earning_release']);
 assert.equal(f.calls.audit[0].actionType,'earning_release_reviewed');
 assert.equal(f.calls.audit[0].targetId,purchaseId);
 assert.equal(f.calls.release,1);
 assert.deepEqual(f.responseCapture.body,{status:'transferred',transferId:'tr_test_support'});
});
test('confirmed Support can be reviewed after the new-checkout switch is turned off',async()=>{
 const f=makeRoute({env:{STRIPE_MODE:'live',ENVIRONMENT:'production'},purchase:{id:purchaseId,content_type:'creator_support',stripe_mode:'live',status:'confirmed'}});
 await f.handler(f.c);
 assert.equal(f.responseCapture.status,200);
 assert.equal(f.calls.rpc.length,1);assert.equal(f.calls.audit.length,1);assert.equal(f.calls.release,1);
 assert.deepEqual(f.responseCapture.body,{status:'transferred',transferId:'tr_test_support'});
});
test('unconfirmed support payment cannot be approved for release',async()=>{
 const f=makeRoute({purchase:{id:purchaseId,content_type:'creator_support',stripe_mode:'test',status:'payment_pending'}});await f.handler(f.c);
 assert.equal(f.responseCapture.status,409);assert.equal(f.responseCapture.body.code,'CAPTRO_RELEASE_NOT_ELIGIBLE');
 assert.equal(f.calls.rpc.length,0);assert.equal(f.calls.release,0);
});
test('read-only or revoked administrator cannot inspect or release through this route',async()=>{
 const f=makeRoute({denied:true});await f.handler(f.c);
 assert.equal(f.calls.permission,'payments:release');
 assert.equal(f.calls.queries.length,0);assert.equal(f.calls.rpc.length,0);assert.equal(f.calls.release,0);
 assert.equal(f.responseCapture.status,403);
});

test('Admin Creator Support category reads individual orders so each transfer is reviewable',async()=>{
 const n=ast.statements.find(n=>ts.isExpressionStatement(n)&&ts.isCallExpression(n.expression)&&
  n.expression.expression.getText(ast)==='api.get'&&n.expression.arguments[0]?.text==='/admin/finance/records');
 assert.ok(n,'active finance records route exists');
 const code=ts.transpileModule('const handler='+n.expression.arguments.at(-1).getText(ast)+';handler',
  {compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const calls={permission:null,table:null,options:null};
 const handler=vm.runInNewContext(code,{
  requireAdminRole:async(_c,p)=>{calls.permission=p;return {userId:'admin-owner'};},
  supportModeEnabled:()=>false,
  cleanText:value=>String(value??'').trim(),isUuidText:value=>typeof value==='string'&&/^[0-9a-f-]{36}$/i.test(value)?value:null,
  configuredStripeMode:()=> 'test',postgrestEqFilter:value=>'eq.'+value,postgrestInFilter:value=>'in.('+value.join(',')+')',
  supabaseAdminQueryRows:async(_c,table,options)=>{calls.table=table;calls.options=options;return [{order_id:purchaseId,category:'creator_support',seller_id:'creator-a',currency:'USD'}];},
  getErrorCode:()=>'',
 });
 const queries={category:'creator_support',currency:'USD',offset:'0'};let response;
 const c={req:{query:name=>queries[name]},header(){},json(body,status=200){response={body,status};return response;}};
 await handler(c);
 assert.equal(calls.permission,'payments:read');assert.equal(calls.table,'app_finance_order_totals');
 assert.equal(calls.options.filters.category,'eq.creator_support');assert.equal(calls.options.filters.currency,'eq.USD');
 assert.equal(calls.options.filters.stripe_mode,'eq.test');assert.equal(response.body.items[0].order_id,purchaseId);
});


const supportCreatorAppId='11111111-1111-4111-8111-111111111111';
const supportCreatorAuthId='22222222-2222-4222-8222-222222222222';
const supportReviewedAt='2026-10-26T12:00:00.000Z';
function enrollmentHandler(method){
 const path='/admin/creator-support/enrollments/:creatorId';
 const n=ast.statements.find(n=>ts.isExpressionStatement(n)&&ts.isCallExpression(n.expression)&&
  n.expression.expression.getText(ast)===method&&n.expression.arguments[0]?.text===path);
 assert.ok(n,'creator support enrollment route exists');
 return ts.transpileModule('const handler='+n.expression.arguments.at(-1).getText(ast)+';handler',
  {compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
}
function makeEnrollmentRoute(method,options={}){
 const calls={permission:null,queries:[],rpc:[],readiness:[],audit:[],restriction:0};
 const handler=vm.runInNewContext(enrollmentHandler(method),{
  Date,Math,Number,String,Array,URL,Response,console:{warn(){},error(){}},
  requireAdminRole:async(_c,permission)=>{calls.permission=permission;if(options.denied)throw Error('FORBIDDEN');return {userId:'owner-user-id',role:'owner'};},
  requireStripeDatabaseMode:async()=>{},
  isUuidText:value=>typeof value==='string'&&/^[0-9a-f-]{36}$/i.test(value)?value:null,
  supabaseUserByAnyId:async(_c,id)=>id===supportCreatorAppId?{id:supportCreatorAppId,supabase_user_id:supportCreatorAuthId,username:'creator',metadata:{status:'active'}}:null,
  supabaseUserStatus:user=>user?.metadata?.status||'active',configuredStripeMode:()=>options.mode||'test',supportModeEnabled:()=>false,
  postgrestEqFilter:value=>'eq.'+value,cleanText:value=>String(value??'').trim(),
  supabaseAdminSelectRows:async(_c,table,filters,fields,limit)=>{calls.queries.push({table,filters,fields,limit});return options.enrollment===null?[]:[options.enrollment||{creator_id:supportCreatorAuthId,enabled_for_test:false,enabled_for_live:false,reviewed_by:null,reviewed_at:supportReviewedAt}];},
  userHasActiveRestriction:async()=>{calls.restriction++;return Boolean(options.restricted);},
  loadCreatorSupportReadiness:async(_c,id,enrolled,ignoreRollout=false)=>{calls.readiness.push({id,enrolled,ignoreRollout});return options.readiness||{status:'ready',mode:options.mode||'test',providerVerified:true,retryable:false,blockers:[]};},
  supabaseAdminRpc:async(_c,name,args)=>{calls.rpc.push({name,args});if(options.rpcError)throw Error(options.rpcError);return {creator_id:supportCreatorAuthId,enabled_for_test:args.p_enabled,enabled_for_live:false,reviewed_by:'owner-user-id',reviewed_at:'2026-10-26T12:05:00.000Z'};},
  writeAdminAuditLog:async(_c,_admin,entry)=>calls.audit.push(entry),getErrorCode:error=>String(error?.message||error),
 });
 const responseCapture={body:null,status:200,headers:{}};
 const body=options.body||{enabled:true,expectedReviewedAt:supportReviewedAt,reason:'Verified eligible payout account.'};
 const c={env:{STRIPE_MODE:options.mode||'test',ENVIRONMENT:'test'},req:{param:()=>supportCreatorAppId,json:async()=>body,header:()=> 'support-request-id'},
  get:key=>key==='requestId'?'support-request-id':undefined,header:(key,value)=>{responseCapture.headers[key]=value;},
  json:(body,status=200)=>{responseCapture.body=body;responseCapture.status=status;return responseCapture;}};
 return {handler,c,calls,responseCapture};
}
test('owner can pre-approve a payout-ready creator while global checkout rollout remains off',async()=>{
 const f=makeEnrollmentRoute('api.post');await f.handler(f.c);
 assert.equal(f.calls.permission,'payments:support:manage');
 assert.equal(f.calls.queries[0].filters.creator_id,'eq.'+supportCreatorAuthId,'approval resolves canonical auth identity');
 assert.equal(f.calls.readiness[0].ignoreRollout,true,'checks Stripe prerequisites independently of rollout');
 assert.equal(f.calls.restriction,1);assert.equal(f.calls.rpc.length,1);
 assert.equal(f.calls.rpc[0].name,'captro_admin_set_creator_support_enrollment');
 assert.equal(f.calls.rpc[0].args.p_creator_id,supportCreatorAuthId);assert.equal(f.calls.rpc[0].args.p_enabled,true);
 assert.equal(f.calls.rpc[0].args.p_mode,'test');assert.equal(f.calls.rpc[0].args.p_expected_reviewed_at,supportReviewedAt);
 assert.equal(f.responseCapture.status,200);assert.equal(f.responseCapture.body.enabled,true);
 assert.equal(f.calls.audit.length,0,'successful decision is audited atomically by SQL RPC');
});
test('server-reported payout blockers prevent creator approval',async()=>{
 const f=makeEnrollmentRoute('api.post',{readiness:{status:'blocked',mode:'test',providerVerified:true,retryable:false,blockers:[{code:'transfers_inactive'}]}});
 await f.handler(f.c);assert.equal(f.responseCapture.status,409);assert.equal(f.responseCapture.body.readiness.status,'blocked');assert.equal(f.calls.rpc.length,0);
});
test('active commerce restriction prevents approval and does not mutate enrollment',async()=>{
 const f=makeEnrollmentRoute('api.post',{restricted:true});await f.handler(f.c);
 assert.equal(f.responseCapture.status,409);assert.equal(f.calls.rpc.length,0);
});
test('read-only or revoked administrator cannot inspect creator enrollment',async()=>{
 const f=makeEnrollmentRoute('api.get',{denied:true});await f.handler(f.c);
 assert.equal(f.calls.permission,'payments:support:manage');assert.equal(f.responseCapture.status,403);
 assert.equal(f.calls.queries.length,0);assert.equal(f.calls.readiness.length,0);
});
test('invalid review reason is rejected before enrollment mutation',async()=>{
 const f=makeEnrollmentRoute('api.post',{body:{enabled:true,expectedReviewedAt:supportReviewedAt,reason:'ok'}});await f.handler(f.c);
 assert.equal(f.responseCapture.status,400);assert.equal(f.calls.rpc.length,0);
});
test('stale concurrent approval is reported without optimistic success and is audited',async()=>{
 const f=makeEnrollmentRoute('api.post',{rpcError:'CAPTRO_SUPPORT_ENROLLMENT_STALE'});await f.handler(f.c);
 assert.equal(f.responseCapture.status,409);assert.equal(f.responseCapture.body.code,'CAPTRO_SUPPORT_ENROLLMENT_STALE');
 assert.equal(f.responseCapture.body.enabled,undefined);assert.equal(f.calls.audit.length,1);
 assert.equal(f.calls.audit[0].actionType,'creator_support_enrollment_failed');
});
test('pausing a creator remains available when global checkout rollout is off',async()=>{
 const f=makeEnrollmentRoute('api.post',{enrollment:{creator_id:supportCreatorAuthId,enabled_for_test:true,enabled_for_live:false,reviewed_at:supportReviewedAt},
  body:{enabled:false,expectedReviewedAt:supportReviewedAt,reason:'Pause until readiness is reviewed.'}});
 await f.handler(f.c);assert.equal(f.responseCapture.status,200);assert.equal(f.calls.rpc[0].args.p_enabled,false);
 assert.equal(f.calls.readiness.length,1,'response reports server rollout status after pause');
});
