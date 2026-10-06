/** Current Realtime API contract. No beta payloads or permanent client keys. */
export const realtimeModel = 'gpt-realtime-2.1';

export function realtimeSessionConfig(instructions: string) {
  return { session: {
    type: 'realtime', model: realtimeModel, instructions,
    output_modalities: ['audio'], max_output_tokens: 256,
    audio: {
      input: {
        format: { type: 'audio/pcm', rate: 24000 },
        transcription: { model: 'gpt-transcribe' },
        turn_detection: { type: 'semantic_vad', eagerness: 'medium', create_response: true, interrupt_response: true },
      },
      output: { format: { type: 'audio/pcm', rate: 24000 }, voice: 'marin' },
    },
  } };
}

export function realtimeFailure(status: number, providerCode: unknown) {
  const code = typeof providerCode === 'string' ? providerCode : '';
  if (['insufficient_quota', 'billing_hard_limit_reached', 'billing_not_active'].includes(code))
    return { code: 'AI_QUOTA_UNAVAILABLE', retryable: false, status: 503 as const };
  if (status === 401) return { code: 'AI_CREDENTIALS_INVALID', retryable: false, status: 503 as const };
  if (status === 403 || code === 'model_not_found') return { code: 'AI_MODEL_ACCESS_DENIED', retryable: false, status: 503 as const };
  if (status === 429) return { code: 'AI_RATE_LIMITED', retryable: true, status: 429 as const };
  if (status >= 400 && status < 500) return { code: 'AI_CONFIGURATION_INVALID', retryable: false, status: 503 as const };
  return { code: 'AI_SERVICE_TEMPORARY_FAILURE', retryable: true, status: 503 as const };
}

export function realtimeCredential(value: unknown, nowSeconds = Date.now() / 1000) {
  if (!value || typeof value !== 'object') return null;
  const result = value as Record<string, unknown>;
  if (typeof result.value !== 'string' || result.value.length < 20
      || typeof result.expires_at !== 'number' || !Number.isFinite(result.expires_at) || result.expires_at <= nowSeconds + 5) return null;
  // The current response is flat { value, expires_at, session }, not the old
  // { client_secret: { value } } shape. Do not mistake an error body for auth.
  return { value: result.value, expiresAt: result.expires_at };
}

export function safeRealtimeCode(value: unknown) {
  return typeof value === 'string' && /^[a-z0-9_.-]{1,80}$/i.test(value)
    && !/^(sk_|sk-|ek_|ek-|bearer)/i.test(value) ? value : 'unknown';
}
