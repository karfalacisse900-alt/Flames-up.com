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
