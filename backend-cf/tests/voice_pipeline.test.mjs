import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { classifyOpenAIServiceFailure, decideVoiceModeration, inspectVoiceAudio, validatedContextEvidence } from '../src/voice.ts';

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

test('exhausted AI credits stop retries without exposing provider responses', () => {
  assert.deepEqual(classifyOpenAIServiceFailure({ status: 429, message: 'You have no credits remaining. Add credits to continue using the API.' }), {
    code: 'AI_CREDITS_EXHAUSTED', retryable: false,
  });
  assert.deepEqual(classifyOpenAIServiceFailure({ status: 429, code: 'rate_limit_exceeded' }), {
    code: 'AI_SERVICE_TEMPORARY_FAILURE', retryable: true,
  });
  assert.deepEqual(classifyOpenAIServiceFailure(new Error('OPENAI_API_KEY_MISSING')), {
    code: 'AI_CREDENTIALS_MISSING', retryable: false,
  });
});

test('source keeps Cloudflare R2 storage private and publishing version-bound', () => {
  const migration = fs.readFileSync('../supabase/migrations/20260919150750_voice_recordings_moderation.sql', 'utf8');
  const source = fs.readFileSync('../backend-cf/src/voice.ts', 'utf8');
  assert.match(migration, /approved_content_version <> p_content_version/);
  assert.match(migration, /status = 'pending_voice'/);
  assert.match(source, /VOICE_RECORDINGS\?\s*:\s*R2Bucket/);
  assert.match(source, /VOICE_RECORDINGS\.put/);
  assert.match(source, /VOICE_RECORDINGS\.get/);
  assert.match(source, /VOICE_RECORDINGS\.delete/);
  assert.match(source, /cloudflare-r2-private/);
  assert.doesNotMatch(source, /\/storage\/v1\/object/);
  assert.match(source, /publication_state === 'published'/);
  assert.doesNotMatch(source, /moderation_state\s*:\s*clean\(form/);
});

test('native voice recording and assistant implementations are retired', () => {
  for (const file of ['Components/CaptroVoiceComponents.swift', 'Components/CaptroChatVoiceComponents.swift',
    'Screens/CaptroCaptureAssistantView.swift', 'Services/CaptroRealtimeVoiceSession.swift']) {
    assert.equal(fs.existsSync('../ios_native/MIRA/Sources/MIRANative/' + file), false, file);
  }
});

test('composer and comments cannot record or upload retired voice attachments', () => {
  for (const file of ['NotificationLibrarySearchCreateViews.swift', 'PostDetailNativeView.swift']) {
    const source = fs.readFileSync('../ios_native/MIRA/Sources/MIRANative/Screens/' + file, 'utf8');
    assert.doesNotMatch(source, /CaptroVoiceRecorderSheet|CaptroVoiceUploadService|voiceSubmissionId|pendingVoiceReplies/);
    assert.match(source, /voiceAudioId: nil/);
  }
  const cache = fs.readFileSync('../ios_native/MIRA/Sources/MIRANative/Services/MIRAAppCacheStore.swift', 'utf8');
  assert.match(cache, /retiredVoiceDraft/);
  assert.doesNotMatch(cache, /removeItem\(at: voice\.fileURL\)/);
});

test('stored stamped voice records retain historical moderation boundaries', () => {
  const composer = fs.readFileSync('../ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift', 'utf8');
  const backend = fs.readFileSync('../backend-cf/src/index.ts', 'utf8');
  assert.match(composer, /postType: selectedStampKind\.backendPostType/);
  assert.match(composer, /voiceAudioId: nil/);
  assert.match(backend, /await validateVoiceAttachment\(c\.env, voiceAudioId, userId, 'post'\)/);
  assert.match(backend, /await bindVoiceAttachment\(c\.env, \{[\s\S]*?targetType: 'post', targetId: id/);
  assert.match(backend, /status: input\.voiceAudioId \? 'pending_voice' : 'active'/);
});

test('migration permits private voice posts and voice-only replies without opening ordinary empty comments', async () => {
  const db = new PGlite();
  await db.exec(`create schema if not exists public;
    create table public.app_posts (status text constraint app_posts_status_check check (status in ('active','archived','removed')));
    create table public.post_comments (
      body text not null constraint post_comments_body_check check (char_length(body) between 1 and 1200),
      status text constraint post_comments_status_check check (status in ('active','removed','hidden')),
      metadata jsonb not null default '{}'::jsonb
    );`);
  const migration = fs.readFileSync('../supabase/migrations/20260929141014_enable_pending_voice_publication.sql', 'utf8');
  await db.exec(migration);
  await db.exec(`insert into public.app_posts(status) values ('pending_voice');
    insert into public.post_comments(body,status,metadata) values
      ('','pending_voice','{"voice":{"id":"private-recording"}}'),
      ('','active','{"voice":{"id":"approved-recording"}}');`);
  await assert.rejects(db.exec("insert into public.post_comments(body,status) values ('','active')"));
  await db.close();
});


test('voice reply creation binds after a focused comment count, not a full engagement refresh', () => {
  const backend = fs.readFileSync('../backend-cf/src/index.ts', 'utf8');
  const create = backend.split('async function supabaseCreatePostComment(')[1].split('async function supabaseReadPostComments(')[0];
  assert.match(create, /await supabaseAdminUpsert\(c, 'post_comments'/);
  assert.match(create, /await supabasePostCommentCount\(c, input\.postId\)/);
  assert.doesNotMatch(create, /getSupabasePostEngagementState/);
});
