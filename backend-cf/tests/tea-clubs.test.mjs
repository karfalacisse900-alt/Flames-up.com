import test from 'node:test';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import {clubInput,mountTeaClubs} from '../src/tea-clubs.ts';
import {Hono} from 'hono';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
async function fixture(){
 const db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create table app_users(id text primary key,supabase_user_id uuid,metadata jsonb default '{}',full_name text,username text);
 create table app_blocks(blocker_id text,blocked_id text);
 create table app_purchasables(id uuid primary key,post_id uuid,content_type text,private_config jsonb,status text,title text,description text,creator_app_user_id text,creator_id uuid,approval_required boolean);
 create table app_group_chats(id text primary key,metadata jsonb default '{}');
 create table app_group_chat_members(id text primary key,group_id text,user_id text,role text);
 create table app_group_messages(id text primary key,group_id text,sender_id text,body text,media jsonb default '{}',media_url text,media_type text,created_at timestamptz default now());
 insert into app_users(id,full_name,username) values('owner','Owner','owner'),('member','Member','member'),('visitor','Visitor','visitor'),('moderator','Moderator','mod');
 insert into app_purchasables values('${id(1)}','${id(10)}','club','{"group_chat_id":"group"}','active','Club','Description','owner',null,false);
 insert into app_group_chats(id) values('group');
 insert into app_group_chat_members values('a','group','owner','owner'),('b','group','member','member'),('c','group','moderator','admin');
 insert into app_group_messages(id,group_id,sender_id,body) values('legacy','group','member','Old message');
 `);
 await db.exec(readFileSync(new URL('../../supabase/migrations/20261115015247_tea_club_spaces.sql',import.meta.url),'utf8'));
 const call=async(actor,action,data={},club=id(1))=>(await db.query('select captro_tea_club($1,$2,$3,$4) result',[actor,club,action,JSON.stringify(data)])).rows[0].result;
 return {db,call};
}
test('General preserves existing messages; membership, rooms, quotes, pins, links, roles and unread are enforced',async()=>{
 const {db,call}=await fixture();try{
  for(const action of ['overview','messages','members','links','invites'])await assert.rejects(call('visitor',action),/FORBIDDEN/);
  assert.equal((await call('member','messages'))[0].id,'legacy');
  assert.equal((await call('member','overview')).rooms.length,0);
  await assert.rejects(call('member','createRoom',{id:id(2),name:'News',announcements:true}),/FORBIDDEN/);
  await call('owner','createRoom',{id:id(2),name:'News',announcements:true});
  await assert.rejects(call('member','send',{id:id(3),room:id(2),body:'Forged'}),/FORBIDDEN/);
  await call('owner','send',{id:id(3),room:id(2),body:'Announcement',quote:'legacy'});
  assert.equal((await call('member','overview')).rooms[0].unread,true);
  await call('member','read',{room:id(2),message:id(3)});
  assert.equal((await call('member','overview')).rooms[0].unread,false);
  const send={id:id(4),body:'See https://example.com/info',quote:'legacy'};
  await call('member','send',send);await call('member','send',send);
  assert.equal((await call('member','messages')).length,2);
  assert.equal((await call('member','message',{message:id(4)}))[0].quote.id,'legacy');
  await assert.rejects(call('owner','send',send),/CONFLICT/);
  await assert.rejects(call('member','send',{id:id(5),body:'Hi',quote:'foreign'}),/UNAVAILABLE/);
  await assert.rejects(call('member','pin',{message:id(4),version:1}),/FORBIDDEN/);
  await call('owner','pin',{message:id(4),version:1});
  assert.equal((await call('member','overview')).pin.id,id(4));
  await assert.rejects(call('owner','pin',{message:'legacy',version:1}),/CONFLICT/);
  const link={id:id(6),title:'Info',url:'https://example.com/info',message:id(4)};
  await call('member','saveLink',link);await call('member','saveLink',link);
  assert.equal((await call('member','links')).length,1);
  await assert.rejects(call('member','removeLink',{id:id(6),version:1}),/FORBIDDEN/);
  await call('moderator','editLink',{id:id(6),title:'Updated',url:'https://example.com/new',version:1});
  await assert.rejects(call('owner','removeLink',{id:id(6),version:1}),/CONFLICT/);
  await call('owner','removeLink',{id:id(6),version:2});assert.equal((await call('member','links')).length,0);
  await assert.rejects(call('moderator','memberRole',{user:'member',role:'admin'}),/FORBIDDEN/);
  await assert.rejects(call('owner','removeMember',{user:'owner'}),/FORBIDDEN/);
  await call('owner','removeMember',{user:'member'});
  await assert.rejects(call('member','message',{message:'legacy'}),/FORBIDDEN/);
  await db.exec('set role authenticated');
  await assert.rejects(db.query('select * from app_tea_club_links'),/permission denied/);
  await assert.rejects(call('owner','overview'),/permission denied/);
 }finally{await db.close();}
});
test('revocable approval invites never grant chat membership or financial access',async()=>{
 const {db,call}=await fixture();try{
  const invite={id:id(7),hash:'fixture-hash',approval:true,expires:new Date(Date.now()+86400000).toISOString()};
  await call('owner','createInvite',invite);
  const open=async(accept=false)=>(await db.query('select captro_tea_invite($1,$2,$3) r',['visitor','fixture-hash',accept])).rows[0].r;
  assert.equal((await open()).state,'approval_required');assert.equal((await open(true)).state,'pending');
  await assert.rejects(call('visitor','messages'),/FORBIDDEN/);
  await call('owner','decideInvite',{id:id(7),user:'visitor',approve:true});
  assert.equal((await open()).state,'continue_to_join');
  await assert.rejects(call('visitor','messages'),/FORBIDDEN/);
  await call('owner','revokeInvite',{id:id(7)});await assert.rejects(open(),/REVOKED/);
  await db.exec("update app_tea_club_invites set revoked_at=null,expires_at=now()-interval '1 second'");await assert.rejects(open(),/EXPIRED/);
  await assert.rejects(db.query("select captro_tea_invite('visitor','unknown',true)"),/INVALID/);
 }finally{await db.close();}
});
test('HTTP actions reject anonymous actors and unsafe or forged data',async()=>{
 const api=new Hono();let calls=0;
 mountTeaClubs(api,{auth:async(c,next)=>c.req.header('Authorization')?next():c.json({},401),viewer:async()=> 'member',limit:async()=>null,restriction:async()=>null,site:p=>'https://example.com/'+p,rpc:async()=>{calls++;throw Error('TEA_CLUB_FORBIDDEN');}});
 assert.equal((await api.request('/tea/clubs/'+id(1))).status,401);
 for(const body of [{id:id(2),title:'x',url:'javascript:alert(1)'},{id:id(2),title:'x',url:'https://example.com',actor:'owner'}]){
  const r=await api.request('/tea/clubs/'+id(1)+'/saveLink',{method:'POST',headers:{Authorization:'fixture','Content-Type':'application/json'},body:JSON.stringify(body)});assert.equal(r.status,400);
 }
 assert.equal(calls,0);
 assert.throws(()=>clubInput('memberRole',{user:'member',role:'owner'}));
 assert.equal((await api.request('/tea/clubs/'+id(1),{headers:{Authorization:'fixture'}})).status,403);
});

test('real HTTP/database pagination preserves legacy messages, binds cursors, and never exposes invite hashes',async()=>{
 const {db,call}=await fixture();try {
  await db.exec(`insert into app_group_messages(id,group_id,sender_id,body,created_at)
    select 'legacy-message-'||lpad(n::text,3,'0'),'group','member','Message '||n,'2026-11-01'::timestamptz + n*interval '1 second' from generate_series(1,61) n;`);
  const api=new Hono();
  mountTeaClubs(api,{auth:async(c,next)=>c.req.header('Authorization')?next():c.json({},401),viewer:async c=>c.req.header('Authorization'),limit:async()=>null,restriction:async()=>null,site:p=>'https://captro-site.pages.dev/'+p,
   rpc:async(c,name,p)=>name==='captro_tea_club'?call(p.p_actor,p.p_action,p.p_data,p.p_club):(await db.query('select captro_tea_invite($1,$2,$3) r',[p.p_actor,p.p_hash,p.p_accept])).rows[0].r});
  const secret={JWT_SECRET:'isolated-cursor-secret-at-least-32-characters'};
  const req=(path,user='member',data,env=secret)=>api.request(path,{headers:{Authorization:user,'Content-Type':'application/json'},...(data?{method:'POST',body:JSON.stringify(data)}:{})},env);
  const base='/tea/clubs/'+id(1);
  const first=await (await req(base+'/messages')).json();assert.equal(first.items.length,50);assert.ok(first.nextCursor);
  const second=await (await req(base+'/messages?cursor='+first.nextCursor)).json();
  assert.equal(new Set([...first.items,...second.items].map(m=>m.id)).size,62);assert.equal(second.nextCursor,null);
  assert.equal((await req(base+'/messages?cursor='+first.nextCursor,'owner')).status,400);
  assert.equal((await req(base+'/links?cursor='+first.nextCursor)).status,400);
  const invite=await (await req(base+'/createInvite','owner',{id:id(9),approval:true,expires:new Date(Date.now()+86400000).toISOString()})).json();
  assert.ok(invite.url);assert.equal(invite.token_hash,undefined);
  const listing=await (await req(base+'/invites','owner')).json();assert.equal(listing.items[0].url,invite.url);assert.equal(listing.items[0].token_hash,undefined);
  const rotated=await (await req(base+'/invites','owner',undefined,{JWT_SECRET:'a-different-signing-key-for-rotation'})).json();assert.equal(rotated.items[0].url,null);
  const token=invite.url.split('/').at(-1);
  assert.equal((await (await req('/tea/club-invites/'+token,'visitor')).json()).state,'approval_required');
  await db.exec("insert into app_blocks values('visitor','owner')");
  assert.equal((await req('/tea/club-invites/'+token,'visitor')).status,404);
 }finally{await db.close();}
});

test('canonical approval, removed messages, foreign rooms and concurrent writes retain authorization',async()=>{
 const {db,call}=await fixture();try {
  await db.exec(`update app_purchasables set approval_required=true;
    insert into app_group_messages(id,group_id,sender_id,body) values('foreign','other','owner','Private other group');`);
  await assert.rejects(call('member','message',{message:'foreign'}).then(rows=>{if(!rows.length)throw Error('UNAVAILABLE')}),/UNAVAILABLE/);
  await assert.rejects(call('member','send',{id:id(3),body:'Hi',room:id(99)}),/UNAVAILABLE/);
  await assert.rejects(call('member','saveLink',{id:id(4),message:'foreign',title:'Leaked',url:'https://example.com'}),/UNAVAILABLE/);
  await db.exec(`update app_group_messages set media='{"removed_at":"2026-11-01"}' where id='legacy'`);
  assert.equal((await call('member','messages')).length,0);
  await assert.rejects(call('member','send',{id:id(3),body:'Hi',quote:'legacy'}),/UNAVAILABLE/);
  const payload={id:id(7),hash:'fixture',approval:false,expires:new Date(Date.now()+86400000).toISOString()};
  assert.equal((await call('owner','createInvite',payload)).requires_approval,true);
  await assert.rejects(call('owner','createInvite',{...payload,expires:new Date(Date.now()+172800000).toISOString()}),/CONFLICT/);
  await db.query("select captro_tea_invite('visitor','fixture',true)");
  await call('owner','decideInvite',{id:id(7),user:'visitor',approve:true});
  await assert.rejects(call('owner','decideInvite',{id:id(7),user:'visitor',approve:false}),/CONFLICT/);
  const pair=await Promise.allSettled([call('owner','settings',{version:1,rules:'A',links:[]}),call('moderator','settings',{version:1,rules:'B',links:[]})]);
  assert.equal(pair.filter(x=>x.status==='fulfilled').length,1);assert.equal(pair.filter(x=>x.status==='rejected').length,1);
  await db.exec("update app_users set metadata='{\"status\":\"suspended\"}' where id='member'");
  await assert.rejects(call('member','overview'),/FORBIDDEN/);
 }finally{await db.close();}
});
