import { Hono } from 'hono';
import type { Env } from '../types';
import { getAuthUser, generateId } from '../lib/auth';

export const postRoutes = new Hono<{ Bindings: Env }>();

// Create post
postRoutes.post('/', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const { content, image_ids, media_types, location } = await c.req.json();
  const id = generateId();
  await c.env.DB.prepare(
    'INSERT INTO posts (id, user_id, content, image_ids, media_types, location) VALUES (?, ?, ?, ?, ?, ?)'
  ).bind(id, user.id, content, JSON.stringify(image_ids || []), JSON.stringify(media_types || []), location || null).run();
  return c.json({ id, user_id: user.id, content, image_ids: image_ids || [], location });
});

// Get post
postRoutes.get('/:id', async (c) => {
  const post = await c.env.DB.prepare(
    'SELECT p.*, u.username, u.full_name, u.avatar_image_id FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?'
  ).bind(c.req.param('id')).first();
  if (!post) return c.json({ error: 'Not found' }, 404);
  const imageIds = JSON.parse((post.image_ids as string) || '[]');
  return c.json({
    ...post,
    image_ids: imageIds,
    image_urls: imageIds.map((imgId: string) => `https://imagedelivery.net/${c.env.CF_ACCOUNT_HASH}/${imgId}/public`),
    user_avatar_url: post.avatar_image_id ? `https://imagedelivery.net/${c.env.CF_ACCOUNT_HASH}/${post.avatar_image_id}/public` : null,
  });
});

// Like post
postRoutes.post('/:id/like', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const postId = c.req.param('id');
  const existing = await c.env.DB.prepare('SELECT id FROM likes WHERE post_id = ? AND user_id = ?').bind(postId, user.id).first();
  if (existing) {
    await c.env.DB.prepare('DELETE FROM likes WHERE post_id = ? AND user_id = ?').bind(postId, user.id).run();
    await c.env.DB.prepare('UPDATE posts SET likes_count = likes_count - 1 WHERE id = ?').bind(postId).run();
    return c.json({ liked: false });
  }
  await c.env.DB.prepare('INSERT INTO likes (id, post_id, user_id) VALUES (?, ?, ?)').bind(generateId(), postId, user.id).run();
  await c.env.DB.prepare('UPDATE posts SET likes_count = likes_count + 1 WHERE id = ?').bind(postId).run();
  return c.json({ liked: true });
});

// Comment on post
postRoutes.post('/:id/comment', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const { content, parent_id } = await c.req.json();
  const id = generateId();
  await c.env.DB.prepare(
    'INSERT INTO comments (id, post_id, user_id, content, parent_id) VALUES (?, ?, ?, ?, ?)'
  ).bind(id, c.req.param('id'), user.id, content, parent_id || null).run();
  await c.env.DB.prepare('UPDATE posts SET comments_count = comments_count + 1 WHERE id = ?').bind(c.req.param('id')).run();
  return c.json({ id, content, user_id: user.id, username: user.username });
});
