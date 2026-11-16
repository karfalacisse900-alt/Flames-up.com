import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { professionalWorkerBaseline, professionalWorkerFiles, checkProfessionalWorker, inspectProfessionalWorker } from '../scripts/verify-professional-worker.mjs';
const deployment = { versions: [{ version_id: professionalWorkerBaseline.version, percentage: 100 }] };
test('Worker preparation refuses unrelated files, changed deployment and financial configuration', () => {
  const state = { changed: professionalWorkerFiles, deployment, bindings: [] };
  assert.throws(() => checkProfessionalWorker({...state,changed:[...professionalWorkerFiles,'backend-cf/wrangler.toml']}), /scope changed/);
  assert.throws(() => checkProfessionalWorker({...state,deployment:{versions:[{version_id:'different',percentage:100}]}}), /Worker changed/);
  assert.throws(() => checkProfessionalWorker({...state,deployment:{versions:[{version_id:professionalWorkerBaseline.version,percentage:50}]}}), /full deployment/);
  assert.throws(() => checkProfessionalWorker({...state,bindings:[{name:'STRIPE_MODE',type:'plain_text',text:'test'}]}), /configuration changed/);
});
test('post-deployment inspection rejects a version without the exact candidate provenance', async () => {
  const env={CLOUDFLARE_ACCOUNT_ID:'2ca88b3551321681a5f9434814f38ec8',CLOUDFLARE_API_TOKEN:'fixture',GITHUB_SHA:'a'.repeat(40)};
  await assert.rejects(inspectProfessionalWorker(env, async url => Response.json({success:true,result:
    url.endsWith('/deployments')?{deployments:[deployment]}:{annotations:{'workers/message':'unrelated deployment'}}}),
    ()=>professionalWorkerFiles.join('\n'),true), /reviewed candidate source/);
});
test('professional inspect cannot dispatch any of the existing mutation jobs', () => {
  const source=readFileSync(new URL('../../.github/workflows/deploy-worker.yml',import.meta.url),'utf8');
  const jobs=source.split(/\n(?=  \S)/).map(s=>s.trimStart());
  for(const name of ['tea','branding-support','scoped-profile','payment-diagnostics','deploy-reliability','deploy','configure-platform-retention','checkout-readiness']){
    const job=jobs.find(j=>j.startsWith(name+':'));
    assert.ok(job,name); assert.match(job,/inputs\.professional_release_stage == '' \|\| inputs\.professional_release_stage == 'none'/);
  }
});
test('Worker inspection only reads metadata with bounded requests and never logs provider errors', async () => {
  const env = { CLOUDFLARE_ACCOUNT_ID:'2ca88b3551321681a5f9434814f38ec8', CLOUDFLARE_API_TOKEN:'fixture' };
  const execute = () => professionalWorkerFiles.join('\n');
  const paths = [];
  await assert.rejects(inspectProfessionalWorker(env, async (url, options) => {
    assert.equal(options.method,'GET'); assert.equal(options.redirect,'error'); assert.ok(options.signal);
    paths.push(new URL(url).pathname.split('/').pop());
    return Response.json({success:true,result:url.endsWith('/deployments')?{deployments:[deployment]}:{bindings:[]}});
  }, execute), /configuration changed/);
  assert.deepEqual(paths,['deployments','settings']);
  await assert.rejects(inspectProfessionalWorker(env,async () => {throw Error('PRIVATE PROVIDER DATA');},execute), /lookup unavailable/);
  await assert.rejects(inspectProfessionalWorker(env,async () => new Response('PRIVATE PROVIDER DATA',{status:403}),execute), /HTTP 403/);
});
