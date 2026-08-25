import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const sourceURL = new URL('../src/aura.ts', import.meta.url);
const workflowURL = new URL('../../.github/workflows/deploy-worker.yml', import.meta.url);

test('Aura document verification is authenticated, bounded, non-retaining, and only authorizes privacy-safe proof bytes', async () => {
  const source = await fs.readFile(sourceURL, 'utf8');
  assert.match(source, /aura\.use\('\*', authMiddleware\)/);
  assert.match(source, /MAX_DOCUMENT_BYTES = 12 \* 1024 \* 1024/);
  assert.match(source, /auto_delete: true/);
  assert.match(source, /proofIssued: false/);
  assert.match(source, /blockchainSubmitted: false/);
  assert.match(source, /independentPurchaseConfirmed: false/);
  assert.match(source, /veryfiSignature/);
  assert.match(source, /purchaseProofAttestation/);
  assert.match(source, /proof\/purchase\/verifier-signing\/v1/);
  assert.match(source, /aura-receipt-nullifier-v1/);
  assert.match(source, /AURA_PROOF_VERIFIER_PRIVATE_KEY_PKCS8_BASE64/);
  assert.match(source, /AURA_PROOF_NULLIFIER_KEY_BASE64/);
  assert.doesNotMatch(source, /a5eef8|0FBr1|vrfsgsvt/);
});

test('Aura wallet routes proxy only allowlisted operations to an authenticated Rust gateway', async () => {
  const source = await fs.readFile(sourceURL, 'utf8');
  assert.match(source, /ALLOWED_GATEWAY_PATH/);
  assert.match(source, /authorization: `Bearer \$\{token\}`/);
  assert.match(source, /X-Aura-Request-Timestamp/);
  assert.match(source, /AURA_GATEWAY_UNAVAILABLE/);
  assert.match(source, /\/transactions\/broadcast/);
  assert.match(source, /\/proofs\/broadcast/);
  assert.match(source, /feedback-eligibility/);
  assert.match(source, /MAX_GATEWAY_ORIGINS = 3/);
  assert.match(source, /AURA_MOBILE_GATEWAY_URLS/);
  assert.match(source, /gatewayHasExpectedIdentity/);
  assert.match(source, /matchesExpectedAuraNetwork/);
  assert.match(source, /for \(const base of bases\)/);
  assert.match(source, /if \(response\.status >= 500\) continue/);
  assert.match(source, /ALLOWED_GATEWAY_EVENT_PATH/);
  assert.match(source, /text\/event-stream/);
  assert.match(source, /aura_gateway_events/);
  assert.match(source, /new Response\(response\.body/);
});

test('deployment syncs credential names from GitHub Actions without source values', async () => {
  const workflow = await fs.readFile(workflowURL, 'utf8');
  for (const name of ['VERYFI_CLIENT_ID', 'VERYFI_CLIENT_SECRET', 'VERYFI_USERNAME', 'VERYFI_API_KEY']) {
    assert.match(workflow, new RegExp(`secrets\\.${name}`));
  }
  assert.match(workflow, /secrets\.AURA_MOBILE_GATEWAY_URLS/);
  assert.match(workflow, /secrets\.AURA_PROOF_VERIFIER_PRIVATE_KEY_PKCS8_BASE64/);
  assert.match(workflow, /secrets\.AURA_PROOF_NULLIFIER_KEY_BASE64/);
  assert.doesNotMatch(workflow, /a5eef8|0FBr1|vrfsgsvt/);
});
