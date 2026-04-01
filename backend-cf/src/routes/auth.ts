import { Hono } from 'hono';
import type { Env } from '../types';
import { hashPassword, verifyPassword, createToken, getAuthUser, generateId } from '../lib/auth';

export const authRoutes = new Hono<{ Bindings: Env }>();

authRoutes.post('/signup', async (c) => {
  const { email, password, full_name, username } = await c.req.json();
  if (!email || !password || !full_name || !username) {
    return c.json({ error: 'All fields required' }, 400);
  }
  const existing = await c.env.DB.prepare('SELECT id FROM users WHERE email = ? OR username = ?').bind(email, username).first();
  if (existing) return c.json({ error: 'User already exists' }, 409);

  const id = generateId();
  const hashed = await hashPassword(password);
  await c.env.DB.prepare(
    'INSERT INTO users (id, email, username, full_name, hashed_password) VALUES (?, ?, ?, ?, ?)'
  ).bind(id, email, username, full_name, hashed).run();

  await c.env.DB.prepare('INSERT INTO profiles (user_id, display_name) VALUES (?, ?)').bind(id, full_name).run();

  const token = await createToken({ sub: id, exp: Math.floor(Date.now() / 1000) + 86400 * 7 }, c.env.JWT_SECRET);
  return c.json({ token, user: { id, email, username, full_name } });
});

authRoutes.post('/login', async (c) => {
  const { email, password } = await c.req.json();
  const user = await c.env.DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).first();
  if (!user) return c.json({ error: 'Invalid credentials' }, 401);

  const valid = await verifyPassword(password, user.hashed_password as string);
  if (!valid) return c.json({ error: 'Invalid credentials' }, 401);

  const token = await createToken({ sub: user.id as string, exp: Math.floor(Date.now() / 1000) + 86400 * 7 }, c.env.JWT_SECRET);
  return c.json({
    token,
    user: {
      id: user.id, email: user.email, username: user.username,
      full_name: user.full_name,
      avatar_url: user.avatar_image_id ? `https://imagedelivery.net/${c.env.CF_ACCOUNT_HASH}/${user.avatar_image_id}/public` : null,
    },
  });
});

authRoutes.get('/me', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);
  return c.json({
    id: user.id, email: user.email, username: user.username,
    full_name: user.full_name, bio: user.bio,
    avatar_url: user.avatar_image_id ? `https://imagedelivery.net/${c.env.CF_ACCOUNT_HASH}/${user.avatar_image_id}/public` : null,
  });
});
