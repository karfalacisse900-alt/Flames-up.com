import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {stripTypeScriptTypes} from 'node:module';

test('authenticated profile and sign-in payload retain persisted Open to',()=>{
 const source=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
 const code=stripTypeScriptTypes(source.slice(source.indexOf('function authUserPayload('),source.indexOf('async function requirePhoneVerified(')));
 const deps={usernameNeedsOnboarding:()=>false,publicUserEmail:v=>v,accountEmailVerified:()=>true,publicUsernameFor:u=>u.username,userHasActivePremium:()=>false,normalizeLanguage:v=>v,normalizeAuthProvider:v=>v,cleanText:v=>v??''};
 const payload=Function(...Object.keys(deps),code+';return authUserPayload;')(...Object.values(deps));
 assert.equal(payload({id:'owner',open_to:'Photo walks'}).open_to,'Photo walks');
 assert.equal(payload({id:'owner',open_to:''}).open_to,'');
 assert.equal(payload({id:'owner'}).open_to,'');
});

test('private follow transitions are atomic, idempotent and owner-decided', async()=>{
 const db=new PGlite();
 try {
  await db.exec(`create role anon; create role authenticated; create role service_role;
   create table app_users(id text primary key,is_private boolean default false,metadata jsonb default '{}',profile jsonb default '{}',updated_at timestamptz,
     full_name text,bio text,avatar_url text,cover_url text,city text,username text);
   create table app_follows(app_follower_id text,app_following_id text,status text,updated_at timestamptz,primary key(app_follower_id,app_following_id));
   create table app_blocks(blocker_id text,blocked_id text);
   create table app_posts(legacy_post_id text primary key,app_user_id text,status text,post_type text);
   insert into app_users(id,is_private) values('a',true),('b',false),('c',false);
   insert into app_posts values('club-a','a','active','club'),('moment-a','a','active','media'),('private-b','b','active','club');`);
  await db.exec(readFileSync(new URL('../../supabase/migrations/20261018224210_profile_privacy_showcase.sql',import.meta.url),'utf8'));
  const follow=async(actor,target,action)=>(await db.query('select captro_profile_follow($1,$2,$3) result',[actor,target,action])).rows[0].result;
  const showcase=async(actor,patch)=>(await db.query('select captro_profile_showcase($1,$2) result',[actor,JSON.stringify(patch)])).rows[0].result;
  assert.deepEqual(await follow('b','a','follow'),{following:false,follow_pending:true});
  assert.deepEqual(await follow('b','a','follow'),{following:false,follow_pending:true});
  await assert.rejects(follow('c','b','approve'),/REQUEST_MISSING/);
  assert.deepEqual(await follow('a','b','approve'),{following:true,follow_pending:false});
  assert.deepEqual(await follow('a','b','approve'),{following:true,follow_pending:false});
  await follow('b','a','unfollow');
  assert.deepEqual(await follow('b','a','unfollow'),{following:false,follow_pending:false});
  await follow('b','a','follow'); await follow('a','b','decline');
  assert.equal((await db.query('select * from app_follows')).rows.length,0);
  assert.equal((await follow('a','b','follow')).following,true);
  await db.exec("insert into app_blocks values('c','a')");
  await assert.rejects(follow('a','c','follow'),/BLOCKED/);
  await db.exec("update app_users set metadata='{"+'"status":"suspended"'+"}' where id='b'");
  await assert.rejects(follow('b','a','follow'),/UNAVAILABLE/);
  assert.deepEqual(await showcase('a',{pinned_post_id:'moment-a',club_post_ids:['club-a']}),{pinned_post_id:'moment-a',club_post_ids:['club-a']});
  await showcase('a',{pinned_post_id:'club-a'});
  assert.equal((await showcase('a',{pinned_post_id:''})).pinned_post_id,'');
  await assert.rejects(showcase('a',{pinned_post_id:'private-b'}),/NOT_OWNED/);
  await assert.rejects(showcase('a',{club_post_ids:['moment-a']}),/NOT_CLUB/);
  await assert.rejects(showcase('a',{is_verified:true}),/INVALID_FIELDS/);
  await assert.rejects(showcase('a',{club_post_ids:Array(13).fill('club-a')}),/INVALID_CLUBS/);
  await assert.rejects(showcase('a',null),/INVALID_FIELDS/);
  const edit=async(patch,profile)=>(await db.query('select captro_profile_edit($1,$2,$3)',['a',JSON.stringify(patch),JSON.stringify(profile)]));
  await showcase('a',{pinned_post_id:'club-a'});
  await edit({bio:'Updated biography'},{open_to:'Photo walks'});
  await showcase('a',{club_post_ids:[]});
  const edited=(await db.query("select * from app_users where id='a'")).rows[0];
  assert.equal(edited.bio,'Updated biography');
  assert.equal(edited.profile.pinned_post_id,'club-a');
  assert.equal(edited.profile.open_to,'Photo walks');
  await assert.rejects(edit({metadata:{status:'active'}},{}),/INVALID_FIELDS/);
  await assert.rejects(edit({},{pinned_post_id:'private-b'}),/INVALID_FIELDS/);
  await db.exec('set role authenticated');
  await assert.rejects(follow('b','a','follow'),/permission denied/);
  await assert.rejects(db.query("insert into app_follows values('b','a','active',now())"),/permission denied/);
  await assert.rejects(showcase('a',{pinned_post_id:'club-a'}),/permission denied/);
  await assert.rejects(edit({bio:'Forged'},{}),/permission denied/);
 } finally {await db.close();}
});

test('actual public profile projection strips private fields and locked counts',async()=>{
 const source=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
 const code=stripTypeScriptTypes(source.slice(source.indexOf('async function supabasePublicUserPayload('),source.indexOf('async function supabaseSetFollowState(')));
 let privateAccount=false, following=false, block=null;
 const deps={supabaseUserByAnyId:async()=>({id:'owner',is_private:privateAccount,username:'owner',email:'secret',phone:'secret',metadata:{secret:true},profile:{open_to:'Photo walks'}}),
  supabaseUserStatus:()=> 'active',publicId:v=>String(v??''),supabaseFollowStats:async()=>({followers_count:10,following_count:5}),supabaseIsFollowing:async()=>following,
  supabaseBlockPair:async()=>block,supabaseAdminQueryRows:async()=>[],postgrestEqFilter:v=>'eq.'+v,parseJsonObject:v=>v??{},safeUserPayload:v=>v,cleanText:v=>v??''};
 const read=Function(...Object.keys(deps),code+';return supabasePublicUserPayload;')(...Object.values(deps));
 let response=await read({},'visitor','owner');
 assert.equal(response.body.open_to,'Photo walks');
 for(const field of ['email','phone','metadata','profile','supabase_user_id']) assert.equal(field in response.body,false);
 privateAccount=true; response=await read({},'visitor','owner');
 assert.equal(response.body.privacy_locked,true);
 for(const field of ['followers_count','following_count','posts_count','open_to','bio','city']) assert.equal(field in response.body,false);
 following=true; assert.equal((await read({},'visitor','owner')).body.privacy_locked,undefined);
 block={blocker_id:'visitor',blocked_id:'owner'};
 assert.equal((await read({},'visitor','owner')).body.privacy_locked,true);
});
