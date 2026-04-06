import api from '../api/client';

/**
 * Upload an image to Cloudflare Images via the backend.
 * Falls back to returning base64 data if upload fails.
 */
export async function uploadImage(base64Image: string): Promise<string> {
  if (!base64Image) return '';
  try {
    const response = await api.post('/upload/image', { image: base64Image });
    return response.data?.url || base64Image;
  } catch (error) {
    console.log('Image upload failed, using base64 fallback:', error);
    return base64Image;
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

/**
 * Get the Cloudflare Stream video playback URL from the backend
 */
export async function getStreamPlaybackInfo(videoUid: string): Promise<{
  hls: string | null;
  thumbnail: string | null;
  ready: boolean;
} | null> {
  try {
    const response = await api.get(`/stream/video/${videoUid}`);
    return {
      hls: response.data?.hls || null,
      thumbnail: response.data?.thumbnail || null,
      ready: response.data?.ready || false,
    };
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
