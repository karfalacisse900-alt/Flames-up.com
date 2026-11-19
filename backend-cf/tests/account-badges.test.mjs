import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {Hono} from 'hono';
import {badgeInput,mountAccountBadges} from '../src/account-badges.ts';
import {teaAuthorPhotos} from '../src/tea-authors.ts';
const form={display_name:'Test photographer',reason:'Original work and public portfolio.',links:['https://example.com/work'],version:0};
test('verification inputs reject protected fields and unsafe destinations',()=>{
  assert.equal(badgeInput('submit',{...form,id:randomUUID()}).displayName,form.display_name);
  for(const patch of [{is_verified:true},{user_id:'other'},{status:'approved'},{links:['javascript:alert(1)']},{links:['https://localhost/x']},{version:-1},{reason:'no'}])
    assert.throws(()=>badgeInput('submit',{...form,id:randomUUID(),...patch}));
});
test('private application lifecycle, separate authority, audit, idempotency and revocation',async t=>{
  const db=new PGlite();t.after(()=>db.close());
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
    create table app_users(id text primary key,supabase_user_id uuid,metadata jsonb default '{}',is_verified boolean default false);
    create table app_admin_roles(user_id text,role text);
    insert into app_users(id) values('owner'),('applicant'),('other');insert into app_admin_roles values('owner','owner');
    grant select,update on app_users to service_role;grant select on app_admin_roles to service_role;`);
  await db.exec(readFileSync(new URL('../../supabase/migrations/20261119023323_account_badge_verification.sql',import.meta.url),'utf8'));
  const call=async(actor,target,action,data,id=randomUUID())=>(await db.query('select captro_badge_mutate($1,$2,$3,$4,$5) r',[actor,target,action,id,JSON.stringify(data)])).rows[0].r;
  const input=badgeInput('submit',{...form,id:randomUUID()});const {id,...data}=input;
  await db.exec('set role service_role');
  assert.equal((await call('applicant','applicant','submit',data,id)).ok,true);
  await call('applicant','applicant','submit',data,id);
  assert.equal((await db.query('select count(*)::int n from app_badge_audit')).rows[0].n,1);
  assert.equal((await db.query("select is_verified from app_users where id='applicant'")).rows[0].is_verified,false);
  await assert.rejects(call('applicant','other','submit',data),/FORBIDDEN/);
  await assert.rejects(call('applicant','applicant','approve',{version:1,message:'Approved',note:''}),/FORBIDDEN/);
  await assert.rejects(call('other','applicant','approve',{version:1,message:'Approved',note:''}),/FORBIDDEN/);
  await call('owner','applicant','request_changes',{version:1,message:'Add a work sample',note:'Internal only'});
  await assert.rejects(call('owner','applicant','approve',{version:1,message:'Approved'}),/CONFLICT/);
  await call('applicant','applicant','submit',{...data,version:2});
  const decision=randomUUID(),approval={version:3,message:'Application approved',note:'Reviewed public portfolio'};
  await call('owner','applicant','approve',approval,decision);await call('owner','applicant','approve',approval,decision);
  assert.equal((await db.query("select is_verified from app_users where id='applicant'")).rows[0].is_verified,true);
  await assert.rejects(call('owner','applicant','decline',approval,decision),/CONFLICT/);
  await call('owner','applicant','revoke',{version:4,message:'Identity needs another review',note:''});
  assert.equal((await db.query("select is_verified from app_users where id='applicant'")).rows[0].is_verified,false);
  await db.exec('reset role');await db.exec("update app_users set metadata='{"+'"status":"banned"'+"}' where id='applicant'");
  await assert.rejects(call('applicant','applicant','submit',{...data,version:5}),/FORBIDDEN/);
  await db.exec('set role authenticated');
  await assert.rejects(db.query('select * from app_badge_applications'),/permission denied/);
  await assert.rejects(db.query('select * from app_badge_audit'),/permission denied/);
  await assert.rejects(call('owner','applicant','approve',approval),/permission denied/);
});
test('API scopes applications to actor and denies private review endpoints',async()=>{
  const app=new Hono();let admin=false,calls=[];
  mountAccountBadges(app,{auth:async(c,n)=>n(),actor:()=> 'self',admin:async()=>{if(!admin)throw Error('FORBIDDEN');},limit:async()=>null,eq:v=>'eq.'+v,
    query:async(c,table,options)=>{calls.push([table,options]);return table==='app_users'?[{is_verified:false}]:[{user_id:'self',status:'under_review',decided_by:'private-admin'}];},
    rpc:async(c,name,data)=>{calls.push(data);return {ok:true};}});
  const res=await app.request('/verification/me');assert.equal(res.status,200);assert.doesNotMatch(await res.text(),/private-admin|decided_by/);
  assert.ok(calls.every(x=>Object.values(x[1].filters).includes('eq.self')));
  for(const path of ['/admin/verification','/admin/verification/other'])assert.equal((await app.request(path)).status,403);
  assert.equal((await app.request('/verification/apply',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...form,id:randomUUID()})})).status,200);
  assert.equal(calls.at(-1).p_target,'self');assert.equal(calls.at(-1).p_actor,'self');
  assert.equal((await app.request('/verification/apply',{method:'POST',body:'bad-json'})).status,400);
  admin=true;assert.equal((await app.request('/admin/verification')).status,200);
});
test('public badges are server-authoritative, including missing and revoked identities',async()=>{
  const rows=[{author:{id:'approved',isVerified:false}},{author:{id:'unapproved',isVerified:true}}];
  const out=await teaAuthorPhotos(rows,async()=>new Map([['approved',{photoURL:'https://example.com/a.jpg',isVerified:true}]]));
  assert.equal(out[0].author.isVerified,true);assert.equal(out[1].author.isVerified,false);
});
