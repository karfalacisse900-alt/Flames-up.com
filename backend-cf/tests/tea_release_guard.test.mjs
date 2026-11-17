import test from 'node:test';
import assert from 'node:assert/strict';
import { baseline, precedingVersion, teaRepairFiles, verifyTeaSource } from '../scripts/verify-tea-release.mjs';
const before={changed:teaRepairFiles,version:precedingVersion,annotations:{'workers/message':'Professional accounts and Tea '+baseline}};
test('Tea repair release binds the reviewed production version, source and four-file scope',()=>{
  assert.doesNotThrow(()=>verifyTeaSource(before));
  assert.throws(()=>verifyTeaSource({...before,changed:[...teaRepairFiles,'backend-cf/src/creator-support.ts']}));
  assert.throws(()=>verifyTeaSource({...before,version:'unexpected'}));
  assert.throws(()=>verifyTeaSource({...before,annotations:{'workers/message':'unreviewed'}}));
  assert.throws(()=>verifyTeaSource({...before,expectedVersion:'different-inspection'}));
});
test('Tea repair post-deployment check requires the exact candidate source',()=>{
  const candidate='a'.repeat(40),after={...before,after:true,candidate,annotations:{'workers/message':'Tea Conversations '+candidate}};
  assert.doesNotThrow(()=>verifyTeaSource(after));
  assert.throws(()=>verifyTeaSource({...after,candidate:'b'.repeat(40)}));
  assert.throws(()=>verifyTeaSource({...after,candidate:''}));
  assert.throws(()=>verifyTeaSource({...after,changed:[]}));
});
