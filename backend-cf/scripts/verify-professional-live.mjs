import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

// Exercises only newly created private identities. No checkout, publication,
// payout, or real customer operations. Audit evidence is retained; fixtures are
// disabled and their grants removed in finally, including after an assertion.
const ref = process.env.SUPABASE_PROJECT_REF;
assert.equal(ref, 'cclgvxukwccvtgrbcwie');
const service = process.env.SUPABASE_SERVICE_ROLE_KEY, anon = process.env.SUPABASE_ANON_KEY;
assert.ok(service && anon, 'Existing protected Supabase credentials are required');
const db = `https://${ref}.supabase.co`, api = 'https://flames-up-api.karfalacisse900.workers.dev/api';
const trusted = { apikey: service, Authorization: `Bearer ${service}` };
const accounts = [];
let checks = 0;
function check(ok, label) { assert.ok(ok, label); checks++; }
async function request(url, method = 'GET', body, headers = {}, expected) {
  const response = await fetch(url, { method, headers: { 'Content-Type':'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body), redirect:'error', signal:AbortSignal.timeout(30000) });
  // Never emit URLs/IDs, credentials, response bodies or provider exceptions.
  assert.ok(expected ? [].concat(expected).includes(response.status) : response.ok,
    `Release fixture request (${method}) returned HTTP ${response.status}; expected ${expected ?? 'success'}`);
  const text = await response.text(); return text ? JSON.parse(text) : null;
}
async function account() {
  const email = `captro-professional-qa-${randomUUID()}@captro.invalid`, password = randomUUID()+randomUUID();
  const created = await request(db+'/auth/v1/admin/users','POST',
    {email,password,email_confirm:true,app_metadata:{captro_release_fixture:'professional-20261116'}},trusted);
  const entry = {auth:created.id,email}; accounts.push(entry);
  const auth = await request(db+'/auth/v1/token?grant_type=password','POST',{email,password},{apikey:anon});
  entry.headers = {Authorization:`Bearer ${auth.access_token}`};
  entry.id = (await request(api+'/auth/me','GET',undefined,entry.headers)).id;
  check(typeof entry.id === 'string' && /^[\w-]{1,120}$/.test(entry.id), 'Canonical fixture identity');
  await request(api+'/users/me','PUT',{is_private:true,bio:'Private automated release fixture'},entry.headers);
  return entry;
}
try {
  await request(api+'/professional/me','GET',undefined,{},401); checks++;
  const applicant = await account(), reviewer = await account();
  const call = (path,method='GET',body,who=applicant,status) => request(api+path,method,body,who.headers,status);
  const state = () => call('/professional/me');
  const reviewPath = role => `/admin/professional/${applicant.id}/${role}`;
  const data = {displayName:'Private release fixture',category:'musician',description:'Automated acceptance only',links:[],pickup:false,area:'',portfolioPostIds:[]};
  const payload = (version,role='creator') => ({id:randomUUID(),version,message:'Automated release fixture',public:{...data,
    ...(role==='business'?{category:'coffee_bakery',pickup:true,area:'Test area'}:{})}});
  const decide = async (role,action,version) => {
    const body = {id:randomUUID(),version,reason:'Automated private release verification',message:'Fixture review outcome',note:'INTERNAL_RELEASE_NOTE'};
    const result = await call(reviewPath(role)+'/'+action,'POST',body,reviewer);
    check(result.ok === true, `Review ${role}/${action}`); return body;
  };
  let current = await state();
  check(current.applications.length===0 && current.roles.length===0 && current.studio_url===null,'Regular account remains regular');
  await call(reviewPath('creator'),'GET',undefined,reviewer,403); checks++;
  await call('/professional/creator/save','POST',{...payload(0),status:'approved'},applicant,400); checks++;
  await call('/professional/creator/save','POST',payload(0));
  check((await state()).applications[0].status==='draft','Draft persisted');
  const submission = payload(1);
  await call('/professional/creator/submit','POST',submission);
  await call('/professional/creator/submit','POST',submission);
  await call('/professional/business/submit','POST',payload(0,'business'));
  current = await state();
  check(current.roles.length===0 && current.applications.every(x=>x.status==='under_review'),'Submission grants neither role');
  check(current.applications.find(x=>x.role==='creator').version===2,'Duplicate submit is idempotent');
  const other = await call('/professional/me','GET',undefined,reviewer);
  check(other.applications.length===0,'Applications scoped to current account');
  await request(db+'/rest/v1/app_professional_roles?select=role','GET',undefined,{apikey:anon,...reviewer.headers},[401,403]); checks++;
  await request(db+'/rest/v1/app_admin_roles','POST',{user_id:reviewer.id,role:'admin'},trusted);
  await decide('creator','request_changes',2);
  current=await state();
  check(current.applications.find(x=>x.role==='creator').status==='needs_changes','Applicant sees requested changes');
  check(!JSON.stringify(current).includes('INTERNAL_RELEASE_NOTE'),'Internal review notes stay private');
  await call('/professional/creator/submit','POST',payload(3));
  const approval=await decide('creator','approve',4);
  await call(reviewPath('creator')+'/approve','POST',approval,reviewer); checks++;
  current=await state();
  check(current.roles.length===1 && current.roles[0].role==='creator','Creator approval does not grant Business');
  const eligibility=await call(`/creator-support/eligibility/${applicant.id}`,'GET',undefined,reviewer);
  check(eligibility.enabled===false,'Approval alone never enables payment');
  await decide('business','approve',1);
  check((await state()).roles.filter(x=>x.status==='active').length===2,'Independent dual roles');
  await decide('creator','suspend',1);
  current=await state();
  check(current.roles.find(x=>x.role==='business').status==='active' && current.roles.find(x=>x.role==='creator').status==='suspended','Role suspension is isolated');
  await call('/professional/creator/edit_public','POST',payload(2),applicant,403); checks++;
  await decide('creator','restore',2);
  await decide('business','remove',1);
  current=await state();
  check(current.roles.find(x=>x.role==='creator').status==='active' && current.roles.find(x=>x.role==='business').status==='removed','Removal preserves other role');
  await call('/professional/creator/edit_public','POST',payload(1),applicant,409); checks++;
  const detail=await call(reviewPath('creator'),'GET',undefined,reviewer);
  check(detail.history.some(x=>x.action==='approve') && detail.history.some(x=>x.action==='restore'),'Server audit records decisions');
  await call('/professional/studio-handoff','POST',{},applicant,503); checks++;
  await request(db+`/rest/v1/app_admin_roles?user_id=eq.${reviewer.id}`,'DELETE',undefined,trusted);
  await call(reviewPath('creator'),'GET',undefined,reviewer,403); checks++;
  console.log(`PASS: ${checks} live professional identity, application, review, role, payment-gate and revocation checks.`);
} finally {
  let cleanupFailures=0;
  for (const entry of accounts) {
    try {
      const auth=await request(db+`/auth/v1/admin/users/${entry.auth}`,'GET',undefined,trusted);
      assert.equal(auth.email,entry.email);
      assert.match(auth.email,/^captro-professional-qa-[a-f0-9-]+@captro\.invalid$/);
      assert.equal(auth.app_metadata?.captro_release_fixture,'professional-20261116');
      // Revoke even if subsequent cleanup fails. Never touch non-fixture users.
      await request(db+`/auth/v1/admin/users/${entry.auth}`,'PUT',{ban_duration:'876000h'},trusted);
      if (entry.id) {
        await request(db+`/rest/v1/app_admin_roles?user_id=eq.${entry.id}`,'DELETE',undefined,trusted);
        await request(db+`/rest/v1/app_professional_roles?user_id=eq.${entry.id}`,'PATCH',{status:'removed',status_message:'Automated fixture closed'},trusted);
        await request(db+`/rest/v1/app_professional_applications?user_id=eq.${entry.id}`,'PATCH',{status:'declined',reviewer_message:'Automated fixture closed'},trusted);
        const [row]=await request(db+`/rest/v1/app_users?id=eq.${entry.id}&select=metadata`,'GET',undefined,trusted);
        await request(db+`/rest/v1/app_users?id=eq.${entry.id}`,'PATCH',{metadata:{...row.metadata,status:'banned',session_revoked_at:new Date().toISOString(),captro_release_fixture:'professional-20261116'}},trusted);
        await request(api+'/professional/me','GET',undefined,entry.headers,[401,403]);
      }
    } catch { cleanupFailures++; }
  }
  assert.equal(cleanupFailures,0,'Fixture cleanup incomplete; operator follow-up required');
  console.log('PASS: fixture access revoked, grants removed, review queue closed; immutable synthetic audit retained.');
}
