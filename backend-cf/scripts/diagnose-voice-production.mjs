import assert from 'node:assert/strict';

// Disposable, private, synthetic voice smoke against the deployed Worker.
// No real user recordings, tokens, transcripts, or provider secrets are logged.
const project = process.env.SUPABASE_PROJECT_REF;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const publishableKey = process.env.SUPABASE_ANON_KEY;
assert.ok(project && serviceKey && publishableKey, 'Supabase smoke credentials are required');
const supabase = `https://${project}.supabase.co`;
const api = 'https://flames-up-api.karfalacisse900.workers.dev/api';
const admin = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
let authUserId = '';
let bearer;
const voiceIds = [];

async function call(url, init = {}) {
  const response = await fetch(url, { ...init, signal: AbortSignal.timeout(75_000) });
  const result = response.headers.get('content-type')?.includes('application/json') ? await response.json() : {};
  return { response, result };
}

function wavSilence() {
  const sampleRate = 8_000;
  const dataBytes = sampleRate * 2;
  const bytes = new Uint8Array(44 + dataBytes);
  const view = new DataView(bytes.buffer);
  const text = (at, value) => [...value].forEach((char, index) => { bytes[at + index] = char.charCodeAt(0); });
  text(0, 'RIFF'); view.setUint32(4, 36 + dataBytes, true); text(8, 'WAVE'); text(12, 'fmt ');
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true); view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true); view.setUint16(34, 16, true); text(36, 'data'); view.setUint32(40, dataBytes, true);
  return bytes;
}

async function uploadVoice(targetType, parentPostId) {
  const form = new FormData();
  form.append('file', new File([wavSilence()], 'synthetic-silence.wav', { type: 'audio/wav' }));
  form.append('target_type', targetType);
  form.append('disclosure_accepted', 'true');
  form.append('disclosure_version', 'voice-ai-processing-v1');
  if (parentPostId) form.append('parent_post_id', parentPostId);
  const { response, result } = await call(`${api}/voice/submissions`, { method: 'POST', headers: bearer, body: form });
  console.log(JSON.stringify({ stage: `voice_${targetType}_upload`, status: response.status, code: result.code || null }));
  assert.equal(response.status, 202, 'Private synthetic voice upload failed');
  assert.ok(result.id, 'Voice upload did not return an ID');
  voiceIds.push(result.id);
  return result.id;
}

try {
  const email = `captro-voice-smoke-${crypto.randomUUID()}@captro.invalid`;
  const password = crypto.randomUUID() + crypto.randomUUID();
  const created = await call(`${supabase}/auth/v1/admin/users`, {
    method: 'POST', headers: { ...admin, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  assert.ok(created.response.ok && created.result.id, 'Could not create temporary voice test account');
  authUserId = created.result.id;
  const session = await call(`${supabase}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: publishableKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  assert.ok(session.response.ok && session.result.access_token, 'Temporary voice test sign-in failed');
  bearer = { Authorization: `Bearer ${session.result.access_token}` };
  const profile = await call(`${api}/auth/me`, { headers: bearer });
  assert.equal(profile.response.status, 200, 'Temporary user cannot reach Captro');

  const textAssistant = await call(`${api}/ai/capture-assistant`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ utterance: 'Help me prepare a post.', history: [], has_current_recording: false }),
  });
  console.log(JSON.stringify({ stage: 'openai_assistant_text', status: textAssistant.response.status, code: textAssistant.result.code || null, answered: !!textAssistant.result.reply }));
  assert.equal(textAssistant.response.status, 200, 'Existing OpenAI assistant did not respond');
  assert.ok(textAssistant.result.reply);

  const audioForm = new FormData();
  audioForm.append('file', new File([wavSilence()], 'synthetic-silence.wav', { type: 'audio/wav' }));
  audioForm.append('history', '[]');
  audioForm.append('has_current_recording', 'false');
  const audioAssistant = await call(`${api}/ai/capture-assistant/audio`, { method: 'POST', headers: bearer, body: audioForm });
  console.log(JSON.stringify({ stage: 'openai_assistant_audio', status: audioAssistant.response.status, code: audioAssistant.result.code || null }));
  assert.ok(audioAssistant.response.status === 200 || (audioAssistant.response.status === 422 && audioAssistant.result.code === 'VOICE_NOT_HEARD'),
    'The audio request did not reach a successful transcription outcome');

  const post = await call(`${api}/posts`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'Temporary private voice test', content: 'Synthetic test only.', post_type: 'general', visibility: 'private' }),
  });
  console.log(JSON.stringify({ stage: 'private_parent_post', status: post.response.status, code: post.result.code || null }));
  assert.ok(post.response.ok && post.result.id, 'Could not create temporary private parent post');
  const parentPostId = post.result.id;

  const replyVoice = await uploadVoice('reply', parentPostId);
  const comment = await call(`${api}/posts/${parentPostId}/comments`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ content: '', voice_audio_id: replyVoice, client_request_id: crypto.randomUUID() }),
  });
  console.log(JSON.stringify({ stage: 'voice_only_comment', status: comment.response.status, code: comment.result.code || null }));
  assert.equal(comment.response.status, 202, 'Voice-only comment could not enter pending moderation');

  const postVoice = await uploadVoice('post');
  const voicePost = await call(`${api}/posts`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'Temporary private voice post', content: '', post_type: 'general', visibility: 'private', voice_audio_id: postVoice }),
  });
  console.log(JSON.stringify({ stage: 'voice_post', status: voicePost.response.status, code: voicePost.result.code || null }));
  assert.ok(voicePost.response.ok && voicePost.result.id, 'Voice post could not enter pending moderation');

  const voiceRows = await call(`${supabase}/rest/v1/app_voice_recordings?owner_app_user_id=eq.${authUserId}&select=target_type,target_id`, { headers: admin });
  assert.ok(voiceRows.response.ok);
  assert.equal(voiceRows.result.length, 2);
  assert.ok(voiceRows.result.every(row => !!row.target_id), 'A successful voice submission remained an unbound draft');
  console.log(JSON.stringify({ stage: 'voice_binding', bound: voiceRows.result.length }));
} finally {
  const cleanupErrors = [];
  for (const id of voiceIds) {
    if (!bearer) break;
    const deleted = await call(`${api}/voice/${id}`, { method: 'DELETE', headers: bearer }).catch(() => null);
    if (!deleted?.response.ok) cleanupErrors.push('private_voice_object');
  }
  if (authUserId) {
    for (const table of ['post_comments?app_user_id', 'app_posts?app_user_id', 'app_voice_recordings?owner_app_user_id', 'app_users?id']) {
      const deleted = await call(`${supabase}/rest/v1/${table}=eq.${authUserId}`, { method: 'DELETE', headers: admin }).catch(() => null);
      if (!deleted?.response.ok) cleanupErrors.push(table.split('?')[0]);
    }
    const deleted = await call(`${supabase}/auth/v1/admin/users/${authUserId}`, { method: 'DELETE', headers: admin }).catch(() => null);
    if (!deleted?.response.ok) cleanupErrors.push('temporary_auth_user');
  }
  console.log(JSON.stringify({ stage: 'cleanup', complete: cleanupErrors.length === 0, errors: cleanupErrors }));
  assert.equal(cleanupErrors.length, 0, 'Temporary private smoke cleanup failed');
}
