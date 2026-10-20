// Optional support uses the existing deferred marketplace ledger, not a new wallet.
// Public/live activation is intentionally impossible in this development contract.
export const SUPPORT_ORIGIN = 'https://captro-site.pages.dev';
export const SUPPORT_LIMITS = Object.freeze({ currency: 'USD', minimum: 200, maximum: 20000, suggested: [200, 500, 1000, 2000] });
export const SUPPORT_DISCLOSURE = 'Captro takes 0%. Payment-processing fees apply.';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export class SupportError extends Error {
  status: number;
  constructor(code: string, status = 409) { super(code); this.status = status; }
}
export function supportTestEnabled(env: any) {
  return env.CAPTRO_CREATOR_SUPPORT === 'test' && env.STRIPE_MODE === 'test'
    && env.ENVIRONMENT !== 'production';
}
export function supportAmount(value: unknown, currency: unknown) {
  if (currency !== 'USD' || !Number.isSafeInteger(value) || Number(value) < SUPPORT_LIMITS.minimum
    || Number(value) > SUPPORT_LIMITS.maximum) throw new SupportError('CAPTRO_SUPPORT_AMOUNT_INVALID', 400);
  return Number(value);
}
export function supportCheckoutParameters(p: any) {
  supportAmount(p.total_amount, p.currency);
  if (p.content_type !== 'creator_support' || p.stripe_mode !== 'test' || p.payment_interface !== 'checkout'
    || p.settlement_model !== 'deferred' || p.service_fee_amount !== 0 || p.platform_fee_amount !== 0 || p.tax_amount !== 0
    || p.buyer_id === p.creator_id || !uuid.test(p.id) || !p.stripe_destination_account_id?.startsWith('acct_')) {
    throw new SupportError('CAPTRO_SUPPORT_SNAPSHOT_INVALID');
  }
  const back = `${SUPPORT_ORIGIN}/support-creator/return?purchase_id=${p.id}`;
  return {
    mode: 'payment', success_url: back, cancel_url: `${back}&cancelled=1`,
    client_reference_id: p.buyer_id,
    expires_at: Math.floor(Date.parse(p.hold_expires_at) / 1000),
    'line_items[0][price_data][currency]': 'usd',
    'line_items[0][price_data][unit_amount]': p.total_amount,
    'line_items[0][price_data][product_data][name]': 'One-time creator support',
    'line_items[0][quantity]': 1,
    'payment_method_types[0]': 'card',
    'metadata[source]': 'captro_commerce',
    'metadata[captro_purchase_kind]': 'creator_support',
    'metadata[captro_purchase_id]': p.id,
    'metadata[captro_tax_amount]': 0,
    'payment_intent_data[metadata][source]': 'captro_commerce',
    'payment_intent_data[metadata][captro_purchase_kind]': 'creator_support',
    'payment_intent_data[metadata][captro_purchase_id]': p.id,
    'payment_intent_data[metadata][captro_creator_id]': p.creator_id,
    'payment_intent_data[transfer_group]': `captro_purchase_${p.id.replace(/-/g, '')}`,
    // Separate charges/transfers: no application_fee, transfer_data, tax or
    // marketplace service-fee line. Creator net is settled using actual fees.
  };
}
export function supportStatus(p: any) {
  const statuses: Record<string, string> = { confirmed: 'confirmed', refunded: 'refunded', partially_refunded: 'partially_refunded',
    cancelled: 'cancelled', expired: 'expired', rejected: 'unavailable', disputed: 'disputed', payment_received_under_review: 'under_review' };
  return { id: p.id, status: statuses[p.status] || 'confirming', amount: p.total_amount, currency: p.currency,
    disclosure: SUPPORT_DISCLOSURE, platform_fee: 0, handoff_id: p.handoff_id ?? null };
}
export async function supportToken(secret: string, buyer: string, creator: string, request: string) {
  if (!secret || secret.length < 32) throw new SupportError('CAPTRO_SUPPORT_UNAVAILABLE', 503);
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const bytes = new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(JSON.stringify(['captro-support-v1', buyer, creator, request]))));
  return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
}

type Services = {
  enabled(c: any): boolean;
  hash(token: string): Promise<string>;
  viewer(c: any): string;
  limit(c: any, key: string): Promise<Response | null>;
  authorize(c: any, buyer: string, creator: string, issuedAt?: string): Promise<any>;
  validateBuyer(c: any, buyer: string, authId: string, issuedAt: string): Promise<void>;
  rpc(c: any, name: string, args: any): Promise<any>;
  handoff(c: any, hash: string): Promise<any>;
  handoffById(c: any, id: string): Promise<any>;
  purchase(c: any, id: string): Promise<any>;
  checkout(c: any, purchase: any): Promise<any>;
  reconcile(c: any, purchase: any): Promise<void>;
};
export function registerCreatorSupportRoutes(api: any, auth: any, s: Services) {
  const one = (value: any) => Array.isArray(value) ? value[0] : value;
  const guard = (handler: (c: any) => Promise<any>) => async (c: any) => {
    c.header('Cache-Control', 'private, no-store'); c.header('Referrer-Policy', 'no-referrer');
    try {
      if (!s.enabled(c)) throw new SupportError('CAPTRO_SUPPORT_UNAVAILABLE', 503);
      return await handler(c);
    } catch (error) {
      // Never return provider errors, token values, private metadata or stack traces.
      return c.json({ code: error instanceof SupportError ? error.message : 'CAPTRO_SUPPORT_RETRY',
        detail: 'Could not confirm this request. Check payment status before retrying.' },
        error instanceof SupportError ? error.status : 503);
    }
  };
  const body = async (c: any) => {
    if (Number(c.req.header('Content-Length') || 0) > 2048) throw new SupportError('CAPTRO_SUPPORT_INPUT_INVALID', 400);
    const reader = c.req.raw.body?.getReader();
    if (!reader) throw new SupportError('CAPTRO_SUPPORT_INPUT_INVALID', 400);
    const bytes = new Uint8Array(2048); let size = 0;
    try {
      while (true) {
        const chunk = await reader.read(); if (chunk.done) break;
        if (size + chunk.value.length > bytes.length) {
          await reader.cancel(); throw new SupportError('CAPTRO_SUPPORT_INPUT_INVALID', 400);
        }
        bytes.set(chunk.value, size); size += chunk.value.length;
      }
    } finally { reader.releaseLock(); }
    const text = new TextDecoder().decode(bytes.subarray(0, size));
    try { const b = JSON.parse(text); if (!b || typeof b !== 'object' || Array.isArray(b)) throw new Error(); return b; }
    catch { throw new SupportError('CAPTRO_SUPPORT_INPUT_INVALID', 400); }
  };
  const webContext = async (c: any, b: any, readOnly = false) => {
    if (c.req.header('Origin') !== SUPPORT_ORIGIN) throw new SupportError('CAPTRO_SUPPORT_ORIGIN_DENIED', 403);
    if (typeof b.token !== 'string' || !/^[a-f0-9]{64}$/.test(b.token)) throw new SupportError('CAPTRO_SUPPORT_LINK_EXPIRED', 401);
    const hash = await s.hash(b.token);
    const limited = await s.limit(c, hash); if (limited) throw new SupportError('CAPTRO_SUPPORT_RATE_LIMITED', 429);
    const h = await s.handoff(c, hash);
    if (!h || !Number.isFinite(Date.parse(h.expires_at)) || Date.parse(h.expires_at) <= Date.now()) throw new SupportError('CAPTRO_SUPPORT_LINK_EXPIRED', 401);
    await s.validateBuyer(c, h.buyer_app_user_id, h.buyer_id, h.created_at);
    if (readOnly) return { h, who: null, hash };
    const who = await s.authorize(c, h.buyer_app_user_id, h.creator_app_user_id, h.created_at);
    if (who.buyerId !== h.buyer_id || who.creatorId !== h.creator_id) throw new SupportError('CAPTRO_SUPPORT_IDENTITY_CHANGED', 403);
    return { h, who, hash };
  };
  api.get('/creator-support/eligibility/:creator', auth, async (c: any) => {
    c.header('Cache-Control', 'no-store');
    if (!s.enabled(c)) return c.json({ enabled: false });
    try { await s.authorize(c, s.viewer(c), c.req.param('creator')); return c.json({ enabled: true, ...SUPPORT_LIMITS, disclosure: SUPPORT_DISCLOSURE }); }
    catch { return c.json({ enabled: false }); }
  });
  api.post('/creator-support/handoffs', auth, guard(async c => {
    const b = await body(c);
    if (!uuid.test(b.request_key || '') || b.storefront !== 'USA' || typeof b.creator_id !== 'string'
      || Object.keys(b).some(k => !['request_key','storefront','creator_id'].includes(k))) throw new SupportError('CAPTRO_SUPPORT_INPUT_INVALID', 400);
    const limited = await s.limit(c, s.viewer(c)); if (limited) return limited;
    const who = await s.authorize(c, s.viewer(c), b.creator_id);
    const token = await supportToken(c.env.JWT_SECRET, who.buyerId, who.creatorId, b.request_key);
    const h = one(await s.rpc(c, 'captro_issue_support_handoff', { p_buyer_id: who.buyerId, p_buyer_app_user_id: who.buyerAppId,
      p_creator_id: who.creatorId, p_creator_app_user_id: who.creatorAppId, p_request_key: b.request_key, p_token_hash: await s.hash(token) }));
    return c.json({ id: h.id, url: `${SUPPORT_ORIGIN}/support-creator/#handoff=${token}`, expires_at: h.expires_at });
  }));
  api.post('/creator-support/web/session', guard(async c => {
    const { h, who } = await webContext(c, await body(c));
    const p = h.purchase_id ? await s.purchase(c, h.purchase_id) : null;
    return c.json({ creator: who.profile, ...SUPPORT_LIMITS, disclosure: SUPPORT_DISCLOSURE, purchase: p ? supportStatus(p) : null });
  }));
  api.post('/creator-support/web/checkout', guard(async c => {
    const b = await body(c);
    if (Object.keys(b).some(k => !['token','amount','currency'].includes(k))) throw new SupportError('CAPTRO_SUPPORT_INPUT_INVALID', 400);
    const amount = supportAmount(b.amount, b.currency);
    const { hash, who } = await webContext(c, b);
    const p = one(await s.rpc(c, 'captro_begin_creator_support', { p_token_hash: hash, p_amount: amount, p_connected_account_id: who.accountId }));
    if (p.status !== 'payment_pending') return c.json({ purchase: supportStatus(p) });
    const session = await s.checkout(c, p);
    const url = new URL(session.url);
    if (url.protocol !== 'https:' || url.hostname !== 'checkout.stripe.com' || url.username || url.password) throw new SupportError('CAPTRO_SUPPORT_CHECKOUT_INVALID', 503);
    return c.json({ checkout_url: url.href, purchase: supportStatus(p) });
  }));
  api.post('/creator-support/web/status', guard(async c => {
    const { h } = await webContext(c, await body(c), true);
    if (!h.purchase_id) return c.json({ status: 'not_started' });
    let p = await s.purchase(c, h.purchase_id);
    await s.reconcile(c, p);
    p = await s.purchase(c, h.purchase_id);
    return c.json(supportStatus(p));
  }));
  api.get('/creator-support/purchases/:id', auth, guard(async c => {
    if (!uuid.test(c.req.param('id'))) throw new SupportError('CAPTRO_SUPPORT_NOT_FOUND', 404);
    const p = await s.purchase(c, c.req.param('id'));
    if (!p || p.content_type !== 'creator_support' || p.buyer_app_user_id !== s.viewer(c)) throw new SupportError('CAPTRO_SUPPORT_NOT_FOUND', 404);
    await s.reconcile(c, p);
    return c.json(supportStatus(await s.purchase(c, p.id)));
  }));
  api.get('/creator-support/handoffs/:id/status', auth, guard(async c => {
    if (!uuid.test(c.req.param('id'))) throw new SupportError('CAPTRO_SUPPORT_NOT_FOUND', 404);
    const h = await s.handoffById(c, c.req.param('id'));
    if (!h || h.buyer_app_user_id !== s.viewer(c)) throw new SupportError('CAPTRO_SUPPORT_NOT_FOUND', 404);
    if (!h.purchase_id) return c.json({ status: 'not_started' });
    const p = await s.purchase(c, h.purchase_id);
    await s.reconcile(c, p);
    return c.json(supportStatus(await s.purchase(c, p.id)));
  }));
}
