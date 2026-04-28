import {
  RecommendationContext,
  RecommendationItem,
  RecommendationOptions,
} from './types';

type Scored = {
  item: RecommendationItem;
  baseScore: number;
  qualityScore: number;
  recencyScore: number;
  affinityScore: number;
  proximityScore: number;
};

const Z_80 = 1.281551565545;

function clamp01(v: number): number {
  if (v < 0) return 0;
  if (v > 1) return 1;
  return v;
}

function wilsonLowerBound(positive: number, total: number): number {
  if (total <= 0) return 0;
  const pHat = positive / total;
  const z2 = Z_80 * Z_80;
  const denom = 1 + z2 / total;
  const center = pHat + z2 / (2 * total);
  const margin = Z_80 * Math.sqrt((pHat * (1 - pHat) + z2 / (4 * total)) / total);
  return clamp01((center - margin) / denom);
}

function hoursSince(createdAtMs: number, nowMs: number): number {
  return Math.max(0, (nowMs - createdAtMs) / (1000 * 60 * 60));
}

function recencyDecay(ageHours: number, halfLifeHours: number): number {
  return Math.pow(2, -ageHours / Math.max(1, halfLifeHours));
}

function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

function affinity(item: RecommendationItem, interests: string[]): number {
  if (interests.length === 0) return 0.35;
  const corpus = `${item.category || ''} ${item.location || ''} ${item.content || ''}`;
  const tokens = new Set(tokenize(corpus));
  let hits = 0;
  for (const interest of interests) {
    const t = interest.toLowerCase().trim();
    if (!t) continue;
    if (tokens.has(t)) hits += 1;
  }
  const ratio = hits / Math.max(1, interests.length);
  return clamp01(0.2 + ratio * 0.8);
}

function toRad(v: number): number {
  return (v * Math.PI) / 180;
}

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return 6371 * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
}

function proximity(item: RecommendationItem, ctx: RecommendationContext): number {
  if (
    ctx.userLat === undefined ||
    ctx.userLng === undefined ||
    item.lat === undefined ||
    item.lng === undefined
  ) {
    return 0.45;
  }
  const distance = haversineKm(ctx.userLat, ctx.userLng, item.lat, item.lng);
  const score = Math.exp(-distance / 20);
  return clamp01(score);
}

function similarity(a: RecommendationItem, b: RecommendationItem): number {
  let score = 0.05;
  if (a.authorId && b.authorId && a.authorId === b.authorId) score += 0.65;
  if (a.category && b.category && a.category === b.category) score += 0.2;

  const aLoc = (a.location || '').toLowerCase();
  const bLoc = (b.location || '').toLowerCase();
  if (aLoc && bLoc && (aLoc.includes(bLoc) || bLoc.includes(aLoc))) score += 0.12;

  return clamp01(score);
}

function scoreItem(
  item: RecommendationItem,
  ctx: RecommendationContext,
  halfLifeHours: number
): Scored {
  const interactions = item.likes + item.comments * 2 + item.shares * 3 + item.saves * 2;
  const views = Math.max(item.impressions, interactions + 20);
  const qualityScore = wilsonLowerBound(Math.min(interactions, views), views);
  const ageHours = hoursSince(item.createdAtMs, ctx.nowMs);
  const recencyScore = recencyDecay(ageHours, halfLifeHours);
  const affinityScore = affinity(item, ctx.interests);
  const proximityScore = proximity(item, ctx);

  // Weighted fusion: quality + recency + personalization + locality.
  const baseScore =
    qualityScore * 0.42 +
    recencyScore * 0.28 +
    affinityScore * 0.2 +
    proximityScore * 0.1;

  return { item, baseScore, qualityScore, recencyScore, affinityScore, proximityScore };
}

export function rankWithFallback(
  items: RecommendationItem[],
  ctx: RecommendationContext,
  options?: RecommendationOptions
): RecommendationItem[] {
  if (items.length <= 1) return items;

  const maxItems = options?.maxItems ?? items.length;
  const lambda = options?.lambda ?? 0.8;
  const halfLifeHours = options?.halfLifeHours ?? 36;

  const candidates = items.map((item) => scoreItem(item, ctx, halfLifeHours));
  const selected: Scored[] = [];
  const remaining = [...candidates];

  while (selected.length < maxItems && remaining.length > 0) {
    let bestIdx = 0;
    let bestValue = -Infinity;

    for (let i = 0; i < remaining.length; i += 1) {
      const candidate = remaining[i];
      let maxSim = 0;
      for (const s of selected) {
        const sim = similarity(candidate.item, s.item);
        if (sim > maxSim) maxSim = sim;
      }

      const mmr = lambda * candidate.baseScore - (1 - lambda) * maxSim;
      if (mmr > bestValue) {
        bestValue = mmr;
        bestIdx = i;
      }
    }

    selected.push(remaining[bestIdx]);
    remaining.splice(bestIdx, 1);
  }

  return selected.map((s) => s.item);
}
