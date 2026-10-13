import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { realtimeSessionConfig, realtimeCredential, realtimeFailure, safeRealtimeCode } from '../src/realtime-session.ts';

test('speech-to-speech config uses semantic VAD with automatic replies and interruption', () => {
  const { session } = realtimeSessionConfig('test instruction');
  assert.equal(session.type, 'realtime');
  assert.deepEqual(session.output_modalities, ['audio']);
  assert.deepEqual(session.audio.input.turn_detection, {
    type: 'semantic_vad', eagerness: 'medium', create_response: true, interrupt_response: true,
  });
  assert.equal(session.audio.input.format.rate, 24000);
  assert.equal(session.audio.output.format.rate, 24000);
});
test('only fresh flat credentials are accepted, never an HTTP error or legacy nested token', () => {
  const value = 'test-credential-not-a-live-key';
  assert.deepEqual(realtimeCredential({ value, expires_at: 200 }, 100), { value, expiresAt: 200 });
  for (const bad of [null, {}, { error: { value } }, { client_secret: { value }, expires_at: 200 },
    { value, expires_at: 100 }, { value, expires_at: Infinity }, { value, expires_at: NaN }, { value: '', expires_at: 200 }]) {
    assert.equal(realtimeCredential(bad, 100), null);
  }
});
test('permanent credentials/model/billing/config failures do not enter transient retry loops', () => {
  for (const [status, code] of [[401, 'invalid_api_key'], [403, 'access_denied'], [404, 'model_not_found'],
    [429, 'insufficient_quota'], [400, 'invalid_value']]) assert.equal(realtimeFailure(status, code).retryable, false);
  assert.equal(realtimeFailure(429, 'rate_limit_exceeded').code, 'AI_RATE_LIMITED');
  assert.equal(realtimeFailure(503, 'server_error').retryable, true);
  for (const code of ['sk-secret', 'ek_secret', 'Bearer-secret', 'private transcript here', {}]) assert.equal(safeRealtimeCode(code), 'unknown');
});

const read = file => readFileSync(new URL(`../../ios_native/MIRA/Sources/MIRANative/${file}`, import.meta.url), 'utf8');
test('retired voice has no chat recorder, player, retry upload, or AI route', () => {
  const room = read('Screens/ConversationNativeView.swift');
  assert.doesNotMatch(room, /CaptroChatAudioMessage|sendVoiceRecording|showVoiceRecorder|Record voice message/);
  assert.match(room, /Voice messages are no longer supported/);
  assert.match(room, /hasNewMessages/);
  assert.match(room, /Send message/);
});
