import api from '../api/client';

/**
 * Upload an image to Cloudflare Images via the backend.
 * Falls back to returning base64 data if upload fails.
 * @param base64Image - The base64 image data (with or without data URI prefix)
 * @returns The Cloudflare Images URL or the original base64 string
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
 * @returns Upload URL and video UID
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
 * @param uploadUrl - The direct upload URL from getVideoUploadUrl
 * @param videoUri - Local URI of the video file
 * @returns true if successful
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
 * Get the Cloudflare Stream video playback URL
 * @param videoUid - The video UID from Cloudflare Stream
 * @returns HLS playback URL
 */
export function getStreamPlaybackUrl(videoUid: string): string {
  return `https://customer-${videoUid}.cloudflarestream.com/${videoUid}/manifest/video.m3u8`;
}

/**
 * Get the Cloudflare Stream video thumbnail URL
 * @param videoUid - The video UID
 * @returns Thumbnail URL
 */
export function getStreamThumbnailUrl(videoUid: string): string {
  return `https://customer-${videoUid}.cloudflarestream.com/${videoUid}/thumbnails/thumbnail.jpg`;
}
