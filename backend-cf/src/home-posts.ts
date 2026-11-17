// Content identity, never caption/category keywords or whether a cover loaded.
export const activityPostTypes = [
  'club', 'group', 'event', 'meetup', 'party', 'concert', 'show', 'ticket', 'access_pass',
  'deal', 'offer', 'local_offer', 'booking', 'reservation', 'activity', 'listing',
  'business', 'place', 'guide', 'travel', 'receipt', 'invoice', 'document', 'collection',
] as const;
const excluded = new Set<string>([...activityPostTypes, 'note', 'text']);
export function isRegularHomePost(post: any): boolean {
  return !excluded.has(String(post?.post_type ?? post?.postType ?? '').trim().toLowerCase())
    && !post?.detail?.commerce && !post?.detail?.event && !post?.detail?.travel
    && !post?.detail?.document && !post?.detail?.collection;
}

// Existing FK relations provide anti-joins BEFORE LIMIT/OFFSET. A legacy post
// marked general but owning a listing is still a listing, including paused ones.
export const homePostRelations = ',home_listing:app_purchasables(),home_object:app_post_objects()';
export function homePostFilters(): Record<string, string> {
  return {
    home_listing: 'is.null', home_object: 'is.null',
    and: '(or(post_type.is.null,post_type.not.in.(' + [...excluded].join(',') + ')),or(media.neq.[],and(metadata->>image.not.is.null,metadata->>image.neq.)))',
  };
}
