import type { Context, Hono, MiddlewareHandler } from 'hono';

const shops = 'app_businesses';
const products = 'app_business_products';
const orders = 'app_business_orders';
const source = 'captro_business';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const eq = (value: string) => 'eq.' + value;
const token = (value: unknown) => typeof value === 'string' && uuid.test(value) ? value.toLowerCase() : invalid();
const string = (value: unknown, max: number, optional = false) => {
  if (typeof value !== 'string' || value.trim().length > max || (!optional && !value.trim())) invalid();
  return (value as string).trim();
};
const integer = (v: unknown, min: number, max: number) => {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max) invalid();
  return v as number;
};
const coordinate = (v: unknown, max: number) => {
  if (typeof v !== 'number' || !Number.isFinite(v) || Math.abs(v) > max) invalid();
  return v as number;
};
const array = (v: unknown, max: number): any[] => Array.isArray(v) && v.length <= max ? v : invalid();
const invalid = (): never => { throw new Error('INVALID_BUSINESS_INPUT'); };
const errors: Record<string, [400 | 404 | 409 | 503, string]> = {
  INVALID_BUSINESS_INPUT: [400, 'Check the business, product, or order details and try again.'],
  BUSINESS_UNAVAILABLE: [409, 'This business is not taking orders.'],
  PRODUCT_UNAVAILABLE: [409, 'A product in your bag is no longer available.'],
  INVALID_OPTIONS: [409, 'The menu changed. Review the options in your bag.'],
  INVALID_BAG: [400, 'Check the quantities in your bag.'],
  BAG_LIMIT: [400, 'This bag exceeds the order limit.'],
  ORDER_NOT_FOUND: [404, 'This order could not be found.'],
  INVALID_ORDER_ACTION: [409, 'This action is no longer available for this order.'],
  PRICE_CHANGED: [409, 'The total changed. Review your bag before paying.'],
  REQUEST_MISMATCH: [409, 'This checkout already exists. Find it in Your Orders.'],
  CAPTRO_PAYOUTS_NOT_READY: [409, 'This business has not finished payment setup.'],
  CAPTRO_SELLER_IDENTITY_REQUIRED: [409, 'This business has not completed seller verification.'],
  BUSINESS_PAYMENTS_DISABLED: [503, 'Business checkout is currently unavailable.'],
  BUSINESS_PROVIDER_PENDING: [503, 'Stripe has not confirmed this update yet. Check the order again shortly.'],
};

type StripeResult = { ok: boolean; data: any };
type Dependencies = {
  rpc(c: Context, name: string, body: Record<string, unknown>): Promise<any>;
  select(c: Context, table: string, filters: Record<string, string>, columns: string, limit: number): Promise<any[]>;
  query(c: Context, table: string, options: { filters: Record<string, string>; select: string; limit: number; offset?: number; order: string }): Promise<any[]>;
  insert(c: Context, table: string, rows: any[]): Promise<any[]>;
  patch(c: Context, table: string, filters: Record<string, string>, patch: Record<string, unknown>): Promise<unknown>;
  getStripe(c: Context, path: string): Promise<StripeResult>;
  postStripe(c: Context, path: string, params: Record<string, string | number | boolean>, key: string): Promise<StripeResult>;
  stripe(c: Context): { mode: 'test' | 'live' | null; configured: boolean; webhookConfigured: boolean; publishableKey: string };
  actor(c: Context): string;
  seller(c: Context, id: string): Promise<{ provider_account_id: string }>;
  media(c: Context, ids: string[]): Promise<string[]>;
  limit(c: Context, key: string): Promise<Response | null | undefined>;
};

export function businessLines(value: unknown) {
  return array(value, 40).map(line => ({
    product_id: token(line?.product_id),
    quantity: integer(line?.quantity, 1, 20),
    option_ids: array(line?.option_ids, 30).map(token).sort(),
  }));
}

export function businessGroups(value: unknown, mode: string) {
  const ids = new Set<string>();
  const unique = (v: unknown) => {
    const id = token(v);
    if (ids.has(id)) invalid();
    ids.add(id);
    return id;
  };
  const groups = array(value, 12);
  if ((mode === 'QUICK_ADD' && groups.length) || (mode === 'CUSTOMIZE' && !groups.length)) invalid();
  return groups.map(group => {
    const options = array(group?.options, 30).map(option => ({
      id: unique(option?.id),
      name: string(option?.name, 60),
      extra: integer(option?.extra, 0, 5000),
    }));
    const maximum = integer(group?.maximum, 1, options.length);
    return { id: unique(group?.id), name: string(group?.name, 60),
      minimum: integer(group?.minimum, 0, maximum), maximum, options };
  });
}

function orderView(row: any, buyer: boolean) {
  return {
    id: row.id, business_id: row.business_id, business_name: row.business_name,
    pickup_address: row.pickup_address, latitude: row.latitude, longitude: row.longitude,
    location_updated_at: row.location_updated_at, created_at: row.created_at,
    subtotal: row.subtotal, tax: row.tax, fee: row.fee, total: row.total, status: row.status,
    lines: row.lines, refunded_amount: row.refunded_amount,
    processing_fee: buyer ? null : row.processing_fee,
    pickup_token: buyer && row.status === 'ready' ? row.pickup_token : null,
  };
}

export function makeBusinessOrdering<E extends { Bindings?: object; Variables?: object }>(
  api: Hono<E>, auth: MiddlewareHandler<E>, deps: Dependencies,
) {
  const get = async (c: Context, table: string, id: string, extra = {}) =>
    (await deps.select(c, table, { id: eq(id), ...extra }, '*', 1))[0];
  const owner = async (c: Context, business: string) => {
    const shop = await get(c, shops, business, { owner_id: eq(deps.actor(c)) });
    if (!shop) throw new Error('ORDER_NOT_FOUND');
    return shop;
  };
  const payable = (c: Context) => {
    const stripe = deps.stripe(c);
    // Food settlement has no release adapter in the existing payout queue yet.
    if (c.env.CAPTRO_BUSINESS_TEST_CHECKOUT !== '1' || stripe.mode !== 'test' ||
      !stripe.configured || !stripe.webhookConfigured) throw new Error('BUSINESS_PAYMENTS_DISABLED');
    return { ...stripe, mode: 'test' as const };
  };
  const wrap = (handler: (c: Context) => Promise<Response>, limited = false) => async (c: Context) => {
    try {
      if (limited) {
        const limitedResponse = await deps.limit(c, 'business_ordering');
        if (limitedResponse) return limitedResponse;
      }
      return await handler(c);
    } catch (error) {
      const message = error instanceof Error ? error.message : '';
      const code = Object.keys(errors).find(key => message === key || message.endsWith(':' + key));
      if (code) return c.json({ detail: errors[code][1], code }, errors[code][0]);
      console.warn(JSON.stringify({ event: 'business_request_failed', request_id: c.get('requestId') }));
      return c.json({ detail: 'Could not complete the business request. Try again.', code: 'BUSINESS_REQUEST_FAILED' }, 503);
    }
  };
  const body = (c: Context) => c.req.json().catch(() => invalid());
  const offset = (c: Context) => integer(Number(c.req.query('offset') ?? '0'), 0, 10_000);

  async function verify(c: Context, order: any, paymentId: string) {
    if (!/^pi_[A-Za-z0-9]+$/.test(paymentId)) invalid();
    const result = await deps.getStripe(c, '/payment_intents/' + paymentId);
    const intent = result.data;
    if (!result.ok) throw new Error('BUSINESS_PROVIDER_PENDING');
    if (intent.id !== paymentId || intent.metadata?.source !== source ||
      intent.metadata?.business_order_id !== order.id || intent.currency !== 'usd' ||
      intent.amount !== order.total || intent.livemode !== (order.stripe_mode === 'live') ||
      intent.transfer_group !== 'business_' + order.id || intent.transfer_data || intent.on_behalf_of) {
      throw new Error('PAYMENT_MISMATCH');
    }
    if (intent.status !== 'succeeded') return order;
    const chargeId = typeof intent.latest_charge === 'string' ? intent.latest_charge : intent.latest_charge?.id;
    if (intent.amount_received !== order.total || !/^ch_[A-Za-z0-9]+$/.test(chargeId ?? '')) throw new Error('PAYMENT_MISMATCH');
    const chargeResult = await deps.getStripe(c, '/charges/' + chargeId + '?expand[]=balance_transaction');
    const charge = chargeResult.data;
    if (!chargeResult.ok) {
      throw new Error('BUSINESS_PROVIDER_PENDING');
    }
    if (charge.id !== chargeId || charge.payment_intent !== paymentId || charge.currency !== 'usd' ||
      charge.amount !== order.total || !charge.paid || !charge.captured) throw new Error('PAYMENT_MISMATCH');
    const balance = charge.balance_transaction;
    const fee = balance?.currency === 'usd' && Number.isInteger(balance.fee) ? balance.fee : null;
    return deps.rpc(c, 'captro_business_payment', {
      p_order: order.id, p_intent: paymentId, p_charge: chargeId, p_total: intent.amount_received,
      p_currency: 'USD', p_mode: order.stripe_mode, p_fee: fee,
      p_refunded: charge.amount_refunded, p_disputed: charge.disputed === true,
    });
  }

  api.get('/businesses', wrap(async c => {
    const lat = c.req.query('lat'), lon = c.req.query('lon');
    if ((lat === undefined) !== (lon === undefined)) invalid();
    return c.json(await deps.rpc(c, 'captro_business_discover', {
      p_lat: lat === undefined ? null : coordinate(Number(lat), 90),
      p_lon: lon === undefined ? null : coordinate(Number(lon), 180), p_offset: offset(c),
    }));
  }));
  api.get('/businesses/:id/menu', wrap(async c => {
    const id = token(c.req.param('id'));
    if (!await get(c, shops, id, { published: 'eq.true' })) throw new Error('ORDER_NOT_FOUND');
    return c.json(await deps.query(c, products, {
      filters: { business_id: eq(id), available: 'eq.true' }, select: '*',
      order: 'category.asc,name.asc,id.asc', limit: 50, offset: offset(c),
    }));
  }));
  api.post('/businesses/:id/quote', auth, wrap(async c => {
    const input = await body(c);
    return c.json(await deps.rpc(c, 'captro_business_price', {
      p_business: token(c.req.param('id')), p_lines: businessLines(input?.lines),
    }));
  }, true));
  api.post('/businesses/:id/checkout', auth, wrap(async c => {
    const stripe = payable(c);
    const id = token(c.req.param('id'));
    const input = await body(c);
    const shop = await get(c, shops, id, { published: 'eq.true' });
    if (!shop) throw new Error('BUSINESS_UNAVAILABLE');
    const account = await deps.seller(c, shop.owner_id);
    const order = await deps.rpc(c, 'captro_business_begin', {
      p_business: id, p_buyer: deps.actor(c), p_request: token(input?.request_id),
      p_lines: businessLines(input?.lines), p_total: integer(input?.total, 50, 100000),
      p_mode: stripe.mode, p_account: account.provider_account_id,
    });
    if (order.status !== 'awaiting_payment') return c.json({ order: orderView(order, true) });
    if (!order.intent_id && Date.now() - Date.parse(order.created_at) > 22 * 60 * 60 * 1000) {
      throw new Error('BUSINESS_PROVIDER_PENDING');
    }
    const result = order.intent_id ? await deps.getStripe(c, '/payment_intents/' + order.intent_id) :
      await deps.postStripe(c, '/payment_intents', {
        amount: order.total, currency: 'usd', 'payment_method_types[0]': 'card',
        transfer_group: 'business_' + order.id, 'metadata[source]': source, 'metadata[business_order_id]': order.id,
      }, 'business-payment:' + order.id);
    const intent = result.data;
    if (!result.ok || !/^pi_[A-Za-z0-9]+$/.test(intent?.id || '') || intent.amount !== order.total ||
      intent.metadata?.business_order_id !== order.id || intent.metadata?.source !== source || intent.livemode !== false ||
      intent.transfer_group !== 'business_' + order.id || intent.currency !== 'usd') throw new Error('BUSINESS_PROVIDER_PENDING');
    if (intent.status === 'succeeded') return c.json({ order: orderView(await verify(c, order, intent.id), true) });
    if (!['requires_payment_method', 'requires_confirmation', 'requires_action'].includes(intent.status) ||
      typeof intent.client_secret !== 'string' || !intent.client_secret.startsWith(intent.id + '_secret_')) {
      throw new Error('BUSINESS_PROVIDER_PENDING');
    }
    await deps.patch(c, orders, { id: eq(order.id), intent_id: 'is.null' }, { intent_id: intent.id });
    return c.json({ order: orderView(order, true), payment: {
      publishable_key: stripe.publishableKey, client_secret: intent.client_secret,
    } });
  }, true));

  api.get('/business-orders', auth, wrap(async c => {
    const rows = await deps.query(c, orders, { filters: { buyer_id: eq(deps.actor(c)) }, select: '*',
      limit: 50, offset: offset(c), order: 'created_at.desc,id.desc' });
    return c.json(rows.map(row => orderView(row, true)));
  }));
  api.get('/business-orders/:id', auth, wrap(async c => {
    const row = await get(c, orders, token(c.req.param('id')), { buyer_id: eq(deps.actor(c)) });
    if (!row) throw new Error('ORDER_NOT_FOUND');
    const shop = await get(c, shops, row.business_id);
    const pickup = shop?.category === 'street_food' && !['completed','refunded','cancelled'].includes(row.status)
      ? { pickup_address: shop.pickup_address, latitude: shop.latitude, longitude: shop.longitude,
          location_updated_at: shop.location_updated_at }
      : {};
    return c.json(orderView({ ...row, ...pickup }, true));
  }));
  api.post('/business-orders/:id/verify', auth, wrap(async c => {
    const row = await get(c, orders, token(c.req.param('id')), { buyer_id: eq(deps.actor(c)) });
    if (!row) throw new Error('ORDER_NOT_FOUND');
    const checked = row.intent_id && (row.status === 'awaiting_payment' || row.processing_fee == null)
      ? await verify(c, row, row.intent_id) : row;
    return c.json(orderView(checked, true));
  }, true));
  api.post('/business-orders/:id/action', auth, wrap(async c => {
    const input = await body(c);
    const action = string(input?.action, 20);
    if (!['accept','prepare','ready','reject','cancel','pickup'].includes(action)) invalid();
    let row = await deps.rpc(c, 'captro_business_transition', {
      p_order: token(c.req.param('id')), p_actor: deps.actor(c), p_action: action,
      p_token: action === 'pickup' ? token(input?.pickup_token) : null,
    });
    if (row.status === 'refund_pending') {
      if (!row.intent_id || row.stripe_mode !== deps.stripe(c).mode) throw new Error('BUSINESS_PROVIDER_PENDING');
      if (!row.refund_id && Date.now() - Date.parse(row.refund_requested_at) > 22 * 60 * 60 * 1000) {
        // Avoid replaying an ambiguous creation after Stripe's idempotency retention window.
        throw new Error('BUSINESS_PROVIDER_PENDING');
      }
      const result = row.refund_id ? await deps.getStripe(c, '/refunds/' + row.refund_id) :
        await deps.postStripe(c, '/refunds', { payment_intent: row.intent_id }, 'business-refund:' + row.id);
      if (!result.ok || !/^re_[A-Za-z0-9]+$/.test(result.data?.id || '')) throw new Error('BUSINESS_PROVIDER_PENDING');
      await deps.patch(c, orders, { id: eq(row.id), refund_id: 'is.null' }, { refund_id: result.data.id });
      row = await verify(c, row, row.intent_id);
    }
    return c.json(orderView(row, row.buyer_id === deps.actor(c)));
  }, true));

  api.get('/business-owner/shops', auth, wrap(async c =>
    c.json(await deps.select(c, shops, { owner_id: eq(deps.actor(c)) }, '*', 50))));
  api.post('/business-owner/shops', auth, wrap(async c => {
    const input = await body(c);
    const id = token(input?.id);
    const category = string(input?.category, 24);
    if (!['coffee_bakery', 'street_food'].includes(category) || typeof input?.paused !== 'boolean') invalid();
    const current = await get(c, shops, id);
    if (current && current.owner_id !== deps.actor(c)) throw new Error('ORDER_NOT_FOUND');
    const photoIds = input?.photo_ids === undefined ? undefined : array(input.photo_ids, 8).map(token);
    const avatarId = input?.avatar_id ? token(input.avatar_id) : null;
    const photoUrls = photoIds?.length ? await deps.media(c, photoIds) : photoIds;
    const avatarUrl = avatarId ? (await deps.media(c, [avatarId]))[0] : input?.avatar_id === '' ? null : undefined;
    const latitude = coordinate(input?.latitude, 90), longitude = coordinate(input?.longitude, 180);
    const address = string(input?.pickup_address, 240);
    const fields = {
      name: string(input?.name, 80), category, pickup_address: address, latitude, longitude,
      hours: string(input?.hours ?? '', 300, true), paused: input.paused,
      ...(photoUrls ? { photos: photoUrls } : {}), ...(avatarUrl !== undefined ? { avatar_url: avatarUrl } : {}),
      ...(!current || current.latitude !== latitude || current.longitude !== longitude || current.pickup_address !== address
        ? { location_updated_at: new Date().toISOString() } : {}),
    };
    if (current) await deps.patch(c, shops, { id: eq(id), owner_id: eq(deps.actor(c)) }, fields);
    else await deps.insert(c, shops, [{ ...fields, id, owner_id: deps.actor(c) }]);
    return c.json(await owner(c, id));
  }, true));
  api.get('/business-owner/:id/products', auth, wrap(async c => {
    const shop = await owner(c, token(c.req.param('id')));
    return c.json(await deps.query(c, products, { filters: { business_id: eq(shop.id) }, select: '*',
      limit: 50, offset: offset(c), order: 'category.asc,name.asc,id.asc' }));
  }));
  api.post('/business-owner/:id/products', auth, wrap(async c => {
    const shop = await owner(c, token(c.req.param('id')));
    const input = await body(c);
    const id = token(input?.id);
    const current = await get(c, products, id);
    if (current && current.business_id !== shop.id) throw new Error('ORDER_NOT_FOUND');
    const mode = string(input?.mode, 16);
    if (!['QUICK_ADD', 'CUSTOMIZE'].includes(mode) || typeof input?.available !== 'boolean') invalid();
    const image = input?.media_id ? (await deps.media(c, [token(input.media_id)]))[0] : undefined;
    const fields = { name: string(input?.name, 80), category: string(input?.category, 48),
      unit_amount: integer(input?.unit_amount, 50, 100000), available: input.available,
      mode, groups: businessGroups(input?.groups, mode), ...(image ? { image_url: image } : {}) };
    if (current) await deps.patch(c, products, { id: eq(id), business_id: eq(shop.id) }, fields);
    else await deps.insert(c, products, [{ ...fields, id, business_id: shop.id }]);
    return c.json(await get(c, products, id));
  }, true));
  api.get('/business-owner/:id/orders', auth, wrap(async c => {
    const shop = await owner(c, token(c.req.param('id')));
    const rows = await deps.query(c, orders, { filters: { business_id: eq(shop.id), status: 'neq.awaiting_payment' },
      select: '*', limit: 50, offset: offset(c), order: 'created_at.desc,id.desc' });
    return c.json(rows.map(row => orderView(row, false)));
  }));
  api.get('/business-owner/:id/orders/:orderId', auth, wrap(async c => {
    const shop = await owner(c, token(c.req.param('id')));
    const row = await get(c, orders, token(c.req.param('orderId')), { business_id: eq(shop.id) });
    if (!row || row.status === 'awaiting_payment') throw new Error('ORDER_NOT_FOUND');
    return c.json(orderView(row, false));
  }));
  api.post('/business-owner/:id/pickup', auth, wrap(async c => {
    const shop = await owner(c, token(c.req.param('id')));
    const input = await body(c);
    const [prefix, orderId, pickupToken, extra] = string(input?.code, 100).split(':');
    if (prefix !== 'captro-pickup' || extra !== undefined) invalid();
    const row = await get(c, orders, token(orderId), { business_id: eq(shop.id) });
    if (!row) throw new Error('ORDER_NOT_FOUND');
    return c.json(orderView(await deps.rpc(c, 'captro_business_transition', {
      p_order: row.id, p_actor: deps.actor(c), p_action: 'pickup', p_token: token(pickupToken),
    }), false));
  }, true));

  return async (c: Context, event: any): Promise<boolean> => {
    if (event.account) return false;
    const object = event.data?.object;
    if (event.type.startsWith('payment_intent.') && object?.metadata?.source === source) {
      if (event.type === 'payment_intent.succeeded') {
        const row = await get(c, orders, token(object.metadata.business_order_id));
        if (!row) throw new Error('ORDER_NOT_FOUND');
        await verify(c, row, object.id);
      }
      return true;
    }
    if (!['charge.updated','charge.refunded','refund.created','refund.updated','charge.dispute.created','charge.dispute.closed'].includes(event.type)) return false;
    const id = object?.payment_intent;
    if (!/^pi_[A-Za-z0-9]+$/.test(id || '')) return false;
    const rows = await deps.select(c, orders, { intent_id: eq(id) }, '*', 1);
    if (!rows.length) return false;
    await verify(c, rows[0], id);
    return true;
  };
}
