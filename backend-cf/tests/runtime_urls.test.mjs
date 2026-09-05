import assert from 'node:assert/strict';
import test from 'node:test';
import { supabaseRuntimeURL } from '../src/runtime-urls.ts';

test('only an explicit isolated test runtime can use loopback Supabase without TLS', () => {
  const local = { SUPABASE_URL: 'http://127.0.0.1:54321', ENVIRONMENT: 'test', STRIPE_MODE: 'test' };
  assert.equal(supabaseRuntimeURL(local), local.SUPABASE_URL);
  for (const patch of [{ ENVIRONMENT: 'production' }, { STRIPE_MODE: 'live' }, { STRIPE_MODE: undefined },
    { SUPABASE_URL: 'http://127.0.0.1.example.com' }, { SUPABASE_URL: 'http://10.0.0.1' },
    { SUPABASE_URL: 'http://user:secret@localhost:54321' }, { SUPABASE_URL: 'http://localhost:54321/redirect' }]) {
    assert.throws(() => supabaseRuntimeURL({ ...local, ...patch }), /SUPABASE_NOT_CONFIGURED/);
  }
  assert.equal(supabaseRuntimeURL({ SUPABASE_URL: 'https://project.supabase.co/' }), 'https://project.supabase.co');
});
