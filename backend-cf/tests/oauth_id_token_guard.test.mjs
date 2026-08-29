import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

test('native OAuth uses the raw Supabase ID-token REST contract', () => {
  assert.match(
    source,
    /const body: any = \{ provider, id_token: idToken \};/,
    'Supabase raw REST requests must send id_token, not the client-library token alias',
  );
  assert.doesNotMatch(
    source,
    /const body: any = \{ provider, token: idToken \};/,
  );
  assert.match(source, /if \(provider === 'google' && accessToken\) body\.access_token = accessToken;/);
  assert.match(source, /if \(nonce\) body\.nonce = nonce;/);
});

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

test('Apple retains its raw nonce through direct exchange and verified bridge', () => {
  const appleRoute = source.slice(
    source.indexOf("api.post('/auth/oauth/apple'"),
    source.indexOf("api.get('/auth/me'"),
  );
  assert.match(appleRoute, /const rawNonce = cleanText/);
  assert.match(appleRoute, /signInSupabaseIdToken\(c, 'apple', idToken, \{[\s\S]*nonce: rawNonce/);
  assert.match(appleRoute, /verifyAppleIdToken\(c, idToken, rawNonce\)/);
  assert.match(source, /if \(tokenNonce !== expectedNonce\) throw new Error\('APPLE_NONCE_MISMATCH'\)/);
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
