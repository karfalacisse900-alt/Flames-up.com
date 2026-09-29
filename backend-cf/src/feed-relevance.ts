// Bounded, deterministic ranking over an already-authorized feed page. OpenAI
// topics are calculated once after a public text post is created; no model is
// called while a reader scrolls and no financial or attendance fields are made
// up by this ranking layer.
type FeedPost = {
  id?: string;
  category?: string;
  post_type?: string;
  title?: string;
  content?: string;
  tags_json?: unknown;
  feed_ai_topics?: unknown;
  is_following?: boolean;
  detail?: any;
};

function strings(value: unknown): string[] {
  if (Array.isArray(value)) return value.filter((item): item is string => typeof item === 'string');
  if (typeof value !== 'string') return [];
  try {
    const parsed = JSON.parse(value);
    if (Array.isArray(parsed)) return strings(parsed);
  } catch { /* A plain interest string is also valid. */ }
  return value.split(',').map((item) => item.trim()).filter(Boolean);
}

function words(value: string): Set<string> {
  return new Set((value.toLowerCase().match(/[\p{L}\p{N}]{3,}/gu) || []).slice(0, 120));
}

function unavailable(post: FeedPost): boolean {
  const commerce = post.detail?.commerce || {};
  const event = post.detail?.event || {};
  const states = [commerce.status, commerce.availability, commerce.purchasable?.status, event.status]
    .filter((value): value is string => typeof value === 'string')
    .map((value) => value.toLowerCase());
  return states.some((value) => ['cancelled', 'canceled', 'expired', 'sold_out', 'sold out', 'unavailable'].includes(value));
}

function relevance(post: FeedPost, interests: Set<string>): number {
  if (unavailable(post)) return -3;
  const ai = words(strings(post.feed_ai_topics).join(' '));
  const ordinary = words([
    post.category || '', post.post_type || '', post.title || '', post.content || '', strings(post.tags_json).join(' '),
  ].join(' '));
  let aiMatches = 0;
  let ordinaryMatches = 0;
  for (const word of interests) {
    if (ai.has(word)) aiMatches += 1;
    else if (ordinary.has(word)) ordinaryMatches += 1;
  }
  return Math.min(4, aiMatches * 1.4 + ordinaryMatches * 0.65) + (post.is_following ? 0.25 : 0);
}

export function rankVisibleFeedWindow<T extends FeedPost>(authorizedPosts: T[], rawInterests: unknown): T[] {
  const interests = words(strings(rawInterests).join(' '));
  if (interests.size === 0 || authorizedPosts.length < 2) return authorizedPosts;
  const remaining = authorizedPosts.map((post) => ({ post, score: relevance(post, interests) }));
  const result: T[] = [];
  let previousType = '';
  while (remaining.length) {
    let best = 0;
    let bestValue = -Infinity;
    for (let index = 0; index < Math.min(4, remaining.length); index += 1) {
      const item = remaining[index];
      const type = item.post.post_type || item.post.category || '';
      const repeatPenalty = previousType && type === previousType ? 0.7 : 0;
      const value = item.score - index * 0.55 - repeatPenalty;
      if (value > bestValue) { best = index; bestValue = value; }
    }
    const [selected] = remaining.splice(best, 1);
    result.push(selected.post);
    previousType = selected.post.post_type || selected.post.category || '';
  }
  return result;
}
