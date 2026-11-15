import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {Hono} from 'hono';
import {professionalPublicData,professionalOperation,studioPathAllowed,mountProfessionalAccounts} from '../src/professional-accounts.ts';

const creator={displayName:'Sample artist',category:'musician',description:'Independent musician',links:[],pickup:false,area:'',portfolioPostIds:[]};
const business={...creator,displayName:'Sample café',category:'coffee_bakery',pickup:true,area:'Brooklyn'};
test('professional form validates optional sites, roles and protected fields',()=>{
 assert.deepEqual(professionalPublicData('creator',creator,true),creator);
 assert.equal(professionalPublicData('business',business,true).pickup,true);
 for(const patch of [{status:'approved'},{category:'admin'},{pickup:true},{links:['http://unsafe.test']},{links:['https://a.test','https://b.test','https://c.test','https://d.test']}])assert.throws(()=>professionalPublicData('creator',{...creator,...patch},true));
 assert.throws(()=>professionalOperation('creator','approve',{id:randomUUID(),version:1,reason:'',message:'',note:''}));
 assert.throws(()=>professionalPublicData('business',{...business,area:''},true));
 for(const path of ['/api/admin/professional','/api/businesses/x/checkout','/api/creator-support/handoffs','/api/users/me/password','/api/posts'])assert.equal(studioPathAllowed('POST',path),false);
 assert.equal(studioPathAllowed('GET','/api/business-owner/abc/orders'),true);
 assert.equal(studioPathAllowed('POST','/api/professional/creator/edit_public'),true);
});

test('isolated Postgres applications, decisions, independent roles, revocation and immutable history',async t=>{
 const db=new PGlite();t.after(()=>db.close());
 await db.exec(`create role anon; create role authenticated; create role service_role;
 create table app_users(id text primary key,supabase_user_id uuid,metadata jsonb default '{}');
 create table app_admin_roles(user_id text,role text);
 create table app_purchases(id uuid default gen_random_uuid(),creator_id uuid,content_type text);
 create table app_businesses(id uuid primary key,owner_id uuid,name text,category text,published boolean,paused boolean,latitude float8,longitude float8,tax_bps integer);
 create table app_business_products(id uuid primary key,business_id uuid);
 create table app_business_orders(id uuid primary key,business_id uuid,lines jsonb);
 insert into app_users values('owner','10000000-0000-4000-8000-000000000001','{}'),('applicant','10000000-0000-4000-8000-000000000002','{}'),('stranger','10000000-0000-4000-8000-000000000003','{}');
 insert into app_admin_roles values('owner','owner');`);
 await db.exec(readFileSync(new URL('../../supabase/migrations/20261115224938_professional_accounts_studio.sql',import.meta.url),'utf8'));
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const mutate=async(actor,role,action,data,id=randomUUID(),target='applicant')=>(await q('select captro_professional_mutate($1,$2,$3,$4,$5,$6) v',[actor,target,role,action,JSON.stringify(data),id]))[0].v;
 const active=async role=>(await q('select captro_professional_active($1,$2) v',['applicant',role]))[0].v;
 const decision=(version)=>({version,reason:'Reviewed sample application',message:'Public review response',note:'Private reviewer note'});
 assert.deepEqual(await mutate('stranger','creator','submit',{version:0,public:creator,message:''}),{error:'PROFESSIONAL_FORBIDDEN'});
 assert.deepEqual(await mutate('applicant','creator','submit',{version:0,public:creator,message:'Reviewer-only context'}),{ok:true});
 assert.equal(await active('creator'),false);
 assert.deepEqual(await mutate('applicant','creator','approve',decision(1)),{error:'PROFESSIONAL_FORBIDDEN'});
 await mutate('owner','creator','request_changes',decision(1));
 await mutate('applicant','creator','submit',{version:2,public:creator,message:'Updated'});
 const id=randomUUID();assert.deepEqual(await mutate('owner','creator','approve',decision(3),id),{ok:true});
 assert.deepEqual(await mutate('owner','creator','approve',decision(3),id),{ok:true},'lost response replay returns the original outcome');
 assert.equal(await active('creator'),true);assert.equal(await active('business'),false);
 assert.equal((await q('select count(*) n from app_professional_roles'))[0].n,1);
 assert.deepEqual(await mutate('owner','creator','suspend',decision(1),id),{error:'PROFESSIONAL_CONFLICT'});
 await mutate('applicant','business','submit',{version:0,public:business,message:''});
 await mutate('owner','business','decline',decision(1));
 assert.equal(await active('business'),false);
 await mutate('applicant','business','submit',{version:2,public:business,message:'New information'});
 await mutate('owner','business','approve',decision(3));
 assert.equal(await active('business'),true);
 await q("insert into app_purchases(creator_id,content_type) values('10000000-0000-4000-8000-000000000002','creator_support')");
 await mutate('owner','creator','suspend',decision(1));
 assert.equal(await active('creator'),false);assert.equal(await active('business'),true);
 await assert.rejects(q("insert into app_purchases(creator_id,content_type) values('10000000-0000-4000-8000-000000000002','creator_support')"),/PROFESSIONAL_REQUIRED/);
 await mutate('owner','creator','restore',decision(2));assert.equal(await active('creator'),true);
 await mutate('owner','business','remove',decision(1));assert.equal(await active('business'),false);assert.equal(await active('creator'),true);
 assert.equal((await q('select count(*) n from app_purchases'))[0].n,1,'existing financial history survives suspension');
 await assert.rejects(q("insert into app_businesses(id,owner_id) values(gen_random_uuid(),'10000000-0000-4000-8000-000000000002')"),/PROFESSIONAL_FORBIDDEN/);
 const session=async(action,hash,user=null,sessionHash=null)=>(await q('select captro_studio_session($1,$2,$3,$4) v',[action,hash,user,sessionHash]))[0].v;
 await session('issue','a'.repeat(64),'applicant');await session('exchange','a'.repeat(64),null,'b'.repeat(64));
 assert.equal((await session('resolve','b'.repeat(64))).user_id,'applicant');
 await assert.rejects(session('exchange','a'.repeat(64),null,'c'.repeat(64)),/SESSION_INVALID/);
 await q("update app_users set metadata='{\"status\":\"banned\"}' where id='applicant'");
 assert.equal(await active('creator'),false);await assert.rejects(session('resolve','b'.repeat(64)),/SESSION_INVALID/);
 assert.deepEqual(await mutate('applicant','creator','edit_public',{version:3,public:creator,message:''}),{error:'PROFESSIONAL_FORBIDDEN'});
 await q("update app_users set metadata='{}' where id='applicant'");
 await session('revoke','b'.repeat(64));await assert.rejects(session('resolve','b'.repeat(64)),/SESSION_INVALID/);
 const privileges=await q("select has_table_privilege('authenticated','app_professional_roles','UPDATE') role,has_table_privilege('authenticated','app_professional_audit','SELECT') audit,has_table_privilege('service_role','app_professional_audit','DELETE') erase");
 assert.deepEqual(privileges[0],{role:false,audit:false,erase:false});
 assert.ok((await q("select * from app_professional_audit where internal_note='Private reviewer note'")).length>0);
 assert.equal((await q("select count(*) n from app_professional_audit where id=$1",[id]))[0].n,1);
});

test('actual HTTP routes deny forged owner/admin operations and keep reviewer notes private',async()=>{
 const app=new Hono();let rpcCalls=0;
 mountProfessionalAccounts(app,{auth:async(c,next)=>{if(!c.req.header('fixture-user'))return c.json({},401);await next();},actor:c=>c.req.header('fixture-user'),
 admin:async c=>{if(c.req.header('fixture-user')!=='admin')throw new Error('PROFESSIONAL_FORBIDDEN');},limit:async()=>null,eq:v=>'eq.'+v,portfolio:async()=>{},
 rpc:async()=>{rpcCalls++;return {ok:true};},query:async(c,table,opts)=>{
 assert.equal(opts.filters.user_id,'eq.alice');return table==='app_professional_applications'?[{user_id:'alice',role:'creator',status:'under_review',decided_by:'private-admin'}]:[];}});
 const send=(path,user,body)=>app.request(path,{method:body?'POST':'GET',headers:{...(user?{'fixture-user':user}:{}),'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})},{});
 assert.equal((await send('/professional/me')).status,401);
 const mine=await(await send('/professional/me','alice')).json();assert.equal(mine.applications[0].decided_by,undefined);
 assert.equal((await send('/admin/professional','alice')).status,403);
 assert.equal((await send('/professional/creator/approve','alice',{})).status,400);
 assert.equal((await send('/professional/creator/submit','alice',{id:randomUUID(),version:0,public:{...creator,user_id:'victim'}})).status,400);
 assert.equal(rpcCalls,0);
});
