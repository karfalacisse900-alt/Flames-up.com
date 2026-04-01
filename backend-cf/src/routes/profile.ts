import { Hono } from 'hono';
import type { Env } from '../types';
import { getAuthUser } from '../lib/auth';

export const profileRoutes = new Hono<{ Bindings: Env }>();

profileRoutes.get('/:username', async (c) => {
  const username = c.req.param('username');
  const user = await c.env.DB.prepare(
    'SELECT u.*, p.* FROM users u LEFT JOIN profiles p ON u.id = p.user_id WHERE u.username = ?'
  ).bind(username).first();
  if (!user) return c.json({ error: 'User not found' }, 404);

  const postsCount = await c.env.DB.prepare('SELECT COUNT(*) as count FROM posts WHERE user_id = ?').bind(user.id).first();
  const followersCount = await c.env.DB.prepare('SELECT COUNT(*) as count FROM follows WHERE following_id = ?').bind(user.id).first();
  const followingCount = await c.env.DB.prepare('SELECT COUNT(*) as count FROM follows WHERE follower_id = ?').bind(user.id).first();

  return c.json({
    id: user.id, username: user.username, full_name: user.full_name, bio: user.bio,
    avatar_url: user.avatar_image_id ? `https://imagedelivery.net/${c.env.CF_ACCOUNT_HASH}/${user.avatar_image_id}/public` : null,
    posts_count: (postsCount as any)?.count || 0,
    followers_count: (followersCount as any)?.count || 0,
    following_count: (followingCount as any)?.count || 0,
    interests: JSON.parse((user.interests as string) || '[]'),
    looking_for: JSON.parse((user.looking_for as string) || '[]'),
    location: user.location,
    age: user.age,
  });
});
