// Prospective validation only. Stored posts/votes/recordings remain unchanged.
const structured = new Set(['club', 'event', 'meetup', 'deal', 'offer', 'local_offer',
  'group', 'ticket', 'booking', 'party', 'place', 'guide', 'travel', 'receipt', 'invoice']);

/** Retire new actions without removing authorized historical reads/deletion. */
export function retiredFeatureCode(method: string, requestPath: string): string | null {
  const path = requestPath.replace(/^\/api(?=\/)/, '');
  if (method !== 'POST') return null;
  if (path === '/voice/submissions' || path === '/upload/audio' || path.startsWith('/ai/capture-assistant')
    || path.startsWith('/ai/realtime/')) return 'VOICE_RETIRED';
  if (/^\/posts\/[^/]+\/responses$/.test(path)) return 'POST_RESPONSES_RETIRED';
  return null;
}

export function retiredPostInputError(body: Record<string, any>, mediaCount: number) {
  if ([body.voice_audio_id, body.voiceAudioId].some(value => String(value ?? '').trim()))
    return { detail: 'Voice posting is no longer available. Your recording has not been deleted.', code: 'VOICE_RETIRED' };
  if (body.post_response != null || body.postResponse != null)
    return { detail: 'Poll responses are no longer available. Use comments to reply.', code: 'POST_RESPONSES_RETIRED' };
  const type = String(body.post_type || body.postType || body.type || body.category || 'general').trim().toLowerCase();
  if (!structured.has(type) && mediaCount === 0)
    return { detail: 'Add a photo or video to publish.', code: 'POST_MEDIA_REQUIRED' };
  return null;
}
