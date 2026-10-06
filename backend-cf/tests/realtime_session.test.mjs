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
test('native session owns streaming, epoch guards, and actual playback rather than a manual reply queue', () => {
  const source = read('Services/CaptroRealtimeVoiceSession.swift');
  assert.doesNotMatch(source, /"type": "response\.create"|pendingReplyItemIDs|requestNextReply/);
  assert.match(source, /turnDetection\?\["create_response"\] as\? Bool == true/);
  assert.match(source, /completionCallbackType: \.dataPlayedBack/);
  assert.match(source, /player\.installTap/);
  assert.match(source, /"conversation\.item\.truncate"/);
  const route = source.split('func handleRouteChange')[1].split('func suspendForBackground')[0];
  assert.doesNotMatch(route, /recoverTransport|connect\(api:/);
  assert.match(route, /stopAudio\(\)/);
  assert.match(source, /self\.audioEpoch == captureEpoch/);
});
test('reference character mouth uses playback signal, with independent eye/body layers', () => {
  const source = read('Components/CaptroVoiceCharacterView.swift');
  const bridge = read('Components/CaptroVoiceVisualState.swift');
  assert.match(source, /state\.isSpeaking.*state\.playbackAmplitude/);
  const face = source.split('private var face: some View')[1].split('private var eye: some View')[0];
  assert.doesNotMatch(face, /microphoneAmplitude|transcript|speakingLevel.*Date/);
  assert.match(bridge, /playbackAmplitude = isSpeaking \? session\.playbackLevel : 0/);
  assert.match(source, /reduceMotion/);
  assert.match(source, /Task\.isCancelled/);
  assert.match(source, /CaptroCharacterBody/);
});
test('human chat microphone has a distinct deliberate recording and preview flow, never AI', () => {
  const source = read('Components/CaptroChatVoiceComponents.swift');
  const room = read('Screens/ConversationNativeView.swift');
  assert.match(source, /CaptroVoiceRecorder\(limit: 60\)/);
  assert.match(source, /Button\("Send"\)/);
  assert.match(source, /startTask\?\.cancel\(\)/);
  assert.doesNotMatch(source, /CaptroRealtimeVoiceSession|\/ai\/|transcrib/);
  assert.match(room, /CaptroChatAudioMessage\(url: url/);
  assert.match(room, /sendVoiceRecording/);
  assert.match(room, /hasNewMessages/);
  assert.match(read('Screens/ProfileChatVerificationStudio.swift'), /fullScreenCover\(isPresented: \$showsCaptroAI\)/);
});
