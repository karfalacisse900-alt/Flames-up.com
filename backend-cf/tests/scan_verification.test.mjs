import assert from 'node:assert/strict';
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

test('consumer verdict vocabulary excludes accusation and score labels', async () => {
  const source = await readFile(path.join(repositoryRoot, 'backend-cf', 'src', 'scan.ts'), 'utf8');
  assert.match(source, /verdict: row\.status === 'verified' \? 'Verified' : row\.status === 'couldnt_verify' \? "Couldn't Verify"/);
  assert.doesNotMatch(source, /verdict:\s*['"](?:Fraud|Fake|Scam|Suspicious|Level 1|Level 2)/i);
  assert.match(source, /https:\/\/api\.storekit\.apple\.com/);
  assert.match(source, /https:\/\/api\.storekit-sandbox\.apple\.com/);
});

test('iOS Scan replaces Discover and preserves the paid-review contract', async () => {
  const root = await readFile(path.join(repositoryRoot, 'ios_native', 'MIRA', 'Sources', 'MIRANative', 'App', 'MIRANativeRootView.swift'), 'utf8');
  const screen = await readFile(path.join(repositoryRoot, 'ios_native', 'MIRA', 'Sources', 'MIRANative', 'Screens', 'CaptroScanView.swift'), 'utf8');
  const purchase = await readFile(path.join(repositoryRoot, 'ios_native', 'MIRA', 'Sources', 'MIRANative', 'Services', 'CaptroScanPurchaseService.swift'), 'utf8');
  const models = await readFile(path.join(repositoryRoot, 'ios_native', 'MIRA', 'Sources', 'MIRANative', 'Services', 'CaptroScanModels.swift'), 'utf8');
  const scanSources = `${screen}\n${purchase}\n${models}`;

  assert.match(root, /lazyTab\(\.scan\)/);
  assert.match(root, /Label\("Scan", systemImage: "doc\.viewfinder\.fill"\)/);
  assert.doesNotMatch(root, /lazyTab\(\.discover\)/);
  assert.match(screen, /Label\("Scan Document", systemImage: "doc\.viewfinder"\)/);
  assert.match(screen, /Label\("Photos", systemImage: "photo\.on\.rectangle"\)/);
  assert.match(screen, /Label\("Import", systemImage: "square\.and\.arrow\.down"\)/);
  assert.match(screen, /Verification/);
  assert.match(screen, /Verify for \$0\.10/);
  assert.match(screen, /idempotencyKey = "scan:\\?\(document\.sha256Hex\):\\?\(UUID\(\)\.uuidString\)"/);
  assert.match(purchase, /com\.captro\.scan\.credits\.10/);
  assert.match(purchase, /Transaction\.unfinished/);
  assert.doesNotMatch(scanSources, /Aura/);
  assert.doesNotMatch(screen, /\b(?:Fraud|Fake|Scam|Suspicious|Level 1|Level 2|risk percentage)\b/i);
});

test('App Store setup uses the dedicated in-app purchase availability resource', async () => {
  const setup = await readFile(path.join(repositoryRoot, 'scripts', 'app-store', 'ensure-scan-iap.mjs'), 'utf8');

  assert.doesNotMatch(setup, /availableInAllTerritories/);
  assert.match(setup, /\/v1\/inAppPurchaseAvailabilities/);
  assert.match(setup, /availableInNewTerritories: true/);
  assert.match(setup, /\/v1\/territories\?limit=200/);
});
