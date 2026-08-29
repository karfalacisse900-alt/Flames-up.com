import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { captroScanTestSupport } from '../src/scan.ts';

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, '..', '..');

function providerDocument(overrides = {}) {
  return {
    id: 'provider-document-1',
    document_type: { value: 'receipt' },
    is_document: true,
    vendor: {
      name: 'Example Market',
      address: {
        address_line: '10 Main Street',
        city: 'New York',
        state: 'NY',
        postal_code: '10001',
        country: 'US',
      },
    },
    date: '2026-08-26',
    time: '09:17',
    receipt_number: 'R-100',
    subtotal: 10,
    tax: 0.8,
    total: 10.8,
    currency_code: 'USD',
    line_items: [{ description: 'Item', quantity: 1, price: 10, total: 10 }],
    fraud: {
      decision: 'green',
      digital_tampering: false,
      ai_generated: false,
      screenshot: false,
      invalid_qr_data: false,
      vendor_layout_mismatch: false,
      not_a_document: false,
    },
    ...overrides,
  };
}

test('recognition alone never becomes Verified', () => {
  const extracted = captroScanTestSupport.normalizeProviderDocument(providerDocument({ fraud: {} }));
  const checks = captroScanTestSupport.buildChecks(extracted);
  assert.equal(captroScanTestSupport.verdictFromChecks(checks), 'couldnt_verify');
  assert.equal(checks.find((check) => check.key === 'provider_document_signal')?.status, 'unavailable');
});

test('a supported document needs real provider, date, and arithmetic checks', () => {
  const extracted = captroScanTestSupport.normalizeProviderDocument(providerDocument());
  const checks = captroScanTestSupport.buildChecks(extracted);
  assert.equal(captroScanTestSupport.verdictFromChecks(checks), 'verified');
  assert.equal(checks.find((check) => check.key === 'total_arithmetic')?.status, 'passed');
  assert.equal(checks.find((check) => check.key === 'line_item_arithmetic')?.status, 'passed');
});

test('failed arithmetic prevents a Verified verdict', () => {
  const extracted = captroScanTestSupport.normalizeProviderDocument(providerDocument({ total: 19.99 }));
  const checks = captroScanTestSupport.buildChecks(extracted);
  assert.equal(captroScanTestSupport.verdictFromChecks(checks), 'couldnt_verify');
  assert.equal(checks.find((check) => check.key === 'total_arithmetic')?.status, 'failed');
});

test('receipt feedback eligibility requires consistent core purchase data', () => {
  const accepted = captroScanTestSupport.normalizeProviderDocument(providerDocument());
  const missingMerchant = captroScanTestSupport.normalizeProviderDocument(providerDocument({ vendor: {} }));

  assert.equal(captroScanTestSupport.receiptAcceptedForFeedback(accepted), true);
  assert.equal(captroScanTestSupport.receiptAcceptedForFeedback(missingMerchant), false);
});

test('purchase category drives the expected feedback questions', () => {
  const restaurant = providerDocument({ vendor: { name: 'Neighborhood Cafe', category: 'Restaurant' } });
  const extracted = captroScanTestSupport.normalizeProviderDocument(restaurant);
  const category = captroScanTestSupport.purchaseCategory(restaurant, extracted);

  assert.equal(category, 'restaurant_food');
  assert.deepEqual(captroScanTestSupport.categoryQuestionKeys[category], [
    'quality', 'cleanliness', 'speed', 'service', 'value', 'overall',
  ]);
});

test('Veryfi request signatures use the documented serialized payload and base64 HMAC', async () => {
  const payload = {
    file_name: 'receipt.jpg',
    external_id: 'scan-1',
    document_type: null,
    boost_mode: false,
    allowed_async_enrichments: [],
  };
  const timestamp = 1787979600000;
  const serialized = 'timestamp:1787979600000,file_name:"receipt.jpg",external_id:"scan-1",document_type:null,boost_mode:false,allowed_async_enrichments:[]';
  assert.equal(captroScanTestSupport.veryfiSignaturePayload(payload, timestamp), serialized);
  assert.equal(
    await captroScanTestSupport.veryfiSignature('test-secret', payload, timestamp),
    createHmac('sha256', 'test-secret').update(serialized).digest('base64'),
  );
});

test('receipt and invoice rewards are server-configurable with guarded defaults', () => {
  assert.equal(captroScanTestSupport.configuredRewardCents({}, 'receipt'), 10);
  assert.equal(captroScanTestSupport.configuredRewardCents({ RECEIPT_REWARD_CENTS: '15' }, 'receipt'), 15);
  assert.equal(captroScanTestSupport.configuredRewardCents({ INVOICE_REWARD_CENTS: '25' }, 'invoice'), 25);
  assert.throws(
    () => captroScanTestSupport.configuredRewardCents({ RECEIPT_REWARD_CENTS: '0' }, 'receipt'),
    /SCAN_REWARD_CONFIGURATION_INVALID/,
  );
});

test('semantic reward fingerprint survives a different photograph of the same receipt', async () => {
  const first = captroScanTestSupport.normalizeProviderDocument(providerDocument());
  const second = captroScanTestSupport.normalizeProviderDocument(providerDocument({ id: 'another-provider-request' }));
  const differentTotal = captroScanTestSupport.normalizeProviderDocument(providerDocument({ total: 12.8, subtotal: 12 }));

  assert.equal(await captroScanTestSupport.receiptRewardFingerprint(first), await captroScanTestSupport.receiptRewardFingerprint(second));
  assert.notEqual(await captroScanTestSupport.receiptRewardFingerprint(first), await captroScanTestSupport.receiptRewardFingerprint(differentTotal));
});

test('migration locks billing to ten cents and makes retries idempotent', async () => {
  const migrationDirectory = path.join(repositoryRoot, 'supabase', 'migrations');
  const files = await import('node:fs/promises').then(({ readdir }) => readdir(migrationDirectory));
  const migrationName = files.find((name) => name.endsWith('_captro_scan_verification.sql'));
  assert.ok(migrationName);
  const migration = await readFile(path.join(migrationDirectory, migrationName), 'utf8');

  assert.match(migration, /price_cents integer not null default 10 check \(price_cents = 10\)/);
  assert.match(migration, /unique \(user_id, idempotency_key\)/);
  assert.match(migration, /idempotency_key text not null unique/);
  assert.match(migration, /captro_begin_scan_verification/);
  assert.match(migration, /captro_restore_scan_credit/);
  assert.match(migration, /revoke all on public\.scan_verifications from anon, authenticated/);
});

test('receipt reward migration is private, atomic, and exactly ten cents', async () => {
  const migrationDirectory = path.join(repositoryRoot, 'supabase', 'migrations');
  const files = await import('node:fs/promises').then(({ readdir }) => readdir(migrationDirectory));
  const migrationName = files.find((name) => name.endsWith('_captro_receipt_feedback_rewards.sql'));
  assert.ok(migrationName);
  const migration = await readFile(path.join(migrationDirectory, migrationName), 'utf8');

  assert.match(migration, /create table if not exists public\.scanned_receipts/);
  assert.match(migration, /create table if not exists public\.receipt_feedback/);
  assert.match(migration, /create table if not exists public\.receipt_rewards/);
  assert.match(migration, /create table if not exists public\.user_reward_balance/);
  assert.match(migration, /create table if not exists public\.receipt_withdrawal_requests/);
  assert.match(migration, /amount_cents integer not null default 10 check \(amount_cents = 10\)/);
  assert.match(migration, /unique \(user_id, document_sha256\)/);
  assert.match(migration, /scanned_receipts_reward_fingerprint_uidx/);
  assert.match(migration, /receipt_id uuid not null unique/);
  assert.match(migration, /captro_claim_receipt_reward_fingerprint/);
  assert.match(migration, /captro_submit_receipt_feedback_reward/);
  assert.match(migration, /security definer\s+set search_path = ''/);
  assert.match(migration, /available_balance_cents = available_balance_cents \+ 10/);
  assert.match(migration, /revoke all on public\.receipt_rewards from anon, authenticated/);
  assert.match(migration, /from public, anon, authenticated/);
});

test('corrected receipt migration stores configured rewards and provider-owned verification state', async () => {
  const migration = await readFile(
    path.join(repositoryRoot, 'supabase', 'migrations', '20260829033952_correct_captro_scan_provider_rewards.sql'),
    'utf8',
  );

  assert.match(migration, /reward_amount_cents integer not null default 10/);
  assert.match(migration, /verification_status text not null default 'pending'/);
  assert.match(migration, /v_receipt\.reward_amount_cents/);
  assert.match(migration, /available_balance_cents = available_balance_cents \+ v_amount/);
  assert.match(migration, /status in \('pending', 'available', 'reversed', 'withdrawn'\)/);
  assert.match(migration, /from public, anon, authenticated/);
  assert.doesNotMatch(migration, /amount_cents = 10/);
});

test('consumer verdict vocabulary excludes accusation and score labels', async () => {
  const source = await readFile(path.join(repositoryRoot, 'backend-cf', 'src', 'scan.ts'), 'utf8');
  assert.match(source, /verdict: row\.status === 'verified' \? 'Verified' : row\.status === 'couldnt_verify' \? "Couldn't Verify"/);
  assert.doesNotMatch(source, /verdict:\s*['"](?:Fraud|Fake|Scam|Suspicious|Level 1|Level 2)/i);
  assert.match(source, /https:\/\/api\.storekit\.apple\.com/);
  assert.match(source, /https:\/\/api\.storekit-sandbox\.apple\.com/);
});

test('iOS Scan uses centered review, adaptive feedback, and a private reward balance', async () => {
  const root = await readFile(path.join(repositoryRoot, 'ios_native', 'MIRA', 'Sources', 'MIRANative', 'App', 'MIRANativeRootView.swift'), 'utf8');
  const screen = await readFile(path.join(repositoryRoot, 'ios_native', 'MIRA', 'Sources', 'MIRANative', 'Screens', 'CaptroScanView.swift'), 'utf8');
  const camera = await readFile(path.join(repositoryRoot, 'ios_native', 'MIRA', 'Sources', 'MIRANative', 'Components', 'CaptroReceiptCameraView.swift'), 'utf8');
  const models = await readFile(path.join(repositoryRoot, 'ios_native', 'MIRA', 'Sources', 'MIRANative', 'Services', 'CaptroScanModels.swift'), 'utf8');
  const profile = await readFile(path.join(repositoryRoot, 'ios_native', 'MIRA', 'Sources', 'MIRANative', 'Screens', 'ProfileChatVerificationStudio.swift'), 'utf8');
  const scanSources = `${screen}\n${camera}\n${models}\n${profile}`;

  assert.match(root, /lazyTab\(\.scan\)/);
  assert.match(root, /Label\("Scan", systemImage: "doc\.viewfinder\.fill"\)/);
  assert.match(root, /CaptroScanView\(api: api\) \{\s*selectedTab = \.main/);
  assert.doesNotMatch(root, /lazyTab\(\.discover\)/);
  assert.match(screen, /CaptroReceiptCameraView\(/);
  assert.match(camera, /AVCaptureSession\(\)/);
  assert.match(camera, /VNDetectRectanglesRequest\(/);
  assert.match(camera, /CIPerspectiveCorrection/);
  assert.match(screen, /cameraImportControl\(systemImage: "photo\.on\.rectangle", label: "Photos"\)/);
  assert.match(screen, /cameraImportControl\(systemImage: "doc", label: "Files"\)/);
  assert.match(screen, /Text\("Review"\)/);
  assert.match(screen, /statusLine\("Processing your document\.\.\."/);
  assert.match(screen, /Text\("Next"\)/);
  assert.match(screen, /Label\("View original"/);
  assert.match(screen, /Text\("Purchase feedback"\)/);
  assert.match(screen, /How clean was the location\?/);
  assert.match(screen, /How fresh were the products\?/);
  assert.match(screen, /How professional was the service\?/);
  assert.match(screen, /Text\(isSubmittingFeedback \? "Submitting" : "Submit"\)/);
  assert.match(screen, /You earned/);
  assert.match(screen, /receipt-review:\\?\(document\.sha256Hex\):\\?\(UUID\(\)\.uuidString\)/);
  assert.match(screen, /api\.reviewCaptroReceipt\(document, idempotencyKey:/);
  assert.doesNotMatch(screen, /detectedType:/);
  assert.match(models, /\/scan\/receipts\/review/);
  assert.match(models, /"source": document\.source\.apiValue/);
  assert.match(models, /\/scan\/receipts\/\\\(receiptId\)\/feedback/);
  assert.match(models, /\/scan\/rewards\/balance/);
  assert.match(models, /\/scan\/receipts\/history/);
  assert.match(models, /\/scan\/receipts\/\\\(id\)\/original/);
  assert.match(profile, /Receipt Earnings/);
  assert.match(profile, /My Receipt Submissions/);
  assert.match(profile, /earningsValue\("Pending", cents: earnings\.pendingRewardCents\)/);
  assert.match(profile, /Label\("Private", systemImage: "lock\.fill"\)/);
  assert.match(profile, /Button\("Withdraw"\)/);
  assert.doesNotMatch(screen, /Verify for \$0\.10/);
  assert.doesNotMatch(scanSources, /Aura/);
});

test('reward API stores raw documents in a private server-side bucket', async () => {
  const source = await readFile(path.join(repositoryRoot, 'backend-cf', 'src', 'scan.ts'), 'utf8');

  assert.match(source, /PRIVATE_RECEIPT_BUCKET = 'captro-private-receipts'/);
  assert.match(source, /public: false/);
  assert.match(source, /\/storage\/v1\/object\/\$\{PRIVATE_RECEIPT_BUCKET\}/);
  assert.match(source, /captro_begin_receipt_review/);
  assert.match(source, /captro_submit_receipt_feedback_reward/);
  assert.match(source, /rewardCents: Math\.max\(0, Number\(row\.reward_amount_cents \|\| 0\)\)/);
  assert.match(source, /withdrawalEnabled: false/);
});

test('App Store setup uses the dedicated in-app purchase availability resource', async () => {
  const setup = await readFile(path.join(repositoryRoot, 'scripts', 'app-store', 'ensure-scan-iap.mjs'), 'utf8');

  assert.doesNotMatch(setup, /availableInAllTerritories/);
  assert.match(setup, /\/v1\/inAppPurchaseAvailabilities/);
  assert.match(setup, /availableInNewTerritories: true/);
  assert.match(setup, /\/v1\/territories\?limit=200/);
});
