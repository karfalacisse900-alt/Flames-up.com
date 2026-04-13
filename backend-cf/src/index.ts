// Flames-Up Cloudflare Workers API — Hono + D1 + CF Images + CF Stream
// Deploy: wrangler deploy
import { Hono } from 'hono';
import { cors } from 'hono/cors';

// ─── Types ───────────────────────────────────────────────────────────────────
interface Env {
  DB: D1Database;
  KV: KVNamespace;
  JWT_SECRET: string;
  CLOUDFLARE_ACCOUNT_ID: string;
  CLOUDFLARE_IMAGES_TOKEN: string;
  CLOUDFLARE_STREAM_TOKEN: string;
  GOOGLE_MAPS_API_KEY: string;
  FRONTEND_URL: string;
}

type HonoApp = { Bindings: Env; Variables: { userId: string } };

const app = new Hono<HonoApp>();

// Root handler
app.get('/', (c) => c.json({ name: 'Flames-Up API', version: '2.0', status: 'live', docs: '/api/health' }));

const api = new Hono<HonoApp>();

// ─── CORS ────────────────────────────────────────────────────────────────────
app.use('*', cors({ origin: '*', allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'] }));
api.use('*', cors({ origin: '*', allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'] }));

// ─── Helpers ─────────────────────────────────────────────────────────────────
const uuid = () => crypto.randomUUID();
const now = () => new Date().toISOString();

async function hashPassword(password: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(password + 'flames-up-salt');
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, '0')).join('');
}

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return (await hashPassword(password)) === hash;
}

function getUserId(c: any): string {
  const payload = c.get('jwtPayload');
  return payload?.sub || payload?.userId || '';
}

// ─── Auth Middleware ──────────────────────────────────────────────────────────
const authMiddleware = async (c: any, next: () => Promise<void>) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return c.json({ detail: 'Not authenticated' }, 401);
  const token = authHeader.slice(7);
  try {
    const { jwtVerify } = await import('jose');
    const { payload } = await jwtVerify(token, new TextEncoder().encode(c.env.JWT_SECRET));
    c.set('jwtPayload', payload);
    await next();
  } catch {
    return c.json({ detail: 'Invalid token' }, 401);
  }
};

async function createToken(userId: string, secret: string): Promise<string> {
  const { SignJWT } = await import('jose');
  return new SignJWT({ sub: userId })
    .setProtectedHeader({ alg: 'HS256' })
    .setExpirationTime('30d')
    .sign(new TextEncoder().encode(secret));
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTH
// ═══════════════════════════════════════════════════════════════════════════════
api.post('/auth/register', async (c) => {
  const { email, password, username, full_name } = await c.req.json();
  if (!email || !password || !username || !full_name)
    return c.json({ detail: 'All fields required' }, 400);
  const existing = await c.env.DB.prepare('SELECT id FROM users WHERE email = ? OR username = ?')
    .bind(email, username).first();
  if (existing) return c.json({ detail: 'Email or username already exists' }, 400);
  const id = uuid();
  const hash = await hashPassword(password);
  await c.env.DB.prepare(
    'INSERT INTO users (id, email, username, full_name, password_hash) VALUES (?, ?, ?, ?, ?)'
  ).bind(id, email, username, full_name, hash).run();
  const token = await createToken(id, c.env.JWT_SECRET);
  return c.json({ access_token: token, token_type: 'bearer', user: { id, email, username, full_name } });
});

api.post('/auth/login', async (c) => {
  const { email, password } = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).first();
  if (!user || !(await verifyPassword(password, user.password_hash)))
    return c.json({ detail: 'Invalid credentials' }, 401);
  const token = await createToken(user.id, c.env.JWT_SECRET);
  return c.json({
    access_token: token, token_type: 'bearer',
    user: { id: user.id, email: user.email, username: user.username, full_name: user.full_name,
      profile_image: user.profile_image, bio: user.bio, city: user.city,
      age: user.age, looking_for: user.looking_for, interests: user.interests,
      social_website: user.social_website, social_tiktok: user.social_tiktok, social_instagram: user.social_instagram,
      followers_count: user.followers_count, following_count: user.following_count, posts_count: user.posts_count },
  });
});

api.get('/auth/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  if (!user) return c.json({ detail: 'User not found' }, 404);
  const { password_hash, ...safe } = user;
  return c.json(safe);
});

// ═══════════════════════════════════════════════════════════════════════════════
// USERS
// ═══════════════════════════════════════════════════════════════════════════════
api.put('/users/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const body = await c.req.json();
  const fields = ['full_name', 'bio', 'profile_image', 'cover_image', 'city', 'username', 'age', 'looking_for', 'interests', 'social_website', 'social_tiktok', 'social_instagram'];
  const updates: string[] = []; const values: any[] = [];
  for (const f of fields) { if (body[f] !== undefined) { updates.push(`${f} = ?`); values.push(body[f]); } }
  if (updates.length === 0) return c.json({ detail: 'Nothing to update' }, 400);
  values.push(userId);
  await c.env.DB.prepare(`UPDATE users SET ${updates.join(', ')}, updated_at = datetime('now') WHERE id = ?`).bind(...values).run();
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  const { password_hash, ...safe } = user;
  return c.json(safe);
});

api.get('/users/search/:query', authMiddleware, async (c) => {
  const q = c.req.param('query');
  const r = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio FROM users WHERE username LIKE ? OR full_name LIKE ? LIMIT 20').bind(`%${q}%`, `%${q}%`).all();
  return c.json(r.results);
});

api.get('/users/:userId', authMiddleware, async (c) => {
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(c.req.param('userId')).first();
  if (!user) return c.json({ detail: 'User not found' }, 404);
  const { password_hash, ...safe } = user;
  return c.json(safe);
});

api.post('/users/:userId/follow', authMiddleware, async (c) => {
  const userId = getUserId(c); const targetId = c.req.param('userId');
  if (userId === targetId) return c.json({ detail: 'Cannot follow yourself' }, 400);
  const ex = await c.env.DB.prepare('SELECT id FROM follows WHERE follower_id = ? AND following_id = ?').bind(userId, targetId).first();
  if (ex) {
    await c.env.DB.prepare('DELETE FROM follows WHERE follower_id = ? AND following_id = ?').bind(userId, targetId).run();
    await c.env.DB.prepare('UPDATE users SET following_count = MAX(0, following_count - 1) WHERE id = ?').bind(userId).run();
    await c.env.DB.prepare('UPDATE users SET followers_count = MAX(0, followers_count - 1) WHERE id = ?').bind(targetId).run();
    return c.json({ following: false });
  }
  await c.env.DB.prepare('INSERT INTO follows (id, follower_id, following_id) VALUES (?, ?, ?)').bind(uuid(), userId, targetId).run();
  await c.env.DB.prepare('UPDATE users SET following_count = following_count + 1 WHERE id = ?').bind(userId).run();
  await c.env.DB.prepare('UPDATE users SET followers_count = followers_count + 1 WHERE id = ?').bind(targetId).run();
  return c.json({ following: true });
});

// ═══════════════════════════════════════════════════════════════════════════════
// POSTS (with Check-In support)
// ═══════════════════════════════════════════════════════════════════════════════
api.post('/posts', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image FROM users WHERE id = ?').bind(userId).first();
  const b = await c.req.json();
  const id = uuid(); const postType = b.post_type || 'lifestyle';
  const isCheckin = postType === 'check_in' && b.place_id ? 1 : 0;
  const location = postType === 'check_in' && b.place_name ? b.place_name : (b.location || null);
  await c.env.DB.prepare(
    `INSERT INTO posts (id, user_id, content, image, images, media_types, location, post_type, place_id, place_name, place_lat, place_lng, is_verified_checkin)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(id, userId, b.content || '', b.image || null, JSON.stringify(b.images || []), JSON.stringify(b.media_types || []),
    location, postType, b.place_id || null, b.place_name || null, b.place_lat || null, b.place_lng || null, isCheckin).run();
  await c.env.DB.prepare('UPDATE users SET posts_count = posts_count + 1 WHERE id = ?').bind(userId).run();
  return c.json({ id, user_id: userId, user_username: user?.username, user_full_name: user?.full_name,
    user_profile_image: user?.profile_image, content: b.content, image: b.image, images: b.images || [],
    media_types: b.media_types || [], location, post_type: postType, place_id: b.place_id, place_name: b.place_name,
    place_lat: b.place_lat, place_lng: b.place_lng, is_verified_checkin: !!isCheckin,
    likes_count: 0, comments_count: 0, liked_by: [], created_at: now() });
});

api.get('/posts/feed', authMiddleware, async (c) => {
  const skip = parseInt(c.req.query('skip') || '0'); const limit = parseInt(c.req.query('limit') || '20');
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT ? OFFSET ?`
  ).bind(limit, skip).all();
  const results = [];
  for (const p of posts.results as any[]) {
    const likes = await c.env.DB.prepare('SELECT user_id FROM likes WHERE post_id = ?').bind(p.id).all();
    results.push({ ...p, images: JSON.parse(p.images || '[]'), media_types: JSON.parse(p.media_types || '[]'),
      liked_by: likes.results.map((l: any) => l.user_id), is_verified_checkin: !!p.is_verified_checkin });
  }
  return c.json(results);
});

api.get('/posts/nearby-feed', authMiddleware, async (c) => {
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT 50`
  ).all();
  return c.json((posts.results as any[]).map(p => ({ ...p, images: JSON.parse(p.images || '[]'), media_types: JSON.parse(p.media_types || '[]'), is_verified_checkin: !!p.is_verified_checkin })));
});

api.get('/posts/:postId', authMiddleware, async (c) => {
  const postId = c.req.param('postId');
  const p: any = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?`).bind(postId).first();
  if (!p) return c.json({ detail: 'Post not found' }, 404);
  const likes = await c.env.DB.prepare('SELECT user_id FROM likes WHERE post_id = ?').bind(postId).all();
  return c.json({ ...p, images: JSON.parse(p.images || '[]'), media_types: JSON.parse(p.media_types || '[]'),
    liked_by: likes.results.map((l: any) => l.user_id), is_verified_checkin: !!p.is_verified_checkin });
});

api.post('/posts/:postId/like', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  const ex = await c.env.DB.prepare('SELECT id FROM likes WHERE user_id = ? AND post_id = ?').bind(userId, postId).first();
  if (ex) {
    await c.env.DB.prepare('DELETE FROM likes WHERE user_id = ? AND post_id = ?').bind(userId, postId).run();
    await c.env.DB.prepare('UPDATE posts SET likes_count = MAX(0, likes_count - 1) WHERE id = ?').bind(postId).run();
    return c.json({ liked: false });
  }
  await c.env.DB.prepare('INSERT INTO likes (id, user_id, post_id) VALUES (?, ?, ?)').bind(uuid(), userId, postId).run();
  await c.env.DB.prepare('UPDATE posts SET likes_count = likes_count + 1 WHERE id = ?').bind(postId).run();
  return c.json({ liked: true });
});

api.delete('/posts/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  const post: any = await c.env.DB.prepare('SELECT user_id FROM posts WHERE id = ?').bind(postId).first();
  if (!post) return c.json({ detail: 'Post not found' }, 404);
  if (post.user_id !== userId) return c.json({ detail: 'Not your post' }, 403);
  await c.env.DB.prepare('DELETE FROM likes WHERE post_id = ?').bind(postId).run();
  await c.env.DB.prepare('DELETE FROM comments WHERE post_id = ?').bind(postId).run();
  await c.env.DB.prepare('DELETE FROM posts WHERE id = ?').bind(postId).run();
  await c.env.DB.prepare('UPDATE users SET posts_count = MAX(0, posts_count - 1) WHERE id = ?').bind(userId).run();
  return c.json({ deleted: true });
});

api.get('/users/:userId/posts', authMiddleware, async (c) => {
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id WHERE p.user_id = ? ORDER BY p.created_at DESC`
  ).bind(c.req.param('userId')).all();
  return c.json((posts.results as any[]).map(p => ({ ...p, images: JSON.parse(p.images || '[]'), media_types: JSON.parse(p.media_types || '[]'), is_verified_checkin: !!p.is_verified_checkin })));
});

// Comments
api.post('/posts/:postId/comments', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  const { content } = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image FROM users WHERE id = ?').bind(userId).first();
  const id = uuid();
  await c.env.DB.prepare('INSERT INTO comments (id, user_id, post_id, content) VALUES (?, ?, ?, ?)').bind(id, userId, postId, content).run();
  await c.env.DB.prepare('UPDATE posts SET comments_count = comments_count + 1 WHERE id = ?').bind(postId).run();
  return c.json({ id, user_id: userId, post_id: postId, content, user_username: user?.username, user_full_name: user?.full_name, user_profile_image: user?.profile_image, created_at: now() });
});

api.get('/posts/:postId/comments', authMiddleware, async (c) => {
  const r = await c.env.DB.prepare(
    `SELECT c.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM comments c JOIN users u ON c.user_id = u.id WHERE c.post_id = ? ORDER BY c.created_at ASC`
  ).bind(c.req.param('postId')).all();
  return c.json(r.results);
});

// Statuses
api.post('/statuses', authMiddleware, async (c) => {
  const userId = getUserId(c); const b = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image FROM users WHERE id = ?').bind(userId).first();
  const id = uuid(); const expiresAt = new Date(Date.now() + 86400000).toISOString();
  await c.env.DB.prepare('INSERT INTO statuses (id, user_id, content, image, background_color, text_color, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(id, userId, b.content || '', b.image || null, b.background_color || '#1B4332', b.text_color || '#FFFFFF', expiresAt).run();
  return c.json({ id, user_id: userId, content: b.content, image: b.image, background_color: b.background_color, text_color: b.text_color, user_username: user?.username, user_full_name: user?.full_name, user_profile_image: user?.profile_image, viewed_by: [], created_at: now(), expires_at: expiresAt });
});

api.get('/statuses', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const r = await c.env.DB.prepare(`SELECT s.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM statuses s JOIN users u ON s.user_id = u.id WHERE s.expires_at > datetime('now') ORDER BY s.created_at DESC`).all();
  // Group statuses by user_id for the frontend story bar
  const grouped = new Map<string, any>();
  for (const s of r.results as any[]) {
    const uid = s.user_id;
    if (!grouped.has(uid)) {
      grouped.set(uid, {
        user_id: uid,
        user_username: s.user_username,
        user_full_name: s.user_full_name,
        user_profile_image: s.user_profile_image,
        statuses: [],
        has_unviewed: false,
      });
    }
    const parsed = { ...s, viewed_by: JSON.parse(s.viewed_by || '[]') };
    grouped.get(uid)!.statuses.push(parsed);
    if (!parsed.viewed_by.includes(userId)) {
      grouped.get(uid)!.has_unviewed = true;
    }
  }
  return c.json(Array.from(grouped.values()));
});

api.post('/statuses/:statusId/view', authMiddleware, async (c) => {
  const userId = getUserId(c); const statusId = c.req.param('statusId');
  const s: any = await c.env.DB.prepare('SELECT viewed_by FROM statuses WHERE id = ?').bind(statusId).first();
  if (!s) return c.json({ detail: 'Not found' }, 404);
  const vb: string[] = JSON.parse(s.viewed_by || '[]');
  if (!vb.includes(userId)) { vb.push(userId); await c.env.DB.prepare('UPDATE statuses SET viewed_by = ? WHERE id = ?').bind(JSON.stringify(vb), statusId).run(); }
  return c.json({ viewed: true });
});

// Messages (with media support)
api.get('/conversations', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const msgs = await c.env.DB.prepare(`SELECT m.*, u.username, u.full_name, u.profile_image FROM messages m JOIN users u ON (CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END) = u.id WHERE m.sender_id = ? OR m.receiver_id = ? ORDER BY m.created_at DESC`).bind(userId, userId, userId).all();
  const map = new Map<string, any>();
  for (const m of msgs.results as any[]) {
    const oid = m.sender_id === userId ? m.receiver_id : m.sender_id;
    if (!map.has(oid)) {
      let preview = m.content || '';
      if (!preview && m.media_type === 'video') preview = 'Sent a video';
      else if (!preview && (m.media_url || m.image)) preview = 'Sent a photo';
      map.set(oid, { id: `conv-${oid}`, participants: [userId, oid], other_user: { id: oid, username: m.username, full_name: m.full_name, profile_image: m.profile_image }, last_message: preview, last_message_time: m.created_at, unread_count: (!m.is_read && m.receiver_id === userId) ? 1 : 0 });
    }
  }
  return c.json(Array.from(map.values()));
});

api.post('/messages', authMiddleware, async (c) => {
  const userId = getUserId(c); const b = await c.req.json(); const id = uuid();
  await c.env.DB.prepare('INSERT INTO messages (id, sender_id, receiver_id, content, media_url, media_type) VALUES (?, ?, ?, ?, ?, ?)').bind(id, userId, b.receiver_id, b.content || '', b.media_url || null, b.media_type || null).run();
  return c.json({ id, sender_id: userId, receiver_id: b.receiver_id, content: b.content || '', media_url: b.media_url, media_type: b.media_type, created_at: now() });
});

api.get('/messages/:userId', authMiddleware, async (c) => {
  const myId = getUserId(c); const oid = c.req.param('userId');
  await c.env.DB.prepare('UPDATE messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0').bind(oid, myId).run();
  const r = await c.env.DB.prepare('SELECT * FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at ASC').bind(myId, oid, oid, myId).all();
  return c.json(r.results);
});

// Notifications
api.get('/notifications', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 50').bind(getUserId(c)).all(); return c.json(r.results); });
api.get('/notifications/unread-count', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0').bind(getUserId(c)).first(); return c.json({ count: (r as any)?.count || 0 }); });
api.post('/notifications/mark-read', authMiddleware, async (c) => { await c.env.DB.prepare('UPDATE notifications SET is_read = 1 WHERE user_id = ?').bind(getUserId(c)).run(); return c.json({ marked: true }); });

// Library
api.get('/library/liked', authMiddleware, async (c) => { const r = await c.env.DB.prepare(`SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM likes l JOIN posts p ON l.post_id = p.id JOIN users u ON p.user_id = u.id WHERE l.user_id = ? ORDER BY l.created_at DESC`).bind(getUserId(c)).all(); return c.json(r.results); });
api.get('/library/saved', authMiddleware, async (c) => { const r = await c.env.DB.prepare(`SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image, sp.collection FROM saved_posts sp JOIN posts p ON sp.post_id = p.id JOIN users u ON p.user_id = u.id WHERE sp.user_id = ? ORDER BY sp.created_at DESC`).bind(getUserId(c)).all(); return c.json(r.results); });
api.post('/library/save/:postId', authMiddleware, async (c) => { const b = await c.req.json().catch(() => ({})); await c.env.DB.prepare('INSERT OR IGNORE INTO saved_posts (id, user_id, post_id, collection) VALUES (?, ?, ?, ?)').bind(uuid(), getUserId(c), c.req.param('postId'), (b as any).collection || 'default').run(); return c.json({ saved: true }); });
api.delete('/library/save/:postId', authMiddleware, async (c) => { await c.env.DB.prepare('DELETE FROM saved_posts WHERE user_id = ? AND post_id = ?').bind(getUserId(c), c.req.param('postId')).run(); return c.json({ unsaved: true }); });
api.get('/library/collections', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT collection, COUNT(*) as count FROM saved_posts WHERE user_id = ? GROUP BY collection').bind(getUserId(c)).all(); return c.json(r.results); });

// Friends
api.post('/friends/request/:userId', authMiddleware, async (c) => { const fid = getUserId(c); const tid = c.req.param('userId'); if (fid === tid) return c.json({ detail: 'Cannot friend yourself' }, 400); const ex = await c.env.DB.prepare('SELECT id, status FROM friend_requests WHERE from_user_id = ? AND to_user_id = ?').bind(fid, tid).first(); if (ex) return c.json({ detail: 'Already sent', status: (ex as any).status }, 400); const id = uuid(); await c.env.DB.prepare('INSERT INTO friend_requests (id, from_user_id, to_user_id) VALUES (?, ?, ?)').bind(id, fid, tid).run(); return c.json({ id, status: 'pending' }); });
api.post('/friends/accept/:requestId', authMiddleware, async (c) => { const uid = getUserId(c); const rid = c.req.param('requestId'); const r: any = await c.env.DB.prepare('SELECT * FROM friend_requests WHERE id = ? AND to_user_id = ?').bind(rid, uid).first(); if (!r) return c.json({ detail: 'Not found' }, 404); await c.env.DB.prepare("UPDATE friend_requests SET status = 'accepted' WHERE id = ?").bind(rid).run(); await c.env.DB.prepare('INSERT OR IGNORE INTO friendships (id, user_id, friend_id) VALUES (?, ?, ?)').bind(uuid(), uid, r.from_user_id).run(); await c.env.DB.prepare('INSERT OR IGNORE INTO friendships (id, user_id, friend_id) VALUES (?, ?, ?)').bind(uuid(), r.from_user_id, uid).run(); return c.json({ accepted: true }); });
api.post('/friends/reject/:requestId', authMiddleware, async (c) => { await c.env.DB.prepare("UPDATE friend_requests SET status = 'rejected' WHERE id = ?").bind(c.req.param('requestId')).run(); return c.json({ rejected: true }); });
api.get('/friends/requests', authMiddleware, async (c) => { const r = await c.env.DB.prepare(`SELECT fr.*, u.username, u.full_name, u.profile_image FROM friend_requests fr JOIN users u ON fr.from_user_id = u.id WHERE fr.to_user_id = ? AND fr.status = 'pending'`).bind(getUserId(c)).all(); return c.json(r.results); });
api.get('/friends', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT u.id, u.username, u.full_name, u.profile_image, u.bio FROM friendships f JOIN users u ON f.friend_id = u.id WHERE f.user_id = ?').bind(getUserId(c)).all(); return c.json(r.results); });
api.get('/friends/status/:userId', authMiddleware, async (c) => { const mid = getUserId(c); const oid = c.req.param('userId'); const f = await c.env.DB.prepare('SELECT id FROM friendships WHERE user_id = ? AND friend_id = ?').bind(mid, oid).first(); if (f) return c.json({ status: 'friends' }); const sr: any = await c.env.DB.prepare("SELECT id FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'").bind(mid, oid).first(); if (sr) return c.json({ status: 'request_sent', request_id: sr.id }); const rr: any = await c.env.DB.prepare("SELECT id FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'").bind(oid, mid).first(); if (rr) return c.json({ status: 'request_received', request_id: rr.id }); return c.json({ status: 'none' }); });
api.delete('/friends/:userId', authMiddleware, async (c) => { const mid = getUserId(c); const oid = c.req.param('userId'); await c.env.DB.prepare('DELETE FROM friendships WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)').bind(mid, oid, oid, mid).run(); return c.json({ removed: true }); });

// Discover
api.get('/discover/trending', authMiddleware, async (c) => { const r = await c.env.DB.prepare(`SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.likes_count DESC, p.created_at DESC LIMIT 20`).all(); return c.json((r.results as any[]).map(p => ({ ...p, images: JSON.parse(p.images || '[]'), media_types: JSON.parse(p.media_types || '[]') }))); });
api.get('/discover/search', authMiddleware, async (c) => { const q = c.req.query('q') || ''; const posts = await c.env.DB.prepare(`SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM posts p JOIN users u ON p.user_id = u.id WHERE p.content LIKE ? LIMIT 20`).bind(`%${q}%`).all(); const users = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio FROM users WHERE username LIKE ? OR full_name LIKE ? LIMIT 10').bind(`%${q}%`, `%${q}%`).all(); return c.json({ posts: posts.results, users: users.results }); });
api.get('/discover/suggested-users', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio, followers_count FROM users WHERE id != ? ORDER BY followers_count DESC LIMIT 10').bind(getUserId(c)).all(); return c.json(r.results); });

// Uploads (Cloudflare Images + Stream direct upload)
api.post('/upload/image-direct', authMiddleware, async (c) => {
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/images/v2/direct_upload`, { method: 'POST', headers: { Authorization: `Bearer ${c.env.CLOUDFLARE_IMAGES_TOKEN}` } });
  const data: any = await res.json();
  if (!data.success) return c.json({ detail: 'Failed to get upload URL' }, 500);
  return c.json({ upload_url: data.result.uploadURL, image_id: data.result.id });
});

api.post('/upload/video-direct', authMiddleware, async (c) => {
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/stream/direct_upload`, { method: 'POST', headers: { Authorization: `Bearer ${c.env.CLOUDFLARE_STREAM_TOKEN}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ maxDurationSeconds: 300, creator: getUserId(c) }) });
  const data: any = await res.json();
  if (!data.success) return c.json({ detail: 'Failed to get upload URL' }, 500);
  return c.json({ upload_url: data.result.uploadURL, video_uid: data.result.uid });
});

// Reports
api.post('/reports', authMiddleware, async (c) => { const b = await c.req.json(); const id = uuid(); await c.env.DB.prepare('INSERT INTO reports (id, reporter_id, reported_id, report_type, reason, content_id) VALUES (?, ?, ?, ?, ?, ?)').bind(id, getUserId(c), b.reported_id || '', b.report_type || 'other', b.reason || '', b.content_id || null).run(); return c.json({ id, reported: true }); });

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLISHER
// ═══════════════════════════════════════════════════════════════════════════════
api.post('/publisher/apply', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c); const b = await c.req.json();
    if (!b.business_name || !b.category || !b.about || !b.phone || !b.why_publish) {
      return c.json({ detail: 'Missing required fields' }, 400);
    }
    const existing: any = await c.env.DB.prepare('SELECT id, status FROM publisher_applications WHERE user_id = ?').bind(userId).first();
    if (existing) return c.json({ detail: 'Application already exists', status: existing.status });
    const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image FROM users WHERE id = ?').bind(userId).first();
    const id = uuid();
    await c.env.DB.prepare(
      `INSERT INTO publisher_applications (id, user_id, user_username, user_full_name, user_profile_image, business_name, category, about, phone, website, social_instagram, social_twitter, social_tiktok, address, city, why_publish)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(id, userId, user?.username || '', user?.full_name || '', user?.profile_image || '', b.business_name || '', b.category || '', b.about || '', b.phone || '', b.website || '', b.social_instagram || '', b.social_twitter || '', b.social_tiktok || '', b.address || '', b.city || '', b.why_publish || '').run();
    return c.json({ id, status: 'pending', submitted: true });
  } catch (e: any) {
    return c.json({ detail: 'Application failed: ' + (e.message || 'unknown error') }, 500);
  }
});

api.get('/publisher/status', authMiddleware, async (c) => {
  const app: any = await c.env.DB.prepare('SELECT status FROM publisher_applications WHERE user_id = ? ORDER BY created_at DESC LIMIT 1').bind(getUserId(c)).first();
  return c.json({ status: app?.status || 'none' });
});

// Discover posts (publisher content)
api.post('/discover/posts', authMiddleware, async (c) => {
  const userId = getUserId(c); const b = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image, is_publisher FROM users WHERE id = ?').bind(userId).first();
  if (!user?.is_publisher) return c.json({ detail: 'Publishers only' }, 403);
  const id = uuid();
  await c.env.DB.prepare('INSERT INTO discover_posts (id, user_id, content, image, images, category, location) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(id, userId, b.content || '', b.image || null, JSON.stringify(b.images || []), b.category || 'local_news', b.location || '').run();
  return c.json({ id, user_id: userId, user_username: user.username, user_full_name: user.full_name, user_profile_image: user.profile_image, content: b.content, category: b.category, created_at: now() });
});

api.get('/discover/feed', authMiddleware, async (c) => {
  const category = c.req.query('category') || 'all';
  let sql = `SELECT dp.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM discover_posts dp JOIN users u ON dp.user_id = u.id`;
  if (category !== 'all') sql += ` WHERE dp.category = '${category}'`;
  sql += ' ORDER BY dp.created_at DESC LIMIT 50';
  const r = await c.env.DB.prepare(sql).all();
  return c.json((r.results as any[]).map(p => ({ ...p, images: JSON.parse(p.images || '[]') })));
});

api.post('/discover/posts/:postId/like', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  const ex = await c.env.DB.prepare('SELECT id FROM discover_likes WHERE user_id = ? AND post_id = ?').bind(userId, postId).first();
  if (ex) {
    await c.env.DB.prepare('DELETE FROM discover_likes WHERE user_id = ? AND post_id = ?').bind(userId, postId).run();
    await c.env.DB.prepare('UPDATE discover_posts SET likes_count = MAX(0, likes_count - 1) WHERE id = ?').bind(postId).run();
    return c.json({ liked: false });
  }
  await c.env.DB.prepare('INSERT INTO discover_likes (id, user_id, post_id) VALUES (?, ?, ?)').bind(uuid(), userId, postId).run();
  await c.env.DB.prepare('UPDATE discover_posts SET likes_count = likes_count + 1 WHERE id = ?').bind(postId).run();
  return c.json({ liked: true });
});

api.get('/discover/categories', async (c) => {
  return c.json([
    { id: 'local_news', name: 'Local News', icon: 'newspaper' },
    { id: 'events', name: 'Events', icon: 'calendar' },
    { id: 'food_reviews', name: 'Food Reviews', icon: 'restaurant' },
    { id: 'culture', name: 'Culture', icon: 'color-palette' },
    { id: 'tips', name: 'Tips & Recs', icon: 'bulb' },
    { id: 'spotlights', name: 'Spotlights', icon: 'flash' },
  ]);
});

// Places (user-created)
api.post('/places', authMiddleware, async (c) => {
  const userId = getUserId(c); const b = await c.req.json(); const id = uuid();
  await c.env.DB.prepare('INSERT INTO places (id, name, description, category, lat, lng, address, image, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(id, b.name, b.description || '', b.category || '', b.lat || null, b.lng || null, b.address || '', b.image || null, userId).run();
  return c.json({ id, name: b.name, created_at: now() });
});

api.get('/places', authMiddleware, async (c) => {
  const r = await c.env.DB.prepare('SELECT * FROM places ORDER BY created_at DESC LIMIT 50').all();
  return c.json(r.results);
});

api.get('/places/nearby', authMiddleware, async (c) => {
  const r = await c.env.DB.prepare('SELECT * FROM places ORDER BY created_at DESC LIMIT 50').all();
  return c.json(r.results);
});

api.get('/places/:placeId', authMiddleware, async (c) => {
  const p = await c.env.DB.prepare('SELECT * FROM places WHERE id = ?').bind(c.req.param('placeId')).first();
  if (!p) return c.json({ detail: 'Not found' }, 404);
  return c.json(p);
});

api.post('/places/verify-proximity', authMiddleware, async (c) => {
  const b = await c.req.json();
  const distance = Math.sqrt(Math.pow((b.user_lat - b.place_lat) * 111320, 2) + Math.pow((b.user_lng - b.place_lng) * 111320 * Math.cos(b.user_lat * Math.PI / 180), 2));
  return c.json({ verified: distance <= 200, distance: Math.round(distance) });
});

// ═══════════════════════════════════════════════════════════════════════════════
// ADMIN
// ═══════════════════════════════════════════════════════════════════════════════
const adminGuard = async (c: any, next: () => Promise<void>) => {
  const userId = getUserId(c);
  const user: any = await c.env.DB.prepare('SELECT is_admin FROM users WHERE id = ?').bind(userId).first();
  if (!user?.is_admin) return c.json({ detail: 'Admin access required' }, 403);
  await next();
};

api.get('/admin/stats', authMiddleware, adminGuard, async (c) => {
  const users = await c.env.DB.prepare('SELECT COUNT(*) as c FROM users').first() as any;
  const posts = await c.env.DB.prepare('SELECT COUNT(*) as c FROM posts').first() as any;
  const reports = await c.env.DB.prepare('SELECT COUNT(*) as c FROM reports').first() as any;
  const apps = await c.env.DB.prepare("SELECT COUNT(*) as c FROM publisher_applications WHERE status = 'pending'").first() as any;
  return c.json({ total_users: users?.c || 0, total_posts: posts?.c || 0, total_reports: reports?.c || 0, pending_applications: apps?.c || 0 });
});

api.get('/admin/reported-posts', authMiddleware, adminGuard, async (c) => {
  const r = await c.env.DB.prepare(`SELECT r.*, p.content AS post_content, p.image AS post_image, u.username AS reporter_name FROM reports r LEFT JOIN posts p ON r.content_id = p.id LEFT JOIN users u ON r.reporter_id = u.id WHERE r.report_type = 'post' ORDER BY r.created_at DESC`).all();
  return c.json(r.results);
});

api.get('/admin/reported-accounts', authMiddleware, adminGuard, async (c) => {
  const r = await c.env.DB.prepare(`SELECT r.reported_id, u.username, u.full_name, u.profile_image, COUNT(*) as report_count FROM reports r JOIN users u ON r.reported_id = u.id WHERE r.report_type = 'user' GROUP BY r.reported_id`).all();
  return c.json(r.results);
});

api.post('/admin/remove-post/:postId', authMiddleware, adminGuard, async (c) => {
  const postId = c.req.param('postId');
  await c.env.DB.prepare('DELETE FROM likes WHERE post_id = ?').bind(postId).run();
  await c.env.DB.prepare('DELETE FROM comments WHERE post_id = ?').bind(postId).run();
  await c.env.DB.prepare('DELETE FROM posts WHERE id = ?').bind(postId).run();
  return c.json({ removed: true });
});

api.get('/admin/publisher-applications', authMiddleware, adminGuard, async (c) => {
  const r = await c.env.DB.prepare('SELECT * FROM publisher_applications ORDER BY created_at DESC').all();
  return c.json(r.results);
});

api.post('/admin/publisher-applications/:appId/decide', authMiddleware, adminGuard, async (c) => {
  const appId = c.req.param('appId'); const { decision } = await c.req.json();
  const app: any = await c.env.DB.prepare('SELECT user_id FROM publisher_applications WHERE id = ?').bind(appId).first();
  if (!app) return c.json({ detail: 'Not found' }, 404);
  await c.env.DB.prepare('UPDATE publisher_applications SET status = ? WHERE id = ?').bind(decision, appId).run();
  if (decision === 'approved') {
    await c.env.DB.prepare('UPDATE users SET is_publisher = 1 WHERE id = ?').bind(app.user_id).run();
  }
  return c.json({ decided: true, status: decision });
});

api.post('/admin/make-admin/:userId', authMiddleware, adminGuard, async (c) => {
  await c.env.DB.prepare('UPDATE users SET is_admin = 1 WHERE id = ?').bind(c.req.param('userId')).run();
  return c.json({ success: true });
});

api.get('/admin/reports', authMiddleware, adminGuard, async (c) => {
  const r = await c.env.DB.prepare('SELECT * FROM reports ORDER BY created_at DESC LIMIT 50').all();
  return c.json(r.results);
});

api.post('/admin/reports/:reportId/action', authMiddleware, adminGuard, async (c) => {
  const { action } = await c.req.json();
  await c.env.DB.prepare('DELETE FROM reports WHERE id = ?').bind(c.req.param('reportId')).run();
  return c.json({ action, done: true });
});

// Upload (Cloudflare Images)
api.post('/upload/image', authMiddleware, async (c) => {
  try {
    const body = await c.req.json();
    const base64Data = body.image || body.base64;
    if (!base64Data) return c.json({ detail: 'No image data provided' }, 400);

    // Extract the actual base64 content (remove data:image/...;base64, prefix)
    const base64Content = base64Data.includes(',') ? base64Data.split(',')[1] : base64Data;
    const binaryStr = atob(base64Content);
    const bytes = new Uint8Array(binaryStr.length);
    for (let i = 0; i < binaryStr.length; i++) bytes[i] = binaryStr.charCodeAt(i);

    // Detect mime type
    let mimeType = 'image/jpeg';
    if (base64Data.includes('data:image/png')) mimeType = 'image/png';
    else if (base64Data.includes('data:image/webp')) mimeType = 'image/webp';

    const blob = new Blob([bytes], { type: mimeType });
    const formData = new FormData();
    formData.append('file', blob, `upload-${Date.now()}.${mimeType.split('/')[1]}`);

    const cfRes = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/images/v1`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${c.env.CLOUDFLARE_IMAGES_TOKEN}` },
      body: formData,
    });
    const cfData: any = await cfRes.json();
    if (!cfData.success) {
      console.log('CF Images error:', JSON.stringify(cfData.errors));
      return c.json({ url: base64Data, source: 'base64_fallback' });
    }
    // Build proper delivery URL with account hash
    const imageId = cfData.result.id;
    const ACCOUNT_HASH = 'DY-IgVdOm-0zb0K5ZFnpKA';
    const deliveryUrl = `https://imagedelivery.net/${ACCOUNT_HASH}/${imageId}/public`;
    return c.json({ url: deliveryUrl, id: imageId, source: 'cloudflare_images' });
  } catch (e: any) {
    return c.json({ detail: 'Upload failed: ' + e.message }, 500);
  }
});

api.post('/upload/base64-image', authMiddleware, async (c) => {
  // Alias for /upload/image
  const body = await c.req.json();
  const newReq = new Request(c.req.url.replace('base64-image', 'image'), {
    method: 'POST',
    headers: c.req.raw.headers,
    body: JSON.stringify(body),
  });
  return api.fetch(newReq, c.env);
});

api.post('/upload/video', authMiddleware, async (c) => {
  try {
    // Get a direct upload URL from Cloudflare Stream
    const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/stream/direct_upload`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${c.env.CLOUDFLARE_STREAM_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ maxDurationSeconds: 300 }),
    });
    const data: any = await res.json();
    if (!data.success) return c.json({ detail: 'Failed to get upload URL' }, 500);
    return c.json({ upload_url: data.result.uploadURL, video_uid: data.result.uid, source: 'cloudflare_stream' });
  } catch (e: any) {
    return c.json({ detail: 'Video upload setup failed: ' + e.message }, 500);
  }
});

// Get video playback info from Cloudflare Stream
api.get('/stream/video/:videoUid', async (c) => {
  const uid = c.req.param('videoUid');
  try {
    const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/stream/${uid}`, {
      headers: { 'Authorization': `Bearer ${c.env.CLOUDFLARE_STREAM_TOKEN}` },
    });
    const data: any = await res.json();
    if (!data.success || !data.result) return c.json({ detail: 'Video not found' }, 404);
    const v = data.result;
    return c.json({
      uid: v.uid,
      status: v.status?.state || 'unknown',
      duration: v.duration,
      thumbnail: v.thumbnail,
      preview: v.preview,
      playback: v.playback || {},
      hls: v.playback?.hls || null,
      dash: v.playback?.dash || null,
      ready: v.readyToStream || false,
    });
  } catch (e: any) {
    return c.json({ detail: 'Stream fetch failed: ' + e.message }, 500);
  }
});

// Google Places proxy
api.get('/google-places/nearby', async (c) => {
  const key = c.env.GOOGLE_MAPS_API_KEY;
  if (!key) return c.json({ error: 'Google Maps API key not configured', places: [] });
  const keyword = c.req.query('keyword') || '';
  let url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${c.req.query('lat') || '40.7128'},${c.req.query('lng') || '-74.006'}&radius=${c.req.query('radius') || '5000'}&type=${c.req.query('type') || 'restaurant'}&key=${key}`;
  if (keyword) url += `&keyword=${encodeURIComponent(keyword)}`;
  const res = await fetch(url); const data: any = await res.json();
  if (data.status !== 'OK' && data.status !== 'ZERO_RESULTS') {
    return c.json({ error: data.error_message || data.status, places: [] });
  }
  return c.json((data.results || []).map((p: any) => ({
    place_id: p.place_id, name: p.name, vicinity: p.vicinity, rating: p.rating,
    user_ratings_total: p.user_ratings_total, open_now: p.opening_hours?.open_now,
    lat: p.geometry?.location?.lat, lng: p.geometry?.location?.lng, types: p.types,
    photo_url: p.photos?.[0]?.photo_reference ? `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=${p.photos[0].photo_reference}&key=${key}` : null,
  })));
});

api.get('/google-places/:placeId', async (c) => {
  const key = c.env.GOOGLE_MAPS_API_KEY; const pid = c.req.param('placeId');
  const url = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${pid}&fields=name,formatted_address,formatted_phone_number,rating,user_ratings_total,reviews,photos,opening_hours,website,price_level,types,geometry,url&key=${key}`;
  const res = await fetch(url); const data: any = await res.json(); const p = data.result || {};
  return c.json({ place_id: pid, name: p.name, address: p.formatted_address, phone: p.formatted_phone_number,
    rating: p.rating, user_ratings_total: p.user_ratings_total, website: p.website,
    price_level: p.price_level, types: p.types || [], url: p.url,
    lat: p.geometry?.location?.lat, lng: p.geometry?.location?.lng,
    opening_hours: p.opening_hours, reviews: p.reviews || [],
    photos: (p.photos || []).map((ph: any) => `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${ph.photo_reference}&key=${key}`) });
});

// Health
api.get('/', (c) => c.json({ message: 'Flames-Up API', version: '2.0', runtime: 'Cloudflare Workers + Hono + D1' }));
api.get('/health', (c) => c.json({ status: 'healthy', timestamp: now() }));

// ═══════════════════════════════════════════════════════════════════════════════
// BOOKMARKS / SAVE SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

// Setup bookmarks table
api.post('/bookmarks/setup-db', authMiddleware, async (c) => {
  try {
    await c.env.DB.exec(`
      CREATE TABLE IF NOT EXISTS bookmarks (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL, post_id TEXT NOT NULL,
        collection TEXT DEFAULT 'saved', created_at TEXT DEFAULT (datetime('now')),
        UNIQUE(user_id, post_id), FOREIGN KEY (user_id) REFERENCES users(id), FOREIGN KEY (post_id) REFERENCES posts(id)
      );
      CREATE TABLE IF NOT EXISTS saved_places (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL, place_id TEXT NOT NULL,
        place_name TEXT DEFAULT '', place_type TEXT DEFAULT '',
        save_type TEXT DEFAULT 'want_to_go', created_at TEXT DEFAULT (datetime('now')),
        UNIQUE(user_id, place_id), FOREIGN KEY (user_id) REFERENCES users(id)
      );
      CREATE INDEX IF NOT EXISTS idx_bookmarks_user ON bookmarks(user_id);
      CREATE INDEX IF NOT EXISTS idx_bookmarks_post ON bookmarks(post_id);
      CREATE INDEX IF NOT EXISTS idx_saved_places_user ON saved_places(user_id);
    `);
    // Add category column to posts if not exists
    try { await c.env.DB.exec(`ALTER TABLE posts ADD COLUMN category TEXT DEFAULT 'all';`); } catch {}
    try { await c.env.DB.exec(`ALTER TABLE posts ADD COLUMN place_id TEXT DEFAULT NULL;`); } catch {}
    try { await c.env.DB.exec(`ALTER TABLE posts ADD COLUMN place_name TEXT DEFAULT NULL;`); } catch {}
    return c.json({ success: true, message: 'Bookmarks + Saved Places tables created' });
  } catch (e: any) { return c.json({ success: true, message: 'Tables exist', detail: e?.message }); }
});

// Save/Bookmark a post
api.post('/bookmarks', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const { post_id, collection } = await c.req.json();
  if (!post_id) return c.json({ detail: 'post_id required' }, 400);
  const id = uuid();
  try {
    await c.env.DB.prepare('INSERT INTO bookmarks (id, user_id, post_id, collection) VALUES (?, ?, ?, ?) ON CONFLICT(user_id, post_id) DO UPDATE SET collection = ?')
      .bind(id, userId, post_id, collection || 'saved', collection || 'saved').run();
    return c.json({ saved: true, collection: collection || 'saved' });
  } catch (e: any) { return c.json({ detail: 'Save failed', error: e?.message }, 500); }
});

// Unsave/Remove bookmark
api.delete('/bookmarks/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await c.env.DB.prepare('DELETE FROM bookmarks WHERE user_id = ? AND post_id = ?').bind(userId, c.req.param('postId')).run();
  return c.json({ saved: false });
});

// Get saved posts by collection
api.get('/bookmarks', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const collection = c.req.query('collection');
  let q = 'SELECT b.*, p.content, p.image, p.images, p.likes_count, p.post_type, p.created_at as post_date, u.full_name, u.username, u.profile_image FROM bookmarks b JOIN posts p ON b.post_id = p.id JOIN users u ON p.user_id = u.id WHERE b.user_id = ?';
  const binds: any[] = [userId];
  if (collection) { q += ' AND b.collection = ?'; binds.push(collection); }
  q += ' ORDER BY b.created_at DESC';
  const { results } = await c.env.DB.prepare(q).bind(...binds).all();
  return c.json({ bookmarks: results || [] });
});

// Check if post is saved
api.get('/bookmarks/check/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const r: any = await c.env.DB.prepare('SELECT collection FROM bookmarks WHERE user_id = ? AND post_id = ?').bind(userId, c.req.param('postId')).first();
  return c.json({ saved: !!r, collection: r?.collection || null });
});

// Save a place (My Spots)
api.post('/saved-places', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const { place_id, place_name, place_type, save_type } = await c.req.json();
  if (!place_id) return c.json({ detail: 'place_id required' }, 400);
  const id = uuid();
  try {
    await c.env.DB.prepare('INSERT INTO saved_places (id, user_id, place_id, place_name, place_type, save_type) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, place_id) DO UPDATE SET save_type = ?')
      .bind(id, userId, place_id, place_name || '', place_type || '', save_type || 'want_to_go', save_type || 'want_to_go').run();
    return c.json({ saved: true });
  } catch (e: any) { return c.json({ detail: 'Save failed', error: e?.message }, 500); }
});

// Get saved places (My Spots)
api.get('/saved-places', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const save_type = c.req.query('type');
  let q = 'SELECT * FROM saved_places WHERE user_id = ?';
  const binds: any[] = [userId];
  if (save_type) { q += ' AND save_type = ?'; binds.push(save_type); }
  q += ' ORDER BY created_at DESC';
  const { results } = await c.env.DB.prepare(q).bind(...binds).all();
  return c.json({ places: results || [] });
});

// Remove saved place
api.delete('/saved-places/:placeId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await c.env.DB.prepare('DELETE FROM saved_places WHERE user_id = ? AND place_id = ?').bind(userId, c.req.param('placeId')).run();
  return c.json({ saved: false });
});

// ═══════════════════════════════════════════════════════════════════════════════
// CREATOR HUB
// ═══════════════════════════════════════════════════════════════════════════════

// DB Setup — run once to create creator tables
api.post('/creators/setup-db', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const user: any = await c.env.DB.prepare('SELECT is_admin FROM users WHERE id = ?').bind(userId).first();
  if (!user?.is_admin) return c.json({ detail: 'Admin only' }, 403);
  try {
    await c.env.DB.exec(`
      CREATE TABLE IF NOT EXISTS creators (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE, category TEXT NOT NULL,
        skills TEXT DEFAULT '[]', portfolio_links TEXT DEFAULT '[]', short_bio TEXT DEFAULT '',
        city TEXT DEFAULT '', borough TEXT DEFAULT '', availability_status TEXT DEFAULT 'available',
        pricing_range TEXT DEFAULT '', contact_link TEXT DEFAULT '', example_work TEXT DEFAULT '[]',
        status TEXT DEFAULT 'pending', is_verified INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')), updated_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (user_id) REFERENCES users(id)
      );
      CREATE TABLE IF NOT EXISTS creator_portfolio_items (
        id TEXT PRIMARY KEY, creator_id TEXT NOT NULL, post_id TEXT NOT NULL,
        display_order INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')),
        UNIQUE(creator_id, post_id),
        FOREIGN KEY (creator_id) REFERENCES creators(id), FOREIGN KEY (post_id) REFERENCES posts(id)
      );
      CREATE INDEX IF NOT EXISTS idx_creators_user ON creators(user_id);
      CREATE INDEX IF NOT EXISTS idx_creators_status ON creators(status);
      CREATE INDEX IF NOT EXISTS idx_creators_category ON creators(category);
      CREATE INDEX IF NOT EXISTS idx_creators_city ON creators(city);
      CREATE INDEX IF NOT EXISTS idx_portfolio_creator ON creator_portfolio_items(creator_id);
    `);
    // Add is_creator column if not exists
    try { await c.env.DB.exec(`ALTER TABLE users ADD COLUMN is_creator INTEGER DEFAULT 0;`); } catch {}
    return c.json({ success: true, message: 'Creator Hub tables created' });
  } catch (e: any) { return c.json({ success: true, message: 'Tables already exist or created', detail: e?.message }); }
});

// Apply for Creator status
api.post('/creators/apply', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const body = await c.req.json();
  const { category, portfolio_links, short_bio, city, example_work } = body;
  if (!category) return c.json({ detail: 'Category is required' }, 400);

  // Check if already applied
  try {
    const existing: any = await c.env.DB.prepare('SELECT id, status FROM creators WHERE user_id = ?').bind(userId).first();
    if (existing) {
      if (existing.status === 'approved') return c.json({ detail: 'You are already an approved creator' }, 400);
      if (existing.status === 'pending') return c.json({ detail: 'You already have a pending application' }, 400);
      // If rejected, allow re-application by updating
      await c.env.DB.prepare(
        'UPDATE creators SET category = ?, portfolio_links = ?, short_bio = ?, city = ?, example_work = ?, status = ?, updated_at = ? WHERE user_id = ?'
      ).bind(category, JSON.stringify(portfolio_links || []), short_bio || '', city || '', JSON.stringify(example_work || []), 'pending', now(), userId).run();
      return c.json({ message: 'Creator application re-submitted', status: 'pending' });
    }
  } catch {}

  const id = uuid();
  try {
    await c.env.DB.prepare(
      'INSERT INTO creators (id, user_id, category, portfolio_links, short_bio, city, example_work, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    ).bind(id, userId, category, JSON.stringify(portfolio_links || []), short_bio || '', city || '', JSON.stringify(example_work || []), 'pending').run();
  } catch (e: any) {
    return c.json({ detail: 'Failed to submit application. Run /api/creators/setup-db first.', error: e?.message }, 500);
  }
  return c.json({ message: 'Creator application submitted', creator_id: id, status: 'pending' });
});

// Get own creator status
api.get('/creators/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  try {
    const creator: any = await c.env.DB.prepare('SELECT * FROM creators WHERE user_id = ?').bind(userId).first();
    if (!creator) return c.json({ is_creator: false, status: null });
    return c.json({
      ...creator, is_creator: creator.status === 'approved',
      portfolio_links: JSON.parse(creator.portfolio_links || '[]'),
      skills: JSON.parse(creator.skills || '[]'),
      example_work: JSON.parse(creator.example_work || '[]'),
    });
  } catch { return c.json({ is_creator: false, status: null }); }
});

// Update creator profile
api.put('/creators/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const body = await c.req.json();
  try {
    const creator: any = await c.env.DB.prepare('SELECT id, status FROM creators WHERE user_id = ?').bind(userId).first();
    if (!creator || creator.status !== 'approved') return c.json({ detail: 'Not an approved creator' }, 403);
    const fields: string[] = []; const vals: any[] = [];
    if (body.availability_status !== undefined) { fields.push('availability_status = ?'); vals.push(body.availability_status); }
    if (body.pricing_range !== undefined) { fields.push('pricing_range = ?'); vals.push(body.pricing_range); }
    if (body.contact_link !== undefined) { fields.push('contact_link = ?'); vals.push(body.contact_link); }
    if (body.short_bio !== undefined) { fields.push('short_bio = ?'); vals.push(body.short_bio); }
    if (body.skills !== undefined) { fields.push('skills = ?'); vals.push(JSON.stringify(body.skills)); }
    if (body.portfolio_links !== undefined) { fields.push('portfolio_links = ?'); vals.push(JSON.stringify(body.portfolio_links)); }
    if (body.city !== undefined) { fields.push('city = ?'); vals.push(body.city); }
    if (body.borough !== undefined) { fields.push('borough = ?'); vals.push(body.borough); }
    if (fields.length === 0) return c.json({ detail: 'No fields to update' }, 400);
    fields.push('updated_at = ?'); vals.push(now()); vals.push(userId);
    await c.env.DB.prepare(`UPDATE creators SET ${fields.join(', ')} WHERE user_id = ?`).bind(...vals).run();
    return c.json({ message: 'Creator profile updated' });
  } catch (e: any) { return c.json({ detail: 'Update failed', error: e?.message }, 500); }
});

// List creators (with optional filters: category, city, availability)
api.get('/creators', async (c) => {
  const category = c.req.query('category');
  const city = c.req.query('city');
  const availability = c.req.query('availability');
  const search = c.req.query('search');
  const limit = parseInt(c.req.query('limit') || '20');
  const offset = parseInt(c.req.query('offset') || '0');

  let where = "c.status = 'approved'";
  const binds: any[] = [];
  if (category) { where += ' AND c.category = ?'; binds.push(category); }
  if (city) { where += ' AND c.city = ?'; binds.push(city); }
  if (availability) { where += ' AND c.availability_status = ?'; binds.push(availability); }
  if (search) { where += ' AND (u.full_name LIKE ? OR u.username LIKE ? OR c.category LIKE ?)'; binds.push(`%${search}%`, `%${search}%`, `%${search}%`); }
  binds.push(limit, offset);

  try {
    const { results } = await c.env.DB.prepare(`
      SELECT c.*, u.full_name, u.username, u.profile_image, u.followers_count, u.posts_count
      FROM creators c JOIN users u ON c.user_id = u.id
      WHERE ${where} ORDER BY u.followers_count DESC, c.created_at DESC LIMIT ? OFFSET ?
    `).bind(...binds).all();
    const creators = (results || []).map((cr: any) => ({
      ...cr, portfolio_links: JSON.parse(cr.portfolio_links || '[]'),
      skills: JSON.parse(cr.skills || '[]'),
    }));
    return c.json({ creators, count: creators.length });
  } catch (e: any) { return c.json({ creators: [], count: 0, error: e?.message }); }
});

// Get creator categories
api.get('/creators/categories', async (c) => {
  return c.json({
    categories: [
      { id: 'photographer', name: 'Photographer', icon: 'camera' },
      { id: 'artist', name: 'Artist', icon: 'color-palette' },
      { id: 'musician', name: 'Musician', icon: 'musical-notes' },
      { id: 'model', name: 'Model', icon: 'body' },
      { id: 'stylist', name: 'Stylist', icon: 'cut' },
      { id: 'dancer', name: 'Dancer', icon: 'walk' },
      { id: 'influencer', name: 'Influencer', icon: 'star' },
      { id: 'chef', name: 'Chef', icon: 'restaurant' },
      { id: 'filmmaker', name: 'Filmmaker', icon: 'videocam' },
      { id: 'designer', name: 'Designer', icon: 'brush' },
      { id: 'writer', name: 'Writer', icon: 'pencil' },
      { id: 'dj', name: 'DJ', icon: 'headset' },
    ],
  });
});

// Get single creator profile
api.get('/creators/:creatorId', async (c) => {
  const creatorId = c.req.param('creatorId');
  try {
    const creator: any = await c.env.DB.prepare(`
      SELECT c.*, u.full_name, u.username, u.profile_image, u.bio, u.followers_count, u.following_count, u.posts_count, u.city as user_city
      FROM creators c JOIN users u ON c.user_id = u.id WHERE c.id = ?
    `).bind(creatorId).first();
    if (!creator) return c.json({ detail: 'Creator not found' }, 404);
    // Get portfolio items
    const { results: portfolio } = await c.env.DB.prepare(`
      SELECT cpi.*, p.content, p.image, p.images, p.likes_count, p.created_at as post_created_at
      FROM creator_portfolio_items cpi JOIN posts p ON cpi.post_id = p.id
      WHERE cpi.creator_id = ? ORDER BY cpi.display_order ASC LIMIT 20
    `).bind(creatorId).all();
    return c.json({
      ...creator, portfolio_links: JSON.parse(creator.portfolio_links || '[]'),
      skills: JSON.parse(creator.skills || '[]'), portfolio: portfolio || [],
    });
  } catch (e: any) { return c.json({ detail: 'Error fetching creator', error: e?.message }, 500); }
});

// Portfolio management
api.post('/creators/portfolio', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const { post_id, display_order } = await c.req.json();
  if (!post_id) return c.json({ detail: 'post_id is required' }, 400);
  try {
    const creator: any = await c.env.DB.prepare('SELECT id FROM creators WHERE user_id = ? AND status = ?').bind(userId, 'approved').first();
    if (!creator) return c.json({ detail: 'Not an approved creator' }, 403);
    const id = uuid();
    await c.env.DB.prepare(
      'INSERT INTO creator_portfolio_items (id, creator_id, post_id, display_order) VALUES (?, ?, ?, ?)'
    ).bind(id, creator.id, post_id, display_order || 0).run();
    return c.json({ message: 'Portfolio item added', id });
  } catch (e: any) { return c.json({ detail: 'Failed to add portfolio item', error: e?.message }, 500); }
});

api.delete('/creators/portfolio/:itemId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const itemId = c.req.param('itemId');
  try {
    const creator: any = await c.env.DB.prepare('SELECT id FROM creators WHERE user_id = ?').bind(userId).first();
    if (!creator) return c.json({ detail: 'Not a creator' }, 403);
    await c.env.DB.prepare('DELETE FROM creator_portfolio_items WHERE id = ? AND creator_id = ?').bind(itemId, creator.id).run();
    return c.json({ message: 'Portfolio item removed' });
  } catch (e: any) { return c.json({ detail: 'Delete failed', error: e?.message }, 500); }
});

// Admin: Creator applications
api.get('/admin/creator-applications', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const admin: any = await c.env.DB.prepare('SELECT is_admin FROM users WHERE id = ?').bind(userId).first();
  if (!admin?.is_admin) return c.json({ detail: 'Admin only' }, 403);
  const status = c.req.query('status') || 'pending';
  try {
    const { results } = await c.env.DB.prepare(`
      SELECT c.*, u.full_name, u.username, u.profile_image, u.email
      FROM creators c JOIN users u ON c.user_id = u.id WHERE c.status = ? ORDER BY c.created_at DESC
    `).bind(status).all();
    return c.json({ applications: results || [] });
  } catch (e: any) { return c.json({ applications: [], error: e?.message }); }
});

// Admin: Approve creator
api.post('/admin/creators/:creatorId/approve', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const admin: any = await c.env.DB.prepare('SELECT is_admin FROM users WHERE id = ?').bind(userId).first();
  if (!admin?.is_admin) return c.json({ detail: 'Admin only' }, 403);
  const creatorId = c.req.param('creatorId');
  try {
    const creator: any = await c.env.DB.prepare('SELECT user_id FROM creators WHERE id = ?').bind(creatorId).first();
    if (!creator) return c.json({ detail: 'Creator not found' }, 404);
    await c.env.DB.prepare('UPDATE creators SET status = ?, is_verified = 1, updated_at = ? WHERE id = ?').bind('approved', now(), creatorId).run();
    try { await c.env.DB.prepare('UPDATE users SET is_creator = 1 WHERE id = ?').bind(creator.user_id).run(); } catch {}
    return c.json({ message: 'Creator approved' });
  } catch (e: any) { return c.json({ detail: 'Approve failed', error: e?.message }, 500); }
});

// Admin: Reject creator
api.post('/admin/creators/:creatorId/reject', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const admin: any = await c.env.DB.prepare('SELECT is_admin FROM users WHERE id = ?').bind(userId).first();
  if (!admin?.is_admin) return c.json({ detail: 'Admin only' }, 403);
  const creatorId = c.req.param('creatorId');
  try {
    await c.env.DB.prepare('UPDATE creators SET status = ?, updated_at = ? WHERE id = ?').bind('rejected', now(), creatorId).run();
    return c.json({ message: 'Creator rejected' });
  } catch (e: any) { return c.json({ detail: 'Reject failed', error: e?.message }, 500); }
});

// Admin: Remove creator badge
api.delete('/admin/creators/:creatorId/badge', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const admin: any = await c.env.DB.prepare('SELECT is_admin FROM users WHERE id = ?').bind(userId).first();
  if (!admin?.is_admin) return c.json({ detail: 'Admin only' }, 403);
  const creatorId = c.req.param('creatorId');
  try {
    const creator: any = await c.env.DB.prepare('SELECT user_id FROM creators WHERE id = ?').bind(creatorId).first();
    if (!creator) return c.json({ detail: 'Creator not found' }, 404);
    await c.env.DB.prepare('UPDATE creators SET status = ?, is_verified = 0, updated_at = ? WHERE id = ?').bind('revoked', now(), creatorId).run();
    try { await c.env.DB.prepare('UPDATE users SET is_creator = 0 WHERE id = ?').bind(creator.user_id).run(); } catch {}
    return c.json({ message: 'Creator badge removed' });
  } catch (e: any) { return c.json({ detail: 'Remove badge failed', error: e?.message }, 500); }
});

// ═══════════════════════════════════════════════════════════════
// ADMIN GOVERNANCE ENDPOINTS
// ═══════════════════════════════════════════════════════════════

// Helper: check admin
const requireAdmin = async (c: any) => {
  const userId = getUserId(c);
  const admin: any = await c.env.DB.prepare('SELECT is_admin FROM users WHERE id = ?').bind(userId).first();
  if (!admin?.is_admin) throw new Error('FORBIDDEN');
  return userId;
};

// Create tables for governance (run once)
api.post('/admin/init-governance', authMiddleware, async (c) => {
  try {
    const adminId = await requireAdmin(c);
    await c.env.DB.exec(`
      CREATE TABLE IF NOT EXISTS applications (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        type TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        details TEXT DEFAULT '{}',
        admin_notes TEXT DEFAULT '',
        reviewed_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
      );
      CREATE TABLE IF NOT EXISTS reports (
        id TEXT PRIMARY KEY,
        reporter_id TEXT NOT NULL,
        reported_type TEXT NOT NULL,
        reported_id TEXT NOT NULL,
        reason TEXT NOT NULL,
        details TEXT DEFAULT '',
        status TEXT DEFAULT 'pending',
        admin_notes TEXT DEFAULT '',
        reviewed_by TEXT,
        action_taken TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (reporter_id) REFERENCES users(id)
      );
      CREATE TABLE IF NOT EXISTS admin_actions (
        id TEXT PRIMARY KEY,
        admin_id TEXT NOT NULL,
        action_type TEXT NOT NULL,
        target_type TEXT NOT NULL,
        target_id TEXT NOT NULL,
        details TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (admin_id) REFERENCES users(id)
      );
    `);
    return c.json({ message: 'Governance tables created' });
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// ── Applications ──

// Submit application (from main app)
api.post('/applications', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const body = await c.req.json();
  const { type, details } = body; // type: 'creator' | 'publisher'
  if (!type || !['creator', 'publisher'].includes(type)) return c.json({ detail: 'Invalid type' }, 400);
  const id = crypto.randomUUID();
  const ts = now();
  await c.env.DB.prepare(
    'INSERT INTO applications (id, user_id, type, status, details, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
  ).bind(id, userId, type, 'pending', JSON.stringify(details || {}), ts, ts).run();
  return c.json({ id, status: 'pending', message: 'Application submitted' });
});

// List applications (admin)
api.get('/admin/applications', authMiddleware, async (c) => {
  try {
    await requireAdmin(c);
    const type = c.req.query('type') || '';
    const status = c.req.query('status') || '';
    let q = 'SELECT a.*, u.full_name, u.email, u.username, u.profile_image FROM applications a LEFT JOIN users u ON a.user_id = u.id';
    const conditions: string[] = [];
    const binds: string[] = [];
    if (type) { conditions.push('a.type = ?'); binds.push(type); }
    if (status) { conditions.push('a.status = ?'); binds.push(status); }
    if (conditions.length > 0) q += ' WHERE ' + conditions.join(' AND ');
    q += ' ORDER BY a.created_at DESC LIMIT 100';
    let stmt = c.env.DB.prepare(q);
    for (let i = 0; i < binds.length; i++) stmt = stmt.bind(...binds);
    // Manual binding
    const r = binds.length === 0 ? await c.env.DB.prepare(q).all()
      : binds.length === 1 ? await c.env.DB.prepare(q).bind(binds[0]).all()
      : await c.env.DB.prepare(q).bind(binds[0], binds[1]).all();
    return c.json(r.results);
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Review application (admin)
api.put('/admin/applications/:id', authMiddleware, async (c) => {
  try {
    const adminId = await requireAdmin(c);
    const appId = c.req.param('id');
    const body = await c.req.json();
    const { status, admin_notes } = body;
    if (!['approved', 'declined'].includes(status)) return c.json({ detail: 'Invalid status' }, 400);
    const ts = now();
    await c.env.DB.prepare(
      'UPDATE applications SET status = ?, admin_notes = ?, reviewed_by = ?, updated_at = ? WHERE id = ?'
    ).bind(status, admin_notes || '', adminId, ts, appId).run();

    // If approved, update user role
    if (status === 'approved') {
      const app: any = await c.env.DB.prepare('SELECT * FROM applications WHERE id = ?').bind(appId).first();
      if (app) {
        if (app.type === 'creator') {
          await c.env.DB.prepare('UPDATE users SET is_creator = 1 WHERE id = ?').bind(app.user_id).run();
        } else if (app.type === 'publisher') {
          await c.env.DB.prepare('UPDATE users SET is_publisher = 1 WHERE id = ?').bind(app.user_id).run();
        }
      }
    }

    // Log admin action
    await c.env.DB.prepare(
      'INSERT INTO admin_actions (id, admin_id, action_type, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).bind(crypto.randomUUID(), adminId, `application_${status}`, 'application', appId, JSON.stringify({ admin_notes }), ts).run();

    return c.json({ message: `Application ${status}` });
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// ── Reports ──

// Submit report (from main app)
api.post('/reports', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const body = await c.req.json();
  const { reported_type, reported_id, reason, details } = body;
  if (!reported_type || !reported_id || !reason) return c.json({ detail: 'Missing fields' }, 400);
  const id = crypto.randomUUID();
  const ts = now();
  await c.env.DB.prepare(
    'INSERT INTO reports (id, reporter_id, reported_type, reported_id, reason, details, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
  ).bind(id, userId, reported_type, reported_id, reason, details || '', 'pending', ts, ts).run();
  return c.json({ id, message: 'Report submitted' });
});

// List reports (admin)
api.get('/admin/reports', authMiddleware, async (c) => {
  try {
    await requireAdmin(c);
    const status = c.req.query('status') || '';
    let q = 'SELECT r.*, u.full_name as reporter_name, u.email as reporter_email FROM reports r LEFT JOIN users u ON r.reporter_id = u.id';
    if (status) q += ' WHERE r.status = ?';
    q += ' ORDER BY r.created_at DESC LIMIT 100';
    const r = status
      ? await c.env.DB.prepare(q).bind(status).all()
      : await c.env.DB.prepare(q).all();
    return c.json(r.results);
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Review report (admin)
api.put('/admin/reports/:id', authMiddleware, async (c) => {
  try {
    const adminId = await requireAdmin(c);
    const reportId = c.req.param('id');
    const body = await c.req.json();
    const { status, admin_notes, action_taken } = body;
    const ts = now();
    await c.env.DB.prepare(
      'UPDATE reports SET status = ?, admin_notes = ?, action_taken = ?, reviewed_by = ?, updated_at = ? WHERE id = ?'
    ).bind(status || 'resolved', admin_notes || '', action_taken || '', adminId, ts, reportId).run();

    await c.env.DB.prepare(
      'INSERT INTO admin_actions (id, admin_id, action_type, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).bind(crypto.randomUUID(), adminId, `report_${status}`, 'report', reportId, JSON.stringify({ admin_notes, action_taken }), ts).run();

    return c.json({ message: 'Report updated' });
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// ── Content Moderation ──

// Admin: Remove post
api.delete('/admin/posts/:postId', authMiddleware, async (c) => {
  try {
    const adminId = await requireAdmin(c);
    const postId = c.req.param('postId');
    const ts = now();
    await c.env.DB.prepare('DELETE FROM posts WHERE id = ?').bind(postId).run();

    await c.env.DB.prepare(
      'INSERT INTO admin_actions (id, admin_id, action_type, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).bind(crypto.randomUUID(), adminId, 'remove_post', 'post', postId, '{}', ts).run();

    return c.json({ message: 'Post removed' });
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Admin: Get all posts for moderation
api.get('/admin/posts', authMiddleware, async (c) => {
  try {
    await requireAdmin(c);
    const page = parseInt(c.req.query('page') || '1');
    const limit = 20;
    const offset = (page - 1) * limit;
    const r = await c.env.DB.prepare(
      'SELECT p.*, u.full_name as user_full_name, u.email as user_email FROM posts p LEFT JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT ? OFFSET ?'
    ).bind(limit, offset).all();
    return c.json(r.results);
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Admin: Get all users
api.get('/admin/users', authMiddleware, async (c) => {
  try {
    await requireAdmin(c);
    const r = await c.env.DB.prepare(
      'SELECT id, email, full_name, username, profile_image, is_admin, is_creator, is_publisher, is_verified, created_at FROM users ORDER BY created_at DESC LIMIT 200'
    ).all();
    return c.json(r.results);
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Admin: Update user role
api.put('/admin/users/:userId', authMiddleware, async (c) => {
  try {
    const adminId = await requireAdmin(c);
    const targetUserId = c.req.param('userId');
    const body = await c.req.json();
    const { is_admin, is_creator, is_publisher, is_verified } = body;
    const ts = now();
    const fields: string[] = [];
    const vals: any[] = [];
    if (is_admin !== undefined) { fields.push('is_admin = ?'); vals.push(is_admin ? 1 : 0); }
    if (is_creator !== undefined) { fields.push('is_creator = ?'); vals.push(is_creator ? 1 : 0); }
    if (is_publisher !== undefined) { fields.push('is_publisher = ?'); vals.push(is_publisher ? 1 : 0); }
    if (is_verified !== undefined) { fields.push('is_verified = ?'); vals.push(is_verified ? 1 : 0); }
    if (fields.length === 0) return c.json({ detail: 'No fields to update' }, 400);
    vals.push(targetUserId);
    await c.env.DB.prepare(`UPDATE users SET ${fields.join(', ')} WHERE id = ?`).bind(...vals).run();

    await c.env.DB.prepare(
      'INSERT INTO admin_actions (id, admin_id, action_type, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).bind(crypto.randomUUID(), adminId, 'update_user', 'user', targetUserId, JSON.stringify(body), ts).run();

    return c.json({ message: 'User updated' });
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Admin: Action log
api.get('/admin/actions', authMiddleware, async (c) => {
  try {
    await requireAdmin(c);
    const r = await c.env.DB.prepare(
      'SELECT a.*, u.full_name as admin_name FROM admin_actions a LEFT JOIN users u ON a.admin_id = u.id ORDER BY a.created_at DESC LIMIT 100'
    ).all();
    return c.json(r.results);
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Admin: Dashboard stats
api.get('/admin/stats', authMiddleware, async (c) => {
  try {
    await requireAdmin(c);
    const [users, posts, pendingApps, pendingReports] = await Promise.all([
      c.env.DB.prepare('SELECT COUNT(*) as count FROM users').first(),
      c.env.DB.prepare('SELECT COUNT(*) as count FROM posts').first(),
      c.env.DB.prepare("SELECT COUNT(*) as count FROM applications WHERE status = 'pending'").first().catch(() => ({ count: 0 })),
      c.env.DB.prepare("SELECT COUNT(*) as count FROM reports WHERE status = 'pending'").first().catch(() => ({ count: 0 })),
    ]);
    return c.json({
      total_users: (users as any)?.count || 0,
      total_posts: (posts as any)?.count || 0,
      pending_applications: (pendingApps as any)?.count || 0,
      pending_reports: (pendingReports as any)?.count || 0,
    });
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});


// Mount API routes on app
app.route('/api', api);

export default app;
