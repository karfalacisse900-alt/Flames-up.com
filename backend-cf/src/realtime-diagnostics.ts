const stages = new Set([
  'microphone_permission_denied', 'microphone_permission_granted', 'credential_created', 'credential_failed',
  'transport_connecting', 'transport_closed', 'session_created', 'session_configured', 'configuration_failed',
  'audio_engine_started', 'audio_engine_failed', 'first_pcm_sent', 'pcm_streaming', 'pcm_send_failed',
  'microphone_signal_detected', 'microphone_stream_stalled', 'speech_started', 'speech_stopped',
  'turn_committed', 'response_requested', 'response_created', 'response_finished', 'response_failed',
  'audio_received', 'audio_playback_started', 'audio_playback_finished', 'barge_in', 'api_error',
  'transcription_completed', 'transcription_failed', 'microphone_muted', 'microphone_unmuted',
  'audio_interrupted', 'audio_route_changed', 'audio_output_selected', 'audio_route_failed',
  'background_suspended', 'heartbeat_failed', 'session_stopped', 'connection_timeout',
  'reconnect_scheduled', 'recovery_exhausted', 'microphone_conversion_failed',
]);

/** Strict telemetry schema. Never accept arbitrary event payloads, audio, text or credentials. */
export function validateRealtimeDiagnostic(body: unknown): Record<string, string | number> | null {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
  const value = body as Record<string, unknown>;
  if (Object.keys(value).some(key => !['diagnostic_id', 'stage', 'epoch', 'frames', 'bytes', 'code', 'http_status'].includes(key))) return null;
  if (typeof value.diagnostic_id !== 'string' || !/^[0-9a-f-]{36}$/i.test(value.diagnostic_id)
    || typeof value.stage !== 'string' || !stages.has(value.stage)) return null;
  for (const key of ['epoch', 'frames', 'bytes']) {
    if (!Number.isSafeInteger(value[key]) || (value[key] as number) < 0 || (value[key] as number) > 1_000_000_000) return null;
  }
  const result: Record<string, string | number> = {
    diagnostic_id: value.diagnostic_id, stage: value.stage,
    epoch: value.epoch as number, frames: value.frames as number, bytes: value.bytes as number,
  };
  if (value.code != null) {
    if (typeof value.code !== 'string' || !/^[a-z0-9._-]{1,100}$/i.test(value.code) || /^(sk_|sk-|ek_|ek-|sess_|bearer)/i.test(value.code)) return null;
    result.code = value.code;
  }
  if (value.http_status != null) {
    if (!Number.isInteger(value.http_status) || (value.http_status as number) < 100 || (value.http_status as number) > 599) return null;
    result.http_status = value.http_status as number;
  }
  return result;
}
