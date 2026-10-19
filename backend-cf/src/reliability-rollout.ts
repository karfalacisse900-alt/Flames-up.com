// A short-lived coordinated schema/Worker gate. Never gate provider webhooks,
// existing entitlement reads, or payment confirmation behind a new-sale switch.
// Compiled by Wrangler --define; it consumes no production binding slots.
declare const CAPTRO_RELIABILITY_RELEASE_MODE: 'maintenance' | 'ready';
export function reliabilityReleaseMode(): 'maintenance' | 'ready' {
  return typeof CAPTRO_RELIABILITY_RELEASE_MODE === 'undefined' ? 'ready' : CAPTRO_RELIABILITY_RELEASE_MODE;
}
export function reliabilityRolloutBlocks(mode: string | undefined, method: string, path: string): boolean {
  if (mode !== 'maintenance' || ['GET','HEAD','OPTIONS'].includes(method)) return false;
  const route=path.replace(/^\/api(?=\/)/,'');
  if (route.startsWith('/stripe/webhook') || /^\/commerce\/purchases\/[^/]+\/complete$/.test(route)) return false;
  return route==='/posts' || route.startsWith('/checkout/') || route.startsWith('/commerce/') ||
    route==='/stripe/checkout/sessions' || route.startsWith('/admin/console/') ||
    route.startsWith('/admin/finance/recovery/') || route.startsWith('/users/me/appeals');
}
