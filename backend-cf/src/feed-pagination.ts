// Opaque continuation for an already-authorized feed. Encryption matters here:
// a scan boundary can belong to a private/blocked post and must not disclose its ID.
export class FeedCursorError extends Error {
  constructor() { super('FEED_CURSOR_INVALID'); }
}

export type FeedBoundary = { legacyCreatedAt: string | null; createdAt: string; id: string };
export type FeedCursor = {
  version: 1; viewer: string; scope: string; city: string;
  snapshot: string; expires: number; boundary: FeedBoundary | null;
};

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const maxAge = 24 * 60 * 60 * 1000;
const datePattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;
function validDate(value: unknown): value is string {
  return typeof value === 'string' && datePattern.test(value) && Number.isFinite(Date.parse(value));
}
function validBoundary(value: any): value is FeedBoundary {
  return value != null && (value.legacyCreatedAt === null || validDate(value.legacyCreatedAt))
    && validDate(value.createdAt) && typeof value.id === 'string'
    && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value.id);
}
async function key(secret: string) {
  if (typeof secret !== 'string' || secret.length < 16) throw Error('FEED_CURSOR_KEY_UNAVAILABLE');
  const material = await crypto.subtle.digest('SHA-256', encoder.encode(`captro-feed-cursor-v1:${secret}`));
  return crypto.subtle.importKey('raw', material, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
}
function encode(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}
function decode(text: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(text)) throw new FeedCursorError();
  return Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), character => character.charCodeAt(0));
}

export async function readFeedCursor(secret: string, token: string | undefined, binding: {
  viewer: string; scope: string; city?: string;
}, time = Date.now()): Promise<FeedCursor> {
  const expected = { viewer: binding.viewer, scope: binding.scope, city: binding.city || '' };
  if (!token) return { version: 1, ...expected, snapshot: new Date(time).toISOString(), expires: time + maxAge, boundary: null };
  // Validate before interpreting any value as a PostgREST filter.
  try {
    if (token.length > 2048) throw new FeedCursorError();
    const bytes = decode(token);
    if (bytes.length < 29) throw new FeedCursorError();
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: bytes.slice(0, 12) }, await key(secret), bytes.slice(12));
    const cursor = JSON.parse(decoder.decode(plain));
    if (cursor.version !== 1 || cursor.viewer !== expected.viewer || cursor.scope !== expected.scope
      || cursor.city !== expected.city || !validDate(cursor.snapshot) || !Number.isFinite(cursor.expires)
      || cursor.expires <= time || cursor.expires > time + maxAge + 60_000
      || Date.parse(cursor.snapshot) > time + 60_000 || !validBoundary(cursor.boundary)) throw new FeedCursorError();
    return cursor;
  } catch { throw new FeedCursorError(); }
}

export async function writeFeedCursor(secret: string, cursor: FeedCursor): Promise<string> {
  if (!validBoundary(cursor.boundary)) throw Error('FEED_CURSOR_BOUNDARY_INVALID');
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const payload = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(secret), encoder.encode(JSON.stringify(cursor)));
  const bytes = new Uint8Array(iv.length + payload.byteLength);
  bytes.set(iv); bytes.set(new Uint8Array(payload), iv.length);
  return encode(bytes);
}

export function feedBoundary(row: any): FeedBoundary {
  const value = { legacyCreatedAt: row.legacy_created_at ?? null, createdAt: row.created_at, id: row.id };
  if (!validBoundary(value)) throw Error('FEED_ROW_BOUNDARY_INVALID');
  // Preserve database microseconds; Date.toISOString would truncate them and
  // skip rows sharing the same millisecond.
  return value;
}

export function feedKeysetFilters(cursor: FeedCursor): Record<string, string> {
  const filters: Record<string, string> = { status: 'eq.active', created_at: `lte.${cursor.snapshot}` };
  const b = cursor.boundary;
  if (!b) return filters;
  if (!validBoundary(b)) throw new FeedCursorError();
  const olderCreated = `created_at.lt.${b.createdAt}`;
  const sameCreatedOlderID = `and(created_at.eq.${b.createdAt},id.lt.${b.id})`;
  filters.or = b.legacyCreatedAt === null
    ? `(and(legacy_created_at.is.null,or(${olderCreated},${sameCreatedOlderID})))`
    : `(legacy_created_at.lt.${b.legacyCreatedAt},and(legacy_created_at.eq.${b.legacyCreatedAt},or(${olderCreated},${sameCreatedOlderID})),legacy_created_at.is.null)`;
  return filters;
}

export const feedKeysetOrder = 'legacy_created_at.desc.nullslast,created_at.desc,id.desc';
