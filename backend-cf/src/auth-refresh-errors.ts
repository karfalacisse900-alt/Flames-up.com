export class AuthRefreshFailure extends Error {
  status: 401 | 429 | 503;
  code: string;
  retryAfter?: string;
  constructor(status: 401 | 429 | 503, code: string, retryAfter?: string) {
    super(code); this.status = status; this.code = code; this.retryAfter = retryAfter;
  }
}
const invalidRefreshCodes = new Set(['refresh_token_not_found', 'refresh_token_already_used', 'invalid_credentials', 'session_not_found', 'session_expired']);
export function upstreamRefreshFailure(status: number, code: unknown, retryAfter?: string | null) {
  if ((status === 400 || status === 401) && typeof code === 'string' && invalidRefreshCodes.has(code)) {
    return new AuthRefreshFailure(401, 'INVALID_TOKEN');
  }
  if (status === 429) return new AuthRefreshFailure(429, 'SESSION_REFRESH_THROTTLED', /^\d{1,5}$/.test(retryAfter ?? '') ? retryAfter! : '30');
  return new AuthRefreshFailure(503, 'SESSION_REFRESH_UNAVAILABLE');
}
