import { Hono } from 'hono';
import type { Env } from '../types';
import { getAuthUser, generateId } from '../lib/auth';

export const socialRoutes = new Hono<{ Bindings: Env }>();

// Follow/Unfollow
socialRoutes.post('/follow/:userId', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const targetId = c.req.param('userId');
  const existing = await c.env.DB.prepare('SELECT id FROM follows WHERE follower_id = ? AND following_id = ?').bind(user.id, targetId).first();
  if (existing) {
    await c.env.DB.prepare('DELETE FROM follows WHERE follower_id = ? AND following_id = ?').bind(user.id, targetId).run();
    return c.json({ following: false });
  }
  await c.env.DB.prepare('INSERT INTO follows (id, follower_id, following_id) VALUES (?, ?, ?)').bind(generateId(), user.id, targetId).run();
  return c.json({ following: true });
});

// Like/comment/notifications
socialRoutes.get('/notifications', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const notifs = await c.env.DB.prepare('SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 50').bind(user.id).all();
  return c.json(notifs.results || []);
});

// Report
socialRoutes.post('/reports', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const { target_type, target_id, reason, details } = await c.req.json();
  await c.env.DB.prepare(
    'INSERT INTO reports (id, reporter_id, target_type, target_id, reason, details) VALUES (?, ?, ?, ?, ?, ?)'
  ).bind(generateId(), user.id, target_type, target_id, reason, details || null).run();
  return c.json({ message: 'Report submitted' });
});

// Save post
socialRoutes.post('/library/save/:postId', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const { collection } = await c.req.json().catch(() => ({ collection: 'all' }));
  await c.env.DB.prepare(
    'INSERT OR REPLACE INTO saved_posts (id, user_id, post_id, collection) VALUES (?, ?, ?, ?)'
  ).bind(generateId(), user.id, c.req.param('postId'), collection || 'all').run();
  return c.json({ status: 'saved' });
});

// Get liked posts
socialRoutes.get('/library/liked', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username, u.full_name FROM posts p 
     JOIN likes l ON p.id = l.post_id 
     JOIN users u ON p.user_id = u.id 
     WHERE l.user_id = ? ORDER BY l.created_at DESC LIMIT 100`
  ).bind(user.id).all();
  return c.json(posts.results || []);
});

// Friend requests
socialRoutes.post('/friends/request/:userId', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const targetId = c.req.param('userId');
  const existing = await c.env.DB.prepare('SELECT id FROM friends WHERE (user_a = ? AND user_b = ?) OR (user_a = ? AND user_b = ?)').bind(user.id, targetId, targetId, user.id).first();
  if (existing) return c.json({ error: 'Already friends' }, 400);
  const pending = await c.env.DB.prepare('SELECT id FROM friend_requests WHERE from_id = ? AND to_id = ? AND status = ?').bind(user.id, targetId, 'pending').first();
  if (pending) return c.json({ error: 'Request already sent' }, 400);
  const id = generateId();
  await c.env.DB.prepare('INSERT INTO friend_requests (id, from_id, to_id) VALUES (?, ?, ?)').bind(id, user.id, targetId).run();
  return c.json({ status: 'pending', request_id: id });
});

socialRoutes.post('/friends/accept/:requestId', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  const req = await c.env.DB.prepare('SELECT * FROM friend_requests WHERE id = ? AND to_id = ? AND status = ?').bind(c.req.param('requestId'), user.id, 'pending').first();
  if (!req) return c.json({ error: 'Not found' }, 404);
  await c.env.DB.prepare('UPDATE friend_requests SET status = ? WHERE id = ?').bind('accepted', req.id).run();
  await c.env.DB.prepare('INSERT INTO friends (id, user_a, user_b) VALUES (?, ?, ?)').bind(generateId(), req.from_id, user.id).run();
  return c.json({ status: 'accepted' });
});
