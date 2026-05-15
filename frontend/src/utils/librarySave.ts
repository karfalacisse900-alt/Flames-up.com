import api from '../api/client';

export const DEFAULT_LIBRARY_COLLECTION = 'My Library';

export function cleanCollectionName(value?: string | null) {
  const cleaned = String(value || '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 36);
  return cleaned || DEFAULT_LIBRARY_COLLECTION;
}

export async function savePostToCollection(postId: string, collection?: string | null) {
  const name = cleanCollectionName(collection);
  try {
    return await api.post(`/library/save/${postId}`, { collection: name });
  } catch {
    return api.post('/bookmarks', { post_id: postId, collection: name });
  }
}

export async function removePostFromLibrary(postId: string) {
  try {
    return await api.delete(`/library/save/${postId}`);
  } catch {
    return api.delete(`/bookmarks/${postId}`);
  }
}
