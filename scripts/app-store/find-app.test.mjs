import test from 'node:test';
import assert from 'node:assert/strict';
import {findApp} from './find-app.mjs';
const app = {id:'captro-test',attributes:{bundleId:'com.captro.app'}};
test('filtered lookup requires the exact app identity',async()=>{
  assert.equal((await findApp(async()=>({data:[app]}),'com.captro.app')).id,'captro-test');
  await assert.rejects(findApp(async()=>({data:[app]}),'com.other.app'),/exact bundle/);
});
test('server error fallback cannot select another app',async()=>{
  const paths=[];
  const result=await findApp(async path=>{
    paths.push(path);
    if(paths.length===1) throw Object.assign(Error('server'),{status:500});
    return {data:[{id:'other',attributes:{bundleId:'com.other.app'}},app]};
  },'com.captro.app');
  assert.equal(result.id,'captro-test'); assert.equal(paths.length,2);
  assert.equal(new URLSearchParams(paths[1].split('?')[1]).get('fields[apps]'),'bundleId');
});
test('authorization failures are not bypassed',async()=>{
  let calls=0;
  await assert.rejects(findApp(async()=>{calls++;throw Object.assign(Error('denied'),{status:403});},'com.captro.app'),/denied/);
  assert.equal(calls,1);
});
test('missing or ambiguous identity fails closed',async()=>{
  for(const data of [[],[app,app]]) await assert.rejects(findApp(async()=>({data}),'com.captro.app'),/exact bundle/);
});
