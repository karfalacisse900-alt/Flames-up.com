const providerTypes = new Set([
  'api_error', 'authentication_error', 'card_error', 'idempotency_error',
  'invalid_request_error', 'rate_limit_error',
]);

export function stripeFailureCode(data: any, fallback: string): string {
  const code = data?.error?.code || data?.code;
  if (typeof code === 'string' && /^[a-z_]{1,80}$/.test(code)
      && !/^(sk_|rk_|pk_|whsec_)/.test(code)) return code;
  if (code === 'STRIPE_INVALID_RESPONSE' || code === 'STRIPE_NOT_CONFIGURED'
      || code === 'STRIPE_CONNECT_ACTIVATION_REQUIRED') return code;
  if (providerTypes.has(data?.error?.type)) return data.error.type;
  return fallback;
}

export async function decodeStripeResponse(response: Response, path: string) {
  let data: any = await response.json().catch(() => null);
  const valid = data !== null && typeof data === 'object' && !Array.isArray(data);
  if (!valid) data = { code: 'STRIPE_INVALID_RESPONSE' };
  const ok = response.ok && valid && !data.error;
  const header = response.headers.get('Request-Id') || '';
  const requestId = /^req_[a-zA-Z0-9]{1,100}$/.test(header) ? header : null;
  let code = stripeFailureCode(data, 'STRIPE_REQUEST_FAILED');
  if (path === '/accounts' && response.status === 400
      && typeof data.error?.message === 'string'
      && data.error.message.includes("You can only create new accounts if you've signed up for Connect")) {
    code = 'STRIPE_CONNECT_ACTIVATION_REQUIRED';
    data = { ...data, error: { ...data.error, code } };
  }
  if (!ok) {
    // Never log provider messages, URLs, bodies, account details or request headers.
    console.warn(JSON.stringify({ event: 'stripe_api_failed', status: response.status, requestId, code }));
  }
  return { ok, status: response.status, data, requestId };
}
