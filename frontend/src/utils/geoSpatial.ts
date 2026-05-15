type LatLng = { lat: number; lng: number };

export type PlaceLike = {
  place_id?: string;
  id?: string;
  name?: string;
  lat?: number | string;
  lng?: number | string;
  rating?: number;
  user_ratings_total?: number;
  vicinity?: string;
  types?: string[];
  [key: string]: any;
};

export type PlaceMarkerNode = {
  kind: 'place';
  id: string;
  lat: number;
  lng: number;
  count: 1;
  place: PlaceLike;
};

export type PlaceClusterNode = {
  kind: 'cluster';
  id: string;
  lat: number;
  lng: number;
  count: number;
  places: PlaceLike[];
  label: string;
};

export type GeoNode = PlaceMarkerNode | PlaceClusterNode;

type NativeGeoSearch = {
  rankPlaceIds?: (
    places: PlaceLike[],
    query: string,
    userLat?: number,
    userLng?: number,
    limit?: number
  ) => string[] | string;
};

declare global {
  // Installed by the native C++ JSI geospatial engine when available.
  var __FlamesGeoSearch: NativeGeoSearch | undefined;
}

const EARTH_RADIUS_KM = 6371;
const WORLD_EXTENT_METERS = 20037508.34;

function toRad(value: number): number {
  return (value * Math.PI) / 180;
}

function toNumber(value: number | string | undefined): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string') {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function normalizeText(value: string): string {
  return value.trim().toLowerCase();
}

function toMercatorMeters(lat: number, lng: number): { x: number; y: number } {
  const x = (lng * WORLD_EXTENT_METERS) / 180;
  const y =
    (Math.log(Math.tan(((90 + lat) * Math.PI) / 360)) / (Math.PI / 180)) *
    (WORLD_EXTENT_METERS / 180);
  return { x, y };
}

function fromMercatorMeters(x: number, y: number): LatLng {
  const lng = (x / WORLD_EXTENT_METERS) * 180;
  const lat =
    (180 / Math.PI) *
    (2 * Math.atan(Math.exp((y / WORLD_EXTENT_METERS) * Math.PI)) - Math.PI / 2);
  return { lat, lng };
}

function resolveCellSizeMeters(zoom: number, baseAtZoom14 = 180): number {
  const boundedZoom = Math.max(4, Math.min(20, zoom));
  const scale = Math.pow(2, 14 - boundedZoom);
  return Math.max(40, baseAtZoom14 * scale);
}

function getPlaceId(place: PlaceLike, index: number): string {
  return String(place.place_id || place.id || `place-${index}`);
}

function parseNativeIds(value: string[] | string | undefined): string[] | null {
  if (!value) return null;
  if (Array.isArray(value)) return value.map(String);
  try {
    const parsed = JSON.parse(value);
    if (Array.isArray(parsed)) return parsed.map(String);
  } catch {}
  return null;
}

function tokenize(value: string): string[] {
  return normalizeText(value)
    .split(/[\s,.-]+/)
    .map((v) => v.trim())
    .filter(Boolean);
}

export function haversineKm(a: LatLng, b: LatLng): number {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const aa =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(a.lat)) *
      Math.cos(toRad(b.lat)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(aa), Math.sqrt(1 - aa));
  return EARTH_RADIUS_KM * c;
}

export function rankPlacesByQuery<T extends PlaceLike>(
  places: T[],
  query: string,
  userLoc?: LatLng,
  limit = 120
): T[] {
  try {
    const ids = parseNativeIds(global.__FlamesGeoSearch?.rankPlaceIds?.(
      places,
      query,
      userLoc?.lat,
      userLoc?.lng,
      limit
    ));
    if (ids?.length) {
      const byId = new Map(places.map((place, index) => [getPlaceId(place, index), place]));
      return ids.map((id) => byId.get(id)).filter(Boolean) as T[];
    }
  } catch {}

  const normalizedQuery = normalizeText(query);
  if (!normalizedQuery) return places.slice(0, limit);
  const tokens = tokenize(normalizedQuery);

  const scored = places
    .map((place) => {
      const name = normalizeText(place.name || '');
      const vicinity = normalizeText(place.vicinity || '');
      const typeText = normalizeText((place.types || []).join(' '));
      const haystack = `${name} ${vicinity} ${typeText}`;

      let textScore = 0;
      if (name.startsWith(normalizedQuery)) textScore += 80;
      if (name.includes(normalizedQuery)) textScore += 55;
      if (vicinity.includes(normalizedQuery)) textScore += 30;
      if (typeText.includes(normalizedQuery)) textScore += 25;

      for (const token of tokens) {
        if (name.includes(token)) textScore += 18;
        else if (haystack.includes(token)) textScore += 10;
      }

      const rating = Number(place.rating || 0);
      const ratingsCount = Number(place.user_ratings_total || 0);
      const qualityScore = Math.max(0, rating * 5) + Math.log10(1 + ratingsCount) * 5;

      let proximityScore = 0;
      if (userLoc) {
        const lat = toNumber(place.lat);
        const lng = toNumber(place.lng);
        if (lat !== null && lng !== null) {
          const km = haversineKm(userLoc, { lat, lng });
          proximityScore = Math.max(0, 30 - km * 2.2);
        }
      }

      return {
        place,
        score: textScore + qualityScore + proximityScore,
      };
    })
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score);

  if (scored.length > 0) {
    return scored.slice(0, limit).map((item) => item.place);
  }
  return places.slice(0, limit);
}

export function clusterPlaces<T extends PlaceLike>(places: T[], zoom = 14): GeoNode[] {
  if (!places.length) return [];

  const stepMeters = resolveCellSizeMeters(zoom);
  const buckets = new Map<string, T[]>();

  places.forEach((place) => {
    const lat = toNumber(place.lat);
    const lng = toNumber(place.lng);
    if (lat === null || lng === null) return;
    const { x, y } = toMercatorMeters(lat, lng);
    const gx = Math.floor(x / stepMeters);
    const gy = Math.floor(y / stepMeters);
    const key = `${gx}:${gy}`;
    const bucket = buckets.get(key);
    if (bucket) bucket.push(place);
    else buckets.set(key, [place]);
  });

  const nodes: GeoNode[] = [];
  let index = 0;

  for (const bucketPlaces of buckets.values()) {
    if (bucketPlaces.length === 1) {
      const p = bucketPlaces[0];
      const lat = toNumber(p.lat);
      const lng = toNumber(p.lng);
      if (lat === null || lng === null) continue;
      nodes.push({
        kind: 'place',
        id: getPlaceId(p, index++),
        lat,
        lng,
        count: 1,
        place: p,
      });
      continue;
    }

    let xTotal = 0;
    let yTotal = 0;
    bucketPlaces.forEach((place) => {
      const lat = toNumber(place.lat) || 0;
      const lng = toNumber(place.lng) || 0;
      const { x, y } = toMercatorMeters(lat, lng);
      xTotal += x;
      yTotal += y;
    });

    const center = fromMercatorMeters(xTotal / bucketPlaces.length, yTotal / bucketPlaces.length);
    const topNames = bucketPlaces
      .map((p) => p.name || '')
      .filter(Boolean)
      .slice(0, 2)
      .join(' • ');

    nodes.push({
      kind: 'cluster',
      id: `cluster-${index++}`,
      lat: center.lat,
      lng: center.lng,
      count: bucketPlaces.length,
      places: bucketPlaces,
      label: topNames || `${bucketPlaces.length} places`,
    });
  }

  return nodes.sort((a, b) => b.count - a.count);
}

