import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Preparation only: every network request is GET. The exact preceding deployment
// is recorded in run 43652503796. A changed baseline requires a new review.
export const professionalWorkerBaseline = Object.freeze({
  source: '89ca332f6e47954f376aec366845468b8efa48f4',
  version: '0728d43a-5775-49e9-b1db-be4fa903d5b6',
  bindings: '1301827a84a80cfca3d2dca6ee31e08e346a1d2a4125da2e603c849f2a21f33a',
});
export const professionalWorkerFiles = Object.freeze([
  'backend-cf/src/business-ordering.ts', 'backend-cf/src/creator-support.ts',
  'backend-cf/src/feed-pagination.ts', 'backend-cf/src/index.ts',
  'backend-cf/src/professional-accounts.ts', 'backend-cf/src/tea-clubs.ts',
  'backend-cf/src/tea-conversations.ts', 'backend-cf/src/tea.ts',
]);
export function checkProfessionalWorker({ changed, deployment, bindings }) {
  assert.deepEqual(changed, professionalWorkerFiles, 'Worker code/configuration scope changed; review required.');
  assert.equal(deployment?.versions?.length, 1, 'Expected one deployed Worker version.');
  assert.equal(deployment.versions[0].percentage, 100, 'Expected the recorded full deployment.');
  assert.equal(deployment.versions[0].version_id, professionalWorkerBaseline.version, 'Production Worker changed; review required.');
  assert.ok(Array.isArray(bindings), 'Production bindings are unavailable.');
  const fingerprint = createHash('sha256').update(JSON.stringify(bindings.slice().sort((a,b) => a.name.localeCompare(b.name)))).digest('hex');
  assert.equal(fingerprint, professionalWorkerBaseline.bindings, 'Production configuration changed; review required.');
  return { version: professionalWorkerBaseline.version, configurationHash: fingerprint, changed };
}

export async function inspectProfessionalWorker(env = process.env, request = fetch, execute = execFileSync) {
  if (env.CLOUDFLARE_ACCOUNT_ID !== '2ca88b3551321681a5f9434814f38ec8' || !env.CLOUDFLARE_API_TOKEN)
    throw Error('Existing Captro Cloudflare read credentials are required.');
  const changed = execute('git', ['diff', '--name-only', professionalWorkerBaseline.source, 'HEAD', '--',
    'backend-cf/src', 'backend-cf/wrangler.toml', 'backend-cf/package.json', 'backend-cf/package-lock.json'],
    { cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8' }).trim().split('\n');
  // Reject unrelated source/configuration changes before contacting production.
  assert.deepEqual(changed, professionalWorkerFiles, 'Worker code/configuration scope changed; review required.');
  const base = `https://api.cloudflare.com/client/v4/accounts/${env.CLOUDFLARE_ACCOUNT_ID}/workers/scripts/flames-up-api`;
  async function read(path) {
    let response;
    try { response = await request(base + path, { method: 'GET',
      headers: { Authorization: `Bearer ${env.CLOUDFLARE_API_TOKEN}` },
      signal: AbortSignal.timeout(20_000), redirect: 'error' }); }
    catch { throw Error('Production baseline lookup unavailable.'); }
    if (!response.ok) throw Error(`Production baseline lookup HTTP ${response.status}.`);
    let body; try { body = await response.json(); } catch { throw Error('Invalid production baseline response.'); }
    if (body.success !== true) throw Error('Production baseline lookup failed.');
    return body.result;
  }
  const deployment = (await read('/deployments')).deployments?.[0];
  const settings = await read('/settings');
  return checkProfessionalWorker({ changed, deployment, bindings: settings.bindings });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { console.log(JSON.stringify(await inspectProfessionalWorker())); }
  catch (error) {
    // Assertion values could contain configuration. Never dump actual/expected,
    // response bodies, child-process output, tokens or provider exceptions.
    console.error(error instanceof assert.AssertionError ? 'Production source, version or configuration differs from the reviewed baseline.' : error.message);
    process.exitCode = 1;
  }
}
