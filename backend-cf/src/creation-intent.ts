export type CreationIntent = 'want_to' | 'looking_for' | 'concern';

export function normalizeCreationIntent(value: unknown): CreationIntent | null {
  return value === 'want_to' || value === 'looking_for' || value === 'concern' ? value : null;
}

/** Same extended-grapheme-cluster limit as Swift Character, including emoji/IME text. */
export function compositionCharacterCount(value: string): number {
  return Array.from(new Intl.Segmenter('und', { granularity: 'grapheme' }).segment(value)).length;
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
  return Array.from(first.trim()).slice(0, 180).join('');
}

