import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {commerceAvailability, publicCommercePayload} from '../src/commerce.ts';
import {purchaseFailureMessage} from '../src/purchase-errors.ts';
const now=Date.parse('2026-09-27T00:00:00Z');
test('explicit event end closes new sales without changing original data',()=>{
 const item={id:'a',status:'active',content_type:'event',starts_at:'2026-09-04T20:49:15Z',ends_at:'2026-09-04T21:49:15Z'};
 assert.equal(commerceAvailability(item,now),'ended');
 assert.equal(item.status,'active');
 assert.equal(publicCommercePayload(item,[]).status,'ended');
 assert.match(purchaseFailureMessage('CAPTRO_EVENT_ENDED'),/event has ended/);
});
test('availability uses absolute timestamps, not viewer timezone or start-only guesses',()=>{
 assert.equal(commerceAvailability({status:'active',content_type:'meetup',ends_at:'2026-09-26T20:00:00-04:00'},now),'ended');
 assert.equal(commerceAvailability({status:'active',content_type:'event',starts_at:'2026-09-01T00:00:00Z'},now),'active');
 assert.equal(commerceAvailability({status:'active',content_type:'club',ends_at:'2026-09-01T00:00:00Z'},now),'active');
 assert.equal(commerceAvailability({status:'cancelled',content_type:'event',ends_at:'2026-09-01T00:00:00Z'},now),'cancelled');
 assert.equal(commerceAvailability({status:'active',content_type:'deal',expires_at:'2026-09-01T00:00:00Z'},now),'expired');
});
test('access-only hydration still authorizes visibility before skipping unrelated decoration',()=>{
 const source=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
 const reader=source.slice(source.indexOf('async function supabaseReadVisiblePosts'),source.indexOf('function postgrestInFilter'));
 assert.ok(reader.indexOf('supabaseAppPostVisibleToViewer')<reader.indexOf("if (options.hydration === 'access') return ordered"));
 assert.ok(reader.indexOf("if (options.hydration === 'access') return ordered")<reader.indexOf('await attachPublicPostObjects'));
 const route=source.slice(source.indexOf("api.get('/commerce/posts/:postId'"),source.indexOf('const beginCommercePurchaseHandler'));
 assert.match(route,/hydration: 'access'/);
 assert.ok(route.includes("requestId: c.get('requestId')"));
});

test('identity lookup coalesces within one request, never across accounts or requests',async()=>{
 const {stripTypeScriptTypes}=await import('node:module');
 const source=readFileSync(new URL('../src/index.ts',import.meta.url),'utf8');
 const start=source.indexOf('async function supabaseRelatedInteractionUserIds(');
 const end=source.indexOf('async function readSupabaseRelatedInteractionUserIds(',start);
 const code=stripTypeScriptTypes(source.slice(start,end));
 let calls=0;
 const lookup=new Function('readSupabaseRelatedInteractionUserIds','publicId',code+'; return supabaseRelatedInteractionUserIds;')(
  async(_c,id)=>{calls++;await Promise.resolve();if(id==='fail')throw Error('failed');return [id]}, id=>id);
 const context=()=>{const map=new Map();return {get:k=>map.get(k),set:(k,v)=>map.set(k,v)}};
 const c=context();
 assert.deepEqual(await Promise.all([lookup(c,'buyer'),lookup(c,'buyer'),lookup(c,'buyer')]),[['buyer'],['buyer'],['buyer']]);
 assert.equal(calls,1);
 await lookup(c,'seller');await lookup(context(),'buyer');assert.equal(calls,3);
 await assert.rejects(lookup(c,'fail'));await assert.rejects(lookup(c,'fail'));assert.equal(calls,5);
});
