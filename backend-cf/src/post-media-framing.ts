/** Additive, nondestructive framing contract. Dimensions are display-oriented. */
export function validatePostMediaFraming(value: unknown) {
  if (value == null) return null;
  const raw = value as Record<string, unknown>;
  const source = raw.sourceAspectRatio ?? raw.source_aspect_ratio;
  const display = raw.displayAspectRatio ?? raw.display_aspect_ratio;
  const x = raw.cropX ?? raw.crop_x;
  const y = raw.cropY ?? raw.crop_y;
  const mediaId = raw.mediaId ?? raw.media_id;
  if (typeof value !== 'object' || Array.isArray(value) || raw.version !== 1
    || typeof source !== 'number' || !Number.isFinite(source) || source <= 0 || source > 100
    || typeof display !== 'number' || ![0.8, 1, 0.75, 16 / 9].some(r => Math.abs(r - display) < 0.00001)
    || typeof x !== 'number' || !Number.isFinite(x) || x < 0 || x > 1
    || typeof y !== 'number' || !Number.isFinite(y) || y < 0 || y > 1
    || (mediaId != null && (typeof mediaId !== 'string' || !/^[a-f0-9]{64}$/.test(mediaId)))) {
    throw new Error('Invalid media framing. Review the crop before publishing.');
  }
  return { version: 1, sourceAspectRatio: source, displayAspectRatio: display,
    cropX: x, cropY: y, ...(mediaId ? { mediaId } : {}) };
}
