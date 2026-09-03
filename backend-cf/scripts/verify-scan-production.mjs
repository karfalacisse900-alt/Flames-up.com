import assert from 'node:assert/strict';

const base = `https://${process.env.SUPABASE_PROJECT_REF}.supabase.co`;
const api = process.env.CAPTRO_SCAN_SMOKE_BASE_URL || 'https://api.flames-up.com/api';
assert.ok(['https://api.flames-up.com/api', 'https://flames-up-api.karfalacisse900.workers.dev/api'].includes(api));
const admin = { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' };
const users = [];
const paths = [];
let receiptId;
const clientHeaders = { Accept: 'application/json', 'User-Agent': 'Captro-Release-Smoke/1.0' };
async function json(url, init = {}) {
  const response = await fetch(url, { ...init, headers: { ...clientHeaders, ...init.headers }, signal: AbortSignal.timeout(120_000) });
  if (url.startsWith(`${api}/scan/`)) assert.match(response.headers.get('cache-control') || '', /private.*no-store/);
  if (!response.headers.get('content-type')?.includes('application/json')) {
    throw new Error(`Live scan check received non-JSON: HTTP ${response.status} at ${new URL(url).pathname}`);
  }
  const body = await response.json();
  if (!response.ok) throw new Error(`Live scan check failed: ${response.status}, ${body.code || body.error_code || 'request rejected'}`);
  return body;
}
async function session() {
  const email = `captro-scan-smoke-${crypto.randomUUID()}@captro.invalid`;
  const password = crypto.randomUUID() + crypto.randomUUID();
  const user = await json(`${base}/auth/v1/admin/users`, { method: 'POST', headers: admin, body: JSON.stringify({ email, password, email_confirm: true }) });
  users.push(user.id);
  const auth = await json(`${base}/auth/v1/token?grant_type=password`, { method: 'POST',
    headers: { apikey: process.env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
  const headers = { ...clientHeaders, Authorization: `Bearer ${auth.access_token}` };
  await json(`${api}/auth/me`, { headers });
  return headers;
}
try {
  const owner = await session();
  const stranger = await session();
  const fixture = await fetch('https://raw.githubusercontent.com/veryfi/veryfi-python/master/tests/assets/receipt_public.jpg');
  assert.equal(fixture.status, 200);
  const bytes = await fixture.arrayBuffer();
  const key = `scan-smoke:${crypto.randomUUID()}`;
  const upload = (headers = owner, idempotencyKey = key) => {
    const body = new FormData();
    body.set('file', new Blob([bytes], { type: 'image/jpeg' }), 'Veryfi public sample.jpg');
    body.set('source', 'files'); body.set('idempotencyKey', idempotencyKey);
    return json(`${api}/scan/receipts/review`, { method: 'POST', headers, body });
  };
  const review = await upload();
  receiptId = review.receiptId;
  assert.ok(review.providerDocumentId, 'No provider document ID');
  assert.ok(review.merchantName && review.total, 'Extracted fields are missing');
  const [record] = await json(`${base}/rest/v1/scanned_receipts?id=eq.${receiptId}&select=id,status,provider_request_id,verification_checks,private_storage_path`, { headers: admin });
  paths.push(record.private_storage_path);
  assert.equal(record.provider_request_id, review.providerDocumentId);
  assert.ok(record.verification_checks.length);
  const persisted = await json(`${api}/scan/receipts/${receiptId}`, { headers: owner });
  assert.equal(persisted.providerDocumentId, review.providerDocumentId);
  const link = await json(`${api}/scan/receipts/${receiptId}/original`, { headers: owner });
  const original = await fetch(link.signedUrl);
  assert.equal(original.status, 200);
  assert.equal((await original.arrayBuffer()).byteLength, bytes.byteLength);
  assert.equal((await upload()).receiptId, receiptId, 'Retry created another submission');
  for (const suffix of ['', '/original']) {
    const denied = await fetch(`${api}/scan/receipts/${receiptId}${suffix}`, { headers: stranger });
    assert.equal(denied.status, 404, 'Another account could read private receipt data');
  }
  const duplicate = await upload(stranger, `scan-smoke:${crypto.randomUUID()}`);
  assert.equal(duplicate.status, 'duplicate', 'Cross-account document resubmission was not detected');
  assert.equal(duplicate.rewardEligible, false);
  const rewards = await json(`${base}/rest/v1/receipt_rewards?receipt_id=eq.${receiptId}&select=id`, { headers: admin });
  assert.equal(rewards.length, 0, 'Provider test must not issue a reward');
  console.log(JSON.stringify({ event: 'production_scan_pipeline_passed', apiHost: new URL(api).host, receiptId,
    providerDocumentId: review.providerDocumentId, status: review.status, verdict: review.verdict,
    privateOriginalRead: true, persistedReadback: true, retryIdempotent: true, otherAccountDenied: true,
    crossAccountDuplicateBlocked: true, rewards: 0,
    checks: record.verification_checks.map(({ key, status }) => ({ key, status })) }));
  console.log(JSON.stringify({ event: 'public_fixture_arithmetic', subtotal: review.subtotal,
    tax: review.tax, fees: review.fees, discount: review.discount, total: review.total }));
} finally {
  // Delete only this run's temporary records and files, never customer submissions.
  const cleanupErrors = [];
  const cleanup = async (operation) => {
    try { await operation(); } catch (error) { cleanupErrors.push(error.message); }
  };
  const remove = async (url) => {
    const response = await fetch(url, { method: 'DELETE', headers: admin, signal: AbortSignal.timeout(30_000) });
    if (!response.ok) throw new Error(`Temporary record cleanup failed: ${response.status}`);
  };
  for (const userId of users) {
    await cleanup(async () => {
      const records = await json(`${base}/rest/v1/scanned_receipts?user_id=eq.${userId}&select=private_storage_path`, { headers: admin });
      for (const row of records) if (row.private_storage_path) paths.push(row.private_storage_path);
    });
    await cleanup(() => remove(`${base}/rest/v1/scanned_receipts?user_id=eq.${userId}`));
    await cleanup(() => remove(`${base}/rest/v1/app_users?id=eq.${userId}`));
    await cleanup(() => remove(`${base}/auth/v1/admin/users/${userId}`));
  }
  if (paths.length) await cleanup(() => json(`${base}/storage/v1/object/captro-private-receipts`, {
    method: 'DELETE', headers: admin, body: JSON.stringify({ prefixes: [...new Set(paths)] }),
  }));
  if (cleanupErrors.length) throw new Error(cleanupErrors.join('; '));
  console.log('Temporary scan smoke-test users, submissions and originals cleaned up.');
}
