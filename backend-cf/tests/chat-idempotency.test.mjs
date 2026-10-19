import test from 'node:test';
import assert from 'node:assert/strict';
import {chatOperationID, persistChatOperation} from '../src/chat-idempotency.ts';

test('chat operation identity matches native fixture and isolates sender, thread and intent',async()=>{
  const id=await chatOperationID('sender','direct','peer','local-123');
  assert.equal(id,'f79f842b1895364a25237b105d7e64bc0e4c4f502adb4cbd70e65228740ff7ba');
  for(const args of [['sender','group','peer','local-123'],['other','direct','peer','local-123'],['sender','direct','peer','local-456']])
    assert.notEqual(await chatOperationID(...args),id);
});
test('lost response and concurrent repeated text/media sends produce one immutable canonical message',async()=>{
  for(const group of [false,true])for(const media of [null,'https://fixture.invalid/authorized-image']) {
    const id=await chatOperationID('sender',group?'group':'direct','peer','local-123');
    const row={id,sender_id:'sender',[group?'group_id':'receiver_id']:'peer',body:media?'':'hello',media_url:media,media_type:media?'image':null};
    let stored=null, inserts=0;
    const read=async()=>stored;
    const insert=async()=>{if(stored)throw Error('unique violation');stored=structuredClone(row);inserts++;throw Error('response lost after commit');};
    const results=await Promise.all(Array.from({length:15},()=>persistChatOperation(row,read,insert)));
    assert.equal(inserts,1);assert.ok(results.every(r=>r.row.id===id));
    // Restart loses all caller memory, but the database row still reconciles.
    const replay=await persistChatOperation(structuredClone(row),read,insert);
    assert.equal(replay.row.id,id);assert.equal(inserts,1);
    await assert.rejects(persistChatOperation({...row,body:'different'},read,insert),/CONFLICT/);
    assert.deepEqual(stored,row);
  }
});
test('a real database failure without a canonical row remains a retryable failure',async()=>{
  await assert.rejects(persistChatOperation({id:'fixture'},async()=>null,async()=>{throw Error('unavailable');}),/unavailable/);
});
