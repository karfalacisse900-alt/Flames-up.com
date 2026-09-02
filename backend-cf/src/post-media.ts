export const DIRECT_VIDEO_MAX_BYTES = 200_000_000;
export const POST_VIDEO_MAX_SECONDS = 60;

export function streamProcessingState(video: { readyToStream?: boolean; status?: { state?: string; errorReasonCode?: string } } | null | undefined): 'ready' | 'processing' | 'failed' {
  const state = String(video?.status?.state || '').toLowerCase();
  if (state === 'error' || state === 'failed' || video?.status?.errorReasonCode) return 'failed';
  return video?.readyToStream === true && state === 'ready' ? 'ready' : 'processing';
}

export function streamUID(reference: string): string {
  const clean = String(reference || '').trim();
  if (clean.startsWith('cfstream:')) {
    const uid = clean.slice('cfstream:'.length);
    return /^[a-zA-Z0-9_-]{6,128}$/.test(uid) ? uid : '';
  }
  try {
    const url = new URL(clean);
    const host = url.hostname.toLowerCase();
    if (!['videodelivery.net', 'cloudflarestream.com'].some((domain) => host === domain || host.endsWith(`.${domain}`))) return '';
    const uid = url.pathname.split('/').filter(Boolean)[0] || '';
    return /^[a-zA-Z0-9_-]{6,128}$/.test(uid) ? uid : '';
  } catch {
    return '';
  }
}

export function orderPostMediaAssets<T extends { id: string }>(assets: T[], requestedIds: string[]): T[] {
  const byId = new Map(assets.map((asset) => [asset.id, asset]));
  return requestedIds.flatMap((id) => {
    const asset = byId.get(id);
    return asset ? [asset] : [];
  });
}
