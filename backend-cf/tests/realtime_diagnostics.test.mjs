import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { validateRealtimeDiagnostic } from '../src/realtime-diagnostics.ts';

const valid = { diagnostic_id: '9f736e13-22ea-4a77-bf97-25256af889ad', stage: 'first_pcm_sent', epoch: 1, frames: 2400, bytes: 4800 };
test('voice breadcrumbs accept only bounded stages and counters, never media or secrets', () => {
  assert.deepEqual(validateRealtimeDiagnostic(valid), valid);
  for (const field of ['audio', 'transcript', 'client_secret', 'api_key', 'message']) {
    assert.equal(validateRealtimeDiagnostic({ ...valid, [field]: 'private' }), null);
  }
  for (const change of [ { stage: 'arbitrary' }, { frames: -1 }, { bytes: Infinity },
    { epoch: '1' }, { code: 'sk_secret' }, { code: 'sk-secret' }, { code: 'ek-secret' }, { code: 'contains private speech' },
    { diagnostic_id: 'not-a-session-id' }, { http_status: 999 } ]) {
    assert.equal(validateRealtimeDiagnostic({ ...valid, ...change }), null);
  }
  assert.equal(validateRealtimeDiagnostic({ ...valid, code: 'NSURLErrorDomain.-1009', http_status: 503 }).http_status, 503);
});

const feed = readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroFeedPostView.swift', import.meta.url), 'utf8');


test('structured image-free cards remain compact; ordinary text and poll cards are retired', () => {
  assert.match(feed, /CaptroStructuredFeedCard/);
  assert.match(feed, /structuredStamp\(maxBodyLines: 3\)\s*\.fixedSize\(horizontal: false, vertical: true\)/);
  assert.doesNotMatch(feed, /pageSize|ScrollView\(\.vertical\)/);
  assert.doesNotMatch(feed, /outlinedStamp: true/);
  const card = feed.split('private struct CaptroStructuredFeedCard')[1].split('private struct CaptroAuthorHeader')[0];
  assert.match(card, /\.lineLimit\(maxBodyLines\)\.truncationMode\(\.tail\)/);
  assert.doesNotMatch(card, /CaptroMeasuredCaption|Text\(content\.type\.rawValue/);
  assert.match(card, /Rectangle\(\)\.strokeBorder\(MIRATheme.Color.textPrimary/);
  assert.doesNotMatch(feed, /CaptroPostResponseView/);
  assert.doesNotMatch(feed, /canRespond: showsFeedControls/);
  assert.doesNotMatch(card, /if post\.response != nil/);
  assert.doesNotMatch(card, /Developers|Designers|Co-founders|gradient|shadow|minimumScaleFactor/);
});
