import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { Hono } from 'hono';
import { discussionLinks, discussionInput, mountTeaConversations } from '../src/tea-conversations.ts';

const id = n => '00000000-0000-4000-8000-' + String(n).padStart(12,'0');
const draft = (extra={}) => ({requestID:id(1),title:'Which intro works?',body:'Tell me what you think.',links:[],...extra});
test('links are bounded HTTPS destinations, preserve queries and reject ambiguous or forged payloads',()=>{
  assert.deepEqual(discussionLinks(['https://youtube.com/watch?v=a&token=private','https://example.com/a']),['https://youtube.com/watch?v=a&token=private','https://example.com/a']);
  assert.deepEqual(discussionLinks(['https://youtube.com/a','https://youtube.com/a']),['https://youtube.com/a']);
  for(const url of ['http://example.com','javascript:alert(1)','https://user:pass@example.com','https://localhost/a','https://127.0.0.1','https://[::1]','https://example.com:8080','https://example.com\n']) assert.throws(()=>discussionLinks([url]));
  assert.throws(()=>discussionLinks(Array(4).fill('https://example.com')));
  for(const patch of [{author_id:'other'},{status:'approved'},{authorUpdate:true},{links:['bad']},{title:''}]) assert.throws(()=>discussionInput('create',draft(patch)));
  assert.throws(()=>discussionInput('edit',{title:'a',body:'b',links:[],version:0}));
});

async function database() {
  const db=new PGlite();
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
    create table app_users(id text primary key,supabase_user_id uuid,full_name text,username text,is_private boolean default false,metadata jsonb default '{}');
    create table app_blocks(blocker_id text,blocked_id text);
    create table app_follows(app_follower_id text,app_following_id text,status text);
    insert into app_users(id,supabase_user_id,full_name,username) values('a','${id(100)}','Artist','artist'),('b','${id(101)}','Reader','reader'),('c','${id(102)}','Other','other');
    grant select,update on app_users to service_role; grant select on app_blocks,app_follows to service_role;`);
  await db.exec(readFileSync(new URL('../../supabase/migrations/20261114014202_tea_conversations.sql',import.meta.url),'utf8'));
  const write=async(actor,action,post,data)=>(await db.query('select captro_tea_write($1,$2,$3,$4) value',[actor,action,post,JSON.stringify(data)])).rows[0].value;
  const read=async(actor,kind,post=null,before=null,boundary=null,snapshot=new Date(Date.now()+60000).toISOString())=>(await db.query('select captro_tea_read($1,$2,$3,$4,$5,$6) value',[actor,kind,post,before,boundary,snapshot])).rows[0].value;
  return {db,write,read};
}

test('persisted post/reply/follow lifecycle, ownership, stale edits and duplicate response recovery',async()=>{
  const {db,write,read}=await database(); try {
    const created=await write('a','create',id(1),draft());
    assert.equal(created.isAuthor,true);assert.deepEqual(created.links,[]);
    assert.deepEqual(await write('a','create',id(1),draft()),created);
    await assert.rejects(write('b','create',id(1),draft()),/FORBIDDEN/);
    await assert.rejects(write('b','edit',id(1),draft({version:1,links:['https://example.com']})),/FORBIDDEN/);
    const edited=await write('a','edit',id(1),draft({version:1,links:['https://example.com']}));
    assert.equal(edited.version,2);
    assert.equal((await write('a','edit',id(1),draft({version:1,links:['https://example.com']}))).version,2);
    await assert.rejects(write('a','edit',id(1),draft({version:1,body:'Stale overwrite'})),/CONFLICT/);
    await write('b','follow',id(1),{following:true}); await write('b','follow',id(1),{following:true});
    assert.equal((await read('b','detail',id(1))).following,true);
    assert.equal((await read('c','detail',id(1))).following,false);
    await write('b','follow',id(1),{following:false});assert.equal((await read('b','detail',id(1))).following,false);
    const reply={requestID:id(2),body:'Try the second one.'};
    await write('b','reply',id(1),reply); await write('b','reply',id(1),reply);
    assert.equal((await read('a','replies',id(1))).length,1);
    await assert.rejects(write('c','reply',id(1),reply),/CONFLICT/);
    assert.deepEqual(Object.keys((await read('b','detail',id(1))).author).sort(),['id','name','username']);
    await db.exec('set role authenticated');
    for(const table of ['app_tea_conversations','app_tea_replies','app_tea_follows']) await assert.rejects(db.query('select * from '+table),/permission denied/);
    await assert.rejects(read('a','detail',id(1)),/permission denied/);
    await assert.rejects(write('a','edit',id(1),draft({version:2})),/permission denied/);
  } finally {await db.close();}
});

test('direct detail/replies/follow deny private, blocked, removed and suspended content; page is stable',async()=>{
  const {db,write,read}=await database(); try {
    for(let n=1;n<=23;n++) await write('a','create',id(n),draft());
    const first=await read('','list');assert.equal(first.length,21);
    const last=first[19];const next=await read('','list',null,last.createdAt,last.id);
    assert.equal(new Set([...first.slice(0,20),...next].map(p=>p.id)).size,23);
    await db.exec("update app_users set is_private=true where id='a'");
    assert.equal((await read('','list')).length,0);
    await assert.rejects(read('b','detail',id(1)),/UNAVAILABLE/);
    await db.exec("insert into app_follows values('b','a','active')");
    assert.equal((await read('b','detail',id(1))).id,id(1));
    await db.exec(`insert into app_blocks values('${id(100)}','${id(101)}')`);
    await assert.rejects(read('b','replies',id(1)),/UNAVAILABLE/);
    await assert.rejects(write('b','follow',id(1),{following:true}),/UNAVAILABLE/);
    await db.exec("update app_users set metadata='{\"status\":\"suspended\"}' where id='a'");
    await assert.rejects(write('a','create',id(50),draft()),/FORBIDDEN/);
    assert.equal((await read('a','list')).length,0);
    await db.exec("update app_users set metadata='{}' where id='a'; update app_tea_conversations set status='removed' where id='"+id(1)+"'");
    await assert.rejects(read('a','detail',id(1)),/UNAVAILABLE/);
  } finally {await db.close();}
});

test('real HTTP routes enforce auth, restrictions, canonical actor, HTTPS validation and cursor binding',async()=>{
  const {db,write,read}=await database();try {
    const app=new Hono(); let restricted=false;
    mountTeaConversations(app,{
      auth:async(c,next)=>c.req.header('Authorization')==='Bearer fixture'?next():c.json({detail:'Sign in'},401),
      optionalAuth:async(c,next)=>next(), viewer:async c=>c.req.header('Authorization')?'a':'',
      limit:async()=>null,restriction:async c=>restricted?c.json({detail:'Restricted'},403):null,
      rpc:async(c,name,b)=>name==='captro_tea_write'?write(b.p_actor,b.p_action,b.p_id,b.p_data):read(b.p_viewer,b.p_kind,b.p_id,b.p_before,b.p_boundary,b.p_snapshot??undefined),
    });
    const request=(path,method='GET',body,auth=true)=>app.request('https://fixture.test'+path,{method,headers:{...(auth?{Authorization:'Bearer fixture'}:{}),'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})},{JWT_SECRET:'isolated-fixture-secret-not-production'});
    assert.equal((await request('/tea/conversations','POST',draft(),false)).status,401);
    assert.equal((await request('/tea/conversations','POST',draft({links:['http://example.com']}))).status,400);
    restricted=true;assert.equal((await request('/tea/conversations','POST',draft())).status,403);restricted=false;
    for(let n=1;n<=23;n++) assert.equal((await request('/tea/conversations','POST',draft({requestID:id(n)}))).status,200);
    const page=await (await request('/tea/conversations')).json();assert.equal(page.items.length,20);assert.ok(page.nextCursor);
    assert.equal((await request('/tea/conversations?cursor='+page.nextCursor,'GET',null,false)).status,400);
    assert.equal((await request('/tea/conversations/'+id(1)+'/replies?cursor='+page.nextCursor)).status,400);
    assert.equal((await request('/tea/conversations/'+id(1),'PUT',draft({version:1,author_id:'b'}))).status,400);
    assert.equal((await (await request('/tea/conversations/'+id(1))).json()).author.id,'a');
  } finally {await db.close();}
});
