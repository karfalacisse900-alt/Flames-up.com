import test from 'node:test';
import assert from 'node:assert/strict';
import { recoveryContext, passwordProblem } from '../../captro-site/auth/reset-password/reset.mjs';
import { recoveryHandler } from '../../captro-site/functions/auth/reset-password/api/[action].js';
import { repairPlan, configureRecovery, target } from './recovery-config.mjs';
const origin = 'https://captro-site.pages.dev';
const request = (body, headers = {}, method = 'POST') => new Request(origin+'/auth/reset-password/api/confirm', {method, headers:{Origin:origin,'Content-Type':'application/json',...headers}, ...(method==='POST'?{body:JSON.stringify(body)}:{})});
const input = { access_token:'synthetic-token',password:'A synthetic passphrase 123!' };
test('only recovery fragments enable the form; provider errors never become HTML',()=>{
  assert.equal(recoveryContext('#type=recovery&access_token=fixture').token,'fixture');
  for(const hash of ['', '#type=signup&access_token=fixture','#error=denied&access_token=fixture','#type=recovery']) assert.equal(recoveryContext(hash).token,'');
  assert.ok(passwordProblem('short','short'));
  assert.ok(passwordProblem(input.password,'different'));
  assert.equal(passwordProblem(input.password,input.password),'');
});
test('bridge rejects foreign origins, non-JSON, unknown actions and forged fields without upstream work',async()=>{
  let calls=0;const fetcher=async()=>{calls++;throw Error('not expected');};
  for(const [req,action,status] of [
    [request(input,{Origin:'https://attacker.invalid'}),'confirm',403],
    [request(input,{'Content-Type':'text/plain'}),'confirm',415],
    [request(input),'admin',404],
    [request({}, {},'GET'),'confirm',405],
    [request({...input,role:'owner'}),'confirm',400],
    [request({email:'a@example.com',redirect_to:'https://attacker.invalid'}),'request',400],
    [request({...input,password:'tiny'}),'confirm',400],
  ]) assert.equal((await recoveryHandler(req,action,fetcher)).status,status);
  assert.equal(calls,0);
});
test('request pins correct redirect and confirm never exposes returned sessions',async()=>{
  let payload;
  const result=await recoveryHandler(request({email:'fixture@example.com'}),'request',async(url,options)=>{
    assert.equal(url,'https://api.flames-up.com/api/auth/password/reset/request');
    assert.equal(options.redirect,'manual');payload=JSON.parse(options.body);
    return Response.json({sent:true});
  });
  assert.equal(result.status,200);assert.equal(payload.redirect_to,target);
  const confirmed=await recoveryHandler(request(input),'confirm',async()=>Response.json({access_token:'must-not-escape',refresh_token:'must-not-escape',user:{email:'private'}}));
  assert.deepEqual(await confirmed.json(),{ok:true,code:'OK'});
  assert.equal(confirmed.headers.get('Cache-Control'),'no-store');
});
test('expired/restricted/rate-limited/transient/malformed responses remain failures',async()=>{
  for(const status of [400,401,403,429,500,503]){
    const response=await recoveryHandler(request(input),'confirm',async()=>Response.json({private:'not exposed'},{status}));
    assert.equal(response.status,status<500?status:502);
    assert.equal((await response.json()).ok,false);
  }
  for(const fetcher of [async()=>new Response('<html>'),async()=>Response.json({}),async()=>{throw Error('secret failure');}])
    assert.equal((await recoveryHandler(request(input),'confirm',fetcher)).status,502);
});
test('body ceiling applies even without Content-Length',async()=>{
  assert.equal((await recoveryHandler(request({access_token:'x'.repeat(14000),password:input.password}),'confirm',async()=>{throw Error('must not call');})).status,413);
});
test('redirect repair preserves unrelated allowlist and correct templates',()=>{
  const before={uri_allow_list:'captro://auth/reset-password,https://example.test/callback',mailer_templates_recovery_content:'<a href="{{ .ConfirmationURL }}">Reset</a>',site_url:'https://captro.app'};
  const after=repairPlan(before);
  assert.equal(after.uri_allow_list,before.uri_allow_list+','+target);
  assert.equal(after.mailer_templates_recovery_content,before.mailer_templates_recovery_content);
  assert.equal(after.site_url,undefined);
  assert.equal(repairPlan(after).uri_allow_list,after.uri_allow_list);
  assert.match(repairPlan({...before,mailer_templates_recovery_content:'{{ .SiteURL }}/reset'}).mailer_templates_recovery_content,/ConfirmationURL/);
});
test('configuration inspection is read-only; apply patches only two recovery fields and verifies',async()=>{
  let config={uri_allow_list:'captro://auth/reset-password',mailer_templates_recovery_content:'{{ .SiteURL }}/reset',site_url:'https://captro.app',unrelated:'preserve'};
  let patches=0,backup;
  const fetcher=async(url,opts)=>{
    if(String(url).includes('/verify?')) return new Response(null,{status:302,headers:{location:config.uri_allow_list.includes(target)?target+'#error=access_denied':'https://captro.app/#error=denied'}});
    if(opts.method==='PATCH'){patches++;const body=JSON.parse(opts.body);assert.deepEqual(Object.keys(body).sort(),['mailer_templates_recovery_content','uri_allow_list']);config={...config,...body};}
    return Response.json(config);
  };
  const opts={token:'synthetic',project:'cclgvxukwccvtgrbcwie',fetcher,saveBackup:async value=>{backup=value;}};
  assert.equal((await configureRecovery(opts)).redirectProbeMatches,false);assert.equal(patches,0);
  assert.equal((await configureRecovery({...opts,apply:true})).redirectProbeMatches,true);assert.equal(patches,1);
  assert.equal(config.unrelated,'preserve');assert.equal(config.site_url,'https://captro.app');
  assert.deepEqual(Object.keys(backup).sort(),['mailer_templates_recovery_content','uri_allow_list']);
  await configureRecovery({...opts,apply:true});assert.equal(patches,1);
});
