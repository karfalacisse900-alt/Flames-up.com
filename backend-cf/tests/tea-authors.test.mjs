import test from 'node:test';
import assert from 'node:assert/strict';
import { Hono } from 'hono';
import { teaAuthorPhotos } from '../src/tea-authors.ts';
import { mountTeaConversations } from '../src/tea-conversations.ts';
import { mountTeaClubs } from '../src/tea-clubs.ts';
const photo = 'https://media.example.com/avatar.jpg?signature=preserved';
test('Tea batches only returned authors and preserves exact photo references without altering rows', async () => {
  const rows = [{id:'p',author:{id:'a',name:'A'}},{id:'r',author:{id:'a',name:'A'}},{id:'s',author:{id:'b',name:'B'}}];
  let calls=0;
  const result=await teaAuthorPhotos(rows,async ids=>{calls++;assert.deepEqual(ids,['a','b']);return new Map([['a',photo],['not-returned','secret']]);});
  assert.equal(calls,1);assert.equal(result[0].author.photoURL,photo);assert.equal(result[1].author.photoURL,photo);
  assert.equal(result[2].author.photoURL,null);assert.equal(rows[0].author.photoURL,undefined);
  assert.deepEqual(result.map(r=>r.id),['p','r','s']);assert.doesNotMatch(JSON.stringify(result),/secret/);
  assert.equal(await teaAuthorPhotos(null,()=>assert.fail()),null);
});
test('Tea route adds photos only after visibility succeeds, including replies and club messages',async()=>{
  const id='00000000-0000-4000-8000-000000000001';
  for(const club of [false,true]) {
    let denied=false, photos=0;
    const app=new Hono();
    const deps={auth:async(c,n)=>n(),optionalAuth:async(c,n)=>n(),viewer:async()=> 'viewer',limit:async()=>null,restriction:async()=>null,site:p=>p,
      rpc:async()=>{if(denied)throw Error(club?'TEA_CLUB_FORBIDDEN':'TEA_DISCUSSION_UNAVAILABLE');return [{id,body:'Hello.',version:1,createdAt:new Date().toISOString(),author:{id:'author',name:'Author',username:'author'}}];},
      authors:async(c,v)=>teaAuthorPhotos(v,async ids=>{photos++;assert.deepEqual(ids,['author']);return new Map([['author',photo]]);})};
    if(club)mountTeaClubs(app,deps);else mountTeaConversations(app,deps);
    const paths=club?[`/tea/clubs/${id}/messages`]:['/tea/conversations',`/tea/conversations/${id}/replies`];
    for(const path of paths) {
      const res=await app.request(path,{}, {JWT_SECRET:'isolated-test-secret-long-enough'});
      assert.equal(res.status,200);assert.equal((await res.json()).items[0].author.photoURL,photo);
    }
    const count=photos;denied=true;
    const deniedRes=await app.request(paths[0],{}, {JWT_SECRET:'isolated-test-secret-long-enough'});
    assert.ok([403,404].includes(deniedRes.status));assert.equal(photos,count);
  }
});
