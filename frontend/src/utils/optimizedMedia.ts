import { Image as ExpoImage } from 'expo-image';
import { extractStreamUid, getStreamPlaybackInfo, isCFStreamVideo } from './mediaUpload';

export type OptimizedImagePreset = 'avatar' | 'thumb' | 'feed' | 'detail' | 'cover' | 'music' | 'original';

type PostLike = {
  image?: unknown;
  images?: unknown;
  media_types?: unknown;
  user_profile_image?: unknown;
};

const IMAGE_WIDTHS: Record<OptimizedImagePreset, number> = {
  avatar: 160,
  thumb: 420,
  feed: 1080,
  detail: 1600,
  cover: 1920,
  music: 520,
  original: 0,
};

const IMAGE_QUALITIES: Record<OptimizedImagePreset, number> = {
  avatar: 84,
  thumb: 84,
  feed: 88,
  detail: 90,
  cover: 90,
  music: 86,
  original: 90,
};

const STREAM_THUMB_HEIGHTS: Record<OptimizedImagePreset, number> = {
  avatar: 160,
  thumb: 420,
  feed: 720,
  detail: 960,
  cover: 960,
  music: 420,
  original: 720,
};

function parseImages(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((item) => String(item || '').trim()).filter(Boolean);
  if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) return parsed.map((item) => String(item || '').trim()).filter(Boolean);
    } catch {}
    return [value.trim()];
  }
  return [];
}

function shouldSkipOptimization(uri: string) {
  return !uri
    || /^(data|blob|file|content):/i.test(uri)
    || isCFStreamVideo(uri);
}

export function optimizeImageUrl(
  uri?: string | null,
  preset: OptimizedImagePreset = 'feed',
  widthOverride?: number
): string {
  const clean = typeof uri === 'string' ? uri.trim() : '';
  if (shouldSkipOptimization(clean) || preset === 'original') return clean;

  const width = Math.max(80, Math.round(widthOverride || IMAGE_WIDTHS[preset] || IMAGE_WIDTHS.feed));
  const cfImage = clean.match(/^https?:\/\/imagedelivery\.net\/([^/]+)\/([^/?#]+)(?:\/[^?#]+)?/i);
  if (cfImage) {
    const [, accountHash, imageId] = cfImage;
    // Saved media stays original; this only requests a display-sized Cloudflare Images delivery variant.
    const quality = IMAGE_QUALITIES[preset] || IMAGE_QUALITIES.feed;
    return `https://imagedelivery.net/${accountHash}/${imageId}/w=${width},quality=${quality},fit=cover,format=auto`;
  }

  return clean;
}

export function getStreamThumbnailUrl(videoUid: string, preset: OptimizedImagePreset = 'thumb') {
  const height = STREAM_THUMB_HEIGHTS[preset] || STREAM_THUMB_HEIGHTS.thumb;
  return `https://videodelivery.net/${videoUid}/thumbnails/thumbnail.jpg?time=1s&height=${height}`;
}

export function collectPostPreviewUrls(posts: PostLike[], preset: OptimizedImagePreset = 'feed'): string[] {
  const urls: string[] = [];

  posts.forEach((post) => {
    if (!post) return;
    const avatar = typeof post.user_profile_image === 'string' ? post.user_profile_image : '';
    if (avatar) urls.push(optimizeImageUrl(avatar, 'avatar'));

    const media = [
      typeof post.image === 'string' ? post.image : '',
      ...parseImages(post.images),
    ].filter(Boolean);

    media.forEach((uri) => {
      if (isCFStreamVideo(uri)) {
        const uid = extractStreamUid(uri);
        if (uid) urls.push(getStreamThumbnailUrl(uid, preset));
        return;
      }
      if (/^https?:\/\//i.test(uri)) urls.push(optimizeImageUrl(uri, preset));
    });
  });

  return Array.from(new Set(urls.filter((uri) => /^https?:\/\//i.test(uri))));
}

function collectStreamUids(posts: PostLike[]): string[] {
  const uids: string[] = [];
  posts.forEach((post) => {
    const media = [
      typeof post?.image === 'string' ? post.image : '',
      ...parseImages(post?.images),
    ].filter(Boolean);
    media.forEach((uri) => {
      if (isCFStreamVideo(uri)) {
        const uid = extractStreamUid(uri);
        if (uid) uids.push(uid);
      }
    });
  });
  return Array.from(new Set(uids));
}

export async function prefetchImageUrls(urls: string[], limit = 24) {
  const unique = Array.from(new Set(urls.filter((uri) => /^https?:\/\//i.test(uri)))).slice(0, limit);
  if (unique.length === 0) return false;
  return ExpoImage.prefetch(unique, { cachePolicy: 'memory-disk' }).catch(() => false);
}

export async function prefetchPostMedia(posts: PostLike[], preset: OptimizedImagePreset = 'feed', limit = 24) {
  const streamWarmupLimit = Math.max(0, Math.min(4, Math.ceil(limit / 3)));
  const streamWarmups = collectStreamUids(posts).slice(0, streamWarmupLimit).map((uid) => getStreamPlaybackInfo(uid).catch(() => null));
  const imageWarmup = prefetchImageUrls(collectPostPreviewUrls(posts, preset), limit);
  await Promise.allSettled([imageWarmup, ...streamWarmups]);
  return true;
}
