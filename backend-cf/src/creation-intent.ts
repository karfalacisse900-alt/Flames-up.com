export type CreationIntent = 'want_to' | 'looking_for' | 'concern';

export function normalizeCreationIntent(value: unknown): CreationIntent | null {
  return value === 'want_to' || value === 'looking_for' || value === 'concern' ? value : null;
}

/** Same extended-grapheme-cluster limit as Swift Character, including emoji/IME text. */
export function compositionCharacterCount(value: string): number {
  return Array.from(new Intl.Segmenter('und', { granularity: 'grapheme' }).segment(value)).length;
}

// Creation-only validation. Never applied to stored records, reads or updates.
export function newMediaStampWritingError(input: {
  mediaCount: number; postType: string; title: string; caption: string;
}): { code: string; detail: string } | null {
  if (input.mediaCount <= 0) return null;
  if (compositionCharacterCount(input.title) > 60) {
    return { code: 'MEDIA_TITLE_TOO_LONG', detail: 'Keep media titles within 60 characters. Your draft was not published.' };
  }
  if (['general', 'social', 'moment', 'place', 'check_in'].includes(input.postType)
      && compositionCharacterCount(input.caption) > 220) {
    return { code: 'MEDIA_CAPTION_TOO_LONG', detail: 'Keep media captions within 220 characters. Your draft was not published.' };
  }
  return null;
}

/** Plain native/React text, not HTML. Preserve punctuation; normalize only controls/newlines. */
export function compositionBody(value: unknown): string {
  return String(value ?? '')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, ' ')
    .replace(/\r\n?/g, '\n').trim();
}

export function normalizeCreationTime(value: unknown, intent: CreationIntent | null): string | null {
  if (!intent || intent === 'concern' || value == null || value === '') return null;
  if (typeof value !== 'string' || value.length > 40 || !/^\d{4}-\d{2}-\d{2}T/.test(value)) {
    throw new Error('Choose a valid time.');
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) throw new Error('Choose a valid time.');
  return date.toISOString();
}

/** Legacy feed cards require a headline. This is an index/display label, never inserted into body. */
export function compositionHeadline(body: string): string {
  const first = body.trim().split('\n').find(line => line.trim()) || '';
  // Legacy headline cleaners limit UTF-16 units. Stay within that budget without
  // splitting surrogate pairs or grapheme clusters (Postgres rejects lone surrogates).
  let headline = '';
  for (const { segment } of new Intl.Segmenter('und', { granularity: 'grapheme' }).segment(first.trim())) {
    if (headline.length + segment.length > 180) break;
    headline += segment;
  }
  return headline;
}
