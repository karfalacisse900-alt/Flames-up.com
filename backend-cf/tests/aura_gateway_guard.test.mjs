import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const sourceURL = new URL('../src/aura.ts', import.meta.url);
const workflowURL = new URL('../../.github/workflows/deploy-worker.yml', import.meta.url);
const scanViewURL = new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/Aura/AuraScanView.swift', import.meta.url);
const walletViewURL = new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/Aura/AuraWalletView.swift', import.meta.url);
const meViewURL = new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/Aura/AuraMeView.swift', import.meta.url);
const rootViewURL = new URL('../../ios_native/MIRA/Sources/MIRANative/App/MIRANativeRootView.swift', import.meta.url);
const ticketViewURL = new URL('../../ios_native/MIRA/Sources/MIRANative/Components/AuraMobileComponents.swift', import.meta.url);
const themeURL = new URL('../../ios_native/MIRA/Sources/MIRANative/Design/MIRATheme.swift', import.meta.url);

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
  assert.match(source, /const receiptHasRequiredFields = Boolean\(merchantName && documentDate && documentTotal\)/);
  assert.match(source, /const invoiceHasRequiredFields = Boolean/);
  assert.match(source, /isDocument !== false/);
  assert.match(source, /!blockingDecision/);
  assert.match(source, /Receipt Verified/);
  assert.match(source, /Receipt Could Not Be Verified/);
  assert.match(source, /AURA_PROOF_VERIFIER_PRIVATE_KEY_PKCS8_BASE64/);
  assert.match(source, /AURA_PROOF_NULLIFIER_KEY_BASE64/);
  assert.doesNotMatch(source, /a5eef8|0FBr1|vrfsgsvt/);
});

test('Aura Mobile shell has exactly Home, Scan, Wallet, and Me with real-data ticket cards', async () => {
  const [root, ticket] = await Promise.all([
    fs.readFile(rootViewURL, 'utf8'),
    fs.readFile(ticketViewURL, 'utf8'),
  ]);
  const tabEnum = root.slice(root.indexOf('public enum MIRATab'), root.indexOf('public enum MIRAStartupPhase'));
  assert.match(tabEnum, /case home/);
  assert.match(tabEnum, /case scan/);
  assert.match(tabEnum, /case wallet/);
  assert.match(tabEnum, /case me/);
  assert.doesNotMatch(tabEnum, /proofs|reputation|yearbook/);
  assert.match(root, /AuraHomeView\(/);
  assert.match(root, /AuraScanView\(/);
  assert.match(root, /AuraWalletView\(/);
  assert.match(root, /AuraMeView\(/);
  assert.match(root, /gateway: auraGateway/);
  assert.match(ticket, /merchant: String\?/);
  assert.match(ticket, /status: String/);
  assert.doesNotMatch(`${root}\n${ticket}`, /1,248\.50|BLANK STREET|\$8\.42/);
});

test('Aura Mobile auto-recognizes document type and keeps capture alive across system pickers', async () => {
  const [scanView, walletView] = await Promise.all([
    fs.readFile(scanViewURL, 'utf8'),
    fs.readFile(walletViewURL, 'utf8'),
  ]);
  assert.match(scanView, /if phase == \.background/);
  assert.match(walletView, /if phase == \.background, wallet\.state == \.unlocked/);
  assert.match(scanView, /Automatic recognition/);
  assert.match(scanView, /Aura automatically recognizes receipts and invoices\./);
  assert.match(scanView, /Verify Document/);
  assert.doesNotMatch(scanView, /Scan Receipt/);
  assert.doesNotMatch(scanView, /Scan Invoice/);
  assert.doesNotMatch(scanView, /Import Receipt/);
  assert.doesNotMatch(scanView, /Import Invoice/);
  assert.match(scanView, /result\.submittedType == "receipt"/);
  assert.match(scanView, /result\.submittedType == "invoice"/);
  assert.equal(scanView.includes('Text("Level \\(result.verificationLevel)")'), false);
  assert.doesNotMatch(scanView, /Provider fraud decision/);
  assert.doesNotMatch(scanView, /AI-generated document detected/);
  assert.doesNotMatch(scanView, /Veryfi|Raw document bytes|provider recognized/);

  const source = await fs.readFile(sourceURL, 'utf8');
  assert.match(source, /document_type: null/);
  assert.match(source, /function auraDocumentKind/);
  assert.match(source, /normalized\.submittedType === 'receipt'/);
});

test('Aura Mobile uses warm neutral chrome, restrained color, and physical cards', async () => {
  const [theme, scanView, walletView, meView, ticketView] = await Promise.all([
    fs.readFile(themeURL, 'utf8'),
    fs.readFile(scanViewURL, 'utf8'),
    fs.readFile(walletViewURL, 'utf8'),
    fs.readFile(meViewURL, 'utf8'),
    fs.readFile(ticketViewURL, 'utf8'),
  ]);

  assert.match(theme, /appBackground = adaptive\([\s\S]*?light: UIColor\(red: 0\.961, green: 0\.957, blue: 0\.945/);
  assert.match(theme, /auraViolet = adaptive\([\s\S]*?light: UIColor\(red: 0\.369, green: 0\.247, blue: 0\.847/);
  assert.doesNotMatch(scanView, /LinearGradient/);
  assert.doesNotMatch(walletView, /LinearGradient/);
  assert.match(scanView, /physicalAuraCard/);
  assert.match(walletView, /physicalAuraCard/);
  assert.match(meView, /physicalAuraCard/);
  assert.match(ticketView, /physicalAuraCard/);
  assert.match(scanView, /Creating Aura proof/);
  assert.match(scanView, /Aura proof ready/);
  assert.doesNotMatch(scanView, /Block #|confirmations/);
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
