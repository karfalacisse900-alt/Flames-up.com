import { Hono } from 'hono';
import type { Env } from '../types';
import { getAuthUser } from '../lib/auth';

export const feedRoutes = new Hono<{ Bindings: Env }>();

feedRoutes.get('/feed', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const location = c.req.query('location');
  let posts;
  if (location && location !== 'global') {
    posts = await c.env.DB.prepare(
      `SELECT p.*, u.username, u.full_name, u.avatar_image_id 
       FROM posts p JOIN users u ON p.user_id = u.id 
       WHERE p.location LIKE ? AND (p.expires_at IS NULL OR p.expires_at > datetime('now'))
       ORDER BY p.created_at DESC LIMIT 50`
    ).bind(`%${location}%`).all();
  } else {
    posts = await c.env.DB.prepare(
      `SELECT p.*, u.username, u.full_name, u.avatar_image_id 
       FROM posts p JOIN users u ON p.user_id = u.id 
       WHERE p.expires_at IS NULL OR p.expires_at > datetime('now')
       ORDER BY p.created_at DESC LIMIT 50`
    ).all();
  }
  const results = (posts.results || []).map((post: any) => ({
    ...post,
    image_ids: JSON.parse(post.image_ids || '[]'),
    image_urls: JSON.parse(post.image_ids || '[]').map((imgId: string) => `https://imagedelivery.net/${c.env.CF_ACCOUNT_HASH}/${imgId}/public`),
    user_avatar_url: post.avatar_image_id ? `https://imagedelivery.net/${c.env.CF_ACCOUNT_HASH}/${post.avatar_image_id}/public` : null,
  }));
  return c.json(results);
});
