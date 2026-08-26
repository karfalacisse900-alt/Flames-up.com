const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function cleanCursorDate(value) {
  const text = String(value || '').trim();
  if (!text || text.length > 80) return '';
  const milliseconds = Date.parse(text);
  return Number.isFinite(milliseconds) ? new Date(milliseconds).toISOString() : '';
}

function cleanCursorId(value) {
  const text = String(value || '').trim().toLowerCase();
  return UUID_PATTERN.test(text) ? text : '';
}

function encodeBase64Url(value) {
  const bytes = new TextEncoder().encode(value);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function decodeBase64Url(value) {
  const normalized = String(value || '').replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
  const binary = atob(padded);
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

export function normalizeAuraCommunityCity(value) {
  const normalized = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const compact = normalized.replace(/\s+/g, '');
  const newYorkCityAliases = new Set([
    'nyc',
    'newyork',
    'newyorkcity',
    'newyorkny',
    'newyorkcityny',
    'manhattan',
    'manhattanny',
    'brooklyn',
    'brooklynny',
    'bronx',
    'bronxny',
    'queens',
    'queensny',
    'statenisland',
    'statenislandny',
  ]);
  return newYorkCityAliases.has(compact) ? 'new york city' : normalized;
}

export function encodeAuraCommunityFeedCursor(cursor) {
  const createdAt = cleanCursorDate(cursor?.createdAt);
  const id = cleanCursorId(cursor?.id);
  if (!createdAt || !id) return '';
  return encodeBase64Url(JSON.stringify({ version: 1, created_at: createdAt, id }));
}

export function decodeAuraCommunityFeedCursor(value) {
  const encoded = String(value || '').trim();
  if (!encoded || encoded.length > 512 || !/^[A-Za-z0-9_-]+$/.test(encoded)) return null;
  try {
    const payload = JSON.parse(decodeBase64Url(encoded));
    if (Number(payload?.version) !== 1) return null;
    const createdAt = cleanCursorDate(payload?.created_at);
    const id = cleanCursorId(payload?.id);
    return createdAt && id ? { createdAt, id } : null;
  } catch {
    return null;
  }
}

export function auraCommunityFeedCursorFilter(cursor) {
  const createdAt = cleanCursorDate(cursor?.createdAt);
  const id = cleanCursorId(cursor?.id);
  if (!createdAt || !id) return '';
  return `(created_at.lt.${createdAt},and(created_at.eq.${createdAt},id.lt.${id}))`;
}

export function auraCommunityFeedRowCursor(row) {
  const createdAt = cleanCursorDate(row?.created_at);
  const id = cleanCursorId(row?.id);
  return createdAt && id ? { createdAt, id } : null;
}

export async function collectAuraCommunityCursorPage(options) {
  const limit = Math.max(1, Math.min(50, Math.trunc(Number(options?.limit) || 30)));
  const chunkSize = Math.max(limit, Math.min(300, Math.trunc(Number(options?.chunkSize) || 100)));
  let scanCursor = options?.cursor || null;
  const items = [];

  for (;;) {
    const rows = await options.readChunk(scanCursor, chunkSize);
    if (!Array.isArray(rows) || rows.length === 0) {
      return { items, nextCursor: null, hasMore: false };
    }

    const projected = await options.projectVisible(rows);
    const itemBySourceId = new Map(
      (Array.isArray(projected) ? projected : [])
        .filter((entry) => entry && typeof entry.sourceId === 'string' && entry.sourceId)
        .map((entry) => [entry.sourceId, entry.item])
    );

    for (let index = 0; index < rows.length; index += 1) {
      const rowCursor = options.rowCursor(rows[index]);
      if (!rowCursor) throw new Error('AURA_COMMUNITY_CURSOR_ROW_INVALID');
      scanCursor = rowCursor;
      const sourceId = cleanCursorId(rows[index]?.id);
      if (!sourceId || !itemBySourceId.has(sourceId)) continue;
      items.push(itemBySourceId.get(sourceId));
      if (items.length === limit) {
        return {
          items,
          nextCursor: scanCursor,
          hasMore: index < rows.length - 1 || rows.length === chunkSize,
        };
      }
    }

    if (rows.length < chunkSize) {
      return { items, nextCursor: null, hasMore: false };
    }
  }
}
