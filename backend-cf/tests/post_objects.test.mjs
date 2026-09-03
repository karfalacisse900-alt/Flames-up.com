import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { publicPostObject, privateTicketPayload, attachPublicPostObjects } from '../src/post-objects.ts';

test('Home object allowlist never includes private ticket or document details', () => {
  const sensitive = { passengerName: 'Private', passengerEmail: 'private@example.com', code: 'SECRET',
    invoiceNumber: 'PRIVATE-INVOICE', customer: { name: 'Private' }, barcode: 'SECRET', verified: true };
  for (const kind of ['event', 'travel', 'receipt', 'invoice', 'collection']) {
    const preview = publicPostObject({ kind, public_data: { ...sensitive, operator: 'Train', originCode: 'AAA' } });
    assert.doesNotMatch(JSON.stringify(preview), /SECRET|Private|private@example|PRIVATE-INVOICE|verified/);
  }
});

test('public document status requires stored backend evidence, not caller claims', () => {
  const row = { kind: 'receipt', public_data: { verdict: 'Verified' } };
  assert.equal(publicPostObject(row).document.verdict, 'Unable to Verify');
  assert.equal(publicPostObject(row, { verification_status: 'verified' }).document.verdict, 'Unable to Verify');
  const receipt = { status: 'feedback_pending', verification_status: 'verified', verification_checks: [{ key: 'duplicate_check', status: 'passed' }] };
  assert.equal(publicPostObject(row, receipt).document.verdict, 'Verified');
  assert.equal(publicPostObject(row, { ...receipt, status: 'duplicate' }).document.verdict, 'Unable to Verify');
});

test('only the actual active ticket owner can obtain ticket fields', () => {
  const row = { id: 'ticket', user_id: 'owner', issuer_reference: 'issued-42', status: 'active',
    details: { code: 'QR-PAYLOAD', codeFormat: 'qr', passengerName: 'Owner', unexpected: 'private' }, private_storage_path: 'secret/file.pdf' };
  assert.equal(privateTicketPayload(row, 'another-user'), null);
  assert.equal(privateTicketPayload({ ...row, status: 'revoked' }, 'owner'), null);
  assert.equal(privateTicketPayload({ ...row, issuer_reference: '' }, 'owner'), null);
  const ticket = privateTicketPayload(row, 'owner');
  assert.equal(ticket.code, 'QR-PAYLOAD');
  assert.equal(ticket.downloadable, true);
  assert.equal(ticket.unexpected, undefined);
  assert.equal(ticket.private_storage_path, undefined);
});

test('public enrichment only attaches records to already-visible posts', async () => {
  const posts = [{ id: 'visible', supabase_post_id: 'visible-id', post_type: 'general' }];
  await attachPublicPostObjects(posts, async (table, filters) => {
    assert.equal(table, 'app_post_objects');
    assert.equal(filters.post_id, 'in.(visible-id)');
    return [{ post_id: 'visible-id', kind: 'travel', public_data: { operator: 'Rail', code: 'secret' } },
      { post_id: 'hidden-id', kind: 'event', public_data: {} }];
  });
  assert.equal(posts.length, 1);
  assert.equal(posts[0].post_type, 'travel');
  assert.equal(posts[0].detail.travel.operator, 'Rail');
  assert.equal(posts[0].detail.travel.code, undefined);
});

test('private object routes recheck visibility and owner and do not enter the post cache', () => {
  const worker = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
  const start = worker.indexOf("api.get('/posts/:postId/object'");
  const end = worker.indexOf("api.post('/posts/:postId/like'", start);
  const routes = worker.slice(start, end);
  assert.match(routes, /supabaseReadVisiblePosts/);
  assert.match(routes, /user_id: postgrestEqFilter\(userId\)/);
  assert.match(routes, /user_id: postgrestEqFilter\(authId\)/);
  assert.match(routes, /private, no-store/);
  const model = readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Models/CaptroPostDetails.swift', import.meta.url), 'utf8');
  const publicDetails = model.slice(0, model.indexOf('public struct CaptroEventDetails'));
  assert.doesNotMatch(publicDetails, /CaptroOwnedTicket|CaptroReceiptReview/);
});
