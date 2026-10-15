/** Versioned, uncropped variants. Configuration is checked before deployment. */
export const imageDeliveryVariants = [
  { id: 'captroPreviewV1', options: { width: 480, height: 854, fit: 'scale-down', metadata: 'copyright' }, neverRequireSignedURLs: false },
  { id: 'captroFeedV1', options: { width: 1080, height: 1920, fit: 'scale-down', metadata: 'copyright' }, neverRequireSignedURLs: false },
] as const;

export function uncroppedHostedImageVariant(source: string, variant: string, accountHash: string): string | null {
  if (!imageDeliveryVariants.some(value => value.id === variant) || !accountHash) return null;
  try {
    const url = new URL(source);
    // Signed/query-bearing URLs need server re-signing for a different path.
    // Leave those unchanged; never drop a token or invent an unsigned fallback.
    if (url.protocol !== 'https:' || url.hostname !== 'imagedelivery.net' || url.search || url.hash || url.username || url.password) return null;
    const parts = url.pathname.split('/').filter(Boolean);
    if (parts.length < 3 || parts[0] !== accountHash) return null;
    parts[parts.length - 1] = variant;
    url.pathname = `/${parts.join('/')}`;
    return url.toString();
  } catch { return null; }
}
