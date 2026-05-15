let cachedHomePosts: any[] = [];
let cachedAt = 0;

const MAX_HOME_POSTS = 72;

export function getCachedHomePosts() {
  return cachedHomePosts;
}

export function cacheHomePosts(posts: any[]) {
  if (!Array.isArray(posts)) return;
  cachedHomePosts = posts.slice(0, MAX_HOME_POSTS);
  cachedAt = Date.now();
}

export function getHomeCacheAgeMs() {
  return cachedAt ? Date.now() - cachedAt : Number.POSITIVE_INFINITY;
}
