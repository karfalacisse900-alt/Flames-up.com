import { commerceAvailability } from './commerce.ts';
import { FeedCursorError, readFeedCursor, writeFeedCursor, type FeedCursor } from './feed-pagination.ts';

type Source = 'activity' | 'business';
type Kind = 'club' | 'event' | 'meetup' | 'offer' | 'reservation' | 'business';
type Query = (table: string, input: { select: string; filters: Record<string, string>; order?: string; limit: number }) => Promise<any[]>;
type Input = { cursor?: string; city?: string; lat?: string; lon?: string };
type Point = { latitude: number; longitude: number };
type Candidate = { source: Source; row: any; timestamp: string };
type Access = { posts: Map<string, any>; owners: Map<string, any>; blocked: Set<string> };
type Dependencies = {
  query: Query;
  access: (postIds: string[], ownerIds: string[]) => Promise<Access>;
  isActiveUser: (user: any) => boolean;
  commerce: (purchasable: any) => Promise<unknown>;
};

const types: Record<string, Kind> = {
  club: 'club', group: 'club', event: 'event', party: 'event', ticket: 'event', access_pass: 'event',
  meetup: 'meetup', offer: 'offer', deal: 'offer', booking: 'reservation', reservation: 'reservation',
};
const colors: Record<Kind, string> = {
  club: 'sage', event: 'lilac', meetup: 'navy', offer: 'sky', reservation: 'lilac', business: 'sand',
};
const icons: Record<Kind, string> = {
  club: 'people', event: 'calendar', meetup: 'people', offer: 'ticket', reservation: 'calendar', business: 'storefront',
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const listing = 'id,post_id,creator_id,creator_app_user_id,content_type,title,status,visibility,audience,city,starts_at,ends_at,expires_at,capacity,quantity_committed,created_at';
const businessListing = 'id,owner_id,name,category,paused,published,latitude,longitude,location_updated_at';
const businessDetails = businessListing + ',pickup_address,hours,avatar_url,photos';
const activityTypes = Object.keys(types);
const tableBySource = { activity: 'app_purchasables', business: 'app_businesses' };
const timeBySource = { activity: 'created_at', business: 'location_updated_at' };
const sourceRank = { activity: 1, business: 0 };
const maxBatch = 32;
const pageSize = 20;
const nearbyMiles = 25;

export class TeaInputError extends Error {}
export class TeaUnavailable extends Error {}

function scope(input: Input) {
  const city = (input.city ?? '').trim().normalize('NFC').toLowerCase();
  if (city.length > 80 || !/^[\p{L}\p{M}\p{N} .'’\-]*$/u.test(city)) throw new TeaInputError();
  const latitude = Number(input.lat);
  const longitude = Number(input.lon);
  const hasCoordinates = input.lat !== undefined || input.lon !== undefined;
  if (hasCoordinates && (!input.lat?.trim() || !input.lon?.trim() ||
    !Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180)) {
    throw new TeaInputError();
  }
  const point = hasCoordinates ? { latitude, longitude } : null;
  return { city, point, binding: JSON.stringify([city, point]) };
}

function distance(from: Point, to: Point) {
  const rad = Math.PI / 180;
  const a = Math.sin((to.latitude - from.latitude) * rad / 2) ** 2
    + Math.cos(from.latitude * rad) * Math.cos(to.latitude * rad)
    * Math.sin((to.longitude - from.longitude) * rad / 2) ** 2;
  return 3958.76 * 2 * Math.asin(Math.sqrt(Math.min(1, a)));
}

function timeMicros(value: string) {
  const fraction = value.match(/\.(\d{1,6})/)?.[1] ?? '';
  return Date.parse(value) * 1000 + Number(fraction.padEnd(6, '0').slice(3));
}

function compare(a: Candidate, b: Candidate) {
  return timeMicros(b.timestamp) - timeMicros(a.timestamp)
    || (a.row.id === b.row.id ? sourceRank[b.source] - sourceRank[a.source] : a.row.id < b.row.id ? 1 : -1);
}

function filtersFor(source: Source, cursor: FeedCursor, search: ReturnType<typeof scope>, now: string) {
  const time = timeBySource[source];
  const filters: Record<string, string> = { [time]: 'lte.' + cursor.snapshot };
  const terms: string[] = [];
  if (source === 'activity') {
    Object.assign(filters, {
      status: 'in.(active,sold_out)', visibility: 'eq.public', audience: 'in.(anyone,approval)',
      content_type: 'in.(' + activityTypes.join(',') + ')',
    });
    if (search.city) filters.city = 'ilike.' + search.city;
    terms.push('or(expires_at.is.null,expires_at.gt.' + now + ')',
      'or(content_type.not.in.(event,meetup,party),ends_at.is.null,ends_at.gt.' + now + ')');
  } else {
    filters.published = 'eq.true';
    if (search.point) {
      terms.push('latitude.gte.' + (search.point.latitude - 0.4), 'latitude.lte.' + (search.point.latitude + 0.4));
    }
  }
  if (terms.length) filters.and = '(' + terms.join(',') + ')';
  const b = cursor.boundary;
  if (b) {
    if (!b.source) throw new FeedCursorError();
    const inclusive = sourceRank[source] < sourceRank[b.source];
    filters.or = '(' + time + '.lt.' + b.createdAt + ',and(' + time + '.eq.' + b.createdAt
      + ',id.' + (inclusive ? 'lte.' : 'lt.') + b.id + '))';
  }
  return filters;
}

function businessTableAbsent(error: unknown) {
  if (!(error instanceof Error)) return false;
  const prefix = 'SUPABASE_QUERY_FAILED:app_businesses:404:';
  if (!error.message.startsWith(prefix)) return false;
  return /"code"\s*:\s*"(?:PGRST205|42P01)"/.test(error.message.slice(prefix.length));
}

function eligibility(candidate: Candidate, access: Access, deps: Dependencies, search: ReturnType<typeof scope>, now: number) {
  const { row, source } = candidate;
  if (!uuid.test(row.id)) return null;
  const owner = access.owners.get(source === 'activity' ? row.creator_id : row.owner_id);
  if (!owner || owner.is_private !== false || !deps.isActiveUser(owner)
    || access.blocked.has(owner.id) || access.blocked.has(owner.supabase_user_id)) return null;
  if (source === 'business') {
    if (row.published !== true || !['coffee_bakery', 'street_food'].includes(row.category)) return null;
    if (search.point && (typeof row.latitude !== 'number' || typeof row.longitude !== 'number'
      || distance(search.point, row) > nearbyMiles)) return null;
    return { kind: 'business' as const, status: row.paused ? 'paused' : 'listed', name: row.name };
  }
  const post = access.posts.get(row.post_id);
  if (!post || post.status !== 'active' || post.visibility !== 'public'
    || (post.user_id !== owner.supabase_user_id && post.app_user_id !== owner.id)
    || (post.app_user_id && post.app_user_id !== owner.id)
    || (post.user_id && post.user_id !== owner.supabase_user_id)
    || post.metadata?.removed_at || post.metadata?.discover_blocked_at
    || (post.metadata?.moderation_status && post.metadata.moderation_status !== 'approved')) return null;
  const kind = types[row.content_type];
  const status = commerceAvailability(row, now);
  if (!kind || row.visibility !== 'public' || !['anyone', 'approval'].includes(row.audience)
    || !['active', 'sold_out'].includes(status)
    || (search.city && row.city?.trim().normalize('NFC').toLowerCase() !== search.city)) return null;
  return { kind, status: row.capacity != null && row.quantity_committed >= row.capacity ? 'sold_out' : status, name: row.title };
}

function item(candidate: Candidate, visible: NonNullable<ReturnType<typeof eligibility>>) {
  const { source, row, timestamp } = candidate;
  return {
    id: source + ':' + row.id, kind: visible.kind, name: visible.name, status: visible.status,
    color: colors[visible.kind], icon: icons[visible.kind], timestamp,
    destination: { source, id: row.id },
  };
}

function loadAccess(rows: Candidate[], deps: Dependencies) {
  return deps.access(
    [...new Set(rows.flatMap(candidate => candidate.source === 'activity' ? [candidate.row.post_id] : []))],
    [...new Set(rows.map(candidate => candidate.source === 'activity' ? candidate.row.creator_id : candidate.row.owner_id))],
  );
}

export async function teaPage(deps: Dependencies, secret: string, viewer: string, input: Input, now = Date.now()) {
  const search = scope(input);
  const timestamp = new Date(now).toISOString();
  let cursor = await readFeedCursor(secret, input.cursor, { viewer, scope: 'tea', city: search.binding }, now);
  const items: ReturnType<typeof item>[] = [];
  let more = true;
  let businessAvailable = true;
  for (let batch = 0; batch < 3 && more && items.length < pageSize; batch += 1) {
    const fetchRows = async (source: Source) => {
      if (source === 'business' && !businessAvailable) return [];
      try {
        const rows = await deps.query(tableBySource[source], {
          select: source === 'activity' ? listing : businessListing,
          filters: filtersFor(source, cursor, search, timestamp),
          order: timeBySource[source] + '.desc,id.desc', limit: maxBatch,
        });
        return rows.map(row => ({ row, source, timestamp: row[timeBySource[source]] }));
      } catch (error) {
        if (source === 'business' && businessTableAbsent(error)) { businessAvailable = false; return []; }
        throw error;
      }
    };
    const pages = await Promise.all([fetchRows('activity'), fetchRows('business')]);
    const merged = pages.flat().sort(compare);
    const window = merged.slice(0, maxBatch);
    if (!window.length) { more = false; break; }
    const access = await loadAccess(window, deps);
    let consumed = 0;
    for (const candidate of window) {
      cursor = { ...cursor, boundary: { createdAt: candidate.timestamp, legacyCreatedAt: null,
        id: candidate.row.id, source: candidate.source } };
      consumed += 1;
      const visible = eligibility(candidate, access, deps, search, now);
      if (visible && typeof visible.name === 'string' && visible.name.trim()) items.push(item(candidate, visible));
      if (items.length === pageSize) break;
    }
    more = consumed < merged.length || pages.some(page => page.length === maxBatch);
  }
  return { items, nextCursor: more ? await writeFeedCursor(secret, cursor) : null };
}

async function linkedEvents(deps: Dependencies, club: any, now: number) {
  // Optional links are curated on the canonical club by trusted server tooling.
  const configured = club.private_config?.tea_linked_event_ids;
  const ids = Array.isArray(configured)
    ? [...new Set(configured.filter((id): id is string => typeof id === 'string' && uuid.test(id)))].slice(0, 12)
    : [];
  if (!ids.length) return [];
  const rows = await deps.query('app_purchasables', {
    select: listing, filters: { id: 'in.(' + ids.join(',') + ')', creator_id: 'eq.' + club.creator_id },
    order: 'starts_at.asc.nullslast,id.asc', limit: ids.length,
  });
  const candidates: Candidate[] = rows
    .filter(row => row.creator_id === club.creator_id && types[row.content_type] === 'event' && ids.includes(row.id))
    .map(row => ({ source: 'activity', row, timestamp: row.created_at }));
  if (!candidates.length) return [];
  const access = await loadAccess(candidates, deps);
  return candidates.flatMap(candidate => {
    const visible = eligibility(candidate, access, deps, scope({}), now);
    return visible && typeof visible.name === 'string' && visible.name.trim() ? [item(candidate, visible)] : [];
  });
}

export async function teaDetail(deps: Dependencies, source: string, id: string, now = Date.now()) {
  if ((source !== 'activity' && source !== 'business') || !uuid.test(id)) throw new TeaUnavailable();
  let row;
  try {
    [row] = await deps.query(tableBySource[source], {
      select: source === 'business' ? businessDetails : '*', filters: { id: 'eq.' + id }, limit: 1,
    });
  } catch (error) {
    if (source === 'business' && businessTableAbsent(error)) throw new TeaUnavailable();
    throw error;
  }
  if (!row) throw new TeaUnavailable();
  const candidate: Candidate = { row, source, timestamp: row[timeBySource[source]] };
  const access = await loadAccess([candidate], deps);
  const visible = eligibility(candidate, access, deps, scope({}), now);
  if (!visible) throw new TeaUnavailable();
  if (source === 'business') {
    const { owner_id, ...business } = row;
    return { item: item(candidate, visible), business };
  }
  const post = access.posts.get(row.post_id);
  const [commerce, events] = await Promise.all([
    deps.commerce(row), visible.kind === 'club' ? linkedEvents(deps, row, now) : Promise.resolve([]),
  ]);
  return {
    item: item(candidate, visible),
    post: { id: post.legacy_post_id || post.id, userId: access.owners.get(row.creator_id).id, title: visible.name },
    commerce,
    linkedEvents: events,
  };
}
