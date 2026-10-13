import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import vm from 'node:vm';
import ts from 'typescript';

const source=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
const ast=ts.createSourceFile('index.ts',source,ts.ScriptTarget.Latest,true);
function route(method,path,bindings={}) {
  const call=ast.statements.filter(ts.isExpressionStatement).map(x=>x.expression).find(x=>ts.isCallExpression(x)&&x.expression.getText(ast)===`api.${method}`&&x.arguments[0]?.text===path);
  assert.ok(call);
  const code=ts.transpileModule(`const handler=${call.arguments.at(-1).getText(ast)}`,{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
  return vm.runInNewContext(code+';handler',{
    requireSupabasePrimaryDatabase:()=>null,getUserId:()=> 'alice',enforceRateLimit:async()=>null,rejectLargeRequest:()=>null,
    publicId:x=>String(x||'').trim(),isUuidText:x=>/^[a-f0-9-]{36}$/i.test(x||''),
    clampNumber:(v,min,max)=>Math.max(min,Math.min(max,Number(v))),
    favoriteError:(_c,e)=>{throw e},...bindings});
}
const context=(body={},query={})=>({req:{json:async()=>body,param:()=> 'post',query:key=>query[key]},json:(body,status=200)=>({body,status})});

test('Favorites route refuses saving inaccessible posts and never trusts client owner',async()=>{
  let calls=0;
  const handler=route('put','/favorites/posts/:postId',{
    supabaseReadVisiblePosts:async()=>[], favoriteRPC:async()=>{calls++;},
  });
  const response=await handler(context({saved:true,request_id:randomUUID(),expected_revision:0,collection_ids:[],owner_id:'victim'}));
  assert.equal(response.status,404); assert.equal(calls,0);
});
test('Favorites route uses authenticated identity and permits removing unavailable saves',async()=>{
  let calls=0;
  const handler=route('put','/favorites/posts/:postId',{
    supabaseResolvePostIdentity:async()=>({legacyPostId:'post'}),
    supabaseReadVisiblePosts:async()=>{throw Error('unsave must not require post access')},
    favoriteRPC:async(_c,owner,action,input)=>{
      assert.equal(owner,'alice'); assert.equal(action,'set'); assert.equal(input.saved,false); calls++;
      assert.equal(input.owner_id,undefined); return {state:{saved:false}};
    }
  });
  assert.equal((await handler(context({saved:false,request_id:randomUUID(),expected_revision:1,collection_ids:[],owner_id:'victim'}))).status,200);
  assert.equal(calls,1);
});
test('Favorites list exposes unavailable rows, not private post contents or unsafe previews',async()=>{
  const handler=route('get','/favorites',{
    favoriteRPC:async()=>({post_ids:['visible','private'],collections:[{id:'collection',name:'Mine',count:2,preview_post_ids:['private','visible']}]}),
    supabaseReadVisiblePosts:async(_c,owner)=>{assert.equal(owner,'alice');return [{id:'visible'}]},
    feedPostPayload:row=>row,
  });
  const c=context(); c.env={}; const result=await handler(c);
  assert.equal(result.body.entries[1].post,null);
  assert.equal(result.body.collections[0].previews.length,1);
  assert.equal(result.body.collections[0].previews[0].id,'visible');
});

const migration = readFileSync(new URL('../../supabase/migrations/20261013012807_private_favorites.sql',import.meta.url),'utf8');
async function fixture() {
  const db=new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create table app_users(id text primary key);
    insert into app_users values('alice'),('bob');
    create table app_post_interactions(id uuid primary key default gen_random_uuid(),legacy_post_id text,post_id uuid,
      app_user_id text,user_id uuid,kind text,collection text,actor_key text,created_at timestamptz default now());
    grant all on app_post_interactions to service_role;`);
  await db.exec(migration);
  const rpc=async (action,input={},owner='alice')=> {
    const identity={actor_key:`app:${owner}`,app_ids:[owner],auth_ids:[],actor_keys:[`app:${owner}`]};
    return (await db.query('select captro_favorites($1,$2,$3,$4) result',[owner,JSON.stringify(identity),action,JSON.stringify(input)])).rows[0].result;
  };
  return {db,rpc,set:(saved,ids=[],revision=0,request=randomUUID())=>rpc('set',{post_key:'post',saved,collection_ids:ids,expected_revision:revision,request_id:request})};
}
test('Favorites migration: multi-collection save, unsave and Undo are atomic; likes untouched',async()=>{
  const {db,rpc,set}=await fixture();
  try {
    await db.exec("insert into app_post_interactions(legacy_post_id,app_user_id,kind) values('post','alice','like')");
    await rpc('create',{name:'Dining'}); const created=await rpc('create',{name:'NYC'});
    const ids=created.collections.map(x=>x.id);
    const saved=await set(true,ids); assert.equal(saved.state.saved,true); assert.equal(saved.state.collection_ids.length,2);
    const removed=await set(false,[],1); assert.equal(removed.state.saved,false); assert.deepEqual(removed.state.collection_ids,[]);
    const restored=await set(true,ids,2); assert.deepEqual(restored.state.collection_ids.sort(),ids.sort());
    const rows=(await db.query('select kind,count(*)::int n from app_post_interactions group by kind')).rows;
    assert.deepEqual(Object.fromEntries(rows.map(x=>[x.kind,x.n])),{like:1,save:1});
    await rpc('delete',{collection_id:ids[0]}); const current=await rpc('read',{post_key:'post'});
    assert.equal(current.state.saved,true); assert.equal(current.state.collection_ids.length,1);
  } finally {await db.close();}
});
test('Favorites migration: owner isolation, no direct API access, rollback and stale write rejection',async()=>{
  const {db,rpc,set}=await fixture();
  try {
    const other=(await rpc('create',{name:'Private'},'bob')).collections[0].id;
    await assert.rejects(set(true,[other]),/FAVORITES_COLLECTION_NOT_FOUND/);
    assert.equal((await rpc('read',{post_key:'post'})).state.saved,false);
    await assert.rejects(rpc('rename',{name:'Stolen',collection_id:other}),/FAVORITES_COLLECTION_NOT_FOUND/);
    await assert.rejects(rpc('delete',{collection_id:other}),/FAVORITES_COLLECTION_NOT_FOUND/);
    assert.equal((await rpc('read')).collections.length,0);
    const request=randomUUID(); await set(true,[],0,request); await set(true,[],0,request);
    assert.equal((await rpc('read',{post_key:'post'})).state.revision,1);
    await assert.rejects(set(false,[],0),/FAVORITES_CONFLICT/);
    for(const role of ['anon','authenticated']) {
      await db.exec(`set role ${role}`);
      await assert.rejects(db.query('select * from app_favorite_collections'),/permission denied/);
      await assert.rejects(rpc('read'),/permission denied/);
      await db.exec('reset role');
    }
    await db.exec('set role service_role'); assert.equal((await rpc('read',{post_key:'post'})).state.saved,true);
  } finally {await db.close();}
});
test('Favorites migration: legacy collections imported once; old save routes retain and clear memberships',async()=>{
  const {db,rpc}=await fixture();
  try {
    await db.exec("insert into app_post_interactions(legacy_post_id,app_user_id,kind,collection) values('old','alice','save','Travel')");
    const first=await rpc('read'); assert.equal(first.collections[0].name,'Travel'); assert.equal(first.collections[0].count,1);
    assert.equal((await rpc('read')).collections.length,1);
    await rpc('set',{post_key:'old',saved:true,legacy_collection:'Art'});
    assert.equal((await rpc('read',{post_key:'old'})).state.collection_ids.length,2);
    await rpc('set',{post_key:'old',saved:false});
    assert.deepEqual((await rpc('read',{post_key:'old'})).state.collection_ids,[]);
    assert.deepEqual((await rpc('read')).post_ids,[]);
    await rpc('set',{post_key:'old',saved:true,legacy_collection:'Travel'});
    await db.exec("delete from app_post_interactions where kind='save' and app_user_id='alice'");
    const directDeleted=await rpc('read',{post_key:'old'});
    assert.equal(directDeleted.state.saved,false);
    assert.deepEqual(directDeleted.state.collection_ids,[]);
  } finally {await db.close();}
});
