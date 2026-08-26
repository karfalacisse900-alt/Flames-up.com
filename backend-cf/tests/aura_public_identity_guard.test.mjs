import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function read(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

function environmentAssignments(source) {
  return source
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'))
    .map((line) => {
      const match = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(line);
      assert.ok(match, `unexpected example configuration line: ${line}`);
      return [match[1], match[2]];
    });
}

test('public Worker identity and user-facing copy name Aura', async () => {
  const [worker, workflow, readme, packageManifest, packageLock] = await Promise.all([
    read('backend-cf/src/index.ts'),
    read('.github/workflows/deploy-worker.yml'),
    read('backend-cf/README.md'),
    read('backend-cf/package.json'),
    read('backend-cf/package-lock.json'),
  ]);

  assert.match(worker, /const WORKER_NAME = 'aura-api'/);
  assert.match(worker, /name: 'Aura API'/);
  assert.match(worker, /message: 'Aura API'/);
  assert.match(worker, /Aura production database is not configured/);
  assert.match(worker, /Verify your Aura email/);
  assert.match(worker, /Aura safety warning/);
  assert.match(workflow, /^name: Deploy Aura API$/m);
  assert.match(readme, /^# Aura API \(Cloudflare Workers\)$/m);
  assert.equal(JSON.parse(packageManifest).name, 'aura-api');
  assert.equal(JSON.parse(packageLock).name, 'aura-api');
  assert.equal(JSON.parse(packageLock).packages[''].name, 'aura-api');

  const retiredPublicPhrases = [
    'Captro API',
    'removed from Captro',
    'Captro production database',
    'Captro Premium',
    'Verify your Captro email',
    'Captro account email',
    'Flames-Up sign-in code',
    "Captro's safety rules",
    'Captro safety warning',
    'a Captro account',
    'this Captro account',
    'Captro Email Verification',
    'Captro Email Verified',
    'Your Captro email',
    'through Captro',
    'canonical Captro app database',
    'not the Captro source of truth',
    'Captro account creation',
    'Captro bookmarks',
  ];
  for (const phrase of retiredPublicPhrases) {
    assert.equal(worker.includes(phrase), false, `legacy public product copy remains: ${phrase}`);
  }
});

test('approved legacy infrastructure and auth identifiers remain unchanged for compatibility', async () => {
  const [worker, wrangler, workflow, keychain] = await Promise.all([
    read('backend-cf/src/index.ts'),
    read('backend-cf/wrangler.toml'),
    read('.github/workflows/deploy-worker.yml'),
    read('ios_native/MIRA/Sources/MIRANative/Services/MIRAKeychainSessionProvider.swift'),
  ]);

  // These are protocol, persisted-data, auth, routing, or provisioned-resource identifiers.
  // They must be migrated deliberately rather than renamed as display copy.
  assert.match(wrangler, /name = "flames-up-api"/);
  assert.match(wrangler, /database_name = "flames-up"/);
  assert.match(wrangler, /queue = "captro-media-moderation"/);
  assert.match(wrangler, /com\.captro\.app/);
  assert.match(wrangler, /https:\/\/api\.flames-up\.com/);
  assert.match(workflow, /wrangler queues create captro-media-moderation/);
  assert.match(worker, /X-Captro-Device-Trust-Mode/);
  assert.match(worker, /scheme === 'captro:'/);
  assert.match(worker, /captro_supabase_oauth_v1/);
  assert.match(worker, /const AUDIUS_APP_NAME = 'Captro'/);
  assert.match(worker, /return `Captro-\$\{provider\}-/);
  assert.match(worker, /metadata\.captro_user_id/);
  assert.match(worker, /source: 'captro_ios'/);
  assert.match(worker, /captro_wall_overview/);
  assert.match(keychain, /service: String = "com\.captro\.auth"/);
});

test('Worker deploy stamps public Git commit provenance without replacing bindings or secrets', async () => {
  const [worker, workflow] = await Promise.all([
    read('backend-cf/src/index.ts'),
    read('.github/workflows/deploy-worker.yml'),
  ]);

  assert.ok((worker.match(/commit: c\.env\.SOURCE_COMMIT \|\| ''/g) || []).length >= 2);
  assert.match(workflow, /\[\[ ! "\$GITHUB_SHA" =~ \^\[0-9a-fA-F\]\{40\}\$ \]\]/);
  assert.match(workflow, /wrangler deploy --env production --keep-vars --var "SOURCE_COMMIT:\$GITHUB_SHA"/);
  assert.doesNotMatch(workflow, /wrangler secret put SOURCE_COMMIT/);
});

test('tracked Worker example configuration lists names only', async () => {
  const [environmentExample, developmentExample] = await Promise.all([
    read('backend-cf/.env.example'),
    read('backend-cf/.dev.vars.example'),
  ]);
  const environment = environmentAssignments(environmentExample);
  const development = environmentAssignments(developmentExample);

  for (const [name, value] of [...environment, ...development]) {
    assert.equal(value, '', `${name} must not have a value in tracked example configuration`);
  }

  const configuredNames = new Set(environment.map(([name]) => name));
  for (const unrelatedChainName of ['EVM_RPC_URL', 'EVM_CONTRACT_ADDRESS', 'SOLANA_RPC_URL']) {
    assert.equal(configuredNames.has(unrelatedChainName), false, `${unrelatedChainName} is not an Aura runtime setting`);
  }
  for (const requiredName of [
    'SUPABASE_ACCESS_TOKEN',
    'SUPABASE_PROJECT_REF',
    'SUPABASE_SERVICE_ROLE_KEY',
    'CLOUDFLARE_API_TOKEN',
    'VERYFI_CLIENT_ID',
    'VERYFI_CLIENT_SECRET',
    'VERYFI_USERNAME',
    'VERYFI_API_KEY',
    'AURA_PROOF_VERIFIER_PRIVATE_KEY_PKCS8_BASE64',
    'AURA_PROOF_NULLIFIER_KEY_BASE64',
    'AURA_MOBILE_GATEWAY_URLS',
    'AURA_MOBILE_GATEWAY_URL',
    'AURA_MOBILE_GATEWAY_TOKEN',
    'SOURCE_COMMIT',
  ]) {
    assert.ok(configuredNames.has(requiredName), `missing configuration name: ${requiredName}`);
  }
});
