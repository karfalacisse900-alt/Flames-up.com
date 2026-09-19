import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { decideVoiceModeration, inspectVoiceAudio, validatedContextEvidence } from '../src/voice.ts';

function syntheticWav(seconds = 1, sampleRate = 8000) {
  const samples = Math.round(seconds * sampleRate);
  const dataBytes = samples * 2;
  const bytes = new Uint8Array(44 + dataBytes);
  const view = new DataView(bytes.buffer);
  const text = (offset, value) => [...value].forEach((char, index) => { bytes[offset + index] = char.charCodeAt(0); });
  text(0, 'RIFF'); view.setUint32(4, 36 + dataBytes, true); text(8, 'WAVE'); text(12, 'fmt ');
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true); view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true); view.setUint16(34, 16, true); text(36, 'data'); view.setUint32(40, dataBytes, true);
  return bytes;
}

test('server measures a decodable WAV and enforces the reply duration limit', () => {
  const oneSecond = inspectVoiceAudio({ name: 'voice.wav', type: 'audio/wav' }, syntheticWav(1), 'reply', {});
  assert.equal(oneSecond.format, 'wav');
  assert.ok(oneSecond.durationMs >= 999 && oneSecond.durationMs <= 1001);
  assert.throws(() => inspectVoiceAudio({ name: 'voice.wav', type: 'audio/wav' }, syntheticWav(31), 'reply', {}), /VOICE_DURATION_EXCEEDED/);
});

test('rejects corrupt input instead of trusting filename or MIME metadata', () => {
  assert.throws(() => inspectVoiceAudio({ name: 'voice.m4a', type: 'audio/mp4' }, new Uint8Array(128), 'post', {}), /VOICE_AUDIO_UNREADABLE/);
});

test('silence or empty recognition is held for review', () => {
  assert.deepEqual(decideVoiceModeration({ transcript: '', flagged: false, autoReject: false }), { state: 'needs_review', reason: 'unclear_audio' });
});

test('clean speech can publish and flagged speech stays private during rollout', () => {
  assert.equal(decideVoiceModeration({ transcript: 'I disagree with that proposal.', flagged: false, autoReject: false }).state, 'approved');
  assert.equal(decideVoiceModeration({ transcript: 'A threat', flagged: true, context: { outcome: 'reject', uncertain: false, evidence: ['A threat'] }, autoReject: false }).state, 'needs_review');
});

test('automatic rejection requires the flag, explicit configuration, certainty, and grounded evidence', () => {
  assert.equal(decideVoiceModeration({ transcript: 'submitted phrase', flagged: true, context: { outcome: 'reject', uncertain: false, evidence: ['submitted phrase'] }, autoReject: true }).state, 'rejected');
  assert.equal(decideVoiceModeration({ transcript: 'submitted phrase', flagged: true, context: { outcome: 'reject', uncertain: true, evidence: ['submitted phrase'] }, autoReject: true }).state, 'needs_review');
});

test('review evidence must occur in the submitting author content', () => {
  assert.deepEqual(validatedContextEvidence(['exact words', 'invented evidence'], 'caption\nexact words'), ['exact words']);
});

test('source keeps storage private and publishing version-bound', () => {
  const migration = fs.readFileSync('../supabase/migrations/20260919150750_voice_recordings_moderation.sql', 'utf8');
  const source = fs.readFileSync('../backend-cf/src/voice.ts', 'utf8');
  assert.match(migration, /'captro-voice-private'[\s\S]*false/);
  assert.match(migration, /approved_content_version <> p_content_version/);
  assert.match(migration, /status = 'pending_voice'/);
  assert.match(source, /publication_state === 'published'/);
  assert.doesNotMatch(source, /moderation_state\s*:\s*clean\(form/);
});

test('native recording is explicit, interruption-safe, and disclosed before use', () => {
  const recorder = fs.readFileSync('../ios_native/MIRA/Sources/MIRANative/Components/CaptroVoiceComponents.swift', 'utf8');
  assert.match(recorder, /requestRecordPermission/);
  assert.match(recorder, /AVAudioSession\.interruptionNotification/);
  assert.match(recorder, /AVAudioSession\.routeChangeNotification/);
  assert.match(recorder, /UIApplication\.didEnterBackgroundNotification/);
  assert.match(recorder, /interactiveDismissDisabled\(recorder\.isRecording\)/);
  assert.match(recorder, /disclosureAccepted/);
  assert.match(recorder, /CaptroVoicePlaybackCenter\.shared\.stop\(\)/);
});

test('composer and comments submit private voice IDs instead of fake audio', () => {
  const composer = fs.readFileSync('../ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift', 'utf8');
  const comments = fs.readFileSync('../ios_native/MIRA/Sources/MIRANative/Screens/PostDetailNativeView.swift', 'utf8');
  assert.match(composer, /CaptroVoiceRecorderSheet\(limit: 60\)/);
  assert.match(composer, /CaptroVoiceUploadService\(api: api\)\.submit/);
  assert.match(composer, /voiceAudioId: voiceSubmissionId/);
  assert.match(composer, /Checking your recording…/);
  assert.match(comments, /CaptroVoiceRecorderSheet\(limit: 30\)/);
  assert.match(comments, /voiceAudioId: voiceId/);
  assert.match(comments, /pendingVoiceReplies/);
});
