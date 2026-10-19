import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {chatOperationID,sameChatOperation,persistChatOperation} from '../src/chat-idempotency.ts';

const source=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
const ast=ts.createSourceFile('index.ts',source,ts.ScriptTarget.Latest,true);
function route(method,path,deps) {
  const node=ast.statements.find(n=>ts.isExpressionStatement(n)&&ts.isCallExpression(n.expression)&&
    n.expression.expression.getText(ast)===`api.${method}`&&n.expression.arguments[0]?.text===path);
  assert.ok(node,path);
  const code=ts.transpileModule(`const handler=${node.expression.arguments.at(-1).getText(ast)};`,{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
  return Function(...Object.keys(deps),code+';return handler;')(...Object.values(deps));
}
const clean=v=>String(v??'').trim();
const base={getUserId:()=> 'fixture-owner',requireSupabasePrimaryDatabase:()=>null,rejectLargeRequest:()=>null,
  postgrestEqFilter:v=>'eq.'+v,postgrestInFilter:v=>v,now:()=>new Date().toISOString()};
const context=(body,query={})=>({req:{json:async()=>body,query:k=>query[k],param:()=> 'fixture-peer'},header(){},json:(body,status=200)=>({body,status})});

test('actual notification read route scopes selected IDs to authenticated owner; invalid bodies never bulk-read',async()=>{
  let patch;
  const call=route('post','/notifications/mark-read',{...base,supabaseAdminPatchRows:async(c,t,f,p)=>{patch={t,f,p};}});
  assert.equal((await call(context({ids:['one','two']}))).status,200);
  assert.deepEqual(patch.f,{user_id:'eq.fixture-owner',id:['one','two']});
  for(const body of [null,[],{ids:[]},{ids:Array(61).fill('one')},{ids:[42]}]) {
    patch=null;assert.equal((await call(context(body))).status,400);assert.equal(patch,null);
  }
  await call(context({}));assert.deepEqual(patch.f,{user_id:'eq.fixture-owner'}); // old explicit bulk client
});

test('actual follow request pagination continues past a completely filtered page and supports old array clients',async()=>{
  const rows=Array.from({length:30},(_,i)=>({app_follower_id:'hidden-'+i}));
  const call=route('get','/users/me/follow-requests',{...base,supabaseAdminQueryRows:async(c,t,q)=>{
    assert.equal(q.filters.app_following_id,'eq.fixture-owner');assert.equal(q.limit,30);return rows;
  },supabaseUsersByAnyIds:async()=>new Map(),supabaseBlockedUserIds:async()=>new Set(rows.map(r=>r.app_follower_id)),
  supabaseUserIsActive:()=>false,publicUsernameFor:clean,cleanText:clean,safeMediaReference:clean});
  assert.deepEqual((await call(context(null,{paged:'1',skip:'30'}))).body,{users:[],next_skip:60});
  assert.deepEqual((await call(context(null))).body,[]);
});

test('actual direct/group send handlers reconcile lost responses and reject changed payload or newly denied access',async()=>{
  for(const path of ['/messages','/group-chats/:groupId/messages']) for(const media of [null,'https://fixture.invalid/owned']) {
    const stored=new Map();let insertCount=0,denied=false;
    const deps={...base,publicId:clean,cleanText:clean,cleanMultilineText:clean,rejectUnknownFields:()=>null,
      enforceRateLimit:async()=>null,enforceUserRestriction:async()=>denied?{status:403}:null,
      safeMediaReference:clean,normalizedMediaReferenceForStorage:(c,v)=>v,messageMediaOwnedBy:async()=>true,
      validateDirectMessagePeer:async()=>null,requireGroupMember:async()=>true,getClientRequestId:(c,b)=>b.client_request_id??'',
      chatOperationID,sameChatOperation,persistChatOperation,uuid:()=> 'legacy-fixture',
      supabaseAdminQueryRows:async(c,t,q)=>q.filters.id?[stored.get(q.filters.id.slice(3))].filter(Boolean):[],
      supabaseAdminInsertRows:async(c,t,[row])=>{assert.ok(!stored.has(row.id));stored.set(row.id,row);insertCount++;throw Error('lost committed response');},
      messagePayload:async(c,m)=>m,supabaseMessageToLegacy:v=>v,setSupabasePrimaryTyping:async()=>{},
      supabaseAdminPatchRows:async()=>{},runBackgroundTask:()=>{},logSecurityEvent:async()=>{}};
    const call=route('post',path,deps);
    const body={receiver_id:'fixture-peer',content:media?'':'hello',media_url:media,client_request_id:'local-fixture'};
    const first=await call(context(body));assert.equal(first.status,200);
    const retry=await call(context(body));assert.equal(retry.body.id,first.body.id);assert.equal(insertCount,1);
    assert.equal((await call(context({...body,content:'changed'}))).status,409);
    denied=true;assert.equal((await call(context(body))).status,403);assert.equal(insertCount,1);
  }
});
