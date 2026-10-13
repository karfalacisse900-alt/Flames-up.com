import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

// Explicit post-deploy acceptance. Only two newly-created disposable accounts
// and one private fixture post are modified. Credentials never enter logs.
const db=`https://${process.env.SUPABASE_PROJECT_REF}.supabase.co`;
const api='https://flames-up-api.karfalacisse900.workers.dev/api';
const admin={apikey:process.env.SUPABASE_SERVICE_ROLE_KEY,Authorization:`Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`};
assert.ok(admin.apikey && process.env.SUPABASE_ANON_KEY,'Protected credentials required');
const accounts=[]; const post=randomUUID(); let postCreated=false;
async function request(url,method='GET',body,headers={},expected) {
  const response=await fetch(url,{method,headers:{'Content-Type':'application/json',...headers},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(60000)});
  if(expected) {assert.equal(response.status,expected,`${method} ${new URL(url).pathname}`);return;}
  assert.ok(response.ok,`${method} ${new URL(url).pathname}: HTTP ${response.status}`);
  const text=await response.text(); return text?JSON.parse(text):null;
}
async function account() {
  const email=`captro-favorites-qa-${randomUUID()}@captro.invalid`,password=randomUUID()+randomUUID();
  const user=await request(db+'/auth/v1/admin/users','POST',{email,password,email_confirm:true},admin);
  const entry={auth:user.id,email}; accounts.push(entry);
  const auth=await request(db+'/auth/v1/token?grant_type=password','POST',{email,password},{apikey:process.env.SUPABASE_ANON_KEY});
  entry.headers={Authorization:`Bearer ${auth.access_token}`};
  entry.id=(await request(api+'/auth/me','GET',undefined,entry.headers)).id;
  assert.ok(entry.id); return entry;
}
try {
  const [alice,bob]=[await account(),await account()];
  await request(db+'/rest/v1/app_posts','POST',{id:post,legacy_post_id:post,app_user_id:alice.id,user_id:alice.auth,visibility:'private',content:'Private Favorites acceptance fixture'},admin);
  postCreated=true;
  const call=(path,method='GET',body,owner=alice,expected)=>request(api+path,method,body,owner.headers,expected);
  await call('/favorites/collections','POST',{name:'Dining'});
  const created=await call('/favorites/collections','POST',{name:'New York'});
  const ids=created.collections.map(x=>x.id);
  assert.equal(ids.length,2);
  const path=`/favorites/posts/${post}`;
  const set=(saved,revision,collection_ids,request_id=randomUUID(),owner=alice,expected)=>call(path,'PUT',{saved,expected_revision:revision,collection_ids,request_id},owner,expected);
  assert.equal((await call(path)).state.saved,false);
  const requestID=randomUUID(); const saved=await set(true,0,ids,requestID);
  assert.equal(saved.state.collection_ids.length,2);
  assert.equal((await set(true,0,ids,requestID)).state.revision,1);
  await set(false,0,[],randomUUID(),alice,409);
  assert.equal((await call('/favorites')).entries[0].post.id,post);
  assert.equal((await call('/favorites','GET',undefined,bob)).entries.length,0);
  await set(true,0,[],randomUUID(),bob,404);
  await call(`/favorites/collections/${ids[0]}`,'PUT',{name:'Stolen'},bob,404);
  await set(false,1,[]); assert.equal((await call('/favorites')).entries.length,0);
  await set(true,2,ids); assert.equal((await call(path)).state.collection_ids.length,2);
  await call(`/favorites/collections/${ids[0]}`,'DELETE');
  assert.equal((await call(path)).state.saved,true);
  assert.equal((await call(path)).state.collection_ids.length,1);
  // Old app unsave must remove the new memberships too.
  await call(`/library/save/${post}`,'DELETE');
  assert.equal((await call(path)).state.saved,false);
  assert.equal((await call(path)).state.collection_ids.length,0);
  const counters=await request(db+`/rest/v1/app_posts?id=eq.${post}&select=likes_count`, 'GET',undefined,admin);
  assert.equal(counters[0].likes_count,0);
  console.log('PASS: live save, multi-collection, idempotency, stale-write rejection, private visibility, cross-owner denial, Undo, delete-collection retention, legacy unsave, unchanged likes.');
} finally {
  if(postCreated) {
    await request(db+`/rest/v1/app_post_interactions?legacy_post_id=eq.${post}`,'DELETE',undefined,admin);
    await request(db+`/rest/v1/app_posts?id=eq.${post}`,'DELETE',undefined,admin);
  }
  for(const entry of accounts) {
    const user=await request(db+`/auth/v1/admin/users/${entry.auth}`,'GET',undefined,admin);
    assert.equal(user.email,entry.email);
    assert.match(user.email,/^captro-favorites-qa-[a-f0-9-]+@captro\.invalid$/);
    if(entry.id) await request(db+`/rest/v1/app_users?id=eq.${entry.id}`,'DELETE',undefined,admin);
    await request(db+`/auth/v1/admin/users/${entry.auth}`,'DELETE',undefined,admin);
  }
  console.log('Removed only this run’s disposable accounts and private fixture. No customer posts or media changed.');
}
