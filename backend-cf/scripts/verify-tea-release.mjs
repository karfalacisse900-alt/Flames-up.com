import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {supportModeEnabled} from '../src/creator-support.ts';

const baseline = '0395767084a3642d764ecd5d9479c0b502ea108b';
const productionVersion = '66658b31-1fb8-4423-94fd-cd44bc5f7192';
const changed = execFileSync('git', ['diff', '--name-only', baseline, 'HEAD', '--',
  'backend-cf/src', 'backend-cf/wrangler.toml', 'backend-cf/package.json', 'backend-cf/package-lock.json',
], {cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8'}).trim().split('\n');
assert.deepEqual(changed, [
  'backend-cf/src/feed-pagination.ts',
  'backend-cf/src/index.ts',
  'backend-cf/src/tea.ts',
], 'Unexpected changes in deployed Worker code or configuration');

const {CLOUDFLARE_API_TOKEN: token, CLOUDFLARE_ACCOUNT_ID: account} = process.env;
assert.equal(account, '2ca88b3551321681a5f9434814f38ec8');
assert.ok(token);
const endpoint = 'https://api.cloudflare.com/client/v4/accounts/' + account + '/workers/scripts/flames-up-api';

async function read(path) {
  const response = await fetch(endpoint + path, {
    headers: {Authorization: 'Bearer ' + token},
    signal: AbortSignal.timeout(20000),
  });
  assert.equal(response.status, 200, 'Cloudflare read failed for ' + path);
  const body = await response.json();
  assert.equal(body.success, true);
  return body.result;
}

const expectedVersion = process.argv[2] || productionVersion;
const versions = (await read('/deployments')).deployments?.[0]?.versions;
assert.deepEqual(versions?.map(({version_id, percentage}) => ({version_id, percentage})),
  [{version_id: expectedVersion, percentage: 100}], 'Production version changed');
const {bindings} = await read('/settings');
assert.ok(Array.isArray(bindings));
const vars = Object.fromEntries(bindings.filter(binding => binding.type === 'plain_text')
  .map(binding => [binding.name, binding.text]));
assert.equal(vars.ENVIRONMENT, 'production');
assert.equal(vars.STRIPE_MODE, 'live');
assert.equal(supportModeEnabled(vars), false, 'Support payment mode changed');
for (const name of ['CAPTRO_ACCOUNT_CLEANUP_MANIFEST', 'CAPTRO_PAYMENT_RECOVERY_ACTIONS']) {
  assert.ok(!bindings.some(binding =>
    binding.name === name && (binding.type !== 'plain_text' || binding.text !== 'blocked')), 'Sensitive action gate changed');
}
const backupBindings = bindings.filter(binding => ['MEDIA_BACKUP', 'VOICE_RECORDINGS'].includes(binding.name));
assert.equal(backupBindings.length, 2, 'Production is missing its media backup bindings');
assert.ok(backupBindings.every(binding => binding.type === 'r2_bucket' && binding.bucket_name === 'flames-up-media-backup'),
  'Production media bucket bindings differ from the version configuration');
if (process.argv.length === 2) {
  const bucketResponse = await fetch('https://api.cloudflare.com/client/v4/accounts/' + account +
    '/r2/buckets/flames-up-media-backup', {
    headers: {Authorization: 'Bearer ' + token},
    signal: AbortSignal.timeout(20000),
  });
  const bucket = await bucketResponse.json();
  console.log(JSON.stringify({r2BucketRead: bucketResponse.status, exists: bucket.success === true,
    cloudflareErrorCodes: (bucket.errors ?? []).map(error => error.code)}));
}
console.log('Verified Worker version ' + expectedVersion + ' and existing release flags.');