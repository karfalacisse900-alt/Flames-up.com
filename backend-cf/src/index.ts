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

const app = new Hono<HonoApp>().basePath('/api');

// ─── CORS ────────────────────────────────────────────────────────────────────
app.use('*', cors({ origin: '*', allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'] }));

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
app.post('/auth/register', async (c) => {
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

app.post('/auth/login', async (c) => {
  const { email, password } = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).first();
  if (!user || !(await verifyPassword(password, user.password_hash)))
    return c.json({ detail: 'Invalid credentials' }, 401);
  const token = await createToken(user.id, c.env.JWT_SECRET);
  return c.json({
    access_token: token, token_type: 'bearer',
    user: { id: user.id, email: user.email, username: user.username, full_name: user.full_name,
      profile_image: user.profile_image, bio: user.bio, city: user.city,
      followers_count: user.followers_count, following_count: user.following_count, posts_count: user.posts_count },
  });
});

app.get('/auth/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  if (!user) return c.json({ detail: 'User not found' }, 404);
  const { password_hash, ...safe } = user;
  return c.json(safe);
});

// ═══════════════════════════════════════════════════════════════════════════════
// USERS
// ═══════════════════════════════════════════════════════════════════════════════
app.put('/users/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const body = await c.req.json();
  const fields = ['full_name', 'bio', 'profile_image', 'cover_image', 'city', 'username'];
  const updates: string[] = []; const values: any[] = [];
  for (const f of fields) { if (body[f] !== undefined) { updates.push(`${f} = ?`); values.push(body[f]); } }
  if (updates.length === 0) return c.json({ detail: 'Nothing to update' }, 400);
  values.push(userId);
  await c.env.DB.prepare(`UPDATE users SET ${updates.join(', ')}, updated_at = datetime('now') WHERE id = ?`).bind(...values).run();
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  const { password_hash, ...safe } = user;
  return c.json(safe);
});

app.get('/users/search/:query', authMiddleware, async (c) => {
  const q = c.req.param('query');
  const r = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio FROM users WHERE username LIKE ? OR full_name LIKE ? LIMIT 20').bind(`%${q}%`, `%${q}%`).all();
  return c.json(r.results);
});

app.get('/users/:userId', authMiddleware, async (c) => {
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(c.req.param('userId')).first();
  if (!user) return c.json({ detail: 'User not found' }, 404);
  const { password_hash, ...safe } = user;
  return c.json(safe);
});

app.post('/users/:userId/follow', authMiddleware, async (c) => {
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
app.post('/posts', authMiddleware, async (c) => {
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

app.get('/posts/feed', authMiddleware, async (c) => {
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

app.get('/posts/nearby-feed', authMiddleware, async (c) => {
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT 50`
  ).all();
  return c.json((posts.results as any[]).map(p => ({ ...p, images: JSON.parse(p.images || '[]'), media_types: JSON.parse(p.media_types || '[]'), is_verified_checkin: !!p.is_verified_checkin })));
});

app.get('/posts/:postId', authMiddleware, async (c) => {
  const postId = c.req.param('postId');
  const p: any = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?`).bind(postId).first();
  if (!p) return c.json({ detail: 'Post not found' }, 404);
  const likes = await c.env.DB.prepare('SELECT user_id FROM likes WHERE post_id = ?').bind(postId).all();
  return c.json({ ...p, images: JSON.parse(p.images || '[]'), media_types: JSON.parse(p.media_types || '[]'),
    liked_by: likes.results.map((l: any) => l.user_id), is_verified_checkin: !!p.is_verified_checkin });
});

app.post('/posts/:postId/like', authMiddleware, async (c) => {
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

app.delete('/posts/:postId', authMiddleware, async (c) => {
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

app.get('/users/:userId/posts', authMiddleware, async (c) => {
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id WHERE p.user_id = ? ORDER BY p.created_at DESC`
  ).bind(c.req.param('userId')).all();
  return c.json((posts.results as any[]).map(p => ({ ...p, images: JSON.parse(p.images || '[]'), media_types: JSON.parse(p.media_types || '[]'), is_verified_checkin: !!p.is_verified_checkin })));
});

// Comments
app.post('/posts/:postId/comments', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  const { content } = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image FROM users WHERE id = ?').bind(userId).first();
  const id = uuid();
  await c.env.DB.prepare('INSERT INTO comments (id, user_id, post_id, content) VALUES (?, ?, ?, ?)').bind(id, userId, postId, content).run();
  await c.env.DB.prepare('UPDATE posts SET comments_count = comments_count + 1 WHERE id = ?').bind(postId).run();
  return c.json({ id, user_id: userId, post_id: postId, content, user_username: user?.username, user_full_name: user?.full_name, user_profile_image: user?.profile_image, created_at: now() });
});

app.get('/posts/:postId/comments', authMiddleware, async (c) => {
  const r = await c.env.DB.prepare(
    `SELECT c.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM comments c JOIN users u ON c.user_id = u.id WHERE c.post_id = ? ORDER BY c.created_at ASC`
  ).bind(c.req.param('postId')).all();
  return c.json(r.results);
});

// Statuses
app.post('/statuses', authMiddleware, async (c) => {
  const userId = getUserId(c); const b = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image FROM users WHERE id = ?').bind(userId).first();
  const id = uuid(); const expiresAt = new Date(Date.now() + 86400000).toISOString();
  await c.env.DB.prepare('INSERT INTO statuses (id, user_id, content, image, background_color, text_color, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(id, userId, b.content || '', b.image || null, b.background_color || '#1B4332', b.text_color || '#FFFFFF', expiresAt).run();
  return c.json({ id, user_id: userId, content: b.content, image: b.image, background_color: b.background_color, text_color: b.text_color, user_username: user?.username, user_full_name: user?.full_name, user_profile_image: user?.profile_image, viewed_by: [], created_at: now(), expires_at: expiresAt });
});

app.get('/statuses', authMiddleware, async (c) => {
  const r = await c.env.DB.prepare(`SELECT s.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM statuses s JOIN users u ON s.user_id = u.id WHERE s.expires_at > datetime('now') ORDER BY s.created_at DESC`).all();
  return c.json((r.results as any[]).map(s => ({ ...s, viewed_by: JSON.parse(s.viewed_by || '[]') })));
});

app.post('/statuses/:statusId/view', authMiddleware, async (c) => {
  const userId = getUserId(c); const statusId = c.req.param('statusId');
  const s: any = await c.env.DB.prepare('SELECT viewed_by FROM statuses WHERE id = ?').bind(statusId).first();
  if (!s) return c.json({ detail: 'Not found' }, 404);
  const vb: string[] = JSON.parse(s.viewed_by || '[]');
  if (!vb.includes(userId)) { vb.push(userId); await c.env.DB.prepare('UPDATE statuses SET viewed_by = ? WHERE id = ?').bind(JSON.stringify(vb), statusId).run(); }
  return c.json({ viewed: true });
});

// Messages (with media support)
app.get('/conversations', authMiddleware, async (c) => {
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

app.post('/messages', authMiddleware, async (c) => {
  const userId = getUserId(c); const b = await c.req.json(); const id = uuid();
  await c.env.DB.prepare('INSERT INTO messages (id, sender_id, receiver_id, content, media_url, media_type) VALUES (?, ?, ?, ?, ?, ?)').bind(id, userId, b.receiver_id, b.content || '', b.media_url || null, b.media_type || null).run();
  return c.json({ id, sender_id: userId, receiver_id: b.receiver_id, content: b.content || '', media_url: b.media_url, media_type: b.media_type, created_at: now() });
});

app.get('/messages/:userId', authMiddleware, async (c) => {
  const myId = getUserId(c); const oid = c.req.param('userId');
  await c.env.DB.prepare('UPDATE messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0').bind(oid, myId).run();
  const r = await c.env.DB.prepare('SELECT * FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at ASC').bind(myId, oid, oid, myId).all();
  return c.json(r.results);
});

// Notifications
app.get('/notifications', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 50').bind(getUserId(c)).all(); return c.json(r.results); });
app.get('/notifications/unread-count', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0').bind(getUserId(c)).first(); return c.json({ count: (r as any)?.count || 0 }); });
app.post('/notifications/mark-read', authMiddleware, async (c) => { await c.env.DB.prepare('UPDATE notifications SET is_read = 1 WHERE user_id = ?').bind(getUserId(c)).run(); return c.json({ marked: true }); });

// Library
app.get('/library/liked', authMiddleware, async (c) => { const r = await c.env.DB.prepare(`SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM likes l JOIN posts p ON l.post_id = p.id JOIN users u ON p.user_id = u.id WHERE l.user_id = ? ORDER BY l.created_at DESC`).bind(getUserId(c)).all(); return c.json(r.results); });
app.get('/library/saved', authMiddleware, async (c) => { const r = await c.env.DB.prepare(`SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image, sp.collection FROM saved_posts sp JOIN posts p ON sp.post_id = p.id JOIN users u ON p.user_id = u.id WHERE sp.user_id = ? ORDER BY sp.created_at DESC`).bind(getUserId(c)).all(); return c.json(r.results); });
app.post('/library/save/:postId', authMiddleware, async (c) => { const b = await c.req.json().catch(() => ({})); await c.env.DB.prepare('INSERT OR IGNORE INTO saved_posts (id, user_id, post_id, collection) VALUES (?, ?, ?, ?)').bind(uuid(), getUserId(c), c.req.param('postId'), (b as any).collection || 'default').run(); return c.json({ saved: true }); });
app.delete('/library/save/:postId', authMiddleware, async (c) => { await c.env.DB.prepare('DELETE FROM saved_posts WHERE user_id = ? AND post_id = ?').bind(getUserId(c), c.req.param('postId')).run(); return c.json({ unsaved: true }); });
app.get('/library/collections', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT collection, COUNT(*) as count FROM saved_posts WHERE user_id = ? GROUP BY collection').bind(getUserId(c)).all(); return c.json(r.results); });

// Friends
app.post('/friends/request/:userId', authMiddleware, async (c) => { const fid = getUserId(c); const tid = c.req.param('userId'); if (fid === tid) return c.json({ detail: 'Cannot friend yourself' }, 400); const ex = await c.env.DB.prepare('SELECT id, status FROM friend_requests WHERE from_user_id = ? AND to_user_id = ?').bind(fid, tid).first(); if (ex) return c.json({ detail: 'Already sent', status: (ex as any).status }, 400); const id = uuid(); await c.env.DB.prepare('INSERT INTO friend_requests (id, from_user_id, to_user_id) VALUES (?, ?, ?)').bind(id, fid, tid).run(); return c.json({ id, status: 'pending' }); });
app.post('/friends/accept/:requestId', authMiddleware, async (c) => { const uid = getUserId(c); const rid = c.req.param('requestId'); const r: any = await c.env.DB.prepare('SELECT * FROM friend_requests WHERE id = ? AND to_user_id = ?').bind(rid, uid).first(); if (!r) return c.json({ detail: 'Not found' }, 404); await c.env.DB.prepare("UPDATE friend_requests SET status = 'accepted' WHERE id = ?").bind(rid).run(); await c.env.DB.prepare('INSERT OR IGNORE INTO friendships (id, user_id, friend_id) VALUES (?, ?, ?)').bind(uuid(), uid, r.from_user_id).run(); await c.env.DB.prepare('INSERT OR IGNORE INTO friendships (id, user_id, friend_id) VALUES (?, ?, ?)').bind(uuid(), r.from_user_id, uid).run(); return c.json({ accepted: true }); });
app.post('/friends/reject/:requestId', authMiddleware, async (c) => { await c.env.DB.prepare("UPDATE friend_requests SET status = 'rejected' WHERE id = ?").bind(c.req.param('requestId')).run(); return c.json({ rejected: true }); });
app.get('/friends/requests', authMiddleware, async (c) => { const r = await c.env.DB.prepare(`SELECT fr.*, u.username, u.full_name, u.profile_image FROM friend_requests fr JOIN users u ON fr.from_user_id = u.id WHERE fr.to_user_id = ? AND fr.status = 'pending'`).bind(getUserId(c)).all(); return c.json(r.results); });
app.get('/friends', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT u.id, u.username, u.full_name, u.profile_image, u.bio FROM friendships f JOIN users u ON f.friend_id = u.id WHERE f.user_id = ?').bind(getUserId(c)).all(); return c.json(r.results); });
app.get('/friends/status/:userId', authMiddleware, async (c) => { const mid = getUserId(c); const oid = c.req.param('userId'); const f = await c.env.DB.prepare('SELECT id FROM friendships WHERE user_id = ? AND friend_id = ?').bind(mid, oid).first(); if (f) return c.json({ status: 'friends' }); const sr: any = await c.env.DB.prepare("SELECT id FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'").bind(mid, oid).first(); if (sr) return c.json({ status: 'request_sent', request_id: sr.id }); const rr: any = await c.env.DB.prepare("SELECT id FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'").bind(oid, mid).first(); if (rr) return c.json({ status: 'request_received', request_id: rr.id }); return c.json({ status: 'none' }); });
app.delete('/friends/:userId', authMiddleware, async (c) => { const mid = getUserId(c); const oid = c.req.param('userId'); await c.env.DB.prepare('DELETE FROM friendships WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)').bind(mid, oid, oid, mid).run(); return c.json({ removed: true }); });

// Discover
app.get('/discover/trending', authMiddleware, async (c) => { const r = await c.env.DB.prepare(`SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.likes_count DESC, p.created_at DESC LIMIT 20`).all(); return c.json((r.results as any[]).map(p => ({ ...p, images: JSON.parse(p.images || '[]'), media_types: JSON.parse(p.media_types || '[]') }))); });
app.get('/discover/search', authMiddleware, async (c) => { const q = c.req.query('q') || ''; const posts = await c.env.DB.prepare(`SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM posts p JOIN users u ON p.user_id = u.id WHERE p.content LIKE ? LIMIT 20`).bind(`%${q}%`).all(); const users = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio FROM users WHERE username LIKE ? OR full_name LIKE ? LIMIT 10').bind(`%${q}%`, `%${q}%`).all(); return c.json({ posts: posts.results, users: users.results }); });
app.get('/discover/suggested-users', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio, followers_count FROM users WHERE id != ? ORDER BY followers_count DESC LIMIT 10').bind(getUserId(c)).all(); return c.json(r.results); });

// Uploads (Cloudflare Images + Stream direct upload)
app.post('/upload/image-direct', authMiddleware, async (c) => {
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/images/v2/direct_upload`, { method: 'POST', headers: { Authorization: `Bearer ${c.env.CLOUDFLARE_IMAGES_TOKEN}` } });
  const data: any = await res.json();
  if (!data.success) return c.json({ detail: 'Failed to get upload URL' }, 500);
  return c.json({ upload_url: data.result.uploadURL, image_id: data.result.id });
});

app.post('/upload/video-direct', authMiddleware, async (c) => {
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/stream/direct_upload`, { method: 'POST', headers: { Authorization: `Bearer ${c.env.CLOUDFLARE_STREAM_TOKEN}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ maxDurationSeconds: 300, creator: getUserId(c) }) });
  const data: any = await res.json();
  if (!data.success) return c.json({ detail: 'Failed to get upload URL' }, 500);
  return c.json({ upload_url: data.result.uploadURL, video_uid: data.result.uid });
});

// Reports
app.post('/reports', authMiddleware, async (c) => { const b = await c.req.json(); const id = uuid(); await c.env.DB.prepare('INSERT INTO reports (id, reporter_id, reported_id, report_type, reason, content_id) VALUES (?, ?, ?, ?, ?, ?)').bind(id, getUserId(c), b.reported_id || '', b.report_type || 'other', b.reason || '', b.content_id || null).run(); return c.json({ id, reported: true }); });

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLISHER
// ═══════════════════════════════════════════════════════════════════════════════
app.post('/publisher/apply', authMiddleware, async (c) => {
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

app.get('/publisher/status', authMiddleware, async (c) => {
  const app: any = await c.env.DB.prepare('SELECT status FROM publisher_applications WHERE user_id = ? ORDER BY created_at DESC LIMIT 1').bind(getUserId(c)).first();
  return c.json({ status: app?.status || 'none' });
});

// Discover posts (publisher content)
app.post('/discover/posts', authMiddleware, async (c) => {
  const userId = getUserId(c); const b = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image, is_publisher FROM users WHERE id = ?').bind(userId).first();
  if (!user?.is_publisher) return c.json({ detail: 'Publishers only' }, 403);
  const id = uuid();
  await c.env.DB.prepare('INSERT INTO discover_posts (id, user_id, content, image, images, category, location) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(id, userId, b.content || '', b.image || null, JSON.stringify(b.images || []), b.category || 'local_news', b.location || '').run();
  return c.json({ id, user_id: userId, user_username: user.username, user_full_name: user.full_name, user_profile_image: user.profile_image, content: b.content, category: b.category, created_at: now() });
});

app.get('/discover/feed', authMiddleware, async (c) => {
  const category = c.req.query('category') || 'all';
  let sql = `SELECT dp.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM discover_posts dp JOIN users u ON dp.user_id = u.id`;
  if (category !== 'all') sql += ` WHERE dp.category = '${category}'`;
  sql += ' ORDER BY dp.created_at DESC LIMIT 50';
  const r = await c.env.DB.prepare(sql).all();
  return c.json((r.results as any[]).map(p => ({ ...p, images: JSON.parse(p.images || '[]') })));
});

app.post('/discover/posts/:postId/like', authMiddleware, async (c) => {
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

app.get('/discover/categories', async (c) => {
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
app.post('/places', authMiddleware, async (c) => {
  const userId = getUserId(c); const b = await c.req.json(); const id = uuid();
  await c.env.DB.prepare('INSERT INTO places (id, name, description, category, lat, lng, address, image, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(id, b.name, b.description || '', b.category || '', b.lat || null, b.lng || null, b.address || '', b.image || null, userId).run();
  return c.json({ id, name: b.name, created_at: now() });
});

app.get('/places', authMiddleware, async (c) => {
  const r = await c.env.DB.prepare('SELECT * FROM places ORDER BY created_at DESC LIMIT 50').all();
  return c.json(r.results);
});

app.get('/places/nearby', authMiddleware, async (c) => {
  const r = await c.env.DB.prepare('SELECT * FROM places ORDER BY created_at DESC LIMIT 50').all();
  return c.json(r.results);
});

app.get('/places/:placeId', authMiddleware, async (c) => {
  const p = await c.env.DB.prepare('SELECT * FROM places WHERE id = ?').bind(c.req.param('placeId')).first();
  if (!p) return c.json({ detail: 'Not found' }, 404);
  return c.json(p);
});

app.post('/places/verify-proximity', authMiddleware, async (c) => {
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

app.get('/admin/stats', authMiddleware, adminGuard, async (c) => {
  const users = await c.env.DB.prepare('SELECT COUNT(*) as c FROM users').first() as any;
  const posts = await c.env.DB.prepare('SELECT COUNT(*) as c FROM posts').first() as any;
  const reports = await c.env.DB.prepare('SELECT COUNT(*) as c FROM reports').first() as any;
  const apps = await c.env.DB.prepare("SELECT COUNT(*) as c FROM publisher_applications WHERE status = 'pending'").first() as any;
  return c.json({ total_users: users?.c || 0, total_posts: posts?.c || 0, total_reports: reports?.c || 0, pending_applications: apps?.c || 0 });
});

app.get('/admin/reported-posts', authMiddleware, adminGuard, async (c) => {
  const r = await c.env.DB.prepare(`SELECT r.*, p.content AS post_content, p.image AS post_image, u.username AS reporter_name FROM reports r LEFT JOIN posts p ON r.content_id = p.id LEFT JOIN users u ON r.reporter_id = u.id WHERE r.report_type = 'post' ORDER BY r.created_at DESC`).all();
  return c.json(r.results);
});

app.get('/admin/reported-accounts', authMiddleware, adminGuard, async (c) => {
  const r = await c.env.DB.prepare(`SELECT r.reported_id, u.username, u.full_name, u.profile_image, COUNT(*) as report_count FROM reports r JOIN users u ON r.reported_id = u.id WHERE r.report_type = 'user' GROUP BY r.reported_id`).all();
  return c.json(r.results);
});

app.post('/admin/remove-post/:postId', authMiddleware, adminGuard, async (c) => {
  const postId = c.req.param('postId');
  await c.env.DB.prepare('DELETE FROM likes WHERE post_id = ?').bind(postId).run();
  await c.env.DB.prepare('DELETE FROM comments WHERE post_id = ?').bind(postId).run();
  await c.env.DB.prepare('DELETE FROM posts WHERE id = ?').bind(postId).run();
  return c.json({ removed: true });
});

app.get('/admin/publisher-applications', authMiddleware, adminGuard, async (c) => {
  const r = await c.env.DB.prepare('SELECT * FROM publisher_applications ORDER BY created_at DESC').all();
  return c.json(r.results);
});

app.post('/admin/publisher-applications/:appId/decide', authMiddleware, adminGuard, async (c) => {
  const appId = c.req.param('appId'); const { decision } = await c.req.json();
  const app: any = await c.env.DB.prepare('SELECT user_id FROM publisher_applications WHERE id = ?').bind(appId).first();
  if (!app) return c.json({ detail: 'Not found' }, 404);
  await c.env.DB.prepare('UPDATE publisher_applications SET status = ? WHERE id = ?').bind(decision, appId).run();
  if (decision === 'approved') {
    await c.env.DB.prepare('UPDATE users SET is_publisher = 1 WHERE id = ?').bind(app.user_id).run();
  }
  return c.json({ decided: true, status: decision });
});

app.post('/admin/make-admin/:userId', authMiddleware, adminGuard, async (c) => {
  await c.env.DB.prepare('UPDATE users SET is_admin = 1 WHERE id = ?').bind(c.req.param('userId')).run();
  return c.json({ success: true });
});

app.get('/admin/reports', authMiddleware, adminGuard, async (c) => {
  const r = await c.env.DB.prepare('SELECT * FROM reports ORDER BY created_at DESC LIMIT 50').all();
  return c.json(r.results);
});

app.post('/admin/reports/:reportId/action', authMiddleware, adminGuard, async (c) => {
  const { action } = await c.req.json();
  await c.env.DB.prepare('DELETE FROM reports WHERE id = ?').bind(c.req.param('reportId')).run();
  return c.json({ action, done: true });
});

// Upload (base64 image support)
app.post('/upload/image', authMiddleware, async (c) => {
  return c.json({ detail: 'Use base64 images inline for now' }, 200);
});
app.post('/upload/base64-image', authMiddleware, async (c) => {
  const { image } = await c.req.json();
  return c.json({ url: image }); // Return as-is, stored inline
});
app.post('/upload/video', authMiddleware, async (c) => {
  return c.json({ detail: 'Use direct upload for videos' }, 200);
});

// Google Places proxy
app.get('/google-places/nearby', async (c) => {
  const key = c.env.GOOGLE_MAPS_API_KEY;
  const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${c.req.query('lat') || '40.7128'},${c.req.query('lng') || '-74.006'}&radius=${c.req.query('radius') || '5000'}&type=${c.req.query('type') || 'restaurant'}&key=${key}`;
  const res = await fetch(url); const data: any = await res.json();
  return c.json((data.results || []).map((p: any) => ({
    place_id: p.place_id, name: p.name, vicinity: p.vicinity, rating: p.rating,
    user_ratings_total: p.user_ratings_total, open_now: p.opening_hours?.open_now,
    lat: p.geometry?.location?.lat, lng: p.geometry?.location?.lng, types: p.types,
    photo_url: p.photos?.[0]?.photo_reference ? `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=${p.photos[0].photo_reference}&key=${key}` : null,
  })));
});

app.get('/google-places/:placeId', async (c) => {
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
app.get('/', (c) => c.json({ message: 'Flames-Up API', version: '2.0', runtime: 'Cloudflare Workers + Hono + D1' }));
app.get('/health', (c) => c.json({ status: 'healthy', timestamp: now() }));

export default app;
