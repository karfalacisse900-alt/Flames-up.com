type Select = (table: string, filters: Record<string, string>, select?: string, limit?: number) => Promise<any[]>;

const text = (value: unknown, max = 300): string | undefined => typeof value === 'string' && value.trim()
  ? value.trim().slice(0, max) : undefined;
const object = (value: any): Record<string, any> => value && typeof value === 'object' && !Array.isArray(value) ? value : {};

function fields(value: any, keys: string[]): Record<string, string> {
  const result: Record<string, string> = {};
  for (const key of keys) { const clean = text(value?.[key]); if (clean) result[key] = clean; }
  return result;
}

export const isEventPostType = (value: unknown): boolean => ['event', 'meetup', 'concert', 'show'].includes(String(value));

// This allowlist deliberately excludes tickets, identity, attendance totals and verification.
export function validateCreatorEvent(value: unknown): Record<string, any> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Enter valid event details.');
  const input = value as Record<string, unknown>;
  const result: Record<string, any> = {};
  const read = (key: string) => input[key] ?? input[key.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`)];
  for (const [key, limit] of Object.entries({ venueName: 180, address: 260, city: 80, timeZone: 100 })) {
    const value = read(key);
    if (value == null || value === '') continue;
    if (typeof value !== 'string' || value.trim().length > limit) throw new Error(`Invalid event ${key}.`);
    if (value.trim()) result[key] = value.trim();
  }
  if (result.timeZone) {
    try { new Intl.DateTimeFormat('en', { timeZone: result.timeZone }).format(); }
    catch { throw new Error('Choose a valid time zone.'); }
  }
  for (const key of ['startsAt', 'endsAt']) {
    const value = read(key);
    if (value == null || value === '') continue;
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?(Z|[+-]\d{2}:\d{2})$/.test(value)
        || !Number.isFinite(Date.parse(value))) throw new Error('Enter a valid event date and time.');
    result[key] = new Date(value).toISOString();
  }
  if (result.endsAt && (!result.startsAt || result.endsAt <= result.startsAt)) throw new Error('End time must be after the start time.');
  if (result.startsAt && !result.timeZone) throw new Error('Choose the event time zone.');
  if (input.price != null && input.price !== '') {
    const price = String(input.price).trim();
    const currency = typeof input.currency === 'string' ? input.currency.trim().toUpperCase() : '';
    if (!/^\d{1,7}(\.\d{1,2})?$/.test(price)) throw new Error('Enter a valid non-negative price.');
    if (!Intl.supportedValuesOf('currency').includes(currency)) throw new Error('Choose a valid currency.');
    result.price = price;
    result.currency = currency;
  }
  const attendance = read('attendanceEnabled');
  if (attendance != null && typeof attendance !== 'boolean') throw new Error('Choose a valid RSVP setting.');
  result.attendanceEnabled = attendance !== false;
  return result;
}

export function creatorEventDetails(metadata: any, postType: unknown): any {
  if (!isEventPostType(postType) || !object(metadata).creator_event) return undefined;
  const detail = publicPostObject({ kind: 'event', public_data: metadata.creator_event });
  return { event: { ...detail.event, creatorEditable: true } };
}

// Allowlist all feed fields, even for server-owned records: never serialize a raw object.
export function publicPostObject(row: any, receipt?: any): any {
  const data = object(row?.public_data);
  switch (row?.kind) {
    case 'event': return { event: {
      ...fields(data, ['startsAt', 'endsAt', 'timeZone', 'venueName', 'address', 'city', 'price', 'currency']),
      attendanceEnabled: data.attendanceEnabled === true,
      creatorEditable: false,
    } };
    case 'travel': return { travel: fields(data, [
      'operator', 'originCode', 'destinationCode', 'originCity', 'destinationCity', 'duration',
      'departure', 'arrival', 'serviceNumber', 'travelClass', 'price', 'currency',
    ]) };
    case 'receipt':
    case 'invoice': return { document: {
      documentType: receipt?.receipt_type ?? row.kind,
      merchantName: text(receipt?.merchant_name),
      total: receipt?.total_amount == null ? undefined : String(receipt.total_amount),
      currency: text(receipt?.currency),
      verdict: receipt?.verification_status === 'verified' && receipt?.status !== 'duplicate'
        && Array.isArray(receipt?.verification_checks)
        && receipt.verification_checks.some((check: any) => check.key === 'duplicate_check' && check.status === 'passed')
        ? 'Verified' : receipt?.status === 'processing' ? 'Processing' : 'Unable to Verify',
    } };
    case 'collection': return { collection: { itemIds: Array.isArray(data.itemIds)
      ? data.itemIds.filter((id: unknown) => typeof id === 'string' && /^[a-zA-Z0-9_-]{1,120}$/.test(id)).slice(0, 50) : [] } };
    default: return {};
  }
}

export async function attachPublicPostObjects(posts: any[], select: Select): Promise<void> {
  const ids = posts.map(post => post.supabase_post_id).filter(Boolean);
  if (!ids.length) return;
  const rows = await select('app_post_objects', { post_id: `in.(${ids.join(',')})` });
  const receiptIds = rows.map(row => row.receipt_id).filter(Boolean);
  const receipts = receiptIds.length ? await select('scanned_receipts', { id: `in.(${receiptIds.join(',')})` },
    'id,receipt_type,merchant_name,total_amount,currency,verification_status,verification_checks,status') : [];
  for (const row of rows) {
    const post = posts.find(post => post.supabase_post_id === row.post_id);
    if (!post) continue;
    post.post_type = row.kind;
    post.detail = publicPostObject(row, receipts.find(receipt => receipt.id === row.receipt_id));
  }
}

export function privateTicketPayload(row: any, viewerAuthId: string): any | null {
  if (!viewerAuthId || row?.user_id !== viewerAuthId || row?.status !== 'active' || !text(row.issuer_reference)) return null;
  return {
    id: row.id,
    ...fields(object(row.details), ['tier', 'seat', 'section', 'passengerName', 'passengerEmail',
      'terminal', 'gate', 'serviceNumber', 'travelClass', 'departure', 'arrival']),
    code: text(row.details?.code, 2000),
    codeFormat: ['qr', 'code128'].includes(row.details?.codeFormat) ? row.details.codeFormat : undefined,
    downloadable: Boolean(text(row.private_storage_path, 1200)),
  };
}
