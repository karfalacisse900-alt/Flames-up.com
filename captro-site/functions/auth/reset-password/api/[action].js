// Fixed-purpose same-origin bridge. No service keys and no generic proxy target.
const API = 'https://api.flames-up.com/api/auth/password/reset/';
const REDIRECT = 'https://captro-site.pages.dev/auth/reset-password/';
const MAX_BYTES = 12000;
const headers = { 'Content-Type':'application/json', 'Cache-Control':'no-store', 'Referrer-Policy':'no-referrer', 'X-Content-Type-Options':'nosniff' };
const reply = (status, code, ok = false) => new Response(JSON.stringify({ ok, code }), { status, headers });
export async function recoveryHandler(request, action, fetcher = (url, options) => globalThis.fetch(url, options)) {
  if (request.method !== 'POST') return reply(405, 'METHOD_NOT_ALLOWED');
  if (!['request','confirm'].includes(action)) return reply(404, 'NOT_FOUND');
  if (request.headers.get('Origin') !== new URL(request.url).origin) return reply(403, 'ORIGIN_REJECTED');
  if (request.headers.get('Content-Type')?.split(';')[0].trim() !== 'application/json') return reply(415, 'JSON_REQUIRED');
  if (Number(request.headers.get('Content-Length')) > MAX_BYTES) return reply(413, 'TOO_LARGE');
  let body;
  try {
    const reader = request.body?.getReader();
    if (!reader) return reply(400, 'INVALID_REQUEST');
    const chunks = []; let size = 0;
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > MAX_BYTES) { await reader.cancel(); return reply(413, 'TOO_LARGE'); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    body = JSON.parse(new TextDecoder().decode(bytes));
    if (!body || typeof body !== 'object' || Array.isArray(body)) return reply(400, 'INVALID_REQUEST');
  } catch { return reply(400, 'INVALID_REQUEST'); }
  let payload;
  if (action === 'request') {
    if (Object.keys(body).some(k => k !== 'email') || typeof body.email !== 'string' || body.email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email)) return reply(400, 'INVALID_EMAIL');
    payload = { email: body.email, redirect_to: REDIRECT };
  } else {
    if (Object.keys(body).some(k => !['access_token','password'].includes(k)) || typeof body.access_token !== 'string' || !body.access_token || body.access_token.length > 8192 || typeof body.password !== 'string' || body.password.length < 12 || body.password.length > 128) return reply(400, 'INVALID_REQUEST');
    payload = { access_token: body.access_token, password: body.password };
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetcher(API + action, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload), redirect:'manual', signal:controller.signal });
    if (!response.ok) return reply([400,401,403,429].includes(response.status) ? response.status : 502, 'RECOVERY_FAILED');
    const data = await response.json();
    const valid = action === 'request' ? data?.sent === true : typeof data?.access_token === 'string' && !!data.access_token;
    // Never return provider sessions, identities or errors to the recovery browser.
    return valid ? reply(200, 'OK', true) : reply(502, 'INVALID_UPSTREAM_RESPONSE');
  } catch { return reply(502, 'RECOVERY_UNAVAILABLE'); }
  finally { clearTimeout(timer); }
}
export async function onRequest(context) { return recoveryHandler(context.request, context.params.action); }
