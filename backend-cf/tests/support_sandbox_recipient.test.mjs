import test from 'node:test';
import assert from 'node:assert/strict';
import {findSupportSandboxRecipient} from '../scripts/support-sandbox-recipient.mjs';
const account = (id,patch={}) => ({id,details_submitted:true,payouts_enabled:true,
  settings:{payouts:{schedule:{interval:'manual'}}},requirements:{currently_due:[]},...patch});
const v2 = (id,status='active') => ({id,livemode:false,configuration:{recipient:{capabilities:{stripe_balance:{stripe_transfers:{status}}}}}});
test('sandbox discovery paginates and uses v2 readiness without requiring a nonexistent v1 capability',async()=>{
 const reads=[];
 const result=await findSupportSandboxRecipient(async path=>{
  reads.push(path);
  return path.includes('starting_after')?{data:[account('acct_ready')],has_more:false}:
   {data:[account('acct_incomplete',{details_submitted:false})],has_more:true};
 },async(path,version)=>{assert.match(version,/^\d{4}-\d{2}-\d{2}\./);assert.match(path,/include\[0\]=configuration.recipient/);return v2('acct_ready');});
 assert.equal(result.recipient.id,'acct_ready');assert.equal(result.counts.examined,2);assert.equal(reads.length,2);
});
test('inactive, incomplete, nonmanual and unpaid-out recipients are not silently approved',async()=>{
 const result=await findSupportSandboxRecipient(async()=>({data:[
  account('acct_a',{details_submitted:false}),account('acct_b',{payouts_enabled:false}),
  account('acct_c',{settings:{payouts:{schedule:{interval:'daily'}}}}),
  account('acct_d',{requirements:{currently_due:['identity']}}),account('acct_e')],has_more:false}),
  async()=>v2('acct_e','restricted'));
 assert.equal(result.recipient,null);assert.equal(result.counts.ready,0);assert.equal(result.counts.transfersInactive,1);
 assert.ok(!JSON.stringify(result.counts).includes('acct_'));
});
test('provider ambiguity, wrong mode/identity and stalled pagination stop without changing accounts',async()=>{
 await assert.rejects(findSupportSandboxRecipient(async()=>{throw Error('offline');},async()=>{}),/offline/);
 for (const response of [v2('acct_wrong'),{...v2('acct_a'),livemode:true}])
  await assert.rejects(findSupportSandboxRecipient(async()=>({data:[account('acct_a')]}),async()=>response),/mismatch/);
 await assert.rejects(findSupportSandboxRecipient(async()=>({data:[],has_more:true}),async()=>{}),/progress/);
});
