import api from '../api/client';
import { planMedia } from '../../modules/mira-performance';
import { VIDEO_DIRECT_UPLOAD_THRESHOLD_BYTES } from './mediaQuality';

export type MediaUploadResult = {
  url: string;
  id?: string;
  source?: string;
  videoUid?: string;
  backupId?: string;
  sizeBytes?: number;
  checksumSha256?: string;
};

function estimateBase64Bytes(value: string) {
  const payload = value.includes(',') ? value.split(',').pop() || '' : value;
  return Math.floor(payload.length * 0.75);
}

/**
 * Upload an image to Cloudflare Images via the backend.
 * Falls back to returning base64 data if upload fails.
 */
export async function uploadImage(base64Image: string): Promise<string> {
  const result = await uploadImageWithBackup(base64Image);
  return result.url;
}

/**
 * Upload an image to Cloudflare Images and keep an R2 backup.
 */
export async function uploadImageWithBackup(base64Image: string, filename = 'upload.jpg'): Promise<MediaUploadResult> {
  if (!base64Image) return { url: '' };
  const planningUri = base64Image.startsWith('data:') ? 'data:image/jpeg;base64' : filename;
  const uploadPlan = planMedia(planningUri, 'image/jpeg', filename, estimateBase64Bytes(base64Image), 0, 0, 'quality');
  if (!uploadPlan.allowed) {
    console.warn('Image upload rejected by native media plan:', uploadPlan.reason);
    return { url: '', source: `rejected_${uploadPlan.reason}` };
  }
  try {
    const response = await api.post('/upload/image', { image: base64Image, filename, backup: true });
    return {
      url: response.data?.url || base64Image,
      id: response.data?.id,
      source: response.data?.source,
      backupId: response.data?.backup_id || undefined,
      sizeBytes: response.data?.size_bytes,
      checksumSha256: response.data?.checksum_sha256,
    };
  } catch (error) {
    console.log('Image upload failed, using base64 fallback:', error);
    return { url: base64Image, source: 'base64_fallback' };
  }
}

/**
 * Get a direct video upload URL from Cloudflare Stream
 */
export async function getVideoUploadUrl(): Promise<{ uploadUrl: string; videoUid: string } | null> {
  try {
    const response = await api.post('/upload/video');
    if (response.data?.upload_url) {
      return {
        uploadUrl: response.data.upload_url,
        videoUid: response.data.video_uid,
      };
    }
    return null;
  } catch (error) {
    console.log('Video upload URL request failed:', error);
    return null;
  }
}

/**
 * Upload a video file to Cloudflare Stream using the direct upload URL
 */
export async function uploadVideoToStream(uploadUrl: string, videoUri: string): Promise<boolean> {
  try {
    const formData = new FormData();
    formData.append('file', {
      uri: videoUri,
      type: 'video/mp4',
      name: 'upload.mp4',
    } as any);

    const response = await fetch(uploadUrl, {
      method: 'POST',
      body: formData,
    });
    return response.ok;
  } catch (error) {
    console.log('Video upload failed:', error);
    return false;
  }
}

/**
 * Upload a video through the backend so it can go to Cloudflare Stream and R2 backup together.
 * If the file is too large for Worker-backed upload, it falls back to direct Stream upload.
 */
export async function uploadVideoWithBackup(
  videoUri: string,
  mimeType = 'video/mp4',
  fileName = 'upload.mp4',
  fileSize?: number | null
): Promise<MediaUploadResult | null> {
  const uploadPlan = planMedia(videoUri, mimeType, fileName, Number(fileSize || 0), 0, 0, 'quality');
  if (!uploadPlan.allowed) {
    console.warn('Video upload rejected by native media plan:', uploadPlan.reason);
    return null;
  }

  if (Number(fileSize || 0) > VIDEO_DIRECT_UPLOAD_THRESHOLD_BYTES) {
    const direct = await getVideoUploadUrl();
    if (!direct) return null;
    const ok = await uploadVideoToStream(direct.uploadUrl, videoUri);
    if (!ok) return null;
    return {
      url: `cfstream:${direct.videoUid}`,
      source: 'cloudflare_stream_direct_hd',
      videoUid: direct.videoUid,
      sizeBytes: Number(fileSize || 0) || undefined,
    };
  }

  try {
    const formData = new FormData();
    formData.append('file', {
      uri: videoUri,
      type: mimeType || 'video/mp4',
      name: fileName || 'upload.mp4',
    } as any);

    const response = await api.post('/upload/video-with-backup', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      timeout: 120000,
    });

    if (response.data?.url) {
      return {
        url: response.data.url,
        source: response.data.source,
        videoUid: response.data.video_uid,
        backupId: response.data.backup_id || undefined,
        sizeBytes: response.data.size_bytes,
        checksumSha256: response.data.checksum_sha256,
      };
    }
  } catch (error) {
    console.log('Video upload with backup failed, trying direct Stream upload:', error);
  }

  const direct = await getVideoUploadUrl();
  if (!direct) return null;
  const ok = await uploadVideoToStream(direct.uploadUrl, videoUri);
  if (!ok) return null;
  return {
    url: `cfstream:${direct.videoUid}`,
    source: 'cloudflare_stream',
    videoUid: direct.videoUid,
  };
}

export async function uploadAudioWithBackup(
  audioUri: string,
  mimeType = 'audio/m4a',
  fileName = 'voice.m4a'
): Promise<MediaUploadResult | null> {
  try {
    const formData = new FormData();
    formData.append('file', {
      uri: audioUri,
      type: mimeType || 'audio/m4a',
      name: fileName || 'voice.m4a',
    } as any);

    const response = await api.post('/upload/audio', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      timeout: 90000,
    });

    if (response.data?.url) {
      return {
        url: response.data.url,
        id: response.data.id,
        source: response.data.source,
        backupId: response.data.backup_id || undefined,
        sizeBytes: response.data.size_bytes,
        checksumSha256: response.data.checksum_sha256,
      };
    }
  } catch (error) {
    console.log('Audio upload failed:', error);
  }
  return null;
}

/**
 * Detect if a URI is a Cloudflare Stream video (prefixed with cfstream:)
 */
export function isCFStreamVideo(uri: string): boolean {
  return uri?.startsWith('cfstream:') || false;
}

/**
 * Extract the video UID from a cfstream: prefixed URI
 */
export function extractStreamUid(uri: string): string {
  return uri.replace('cfstream:', '');
}

type StreamPlaybackInfo = {
  hls: string | null;
  thumbnail: string | null;
  ready: boolean;
};

const streamPlaybackCache = new Map<string, StreamPlaybackInfo | null>();
const streamPlaybackRequests = new Map<string, Promise<StreamPlaybackInfo | null>>();

/**
 * Get the Cloudflare Stream video playback URL from the backend
 */
export async function getStreamPlaybackInfo(videoUid: string): Promise<StreamPlaybackInfo | null> {
  if (!videoUid) return null;
  if (streamPlaybackCache.has(videoUid)) return streamPlaybackCache.get(videoUid) || null;
  const pending = streamPlaybackRequests.get(videoUid);
  if (pending) return pending;

  const request = (async () => {
    try {
      const response = await api.get(`/stream/video/${videoUid}`);
      const info = {
        hls: response.data?.hls || null,
        thumbnail: response.data?.thumbnail || null,
        ready: response.data?.ready || false,
      };
      streamPlaybackCache.set(videoUid, info);
      return info;
    } catch {
      return null;
    } finally {
      streamPlaybackRequests.delete(videoUid);
    }
  })();

  streamPlaybackRequests.set(videoUid, request);
  return request;
}

export function primeStreamPlaybackInfo(videoUid: string, info: StreamPlaybackInfo | null) {
  if (!videoUid) return;
  streamPlaybackCache.set(videoUid, info);
}

export function clearStreamPlaybackInfoCache() {
  streamPlaybackCache.clear();
  streamPlaybackRequests.clear();
}

/**
 * Get the Cloudflare Stream video playback URL from the backend without reusing cached state.
 */
export async function refreshStreamPlaybackInfo(videoUid: string): Promise<StreamPlaybackInfo | null> {
  try {
    const response = await api.get(`/stream/video/${videoUid}`);
    const info = {
      hls: response.data?.hls || null,
      thumbnail: response.data?.thumbnail || null,
      ready: response.data?.ready || false,
    };
    streamPlaybackCache.set(videoUid, info);
    return info;
  } catch {
    return null;
  }
}

/**
 * Get the Cloudflare Stream iframe embed URL (works universally)
 */
export function getStreamEmbedUrl(videoUid: string): string {
  return `https://iframe.cloudflarestream.com/${videoUid}`;
}
