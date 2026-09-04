type Select = (table: string, filters: Record<string, string>, select?: string, limit?: number) => Promise<any[]>;

const CONTENT_TYPES = new Set([
  'offer', 'deal', 'club', 'group', 'meetup', 'event', 'party',
  'ticket', 'access_pass', 'booking', 'reservation',
]);

const FULFILLMENT_BY_TYPE: Record<string, string> = {
  offer: 'order',
  deal: 'redemption',
  club: 'membership',
  group: 'group_access',
  meetup: 'attendance',
  event: 'ticket',
  party: 'ticket',
  ticket: 'ticket',
  access_pass: 'ticket',
  booking: 'reservation',
  reservation: 'reservation',
};

const text = (value: unknown, max: number): string | undefined => {
  if (typeof value !== 'string') return undefined;
  const clean = value.trim();
  return clean ? clean.slice(0, max) : undefined;
};

const read = (value: any, camel: string, snake: string): unknown => value?.[camel] ?? value?.[snake];

function bool(value: unknown, fallback = false): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function integer(value: unknown, min: number, max: number): number | undefined {
  if (value == null || value === '') return undefined;
  const number = Number(value);
  if (!Number.isInteger(number) || number < min || number > max) throw new Error('Enter a valid whole number.');
  return number;
}

function isoDate(value: unknown, label: string): string | undefined {
  const clean = text(value, 80);
  if (!clean) return undefined;
  const parsed = Date.parse(clean);
  if (!Number.isFinite(parsed)) throw new Error(`Enter a valid ${label}.`);
  return new Date(parsed).toISOString();
}

function stringList(value: unknown, maxItems: number, itemLength: number): string[] {
  if (!Array.isArray(value)) return [];
  return value.map(item => text(item, itemLength)).filter((item): item is string => !!item).slice(0, maxItems);
}

function publicDataForType(type: string, value: any): Record<string, unknown> {
  const data = value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  const result: Record<string, unknown> = {};
  const addText = (camel: string, snake: string, max: number) => {
    const clean = text(read(data, camel, snake), max);
    if (clean) result[camel] = clean;
  };

  addText('ageRequirement', 'age_requirement', 80);
  if (['offer', 'deal'].includes(type)) {
    addText('originalPrice', 'original_price', 40);
    addText('redemptionRules', 'redemption_rules', 1200);
    result.fulfillmentMethods = stringList(read(data, 'fulfillmentMethods', 'fulfillment_methods'), 4, 40);
  }
  if (['club', 'group'].includes(type)) {
    result.benefits = stringList(data.benefits, 12, 180);
    result.rules = stringList(data.rules, 12, 240);
  }
  if (['booking', 'reservation'].includes(type)) {
    addText('availability', 'availability', 600);
    const duration = integer(read(data, 'durationMinutes', 'duration_minutes'), 5, 1440);
    if (duration) result.durationMinutes = duration;
  }
  return result;
}

export type CaptroCommerceConfig = {
  purchasable: Record<string, unknown>;
  prices: CaptroValidatedPrice[];
};

type CaptroValidatedPrice = {
  label: string;
  unit_amount: number;
  currency: string;
  billing_period: 'one_time';
  capacity: number | null;
  sort_order: number;
};

export function validateCommerceInput(value: unknown, options: {
  postType: string;
  title: string;
  description: string;
  visibility: string;
  location?: string | null;
  city?: string | null;
}): CaptroCommerceConfig | null {
  if (value == null) return null;
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Enter valid purchase details.');
  const input: any = value;
  const enabled = read(input, 'enabled', 'enabled');
  if (enabled === false) return null;
  const contentType = text(read(input, 'contentType', 'content_type'), 40)?.toLowerCase() || options.postType;
  if (!CONTENT_TYPES.has(contentType)) throw new Error('Choose a supported paid or joinable post type.');
  const fulfillmentType = FULFILLMENT_BY_TYPE[contentType];
  const paymentModel = text(read(input, 'paymentModel', 'payment_model'), 20)?.toLowerCase() || 'free';
  if (!['free', 'paid'].includes(paymentModel)) throw new Error('Choose Free or Paid.');
  const commerceClass = text(read(input, 'commerceClass', 'commerce_class'), 30)?.toLowerCase() || 'outside_app';
  if (!['outside_app', 'digital'].includes(commerceClass)) throw new Error('Choose where this purchase is used.');
  const title = text(input.title, 180) || text(options.title, 180);
  if (!title) throw new Error('Add a title before enabling access or payment.');
  const startsAt = isoDate(read(input, 'startsAt', 'starts_at'), 'start date');
  const endsAt = isoDate(read(input, 'endsAt', 'ends_at'), 'end date');
  const expiresAt = isoDate(read(input, 'expiresAt', 'expires_at'), 'expiration date');
  if (startsAt && endsAt && endsAt <= startsAt) throw new Error('End time must be after start time.');
  const capacity = integer(input.capacity, 1, 1_000_000);
  const currency = (text(input.currency, 3) || 'USD').toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) throw new Error('Choose a valid currency.');
  const rawPrices = Array.isArray(input.prices) && input.prices.length ? input.prices.slice(0, 12) : [{
    label: 'General', unitAmount: paymentModel === 'paid' ? read(input, 'unitAmount', 'unit_amount') : 0,
    capacity,
  }];
  const prices: CaptroValidatedPrice[] = rawPrices.map((raw: any, index: number) => {
    const amountValue = Number(read(raw, 'unitAmount', 'unit_amount'));
    const amount = paymentModel === 'free' ? 0 : amountValue;
    if (paymentModel === 'paid' && (!Number.isInteger(amount) || amount < 50 || amount > 5_000_000)) {
      throw new Error('Enter a price of at least $0.50.');
    }
    const tierCapacity = integer(raw.capacity, 1, 1_000_000);
    return {
      label: text(raw.label, 80) || (index === 0 ? 'General' : `Tier ${index + 1}`),
      unit_amount: amount,
      currency,
      billing_period: 'one_time',
      capacity: tierCapacity ?? null,
      sort_order: index,
    };
  });
  const totalTierCapacity = prices.every(price => typeof price.capacity === 'number')
    ? prices.reduce((sum, price) => sum + Number(price.capacity), 0) : undefined;
  if (capacity && totalTierCapacity && totalTierCapacity > capacity) {
    throw new Error('Ticket tier quantities cannot exceed the total capacity.');
  }
  return {
    purchasable: {
      content_type: contentType,
      fulfillment_type: fulfillmentType,
      payment_model: paymentModel,
      commerce_class: commerceClass,
      approval_required: bool(read(input, 'approvalRequired', 'approval_required')),
      pass_required: bool(read(input, 'passRequired', 'pass_required'), ['event', 'party', 'ticket', 'access_pass'].includes(contentType)),
      status: 'active',
      title,
      description: text(input.description, 4000) || text(options.description, 4000) || '',
      location_name: text(read(input, 'locationName', 'location_name'), 180) || text(options.location, 180) || null,
      address: text(input.address, 260) || null,
      city: text(input.city, 100) || text(options.city, 100) || null,
      starts_at: startsAt || null,
      ends_at: endsAt || null,
      timezone: text(input.timezone, 100) || null,
      capacity: capacity ?? null,
      expires_at: expiresAt || null,
      refund_policy: text(read(input, 'refundPolicy', 'refund_policy'), 1600) || '',
      visibility: ['public', 'followers', 'friends', 'private'].includes(options.visibility) ? options.visibility : 'public',
      audience: ['anyone', 'followers', 'friends', 'approval'].includes(String(input.audience)) ? String(input.audience) : 'anyone',
      public_data: publicDataForType(contentType, read(input, 'publicData', 'public_data')),
      private_config: {},
    },
    prices,
  };
}

function pricePayload(row: any) {
  const capacity = row?.capacity == null ? null : Math.max(0, Number(row.capacity));
  const committed = Math.max(0, Number(row?.quantity_committed || 0));
  return {
    id: String(row?.id || ''),
    postId: String(row?.post_id || ''),
    label: String(row?.label || 'General'),
    unitAmount: Math.max(0, Number(row?.unit_amount || 0)),
    currency: String(row?.currency || 'USD'),
    billingPeriod: String(row?.billing_period || 'one_time'),
    capacity,
    remaining: capacity == null ? null : Math.max(0, capacity - committed),
    active: row?.active === true,
  };
}

export function publicCommercePayload(row: any, prices: any[], viewer?: any) {
  const capacity = row?.capacity == null ? null : Math.max(0, Number(row.capacity));
  const committed = Math.max(0, Number(row?.quantity_committed || 0));
  const priceRows = prices.filter(price => price.purchasable_id === row.id && price.active === true)
    .sort((a, b) => Number(a.sort_order || 0) - Number(b.sort_order || 0));
  const lowest = priceRows.reduce((result, price) => !result || Number(price.unit_amount) < Number(result.unit_amount) ? price : result, null as any);
  const viewerStatus = viewer?.entitlement_status || viewer?.purchase_status || null;
  return {
    id: String(row?.id || ''),
    contentType: String(row?.content_type || ''),
    fulfillmentType: String(row?.fulfillment_type || ''),
    paymentModel: String(row?.payment_model || 'free'),
    commerceClass: String(row?.commerce_class || 'outside_app'),
    title: String(row?.title || ''),
    description: String(row?.description || ''),
    locationName: row?.location_name || null,
    address: row?.address || null,
    city: row?.city || null,
    startsAt: row?.starts_at || null,
    endsAt: row?.ends_at || null,
    timeZone: row?.timezone || null,
    capacity,
    joinedCount: committed,
    remaining: capacity == null ? null : Math.max(0, capacity - committed),
    expiresAt: row?.expires_at || null,
    refundPolicy: String(row?.refund_policy || ''),
    approvalRequired: row?.approval_required === true,
    passRequired: row?.pass_required === true,
    status: String(row?.status || 'active'),
    audience: String(row?.audience || 'anyone'),
    publicData: row?.public_data && typeof row.public_data === 'object' ? row.public_data : {},
    prices: priceRows.map(pricePayload),
    lowestPrice: lowest ? pricePayload(lowest) : null,
    viewerStatus,
    viewerPurchaseId: viewer?.purchase_id || null,
    viewerEntitlementId: viewer?.entitlement_id || null,
    viewerDestinationId: viewer?.destination_id || null,
  };
}

export async function attachPublicCommerce(posts: any[], select: Select): Promise<void> {
  const postIds = posts.map(post => post.supabase_post_id).filter((id: unknown) => typeof id === 'string' && id);
  if (!postIds.length) return;
  const rows = await select('app_purchasables', { post_id: `in.(${postIds.join(',')})`, status: 'in.(active,sold_out)' });
  if (!rows.length) return;
  const ids = rows.map(row => row.id).filter(Boolean);
  const prices = await select('app_prices', { purchasable_id: `in.(${ids.join(',')})`, active: 'eq.true' });
  for (const row of rows) {
    const post = posts.find(item => item.supabase_post_id === row.post_id);
    if (!post) continue;
    post.detail = { ...(post.detail || {}), commerce: publicCommercePayload(row, prices) };
  }
}

export const captroCommerceTestSupport = {
  CONTENT_TYPES,
  FULFILLMENT_BY_TYPE,
};
