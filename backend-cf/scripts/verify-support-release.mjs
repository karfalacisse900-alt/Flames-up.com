import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {supportTestEnabled} from '../src/creator-support.ts';
// Verified deployed Worker from 39355433534 (deployment succeeded; its old
// custom-domain smoke hit an edge challenge). Never silently overwrite
// a newer deployment or apply the test-only migration to a live ledger.
const baseline='57651a08303195b6e696dd1eff314a284ce928cc';
const expected='22171738-afa0-465c-afc2-33ecb0896e67';
const changed=execFileSync('git',['diff','--name-only',baseline,'HEAD','--','backend-cf/src','backend-cf/wrangler.toml','backend-cf/package.json','backend-cf/package-lock.json'],{encoding:'utf8'}).trim().split('\n').filter(Boolean);
assert.ok(changed.length>0);
assert.deepEqual(changed,[
  'backend-cf/src/creator-earnings.ts',
  'backend-cf/src/creator-support.ts',
  'backend-cf/src/index.ts',
  'backend-cf/src/support-readiness.ts',
], 'Unexpected deployed code/configuration changes');
const {CLOUDFLARE_API_TOKEN:token,CLOUDFLARE_ACCOUNT_ID:account}=process.env;
assert.equal(account,'2ca88b3551321681a5f9434814f38ec8');assert.ok(token);
const api='https://api.cloudflare.com/client/v4/accounts/'+account+'/workers/scripts/flames-up-api';
async function read(path) {
  const r=await fetch(api+path,{headers:{Authorization:'Bearer '+token},signal:AbortSignal.timeout(20000)});
  assert.equal(r.status,200,'Cloudflare read failed');const b=await r.json();assert.equal(b.success,true);return b.result;
}
const versions=(await read('/deployments')).deployments?.[0]?.versions;
assert.deepEqual(versions?.map(v=>({id:v.version_id,percent:v.percentage})),[{id:expected,percent:100}], 'Production baseline changed; review before deploying');
const bindings=(await read('/settings')).bindings;assert.ok(Array.isArray(bindings));
const variables=Object.fromEntries(bindings.filter(b=>b.type==='plain_text').map(b=>[b.name,b.text]));
assert.equal(variables.ENVIRONMENT,'production');assert.equal(variables.STRIPE_MODE,'live');
assert.equal(supportTestEnabled(variables),false);
for(const name of ['CAPTRO_ACCOUNT_CLEANUP_MANIFEST','CAPTRO_PAYMENT_RECOVERY_ACTIONS'])
  assert.ok(!bindings.some(b=>b.name===name&&(b.type!=='plain_text'||b.text!=='blocked')),'Sensitive action gate changed');
console.log(JSON.stringify({productionVersion:expected,sourceBaseline:baseline,changed,liveSupportEnabled:false,migrationsApplied:false,paymentSettingsChanged:false}));
