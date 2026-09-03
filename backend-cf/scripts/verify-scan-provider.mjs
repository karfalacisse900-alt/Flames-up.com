import assert from 'node:assert/strict';
import { captroScanTestSupport as scan } from '../src/scan.ts';

const env = { ...process.env, SUPABASE_URL: `https://${process.env.SUPABASE_PROJECT_REF}.supabase.co` };
await scan.ensurePrivateReceiptBucket(env);
console.log('Private receipt bucket exists and is not public.');

// Public fixture maintained by Veryfi. This is a provider test, never a rewarded submission.
const source = 'https://raw.githubusercontent.com/veryfi/veryfi-python/master/tests/assets/receipt_public.jpg';
const response = await fetch(source, { signal: AbortSignal.timeout(20_000) });
assert.equal(response.status, 200, 'Veryfi public receipt fixture could not be loaded');
const bytes = new Uint8Array(await response.arrayBuffer());
const result = await scan.providerVerify(env, bytes, 'provider-smoke.jpg', `captro-provider-smoke:${crypto.randomUUID()}`);
const extracted = scan.normalizeProviderDocument(result);
console.log(JSON.stringify({ event: 'veryfi_response_shape', merchantField: typeof result.vendor?.name,
  totalField: typeof result.total, merchantPresent: !!extracted.business.name, totalPresent: !!extracted.total }));
assert.ok(extracted.providerRequestId, 'Provider document ID is missing');
assert.equal(extracted.type, 'receipt');
assert.ok(extracted.business.name, 'Merchant extraction failed');
assert.ok(extracted.total, 'Total extraction failed');
console.log(JSON.stringify({ event: 'veryfi_risk_response',
  color: ['green', 'yellow', 'red'].includes(extracted.signals.color) ? extracted.signals.color : 'not_returned',
  decisionPresent: Boolean(extracted.signals.decision), score: extracted.signals.score,
  digitalTampering: extracted.signals.digitalTampering, aiGenerated: extracted.signals.aiGenerated,
  screenPhoto: extracted.signals.screenPhoto, fraudulentPdf: extracted.signals.fraudulentPdf,
  otherIndicators: extracted.signals.otherIndicators,
  feedbackEligible: scan.receiptAcceptedForFeedback(extracted) }));
console.log(JSON.stringify({ event: 'veryfi_live_smoke_passed', providerDocumentId: extracted.providerRequestId,
  documentType: extracted.type, merchantPresent: !!extracted.business.name, totalPresent: !!extracted.total,
  checks: scan.buildChecks(extracted).map(({ key, status }) => ({ key, status })),
  rewardIssued: false }));
