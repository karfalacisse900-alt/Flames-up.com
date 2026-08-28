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
