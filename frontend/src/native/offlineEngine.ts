export type OfflineFeedItem = {
  id: string;
  authorId?: string;
  createdAtMs?: number;
  likes?: number;
  comments?: number;
  saves?: number;
  shares?: number;
  views?: number;
  hasMedia?: boolean;
  isSaved?: boolean;
  isFollowing?: boolean;
  original?: any;
};

export type OfflineFeedOptions = {
  nowMs?: number;
  limit?: number;
};

type NativeOfflineEngine = {
  buildOfflineQueue?: (items: OfflineFeedItem[], options?: OfflineFeedOptions) => string[] | string;
};

declare global {
  // Installed by the native C++ JSI offline engine when bundled in a dev/prod build.
  var __FlamesOfflineEngine: NativeOfflineEngine | undefined;
}

function parseNativeIds(output: string[] | string | undefined): string[] | null {
  if (!output) return null;
  if (Array.isArray(output)) return output.map(String);
  try {
    const parsed = JSON.parse(output);
    if (Array.isArray(parsed)) return parsed.map(String);
  } catch {}
  return null;
}

function ageHours(createdAtMs: number, nowMs: number): number {
  return Math.max(0, (nowMs - createdAtMs) / (1000 * 60 * 60));
}

function scoreOfflineItem(item: OfflineFeedItem, nowMs: number): number {
  const engagement =
    Number(item.likes || 0) * 3 +
    Number(item.comments || 0) * 5 +
    Number(item.saves || 0) * 5 +
    Number(item.shares || 0) * 6 +
    Math.log10(1 + Number(item.views || 0)) * 8;
  const recency = Math.pow(2, -ageHours(Number(item.createdAtMs || nowMs), nowMs) / 96) * 45;
  const savedBoost = item.isSaved ? 85 : 0;
  const followBoost = item.isFollowing ? 28 : 0;
  const mediaBoost = item.hasMedia ? 12 : 0;
  return savedBoost + followBoost + mediaBoost + engagement + recency;
}

export function buildOfflineFeed(items: OfflineFeedItem[], options: OfflineFeedOptions = {}): OfflineFeedItem[] {
  const nativeIds = (() => {
    try {
      return parseNativeIds(global.__FlamesOfflineEngine?.buildOfflineQueue?.(items, options));
    } catch {
      return null;
    }
  })();

  if (nativeIds?.length) {
    const byId = new Map(items.map((item) => [String(item.id), item]));
    return nativeIds.map((id) => byId.get(id)).filter(Boolean) as OfflineFeedItem[];
  }

  const nowMs = options.nowMs || Date.now();
  const limit = Math.max(1, Math.min(options.limit || items.length, items.length));
  const seen = new Set<string>();

  return items
    .filter((item) => {
      const id = String(item.id || '');
      if (!id || seen.has(id)) return false;
      seen.add(id);
      return true;
    })
    .map((item) => ({ item, score: scoreOfflineItem(item, nowMs) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map((entry) => entry.item);
}
