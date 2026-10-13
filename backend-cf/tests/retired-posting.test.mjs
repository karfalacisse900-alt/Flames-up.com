import assert from 'node:assert/strict';
import test from 'node:test';
import { retiredPostInputError, retiredFeatureCode } from '../src/retired-posting.ts';

test('ordinary posts require media; captions alone and old intent aliases cannot bypass it', () => {
  for (const type of ['general', 'social', 'moment', 'media', 'text', 'note', 'check_in', 'unknown']) {
    assert.equal(retiredPostInputError({ post_type: type, content: 'Preserved draft' }, 0).code, 'POST_MEDIA_REQUIRED');
    assert.equal(retiredPostInputError({ post_type: type, content: '' }, 1), null);
  }
});
test('structured posts retain their existing validation and access flows', () => {
  for (const type of ['club','event','meetup','deal','offer','local_offer','group','ticket','booking','party','place','guide','travel','receipt','invoice'])
    assert.equal(retiredPostInputError({ post_type: type }, 0), null);
});
test('new voice and poll payloads are rejected without modifying old payloads', () => {
  for (const body of [{ voice_audio_id: 'recording' }, { voiceAudioId: 'recording' },
    { voice_audio_id: '', voiceAudioId: 'recording' }, { voice_audio_id: 'recording', voiceAudioId: '' }])
    assert.equal(retiredPostInputError(body, 1).code, 'VOICE_RETIRED');
  for (const key of ['post_response','postResponse']) {
    const body = { [key]: { type: 'poll', options: ['Yes','No'] } };
    const before = JSON.stringify(body);
    assert.equal(retiredPostInputError(body, 1).code, 'POST_RESPONSES_RETIRED');
    assert.equal(JSON.stringify(body), before);
  }
});

test('retired actions fail clearly while historical reads and real stamp actions remain', () => {
  for (const path of ['/voice/submissions','/upload/audio','/ai/capture-assistant','/ai/capture-assistant/audio','/ai/realtime/session'])
    assert.equal(retiredFeatureCode('POST', `/api${path}`), 'VOICE_RETIRED');
  assert.equal(retiredFeatureCode('POST', '/api/posts/post-id/responses'), 'POST_RESPONSES_RETIRED');
  for (const path of ['/posts/post-id/comments','/posts/post-id/attendance','/commerce/purchases','/group-chats/id/join','/voice/old/appeal'])
    assert.equal(retiredFeatureCode('POST', `/api${path}`), null);
  assert.equal(retiredFeatureCode('GET','/api/voice/old/playback'), null);
  assert.equal(retiredFeatureCode('DELETE','/api/voice/old'), null);
});
