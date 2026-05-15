import type { MiraMediaPlan, MiraNativeDesignProfile } from './MiraPerformance.types';

function fallbackHash(value: string) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

function planMedia(
  uri: string,
  mimeType = '',
  fileName = '',
  fileSize = 0,
  width = 0,
  height = 0,
  preset = 'balanced'
): MiraMediaPlan {
  const lowerUri = uri.toLowerCase();
  const lowerMime = mimeType.toLowerCase();
  const sourceName = fileName || uri;
  const ext = sourceName.split(/[?#]/)[0]?.split('.').pop()?.toLowerCase() || '';
  const isVideo = lowerUri.startsWith('cfstream:') || lowerMime.startsWith('video/') || ['mp4', 'mov', 'm4v', 'webm'].includes(ext);
  const isImage = lowerMime.startsWith('image/') || lowerUri.startsWith('data:image/') || ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'].includes(ext);
  const kind = isVideo ? 'video' : isImage ? 'image' : 'unknown';
  const unsafe = ['apk', 'app', 'bat', 'cmd', 'com', 'dll', 'dmg', 'exe', 'js', 'msi', 'ps1', 'sh', 'svg'].includes(ext) || lowerMime.includes('svg');
  const maxBytes = kind === 'video' ? 500 * 1024 * 1024 : 20 * 1024 * 1024;
  const sourceWidth = width > 0 ? width : kind === 'video' ? 1080 : 1440;
  const sourceHeight = height > 0 ? height : kind === 'video' ? 1920 : 1920;
  const maxLongEdge = kind === 'video' ? 1920 : preset === 'quality' ? 3000 : preset === 'compact' ? 1280 : 2200;
  const scale = Math.min(1, maxLongEdge / Math.max(1, sourceWidth, sourceHeight));
  return {
    kind,
    allowed: kind !== 'unknown' && !unsafe && fileSize <= maxBytes,
    reason: kind === 'unknown' ? 'unknown_media_type' : unsafe ? 'blocked_unsafe_file_type' : fileSize > maxBytes ? 'file_too_large' : 'ok',
    targetWidth: Math.max(1, Math.round(sourceWidth * scale)),
    targetHeight: Math.max(1, Math.round(sourceHeight * scale)),
    aspectRatio: sourceWidth / Math.max(1, sourceHeight),
    maxBytes,
    targetMimeType: kind === 'video' ? 'video/mp4' : 'image/jpeg',
    imageQuality: preset === 'quality' ? 0.92 : preset === 'compact' ? 0.84 : 0.89,
    videoBitrate: preset === 'quality' ? 12000000 : preset === 'compact' ? 5500000 : 8000000,
    targetFps: 30,
    shouldUseThumbnail: kind === 'video',
    cacheKey: fallbackHash(`${uri}|${fileName}|${Math.round(sourceWidth)}x${Math.round(sourceHeight)}|${Math.round(fileSize)}`),
  };
}

function nativeDesignProfile(): MiraNativeDesignProfile {
  return {
    runtime: 'javascript',
    platform: 'web',
    surface: '#FFFFFF',
    surfaceSoft: '#FAFAF8',
    textPrimary: '#1D2119',
    textSecondary: '#687066',
    forest: '#20361F',
    forestPressed: '#172917',
    shadowColor: '#20361F',
    shadowOpacity: 0.1,
    radiusCard: 22,
    radiusSheet: 28,
    minTouchTarget: 44,
  };
}

function makeMediaCacheKey(uri: string, width: number, height: number, preset: string) {
  return fallbackHash(`${uri}|${Math.round(width)}x${Math.round(height)}|${preset}`);
}

function scoreFeedItem(
  likes: number,
  comments: number,
  saves: number,
  shares: number,
  views: number,
  ageHours: number,
  isFollowed: boolean,
  isVideo: boolean
) {
  const engagement = (likes * 3) + (comments * 6) + (saves * 7) + (shares * 8) + Math.min(views, 5000) * 0.08;
  const recency = Math.max(0, 72 - ageHours) * 0.9;
  const relationship = isFollowed ? 18 : 0;
  const mediaBoost = isVideo ? 4 : 2;
  return engagement + recency + relationship + mediaBoost;
}

const MiraPerformance = {
  nativeRuntime: 'javascript',
  makeMediaCacheKey,
  planMedia,
  nativeDesignProfile,
  scoreFeedItem,
};

export { makeMediaCacheKey, nativeDesignProfile, planMedia, scoreFeedItem };
export default MiraPerformance;
