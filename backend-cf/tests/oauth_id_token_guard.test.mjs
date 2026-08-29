import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

test('OAuth fallback resolves returning accounts by provider subject', () => {
  assert.match(source, /async function findSupabaseAuthUserForOAuthSubject/);
  assert.match(source, /provider_user_id: postgrestEqFilter\(cleanSubject\)/);
  assert.match(source, /const subjectMatch = await findSupabaseAuthUserForOAuthSubject/);
  assert.match(source, /const sessionEmail = normalizeOptionalEmail\(authResult\.user\.email\) \|\| email;/);
});

test('Google uses the server-verified bridge instead of the nonce-incompatible Supabase grant', () => {
  const googleRoute = source.slice(
    source.indexOf("api.post('/auth/oauth/google'"),
    source.indexOf("api.post('/auth/oauth/apple'"),
  );
  assert.doesNotMatch(googleRoute, /signInSupabaseIdToken\(c, 'google'/);
  assert.match(googleRoute, /verifyGoogleIdToken\(c, id_token\)/);
  assert.match(googleRoute, /signInSupabaseVerifiedOAuth\(c, \{/);
  assert.match(googleRoute, /GOOGLE_CREDENTIAL_EXCHANGE_FAILED/);
});

test('Apple retains its raw nonce and uses the same server-verified bridge as Google', () => {
  const appleRoute = source.slice(
    source.indexOf("api.post('/auth/oauth/apple'"),
    source.indexOf("api.get('/auth/me'"),
  );
  assert.match(appleRoute, /const rawNonce = cleanText/);
  assert.match(appleRoute, /verifyAppleIdToken\(c, idToken, rawNonce\)/);
  assert.match(appleRoute, /signInSupabaseVerifiedOAuth\(c, \{/);
  assert.doesNotMatch(appleRoute, /supabase_id_token/);
  assert.match(source, /if \(tokenNonce !== expectedNonce\) throw new Error\('APPLE_NONCE_MISMATCH'\)/);
});

test('OAuth session bridge requires its dedicated production secret', () => {
  const fallback = source.slice(
    source.indexOf('async function oauthFallbackPassword'),
    source.indexOf('async function signInSupabaseVerifiedOAuth'),
  );
  assert.match(fallback, /c\.env\.OAUTH_FALLBACK_SECRET/);
  assert.doesNotMatch(fallback, /c\.env\.JWT_SECRET/);
  assert.doesNotMatch(fallback, /c\.env\.ABUSE_SIGNAL_SECRET/);
  assert.match(source, /session_bridge:[\s\S]*configured:/);
});

test('OAuth rate limiting falls back to D1 when the KV binding throws', () => {
  const limiter = source.slice(
    source.indexOf('async function enforceRateLimit'),
    source.indexOf('async function usersAreBlocked'),
  );
  assert.match(limiter, /event: 'rate_limit_kv_unavailable'/);
  assert.match(limiter, /fallback: 'd1'/);
  assert.match(limiter, /await ensureReliabilitySchema\(c\.env\.DB\)/);
  assert.match(limiter, /if \(!c\.env\.KV && supabasePrimaryConfigured\(c\) && isProductionEnv\(c\)\)/);
});

test('iOS social-auth payload fields remain accepted by both routes', () => {
  const googleRoute = source.slice(
    source.indexOf("api.post('/auth/oauth/google'"),
    source.indexOf("api.post('/auth/oauth/apple'"),
  );
  const appleRoute = source.slice(
    source.indexOf("api.post('/auth/oauth/apple'"),
    source.indexOf("api.get('/auth/me'"),
  );

  for (const field of ['access_token', 'terms_version', 'terms_accepted_at']) {
    assert.match(googleRoute, new RegExp(`['\"]${field}['\"]`));
  }
  for (const field of ['nonce', 'terms_version', 'terms_accepted_at']) {
    assert.match(appleRoute, new RegExp(`['\"]${field}['\"]`));
  }
});
