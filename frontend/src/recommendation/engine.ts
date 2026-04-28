import {
  RecommendationContext,
  RecommendationItem,
  RecommendationOptions,
} from './types';
import { rankWithFallback } from './fallbackRanker';

type NativeRecommendationEngine = {
  rankFeed: (payloadJson: string) => string;
};

declare global {
  // Installed by native C++ JSI engine when available.
  // eslint-disable-next-line no-var
  var __FlamesRecommendationEngine: NativeRecommendationEngine | undefined;
}

function tryNativeRank(
  items: RecommendationItem[],
  ctx: RecommendationContext,
  options?: RecommendationOptions
): RecommendationItem[] | null {
  const nativeEngine = global.__FlamesRecommendationEngine;
  if (!nativeEngine?.rankFeed) return null;

  try {
    const payload = JSON.stringify({ items, context: ctx, options });
    const output = nativeEngine.rankFeed(payload);
    const rankedIds = JSON.parse(output) as string[];
    const map = new Map(items.map((item) => [item.id, item]));
    const ranked = rankedIds.map((id) => map.get(id)).filter(Boolean) as RecommendationItem[];
    if (ranked.length > 0) return ranked;
    return null;
  } catch {
    return null;
  }
}

export function rankFeed(
  items: RecommendationItem[],
  context: RecommendationContext,
  options?: RecommendationOptions
): RecommendationItem[] {
  const nativeRanked = tryNativeRank(items, context, options);
  if (nativeRanked) return nativeRanked;
  return rankWithFallback(items, context, options);
}
