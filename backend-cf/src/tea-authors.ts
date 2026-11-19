// Only authors from the authorized Tea RPC; never a client-provided roster.
export async function teaAuthorPhotos(value: any, load: (ids: string[]) => Promise<Map<string, string | {photoURL: string; isVerified: boolean}>>) {
  const rows = Array.isArray(value) ? value : [value];
  const ids = [...new Set<string>(rows.map(row => row?.author?.id).filter(id => typeof id === 'string' && /^[a-zA-Z0-9_-]{1,120}$/.test(id)))];
  if (!ids.length) return value;
  if (ids.length > 100) throw new Error('TEA_AUTHOR_PAGE_TOO_LARGE');
  const photos = await load(ids);
  const hydrated = rows.map(row => {
    if (!row?.author || !ids.includes(row.author.id)) return row;
    const identity = photos.get(row.author.id);
    return { ...row, author: { ...row.author,
      photoURL: (typeof identity === 'string' ? identity : identity?.photoURL) || null,
      isVerified: typeof identity === 'object' && identity.isVerified === true } };
  });
  return Array.isArray(value) ? hydrated : hydrated[0];
}
