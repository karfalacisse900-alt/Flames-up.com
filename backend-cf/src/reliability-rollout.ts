// A short-lived coordinated schema/Worker gate. Never gate provider webhooks,
// existing entitlement reads, or payment confirmation behind a new-sale switch.
export function reliabilityRolloutBlocks(mode: string | undefined, method: string, path: string): boolean {
  if (mode !== 'maintenance' || ['GET','HEAD','OPTIONS'].includes(method)) return false;
  const route=path.replace(/^\/api(?=\/)/,'');
  if (route.startsWith('/stripe/webhook') || /^\/commerce\/purchases\/[^/]+\/complete$/.test(route)) return false;
  return route==='/posts' || route.startsWith('/checkout/') || route.startsWith('/commerce/') ||
    route==='/stripe/checkout/sessions' || route.startsWith('/admin/console/') ||
    route.startsWith('/admin/finance/recovery/') || route.startsWith('/users/me/appeals');
}
