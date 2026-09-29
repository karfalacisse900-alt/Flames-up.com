import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

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
const speechPath = join(tmpdir(), `captro-voice-${crypto.randomUUID()}.wav`);
let spokenWav;
try {
  execFileSync('espeak-ng', ['-w', speechPath, '-s', '140', 'This is a private Captro voice test. Help me prepare a post.']);
  spokenWav = readFileSync(speechPath);
} finally {
  rmSync(speechPath, { force: true });
}

async function call(url, init = {}) {
  const response = await fetch(url, { ...init, signal: AbortSignal.timeout(75_000) });
  const result = response.headers.get('content-type')?.includes('application/json') ? await response.json() : {};
  return { response, result };
}

async function uploadVoice(targetType, parentPostId) {
  const form = new FormData();
  form.append('file', new File([spokenWav], 'synthetic-speech.wav', { type: 'audio/wav' }));
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

  const liveSession = await call(`${api}/ai/realtime/session`, {
    method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' },
    body: JSON.stringify({ has_current_recording: false }),
  });
  console.log(JSON.stringify({ stage: 'realtime_credential', status: liveSession.response.status, code: liveSession.result.code || null }));
  assert.equal(liveSession.response.status, 200, 'Realtime session credential could not be created');
  assert.ok(liveSession.result.client_secret && liveSession.result.model === 'gpt-realtime-2.1');
  const connected = await new Promise((resolve, reject) => {
    const socket = new WebSocket('wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1',
      ['realtime', `openai-insecure-api-key.${liveSession.result.client_secret}`]);
    const timer = setTimeout(() => { socket.close(); reject(new Error('Realtime handshake timed out')); }, 15_000);
    socket.onmessage = event => {
      let message;
      try { message = JSON.parse(event.data); } catch { return; }
      if (message.type === 'session.created') {
        clearTimeout(timer);
        socket.close();
        resolve(true);
      } else if (message.type === 'error') {
        clearTimeout(timer);
        socket.close();
        reject(new Error(`Realtime handshake rejected: ${message.error?.code || 'unknown'}`));
      }
    };
    socket.onerror = () => { clearTimeout(timer); reject(new Error('Realtime WebSocket failed')); };
    socket.onclose = () => { clearTimeout(timer); reject(new Error('Realtime WebSocket closed before session ready')); };
  });
  console.log(JSON.stringify({ stage: 'realtime_handshake', connected }));

  const audioForm = new FormData();
  audioForm.append('file', new File([spokenWav], 'synthetic-speech.wav', { type: 'audio/wav' }));
  audioForm.append('history', '[]');
  audioForm.append('has_current_recording', 'false');
  const audioAssistant = await call(`${api}/ai/capture-assistant/audio`, { method: 'POST', headers: bearer, body: audioForm });
  console.log(JSON.stringify({ stage: 'openai_assistant_audio', status: audioAssistant.response.status, code: audioAssistant.result.code || null }));
  assert.equal(audioAssistant.response.status, 200, 'Spoken audio did not receive a Captro AI answer');
  assert.ok(audioAssistant.result.transcript && audioAssistant.result.reply, 'Spoken audio did not transcribe and receive an answer');

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

  let voiceRows;
  for (let attempt = 0; attempt < 12; attempt++) {
    voiceRows = await call(`${supabase}/rest/v1/app_voice_recordings?owner_app_user_id=eq.${authUserId}&select=target_type,target_id,processing_state,moderation_state,publication_state`, { headers: admin });
    assert.ok(voiceRows.response.ok);
    if (voiceRows.result.length === 2 && voiceRows.result.every(row => row.publication_state === 'published')) break;
    await new Promise(resolve => setTimeout(resolve, 5_000));
  }
  assert.equal(voiceRows.result.length, 2);
  assert.ok(voiceRows.result.every(row => !!row.target_id), 'A successful voice submission remained an unbound draft');
  console.log(JSON.stringify({ stage: 'voice_publication', states: voiceRows.result.map(row => ({ target: row.target_type, processing: row.processing_state, moderation: row.moderation_state, publication: row.publication_state })) }));
  assert.ok(voiceRows.result.every(row => row.publication_state === 'published'), 'Spoken voice content was not published after moderation');
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
