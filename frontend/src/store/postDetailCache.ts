const postCache = new Map<string, any>();
const postCommentsCache = new Map<string, any[]>();

export function cachePostForDetail(post: any) {
  const id = String(post?.id || post?.post_id || '');
  if (!id) return;
  postCache.set(id, {
    ...post,
    id,
    user_full_name: post?.user_full_name || post?.full_name,
    user_username: post?.user_username || post?.username,
    user_profile_image: post?.user_profile_image || post?.profile_image,
  });
}

export function cachePostsForDetail(posts: any[]) {
  posts.forEach(cachePostForDetail);
}

export function getCachedPostForDetail(id?: string | null) {
  if (!id) return null;
  return postCache.get(String(id)) || null;
}

export function cachePostCommentsForDetail(postId: string | null | undefined, comments: any[]) {
  if (!postId) return;
  postCommentsCache.set(String(postId), Array.isArray(comments) ? comments : []);
}

export function getCachedPostCommentsForDetail(postId?: string | null) {
  if (!postId) return null;
  return postCommentsCache.has(String(postId)) ? postCommentsCache.get(String(postId)) || [] : null;
}
