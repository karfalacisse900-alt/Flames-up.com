import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath, pathToFileURL} from 'node:url';
// Verified rollout 44000943388. This release adds Notes and the reviewed Home/Tea
// content boundary. Existing commerce, permissions, variables and secrets stay intact.
export const baseline='e6629e92bb18a31f164b6db1682ea037b46011be';
export const precedingVersion='0cef467c-ce2b-4e08-9cac-54bf9132bf34';
export const teaRepairFiles=['backend-cf/src/feed-pagination.ts','backend-cf/src/home-posts.ts','backend-cf/src/index.ts','backend-cf/src/tea-conversations.ts','backend-cf/src/tea.ts'];
export function verifyTeaSource({changed,version,annotations,after=false,candidate,expectedVersion}) {
  assert.deepEqual(changed,teaRepairFiles,'Tea deployment scope changed.');
  if(after) {
    assert.match(candidate??'',/^[a-f0-9]{40}$/,'Missing candidate source.');
    assert.equal(annotations?.['workers/message'],'Tea Conversations '+candidate,'Deployed source does not match candidate.');
  } else {
    assert.equal(version,precedingVersion,'Production changed since inspection.');
    assert.equal(annotations?.['workers/message'],'Tea Conversations '+baseline,'Unexpected preceding source.');
    if(expectedVersion) assert.equal(version,expectedVersion,'Production changed after inspection.');
  }
}
async function main() {
const changed=execFileSync('git',['diff','--name-only',baseline,'HEAD','--','backend-cf/src','backend-cf/wrangler.toml','backend-cf/package.json','backend-cf/package-lock.json'],{encoding:'utf8',cwd:fileURLToPath(new URL('../../',import.meta.url))}).trim().split('\n');
assert.deepEqual(changed,teaRepairFiles,'Tea deployment scope changed.');
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
assert.equal(configurationHash,'1301827a84a80cfca3d2dca6ee31e08e346a1d2a4125da2e603c849f2a21f33a','Production bindings changed after inspection');
if(process.env.DEPLOY==='true') {
  assert.match(process.env.EXPECTED_VERSION??'',/^[a-f0-9-]{36}$/);
  assert.equal(version,process.env.EXPECTED_VERSION,'Production changed after inspection.');
}
verifyTeaSource({changed,version,annotations:metadata.annotations,after:process.argv.includes('--after'),
  candidate:process.env.GITHUB_SHA,expectedVersion:process.env.DEPLOY==='true'?process.env.EXPECTED_VERSION:undefined});
console.log(JSON.stringify({version,created:metadata.metadata?.created_on,annotations:metadata.annotations,configurationHash,changed}));
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  main().catch(error=>{console.error(error.message);process.exitCode=1;});
}
