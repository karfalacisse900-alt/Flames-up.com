import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const baseline='0afe32adc0ad6e6fde6ae1271fac655b55d22919';
const changed=execFileSync('git',['diff','--name-only',baseline,'HEAD','--','backend-cf/src','backend-cf/wrangler.toml','backend-cf/package.json','backend-cf/package-lock.json'],{encoding:'utf8'}).trim().split('\n');
assert.deepEqual(changed,['backend-cf/src/index.ts','backend-cf/src/tea-conversations.ts']);
const {CLOUDFLARE_API_TOKEN:token,CLOUDFLARE_ACCOUNT_ID:account}=process.env;
assert.equal(account,'2ca88b3551321681a5f9434814f38ec8');assert.ok(token);
const base=`https://api.cloudflare.com/client/v4/accounts/${account}/workers/scripts/flames-up-api`;
async function read(path) {
  const r=await fetch(base+path,{headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(20000)});
  assert.equal(r.status,200,'Cloudflare baseline read failed');const b=await r.json();assert.equal(b.success,true);return b.result;
}
const deployment=(await read('/deployments')).deployments?.[0];
assert.equal(deployment?.versions?.length,1);assert.equal(deployment.versions[0].percentage,100);
const version=deployment.versions[0].version_id;
const metadata=await read('/versions/'+version);
const settings=await read('/settings');
const bindings=settings.bindings;
assert.ok(Array.isArray(bindings));
assert.ok(bindings.some(b=>b.name==='ENVIRONMENT'&&b.text==='production'));
const configurationHash=createHash('sha256').update(JSON.stringify(bindings.slice().sort((a,b)=>a.name.localeCompare(b.name)))).digest('hex');
console.log(JSON.stringify({version,created:metadata.metadata?.created_on,annotations:metadata.annotations,configurationHash,changed}));
if(process.env.DEPLOY==='true') {
  assert.match(process.env.EXPECTED_VERSION??'',/^[a-f0-9-]{36}$/);
  assert.equal(version,process.env.EXPECTED_VERSION,'Production changed after inspection.');
}
