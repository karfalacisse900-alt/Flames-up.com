import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');
const scanPath = path.join(
  repoRoot,
  'ios_native/MIRA/Sources/MIRANative/Screens/Aura/AuraScanView.swift',
);

test('Aura Scan uses real document previews and preserves every capture path', async () => {
  const scan = await readFile(scanPath, 'utf8');

  assert.match(scan, /private var cameraPreviewStage/);
  assert.match(scan, /private func actualDocumentPreview/);
  assert.match(scan, /Image\(uiImage: image\)/);
  assert.match(scan, /PDFDocument\(data: data\)\?\.page\(at: 0\)/);
  assert.match(scan, /AuraDocumentScannerView/);
  assert.match(scan, /PhotosPicker/);
  assert.match(scan, /\.fileImporter\(/);
  assert.match(scan, /api\.verifyAuraDocument\(/);
});

test('Aura Scan keeps consumer copy and a compact tactile visual system', async () => {
  const scan = await readFile(scanPath, 'utf8');

  assert.match(scan, /Aura automatically recognizes receipts and invoices\./);
  assert.match(scan, /Label\("Scan Document"/);
  assert.match(scan, /Label\("Photos"/);
  assert.match(scan, /Label\("Import"/);
  assert.match(scan, /MIRATheme\.Color\.paperCanvas\.ignoresSafeArea\(\)/);
  assert.match(scan, /\.stroke\(MIRATheme\.Color\.inkBorder, lineWidth: 1\.5\)/);
  assert.match(scan, /\.shadow\(color: MIRATheme\.Color\.hardShadow, radius: 0, x: 0, y: 5\)/);
  assert.doesNotMatch(scan, /private var scanStage|RECEIPT \/ INVOICE/);
  assert.doesNotMatch(scan, /LinearGradient|ultraThinMaterial/i);
});

test('Aura Scan result stays truthful and hides provider and chain internals', async () => {
  const scan = await readFile(scanPath, 'utf8');

  assert.match(scan, /merchant: result\.merchant\.name/);
  assert.match(scan, /date: result\.date/);
  assert.match(scan, /total: result\.total/);
  assert.match(scan, /status: result\.documentVerified \? "Verified" : "Could not be verified"/);
  assert.doesNotMatch(scan, /Veryfi|Aura asks|Block #|confirmations|blockchain/i);
});
