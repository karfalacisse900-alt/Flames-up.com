export type CallMode = 'call' | 'live';
export type CallRole = 'host' | 'audience';

type CallHrefOptions = {
  currentUserId?: string | null;
  peerId?: string | null;
  peerName?: string | null;
  peerAvatar?: string | null;
  mode?: CallMode;
  role?: CallRole;
};

function cleanChannelPart(value?: string | null): string {
  return String(value || '')
    .trim()
    .replace(/[^a-zA-Z0-9_ -]/g, '_')
    .replace(/\s+/g, '_')
    .slice(0, 28);
}

export function buildCallChannel(currentUserId?: string | null, peerId?: string | null): string {
  const ids = [cleanChannelPart(currentUserId), cleanChannelPart(peerId)].filter(Boolean).sort();
  const base = ids.length === 2 ? ids.join('_') : cleanChannelPart(peerId) || 'preview';
  return `flames_${base}`.slice(0, 63);
}

export function buildAgoraCallHref({
  currentUserId,
  peerId,
  peerName,
  peerAvatar,
  mode = 'call',
  role = 'host',
}: CallHrefOptions): string {
  const channel = encodeURIComponent(buildCallChannel(currentUserId, peerId));
  const params = new URLSearchParams({
    peerId: peerId || '',
    peerName: peerName || 'Video call',
    peerAvatar: peerAvatar || '',
    mode,
    role,
  });
  return `/call/${channel}?${params.toString()}`;
}
