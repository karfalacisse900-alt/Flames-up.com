export function supabaseRuntimeURL(env: { SUPABASE_URL?: string; ENVIRONMENT?: string; STRIPE_MODE?: string }): string {
  let url: URL;
  try { url = new URL(String(env.SUPABASE_URL || '').trim()); }
  catch { throw new Error('SUPABASE_NOT_CONFIGURED'); }
  const isolatedLoopback = env.ENVIRONMENT === 'test' && env.STRIPE_MODE === 'test'
    && url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
  if ((url.protocol !== 'https:' && !isolatedLoopback) || url.username || url.password || url.search || url.hash
      || url.pathname !== '/') throw new Error('SUPABASE_NOT_CONFIGURED');
  return url.origin;
}
