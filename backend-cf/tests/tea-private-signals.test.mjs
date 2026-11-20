import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {Hono} from 'hono';
import {mountTeaConversations} from '../src/tea-conversations.ts';

const id = n => '00000000-0000-4000-8000-' + String(n).padStart(12,'0');
const migration = name => readFileSync(new URL('../../supabase/migrations/'+name,import.meta.url),'utf8');
async function ageLease(db, actor, seconds) {
  await db.query("update app_tea_read_sessions set started_at=clock_timestamp()-make_interval(secs=>$2) where user_id=$1",[actor,seconds]);
}
async function setup() {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create table app_users(id text primary key,supabase_user_id uuid,full_name text,username text,is_private boolean default false,metadata jsonb default '{}');
    create table app_blocks(blocker_id text,blocked_id text);
    create table app_follows(app_follower_id text,app_following_id text,status text);
    create function captro_professional_active(text,text) returns boolean language sql as 'select false';
    insert into app_users(id,supabase_user_id,full_name,username) values
      ('author','${id(100)}','Author','author'),('reader','${id(101)}','Reader','reader'),('other','${id(102)}','Other','other');
    grant select,update on app_users to service_role; grant select on app_blocks,app_follows to service_role;`);
  for (const file of ['20261114230954_tea_conversations.sql','20261115014511_tea_sentence_replies.sql',
    '20261117143031_tea_note_actions.sql','20261120005350_tea_private_interest_insights.sql','20261120022807_tea_qualified_engagement.sql']) await db.exec(migration(file));
  await db.exec(`insert into app_tea_conversations(id,author_id,title,body) values('${id(1)}','author','Existing Note','A plain caption.'); set role service_role;`);
  const rpc = async(name,body) => {
    assert.match(name,/^captro_tea_[a-z_]+$/);
    const keys = Object.keys(body); assert.ok(keys.every(k=>/^p_[a-z_]+$/.test(k)));
    return (await db.query('select '+name+'('+keys.map((k,i)=>k+'=> $'+(i+1)).join(',')+') r',Object.values(body))).rows[0].r;
  };
  const signal = (actor,action,choice=null,post=id(1)) => rpc('captro_tea_private_signal',{p_actor:actor,p_id:post,p_action:action,p_choice:choice});
  const read = actor => rpc('captro_tea_read',{p_viewer:actor,p_kind:'detail',p_id:id(1)});
  return {db,rpc,signal,read};
}

test('real PostgreSQL: one private selection, absolute retries, undo, no public component counts/follows/ranking changes',async()=>{
  const {db,signal,read}=await setup();try {
    const before=await read('reader'); assert.equal(before.interest,null);
    await signal('reader','interest','interested'); await signal('reader','interest','interested');
    assert.equal((await read('reader')).interest,'interested');
    assert.equal((await read('other')).interest,null);
    assert.equal((await read(null)).interest,null);
    assert.deepEqual(await signal('author','insights'),{uniqueOpens:0,interested:1,replies:0,qualifiedReads:0,activePlus:1,uniqueRepliers:0});
    await signal('reader','interest','pass');
    assert.equal((await read('reader')).interest,'pass');
    assert.equal((await signal('author','insights')).interested,0);
    await signal('reader','interest'); await signal('reader','interest');
    const after=await read('reader'); delete after.engagementUpdatedAt; delete before.engagementUpdatedAt; assert.deepEqual(after,before);
    assert.equal((await db.query('select count(*) n from app_tea_follows')).rows[0].n,0);
    assert.equal((await db.query('select count(*) n from app_tea_interest')).rows[0].n,0);
    for(const key of ['uniqueOpens','interested','insights','passCount']) assert.ok(!(key in before));
  }finally{await db.close();}
});

test('real PostgreSQL: legacy instant opens never qualify; only author may read component totals',async()=>{
  const {db,signal,read}=await setup();try {
    await read('reader'); // Merely rendering a list/detail read cannot count an open.
    assert.equal((await signal('author','insights')).uniqueOpens,0);
    await signal('author','open'); await signal('reader','open'); await signal('reader','open'); await signal('other','open');
    assert.equal((await signal('author','insights')).uniqueOpens,0);
    for(const actor of ['reader','other',null,'forged']) await assert.rejects(signal(actor,'insights'),/FORBIDDEN/);
    await db.exec(`reset role; insert into app_tea_replies(id,conversation_id,author_id,body) values('${id(4)}','${id(1)}','reader','Hello'); set role service_role;`);
    assert.equal((await signal('author','insights')).replies,1);
    await db.exec(`reset role; update app_tea_replies set status='removed'; set role service_role;`);
    assert.equal((await signal('author','insights')).replies,0);
  }finally{await db.close();}
});

test('real PostgreSQL: private/blocked/removed/banned accounts and invalid choices fail closed',async()=>{
  const {db,signal}=await setup();try {
    await assert.rejects(signal('reader','interest','upvote'),/INVALID/);
    await assert.rejects(signal('reader','open',null,id(99)),/UNAVAILABLE/);
    await db.exec(`reset role; update app_users set is_private=true where id='author'; set role service_role;`);
    await assert.rejects(signal('reader','interest','interested'),/UNAVAILABLE/);
    await db.exec(`reset role; insert into app_follows values('reader','author','active'); set role service_role;`);
    await signal('reader','interest','interested');
    await db.exec(`reset role; insert into app_blocks values('author','reader'); set role service_role;`);
    await assert.rejects(signal('reader','open'),/UNAVAILABLE/);
    await db.exec(`reset role; delete from app_blocks; update app_users set metadata='{"status":"banned"}' where id='reader'; set role service_role;`);
    await assert.rejects(signal('reader','interest','pass'),/FORBIDDEN/);
    await db.exec(`reset role; update app_tea_conversations set status='removed'; set role service_role;`);
    await assert.rejects(signal('author','insights'),/UNAVAILABLE/);
  }finally{await db.close();}
});

test('real PostgreSQL: anon/authenticated cannot bypass Worker identity with direct tables or RPC',async()=>{
  const {db,signal}=await setup();try {
    for(const role of ['anon','authenticated']) {
      await db.exec('reset role; set role '+role);
      for(const table of ['app_tea_opens','app_tea_interest','app_tea_qualified_reads','app_tea_read_sessions']) await assert.rejects(db.query('select * from '+table),/permission denied/);
      await assert.rejects(signal('author','insights'),/permission denied/);
      await assert.rejects(signal('reader','interest','interested'),/permission denied/);
    }
  }finally{await db.close();}
});

test('account removal can erase private signals without obstructing existing deletion',async()=>{
  const {db,signal}=await setup();try {
    await signal('reader','interest','interested'); await signal('reader','open');
    await db.exec("reset role; delete from app_users where id='reader'; set role service_role;");
    assert.deepEqual(await signal('author','insights'),{uniqueOpens:0,interested:0,replies:0,qualifiedReads:0,activePlus:0,uniqueRepliers:0});
  }finally{await db.close();}
});

test('HTTP + PostgreSQL: actor spoofing rejected; insights enforced server-side; duplicate requests safe',async()=>{
  const {db,rpc}=await setup();try {
    const app=new Hono();
    const auth=async(c,next)=>{if(!c.req.header('X-Test-Actor'))return c.json({},401);await next();};
    mountTeaConversations(app,{auth,optionalAuth:async(c,next)=>next(),viewer:async c=>c.req.header('X-Test-Actor')??null,
      limit:async()=>null,restriction:async()=>null,rpc:async(c,name,body)=>rpc(name,body)});
    const request=(actor,suffix,method='GET',body)=>app.request('/tea/conversations/'+id(1)+'/'+suffix,
      {method,headers:{...(actor?{'X-Test-Actor':actor}:{}),'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});
    assert.equal((await request(null,'interest','PUT',{interest:'interested'})).status,401);
    assert.equal((await request('reader','interest','PUT',{interest:'interested',actor:'author'})).status,400);
    for(let i=0;i<2;i++) assert.equal((await request('reader','interest','PUT',{interest:'interested'})).status,200);
    assert.equal((await request('reader','insights')).status,403);
    assert.equal((await request('other','insights')).status,403);
    assert.deepEqual(await (await request('author','insights')).json(),{uniqueOpens:0,interested:1,replies:0,qualifiedReads:0,activePlus:1,uniqueRepliers:0});
    await request('reader','open','POST',{}); await request('reader','open','POST',{});
    assert.equal((await (await request('author','insights')).json()).uniqueOpens,0);
    assert.equal((await request('reader','interest','PUT',{interest:null})).status,200);
  }finally{await db.close();}
});

test('qualified reads: four seconds rejected, five accepted once, stale/reset/expired tokens rejected',async()=>{
  const {db,signal,read}=await setup();try {
    const first=await signal('reader','read-start');
    assert.equal(first.qualified,false); assert.equal(first.engagementCount,0);
    await ageLease(db,'reader',4);
    await assert.rejects(signal('reader','read-qualify',first.token),/INVALID/);
    assert.equal((await read('reader')).engagementCount,0);
    // A fresh visible session after backgrounding replaces the old lease.
    const second=await signal('reader','read-start');
    assert.notEqual(second.token,first.token);
    await ageLease(db,'reader',5);
    await assert.rejects(signal('reader','read-qualify',first.token),/INVALID/);
    assert.equal((await signal('reader','read-qualify',second.token)).engagementCount,1);
    assert.equal((await signal('reader','read-qualify',second.token)).engagementCount,1);
    assert.equal((await signal('reader','read-start')).qualified,true);
    assert.equal((await signal('author','insights')).qualifiedReads,1);
    assert.equal((await signal('author','read-start')).engagementCount,1);
    const expired=await signal('other','read-start'); await ageLease(db,'other',121);
    await assert.rejects(signal('other','read-qualify',expired.token),/INVALID/);
    assert.equal((await signal('other','open')).confirmed,true);
    assert.equal((await read(null)).engagementCount,1);
  }finally{await db.close();}
});

test('unique union: feed plus, line replies, overlapping actions, undo, moderation and author exclusion',async()=>{
  const {db,rpc,signal,read}=await setup();try {
    assert.equal((await signal('reader','interest','interested')).engagementCount,1);
    const target={id:'1:0:7',version:1,start:0,end:7,quote:'A plain'};
    const reply=(actor,n,t)=>rpc('captro_tea_write',{p_actor:actor,p_action:'reply',p_id:id(1),p_data:{requestID:id(n),body:'A reply',...(t?{target:t}:{})}});
    await reply('reader',20,target); await reply('reader',20,target); await reply('reader',21);
    assert.equal((await read('other')).engagementCount,1);
    assert.equal((await signal('author','insights')).uniqueRepliers,1);
    assert.equal((await signal('reader','interest','pass')).engagementCount,1);
    await db.exec(`update app_tea_replies set status='removed' where id='${id(20)}'`);
    assert.equal((await read('reader')).engagementCount,1);
    await db.exec(`update app_tea_replies set status='removed' where id='${id(21)}'`);
    assert.equal((await read('reader')).engagementCount,0);
    const lease=await signal('reader','read-start'); await ageLease(db,'reader',5);
    await signal('reader','read-qualify',lease.token);
    await reply('reader',22); await signal('reader','interest','interested');
    const totals=await signal('author','insights');
    assert.equal(totals.qualifiedReads,1); assert.equal(totals.activePlus,1); assert.equal(totals.uniqueRepliers,1);
    assert.equal((await read('reader')).engagementCount,1,'three reasons, one account');
    await signal('reader','interest'); await db.exec('update app_tea_replies set status=\'removed\'');
    assert.equal((await read('reader')).engagementCount,1,'qualified read survives undo/deletion');
    await signal('author','interest','interested'); await reply('author',23); await signal('author','open');
    assert.equal((await read('author')).engagementCount,1,'all author activity excluded');
    await signal('other','interest','interested');
    assert.equal((await read('other')).engagementCount,2);
    await signal('other','interest','pass');
    assert.equal((await read('other')).engagementCount,1);
    const page=await rpc('captro_tea_read',{p_viewer:'reader',p_kind:'list'});
    assert.equal(page[0].engagementCount,1,'same count batched in feed');
    for(const key of ['qualifiedReads','activePlus','uniqueRepliers','pass','passCount','userIds']) assert.ok(!(key in page[0]));
  }finally{await db.close();}
});

test('read endpoints: canonical actor, server timer, visibility rechecked at qualification, acknowledged reply count',async()=>{
  const {db,rpc}=await setup();try {
    const app=new Hono(); const auth=async(c,next)=>{if(!c.req.header('X-Test-Actor'))return c.json({},401);await next();};
    mountTeaConversations(app,{auth,optionalAuth:async(c,next)=>next(),viewer:async c=>c.req.header('X-Test-Actor')??null,
      limit:async()=>null,restriction:async()=>null,rpc:async(c,name,body)=>rpc(name,body)});
    const req=(actor,action,body={})=>app.request('/tea/conversations/'+id(1)+'/'+action,{method:'POST',headers:{'Content-Type':'application/json',...(actor?{'X-Test-Actor':actor}:{})},body:JSON.stringify(body)});
    assert.equal((await req(null,'read-start')).status,401);
    assert.equal((await req('reader','read-start',{actor:'author'})).status,400);
    assert.equal((await req('reader','read-qualify',{token:id(30),seconds:5})).status,400);
    const lease=await (await req('reader','read-start')).json();
    assert.equal((await req('reader','read-qualify',{token:lease.token})).status,400);
    await ageLease(db,'reader',5);
    await db.exec("reset role; insert into app_blocks values('author','reader'); set role service_role;");
    assert.equal((await req('reader','read-qualify',{token:lease.token})).status,404);
    await db.exec('reset role; delete from app_blocks; set role service_role;');
    const reply=await req('reader','replies',{request_id:id(40),body:'Confirmed line reply',target:{id:'1:0:7',version:1,start:0,end:7,quote:'A plain'}});
    assert.equal(reply.status,200); assert.equal((await reply.json()).engagementCount,1);
    assert.equal((await req('other','read-qualify',{token:lease.token})).status,400,'cannot qualify another account lease');
  }finally{await db.close();}
});
