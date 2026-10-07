// Version 1 artwork metadata. Source media is never rewritten by this feature.
export function validateMediaWritingOverlays(value: unknown, mediaCount: number): any[] {
  const raw = Array.isArray(value) ? value : [];
  const seen = new Set<number>();
  return raw.filter((item) => item?.type === 'media_writing').map((item) => {
    const index = item.mediaIndex ?? item.media_index;
    const w = item.writing;
    const version = w?.schemaVersion ?? w?.schema_version;
    const ratio = w?.sourceAspectRatio ?? w?.source_aspect_ratio;
    const finite = (v: unknown, min: number, max: number) => typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;
    const count = typeof w?.text === 'string' ? [...new Intl.Segmenter('en', { granularity: 'grapheme' }).segment(w.text)].length : 0;
    if (!Number.isInteger(index) || index < 0 || index >= mediaCount || seen.has(index)
      || version !== 1 || typeof w?.text !== 'string' || !w.text.trim() || count > 80
      || w.text.split(/\r\n|\r|\n/).length > 4 || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(w.text)
      || !['bold', 'clean', 'editorial'].includes(w.style)
      || !['left', 'center', 'right'].includes(w.alignment)
      || !['white', 'black', 'green', 'cream'].includes(w.color)
      || !['small', 'medium', 'large'].includes(w.size)
      || typeof w.readability !== 'boolean'
      || !finite(w.x, 0, 1) || !finite(w.y, 0, 1) || !finite(w.width, 0.2, 0.9)
      || !finite(ratio, 0.05, 20)) {
      throw new Error('Check your media writing: use a short phrase and valid placement for each media item.');
    }
    seen.add(index);
    return { type: 'media_writing', mediaIndex: index, writing: {
      schemaVersion: 1, text: w.text, style: w.style, alignment: w.alignment,
      color: w.color, readability: w.readability, x: w.x, y: w.y, width: w.width,
      size: w.size, sourceAspectRatio: ratio,
    } };
  });
}
