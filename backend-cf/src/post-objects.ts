type Select = (table: string, filters: Record<string, string>, select?: string, limit?: number) => Promise<any[]>;

const text = (value: unknown, max = 300): string | undefined => typeof value === 'string' && value.trim()
  ? value.trim().slice(0, max) : undefined;
const object = (value: any): Record<string, any> => value && typeof value === 'object' && !Array.isArray(value) ? value : {};

function fields(value: any, keys: string[]): Record<string, string> {
  const result: Record<string, string> = {};
  for (const key of keys) { const clean = text(value?.[key]); if (clean) result[key] = clean; }
  return result;
}

// Allowlist all feed fields, even for server-owned records: never serialize a raw object.
export function publicPostObject(row: any, receipt?: any): any {
  const data = object(row?.public_data);
  switch (row?.kind) {
    case 'event': return { event: {
      ...fields(data, ['startsAt', 'endsAt', 'timeZone', 'venueName', 'address', 'city']),
      attendanceEnabled: data.attendanceEnabled === true,
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
