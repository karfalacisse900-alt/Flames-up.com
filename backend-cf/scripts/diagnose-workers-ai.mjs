import assert from 'node:assert/strict';

const account = process.env.CLOUDFLARE_ACCOUNT_ID;
const token = process.env.CLOUDFLARE_API_TOKEN;
assert.ok(account && token, 'Cloudflare diagnostic credentials are required');

// Synthetic text only: never send a real Status, transcript, or customer datum.
const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/ai/run/@cf/meta/llama-guard-3-8b`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    messages: [
      { role: 'system', content: 'Classify the user-supplied status for safety. Return only the safety classification.' },
      { role: 'user', content: 'Temporary synthetic status publication check.' },
    ],
    max_tokens: 32,
    temperature: 0,
  }),
  signal: AbortSignal.timeout(30_000),
});
const payload = await response.json().catch(() => ({}));
console.log(JSON.stringify({
  event: 'workers_ai_diagnostic',
  httpStatus: response.status,
  success: payload.success === true,
  errorCodes: Array.isArray(payload.errors) ? payload.errors.map(error => error.code).slice(0, 3) : [],
  errorMessages: Array.isArray(payload.errors) ? payload.errors.map(error => String(error.message || '').slice(0, 180)).slice(0, 3) : [],
  response: String(payload.result?.response || '').slice(0, 80),
}));
