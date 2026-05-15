const noteCache = new Map<string, any>();
const noteCommentsCache = new Map<string, any[]>();

export function cacheNoteForDetail(note: any) {
  const id = String(note?.id || note?.note_id || '');
  if (!id) return;
  noteCache.set(id, {
    ...note,
    id,
  });
}

export function cacheNotesForDetail(notes: any[]) {
  notes.forEach(cacheNoteForDetail);
}

export function getCachedNoteForDetail(id?: string | null) {
  if (!id) return null;
  return noteCache.get(String(id)) || null;
}

export function cacheNoteCommentsForDetail(noteId: string | null | undefined, comments: any[]) {
  if (!noteId) return;
  noteCommentsCache.set(String(noteId), Array.isArray(comments) ? comments : []);
}

export function getCachedNoteCommentsForDetail(noteId?: string | null) {
  if (!noteId) return null;
  return noteCommentsCache.has(String(noteId)) ? noteCommentsCache.get(String(noteId)) || [] : null;
}
