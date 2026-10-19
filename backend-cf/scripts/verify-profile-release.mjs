import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
// Only newly-created, identifiable disposable accounts and private fixture posts.
// Never print tokens, emails, response bodies or customer identifiers.
const db=`https://${process.env.SUPABASE_PROJECT_REF}.supabase.co`;
const api='https://flames-up-api.karfalacisse900.workers.dev/api';
const admin={apikey:process.env.SUPABASE_SERVICE_ROLE_KEY,Authorization:`Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`};
assert.ok(admin.apikey&&process.env.SUPABASE_ANON_KEY,'Protected credentials required');
const accounts=[],posts=[];
async function request(url,method='GET',body,headers={},expected){
 const response=await fetch(url,{method,headers:{'Content-Type':'application/json',...headers},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
 if(expected){assert.equal(response.status,expected,`${method} ${new URL(url).pathname}`);return;}
 assert.ok(response.ok,`${method} ${new URL(url).pathname}: HTTP ${response.status}`);
 const text=await response.text();return text?JSON.parse(text):null;
}
async function account(){
 const email=`captro-profile-qa-${randomUUID()}@captro.invalid`,password=randomUUID()+randomUUID();
 const created=await request(db+'/auth/v1/admin/users','POST',{email,password,email_confirm:true},admin);
 const entry={auth:created.id,email};accounts.push(entry);
 const auth=await request(db+'/auth/v1/token?grant_type=password','POST',{email,password},{apikey:process.env.SUPABASE_ANON_KEY});
 entry.headers={Authorization:`Bearer ${auth.access_token}`};
 entry.id=(await request(api+'/auth/me','GET',undefined,entry.headers)).id;assert.ok(entry.id);return entry;
}
try{
 const owner=await account(),visitor=await account();
 const call=(path,method='GET',body,who=owner,expected)=>request(api+path,method,body,who.headers,expected);
 await call('/users/me','PUT',{bio:'Disposable profile validation',open_to:'Photo walks',is_private:true});
 const own=await call('/auth/me');assert.equal(own.open_to,'Photo walks');
 const locked=await call(`/users/${owner.id}`,'GET',undefined,visitor);
 assert.equal(locked.privacy_locked,true);
 for(const key of ['email','phone','metadata','profile','open_to','followers_count'])assert.equal(key in locked,false);
 await call(`/users/${owner.id}/posts`,'GET',undefined,visitor,403);
 assert.deepEqual(await call(`/users/${owner.id}/showcase`,'GET',undefined,visitor),{pinned:null,clubs:[]});
 await call('/users/me','PUT',{is_verified:true},owner,400);
 let relation=await call(`/users/${owner.id}/follow`,'POST',{following:true},visitor);
 assert.equal(relation.following,false);assert.equal(relation.follow_pending,true);
 relation=await call(`/users/${owner.id}/follow`,'POST',{following:true},visitor);
 assert.equal(relation.follow_pending,true);
 assert((await call('/users/me/follow-requests')).some(row=>row.id===visitor.id));
 await call(`/users/me/follow-requests/${visitor.id}`,'POST',{approved:true});
 assert.equal((await call(`/users/${owner.id}`,'GET',undefined,visitor)).is_following,true);
 const post=randomUUID();posts.push(post);
 await request(db+'/rest/v1/app_posts','POST',{id:post,legacy_post_id:post,app_user_id:owner.id,user_id:owner.auth,visibility:'private',content:'Private profile acceptance fixture',status:'active'},admin);
 await call('/users/me/showcase','PUT',{pinned_post_id:post});
 await call('/users/me','PUT',{open_to:'Updated introduction'});
 assert.equal((await call(`/users/${owner.id}/showcase`)).pinned.id,post);
 await call('/users/me/showcase','PUT',{pinned_post_id:''});
 assert.equal((await call(`/users/${owner.id}/showcase`)).pinned,null);
 await call(`/users/${owner.id}/follow`,'POST',{following:false},visitor);
 assert.equal((await call(`/users/${owner.id}`,'GET',undefined,visitor)).privacy_locked,true);
 console.log('PASS: live profile edit, protected-field rejection, private projection, pending/repeated follow, owner approval, unfollow, pin/edit/unpin, unauthorized content denial.');
}finally{
 for(const id of posts)await request(db+`/rest/v1/app_posts?id=eq.${id}`,'DELETE',undefined,admin);
 for(const entry of accounts){
  const user=await request(db+`/auth/v1/admin/users/${entry.auth}`,'GET',undefined,admin);
  assert.equal(user.email,entry.email);assert.match(user.email,/^captro-profile-qa-[a-f0-9-]+@captro\.invalid$/);
  if(entry.id)await request(db+`/rest/v1/app_users?id=eq.${entry.id}`,'DELETE',undefined,admin);
  await request(db+`/auth/v1/admin/users/${entry.auth}`,'DELETE',undefined,admin);
 }
 console.log('Removed this run’s disposable profile accounts and private fixture only.');
}
