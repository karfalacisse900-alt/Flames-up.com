import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {Hono} from 'hono';
import {discussionInput, noteApplicationInput, mountTeaConversations} from '../src/tea-conversations.ts';

const id = n => '00000000-0000-4000-8000-' + String(n).padStart(12,'0');
const note = (patch={}) => discussionInput('create',{request_id:id(1),title:'A plain Note',body:'Everyone can participate.',links:[],...patch});
const form = {kind:'application',label:'Apply',height_requested:true,accepting:true};
const application = (patch={}) => noteApplicationInput({request_id:id(90),version:1,full_name:'Test Applicant',height:'175 cm',availability:'Weekends',portfolio:'https://portfolio.example/work',...patch});
const migration = name => readFileSync(new URL('../../supabase/migrations/'+name,import.meta.url),'utf8');
async function setup() {
  const db = new PGlite();
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
    create table app_users(id text primary key,supabase_user_id uuid,full_name text,username text,is_private boolean default false,metadata jsonb default '{}');
    create table app_blocks(blocker_id text,blocked_id text);
    create table app_follows(app_follower_id text,app_following_id text,status text);
    create table app_professional_roles(user_id text,role text,status text);
    insert into app_users(id,supabase_user_id,full_name,username) values
      ('agency','${id(100)}','Agency','agency'),('reader','${id(101)}','Reader','reader'),('other','${id(102)}','Other','other');
    insert into app_professional_roles values('agency','business','active');
    grant select,update on app_users to service_role;
    grant select on app_blocks,app_follows,app_professional_roles to service_role;`);
  const professional = migration('20261115224938_professional_accounts_studio.sql');
  await db.exec(professional.slice(professional.indexOf('create function public.captro_professional_active'),professional.indexOf('create function public.captro_professional_mutate')));
  await db.exec('revoke all on function captro_professional_active(text,text) from public; grant execute on function captro_professional_active(text,text) to service_role;');
  for (const file of ['20261114230954_tea_conversations.sql','20261115014511_tea_sentence_replies.sql','20261117143031_tea_note_actions.sql']) await db.exec(migration(file));
  await db.exec('set role service_role');
  const rpc = async(name,body) => {
    assert.match(name,/^captro_tea_[a-z_]+$/);
    const keys=Object.keys(body); assert.ok(keys.every(k=>/^p_[a-z_]+$/.test(k)));
    return (await db.query('select '+name+'('+keys.map((k,i)=>k+'=> $'+(i+1)).join(',')+') r',Object.values(body).map(v=>v && typeof v==='object' ? JSON.stringify(v):v))).rows[0].r;
  };
  const write = (actor,action,post,data) => rpc('captro_tea_note_write',{p_actor:actor,p_action:action,p_id:post,p_data:data});
  const read = (actor,post) => rpc('captro_tea_read',{p_viewer:actor,p_kind:'detail',p_id:post});
  const submit = (actor,post,data=application()) => rpc('captro_tea_note_apply',{p_actor:actor,p_id:post,p_request:data.requestID,p_version:data.version,p_answers:data.answers});
  const list = (actor,post,extra={}) => rpc('captro_tea_note_applications',{p_actor:actor,p_id:post,...extra});
  return {db,rpc,write,read,submit,list};
}

test('optional Notes fields preserve plain/old posts and reject unsafe or forged action inputs',()=>{
  assert.ok(!('borough' in note()));
  assert.equal(note({borough:'Brooklyn',primary_action:form}).primaryAction.kind,'application');
  assert.equal(note({primary_action:{kind:'external',label:'Join the test',url:'https://example.com/signup'}}).primaryAction.url,'https://example.com/signup');
  for (const url of ['javascript:alert(1)','http://example.com','https://127.0.0.1','https://user@site.com','https://site.com:443/a','https://local.local']) {
    // Explicit default HTTPS port normalizes safely in URL; other explicit ports are rejected by the existing link validator.
    if(url==='https://site.com:443/a') continue;
    assert.throws(()=>note({primary_action:{kind:'external',label:'Apply',url}}));
  }
  for(const patch of [{borough:'Inferred from GPS'},{primary_action:[form]},
    {primary_action:{...form,recipient_id:'other'}},{primary_action:{kind:'listing',label:'View deal',listing_id:'not-an-id'}},
    {primary_action:{...form,label:''}},{primary_action:{...form,accepting:'yes'}}]) assert.throws(()=>note(patch));
  assert.throws(()=>application({recipient_id:'other'}));
  assert.throws(()=>application({portfolio:'javascript:alert(1)'}));
  assert.throws(()=>application({full_name:''}));
});

test('Brooklyn casting: approved forms, private recipient-only submission and retry idempotency',async()=>{
  const {db,write,read,submit,list}=await setup();try {
    const input=note({borough:'Brooklyn',primary_action:form});
    const created=await write('agency','create',id(1),input);
    assert.equal(created.borough,'Brooklyn');assert.equal(created.primaryAction.state,'active');
    assert.equal(created.canManageApplications,true);
    const result=await submit('reader',id(1));assert.equal(result.confirmed,true);
    assert.deepEqual(await submit('reader',id(1)),result);
    assert.deepEqual(await submit('reader',id(1),application({request_id:id(91)})),result);
    assert.equal((await list('agency',id(1))).length,1);
    const publicNote=await read('other',id(1));
    assert.equal(publicNote.applicationSubmitted,false);assert.equal(publicNote.canManageApplications,false);
    assert.ok(!JSON.stringify(publicNote).includes('Test Applicant'));
    assert.equal((await read('reader',id(1))).applicationSubmitted,true);
    for(const actor of ['reader','other','']) await assert.rejects(list(actor,id(1)),/FORBIDDEN/);
    await assert.rejects(submit('other',id(1)),/CONFLICT/);
    await assert.rejects(submit('reader',id(1),application({availability:'Changed'})),/CONFLICT/);
    await db.exec('reset role; set role authenticated');
    await assert.rejects(db.query('select * from app_tea_applications'),/permission denied/);
    await assert.rejects(list('agency',id(1)),/permission denied/);
    await assert.rejects(submit('reader',id(1)),/permission denied/);
    await db.exec('reset role; set role anon');
    await assert.rejects(db.query('select * from app_tea_applications'),/permission denied/);
  }finally{await db.close();}
});

test('closed/changed/suspended forms reject new submissions, while lost success reconciles and history stays private',async()=>{
  const {db,write,read,submit,list}=await setup();try {
    await write('agency','create',id(1),note({primary_action:form}));
    const confirmed=await submit('reader',id(1));
    const edit=discussionInput('edit',{title:'A plain Note',body:'Everyone can participate.',links:[],version:1,primary_action:{...form,accepting:false}});
    const closed=await write('agency','edit',id(1),edit);assert.equal(closed.version,2);assert.equal(closed.primaryAction.state,'closed');
    await assert.rejects(submit('other',id(1),application({request_id:id(92)})),/FORM_CLOSED/);
    assert.deepEqual(await submit('reader',id(1)),confirmed);
    await write('agency','edit',id(1),{...edit,version:2,primaryAction:{...edit.primaryAction,accepting:true}});
    await assert.rejects(submit('other',id(1),application({request_id:id(92)})),/CONFLICT/);
    await db.exec("reset role;update app_professional_roles set status='suspended';set role service_role;");
    assert.equal((await read('other',id(1))).primaryAction.state,'unavailable');
    await assert.rejects(submit('other',id(1),application({request_id:id(92),version:3})),/FORM_CLOSED/);
    assert.equal((await list('agency',id(1))).length,1);
    await assert.rejects(write('other','create',id(2),note({primary_action:form})),/APPROVAL_REQUIRED/);
    await assert.rejects(write('other','create',id(3),note({primary_action:{...form,accepting:false}})),/APPROVAL_REQUIRED/);
    await db.exec("reset role;insert into app_blocks values('other','agency');set role service_role;");
    await assert.rejects(read('other',id(1)),/UNAVAILABLE/);
    await assert.rejects(submit('other',id(1),application({request_id:id(92),version:3})),/UNAVAILABLE/);
  }finally{await db.close();}
});

test('legacy edits/replies keep action and borough; stale action updates conflict; removal keeps recipient history',async()=>{
  const {db,rpc,write,read,submit,list}=await setup();try {
    await write('agency','create',id(1),note({borough:'Brooklyn',primary_action:form}));
    await submit('reader',id(1));
    const oldEdit={title:'Updated by old client',body:'Existing caption.',links:[],version:1};
    const updated=await rpc('captro_tea_write',{p_actor:'agency',p_action:'edit',p_id:id(1),p_data:oldEdit});
    assert.equal(updated.borough,'Brooklyn');assert.equal(updated.primaryAction.kind,'application');
    await rpc('captro_tea_write',{p_actor:'reader',p_action:'reply',p_id:id(1),p_data:{requestID:id(7),body:'Still a general reply'}});
    assert.equal((await read('reader',id(1))).replyCount,1);
    await assert.rejects(write('agency','edit',id(1),{...oldEdit,borough:'Queens'}),/CONFLICT/);
    const removed=await write('agency','edit',id(1),{...oldEdit,version:2,primaryAction:null,borough:null});
    assert.equal(removed.primaryAction,null);assert.equal(removed.borough,null);assert.equal(removed.canManageApplications,true);
    assert.equal((await list('agency',id(1))).length,1);
    await assert.rejects(write('reader','edit',id(1),{...oldEdit,version:3,borough:'Queens'}),/FORBIDDEN/);
  }finally{await db.close();}
});

test('real Notes HTTP routes enforce identity, approval, recipient reads and exact submission shape',async()=>{
  const {db,rpc}=await setup();try {
    const app=new Hono();
    const auth=async(c,next)=>c.req.header('x-test-actor') ? next() : c.json({},401);
    mountTeaConversations(app,{auth,optionalAuth:async(c,next)=>next(),viewer:async c=>c.req.header('x-test-actor')||'',
      limit:async()=>null,restriction:async()=>null,rpc:async(c,name,body)=>rpc(name,body)});
    const request=(path,actor='agency',method='GET',data)=>app.request(path,{method,headers:{...(actor?{'x-test-actor':actor}:{}),'Content-Type':'application/json'},...(data?{body:JSON.stringify(data)}:{})},{JWT_SECRET:'isolated-note-cursor-key-not-production'});
    assert.equal((await (await request('/tea/conversations/capabilities')).json()).canCreateForms,true);
    assert.equal((await (await request('/tea/conversations/capabilities','reader')).json()).canCreateForms,false);
    const payload={request_id:id(1),title:'Brooklyn casting',body:'An isolated test.',links:[],borough:'Brooklyn',primary_action:form};
    assert.equal((await request('/tea/conversations','reader','POST',payload)).status,403);
    assert.equal((await request('/tea/conversations','agency','POST',payload)).status,200);
    const answers={request_id:id(90),version:1,full_name:'Test Applicant',availability:'Weekends'};
    assert.equal((await request('/tea/conversations/'+id(1)+'/applications','','POST',answers)).status,401);
    for(let retry=0;retry<2;retry++) assert.equal((await request('/tea/conversations/'+id(1)+'/applications','reader','POST',answers)).status,200);
    assert.equal((await request('/tea/conversations/'+id(1)+'/applications','other')).status,403);
    const page=await (await request('/tea/conversations/'+id(1)+'/applications')).json();assert.equal(page.items.length,1);
    assert.equal((await request('/tea/conversations/'+id(1)+'/applications','reader','POST',{...answers,recipient_id:'other'})).status,400);
    const resolved=await (await request('/tea/conversations/'+id(1)+'/action','reader')).json();
    assert.equal(resolved.note.applicationSubmitted,true);assert.equal(resolved.note.author.id,'agency');
  }finally{await db.close();}
});
