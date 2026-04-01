import { Hono } from 'hono';
import type { Env } from '../types';
import { getAuthUser } from '../lib/auth';

export const uploadRoutes = new Hono<{ Bindings: Env }>();

// Step 1: Frontend calls this to get a direct upload URL from Cloudflare Images
uploadRoutes.post('/image-direct', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);

  // Request a direct upload URL from Cloudflare Images
  const res = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${c.env.CF_ACCOUNT_ID}/images/v2/direct_upload`,
    {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${c.env.CF_API_TOKEN}` },
    }
  );
  const data: any = await res.json();
  if (!data.success) {
    return c.json({ error: 'Failed to get upload URL', details: data.errors }, 500);
  }

  // Return the upload URL and image ID to frontend
  return c.json({
    upload_url: data.result.uploadURL,
    image_id: data.result.id,
    // Frontend will upload directly to upload_url
    // Then use image_id when creating the post
    delivery_url: `https://imagedelivery.net/${c.env.CF_ACCOUNT_HASH}/${data.result.id}/public`,
  });
});

// Video direct upload (Cloudflare Stream)
uploadRoutes.post('/video-direct', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);

  const res = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${c.env.CF_ACCOUNT_ID}/stream/direct_upload`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${c.env.CF_API_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ maxDurationSeconds: 300 }),
    }
  );
  const data: any = await res.json();
  if (!data.success) {
    return c.json({ error: 'Failed to get video upload URL' }, 500);
  }

  return c.json({
    upload_url: data.result.uploadURL,
    video_uid: data.result.uid,
    stream_url: `https://customer-${c.env.CF_ACCOUNT_ID}.cloudflarestream.com/${data.result.uid}/manifest/video.m3u8`,
  });
});
