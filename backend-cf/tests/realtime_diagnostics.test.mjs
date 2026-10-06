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

const session = readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Services/CaptroRealtimeVoiceSession.swift', import.meta.url), 'utf8');
const ui = readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroCaptureAssistantView.swift', import.meta.url), 'utf8');
const feed = readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroFeedPostView.swift', import.meta.url), 'utf8');

test('native voice readiness follows confirmed config plus PCM send, never permission alone', () => {
  const ready = session.split('case "session.updated":')[1].split('case "input_audio_buffer.speech_started":')[0];
  assert.doesNotMatch(ready, /phase = \.listening|reconnectAttempts = 0/);
  assert.match(ready, /pcm_format_mismatch/);
  assert.match(session, /first_pcm_sent[\s\S]*?self\.phase = \.listening/);
  assert.match(session, /microphone_stream_stalled/);
  assert.match(session, /player\.installTap/);
  assert.match(session, /isInterruptedEvent\(event\)/);
  assert.match(session, /queuedOutputBuffers == 0 && phase != \.userSpeaking/);
  assert.match(session, /input_audio_buffer\.clear/);
  assert.match(session, /suppressed \? Data\(count:/);
  assert.match(session, /chunk\.muteVersion != gate\.version/);
  assert.doesNotMatch(ui, /Send to Captro|Record again|Done speaking/);
  assert.match(ui, /selectOutput\(speaker: false, input: input\)/);
  assert.match(ui, /suspendForBackground\(\)/);
  assert.match(session, /func suspendForBackground\(\)[\s\S]*?stop\(\)/);
});

test('text-only Stamp is outlined, measured, creator-configured and separate from media/header UI', () => {
  assert.match(feed, /CaptroTextOnlyStampCard/);
  assert.match(feed, /textOnlyStamp\(maxBodyLines: 3\)\s*\.fixedSize\(horizontal: false, vertical: true\)/);
  assert.doesNotMatch(feed, /pageSize|ScrollView\(\.vertical\)/);
  assert.match(feed, /outlinedStamp: true/);
  const card = feed.split('private struct CaptroTextOnlyStampCard')[1].split('private struct CaptroAuthorHeader')[0];
  assert.match(card, /CaptroMeasuredCaption/);
  assert.match(card, /Rectangle\(\)\.strokeBorder\(MIRATheme.Color.textPrimary/);
  assert.match(feed, /canRespond: canRespond/);
  assert.doesNotMatch(feed, /canRespond: showsFeedControls/);
  assert.match(card, /if post\.response != nil/);
  assert.doesNotMatch(card, /Developers|Designers|Co-founders|gradient|shadow|minimumScaleFactor/);
});
