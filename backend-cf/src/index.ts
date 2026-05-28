// Flames-Up Cloudflare Workers API — Hono + D1 + CF Images + CF Stream
// Deploy: wrangler deploy --env production --keep-vars
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import bcrypt from 'bcryptjs';
import { RtcRole, RtcTokenBuilder } from 'agora-token';

// ─── Types ───────────────────────────────────────────────────────────────────
interface Env {
  DB: D1Database;
  KV?: KVNamespace;
  HYPERDRIVE?: any;
  AI?: any;
  MEDIA_BACKUP?: R2Bucket;
  JWT_SECRET: string;
  CLOUDFLARE_ACCOUNT_ID: string;
  CLOUDFLARE_IMAGES_ACCOUNT_HASH?: string;
  CLOUDFLARE_IMAGES_TOKEN: string;
  CLOUDFLARE_IMAGES_FEED_VARIANT?: string;
  CLOUDFLARE_IMAGES_THUMBNAIL_VARIANT?: string;
  CLOUDFLARE_STREAM_TOKEN: string;
  MAPBOX_ACCESS_TOKEN?: string;
  ENVIRONMENT?: string;
  FRONTEND_URL: string;
  OWNER_USERNAMES?: string;
  OWNER_EMAILS?: string;
  GOOGLE_OAUTH_CLIENT_ID?: string;
  GOOGLE_OAUTH_CLIENT_IDS?: string;
  SUPABASE_URL?: string;
  SUPABASE_JWT_ISSUER?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  APPLE_OAUTH_AUDIENCE?: string;
  APPLE_OAUTH_AUDIENCES?: string;
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_AUTH_TOKEN?: string;
  TWILIO_VERIFY_SERVICE_SID?: string;
  TWILIO_SERVICE_SID?: string;
  TWILIO_FROM_PHONE?: string;
  GIPHY_API_KEY?: string;
  AGORA_APP_ID?: string;
  AGORA_APP_CERTIFICATE?: string;
  AGORA_TOKEN_TTL_SECONDS?: string;
  APNS_TEAM_ID?: string;
  APNS_KEY_ID?: string;
  APNS_BUNDLE_ID?: string;
  APNS_PRIVATE_KEY?: string;
  APNS_VOIP_PRIVATE_KEY?: string;
  APNS_ENVIRONMENT?: string;
  MEDIA_BACKUP_MAX_VIDEO_BYTES?: string;
  SOURCE_COMMIT?: string;
  WORKER_VERSION?: string;
  STRIPE_SECRET_KEY?: string;
  STRIPE_PUBLISHABLE_KEY?: string;
  STRIPE_DEFAULT_PRICE_ID?: string;
  STRIPE_PREMIUM_PRICE_ID?: string;
  STRIPE_SUCCESS_URL?: string;
  STRIPE_CANCEL_URL?: string;
  STRIPE_WEBHOOK_SECRET?: string;
  ELEVENLABS_API_KEY?: string;
  MUSIC_DAILY_GENERATION_LIMIT?: string;
  MUSIC_GENERATION_COOLDOWN_SECONDS?: string;
  ABUSE_SIGNAL_SECRET?: string;
  OWNERSHIP_ANCHOR_PROVIDER?: string;
  EVM_RPC_URL?: string;
  EVM_CONTRACT_ADDRESS?: string;
  SOLANA_RPC_URL?: string;
  IPFS_API_URL?: string;
  ARWEAVE_GATEWAY?: string;
}

type HonoApp = { Bindings: Env; Variables: { userId: string; requestId: string } };

const app = new Hono<HonoApp>();
const API_VERSION = '2.0';
const WORKER_NAME = 'flames-up-api';

// Root handler
app.get('/', (c) => c.json({ name: 'Captro API', version: API_VERSION, status: 'live', docs: '/api/health' }));

const api = new Hono<HonoApp>();

// ─── CORS ────────────────────────────────────────────────────────────────────
const DEFAULT_ALLOWED_ORIGINS = [
  'https://flames-up.com',
  'https://www.flames-up.com',
  'https://admin.flames-up.com',
  'https://captro-admin.pages.dev',
];
function isProductionEnv(c: any): boolean {
  return String(c?.env?.ENVIRONMENT || '').toLowerCase() === 'production';
}

function allowedOrigins(c?: any): string[] {
  const configured = String(c?.env?.FRONTEND_URL || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => /^https:\/\//.test(origin));
  return Array.from(new Set([...DEFAULT_ALLOWED_ORIGINS, ...configured]));
}

function allowedCorsOrigin(origin: string, c?: any) {
  const origins = allowedOrigins(c);
  if (!origin) return origins[0];
  if (origins.includes(origin)) return origin;
  if (!isProductionEnv(c) && /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) return origin;
  return null;
}
const corsOpts = {
  origin: allowedCorsOrigin,
  allowMethods: ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowHeaders: [
    'Authorization',
    'Content-Type',
    'Range',
    'Idempotency-Key',
    'X-Idempotency-Key',
    'X-Request-ID',
    'X-Captro-Device-Trust-Mode',
    'X-Captro-Device-Trust-Action',
    'X-Captro-App-Attest-Supported',
    'X-Captro-DeviceCheck-Token'
  ],
  exposeHeaders: ['Accept-Ranges', 'Content-Length', 'Content-Range', 'Content-Type', 'ETag', 'Server-Timing', 'X-Request-ID', 'X-Response-Time'],
  maxAge: 600,
};
app.use('*', cors(corsOpts));
api.use('*', cors(corsOpts));

function sanitizeRequestId(value: unknown): string {
  const clean = String(value || '').trim().replace(/[^a-zA-Z0-9_.:-]/g, '').slice(0, 80);
  return clean.length >= 8 ? clean : uuid();
}

const requestIdMiddleware = async (c: any, next: () => Promise<void>) => {
  const requestId = sanitizeRequestId(c.req.header('X-Request-ID') || c.req.header('CF-Ray'));
  c.set('requestId', requestId);
  c.header('X-Request-ID', requestId);
  await next();
  c.header('X-Request-ID', requestId);
};
app.use('*', requestIdMiddleware);
api.use('*', requestIdMiddleware);

const responseTimingMiddleware = async (c: any, next: () => Promise<void>) => {
  const startedAt = Date.now();
  await next();
  const elapsedMs = Date.now() - startedAt;
  c.header('Server-Timing', `app;dur=${elapsedMs}`);
  c.header('X-Response-Time', `${elapsedMs}ms`);
  const status = Number(c.res?.status || 200);
  if (elapsedMs >= 750 || status >= 500) {
    console.warn(JSON.stringify({
      event: 'api_request_slow_or_error',
      request_id: c.get?.('requestId') || '',
      method: c.req.method,
      path: new URL(c.req.url).pathname,
      status,
      duration_ms: elapsedMs,
    }));
  }
};
app.use('*', responseTimingMiddleware);

const securityHeaders = async (c: any, next: () => Promise<void>) => {
  await next();
  c.header('X-Content-Type-Options', 'nosniff');
  c.header('X-Frame-Options', 'DENY');
  c.header('Referrer-Policy', 'strict-origin-when-cross-origin');
  c.header('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=()');
  c.header('Cross-Origin-Resource-Policy', 'cross-origin');
  c.header('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
  if (isProductionEnv(c)) {
    c.header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');
  }
};
app.use('*', securityHeaders);
api.use('*', securityHeaders);

const retiredFeature = (feature: string) => (c: any) => c.json({
  detail: `${feature} has been removed from Flames Up.`,
}, 410);

api.all('/publisher/*', retiredFeature('Publisher tools'));
api.all('/admin/publisher-applications', retiredFeature('Publisher applications'));
api.all('/admin/publisher-applications/*', retiredFeature('Publisher applications'));
api.all('/creators', retiredFeature('Creator Hub'));
api.all('/creators/*', retiredFeature('Creator Hub'));
api.all('/admin/creator-applications', retiredFeature('Creator applications'));
api.all('/admin/creator-applications/*', retiredFeature('Creator applications'));
api.all('/admin/creators/*', retiredFeature('Creator admin tools'));
api.all('/challenges', retiredFeature('Challenges'));
api.all('/challenges/*', retiredFeature('Challenges'));
api.all('/challenge-entries/*', retiredFeature('Challenge entries'));
api.all('/admin/challenges', retiredFeature('Challenge admin tools'));
api.all('/admin/challenges/*', retiredFeature('Challenge admin tools'));
api.all('/music', retiredFeature('Music'));
api.use('/music/*', async (c, next) => {
  const path = new URL(c.req.url).pathname;
  if (path.startsWith('/api/music/audius/')) {
    await next();
    return;
  }
  return retiredFeature('Music')(c);
});
api.all('/admin/music', retiredFeature('Music admin tools'));
api.all('/admin/music/*', retiredFeature('Music admin tools'));
api.all('/admin/notes', retiredFeature('Notes admin tools'));
api.all('/admin/notes/*', retiredFeature('Notes admin tools'));

// ─── Helpers ─────────────────────────────────────────────────────────────────
const uuid = () => crypto.randomUUID();
const now = () => new Date().toISOString();

async function hashPassword(password: string): Promise<string> {
  return bcrypt.hashSync(password, 10);
}

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  if (!hash) return false;
  // Support both bcrypt hashes (starts with $2) and legacy SHA-256
  if (hash.startsWith('$2')) {
    return bcrypt.compareSync(password, hash);
  }
  // Legacy SHA-256 fallback for existing users
  const encoder = new TextEncoder();
  const data = encoder.encode(password + 'flames-up-salt');
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const legacyHash = Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, '0')).join('');
  return legacyHash === hash;
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
  let payload: any;
  let userId = '';

  try {
    const { jwtVerify } = await import('jose');
    const verified = await jwtVerify(token, new TextEncoder().encode(getJwtSecret(c)));
    payload = verified.payload;
    userId = String(payload?.sub || payload?.userId || '');
    c.set('jwtPayload', payload);
  } catch (error: any) {
    try {
      const resolved = await resolveSupabaseSessionUser(c, token);
      payload = resolved.payload;
      userId = resolved.userId;
      c.set('jwtPayload', payload);
    } catch {
      if (getErrorCode(error).includes('JWT_SECRET_MISSING')) {
        return c.json({ detail: 'Auth service is not configured.', code: 'JWT_SECRET_MISSING' }, 503);
      }
      return c.json({ detail: 'Invalid token', code: 'INVALID_TOKEN' }, 401);
    }
  }

  if (!userId) return c.json({ detail: 'Invalid token', code: 'INVALID_TOKEN' }, 401);

  try {
    let user: any;
    try {
      user = await c.env.DB.prepare('SELECT id, status, suspended_until FROM users WHERE id = ?').bind(userId).first();
    } catch (error: any) {
      const message = String(error?.message || '');
      if (message.includes('no such column: suspended_until')) {
        user = await c.env.DB.prepare('SELECT id, status, NULL AS suspended_until FROM users WHERE id = ?').bind(userId).first();
      } else if (message.includes('no such column: status')) {
        user = await c.env.DB.prepare("SELECT id, 'active' AS status, NULL AS suspended_until FROM users WHERE id = ?").bind(userId).first();
      } else {
        throw error;
      }
    }

    if (!user) return c.json({ detail: 'Session user was not found.', code: 'USER_NOT_FOUND' }, 401);

    const accountStatus = String(user?.status || 'active');
    if (accountStatus === 'suspended') {
      const suspendedUntil = Date.parse(String(user?.suspended_until || ''));
      if (Number.isFinite(suspendedUntil) && suspendedUntil <= Date.now()) {
        await c.env.DB.prepare("UPDATE users SET status = 'active', suspended_until = NULL, updated_at = datetime('now') WHERE id = ? AND status = 'suspended'")
          .bind(userId)
          .run()
          .catch(() => {});
      } else {
        return c.json({ detail: 'This account is suspended.' }, 403);
      }
    } else if (accountStatus === 'banned' || accountStatus === 'deleted') {
      return c.json({ detail: 'This account cannot be used.' }, 403);
    }
    await next();
  } catch (error: any) {
    console.error(JSON.stringify({
      event: 'auth_context_failed',
      code: getErrorCode(error),
      message: String(error?.message || '').slice(0, 200),
    }));
    return c.json({ detail: 'Could not load your account session. Please try again.', code: 'AUTH_CONTEXT_FAILED' }, 503);
  }
};

async function getOptionalUserId(c: any): Promise<string> {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return '';

  const token = authHeader.slice(7);
  try {
    const { jwtVerify } = await import('jose');
    const verified = await jwtVerify(token, new TextEncoder().encode(getJwtSecret(c)));
    const payload: any = verified.payload;
    const userId = String(payload?.sub || payload?.userId || '');
    if (!userId) return '';

    let user: any;
    try {
      user = await c.env.DB.prepare('SELECT id, status, suspended_until FROM users WHERE id = ?').bind(userId).first();
    } catch (error: any) {
      const message = String(error?.message || '');
      if (message.includes('no such column: suspended_until')) {
        user = await c.env.DB.prepare('SELECT id, status, NULL AS suspended_until FROM users WHERE id = ?').bind(userId).first();
      } else if (message.includes('no such column: status')) {
        user = await c.env.DB.prepare("SELECT id, 'active' AS status, NULL AS suspended_until FROM users WHERE id = ?").bind(userId).first();
      } else {
        throw error;
      }
    }

    const optionalStatus = String(user?.status || 'active');
    if (!user || optionalStatus === 'banned' || optionalStatus === 'deleted') return '';
    if (optionalStatus === 'suspended') {
      const suspendedUntil = Date.parse(String(user?.suspended_until || ''));
      if (!Number.isFinite(suspendedUntil) || suspendedUntil > Date.now()) return '';
      await c.env.DB.prepare("UPDATE users SET status = 'active', suspended_until = NULL, updated_at = datetime('now') WHERE id = ? AND status = 'suspended'")
        .bind(userId)
        .run()
        .catch(() => {});
    }
    c.set('jwtPayload', payload);
    return userId;
  } catch {
    try {
      const resolved = await resolveSupabaseSessionUser(c, token);
      c.set('jwtPayload', resolved.payload);
      return resolved.userId;
    } catch {
      return '';
    }
  }
}

async function createToken(userId: string, secret: string): Promise<string> {
  const { SignJWT } = await import('jose');
  return new SignJWT({ sub: userId })
    .setProtectedHeader({ alg: 'HS256' })
    .setExpirationTime('30d')
    .sign(new TextEncoder().encode(secret));
}

function parseAudiences(...values: Array<string | undefined>): string[] {
  return values
    .filter(Boolean)
    .flatMap((value) => String(value).split(','))
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
}

function usernameSlug(input: string): string {
  const base = input
    .toLowerCase()
    .replace(/[^a-z0-9_.]/g, '_')
    .replace(/_+/g, '_')
    .replace(/\.+/g, '.')
    .replace(/^_+|_+$/g, '');
  return base.replace(/^\.+|\.+$/g, '') || 'captro';
}

const RESERVED_USERNAMES = new Set([
  'admin',
  'administrator',
  'support',
  'help',
  'official',
  'system',
  'moderator',
  'security',
  'staff',
  'root',
  'owner',
  'verified',
  'captro',
  'team',
  'privacy',
  'terms',
  'safety',
  'legal',
  'login',
  'signup',
  'settings',
  'discover',
  'explore',
  'feed',
  'chat',
  'profile',
  'notifications',
  'null',
  'undefined',
  'api',
]);

const STAFF_USERNAME_PATTERN = /(^|[_.])(admin|administrator|support|moderator|staff|security|official|system|owner|root)([_.]|$)/;

function strictUsernameSlug(value: unknown): string {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/^@+/, '');
}

function isReservedOrStaffUsername(username: string): boolean {
  return RESERVED_USERNAMES.has(username) || STAFF_USERNAME_PATTERN.test(username);
}

const GENERATED_USERNAME_PREFIXES = [
  'user_',
  'temp_',
  'apple_',
  'appleuser',
  'google_',
  'guest_',
  'pending_',
  'phone_',
  'sb_',
  'nulluser',
];

function isLikelyGeneratedUsername(value: unknown): boolean {
  const username = strictUsernameSlug(value);
  if (!username) return true;
  if (GENERATED_USERNAME_PREFIXES.some((prefix) => username.startsWith(prefix))) return true;
  if (/^[0-9a-f]{8,32}$/i.test(username)) return true;
  if (/^[0-9a-f]{6,12}$/i.test(username) && /\d/.test(username)) return true;
  if (/^[a-z0-9]{6,10}$/i.test(username)) {
    const letters = username.replace(/[^a-z]/g, '');
    const vowels = (letters.match(/[aeiou]/g) || []).length;
    const hardConsonantRun = /[bcdfghjklmnpqrstvwxyz]{5,}/.test(letters);
    if (vowels === 0 || hardConsonantRun) return true;
  }
  return false;
}

function usernameNeedsOnboarding(user: any): boolean {
  const username = strictUsernameSlug(user?.username);
  if (!username) return true;
  const validation = validateUsernameForAccount(username, { allowGenerated: false });
  return !validation.ok || isLikelyGeneratedUsername(username);
}

function publicUsernameFor(user: any): string | null {
  return usernameNeedsOnboarding(user) ? null : strictUsernameSlug(user.username);
}

function validateUsernameForAccount(
  value: unknown,
  options: { allowGenerated?: boolean } = {}
): { ok: boolean; username: string; code?: string; detail?: string } {
  const username = strictUsernameSlug(value);
  if (username.length < 3) {
    return { ok: false, username, code: 'too_short', detail: 'Username must be at least 3 characters.' };
  }
  if (username.length > 20) {
    return { ok: false, username, code: 'too_long', detail: 'Username must be 20 characters or fewer.' };
  }
  if (!/^[a-z0-9_.]+$/.test(username)) {
    return { ok: false, username, code: 'invalid_format', detail: 'Use only letters, numbers, underscores, and periods.' };
  }
  if (username.startsWith('.') || username.endsWith('.') || username.includes('..')) {
    return { ok: false, username, code: 'invalid_format', detail: 'Username cannot start or end with a period or contain double periods.' };
  }
  if (isReservedOrStaffUsername(username)) {
    return { ok: false, username, code: 'reserved', detail: 'That username is reserved.' };
  }
  if (!options.allowGenerated && isLikelyGeneratedUsername(username)) {
    return { ok: false, username, code: 'blocked_word', detail: 'Choose a more personal username.' };
  }
  return { ok: true, username };
}

function pendingUsernameForUser(id: string): string {
  return `pending_${String(id || uuid()).replace(/[^a-z0-9]/gi, '').slice(0, 18).toLowerCase()}`;
}

async function ensureUniqueUsername(db: D1Database, desired: string): Promise<string> {
  const desiredSlug = strictUsernameSlug(desired);
  let base = (desiredSlug || usernameSlug(desired)).slice(0, 16).replace(/^\.+|\.+$/g, '');
  if (!validateUsernameForAccount(base, { allowGenerated: true }).ok || isReservedOrStaffUsername(base)) {
    base = 'captro.member';
  }
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const suffix = attempt === 0 ? '' : String(attempt).padStart(2, '0');
    const candidate = `${base.slice(0, Math.max(3, 20 - suffix.length))}${suffix}`;
    const existing = await db.prepare('SELECT id FROM users WHERE LOWER(username) = ?').bind(candidate.toLowerCase()).first();
    if (!existing) return candidate;
  }

  return pendingUsernameForUser(uuid());
}

let phoneAuthSchemaReady = false;
let oauthSchemaReady = false;
let supabaseAuthSchemaReady = false;
let privacySchemaReady = false;
let governanceSchemaReady = false;
let commentSchemaReady = false;
let mediaBackupSchemaReady = false;
let audioSchemaReady = false;
let postEditorSchemaReady = false;
let recommendationSchemaReady = false;
let aiMusicSchemaReady = false;
let notesSchemaReady = false;
let peopleSchemaReady = false;
let reliabilitySchemaReady = false;
let walletSchemaReady = false;
let premiumSchemaReady = false;
let abuseProtectionSchemaReady = false;
let messagePresenceSchemaReady = false;
let productionReadinessSchemaReady = false;
let adminModerationSchemaReady = false;
let autoCategorySchemaReady = false;
let locationSchemaReady = false;

function normalizeSchemaSql(statement: string): string {
  return statement.replace(/\s+/g, ' ').trim().replace(/;$/, '');
}

async function runSchemaStatement(db: D1Database, statement: string) {
  await db.exec(normalizeSchemaSql(statement));
}

function isIgnorableSchemaError(error: any, statement = ''): boolean {
  const message = String(error?.message || '').toLowerCase();
  return message.includes('duplicate column name')
    || message.includes('already exists')
    || (statement.includes('idx_users_phone') && message.includes('unique constraint failed'));
}

async function ensureOAuthSchema(db: D1Database) {
  if (oauthSchemaReady) return;

  const statements = [
    'ALTER TABLE users ADD COLUMN oauth_provider TEXT',
    'ALTER TABLE users ADD COLUMN oauth_subject TEXT',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_oauth_identity ON users(oauth_provider, oauth_subject)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  oauthSchemaReady = true;
}

async function ensureSupabaseAuthSchema(db: D1Database) {
  if (supabaseAuthSchemaReady) return;

  const statements = [
    'ALTER TABLE users ADD COLUMN supabase_user_id TEXT',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_supabase_user_id ON users(supabase_user_id)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  supabaseAuthSchemaReady = true;
}

async function ensureReliabilitySchema(db: D1Database) {
  if (reliabilitySchemaReady) return;

  const statements = [
    `CREATE TABLE IF NOT EXISTS request_rate_limits (
      key TEXT PRIMARY KEY,
      window_start INTEGER NOT NULL,
      count INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )`,
    'ALTER TABLE posts ADD COLUMN client_request_id TEXT',
    'ALTER TABLE comments ADD COLUMN client_request_id TEXT',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_posts_user_client_request ON posts(user_id, client_request_id)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_comments_user_client_request ON comments(user_id, client_request_id)',
    'CREATE INDEX IF NOT EXISTS idx_request_rate_limits_updated ON request_rate_limits(updated_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  reliabilitySchemaReady = true;
}

async function ensureMessagePresenceSchema(db: D1Database) {
  if (messagePresenceSchemaReady) return;

  const statements = [
    `CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      sender_id TEXT NOT NULL,
      receiver_id TEXT NOT NULL,
      content TEXT NOT NULL DEFAULT '',
      media_url TEXT,
      media_type TEXT,
      is_read INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now'))
    )`,
    'ALTER TABLE messages ADD COLUMN media_url TEXT',
    'ALTER TABLE messages ADD COLUMN media_type TEXT',
    'CREATE INDEX IF NOT EXISTS idx_messages_sender_receiver_created ON messages(sender_id, receiver_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_messages_receiver_read ON messages(receiver_id, is_read)',
    `CREATE TABLE IF NOT EXISTS user_presence (
      user_id TEXT PRIMARY KEY,
      last_seen_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS message_typing (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      peer_id TEXT NOT NULL,
      is_typing INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )`,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_message_typing_pair ON message_typing(user_id, peer_id)',
    'CREATE INDEX IF NOT EXISTS idx_message_typing_peer_updated ON message_typing(peer_id, updated_at)',
    'CREATE INDEX IF NOT EXISTS idx_user_presence_last_seen ON user_presence(last_seen_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  messagePresenceSchemaReady = true;
}

async function touchUserPresence(db: D1Database, userId: string) {
  if (!userId) return;
  await ensureMessagePresenceSchema(db);
  const timestamp = now();
  await db.prepare(`
    INSERT INTO user_presence (user_id, last_seen_at, updated_at)
    VALUES (?, ?, ?)
    ON CONFLICT(user_id) DO UPDATE SET
      last_seen_at = excluded.last_seen_at,
      updated_at = excluded.updated_at
  `).bind(userId, timestamp, timestamp).run();
}

function isPresenceOnline(lastSeenAt?: string | null): boolean {
  if (!lastSeenAt) return false;
  const lastSeen = Date.parse(lastSeenAt);
  return Number.isFinite(lastSeen) && Date.now() - lastSeen < 3 * 60 * 1000;
}

async function ensureWalletSchema(db: D1Database) {
  if (walletSchemaReady) return;

  const statements = [
    `CREATE TABLE IF NOT EXISTS coin_balances (
      user_id TEXT PRIMARY KEY,
      balance INTEGER NOT NULL DEFAULT 0 CHECK(balance >= 0),
      lifetime_purchased INTEGER NOT NULL DEFAULT 0,
      lifetime_spent INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS coin_transactions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      type TEXT NOT NULL,
      amount INTEGER NOT NULL,
      balance_after INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'completed',
      related_user_id TEXT DEFAULT '',
      related_id TEXT DEFAULT '',
      stripe_session_id TEXT DEFAULT '',
      stripe_payment_intent_id TEXT DEFAULT '',
      idempotency_key TEXT DEFAULT '',
      metadata TEXT DEFAULT '{}',
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS coin_purchase_orders (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      package_id TEXT DEFAULT '',
      coins INTEGER NOT NULL,
      amount_cents INTEGER NOT NULL,
      currency TEXT NOT NULL DEFAULT 'usd',
      stripe_session_id TEXT UNIQUE,
      stripe_payment_intent_id TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS coin_idempotency_keys (
      key TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      type TEXT NOT NULL,
      created_at TEXT NOT NULL
    )`,
    'CREATE INDEX IF NOT EXISTS idx_coin_transactions_user_created ON coin_transactions(user_id, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_coin_transactions_stripe_session ON coin_transactions(stripe_session_id)',
    'CREATE INDEX IF NOT EXISTS idx_coin_transactions_stripe_payment ON coin_transactions(stripe_payment_intent_id)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_coin_transactions_idempotency ON coin_transactions(idempotency_key) WHERE idempotency_key != \'\'',
    'CREATE INDEX IF NOT EXISTS idx_coin_purchase_orders_user_created ON coin_purchase_orders(user_id, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_coin_purchase_orders_session ON coin_purchase_orders(stripe_session_id)',
    'CREATE INDEX IF NOT EXISTS idx_coin_purchase_orders_payment ON coin_purchase_orders(stripe_payment_intent_id)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  walletSchemaReady = true;
}

async function ensurePremiumSchema(db: D1Database) {
  if (premiumSchemaReady) return;

  const statements = [
    'ALTER TABLE users ADD COLUMN is_premium INTEGER DEFAULT 0',
    "ALTER TABLE users ADD COLUMN premium_plan TEXT DEFAULT ''",
    "ALTER TABLE users ADD COLUMN premium_status TEXT DEFAULT ''",
    'ALTER TABLE users ADD COLUMN premium_until TEXT',
    "ALTER TABLE users ADD COLUMN premium_stripe_customer_id TEXT DEFAULT ''",
    "ALTER TABLE users ADD COLUMN premium_stripe_subscription_id TEXT DEFAULT ''",
    "ALTER TABLE users ADD COLUMN profile_background_image TEXT DEFAULT ''",
    `CREATE TABLE IF NOT EXISTS premium_subscriptions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      stripe_customer_id TEXT DEFAULT '',
      stripe_subscription_id TEXT UNIQUE,
      stripe_checkout_session_id TEXT DEFAULT '',
      price_id TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending',
      current_period_end TEXT,
      cancel_at_period_end INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    'CREATE INDEX IF NOT EXISTS idx_premium_subscriptions_user ON premium_subscriptions(user_id, updated_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_premium_subscriptions_customer ON premium_subscriptions(stripe_customer_id)',
    'CREATE INDEX IF NOT EXISTS idx_users_premium_status ON users(is_premium, premium_status)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  premiumSchemaReady = true;
}

async function ensurePrivacySchema(db: D1Database) {
  if (privacySchemaReady) return;

  const statements = [
    'ALTER TABLE users ADD COLUMN is_private INTEGER DEFAULT 0',
    "ALTER TABLE users ADD COLUMN language TEXT DEFAULT 'en'",
    "ALTER TABLE posts ADD COLUMN visibility TEXT DEFAULT 'public'",
    'ALTER TABLE posts ADD COLUMN pinned_at TEXT',
    "ALTER TABLE statuses ADD COLUMN visibility TEXT DEFAULT 'public'",
    'CREATE INDEX IF NOT EXISTS idx_users_private ON users(is_private)',
    'CREATE INDEX IF NOT EXISTS idx_posts_visibility ON posts(visibility)',
    'CREATE INDEX IF NOT EXISTS idx_posts_user_pinned ON posts(user_id, pinned_at DESC, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_statuses_visibility ON statuses(visibility)',
    'CREATE INDEX IF NOT EXISTS idx_statuses_created_at ON statuses(created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  privacySchemaReady = true;
}

async function ensurePostEditorSchema(db: D1Database) {
  if (postEditorSchemaReady) return;

  const statements = [
    "ALTER TABLE posts ADD COLUMN title TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN editor_overlays TEXT DEFAULT '[]'",
    "ALTER TABLE posts ADD COLUMN tagged_users TEXT DEFAULT '[]'",
    "ALTER TABLE posts ADD COLUMN media_dimensions TEXT DEFAULT '[]'",
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  postEditorSchemaReady = true;
}

async function ensureRecommendationSchema(db: D1Database) {
  if (recommendationSchemaReady) return;

  const statements = [
    `CREATE TABLE IF NOT EXISTS recommendations (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT DEFAULT '',
      category TEXT DEFAULT 'watch',
      tags TEXT DEFAULT '[]',
      external_url TEXT NOT NULL,
      provider TEXT DEFAULT 'link',
      external_id TEXT DEFAULT '',
      embed_url TEXT DEFAULT '',
      thumbnail_url TEXT DEFAULT '',
      creator_name TEXT DEFAULT '',
      status TEXT DEFAULT 'active',
      reports_count INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS recommendation_reports (
      id TEXT PRIMARY KEY,
      recommendation_id TEXT NOT NULL,
      reporter_id TEXT NOT NULL,
      reason TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      UNIQUE(recommendation_id, reporter_id)
    )`,
    'CREATE INDEX IF NOT EXISTS idx_recommendations_status_created ON recommendations(status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_recommendations_category ON recommendations(category, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_recommendations_user ON recommendations(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_recommendation_reports_rec ON recommendation_reports(recommendation_id, created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  const count: any = await db.prepare('SELECT COUNT(*) AS count FROM recommendations').first();
  if (Number(count?.count || 0) === 0) {
    const ts = now();
    const samples = [
      {
        id: 'rec-gatsby-book',
        title: 'The Great Gatsby',
        description: 'A sharp, stylish classic about status, desire, and reinvention. Good for anyone who likes beautiful writing with a little social heat.',
        category: 'books',
        tags: ['classic', 'novel', 'style'],
        external_url: 'https://www.gutenberg.org/ebooks/64317',
        provider: 'book',
        thumbnail_url: 'https://www.gutenberg.org/cache/epub/64317/pg64317.cover.medium.jpg',
        creator_name: 'F. Scott Fitzgerald',
      },
      {
        id: 'rec-arrival-trailer',
        title: 'Arrival',
        description: 'A quiet sci-fi movie recommendation for people who like mystery, language, emotion, and beautiful slow tension.',
        category: 'movies',
        tags: ['film', 'sci-fi', 'mood'],
        external_url: 'https://www.youtube.com/watch?v=tFMo3UJ4B4g',
        provider: 'youtube',
        external_id: 'tFMo3UJ4B4g',
        embed_url: 'https://www.youtube.com/embed/tFMo3UJ4B4g',
        thumbnail_url: 'https://img.youtube.com/vi/tFMo3UJ4B4g/hqdefault.jpg',
        creator_name: 'Paramount Pictures',
      },
      {
        id: 'rec-tiny-desk',
        title: 'Tiny Desk: soulful live sets',
        description: 'For discovering artists through live performance instead of scrolling random clips.',
        category: 'music',
        tags: ['music', 'live', 'artist'],
        external_url: 'https://www.youtube.com/watch?v=ferZnZ0_rSM',
        provider: 'youtube',
        external_id: 'ferZnZ0_rSM',
        embed_url: 'https://www.youtube.com/embed/ferZnZ0_rSM',
        thumbnail_url: 'https://img.youtube.com/vi/ferZnZ0_rSM/hqdefault.jpg',
        creator_name: 'NPR Music',
      },
      {
        id: 'rec-sherlock',
        title: 'Sherlock Holmes',
        description: 'A good pick when someone wants something smart, readable, and detective-story comfortable.',
        category: 'books',
        tags: ['mystery', 'classic', 'detective'],
        external_url: 'https://www.gutenberg.org/ebooks/1661',
        provider: 'book',
        thumbnail_url: '',
        creator_name: 'Arthur Conan Doyle',
      },
    ];

    for (const sample of samples) {
      await db.prepare(
        `INSERT OR IGNORE INTO recommendations
         (id, user_id, title, description, category, tags, external_url, provider, external_id, embed_url, thumbnail_url, creator_name, status, created_at, updated_at)
         VALUES (?, 'system', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)`
      ).bind(
        sample.id,
        sample.title,
        sample.description,
        sample.category,
        JSON.stringify(sample.tags),
        sample.external_url,
        sample.provider,
        sample.external_id || '',
        sample.embed_url || '',
        sample.thumbnail_url || '',
        sample.creator_name || '',
        ts,
        ts
      ).run();
    }
  }

  recommendationSchemaReady = true;
}

async function ensureAiMusicSchema(db: D1Database) {
  if (aiMusicSchemaReady) return;

  const statements = [
    `CREATE TABLE IF NOT EXISTS ai_music_posts (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      provider TEXT DEFAULT 'elevenlabs',
      prompt_text TEXT NOT NULL,
      lyrics_text TEXT DEFAULT '',
      mood TEXT NOT NULL,
      style TEXT NOT NULL,
      audio_url TEXT DEFAULT '',
      audio_r2_key TEXT DEFAULT '',
      audio_duration INTEGER DEFAULT 0,
      waveform_data TEXT DEFAULT '[]',
      status TEXT DEFAULT 'pending',
      is_public INTEGER DEFAULT 0,
      likes_count INTEGER DEFAULT 0,
      comments_count INTEGER DEFAULT 0,
      saves_count INTEGER DEFAULT 0,
      reposts_count INTEGER DEFAULT 0,
      reports_count INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS ai_music_interactions (
      id TEXT PRIMARY KEY,
      music_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(music_id, user_id, kind)
    )`,
    `CREATE TABLE IF NOT EXISTS ai_music_reports (
      id TEXT PRIMARY KEY,
      music_id TEXT NOT NULL,
      reporter_id TEXT NOT NULL,
      reason TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      UNIQUE(music_id, reporter_id)
    )`,
    `CREATE TABLE IF NOT EXISTS ai_music_comments (
      id TEXT PRIMARY KEY,
      music_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      parent_id TEXT DEFAULT '',
      body TEXT NOT NULL,
      likes_count INTEGER DEFAULT 0,
      status TEXT DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    'CREATE INDEX IF NOT EXISTS idx_ai_music_posts_public_created ON ai_music_posts(is_public, status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_ai_music_posts_user_created ON ai_music_posts(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_ai_music_interactions_user ON ai_music_interactions(user_id, kind, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_ai_music_reports_music ON ai_music_reports(music_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_ai_music_comments_music ON ai_music_comments(music_id, created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  aiMusicSchemaReady = true;
}

async function ensureNotesSchema(db: D1Database) {
  if (notesSchemaReady) return;

  const statements = [
    `CREATE TABLE IF NOT EXISTS notes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      body TEXT NOT NULL,
      note_type TEXT DEFAULT 'thought',
      mood TEXT DEFAULT 'soft',
      color TEXT DEFAULT '#F6E7D7',
      media_url TEXT DEFAULT '',
      media_type TEXT DEFAULT '',
      anonymous INTEGER DEFAULT 0,
      status TEXT DEFAULT 'active',
      reactions_count INTEGER DEFAULT 0,
      comments_count INTEGER DEFAULT 0,
      saves_count INTEGER DEFAULT 0,
      shares_count INTEGER DEFAULT 0,
      reports_count INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS note_interactions (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      value TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      UNIQUE(note_id, user_id, kind)
    )`,
    `CREATE TABLE IF NOT EXISTS note_comments (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      parent_id TEXT DEFAULT '',
      body TEXT NOT NULL,
      likes_count INTEGER DEFAULT 0,
      status TEXT DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS note_comment_likes (
      id TEXT PRIMARY KEY,
      comment_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(comment_id, user_id)
    )`,
    `CREATE TABLE IF NOT EXISTS note_reports (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      reporter_id TEXT NOT NULL,
      reason TEXT DEFAULT '',
      details TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      UNIQUE(note_id, reporter_id)
    )`,
    "ALTER TABLE notes ADD COLUMN media_url TEXT DEFAULT ''",
    "ALTER TABLE notes ADD COLUMN media_type TEXT DEFAULT ''",
    'CREATE INDEX IF NOT EXISTS idx_notes_status_created ON notes(status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_notes_user_created ON notes(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_note_interactions_user ON note_interactions(user_id, kind, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_note_comments_note ON note_comments(note_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_note_comment_likes_comment ON note_comment_likes(comment_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_note_reports_note ON note_reports(note_id, created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) throw error;
    }
  }

  notesSchemaReady = true;
}

async function ensurePeopleSchema(db: D1Database) {
  if (peopleSchemaReady) return;

  const statements = [
    `CREATE TABLE IF NOT EXISTS people_profiles (
      id TEXT PRIMARY KEY,
      owner_user_id TEXT DEFAULT '',
      name TEXT NOT NULL,
      role TEXT DEFAULT 'creator',
      category TEXT DEFAULT 'creator',
      bio TEXT DEFAULT '',
      known_for TEXT DEFAULT '',
      city TEXT DEFAULT '',
      profile_image TEXT DEFAULT '',
      instagram_url TEXT DEFAULT '',
      tiktok_url TEXT DEFAULT '',
      youtube_url TEXT DEFAULT '',
      website_url TEXT DEFAULT '',
      source_url TEXT DEFAULT '',
      claim_status TEXT DEFAULT 'unclaimed',
      status TEXT DEFAULT 'active',
      followers_count INTEGER DEFAULT 0,
      saves_count INTEGER DEFAULT 0,
      reports_count INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS people_interactions (
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(profile_id, user_id, kind)
    )`,
    `CREATE TABLE IF NOT EXISTS people_claims (
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      message TEXT DEFAULT '',
      evidence_url TEXT DEFAULT '',
      status TEXT DEFAULT 'pending',
      admin_notes TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS people_reports (
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL,
      reporter_id TEXT NOT NULL,
      reason TEXT DEFAULT '',
      details TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      UNIQUE(profile_id, reporter_id)
    )`,
    'CREATE INDEX IF NOT EXISTS idx_people_profiles_status ON people_profiles(status, updated_at)',
    'CREATE INDEX IF NOT EXISTS idx_people_profiles_category ON people_profiles(category, updated_at)',
    'CREATE INDEX IF NOT EXISTS idx_people_interactions_user ON people_interactions(user_id, kind, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_people_claims_status ON people_claims(status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_people_reports_profile ON people_reports(profile_id, created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) throw error;
    }
  }

  peopleSchemaReady = true;
}

async function ensureGovernanceSchema(db: D1Database) {
  if (governanceSchemaReady) return;

  const statements = [
    "ALTER TABLE users ADD COLUMN status TEXT DEFAULT 'active'",
    'ALTER TABLE users ADD COLUMN banned_at TEXT',
    'ALTER TABLE users ADD COLUMN ban_reason TEXT',
    "ALTER TABLE posts ADD COLUMN status TEXT DEFAULT 'active'",
    'ALTER TABLE posts ADD COLUMN removed_at TEXT',
    'ALTER TABLE posts ADD COLUMN removed_reason TEXT',
    "ALTER TABLE comments ADD COLUMN status TEXT DEFAULT 'active'",
    'ALTER TABLE comments ADD COLUMN removed_at TEXT',
    'ALTER TABLE comments ADD COLUMN removed_reason TEXT',
    "ALTER TABLE reports ADD COLUMN reported_type TEXT DEFAULT ''",
    "ALTER TABLE reports ADD COLUMN details TEXT DEFAULT ''",
    "ALTER TABLE reports ADD COLUMN status TEXT DEFAULT 'pending'",
    "ALTER TABLE reports ADD COLUMN admin_notes TEXT DEFAULT ''",
    'ALTER TABLE reports ADD COLUMN reviewed_by TEXT',
    'ALTER TABLE reports ADD COLUMN reviewed_at TEXT',
    "ALTER TABLE reports ADD COLUMN action_taken TEXT DEFAULT ''",
    "ALTER TABLE reports ADD COLUMN priority TEXT DEFAULT 'normal'",
    'ALTER TABLE reports ADD COLUMN updated_at TEXT',
    `CREATE TABLE IF NOT EXISTS admin_actions (
      id TEXT PRIMARY KEY,
      admin_id TEXT NOT NULL,
      action_type TEXT NOT NULL,
      target_type TEXT NOT NULL,
      target_id TEXT NOT NULL,
      details TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )`,
    'CREATE INDEX IF NOT EXISTS idx_users_status ON users(status)',
    'CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status)',
    'CREATE INDEX IF NOT EXISTS idx_comments_status_post ON comments(status, post_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status)',
    'CREATE INDEX IF NOT EXISTS idx_reports_priority_status ON reports(priority, status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_admin_actions_created ON admin_actions(created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  governanceSchemaReady = true;
}

async function ensureAdminModerationSchema(db: D1Database) {
  if (adminModerationSchemaReady) return;
  await ensureGovernanceSchema(db);
  await ensureCommentSchema(db);
  await ensureMessagePresenceSchema(db);

  const statements = [
    "ALTER TABLE users ADD COLUMN suspended_until TEXT",
    "ALTER TABLE users ADD COLUMN warning_count INTEGER DEFAULT 0",
    "ALTER TABLE reports ADD COLUMN target_owner_user_id TEXT DEFAULT ''",
    "ALTER TABLE reports ADD COLUMN assigned_to TEXT DEFAULT ''",
    "ALTER TABLE reports ADD COLUMN closed_at TEXT",
    "ALTER TABLE posts ADD COLUMN discover_blocked_at TEXT",
    "ALTER TABLE posts ADD COLUMN discover_blocked_by TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN discover_blocked_reason TEXT DEFAULT ''",
    "ALTER TABLE messages ADD COLUMN status TEXT DEFAULT 'active'",
    "ALTER TABLE messages ADD COLUMN removed_at TEXT",
    "ALTER TABLE messages ADD COLUMN removed_by TEXT DEFAULT ''",
    "ALTER TABLE messages ADD COLUMN removed_reason TEXT DEFAULT ''",
    `CREATE TABLE IF NOT EXISTS admin_roles (
      user_id TEXT PRIMARY KEY,
      role TEXT NOT NULL,
      created_at TEXT NOT NULL,
      created_by TEXT DEFAULT '',
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS moderation_notes (
      id TEXT PRIMARY KEY,
      report_id TEXT DEFAULT '',
      target_type TEXT NOT NULL,
      target_id TEXT NOT NULL,
      author_admin_user_id TEXT NOT NULL,
      note TEXT NOT NULL,
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS moderation_actions (
      id TEXT PRIMARY KEY,
      actor_admin_user_id TEXT NOT NULL,
      actor_role TEXT NOT NULL,
      action_type TEXT NOT NULL,
      target_type TEXT NOT NULL,
      target_id TEXT NOT NULL,
      target_user_id TEXT DEFAULT '',
      reason TEXT DEFAULT '',
      note TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS audit_logs (
      id TEXT PRIMARY KEY,
      actor_admin_user_id TEXT NOT NULL,
      actor_role TEXT NOT NULL,
      action_type TEXT NOT NULL,
      target_type TEXT NOT NULL,
      target_id TEXT NOT NULL,
      target_user_id TEXT DEFAULT '',
      reason TEXT DEFAULT '',
      internal_note TEXT DEFAULT '',
      before_state TEXT DEFAULT '{}',
      after_state TEXT DEFAULT '{}',
      ip_hash TEXT DEFAULT '',
      request_id TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS user_restrictions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      restriction_type TEXT NOT NULL,
      reason TEXT DEFAULT '',
      starts_at TEXT NOT NULL,
      ends_at TEXT,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL
    )`,
    'CREATE INDEX IF NOT EXISTS idx_admin_roles_role ON admin_roles(role)',
    'CREATE INDEX IF NOT EXISTS idx_reports_target_status ON reports(reported_type, reported_id, status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_reports_target_owner ON reports(target_owner_user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_moderation_notes_report ON moderation_notes(report_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_moderation_notes_target ON moderation_notes(target_type, target_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_moderation_actions_target ON moderation_actions(target_type, target_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_moderation_actions_actor ON moderation_actions(actor_admin_user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at)',
    'CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs(actor_admin_user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_audit_logs_target ON audit_logs(target_type, target_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_user_restrictions_user_active ON user_restrictions(user_id, restriction_type, starts_at, ends_at)',
    'CREATE INDEX IF NOT EXISTS idx_messages_status_created ON messages(status, created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  adminModerationSchemaReady = true;
}

async function ensureAutoCategorySchema(db: D1Database) {
  if (autoCategorySchemaReady) return;

  const statements = [
    "ALTER TABLE posts ADD COLUMN primary_category TEXT DEFAULT 'lifestyle'",
    'ALTER TABLE posts ADD COLUMN category_confidence REAL DEFAULT 0',
    "ALTER TABLE posts ADD COLUMN category_source TEXT DEFAULT 'fallback'",
    "ALTER TABLE posts ADD COLUMN category_status TEXT DEFAULT 'low_confidence'",
    "ALTER TABLE posts ADD COLUMN category_signals_json TEXT DEFAULT '{}'",
    "ALTER TABLE posts ADD COLUMN tags_json TEXT DEFAULT '[]'",
    'CREATE INDEX IF NOT EXISTS idx_posts_primary_category_created ON posts(primary_category, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_posts_category_status_created ON posts(category_status, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_posts_discover_category_created ON posts(primary_category, status, visibility, created_at DESC)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  autoCategorySchemaReady = true;
}

async function ensureLocationSchema(db: D1Database) {
  if (locationSchemaReady) return;

  const statements = [
    "ALTER TABLE posts ADD COLUMN display_city TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN display_region TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN display_country TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN display_location_label TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN display_location_source TEXT DEFAULT 'none'",
    "ALTER TABLE posts ADD COLUMN display_location_visibility TEXT DEFAULT 'hidden'",
    "ALTER TABLE posts ADD COLUMN place_provider TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN place_provider_id TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN place_formatted_address TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN place_category TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN place_city TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN place_region TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN place_country TEXT DEFAULT ''",
    `CREATE TABLE IF NOT EXISTS post_places (
      id TEXT PRIMARY KEY,
      post_id TEXT NOT NULL,
      provider TEXT DEFAULT 'apple_mapkit',
      provider_place_id TEXT DEFAULT '',
      name TEXT DEFAULT '',
      formatted_address TEXT DEFAULT '',
      latitude REAL,
      longitude REAL,
      category TEXT DEFAULT '',
      city TEXT DEFAULT '',
      region TEXT DEFAULT '',
      country TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )`,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_post_places_post_provider ON post_places(post_id, provider)',
    'CREATE INDEX IF NOT EXISTS idx_post_places_post ON post_places(post_id)',
    'CREATE INDEX IF NOT EXISTS idx_posts_display_location ON posts(display_location_visibility, display_city, display_country, created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  locationSchemaReady = true;
}

async function ensureAbuseProtectionSchema(db: D1Database) {
  if (abuseProtectionSchemaReady) return;
  await ensureGovernanceSchema(db);

  const statements = [
    `CREATE TABLE IF NOT EXISTS security_events (
      id TEXT PRIMARY KEY,
      event_type TEXT NOT NULL,
      user_id TEXT DEFAULT '',
      ip TEXT DEFAULT '',
      metadata TEXT DEFAULT '{}',
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS notifications (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      type TEXT DEFAULT 'general',
      title TEXT DEFAULT '',
      body TEXT DEFAULT '',
      data TEXT DEFAULT '{}',
      is_read INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now'))
    )`,
    `CREATE TABLE IF NOT EXISTS blocks (
      id TEXT PRIMARY KEY,
      blocker_id TEXT NOT NULL,
      blocked_id TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(blocker_id, blocked_id)
    )`,
    `CREATE TABLE IF NOT EXISTS call_sessions (
      id TEXT PRIMARY KEY,
      caller_id TEXT NOT NULL,
      callee_id TEXT NOT NULL,
      caller_name TEXT DEFAULT '',
      caller_avatar TEXT DEFAULT '',
      callee_name TEXT DEFAULT '',
      callee_avatar TEXT DEFAULT '',
      call_type TEXT DEFAULT 'video',
      status TEXT DEFAULT 'ringing',
      room_id TEXT NOT NULL,
      channel_name TEXT NOT NULL,
      push_delivery_status TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      answered_at TEXT DEFAULT '',
      ended_at TEXT DEFAULT '',
      timeout_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS voip_push_tokens (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      token TEXT NOT NULL,
      device_id TEXT DEFAULT '',
      bundle_id TEXT DEFAULT '',
      environment TEXT DEFAULT 'production',
      platform TEXT DEFAULT 'ios',
      is_active INTEGER DEFAULT 1,
      last_seen_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(user_id, token)
    )`,
    `CREATE TABLE IF NOT EXISTS abuse_signals (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      signal_type TEXT NOT NULL,
      signal_hash TEXT NOT NULL,
      source TEXT DEFAULT '',
      first_seen_at TEXT NOT NULL,
      last_seen_at TEXT NOT NULL,
      UNIQUE(user_id, signal_type, signal_hash)
    )`,
    `CREATE TABLE IF NOT EXISTS ban_evasion_flags (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      matched_user_id TEXT DEFAULT '',
      signal_type TEXT NOT NULL,
      source TEXT DEFAULT '',
      reason TEXT DEFAULT '',
      status TEXT DEFAULT 'pending',
      admin_notes TEXT DEFAULT '',
      reviewed_by TEXT DEFAULT '',
      reviewed_at TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(user_id, matched_user_id, signal_type)
    )`,
    'CREATE INDEX IF NOT EXISTS idx_security_events_type_created ON security_events(event_type, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_security_events_user_created ON security_events(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_notifications_user_type_created ON notifications(user_id, type, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON blocks(blocker_id, blocked_id)',
    'CREATE INDEX IF NOT EXISTS idx_call_sessions_callee_status ON call_sessions(callee_id, status, timeout_at)',
    'CREATE INDEX IF NOT EXISTS idx_call_sessions_caller_status ON call_sessions(caller_id, status, timeout_at)',
    'CREATE INDEX IF NOT EXISTS idx_voip_push_tokens_user ON voip_push_tokens(user_id, is_active, last_seen_at)',
    'CREATE INDEX IF NOT EXISTS idx_abuse_signals_hash ON abuse_signals(signal_type, signal_hash, user_id)',
    'CREATE INDEX IF NOT EXISTS idx_abuse_signals_user ON abuse_signals(user_id, last_seen_at)',
    'CREATE INDEX IF NOT EXISTS idx_ban_evasion_flags_status ON ban_evasion_flags(status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_ban_evasion_flags_user ON ban_evasion_flags(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_reports_reporter_target ON reports(reporter_id, reported_type, reported_id, created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  abuseProtectionSchemaReady = true;
}

async function ensureProductionReadinessSchema(db: D1Database) {
  if (productionReadinessSchemaReady) return;

  const statements = [
    `CREATE TABLE IF NOT EXISTS push_tokens (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      token TEXT NOT NULL,
      device_id TEXT DEFAULT '',
      bundle_id TEXT DEFAULT '',
      environment TEXT DEFAULT 'production',
      platform TEXT DEFAULT 'ios',
      is_active INTEGER DEFAULT 1,
      last_seen_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(user_id, token)
    )`,
    `CREATE TABLE IF NOT EXISTS client_events (
      id TEXT PRIMARY KEY,
      user_id TEXT DEFAULT '',
      event_name TEXT NOT NULL,
      category TEXT DEFAULT '',
      status TEXT DEFAULT '',
      duration_ms INTEGER DEFAULT 0,
      metadata TEXT DEFAULT '{}',
      app_version TEXT DEFAULT '',
      platform TEXT DEFAULT 'ios',
      created_at TEXT NOT NULL
    )`,
    'CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON push_tokens(user_id, is_active, last_seen_at)',
    'CREATE INDEX IF NOT EXISTS idx_client_events_name_created ON client_events(event_name, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_client_events_user_created ON client_events(user_id, created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  productionReadinessSchemaReady = true;
}

async function ensureMediaBackupSchema(db: D1Database) {
  if (mediaBackupSchemaReady) return;

  const statements = [
    "ALTER TABLE posts ADD COLUMN media_backup_ids TEXT DEFAULT '[]'",
    `CREATE TABLE IF NOT EXISTS media_backups (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      post_id TEXT,
      message_id TEXT DEFAULT '',
      group_message_id TEXT DEFAULT '',
      media_kind TEXT NOT NULL,
      provider TEXT NOT NULL,
      provider_id TEXT DEFAULT '',
      delivery_url TEXT DEFAULT '',
      r2_key TEXT NOT NULL,
      content_type TEXT DEFAULT '',
      size_bytes INTEGER DEFAULT 0,
      checksum_sha256 TEXT DEFAULT '',
      original_filename TEXT DEFAULT '',
      backup_status TEXT DEFAULT 'stored',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    "ALTER TABLE media_backups ADD COLUMN message_id TEXT DEFAULT ''",
    "ALTER TABLE media_backups ADD COLUMN group_message_id TEXT DEFAULT ''",
    'CREATE INDEX IF NOT EXISTS idx_media_backups_user ON media_backups(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_media_backups_post ON media_backups(post_id)',
    'CREATE INDEX IF NOT EXISTS idx_media_backups_message ON media_backups(message_id)',
    'CREATE INDEX IF NOT EXISTS idx_media_backups_group_message ON media_backups(group_message_id)',
    'CREATE INDEX IF NOT EXISTS idx_media_backups_r2_key ON media_backups(r2_key)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  mediaBackupSchemaReady = true;
}

async function ensureAudioSchema(db: D1Database) {
  if (audioSchemaReady) return;

  const statements = [
    "ALTER TABLE posts ADD COLUMN audio_provider TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN audio_track_id TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN audio_title TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN audio_artist TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN audio_artwork_url TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN audio_stream_url TEXT DEFAULT ''",
    'ALTER TABLE posts ADD COLUMN audio_start_time INTEGER DEFAULT 0',
    'ALTER TABLE posts ADD COLUMN audio_duration INTEGER DEFAULT 0',
    'ALTER TABLE posts ADD COLUMN audio_hidden INTEGER DEFAULT 0',
    "ALTER TABLE statuses ADD COLUMN audio_provider TEXT DEFAULT ''",
    "ALTER TABLE statuses ADD COLUMN audio_track_id TEXT DEFAULT ''",
    "ALTER TABLE statuses ADD COLUMN audio_title TEXT DEFAULT ''",
    "ALTER TABLE statuses ADD COLUMN audio_artist TEXT DEFAULT ''",
    "ALTER TABLE statuses ADD COLUMN audio_artwork_url TEXT DEFAULT ''",
    "ALTER TABLE statuses ADD COLUMN audio_stream_url TEXT DEFAULT ''",
    'ALTER TABLE statuses ADD COLUMN audio_start_time INTEGER DEFAULT 0',
    'ALTER TABLE statuses ADD COLUMN audio_duration INTEGER DEFAULT 0',
    'ALTER TABLE statuses ADD COLUMN audio_hidden INTEGER DEFAULT 0',
    `CREATE TABLE IF NOT EXISTS hidden_sounds (
      track_id TEXT PRIMARY KEY,
      provider TEXT DEFAULT 'audius',
      reason TEXT DEFAULT '',
      hidden_by TEXT,
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS favorite_sounds (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      provider TEXT DEFAULT 'audius',
      track_id TEXT NOT NULL,
      title TEXT DEFAULT '',
      artist TEXT DEFAULT '',
      artwork_url TEXT DEFAULT '',
      duration INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(user_id, provider, track_id)
    )`,
    "ALTER TABLE favorite_sounds ADD COLUMN artist_id TEXT DEFAULT ''",
    "ALTER TABLE favorite_sounds ADD COLUMN artist_handle TEXT DEFAULT ''",
    "ALTER TABLE favorite_sounds ADD COLUMN artist_profile_image TEXT DEFAULT ''",
    "ALTER TABLE favorite_sounds ADD COLUMN genre TEXT DEFAULT ''",
    'ALTER TABLE favorite_sounds ADD COLUMN play_count INTEGER DEFAULT 0',
    'ALTER TABLE favorite_sounds ADD COLUMN favorite_count INTEGER DEFAULT 0',
    'CREATE INDEX IF NOT EXISTS idx_posts_audio_track ON posts(audio_provider, audio_track_id)',
    'CREATE INDEX IF NOT EXISTS idx_statuses_audio_track ON statuses(audio_provider, audio_track_id)',
    'CREATE INDEX IF NOT EXISTS idx_hidden_sounds_provider ON hidden_sounds(provider, track_id)',
    'CREATE INDEX IF NOT EXISTS idx_favorite_sounds_user ON favorite_sounds(user_id, provider, created_at)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  audioSchemaReady = true;
}

function normalizeLanguage(value: unknown): 'en' | 'fr' | 'es' {
  return value === 'fr' || value === 'es' ? value : 'en';
}

function normalizeSqlBoolean(value: unknown): number {
  return value === true || value === 1 || value === '1' || value === 'true' ? 1 : 0;
}

type PostVisibility = 'public' | 'followers' | 'friends' | 'private';

function normalizeVisibility(value: unknown): PostVisibility {
  return value === 'followers' || value === 'friends' || value === 'private' ? value : 'public';
}

function visibleAuthorWhere(alias = 'u'): string {
  return `(${alias}.id = ? OR COALESCE(${alias}.is_private, 0) = 0 OR EXISTS (SELECT 1 FROM friendships f WHERE f.user_id = ? AND f.friend_id = ${alias}.id))
    AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = ${alias}.id) OR (b.blocker_id = ${alias}.id AND b.blocked_id = ?))`;
}

function visibleStatusWhere(userAlias = 'u', statusAlias = 's'): string {
  return `(${statusAlias}.user_id = ? OR (COALESCE(${statusAlias}.visibility, 'public') = 'public' AND COALESCE(${userAlias}.is_private, 0) = 0) OR EXISTS (SELECT 1 FROM friendships f WHERE f.user_id = ? AND f.friend_id = ${statusAlias}.user_id))`;
}

function visiblePostWhere(userAlias = 'u', postAlias = 'p'): string {
  return `COALESCE(${postAlias}.status, 'active') != 'removed' AND ${visibleAuthorWhere(userAlias)} AND (
    COALESCE(${postAlias}.visibility, 'public') = 'public'
    OR ${postAlias}.user_id = ?
    OR (COALESCE(${postAlias}.visibility, 'public') = 'followers' AND (
      EXISTS (SELECT 1 FROM follows fl WHERE fl.follower_id = ? AND fl.following_id = ${postAlias}.user_id)
      OR EXISTS (SELECT 1 FROM friendships f2 WHERE f2.user_id = ? AND f2.friend_id = ${postAlias}.user_id)
    ))
    OR (COALESCE(${postAlias}.visibility, 'public') = 'friends' AND EXISTS (SELECT 1 FROM friendships f3 WHERE f3.user_id = ? AND f3.friend_id = ${postAlias}.user_id))
  )`;
}

function visiblePostBindValues(userId: string): string[] {
  return [userId, userId, userId, userId, userId, userId, userId, userId];
}

function publicPostWhere(userAlias = 'u', postAlias = 'p'): string {
  return `COALESCE(${postAlias}.status, 'active') != 'removed' AND COALESCE(${userAlias}.is_private, 0) = 0 AND COALESCE(${postAlias}.visibility, 'public') = 'public'`;
}

function parseJsonArray(value: unknown): any[] {
  if (Array.isArray(value)) return value;
  const text = String(value || '').trim();
  if (!text) return [];
  try {
    const parsed = JSON.parse(text);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function clampNumber(value: unknown, min: number, max: number, fallback: number): number {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return fallback;
  return Math.max(min, Math.min(max, Math.round(numeric)));
}

function stripHtmlMetaCharacters(value: string): string {
  return value.replace(/[<>"'`]/g, '');
}

function cleanText(value: unknown, max = 500): string {
  return stripHtmlMetaCharacters(String(value || ''))
    .replace(/[\u0000-\u001F\u007F]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function cleanMultilineText(value: unknown, max = 5000): string {
  return stripHtmlMetaCharacters(String(value || ''))
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, ' ')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .trim()
    .slice(0, max);
}

function publicId(value: unknown, max = 120): string {
  return String(value || '').trim().replace(/[^a-zA-Z0-9_.:-]/g, '').slice(0, max);
}

function rejectUnknownFields(c: any, body: any, allowedFields: string[]) {
  const allowed = new Set(allowedFields);
  const unknown = Object.keys(body || {}).filter((key) => !allowed.has(key));
  if (unknown.length > 0) {
    return c.json({
      detail: 'Request contains unsupported fields.',
      fields: unknown.slice(0, 8).map((key) => cleanText(key, 80)),
    }, 400);
  }
  return null;
}

type DiscoverCategory =
  | 'photography'
  | 'outdoors'
  | 'outfits'
  | 'travel'
  | 'events'
  | 'nightlife'
  | 'art'
  | 'lifestyle'
  | 'fitness';

type AutoCategorySource = 'apple_vision' | 'backend_ai' | 'hybrid_ai' | 'fallback' | 'admin_changed' | 'user_changed_optional';
type AutoCategoryStatus = 'pending' | 'classified' | 'low_confidence' | 'needs_review' | 'admin_corrected';

type AutoCategoryLabel = {
  label: string;
  confidence: number;
  source?: string;
};

type AutoCategoryInput = {
  caption?: string;
  mediaType?: string;
  postType?: string;
  hashtags?: string[];
  location?: string | null;
  placeName?: string | null;
  appleLabels?: AutoCategoryLabel[];
  appleCategoryGuess?: string;
  appleConfidence?: number;
  backendLabels?: AutoCategoryLabel[];
  backendCategoryGuess?: string;
  backendConfidence?: number;
};

type AutoCategoryResult = {
  primary_category: DiscoverCategory;
  category_confidence: number;
  category_source: AutoCategorySource;
  category_status: AutoCategoryStatus;
  tags: string[];
  signals: Record<string, unknown>;
};

const DISCOVER_CATEGORIES: DiscoverCategory[] = [
  'photography',
  'outdoors',
  'outfits',
  'travel',
  'events',
  'nightlife',
  'art',
  'lifestyle',
  'fitness',
];

const CATEGORY_KEYWORDS: Record<DiscoverCategory, string[]> = {
  outfits: ['outfit', 'fit', 'fit check', 'clothes', 'style', 'fashion', 'streetwear', 'shoes', 'shoe', 'jacket', 'mirror selfie', 'clothing', 'accessories', 'sneakers', 'dress', 'apparel', 'person'],
  outdoors: ['outdoors', 'outdoor', 'outside', 'park', 'beach', 'hiking', 'trail', 'nature', 'mountain', 'lake', 'sunset', 'sunrise', 'trees', 'tree', 'forest', 'walking', 'landscape', 'snow', 'sky', 'water', 'river', 'ocean', 'sea', 'flower', 'plant', 'grass', 'garden', 'field', 'woods', 'camping'],
  events: ['event', 'concert', 'festival', 'meetup', 'show', 'game', 'crowd', 'stadium', 'venue', 'performance', 'birthday', 'wedding', 'audience', 'stage', 'party', 'celebration'],
  nightlife: ['nightlife', 'night', 'club', 'bar', 'lounge', 'party', 'rooftop', 'dj', 'drinks', 'city night', 'after dark', 'dance', 'neon', 'dark', 'cocktail', 'evening'],
  travel: ['travel', 'trip', 'vacation', 'hotel', 'airport', 'landmark', 'city visit', 'tourist', 'destination', 'road trip', 'passport', 'flight', 'city', 'street', 'architecture', 'building', 'castle', 'monument', 'bridge', 'train', 'station', 'historic', 'old town', 'view'],
  photography: ['photography', 'portrait', 'camera', 'photo shoot', 'street photo', 'aesthetic', 'landscape shot', 'creative shot', 'close up', 'close-up', 'lens', 'film', 'macro', 'black and white', 'monochrome', 'composition'],
  art: ['art', 'drawing', 'painting', 'design', 'sketch', 'illustration', 'mural', 'gallery', 'creative work', 'museum', 'artist', 'craft', 'sculpture', 'visual art'],
  fitness: ['gym', 'workout', 'running', 'fitness', 'sport', 'basketball', 'soccer', 'training', 'yoga', 'exercise', 'athlete', 'cycling', 'bike', 'bicycle'],
  lifestyle: ['daily life', 'friends', 'home', 'routine', 'random moment', 'personal moment', 'general capture', 'selfie', 'room', 'people', 'human', 'family'],
};

function normalizeDiscoverCategory(value: unknown, allowAll = false): DiscoverCategory | 'all' | '' {
  const clean = cleanText(value, 40).toLowerCase().replace(/[\s-]+/g, '_');
  if (allowAll && clean === 'all') return 'all';
  return DISCOVER_CATEGORIES.includes(clean as DiscoverCategory) ? clean as DiscoverCategory : '';
}

function normalizeCategorySource(value: unknown): AutoCategorySource {
  const clean = cleanText(value, 40).toLowerCase().replace(/[\s-]+/g, '_');
  return ['apple_vision', 'backend_ai', 'hybrid_ai', 'fallback', 'admin_changed', 'user_changed_optional'].includes(clean)
    ? clean as AutoCategorySource
    : 'fallback';
}

function normalizeCategoryStatus(value: unknown): AutoCategoryStatus {
  const clean = cleanText(value, 40).toLowerCase().replace(/[\s-]+/g, '_');
  return ['pending', 'classified', 'low_confidence', 'needs_review', 'admin_corrected'].includes(clean)
    ? clean as AutoCategoryStatus
    : 'low_confidence';
}

function sanitizeAutoCategoryTags(value: unknown): string[] {
  const raw = Array.isArray(value) ? value : parseJsonArray(value);
  const seen = new Set<string>();
  return raw
    .flatMap((item) => String(item || '').split(/[#,]/g))
    .map((item) => cleanText(item, 40).toLowerCase().replace(/[^a-z0-9_. -]/g, '').trim())
    .filter((item) => item.length >= 2 && item.length <= 40 && !seen.has(item) && seen.add(item))
    .slice(0, 20);
}

function sanitizeAutoCategoryLabels(value: unknown): AutoCategoryLabel[] {
  const raw = Array.isArray(value) ? value : parseJsonArray(value);
  const labels: AutoCategoryLabel[] = [];
  for (const item of raw) {
    const label = typeof item === 'string'
      ? cleanText(item, 80).toLowerCase()
      : cleanText((item as any)?.label || (item as any)?.identifier || (item as any)?.name, 80).toLowerCase();
    if (!label) continue;
    const confidence = typeof item === 'string'
      ? 0.72
      : clampFloat((item as any)?.confidence ?? (item as any)?.score ?? (item as any)?.probability, 0, 1, 0.70);
    labels.push({ label, confidence, source: cleanText((item as any)?.source || '', 40) || undefined });
  }
  return labels.slice(0, 24);
}

function categoryTextMatches(text: string, keyword: string): boolean {
  const cleanTextValue = text.toLowerCase();
  const cleanKeyword = keyword.toLowerCase();
  return cleanKeyword.includes(' ')
    ? cleanTextValue.includes(cleanKeyword)
    : new RegExp(`(^|[^a-z0-9])${cleanKeyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^a-z0-9]|$)`, 'i').test(cleanTextValue);
}

function collectHashtagsFromText(text: string): string[] {
  const matches = text.match(/#[a-zA-Z0-9_.]{2,40}/g) || [];
  return matches.map((tag) => tag.replace(/^#/, '').toLowerCase());
}

function scoreCategoryFromText(scores: Record<DiscoverCategory, number>, text: string, weight: number) {
  if (!text) return;
  for (const category of DISCOVER_CATEGORIES) {
    for (const keyword of CATEGORY_KEYWORDS[category]) {
      if (categoryTextMatches(text, keyword)) {
        scores[category] += weight;
      }
    }
  }
}

function categoryFromLabels(labels: AutoCategoryLabel[]): { category: DiscoverCategory | ''; confidence: number } {
  const scores = Object.fromEntries(DISCOVER_CATEGORIES.map((category) => [category, 0])) as Record<DiscoverCategory, number>;
  for (const label of labels) {
    for (const category of DISCOVER_CATEGORIES) {
      for (const keyword of CATEGORY_KEYWORDS[category]) {
        if (categoryTextMatches(label.label, keyword)) {
          scores[category] += Math.max(0.1, label.confidence);
        }
      }
    }
  }
  const winner = DISCOVER_CATEGORIES
    .map((category) => ({ category, score: scores[category] }))
    .sort((a, b) => b.score - a.score)[0];
  return winner && winner.score > 0
    ? { category: winner.category, confidence: Math.min(1, winner.score / 2.4) }
    : { category: '', confidence: 0 };
}

function autoCategoryEngine(input: AutoCategoryInput): AutoCategoryResult {
  const scores = Object.fromEntries(DISCOVER_CATEGORIES.map((category) => [category, 0])) as Record<DiscoverCategory, number>;
  const tags = new Set<string>();
  const caption = cleanMultilineText(input.caption || '', 5000).toLowerCase();
  const hashtags = sanitizeAutoCategoryTags([...(input.hashtags || []), ...collectHashtagsFromText(caption)]);
  const placeText = [input.location, input.placeName, input.postType].map((item) => cleanText(item, 160).toLowerCase()).filter(Boolean).join(' ');
  const appleGuess = normalizeDiscoverCategory(input.appleCategoryGuess, false) as DiscoverCategory | '';
  const backendGuess = normalizeDiscoverCategory(input.backendCategoryGuess, false) as DiscoverCategory | '';
  const appleConfidence = clampFloat(input.appleConfidence, 0, 1, 0);
  const backendConfidence = clampFloat(input.backendConfidence, 0, 1, 0);
  const appleLabels = sanitizeAutoCategoryLabels(input.appleLabels || []);
  const backendLabels = sanitizeAutoCategoryLabels(input.backendLabels || []);

  if (backendGuess) scores[backendGuess] += 45 * Math.max(backendConfidence, 0.55);
  if (appleGuess) scores[appleGuess] += 30 * Math.max(appleConfidence, 0.55);
  scoreCategoryFromText(scores, caption, 25);
  scoreCategoryFromText(scores, hashtags.join(' '), 25);
  scoreCategoryFromText(scores, placeText, placeText.includes('event') || placeText.includes('venue') ? 50 : 40);

  for (const { category, confidence } of [categoryFromLabels(appleLabels), categoryFromLabels(backendLabels)]) {
    if (category) scores[category] += Math.round(confidence * 30);
  }

  for (const tag of hashtags) tags.add(tag);
  [...appleLabels, ...backendLabels]
    .sort((a, b) => b.confidence - a.confidence)
    .slice(0, 12)
    .forEach((item) => {
      const label = cleanText(item.label, 40).toLowerCase().replace(/[^a-z0-9_. -]/g, '').trim();
      if (label.length >= 2) tags.add(label);
    });

  const winner = DISCOVER_CATEGORIES
    .map((category) => ({ category, score: scores[category] }))
    .sort((a, b) => b.score - a.score)[0];
  const rawConfidence = winner ? Math.min(0.99, Math.max(0, winner.score / 100)) : 0;
  const confidence = Number(rawConfidence.toFixed(2));
  const isLow = confidence < 0.50;
  const primaryCategory = isLow ? 'lifestyle' : winner.category;
  const source: AutoCategorySource = backendGuess || backendLabels.length
    ? (appleGuess || appleLabels.length ? 'hybrid_ai' : 'backend_ai')
    : appleGuess || appleLabels.length
      ? 'apple_vision'
      : 'fallback';
  const status: AutoCategoryStatus = isLow ? 'low_confidence' : 'classified';

  return {
    primary_category: primaryCategory,
    category_confidence: isLow ? Math.max(confidence, 0.35) : confidence,
    category_source: isLow ? 'fallback' : source,
    category_status: status,
    tags: Array.from(tags).slice(0, 16),
    signals: {
      apple_category_guess: appleGuess || '',
      apple_confidence: appleConfidence || 0,
      apple_labels: appleLabels,
      backend_category_guess: backendGuess || '',
      backend_confidence: backendConfidence || 0,
      backend_labels: backendLabels,
      caption_hashtags: hashtags,
      scores,
    },
  };
}

function autoCategoryFromBody(body: any, input: Omit<AutoCategoryInput, 'appleLabels' | 'appleCategoryGuess' | 'appleConfidence'>): AutoCategoryResult {
  return autoCategoryEngine({
    ...input,
    hashtags: sanitizeAutoCategoryTags([
      ...(input.hashtags || []),
      ...sanitizeAutoCategoryTags(body.tags),
      ...sanitizeAutoCategoryTags(body.hashtags),
    ]),
    appleLabels: sanitizeAutoCategoryLabels(body.apple_vision_labels || body.appleVisionLabels),
    appleCategoryGuess: body.apple_vision_category_guess || body.appleVisionCategoryGuess,
    appleConfidence: clampFloat(body.apple_vision_confidence ?? body.appleVisionConfidence, 0, 1, 0),
  });
}

function safeRateLimitPart(value: unknown): string {
  const clean = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_.:@-]/g, '_')
    .slice(0, 120);
  return clean || 'anonymous';
}

function clientIp(c: any): string {
  const forwarded = String(c.req.header('X-Forwarded-For') || '').split(',')[0]?.trim();
  return String(c.req.header('CF-Connecting-IP') || forwarded || 'unknown').slice(0, 80);
}

function getClientRequestId(c: any, body?: any): string | null {
  const raw = c.req.header('Idempotency-Key')
    || c.req.header('X-Idempotency-Key')
    || body?.client_request_id
    || body?.idempotency_key
    || body?.request_id;
  const clean = String(raw || '').trim().replace(/[^a-zA-Z0-9_.:-]/g, '').slice(0, 120);
  return clean || null;
}

function optionalBoolean(value: unknown): boolean | null {
  if (value === true || value === 1 || value === '1' || value === 'true') return true;
  if (value === false || value === 0 || value === '0' || value === 'false') return false;
  return null;
}

function rejectLargeRequest(c: any, maxBytes: number) {
  const length = Number(c.req.header('content-length') || 0);
  if (Number.isFinite(length) && length > maxBytes) {
    return c.json({ detail: 'Request is too large.', max_bytes: maxBytes }, 413);
  }
  return null;
}

function d1Changes(result: any): number {
  return Number(result?.meta?.changes ?? result?.meta?.changed_db ?? 0) || 0;
}

async function enforceRateLimit(c: any, bucket: string, identity: string, limit: number, windowSeconds: number) {
  await ensureReliabilitySchema(c.env.DB);
  const nowSeconds = Math.floor(Date.now() / 1000);
  const windowStart = Math.floor(nowSeconds / windowSeconds) * windowSeconds;
  const key = `${safeRateLimitPart(bucket)}:${safeRateLimitPart(identity)}:${windowStart}`;
  const updatedAt = now();
  const results = await c.env.DB.batch([
    c.env.DB.prepare('INSERT INTO request_rate_limits (key, window_start, count, updated_at) VALUES (?, ?, 0, ?) ON CONFLICT(key) DO NOTHING')
      .bind(key, windowStart, updatedAt),
    c.env.DB.prepare('UPDATE request_rate_limits SET count = count + 1, updated_at = ? WHERE key = ?')
      .bind(updatedAt, key),
    c.env.DB.prepare('SELECT count FROM request_rate_limits WHERE key = ?')
      .bind(key),
  ]);
  const count = Number((results?.[2] as any)?.results?.[0]?.count || 0);
  if (count > limit) {
    console.warn(JSON.stringify({ event: 'rate_limit_hit', request_id: c.get?.('requestId') || '', bucket: safeRateLimitPart(bucket), identity: safeRateLimitPart(identity), count, limit }));
    return c.json({ detail: 'Too many requests. Try again in a moment.', retry_after_seconds: windowSeconds }, 429);
  }
  return null;
}

async function usersAreBlocked(db: D1Database, firstUserId: string, secondUserId: string): Promise<boolean> {
  if (!firstUserId || !secondUserId || firstUserId === secondUserId) return false;
  await ensureAbuseProtectionSchema(db);
  const block: any = await db.prepare(
    'SELECT id FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1'
  ).bind(firstUserId, secondUserId, secondUserId, firstUserId).first();
  return !!block;
}

async function validateDirectMessagePeer(c: any, currentUserId: string, peerId: string) {
  if (!peerId || peerId === currentUserId) {
    return c.json({ detail: 'Choose a valid recipient.' }, 400);
  }
  const peer = await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(peerId).first();
  if (!peer) return c.json({ detail: 'Recipient not found.' }, 404);
  if (await usersAreBlocked(c.env.DB, currentUserId, peerId)) {
    await logSecurityEvent(c, 'blocked_message_access_denied', currentUserId, { peer_id: peerId });
    return c.json({ detail: 'You cannot message this profile.' }, 403);
  }
  return null;
}

const REPORT_REASONS = new Set([
  'spam',
  'spam_or_scam',
  'scam',
  'impersonation',
  'harassment',
  'harassment_or_bullying',
  'bullying',
  'hate',
  'hate_speech',
  'violence',
  'threats_or_violence',
  'illegal_activity',
  'illegal_or_dangerous_activity',
  'sexual_content',
  'sexual_exploitation',
  'sexual_content_or_exploitation',
  'minor_safety',
  'self_harm_concern',
  'false_or_misleading_content',
  'dont_want_to_see',
  'unwanted_explicit_content',
  'dangerous_product',
  'misleading_product',
  'suspicious_link',
  'copyright_issue',
  'stolen_content_or_copyright',
  'stolen_photo',
  'stolen_video',
  'unauthorized_repost',
  'reposted_without_permission',
  'fake_creator',
  'fake_business_identity',
  'private_personal_information',
  'doxxing_or_private_information',
  'phone_number_exposed',
  'address_exposed',
  'email_exposed',
  'private_screenshot',
  'license_plate',
  'school_information',
  'workplace_information',
  'threats',
  'harassment_private_info',
  'doxxing',
  'privacy_concern',
  'fake_product',
  'scam_product',
  'misleading_price',
  'dangerous_link',
  'impersonated_brand',
  'mention_harassment',
  'other',
]);

const REPORT_TARGET_TYPES = new Set([
  'post',
  'comment',
  'profile',
  'user',
  'message',
  'discover_post',
  'handshake_request',
  'story',
  'note',
  'music',
  'sound',
  'recommendation',
  'people_profile',
  'other',
]);

const URGENT_PRIORITY_REPORT_REASONS = new Set([
  'private_personal_information',
  'doxxing_or_private_information',
  'phone_number_exposed',
  'address_exposed',
  'email_exposed',
  'private_screenshot',
  'license_plate',
  'school_information',
  'workplace_information',
  'threats',
  'threats_or_violence',
  'harassment_private_info',
  'doxxing',
  'privacy_concern',
  'sexual_exploitation',
  'sexual_content_or_exploitation',
  'minor_safety',
  'self_harm_concern',
  'illegal_activity',
  'illegal_or_dangerous_activity',
]);

const HIGH_PRIORITY_REPORT_REASONS = new Set([
  'harassment',
  'harassment_or_bullying',
  'bullying',
  'hate',
  'hate_speech',
  'violence',
  'unwanted_explicit_content',
]);

const COPYRIGHT_REPORT_REASONS = new Set([
  'copyright_issue',
  'stolen_photo',
  'stolen_video',
  'unauthorized_repost',
  'reposted_without_permission',
]);

const REPORT_STATUSES = new Set([
  'pending',
  'open',
  'under_review',
  'in_review',
  'dismissed',
  'action_taken',
  'escalated',
  'duplicate',
  'closed',
]);

function normalizeReportReason(value: unknown): string {
  const reason = cleanText(value || 'other', 80).toLowerCase().replace(/[\s-]+/g, '_');
  const aliases: Record<string, string> = {
    harassment_bullying: 'harassment_or_bullying',
    harassment_or_bullying: 'harassment_or_bullying',
    hate: 'hate_speech',
    hate_speech: 'hate_speech',
    threats: 'threats_or_violence',
    threats_violence: 'threats_or_violence',
    threats_or_violence: 'threats_or_violence',
    doxxing_private_info: 'doxxing_or_private_information',
    doxxing_private_information: 'doxxing_or_private_information',
    doxxing_or_private_information: 'doxxing_or_private_information',
    private_info: 'doxxing_or_private_information',
    spam_scam: 'spam_or_scam',
    spam_or_scam: 'spam_or_scam',
    stolen_content: 'stolen_content_or_copyright',
    stolen_content_or_copyright: 'stolen_content_or_copyright',
    copyright: 'stolen_content_or_copyright',
    sexual_content_exploitation: 'sexual_content_or_exploitation',
    sexual_content_or_exploitation: 'sexual_content_or_exploitation',
    illegal_dangerous_activity: 'illegal_or_dangerous_activity',
    illegal_or_dangerous_activity: 'illegal_or_dangerous_activity',
    self_harm: 'self_harm_concern',
    misleading_content: 'false_or_misleading_content',
    false_or_misleading: 'false_or_misleading_content',
    misleading: 'false_or_misleading_content',
    not_interested: 'dont_want_to_see',
    i_dont_want_to_see_this: 'dont_want_to_see',
  };
  const normalized = aliases[reason] || reason;
  if (REPORT_REASONS.has(normalized)) return normalized;
  return REPORT_REASONS.has(reason) ? reason : 'other';
}

function normalizeReportStatus(value: unknown, fallback = 'pending'): string {
  const status = cleanText(value || fallback, 40).toLowerCase().replace(/[\s-]+/g, '_');
  if (status === 'open') return 'open';
  if (status === 'in_review') return 'under_review';
  if (status === 'resolved' || status === 'removed') return 'action_taken';
  if (status === 'reviewing') return 'under_review';
  return REPORT_STATUSES.has(status) ? status : fallback;
}

function priorityForReportReason(reason: string): 'urgent' | 'high' | 'medium' | 'normal' {
  if (URGENT_PRIORITY_REPORT_REASONS.has(reason)) return 'urgent';
  if (HIGH_PRIORITY_REPORT_REASONS.has(reason)) return 'high';
  if (COPYRIGHT_REPORT_REASONS.has(reason) || reason === 'stolen_content_or_copyright' || reason === 'impersonation' || reason === 'suspicious_link' || reason === 'spam_or_scam') return 'medium';
  return 'normal';
}

function normalizeReportTargetType(value: unknown): string {
  const type = cleanText(value || 'other', 60).toLowerCase().replace(/[\s-]+/g, '_');
  if (type === 'people') return 'people_profile';
  if (type === 'user_profile') return 'profile';
  if (type === 'discover' || type === 'discover_item') return 'discover_post';
  if (type === 'status') return 'story';
  if (type === 'handshake') return 'handshake_request';
  return REPORT_TARGET_TYPES.has(type) ? type : 'other';
}

function scrubLogMetadata(value: Record<string, unknown>): Record<string, unknown> {
  const safe: Record<string, unknown> = {};
  for (const [key, raw] of Object.entries(value || {})) {
    const normalizedKey = key.toLowerCase();
    if (/(password|token|secret|authorization|cookie|card|key)/.test(normalizedKey)) continue;
    if (typeof raw === 'number' || typeof raw === 'boolean') {
      safe[key] = raw;
    } else if (raw != null) {
      safe[key] = cleanText(raw, 180);
    }
  }
  return safe;
}

function sanitizeClientEventMetadata(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  const safe: Record<string, unknown> = {};
  for (const [key, raw] of Object.entries(value as Record<string, unknown>).slice(0, 12)) {
    const normalizedKey = key.toLowerCase();
    if (/(password|token|secret|authorization|cookie|card|email|phone|message|content|caption|body)/.test(normalizedKey)) continue;
    const cleanKey = cleanText(key, 40).replace(/[^a-zA-Z0-9_.:-]/g, '_');
    if (!cleanKey) continue;
    if (typeof raw === 'number') {
      safe[cleanKey] = clampNumber(raw, -1_000_000, 1_000_000, 0);
    } else if (typeof raw === 'boolean') {
      safe[cleanKey] = raw;
    } else if (raw != null) {
      safe[cleanKey] = cleanText(raw, 120);
    }
  }
  return safe;
}

async function logSecurityEvent(c: any, eventType: string, userId = '', metadata: Record<string, unknown> = {}) {
  try {
    await ensureAbuseProtectionSchema(c.env.DB);
    await c.env.DB.prepare(
      'INSERT INTO security_events (id, event_type, user_id, ip, metadata, created_at) VALUES (?, ?, ?, ?, ?, ?)'
    ).bind(uuid(), cleanText(eventType, 80), cleanText(userId, 120), clientIp(c), JSON.stringify(scrubLogMetadata(metadata)), now()).run();
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'security_event_log_failed', type: cleanText(eventType, 80), code: getErrorCode(error) }));
  }
}

function abuseSignalSalt(c: any): string {
  return String(c.env.ABUSE_SIGNAL_SECRET || c.env.JWT_SECRET || 'flames-up-abuse-signal-v1').trim();
}

function normalizeIpPattern(value: string): string {
  const ip = String(value || '').trim();
  if (!ip) return '';
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) {
    return ip.split('.').slice(0, 3).join('.') + '.0/24';
  }
  if (ip.includes(':')) {
    return ip.split(':').slice(0, 4).join(':').toLowerCase();
  }
  return ip.slice(0, 64);
}

function normalizedSignalText(value: unknown, max = 240): string {
  return cleanMultilineText(value, max).toLowerCase().replace(/\s+/g, ' ').trim();
}

function normalizedSignalLink(value: unknown): string {
  const url = safeExternalUrl(value);
  if (!url) return '';
  try {
    const parsed = new URL(url);
    return `${parsed.hostname.toLowerCase()}${parsed.pathname.replace(/\/+$/, '').toLowerCase()}`.slice(0, 240);
  } catch {
    return '';
  }
}

async function hashAbuseSignal(c: any, type: string, value: string): Promise<string> {
  return sha256Hex(`${abuseSignalSalt(c)}:${type}:${value}`);
}

async function buildAbuseSignals(c: any, fields: Record<string, unknown> = {}) {
  const rawSignals: Array<{ type: string; value: string }> = [];
  const ip = normalizeIpPattern(clientIp(c));
  const userAgent = normalizedSignalText(c.req.header('User-Agent') || '', 220);
  const installId = normalizedSignalText(c.req.header('X-Client-Install-Id') || '', 160);
  if (ip) rawSignals.push({ type: 'ip_pattern', value: ip });
  if (userAgent) rawSignals.push({ type: 'user_agent', value: userAgent });
  if (installId) rawSignals.push({ type: 'client_install', value: installId });

  const addText = (type: string, value: unknown, max = 240) => {
    const normalized = normalizedSignalText(value, max);
    if (normalized && normalized.length >= 3) rawSignals.push({ type, value: normalized });
  };
  addText('username', fields.username, 80);
  addText('display_name', fields.display_name || fields.full_name, 120);
  addText('bio', fields.bio, 300);

  for (const raw of parseJsonArray(fields.links)) {
    const link = normalizedSignalLink(raw);
    if (link) rawSignals.push({ type: 'external_link', value: link });
  }
  for (const raw of parseJsonArray(fields.product_links)) {
    const link = normalizedSignalLink(raw);
    if (link) rawSignals.push({ type: 'product_link', value: link });
  }

  const deduped = new Map<string, { type: string; value: string }>();
  for (const signal of rawSignals) deduped.set(`${signal.type}:${signal.value}`, signal);

  const hashed: Array<{ type: string; hash: string }> = [];
  for (const signal of deduped.values()) {
    hashed.push({ type: signal.type, hash: await hashAbuseSignal(c, signal.type, signal.value) });
  }
  return hashed;
}

async function recordAbuseSignals(c: any, userId: string, source: string, fields: Record<string, unknown> = {}) {
  if (!userId) return;
  try {
    await ensureAbuseProtectionSchema(c.env.DB);
    const signals = await buildAbuseSignals(c, fields);
    const ts = now();
    for (const signal of signals) {
      await c.env.DB.prepare(
        `INSERT OR IGNORE INTO abuse_signals (id, user_id, signal_type, signal_hash, source, first_seen_at, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      ).bind(uuid(), userId, signal.type, signal.hash, cleanText(source, 80), ts, ts).run();
      await c.env.DB.prepare(
        'UPDATE abuse_signals SET last_seen_at = ?, source = ? WHERE user_id = ? AND signal_type = ? AND signal_hash = ?'
      ).bind(ts, cleanText(source, 80), userId, signal.type, signal.hash).run();

      const matches = await c.env.DB.prepare(
        `SELECT DISTINCT s.user_id
         FROM abuse_signals s
         JOIN users u ON u.id = s.user_id
         WHERE s.signal_type = ? AND s.signal_hash = ? AND s.user_id != ? AND COALESCE(u.status, 'active') = 'banned'
         LIMIT 5`
      ).bind(signal.type, signal.hash, userId).all();

      for (const match of (matches.results || []) as any[]) {
        await c.env.DB.prepare(
          `INSERT OR IGNORE INTO ban_evasion_flags
           (id, user_id, matched_user_id, signal_type, source, reason, status, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)`
        ).bind(
          uuid(),
          userId,
          cleanText(match.user_id, 120),
          signal.type,
          cleanText(source, 80),
          `Matched a banned account by ${signal.type}. Review before taking action.`,
          ts,
          ts
        ).run();
      }
    }
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'abuse_signal_failed', code: getErrorCode(error), user_id: cleanText(userId, 120) }));
  }
}

function safeNotificationData(value: Record<string, unknown>): Record<string, unknown> {
  return scrubLogMetadata(value);
}

function safeNotificationPayload(row: any) {
  return {
    id: cleanText(row.id, 120),
    user_id: cleanText(row.user_id, 120),
    type: cleanText(row.type || 'general', 60),
    title: cleanText(row.title, 120),
    body: cleanText(row.body, 300),
    data: safeNotificationData(parseJsonObject(row.data)),
    is_read: !!row.is_read,
    created_at: row.created_at,
  };
}

async function insertNotificationOnce(c: any, input: {
  userId: string;
  type: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  dedupeKey?: string;
  dedupeSeconds?: number;
}) {
  await ensureAbuseProtectionSchema(c.env.DB);
  const type = cleanText(input.type || 'general', 60);
  const dedupeKey = cleanText(input.dedupeKey || '', 160);
  const data = safeNotificationData({ ...(input.data || {}), ...(dedupeKey ? { dedupe_key: dedupeKey } : {}) });
  const language = await preferredNotificationLanguage(c, input.userId);
  const copy = localizedNotificationCopy(language, type, input.title, input.body, data);

  if (dedupeKey) {
    try {
      const existing = await c.env.DB.prepare(
        "SELECT id FROM notifications WHERE user_id = ? AND type = ? AND json_extract(data, '$.dedupe_key') = ? AND created_at > datetime('now', ?) LIMIT 1"
      ).bind(input.userId, type, dedupeKey, `-${Math.max(60, input.dedupeSeconds || 86400)} seconds`).first();
      if (existing) return false;
    } catch {
      // Older local D1 builds may not expose JSON functions; insert remains safe because engagement rows are idempotent.
    }
  }

  await c.env.DB.prepare(
    'INSERT INTO notifications (id, user_id, type, title, body, data, is_read, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, datetime(\'now\'))'
  ).bind(uuid(), input.userId, type, cleanText(copy.title, 120), cleanText(copy.body, 300), JSON.stringify(data)).run();
  runBackgroundTask(c, 'alert_push_failed', async () => {
    const status = await sendAlertPushForNotification(c, {
      userId: input.userId,
      type,
      title: copy.title,
      body: copy.body,
      data,
    });
    if (status.startsWith('apns_failed')) {
      await logSecurityEvent(c, 'alert_push_failed', input.userId, { type, status });
    }
  });
  return true;
}

async function preferredNotificationLanguage(c: any, userId: string): Promise<'en' | 'fr' | 'es'> {
  try {
    const row: any = await c.env.DB.prepare('SELECT language FROM users WHERE id = ? LIMIT 1').bind(userId).first();
    const language = cleanText(row?.language || '', 8).toLowerCase().split('-')[0];
    return language === 'fr' || language === 'es' ? language : 'en';
  } catch {
    return 'en';
  }
}

function localizedNotificationCopy(language: 'en' | 'fr' | 'es', type: string, title: string, body: string, data: Record<string, unknown>): { title: string; body: string } {
  const actorName = cleanText((data.actor_name || data.from_user_name || data.from_username || '') as string, 80) || (language === 'fr' ? 'Quelqu’un' : language === 'es' ? 'Alguien' : 'Someone');
  if (type === 'like') {
    if (language === 'fr') return { title: 'Nouveau J’aime', body: `${actorName} a aimé votre publication.` };
    if (language === 'es') return { title: 'Nuevo me gusta', body: `A ${actorName} le gustó tu publicación.` };
    return { title: 'New Like', body: `${actorName} liked your post.` };
  }
  if (type === 'comment' || type === 'comment_reply') {
    const isReply = type === 'comment_reply';
    if (language === 'fr') return { title: isReply ? 'Nouvelle réponse' : 'Nouveau commentaire', body: `${actorName} ${isReply ? 'a répondu à votre commentaire' : 'a commenté votre publication'}.` };
    if (language === 'es') return { title: isReply ? 'Nueva respuesta' : 'Nuevo comentario', body: `${actorName} ${isReply ? 'respondió a tu comentario' : 'comentó tu publicación'}.` };
    return { title: isReply ? 'New Reply' : 'New Comment', body: `${actorName} ${isReply ? 'replied to your comment' : 'commented on your post'}.` };
  }
  if (type === 'message') {
    if (language === 'fr') return { title: 'Nouveau message', body: `Nouveau message de ${actorName}` };
    if (language === 'es') return { title: 'Nuevo mensaje', body: `Nuevo mensaje de ${actorName}` };
    return { title: 'New message', body: `New message from ${actorName}` };
  }
  return { title, body };
}

async function resolveReportTarget(c: any, reporterId: string, type: string, reportedId: string, body: any): Promise<{ ok: boolean; status?: number; detail?: string; contentId?: string; targetOwnerUserId?: string }> {
  try {
    if (!reportedId) return { ok: false, status: 400, detail: 'Choose something to report.' };
    if (type === 'post') {
      const reportPostSql = [
        'SELECT p.id, p.user_id FROM posts p JOIN users u ON p.user_id = u.id',
        `WHERE p.id = ? AND ${visiblePostWhere('u', 'p')} LIMIT 1`,
      ].join(' ');
      const row: any = await c.env.DB.prepare(reportPostSql).bind(reportedId, ...visiblePostBindValues(reporterId)).first();
      if (!row) return { ok: false, status: 404, detail: 'Reported post was not found.' };
      if (row.user_id === reporterId) return { ok: false, status: 400, detail: 'You cannot report your own content.' };
      return { ok: true, contentId: row.id, targetOwnerUserId: row.user_id };
    }
    if (type === 'comment') {
      const reportCommentSql = [
        'SELECT cm.id, cm.user_id, cm.post_id',
        'FROM comments cm',
        'JOIN posts p ON p.id = cm.post_id',
        'JOIN users u ON u.id = p.user_id',
        `WHERE cm.id = ? AND ${visiblePostWhere('u', 'p')} LIMIT 1`,
      ].join(' ');
      const row: any = await c.env.DB.prepare(reportCommentSql).bind(reportedId, ...visiblePostBindValues(reporterId)).first();
      if (!row) return { ok: false, status: 404, detail: 'Reported comment was not found.' };
      if (row.user_id === reporterId) return { ok: false, status: 400, detail: 'You cannot report your own comment.' };
      return { ok: true, contentId: row.post_id, targetOwnerUserId: row.user_id };
    }
    if (type === 'profile' || type === 'user') {
      const row: any = await c.env.DB.prepare('SELECT id FROM users WHERE id = ? LIMIT 1').bind(reportedId).first();
      if (!row) return { ok: false, status: 404, detail: 'Reported profile was not found.' };
      if (row.id === reporterId) return { ok: false, status: 400, detail: 'You cannot report your own profile.' };
      return { ok: true, contentId: row.id, targetOwnerUserId: row.id };
    }
    if (type === 'message') {
      const row: any = await c.env.DB.prepare('SELECT id, sender_id, receiver_id FROM messages WHERE id = ? AND (sender_id = ? OR receiver_id = ?) LIMIT 1')
        .bind(reportedId, reporterId, reporterId)
        .first();
      if (!row) return { ok: false, status: 404, detail: 'Reported message was not found.' };
      const targetOwnerUserId = row.sender_id === reporterId ? row.receiver_id : row.sender_id;
      if (!targetOwnerUserId || targetOwnerUserId === reporterId) return { ok: false, status: 400, detail: 'You cannot report your own message.' };
      return { ok: true, contentId: row.id, targetOwnerUserId };
    }
    if (type === 'discover_post') {
      const row: any = await c.env.DB.prepare('SELECT id, user_id FROM discover_posts WHERE id = ? LIMIT 1').bind(reportedId).first();
      if (!row) return { ok: false, status: 404, detail: 'Reported Discover post was not found.' };
      if (row.user_id === reporterId) return { ok: false, status: 400, detail: 'You cannot report your own Discover post.' };
      return { ok: true, contentId: row.id, targetOwnerUserId: row.user_id };
    }
    if (type === 'story') {
      const storySql = [
        'SELECT s.id, s.user_id FROM statuses s JOIN users u ON s.user_id = u.id',
        `WHERE s.id = ? AND s.created_at >= datetime('now', '-7 days') AND ${visibleStatusWhere('u', 's')} LIMIT 1`,
      ].join(' ');
      const row: any = await c.env.DB.prepare(storySql).bind(reportedId, reporterId, reporterId).first();
      if (!row) return { ok: false, status: 404, detail: 'Reported story was not found.' };
      if (row.user_id === reporterId) return { ok: false, status: 400, detail: 'You cannot report your own story.' };
      return { ok: true, contentId: row.id, targetOwnerUserId: row.user_id };
    }
    if (type === 'note') {
      await ensureNotesSchema(c.env.DB);
      const row: any = await c.env.DB.prepare("SELECT id, user_id FROM notes WHERE id = ? AND COALESCE(status, 'active') = 'active' LIMIT 1").bind(reportedId).first();
      if (!row) return { ok: false, status: 404, detail: 'Reported note was not found.' };
      if (row.user_id === reporterId) return { ok: false, status: 400, detail: 'You cannot report your own note.' };
      return { ok: true, contentId: row.id, targetOwnerUserId: row.user_id };
    }
    if (type === 'music') {
      await ensureAiMusicSchema(c.env.DB);
      const row: any = await c.env.DB.prepare("SELECT id, user_id FROM ai_music_posts WHERE id = ? AND COALESCE(status, 'active') != 'removed' LIMIT 1").bind(reportedId).first();
      if (!row) return { ok: false, status: 404, detail: 'Reported music post was not found.' };
      if (row.user_id === reporterId) return { ok: false, status: 400, detail: 'You cannot report your own music post.' };
      return { ok: true, contentId: row.id, targetOwnerUserId: row.user_id };
    }
    if (type === 'recommendation') {
      await ensureRecommendationSchema(c.env.DB);
      const row: any = await c.env.DB.prepare("SELECT id, user_id FROM recommendations WHERE id = ? AND COALESCE(status, 'active') = 'active' LIMIT 1").bind(reportedId).first();
      if (!row) return { ok: false, status: 404, detail: 'Reported recommendation was not found.' };
      if (row.user_id === reporterId) return { ok: false, status: 400, detail: 'You cannot report your own recommendation.' };
      return { ok: true, contentId: row.id, targetOwnerUserId: row.user_id };
    }
    if (type === 'people_profile') {
      await ensurePeopleSchema(c.env.DB);
      const row: any = await c.env.DB.prepare("SELECT id FROM people_profiles WHERE id = ? AND COALESCE(status, 'active') = 'active' LIMIT 1").bind(reportedId).first();
      if (!row) return { ok: false, status: 404, detail: 'Reported profile was not found.' };
      return { ok: true, contentId: row.id };
    }
    return { ok: true, contentId: publicId(body.content_id || reportedId, 120) };
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'report_target_check_failed', type, code: getErrorCode(error) }));
    return { ok: false, status: 404, detail: 'Reported content was not found.' };
  }
}

async function blockUserForReporter(c: any, blockerId: string, blockedId: string): Promise<boolean> {
  const cleanBlockedId = publicId(blockedId, 120);
  if (!cleanBlockedId || cleanBlockedId === blockerId) return false;
  await ensureAbuseProtectionSchema(c.env.DB);
  const target: any = await c.env.DB.prepare('SELECT id FROM users WHERE id = ? LIMIT 1').bind(cleanBlockedId).first();
  if (!target) return false;
  await c.env.DB.batch([
    c.env.DB.prepare("INSERT OR IGNORE INTO blocks (id, blocker_id, blocked_id, created_at) VALUES (?, ?, ?, datetime('now'))").bind(uuid(), blockerId, cleanBlockedId),
    c.env.DB.prepare('DELETE FROM follows WHERE (follower_id = ? AND following_id = ?) OR (follower_id = ? AND following_id = ?)').bind(blockerId, cleanBlockedId, cleanBlockedId, blockerId),
  ]);
  await logSecurityEvent(c, 'user_blocked', blockerId, { blocked_id: cleanBlockedId, source: 'report_flow' });
  return true;
}

async function submitReportRequest(c: any) {
  await ensureAdminModerationSchema(c.env.DB);
  const bodyTooLarge = rejectLargeRequest(c, 50_000);
  if (bodyTooLarge) return bodyTooLarge;
  const reporterId = getUserId(c);
  const shortLimit = await enforceRateLimit(c, 'report_submit', reporterId, 8, 60);
  if (shortLimit) return shortLimit;
  const dailyLimit = await enforceRateLimit(c, 'report_submit_daily', reporterId, 60, 86400);
  if (dailyLimit) return dailyLimit;

  const body: any = await c.req.json().catch(() => ({}));
  const reportedType = normalizeReportTargetType(body.reported_type || body.report_type || body.target_type || 'other');
  const reportedId = publicId(body.reported_id || body.target_id || body.post_id || body.user_id || body.comment_id || body.message_id || '', 140);
  const reason = normalizeReportReason(body.reason || body.report_reason);
  const priority = priorityForReportReason(reason);
  const details = cleanMultilineText(body.details || body.description || body.notes || '', 500);
  const wantsBlock = optionalBoolean(body.block_user ?? body.blockUser ?? body.block) === true;
  const wantsHideContent = optionalBoolean(body.hide_content ?? body.hideContent ?? body.hide) !== false;
  const target = await resolveReportTarget(c, reporterId, reportedType, reportedId, body);
  if (!target.ok) return c.json({ error_code: 'target_not_found', detail: target.detail || 'Reported content was not found.' }, target.status || 400);

  const existing: any = await c.env.DB.prepare(
    "SELECT id FROM reports WHERE reporter_id = ? AND reported_type = ? AND reported_id = ? AND COALESCE(status, 'open') IN ('open', 'pending', 'under_review', 'reviewing', 'escalated') LIMIT 1"
  ).bind(reporterId, reportedType, reportedId).first();
  if (existing) {
    await logSecurityEvent(c, 'duplicate_report_blocked', reporterId, { reported_type: reportedType, reason });
    const blocked = wantsBlock && target.targetOwnerUserId ? await blockUserForReporter(c, reporterId, target.targetOwnerUserId) : false;
    return c.json({ id: existing.id, reported: true, duplicate: true, blocked, hidden: wantsHideContent, error_code: 'report_duplicate' });
  }

  const id = uuid();
  const ts = now();
  await c.env.DB.prepare(
    `INSERT INTO reports (
      id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, priority, target_owner_user_id, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?, ?)`
  ).bind(id, reporterId, reportedId, reportedType, reportedType, reason, details, target.contentId || '', priority, target.targetOwnerUserId || '', ts, ts).run();
  const blocked = wantsBlock && target.targetOwnerUserId ? await blockUserForReporter(c, reporterId, target.targetOwnerUserId) : false;
  await logSecurityEvent(c, priority === 'urgent' ? 'urgent_report_submitted' : priority === 'high' ? 'high_priority_report_submitted' : 'report_submitted', reporterId, { reported_type: reportedType, reason, priority, target_owner: target.targetOwnerUserId || '' });
  await recordAbuseSignals(c, reporterId, 'report_submit', {});
  return c.json({ id, reported: true, blocked, hidden: wantsHideContent });
}

function clampFloat(value: unknown, min: number, max: number, fallback: number): number {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return fallback;
  return Math.max(min, Math.min(max, numeric));
}

const EDITOR_TEXT_TYPES = new Set(['title', 'subtitle', 'label', 'price', 'rating', 'note']);

function sanitizePostEditorOverlays(value: unknown): any[] {
  const raw = parseJsonArray(value);
  const overlays: any[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    if (item.type === 'filter') {
      const filterName = cleanText(item.filterName || item.name, 60);
      if (!filterName) continue;
      overlays.push({
        type: 'filter',
        id: 'filter',
        filterId: cleanText(item.filterId || filterName, 80),
        filterName,
        intensity: clampNumber(item.intensity, 0, 100, 100),
        tint: cleanText(item.tint || '#FFFFFF', 32),
        tintOpacity: clampFloat(item.tintOpacity, 0, 0.6, 0.08),
        fadeOpacity: clampFloat(item.fadeOpacity, 0, 0.4, 0),
        vignetteOpacity: clampFloat(item.vignetteOpacity, 0, 0.6, 0),
        grainOpacity: clampFloat(item.grainOpacity, 0, 0.4, 0),
        adjustments: item.adjustments && typeof item.adjustments === 'object' ? item.adjustments : {},
        mediaIndex: clampNumber(item.mediaIndex ?? item.media_index, 0, 12, 0),
      });
      continue;
    }
    if (item.type === 'text') {
      const text = cleanText(item.text, 140);
      if (!text) continue;
      overlays.push({
        type: 'text',
        id: cleanText(item.id, 80) || uuid(),
        textType: EDITOR_TEXT_TYPES.has(item.textType) ? item.textType : 'title',
        text,
        x: clampFloat(item.x, 0.04, 0.96, 0.5),
        y: clampFloat(item.y, 0.04, 0.96, 0.18),
        width: clampFloat(item.width, 0.22, 0.9, 0.72),
        fontSize: clampNumber(item.fontSize, 12, 42, 24),
        fontFamily: cleanText(item.fontFamily || 'Inter', 40),
        fontWeight: ['600', '700', '800', '900'].includes(String(item.fontWeight)) ? String(item.fontWeight) : '900',
        color: cleanText(item.color || '#FFFFFF', 32),
        background: cleanText(item.background ?? 'transparent', 48),
        borderColor: cleanText(item.borderColor || '', 48),
        opacity: clampFloat(item.opacity, 0.2, 1, 1),
        shadow: !!item.shadow,
        radius: clampNumber(item.radius, 0, 26, 0),
        paddingX: clampNumber(item.paddingX, 0, 18, 0),
        paddingY: clampNumber(item.paddingY, 0, 14, 0),
        presetId: cleanText(item.presetId || '', 80),
        mediaIndex: clampNumber(item.mediaIndex ?? item.media_index, 0, 12, 0),
      });
      continue;
    }
  }
  return overlays.slice(0, 40);
}

function sanitizeTaggedUsers(value: unknown): any[] {
  const raw = Array.isArray(value)
    ? value
    : typeof value === 'string' && value.trim()
      ? parseJsonArray(value)
      : [];
  const seen = new Set<string>();
  return raw
    .map((item: any) => {
      const id = publicId(item?.id, 80);
      if (!id || seen.has(id)) return null;
      seen.add(id);
      return {
        id,
        username: cleanText(item?.username, 60),
        full_name: cleanText(item?.full_name || item?.fullName, 100),
        profile_image: cleanText(item?.profile_image || item?.profileImage, 1000),
      };
    })
    .filter(Boolean)
    .slice(0, 10);
}

function sanitizeMediaDimensions(value: unknown): any[] {
  return parseJsonArray(value)
    .map((item: any) => {
      const width = clampNumber(item?.width, 0, 12000, 0);
      const height = clampNumber(item?.height, 0, 12000, 0);
      const ratio = clampFloat(item?.ratio || (width > 0 && height > 0 ? width / height : 0), 0, 4, 0);
      const format = cleanText(item?.format, 16);
      const type = String(item?.type || '').toLowerCase().includes('video') ? 'video' : 'image';
      if (!width && !height && !ratio && !format) return null;
      return { width, height, ratio, format, type };
    })
    .filter(Boolean)
    .slice(0, 12);
}

function normalizeRecommendationCategory(value: unknown): string {
  const clean = String(value || '').trim().toLowerCase().replace(/[^a-z0-9 _-]/g, '').replace(/\s+/g, ' ');
  const allowed = new Set(['notes', 'vibe', 'music', 'people', 'artist', 'movies', 'books', 'artists', 'videos', 'podcasts', 'places', 'apps', 'other']);
  if (clean === 'note' || clean === 'thought' || clean === 'poem') return 'notes';
  if (clean === 'vibes' || clean === 'mood') return 'vibe';
  if (clean === 'new' || clean === 'article' || clean === 'articles') return 'other';
  if (clean === 'movie' || clean === 'film') return 'movies';
  if (clean === 'book' || clean === 'novel') return 'books';
  if (clean === 'artist' || clean === 'art' || clean === 'artists' || clean === 'person' || clean === 'people') return 'people';
  if (clean === 'video' || clean === 'youtube') return 'videos';
  if (clean === 'podcast') return 'podcasts';
  return allowed.has(clean) ? clean : 'other';
}

function normalizeRecommendationTags(value: unknown, fallback: string[] = []): string[] {
  const raw = Array.isArray(value)
    ? value
    : typeof value === 'string'
      ? value.startsWith('[')
        ? parseJsonArray(value)
        : value.split(',')
      : fallback;
  const seen = new Set<string>();
  return raw
    .map((item) => String(item || '').trim().toLowerCase().replace(/[^a-z0-9 _-]/g, '').replace(/\s+/g, ' '))
    .filter(Boolean)
    .filter((item) => {
      if (seen.has(item)) return false;
      seen.add(item);
      return true;
    })
    .slice(0, 3);
}

function safeExternalUrl(value: unknown): string {
  const raw = String(value || '').trim();
  if (!raw) return '';
  if (/[\u0000-\u001F\u007F<>"'`\\]/.test(raw)) return '';
  try {
    const url = new URL(raw.startsWith('http://') || raw.startsWith('https://') ? raw : `https://${raw}`);
    if (!['http:', 'https:'].includes(url.protocol)) return '';
    if (url.username || url.password) return '';
    if (!url.hostname || !/[a-z0-9]/i.test(url.hostname)) return '';
    return url.toString();
  } catch {
    return '';
  }
}

function safeMediaReference(value: unknown): string {
  const raw = String(value || '').trim();
  if (!raw || raw.length > 2500) return '';
  if (/^cfstream:[a-zA-Z0-9_-]{6,128}$/.test(raw)) return raw;
  if (/^\/api\/media\/[a-zA-Z0-9_-]{8,160}$/.test(raw)) return raw;
  const external = safeExternalUrl(raw);
  if (!external) return '';
  try {
    const url = new URL(external);
    return url.protocol === 'https:' ? url.toString() : '';
  } catch {
    return '';
  }
}

function sanitizeMediaReferences(value: unknown, fallback?: unknown): string[] {
  const raw = parseJsonArray(value);
  const candidates = raw.length ? raw : fallback ? [fallback] : [];
  const seen = new Set<string>();
  return candidates
    .map(safeMediaReference)
    .filter(Boolean)
    .filter((url) => {
      if (seen.has(url)) return false;
      seen.add(url);
      return true;
    })
    .slice(0, 12);
}

function sanitizeMediaTypes(value: unknown, count: number): string[] {
  const raw = parseJsonArray(value);
  const types = raw.map((item) => String(item || '').toLowerCase().includes('video') ? 'video' : 'image');
  while (types.length < count) types.push('image');
  return types.slice(0, Math.max(0, Math.min(count, 12)));
}

function hostMatches(host: string, domain: string): boolean {
  const cleanHost = String(host || '').replace(/\.+$/, '').replace(/^www\./, '').toLowerCase();
  const cleanDomain = String(domain || '').replace(/^\./, '').toLowerCase();
  return cleanHost === cleanDomain || cleanHost.endsWith(`.${cleanDomain}`);
}

function recommendationLinkMetadata(externalUrl: string, explicitThumbnail = '') {
  const result = {
    provider: 'link',
    external_id: '',
    embed_url: '',
    thumbnail_url: cleanText(explicitThumbnail, 1200),
  };

  try {
    const url = new URL(externalUrl);
    const host = url.hostname.replace(/^www\./, '').toLowerCase();

    if (host === 'youtu.be') {
      const id = url.pathname.split('/').filter(Boolean)[0] || '';
      if (id) {
        result.provider = 'youtube';
        result.external_id = id;
        result.embed_url = `https://www.youtube.com/embed/${encodeURIComponent(id)}`;
        result.thumbnail_url ||= `https://img.youtube.com/vi/${encodeURIComponent(id)}/hqdefault.jpg`;
      }
    } else if (hostMatches(host, 'youtube.com')) {
      const id = url.searchParams.get('v') || url.pathname.match(/\/(?:shorts|embed)\/([^/?#]+)/)?.[1] || '';
      if (id) {
        result.provider = 'youtube';
        result.external_id = id;
        result.embed_url = `https://www.youtube.com/embed/${encodeURIComponent(id)}`;
        result.thumbnail_url ||= `https://img.youtube.com/vi/${encodeURIComponent(id)}/hqdefault.jpg`;
      }
    } else if (hostMatches(host, 'vimeo.com')) {
      const id = url.pathname.match(/(\d+)/)?.[1] || '';
      if (id) {
        result.provider = 'vimeo';
        result.external_id = id;
        result.embed_url = `https://player.vimeo.com/video/${encodeURIComponent(id)}`;
      }
    } else if (host === 'open.spotify.com') {
      const parts = url.pathname.split('/').filter(Boolean);
      if (parts.length >= 2) {
        result.provider = 'spotify';
        result.external_id = `${parts[0]}:${parts[1]}`;
        result.embed_url = `https://open.spotify.com/embed/${encodeURIComponent(parts[0])}/${encodeURIComponent(parts[1])}`;
      }
    } else if (host === 'music.apple.com') {
      result.provider = 'apple_music';
      result.embed_url = externalUrl.replace('https://music.apple.com/', 'https://embed.music.apple.com/');
    } else if (hostMatches(host, 'goodreads.com')) {
      result.provider = 'book';
    } else if (hostMatches(host, 'letterboxd.com') || hostMatches(host, 'imdb.com')) {
      result.provider = 'movie';
    }
  } catch {}

  return result;
}

function publicRecommendationPayload(recommendation: any) {
  return {
    ...recommendation,
    tags: normalizeRecommendationTags(recommendation?.tags),
    reports_count: Number(recommendation?.reports_count || 0),
    user: recommendation.user_id === 'system' ? {
      id: 'system',
      username: 'flames',
      full_name: 'Flames Picks',
      profile_image: '',
    } : {
      id: recommendation.user_id,
      username: recommendation.user_username || '',
      full_name: recommendation.user_full_name || '',
      profile_image: recommendation.user_profile_image || '',
    },
  };
}

const NOTE_TYPES = new Set(['thought', 'feeling', 'advice', 'confession', 'question', 'quote', 'memory', 'mood', 'journal']);
const NOTE_MOODS: Record<string, string> = {
  soft: '#F6E7D7',
  calm: '#E7F1DF',
  blue: '#DCEAF8',
  love: '#F8DDE7',
  night: '#E7E1F5',
  gold: '#F7E7B7',
  green: '#DFF0D8',
  gray: '#ECEBE6',
};

function normalizeNoteType(value: unknown): string {
  const clean = String(value || '').trim().toLowerCase().replace(/[^a-z0-9 _-]/g, '').replace(/\s+/g, ' ');
  if (clean === 'late night thoughts') return 'thought';
  if (clean === 'anonymous feelings') return 'feeling';
  if (clean === 'daily mood') return 'mood';
  return NOTE_TYPES.has(clean) ? clean : 'thought';
}

function normalizeNoteMood(value: unknown): { mood: string; color: string } {
  const clean = String(value || '').trim().toLowerCase().replace(/[^a-z0-9 _-]/g, '').replace(/\s+/g, ' ');
  const mood = NOTE_MOODS[clean] ? clean : 'soft';
  return { mood, color: NOTE_MOODS[mood] };
}

function moderateCommunityText(value: string): { ok: boolean; detail?: string } {
  const text = String(value || '').trim();
  if (!text) return { ok: false, detail: 'Write something first.' };
  const blockedPatterns = [
    /\b(kill yourself|hurt yourself|suicide method|self harm instructions)\b/i,
    /\b(i will kill|i am going to kill|shoot up|bomb threat|stab them)\b/i,
    /\b(how to make a bomb|build a bomb|poison someone|make a weapon)\b/i,
    /\b(doxx|home address is|ssn|social security number|credit card number|private phone number)\b/i,
    /\b(child porn|minor sexual|underage sexual|sexual minor)\b/i,
    /\b(scamming|phishing|wire me money|guaranteed crypto profit)\b/i,
    /\b(nazi praise|exterminate all|racial slur)\b/i,
  ];
  if (blockedPatterns.some((pattern) => pattern.test(text))) {
    return { ok: false, detail: 'That needs moderation review before it can be posted.' };
  }
  return { ok: true };
}

function publicNotePayload(row: any, opts: { reacted?: boolean; saved?: boolean } = {}) {
  const anonymous = Number(row.anonymous || 0) === 1;
  return {
    id: row.id,
    body: row.body || '',
    note_type: row.note_type || 'thought',
    mood: row.mood || 'soft',
    color: row.color || NOTE_MOODS.soft,
    media_url: row.media_url || '',
    media_type: row.media_type || '',
    anonymous,
    status: row.status || 'active',
    reactions_count: Number(row.reactions_count || 0),
    comments_count: Number(row.comments_count || 0),
    saves_count: Number(row.saves_count || 0),
    shares_count: Number(row.shares_count || 0),
    reports_count: Number(row.reports_count || 0),
    created_at: row.created_at,
    updated_at: row.updated_at,
    reacted: !!opts.reacted || Number(row.reacted || 0) === 1,
    saved: !!opts.saved || Number(row.saved || 0) === 1,
    user: anonymous ? {
      id: '',
      username: 'anonymous',
      full_name: 'Anonymous',
      profile_image: '',
    } : {
      id: row.user_id,
      username: row.user_username || '',
      full_name: row.user_full_name || '',
      profile_image: row.user_profile_image || '',
    },
  };
}

function publicPeoplePayload(row: any, opts: { followed?: boolean; saved?: boolean } = {}) {
  return {
    id: row.id,
    owner_user_id: row.owner_user_id || '',
    name: row.name || 'Creator',
    role: row.role || row.category || 'creator',
    category: row.category || 'creator',
    bio: row.bio || '',
    known_for: row.known_for || '',
    city: row.city || '',
    profile_image: row.profile_image || '',
    instagram_url: row.instagram_url || '',
    tiktok_url: row.tiktok_url || '',
    youtube_url: row.youtube_url || '',
    website_url: row.website_url || '',
    source_url: row.source_url || '',
    claim_status: row.claim_status || 'unclaimed',
    followers_count: Number(row.followers_count || 0),
    saves_count: Number(row.saves_count || 0),
    reports_count: Number(row.reports_count || 0),
    followed: !!opts.followed || Number(row.followed || 0) === 1,
    saved: !!opts.saved || Number(row.saved || 0) === 1,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

function normalizePeopleRole(value: unknown): string {
  const clean = String(value || '').trim().toLowerCase().replace(/[^a-z0-9 _-]/g, '').replace(/\s+/g, ' ');
  const allowed = new Set(['creator', 'actor', 'musician', 'model', 'influencer', 'athlete', 'photographer', 'business owner', 'public figure', 'local creator']);
  return allowed.has(clean) ? clean : 'creator';
}

function safeOptionalUrl(value: unknown): string {
  const raw = String(value || '').trim();
  if (!raw) return '';
  return safeExternalUrl(raw);
}

function parseInterestValues(value: unknown): string[] {
  const raw = parsePreferenceList(value);
  const seen = new Set<string>();
  return raw
    .map((item) => String(item || '').trim())
    .filter(Boolean)
    .filter((item) => {
      const key = item.toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 18);
}

const AI_MUSIC_MOODS = new Set([
  'chill',
  'sad',
  'love',
  'hype',
  'dreamy',
  'motivational',
  'late night',
  'soft',
  'cinematic',
  'spiritual',
  'afro vibe',
  'rap vibe',
]);

const AI_MUSIC_STYLES = new Set([
  'spoken word',
  'singing',
  'rap',
  'ambient',
  'melodic',
  'soft female voice',
  'soft male voice',
  'ambient voice',
]);

function normalizeAiMusicMood(value: unknown): string {
  const clean = String(value || '').trim().toLowerCase().replace(/[_-]+/g, ' ').replace(/\s+/g, ' ');
  return AI_MUSIC_MOODS.has(clean) ? clean : 'chill';
}

function normalizeAiMusicStyle(value: unknown): string {
  const clean = String(value || '').trim().toLowerCase().replace(/[_-]+/g, ' ').replace(/\s+/g, ' ');
  return AI_MUSIC_STYLES.has(clean) ? clean : 'spoken word';
}

function normalizeAiMusicPrompt(value: unknown) {
  const raw = String(value || '').replace(/\r/g, '').trim();
  const lines = raw
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(0, 6);
  const text = lines.join('\n').slice(0, 480).trim();
  return { text, lines };
}

function moderateAiMusicPrompt(promptText: string): { ok: boolean; detail?: string } {
  const lower = promptText.toLowerCase();
  if (!promptText.trim()) return { ok: false, detail: 'Write a few original lines first.' };
  if (promptText.length > 480) return { ok: false, detail: 'Keep music posts short: 1 to 6 lines.' };

  const blockedPatterns = [
    /\b(kill yourself|hurt yourself|suicide method|self harm instructions)\b/i,
    /\b(i will kill|i am going to kill|shoot up|bomb threat|stab them)\b/i,
    /\b(how to make a bomb|build a bomb|poison someone|make a weapon)\b/i,
    /\b(doxx|home address is|ssn|social security number|credit card number)\b/i,
    /\b(child porn|minor sexual|underage sexual|sexual minor)\b/i,
    /\b(scamming|phishing|crypto giveaway|wire me money)\b/i,
    /\b(slur|nazi praise|exterminate)\b/i,
  ];

  if (blockedPatterns.some((pattern) => pattern.test(promptText))) {
    return { ok: false, detail: 'That text needs review before it can become music. Try original, non-harmful words.' };
  }

  const copyrightSignals = [
    'lyrics from',
    'copy the lyrics',
    'sing the lyrics',
    'chorus from',
    'verse from',
    'make it sound exactly like',
    'in the style of',
    'like drake',
    'like taylor swift',
    'like beyonce',
    'like bad bunny',
  ];
  if (copyrightSignals.some((signal) => lower.includes(signal))) {
    return { ok: false, detail: 'Use your own words and avoid copying lyrics or imitating a real artist.' };
  }

  return { ok: true };
}

function buildAiMusicPrompt(promptText: string, mood: string, style: string) {
  return [
    `Create a short original social music clip from these original user words:`,
    promptText,
    '',
    `Mood: ${mood}.`,
    `Vocal style: ${style}.`,
    'Length: about 20 seconds.',
    'Use a tasteful background beat, clear voice, and keep the words understandable.',
    'Do not use copyrighted lyrics, real artist imitation, or famous melodies.',
  ].join('\n');
}

function buildWaveformData(seed: string, bars = 48): number[] {
  const source = seed || 'flames-up-ai-music';
  const values: number[] = [];
  for (let index = 0; index < bars; index += 1) {
    const char = source.charCodeAt(index % source.length) || 37;
    const mixed = (char * (index + 17) + index * 31) % 100;
    values.push(Number((0.22 + (mixed / 100) * 0.76).toFixed(2)));
  }
  return values;
}

function aiMusicAudioUrl(c: any, musicId: string) {
  const url = new URL(c.req.url);
  return `${url.origin}/api/music/audio/${encodeURIComponent(musicId)}`;
}

async function aiMusicSettingNumber(db: D1Database, key: string, envValue: unknown, min: number, max: number, fallback: number) {
  const row: any = await db.prepare('SELECT value FROM app_settings WHERE key = ?').bind(key).first().catch(() => null);
  return clampNumber(row?.value ?? envValue, min, max, fallback);
}

function publicAiMusicPayload(row: any, opts: { liked?: boolean; saved?: boolean; reposted?: boolean } = {}) {
  return {
    id: row.id,
    user_id: row.user_id,
    provider: row.provider || 'elevenlabs',
    prompt_text: row.prompt_text || '',
    lyrics_text: row.lyrics_text || row.prompt_text || '',
    mood: row.mood || 'chill',
    style: row.style || 'spoken word',
    audio_url: row.audio_url || '',
    audio_duration: Number(row.audio_duration || 0),
    waveform_data: parseJsonArray(row.waveform_data),
    status: row.status || 'pending',
    is_public: Number(row.is_public || 0) === 1,
    likes_count: Number(row.likes_count || 0),
    comments_count: Number(row.comments_count || 0),
    saves_count: Number(row.saves_count || 0),
    reposts_count: Number(row.reposts_count || 0),
    reports_count: Number(row.reports_count || 0),
    created_at: row.created_at,
    updated_at: row.updated_at,
    liked: !!opts.liked,
    saved: !!opts.saved,
    reposted: !!opts.reposted,
    user: {
      id: row.user_id,
      username: row.user_username || '',
      full_name: row.user_full_name || '',
      profile_image: row.user_profile_image || '',
    },
  };
}

const AUDIUS_APP_NAME = 'Captro';
const AUDIUS_BASE_URL = 'https://api.audius.co/v1';

function audiusUrl(path: string, params: Record<string, string | number | undefined>) {
  const url = new URL(`${AUDIUS_BASE_URL}${path}`);
  url.searchParams.set('app_name', AUDIUS_APP_NAME);
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== '') url.searchParams.set(key, String(value));
  });
  return url.toString();
}

function normalizeAudiusTrack(track: any) {
  const artwork = track?.artwork || track?.cover_art || {};
  const stream = track?.stream || {};
  const user = track?.user || {};
  const profilePicture = user?.profile_picture || {};
  const coverPhoto = user?.cover_photo || {};
  const id = String(track?.id || track?.track_id || '');
  return {
    id,
    track_id: id,
    numeric_track_id: track?.track_id || null,
    title: cleanText(track?.title || 'Untitled track', 180),
    artist: cleanText(user?.name || user?.handle || 'Audius artist', 120),
    artist_id: cleanText(user?.id || track?.user_id || '', 80),
    artist_handle: cleanText(user?.handle || '', 120),
    artist_profile_image: profilePicture?.['480x480'] || profilePicture?.['1000x1000'] || profilePicture?.['150x150'] || '',
    artist_cover_image: coverPhoto?.['640x'] || coverPhoto?.['2000x'] || '',
    artist_location: cleanText(user?.location || '', 120),
    artist_followers: clampNumber(user?.follower_count, 0, 100000000, 0),
    artwork_url: artwork?.['480x480'] || artwork?.['1000x1000'] || artwork?.['150x150'] || '',
    duration: clampNumber(track?.duration, 0, 60 * 60 * 6, 0),
    genre: cleanText(track?.genre || '', 80),
    play_count: clampNumber(track?.play_count, 0, 1000000000, 0),
    favorite_count: clampNumber(track?.favorite_count, 0, 1000000000, 0),
    repost_count: clampNumber(track?.repost_count, 0, 1000000000, 0),
    permalink: cleanText(track?.permalink || '', 500),
    description: cleanText(track?.description || user?.bio || '', 500),
    stream_url: typeof stream?.url === 'string' ? stream.url : '',
  };
}

async function fetchAudiusTracks(path: string, params: Record<string, string | number | undefined>) {
  const response = await fetch(audiusUrl(path, params), {
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) {
    throw new Error(`Audius returned ${response.status}`);
  }
  const data: any = await response.json();
  const tracks = Array.isArray(data?.data) ? data.data : [];
  return tracks.map(normalizeAudiusTrack).filter((track: any) => track.id);
}

async function cachedJson<T>(c: any, key: string, ttlSeconds: number, loader: () => Promise<T>): Promise<T> {
  if (c.env.KV) {
    const cached = await c.env.KV.get(key, 'json').catch(() => null);
    if (cached) return cached as T;
  }
  const fresh = await loader();
  if (c.env.KV) {
    await c.env.KV.put(key, JSON.stringify(fresh), { expirationTtl: ttlSeconds }).catch(() => undefined);
  }
  return fresh;
}

function sanitizeMediaName(value: unknown, fallback = 'upload'): string {
  const clean = String(value || fallback)
    .replace(/\.[a-z0-9]+$/i, '')
    .replace(/[^a-z0-9_-]+/gi, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
  return clean || fallback;
}

function contentTypeExtension(contentType: string, fallback = 'bin'): string {
  const normalized = contentType.toLowerCase().split(';')[0].trim();
  const map: Record<string, string> = {
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
    'audio/m4a': 'm4a',
    'audio/mp4': 'm4a',
    'audio/aac': 'aac',
    'audio/mpeg': 'mp3',
    'audio/wav': 'wav',
    'audio/webm': 'webm',
    'application/pdf': 'pdf',
    'text/plain': 'txt',
    'application/zip': 'zip',
    'application/msword': 'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
    'application/vnd.ms-powerpoint': 'ppt',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
    'application/vnd.ms-excel': 'xls',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  };
  return map[normalized] || fallback;
}

function contentTypeFromFilename(value: unknown): string {
  const map: Record<string, string> = {
    pdf: 'application/pdf',
    txt: 'text/plain',
    zip: 'application/zip',
    doc: 'application/msword',
    docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ppt: 'application/vnd.ms-powerpoint',
    pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    xls: 'application/vnd.ms-excel',
    xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };
  return map[fileExtension(value)] || '';
}

function bytesToArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const buffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(buffer).set(bytes);
  return buffer;
}

function dataUriToBytes(data: string, defaultContentType = 'image/jpeg'): { bytes: Uint8Array; contentType: string } {
  const text = String(data || '');
  const match = /^data:([^;,]+);base64,(.*)$/i.exec(text);
  const contentType = match?.[1] || defaultContentType;
  const base64Content = match?.[2] || (text.includes(',') ? text.split(',').pop() || '' : text);
  const binaryStr = atob(base64Content);
  const bytes = new Uint8Array(binaryStr.length);
  for (let i = 0; i < binaryStr.length; i++) bytes[i] = binaryStr.charCodeAt(i);
  return { bytes, contentType };
}

function normalizedContentType(value: unknown): string {
  return String(value || '').split(';')[0].trim().toLowerCase();
}

const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/jpg', 'image/png', 'image/webp']);
const ALLOWED_VIDEO_TYPES = new Set(['video/mp4', 'video/quicktime', 'video/webm']);
const ALLOWED_AUDIO_TYPES = new Set(['audio/m4a', 'audio/mp4', 'audio/aac', 'audio/mpeg', 'audio/wav', 'audio/webm']);
const ALLOWED_FILE_TYPES = new Set([
  'application/pdf',
  'text/plain',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
]);
const ALLOWED_IMAGE_EXTENSIONS = new Set(['jpg', 'jpeg', 'png', 'webp']);
const ALLOWED_VIDEO_EXTENSIONS = new Set(['mp4', 'mov', 'webm']);
const ALLOWED_AUDIO_EXTENSIONS = new Set(['m4a', 'aac', 'mp3', 'wav', 'webm']);
const ALLOWED_FILE_EXTENSIONS = new Set(['pdf', 'txt', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx']);

function fileExtension(value: unknown): string {
  const match = /\.([a-z0-9]{1,12})$/i.exec(String(value || '').split(/[?#]/)[0]);
  return match ? match[1].toLowerCase() : '';
}

function extensionAllowed(filename: unknown, allowed: Set<string>): boolean {
  const ext = fileExtension(filename);
  return !ext || allowed.has(ext);
}

function detectImageContentType(bytes: Uint8Array): string {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return 'image/png';
  if (bytes.length >= 12
    && bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46
    && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) return 'image/webp';
  return '';
}

function looksLikePlainText(bytes: Uint8Array): boolean {
  const sample = bytes.slice(0, Math.min(bytes.length, 4096));
  if (sample.length === 0) return true;
  let suspicious = 0;
  for (const byte of sample) {
    const isAllowedWhitespace = byte === 0x09 || byte === 0x0a || byte === 0x0d;
    const isPrintable = byte >= 0x20 && byte <= 0x7e;
    const isUtf8HighByte = byte >= 0x80;
    if (!isAllowedWhitespace && !isPrintable && !isUtf8HighByte) suspicious += 1;
  }
  return suspicious / sample.length < 0.02;
}

function detectDocumentContentType(bytes: Uint8Array): string {
  if (bytes.length >= 5
    && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46 && bytes[4] === 0x2d) return 'application/pdf';
  if (bytes.length >= 4
    && bytes[0] === 0xd0 && bytes[1] === 0xcf && bytes[2] === 0x11 && bytes[3] === 0xe0) return 'application/msword';
  if (bytes.length >= 4
    && bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 0x03 && bytes[3] === 0x04) return 'application/zip';
  if (looksLikePlainText(bytes)) return 'text/plain';
  return '';
}

function documentContentMatches(declaredType: string, detectedType: string): boolean {
  if (declaredType === detectedType) return true;
  if (declaredType.startsWith('application/vnd.openxmlformats-officedocument.') && detectedType === 'application/zip') return true;
  if (['application/msword', 'application/vnd.ms-powerpoint', 'application/vnd.ms-excel'].includes(declaredType) && detectedType === 'application/msword') return true;
  return false;
}

async function sha256BinaryHex(input: ArrayBuffer | Uint8Array): Promise<string> {
  const buffer = input instanceof Uint8Array ? bytesToArrayBuffer(input) : input;
  const hash = await crypto.subtle.digest('SHA-256', buffer);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function maxBackupVideoBytes(c: any): number {
  const workerSafeCap = 25_000_000;
  const raw = Number(c.env.MEDIA_BACKUP_MAX_VIDEO_BYTES || workerSafeCap);
  return Math.min(Number.isFinite(raw) && raw > 0 ? raw : workerSafeCap, workerSafeCap);
}

function mediaDeliveryUrl(c: any, backupId: string): string {
  const origin = new URL(c.req.url).origin;
  return `${origin}/api/media/${encodeURIComponent(backupId)}`;
}

function mediaBackupIdFromReference(value: unknown): string {
  const raw = String(value || '').trim();
  if (!raw) return '';
  const relative = /^\/api\/media\/([a-zA-Z0-9_-]{8,160})(?:[?#].*)?$/.exec(raw);
  if (relative) return relative[1];
  try {
    const url = new URL(raw);
    const match = /^\/api\/media\/([a-zA-Z0-9_-]{8,160})$/.exec(url.pathname);
    return match ? match[1] : '';
  } catch {
    return '';
  }
}

async function mediaAccessSignature(c: any, backupId: string, expiresAt: number): Promise<string> {
  return hmacSha256Hex(getJwtSecret(c), `media:${backupId}:${expiresAt}`);
}

async function signedMediaDeliveryUrl(c: any, backupId: string): Promise<string> {
  const expiresAt = Math.floor(Date.now() / 1000) + 24 * 60 * 60;
  const signature = await mediaAccessSignature(c, backupId, expiresAt);
  const url = new URL(mediaDeliveryUrl(c, backupId));
  url.searchParams.set('exp', String(expiresAt));
  url.searchParams.set('sig', signature);
  return url.toString();
}

async function hasValidMediaAccessToken(c: any, backupId: string): Promise<boolean> {
  const expiresAt = Number(c.req.query('exp') || 0);
  const signature = String(c.req.query('sig') || '').trim().toLowerCase();
  if (!Number.isFinite(expiresAt) || expiresAt < Math.floor(Date.now() / 1000)) return false;
  if (!/^[a-f0-9]{64}$/.test(signature)) return false;
  const expected = await mediaAccessSignature(c, backupId, expiresAt);
  return constantTimeEqualHex(signature, expected);
}

async function signedMessageMediaReference(c: any, value: unknown): Promise<string> {
  const raw = String(value || '').trim();
  const backupId = mediaBackupIdFromReference(raw);
  return backupId ? signedMediaDeliveryUrl(c, backupId) : raw;
}

function normalizedMediaReferenceForStorage(c: any, value: string): string {
  const backupId = mediaBackupIdFromReference(value);
  return backupId ? mediaDeliveryUrl(c, backupId) : value;
}

function appendBytes(out: number[], bytes: Uint8Array) {
  for (let i = 0; i < bytes.length; i += 1) out.push(bytes[i]);
}

function stripJpegMetadata(bytes: Uint8Array): { bytes: Uint8Array; stripped: boolean } {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return { bytes, stripped: false };
  const out: number[] = [0xff, 0xd8];
  let offset = 2;
  let stripped = false;

  while (offset < bytes.length) {
    if (bytes[offset] !== 0xff) {
      appendBytes(out, bytes.subarray(offset));
      break;
    }

    while (bytes[offset] === 0xff) offset += 1;
    const marker = bytes[offset];
    offset += 1;

    if (marker === 0xda || marker === 0xd9) {
      out.push(0xff, marker);
      appendBytes(out, bytes.subarray(offset));
      break;
    }

    if ((marker >= 0xd0 && marker <= 0xd7) || marker === 0x01) {
      out.push(0xff, marker);
      continue;
    }

    if (offset + 2 > bytes.length) return { bytes, stripped: false };
    const length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return { bytes, stripped: false };

    // APP1 contains EXIF/XMP, including device, timestamp, and location metadata.
    if (marker === 0xe1) {
      offset += length;
      stripped = true;
      continue;
    }

    out.push(0xff, marker);
    appendBytes(out, bytes.subarray(offset, offset + length));
    offset += length;
  }

  return stripped ? { bytes: new Uint8Array(out), stripped } : { bytes, stripped: false };
}

function readUint32(bytes: Uint8Array, offset: number): number {
  return ((bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]) >>> 0;
}

function writeUint32(out: number[], value: number) {
  out.push((value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff);
}

function stripPngMetadata(bytes: Uint8Array): { bytes: Uint8Array; stripped: boolean } {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 16 || !signature.every((part, index) => bytes[index] === part)) return { bytes, stripped: false };
  const removable = new Set(['eXIf', 'tEXt', 'iTXt', 'zTXt', 'tIME']);
  const out: number[] = [];
  appendBytes(out, bytes.subarray(0, 8));
  let offset = 8;
  let stripped = false;

  while (offset + 12 <= bytes.length) {
    const length = readUint32(bytes, offset);
    const typeStart = offset + 4;
    const type = String.fromCharCode(bytes[typeStart], bytes[typeStart + 1], bytes[typeStart + 2], bytes[typeStart + 3]);
    const chunkEnd = offset + 12 + length;
    if (chunkEnd > bytes.length) return { bytes, stripped: false };

    if (removable.has(type)) {
      stripped = true;
    } else {
      appendBytes(out, bytes.subarray(offset, chunkEnd));
    }
    offset = chunkEnd;
    if (type === 'IEND') break;
  }

  return stripped ? { bytes: new Uint8Array(out), stripped } : { bytes, stripped: false };
}

function stripWebpMetadata(bytes: Uint8Array): { bytes: Uint8Array; stripped: boolean } {
  if (
    bytes.length < 12
    || String.fromCharCode(...bytes.subarray(0, 4)) !== 'RIFF'
    || String.fromCharCode(...bytes.subarray(8, 12)) !== 'WEBP'
  ) return { bytes, stripped: false };

  const out: number[] = [];
  appendBytes(out, bytes.subarray(0, 12));
  let offset = 12;
  let stripped = false;
  while (offset + 8 <= bytes.length) {
    const type = String.fromCharCode(...bytes.subarray(offset, offset + 4));
    const size = (bytes[offset + 4] | (bytes[offset + 5] << 8) | (bytes[offset + 6] << 16) | (bytes[offset + 7] << 24)) >>> 0;
    const paddedSize = size + (size % 2);
    const chunkEnd = offset + 8 + paddedSize;
    if (chunkEnd > bytes.length) return { bytes, stripped: false };
    if (type === 'EXIF' || type === 'XMP ') {
      stripped = true;
    } else {
      appendBytes(out, bytes.subarray(offset, chunkEnd));
    }
    offset = chunkEnd;
  }

  if (!stripped) return { bytes, stripped: false };
  const result = new Uint8Array(out);
  const riffSize = result.length - 8;
  result[4] = riffSize & 0xff;
  result[5] = (riffSize >>> 8) & 0xff;
  result[6] = (riffSize >>> 16) & 0xff;
  result[7] = (riffSize >>> 24) & 0xff;
  return { bytes: result, stripped };
}

function preserveOriginalImage(bytes: Uint8Array, contentType: string) {
  const normalized = normalizedContentType(contentType);
  const stripped = normalized === 'image/jpeg' || normalized === 'image/jpg'
    ? stripJpegMetadata(bytes)
    : normalized === 'image/png'
      ? stripPngMetadata(bytes)
      : normalized === 'image/webp'
        ? stripWebpMetadata(bytes)
        : { bytes, stripped: false };
  return { bytes: stripped.bytes, contentType, status: stripped.stripped ? 'metadata_stripped' : 'original' };
}

async function storeMediaBackup(c: any, opts: {
  userId: string;
  postId?: string | null;
  mediaKind: 'image' | 'video' | 'audio' | 'file';
  provider: string;
  providerId?: string;
  deliveryUrl?: string;
  contentType: string;
  bytes: ArrayBuffer | Uint8Array;
  originalFilename?: string;
}) {
  if (!c.env.MEDIA_BACKUP) return null;
  await ensureMediaBackupSchema(c.env.DB);

  const id = uuid();
  const date = new Date().toISOString().slice(0, 10);
  const ext = contentTypeExtension(opts.contentType, opts.mediaKind === 'image' ? 'jpg' : opts.mediaKind === 'audio' ? 'm4a' : opts.mediaKind === 'file' ? 'bin' : 'mp4');
  const key = `users/${opts.userId}/${date}/${id}.${ext}`;
  const buffer = opts.bytes instanceof Uint8Array ? bytesToArrayBuffer(opts.bytes) : opts.bytes;
  const checksum = await sha256BinaryHex(buffer);
  const createdAt = now();
  const deliveryUrl = opts.deliveryUrl || mediaDeliveryUrl(c, id);

  await c.env.MEDIA_BACKUP.put(key, buffer, {
    httpMetadata: { contentType: opts.contentType },
    customMetadata: {
      userId: opts.userId,
      postId: opts.postId || '',
      mediaKind: opts.mediaKind,
      provider: opts.provider,
      providerId: opts.providerId || '',
    },
  });

  await c.env.DB.prepare(
    `INSERT INTO media_backups (id, user_id, post_id, media_kind, provider, provider_id, delivery_url, r2_key, content_type, size_bytes, checksum_sha256, original_filename, backup_status, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'stored', ?, ?)`
  ).bind(
    id,
    opts.userId,
    opts.postId || null,
    opts.mediaKind,
    opts.provider,
    opts.providerId || '',
    deliveryUrl,
    key,
    opts.contentType,
    buffer.byteLength,
    checksum,
    opts.originalFilename || '',
    createdAt,
    createdAt,
  ).run();

  return { id, r2_key: key, delivery_url: deliveryUrl, size_bytes: buffer.byteLength, checksum_sha256: checksum };
}

async function attachMediaBackupsToPost(db: D1Database, userId: string, postId: string, backupIds: string[]) {
  const ids = backupIds.map(String).filter(Boolean);
  if (!ids.length) return;
  await ensureMediaBackupSchema(db);

  for (const backupId of ids) {
    await db.prepare('UPDATE media_backups SET post_id = ?, updated_at = ? WHERE id = ? AND user_id = ?')
      .bind(postId, now(), backupId, userId)
      .run();
  }
}

async function attachMediaBackupToMessage(
  db: D1Database,
  userId: string,
  messageId: string,
  mediaUrl: string,
  column: 'message_id' | 'group_message_id'
) {
  const backupId = mediaBackupIdFromReference(mediaUrl);
  if (!backupId) return;
  await ensureMediaBackupSchema(db);
  await db.prepare(`UPDATE media_backups SET ${column} = ?, updated_at = ? WHERE id = ? AND user_id = ?`)
    .bind(messageId, now(), backupId, userId)
    .run();
}

async function messagePayload(c: any, row: any): Promise<any> {
  const mediaUrl = row.media_url ? await signedMessageMediaReference(c, row.media_url) : row.media_url;
  return { ...row, media_url: mediaUrl };
}

const FEED_MEDIA_WIDTH = 1080;
const FEED_MEDIA_HEIGHT = 1440;
const FEED_MEDIA_ASPECT_RATIO = FEED_MEDIA_WIDTH / FEED_MEDIA_HEIGHT;

function replaceCloudflareImageVariant(url: string, variant: string): string {
  const cleanVariant = cleanText(variant, 80);
  if (!cleanVariant) return url;
  try {
    const parsed = new URL(url);
    if (!hostMatches(parsed.hostname, 'imagedelivery.net')) return url;
    const segments = parsed.pathname.split('/').filter(Boolean);
    if (segments.length < 3) return url;
    segments[segments.length - 1] = cleanVariant;
    parsed.pathname = `/${segments.join('/')}`;
    return parsed.toString();
  } catch {
    return url;
  }
}

function isVideoMediaUrl(url: string): boolean {
  const lower = String(url || '').toLowerCase();
  return lower.startsWith('cfstream:') || /\.(mp4|mov|m4v|webm)(\?|#|$)/.test(lower);
}

function feedDeliveryUrl(url: string, mediaType: string, variant: string): string {
  if (!url) return '';
  if (mediaType === 'video') return url;
  return replaceCloudflareImageVariant(url, variant);
}

function posterDeliveryUrl(url: string, mediaType: string, variant: string): string {
  if (!url) return '';
  if (mediaType !== 'video') return replaceCloudflareImageVariant(url, variant);
  return url;
}

function cloudflareStreamUid(url: string): string {
  const clean = String(url || '').trim();
  if (!clean.startsWith('cfstream:')) return '';
  return clean.replace('cfstream:', '').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 128);
}

function streamThumbnailUrl(url: string): string {
  const uid = cloudflareStreamUid(url);
  return uid ? `https://videodelivery.net/${uid}/thumbnails/thumbnail.jpg?time=1s&height=720` : '';
}

function streamPlaybackUrl(url: string): string {
  const uid = cloudflareStreamUid(url);
  return uid ? `https://videodelivery.net/${uid}/manifest/video.m3u8` : url;
}

function feedMediaDimensions(mediaUrls: string[], mediaTypes: string[], dimensions: any[]) {
  return mediaUrls.map((url, index) => {
    const original = dimensions[index] || {};
    const originalWidth = Number(original.width || original.original_width || 0) || null;
    const originalHeight = Number(original.height || original.original_height || 0) || null;
    const originalAspectRatio = Number(original.ratio || original.aspect_ratio || (originalWidth && originalHeight ? originalWidth / originalHeight : 0)) || null;
    const rawType = String(mediaTypes[index] || original.type || '').toLowerCase();
    const mediaType = rawType.includes('video') || isVideoMediaUrl(url) ? 'video' : 'image';
    return {
      ...original,
      original_width: originalWidth,
      original_height: originalHeight,
      original_aspect_ratio: originalAspectRatio,
      feed_width: FEED_MEDIA_WIDTH,
      feed_height: FEED_MEDIA_HEIGHT,
      feed_aspect_ratio: FEED_MEDIA_ASPECT_RATIO,
      media_type: mediaType,
      type: mediaType,
    };
  });
}

function normalizeDisplayLocationSource(value: unknown): string {
  const clean = cleanText(value, 40).toLowerCase();
  return ['user_profile', 'mapbox_reverse_geocode', 'manual', 'none'].includes(clean) ? clean : 'none';
}

function normalizeDisplayLocationVisibility(value: unknown): string {
  const clean = cleanText(value, 40).toLowerCase();
  return ['public', 'followers', 'hidden'].includes(clean) ? clean : 'hidden';
}

function normalizeAppleMapKitProvider(value: unknown): string {
  const clean = cleanText(value, 40).toLowerCase();
  return clean === 'apple_mapkit' ? 'apple_mapkit' : '';
}

function normalizeDisplayLocationLabel(city: string, region: string, country: string, fallback: string): string {
  const label = cleanText(fallback, 120);
  if (label) return label;
  const parts = [city, region, country].map((part) => cleanText(part, 80)).filter(Boolean);
  if (!parts.length) return '';
  if (parts.length === 3) return `${parts[0]}, ${parts[1]}, ${parts[2]}`;
  return parts.join(', ');
}

function looksLikePrivatePlace(name: string, address: string, category: string): boolean {
  const text = `${name} ${address} ${category}`.toLowerCase();
  if (!text.trim()) return false;
  if (/\b(home|house|apartment|apt|unit|private residence|residential)\b/.test(text)) return true;
  return /\b\d{1,6}\s+[a-z0-9.' -]+\s+(street|st|avenue|ave|road|rd|lane|ln|drive|dr|court|ct|way|boulevard|blvd)\b/.test(text)
    && !/\b(restaurant|cafe|coffee|gym|park|museum|bar|club|hotel|school|store|venue|stadium|gallery)\b/.test(text);
}

function postPayload(post: any, likedBy: string[] = [], env?: Env) {
  const audioHidden = Number(post.audio_hidden || 0) === 1;
  const likesCount = Math.max(0, Number(post.live_likes_count ?? post.likes_count ?? 0));
  const commentsCount = Math.max(0, Number(post.live_comments_count ?? post.comments_count ?? 0));
  const savesCount = Math.max(0, Number(post.live_saves_count ?? post.saves_count ?? 0));
  const isLiked = post.is_liked === true || post.is_liked === 1 || post.is_liked === '1';
  const isSaved = post.is_saved === true || post.is_saved === 1 || post.is_saved === '1' || post.saved === true || post.saved === 1 || post.saved === '1';
  const mediaUrls = sanitizeMediaReferences(post.images, post.image);
  const primaryMediaUrl = safeMediaReference(post.image) || mediaUrls[0] || '';
  const mediaTypes = parseJsonArray(post.media_types).map((item) => String(item || '').toLowerCase().includes('video') ? 'video' : 'image');
  while (mediaTypes.length < mediaUrls.length) mediaTypes.push(isVideoMediaUrl(mediaUrls[mediaTypes.length]) ? 'video' : 'image');
  const dimensions = parseJsonArray(post.media_dimensions);
  const feedVariant = env?.CLOUDFLARE_IMAGES_FEED_VARIANT || '';
  const thumbnailVariant = env?.CLOUDFLARE_IMAGES_THUMBNAIL_VARIANT || '';
  const feedMediaUrls = mediaUrls.map((url, index) => feedDeliveryUrl(url, mediaTypes[index] || 'image', feedVariant)).filter(Boolean);
  const thumbnailUrls = mediaUrls.map((url, index) => posterDeliveryUrl(url, mediaTypes[index] || 'image', thumbnailVariant)).filter(Boolean);
  const posterUrls = mediaUrls.map((url, index) => posterDeliveryUrl(url, mediaTypes[index] || 'image', thumbnailVariant)).filter(Boolean);
  const primaryCategory = normalizeDiscoverCategory(post.primary_category || post.category || post.post_type || 'lifestyle', false) || 'lifestyle';
  const categoryConfidence = clampFloat(post.category_confidence, 0, 1, 0);
  const displayLocationVisibility = normalizeDisplayLocationVisibility(post.display_location_visibility);
  const canShowDisplayLocation = displayLocationVisibility === 'public'
    || (displayLocationVisibility === 'followers' && (post.is_following === true || post.is_following === 1 || post.is_following === '1'));
  const displayLocationLabel = !canShowDisplayLocation
    ? ''
    : normalizeDisplayLocationLabel(post.display_city || '', post.display_region || '', post.display_country || '', post.display_location_label || '');
  const payload = {
    ...post,
    user_username: publicUsernameFor({ username: post.user_username }),
    user_profile_image: safeMediaReference(post.user_profile_image),
    likes_count: likesCount,
    comments_count: commentsCount,
    saves_count: savesCount,
    is_liked: isLiked,
    is_saved: isSaved,
    saved: isSaved,
    image: primaryMediaUrl,
    images: mediaUrls,
    feed_media_urls: feedMediaUrls,
    thumbnail_urls: thumbnailUrls,
    poster_urls: posterUrls,
    original_media_url: primaryMediaUrl,
    original_media_urls: mediaUrls,
    media_types: mediaTypes.slice(0, mediaUrls.length || mediaTypes.length),
    media_backup_ids: parseJsonArray(post.media_backup_ids),
    media_dimensions: feedMediaDimensions(mediaUrls, mediaTypes, dimensions),
    feed_width: FEED_MEDIA_WIDTH,
    feed_height: FEED_MEDIA_HEIGHT,
    feed_aspect_ratio: FEED_MEDIA_ASPECT_RATIO,
    primary_category: primaryCategory,
    category: primaryCategory,
    category_confidence: categoryConfidence,
    category_source: normalizeCategorySource(post.category_source),
    category_status: normalizeCategoryStatus(post.category_status),
    category_signals: parseJsonObject(post.category_signals_json),
    tags: sanitizeAutoCategoryTags(post.tags_json),
    display_city: canShowDisplayLocation ? cleanText(post.display_city, 80) : '',
    display_region: canShowDisplayLocation ? cleanText(post.display_region, 80) : '',
    display_country: canShowDisplayLocation ? cleanText(post.display_country, 80) : '',
    display_location_label: displayLocationLabel,
    display_location_source: displayLocationLabel ? normalizeDisplayLocationSource(post.display_location_source) : 'none',
    display_location_visibility: displayLocationVisibility,
    place_provider: cleanText(post.place_provider, 40),
    place_provider_id: cleanText(post.place_provider_id || post.place_id, 160),
    place_formatted_address: cleanText(post.place_formatted_address || post.location, 260),
    place_category: cleanText(post.place_category, 80),
    place_city: cleanText(post.place_city, 80),
    place_region: cleanText(post.place_region, 80),
    place_country: cleanText(post.place_country, 80),
    editor_overlays: parseJsonArray(post.editor_overlays),
    tagged_users: parseJsonArray(post.tagged_users),
    liked_by: likedBy,
    is_verified_checkin: !!post.is_verified_checkin,
  };
  delete payload.live_likes_count;
  delete payload.live_comments_count;
  delete payload.live_saves_count;
  delete payload.place_lat;
  delete payload.place_lng;
  if (audioHidden) {
    payload.audio_provider = '';
    payload.audio_track_id = '';
    payload.audio_title = '';
    payload.audio_artist = '';
    payload.audio_artwork_url = '';
    payload.audio_stream_url = '';
    payload.audio_start_time = 0;
    payload.audio_duration = 0;
  }
  return payload;
}

function feedPostPayload(post: any, likedBy: string[] = [], env?: Env) {
  const payload: any = postPayload(post, likedBy, env);
  const feedUrls = Array.isArray(payload.feed_media_urls) ? payload.feed_media_urls.filter(Boolean) : [];
  if (feedUrls.length) {
    payload.image = feedUrls[0];
    payload.images = feedUrls;
  }
  delete payload.original_media_url;
  delete payload.original_media_urls;
  delete payload.media_backup_ids;
  delete payload.client_request_id;
  delete payload.removed_at;
  delete payload.removed_reason;
  delete payload.hidden_at;
  delete payload.hidden_by_user_id;
  delete payload.user_email;
  delete payload.place_lat;
  delete payload.place_lng;
  delete payload.category_signals_json;
  delete payload.category_signals;
  return payload;
}

async function getPostEngagementState(db: D1Database, postId: string, userId: string) {
  const row: any = await db.prepare(
    `SELECT
       (SELECT COUNT(*) FROM likes WHERE post_id = ?) AS likes_count,
       (SELECT COUNT(*) FROM comments WHERE post_id = ? AND COALESCE(status, 'active') NOT IN ('removed', 'hidden')) AS comments_count,
       (SELECT COUNT(*) FROM saved_posts WHERE post_id = ?) AS saves_count,
       EXISTS (SELECT 1 FROM likes WHERE user_id = ? AND post_id = ?) AS is_liked,
       EXISTS (SELECT 1 FROM saved_posts WHERE user_id = ? AND post_id = ?) AS saved`
  ).bind(postId, postId, postId, userId, postId, userId, postId).first();

  const state = {
    likes_count: Math.max(0, Number(row?.likes_count || 0)),
    comments_count: Math.max(0, Number(row?.comments_count || 0)),
    saves_count: Math.max(0, Number(row?.saves_count || 0)),
    liked: row?.is_liked === true || row?.is_liked === 1 || row?.is_liked === '1',
    saved: row?.saved === true || row?.saved === 1 || row?.saved === '1',
  };

  // Keep the denormalized counters repaired, but never trust them as the source of truth.
  try {
    await db.prepare('UPDATE posts SET likes_count = ?, comments_count = ?, saves_count = ? WHERE id = ?')
      .bind(state.likes_count, state.comments_count, state.saves_count, postId)
      .run();
  } catch {}
  return state;
}

async function isFriend(db: D1Database, userId: string, targetId: string): Promise<boolean> {
  const friendship = await db.prepare('SELECT id FROM friendships WHERE user_id = ? AND friend_id = ?').bind(userId, targetId).first();
  return !!friendship;
}

async function canViewUserContent(db: D1Database, viewerId: string, owner: any): Promise<boolean> {
  if (!owner) return false;
  if (viewerId === owner.id) return true;
  try {
    const block = await db.prepare('SELECT id FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1')
      .bind(viewerId, owner.id, owner.id, viewerId)
      .first();
    if (block) return false;
  } catch {}
  if (!owner.is_private) return true;
  return isFriend(db, viewerId, owner.id);
}

function safeUserPayload(user: any, opts: { includePrivate?: boolean } = {}) {
  const onboardingRequired = usernameNeedsOnboarding(user);
  const publicPayload: any = {
    id: user.id,
    username: publicUsernameFor(user),
    username_required: onboardingRequired,
    onboarding_required: onboardingRequired,
    full_name: cleanText(user.full_name, 120),
    profile_image: safeMediaReference(user.profile_image),
    cover_image: safeMediaReference(user.cover_image),
    profile_background_image: safeMediaReference(user.profile_background_image || user.cover_image),
    bio: cleanMultilineText(user.bio, 500),
    city: cleanText(user.city, 120),
    social_website: safeExternalUrl(user.social_website),
    social_tiktok: cleanText(user.social_tiktok, 120),
    social_instagram: cleanText(user.social_instagram, 120),
    followers_count: Number(user.followers_count || 0),
    following_count: Number(user.following_count || 0),
    posts_count: Number(user.posts_count || 0),
    is_creator: !!user.is_creator,
    is_verified: !!user.is_verified,
    is_private: !!user.is_private,
    is_premium: userHasActivePremium(user),
    language: normalizeLanguage(user.language),
  };

  if (opts.includePrivate) {
    publicPayload.email = publicUserEmail(user.email);
    publicPayload.phone = user.phone || '';
    publicPayload.phone_verified = !!user.phone_verified;
    publicPayload.is_admin = !!user.is_admin;
    publicPayload.is_publisher = !!user.is_publisher;
    publicPayload.premium_status = user.premium_status || '';
    publicPayload.premium_plan = user.premium_plan || '';
    publicPayload.premium_until = user.premium_until || '';
  }

  return publicPayload;
}

function normalizePhone(input: string): string {
  const trimmed = String(input || '').trim();
  const digits = trimmed.replace(/\D/g, '');
  if (digits.length < 10 || digits.length > 15) {
    throw new Error('PHONE_INVALID');
  }
  if (trimmed.startsWith('+')) return `+${digits}`;
  if (digits.length === 10) return `+1${digits}`;
  return `+${digits}`;
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hashBuffer)).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function normalizeOptionalEmail(value: unknown): string {
  const email = String(value || '').trim().toLowerCase();
  if (email.length > 254) return '';
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : '';
}

function normalizeOptionalName(value: unknown): string {
  return cleanText(value, 120);
}

function internalOAuthEmail(provider: 'google' | 'apple', subject: string): string {
  const safeSubject = subject.replace(/[^a-z0-9]/gi, '').toLowerCase().slice(0, 48) || 'user';
  return `${provider}_${safeSubject}@oauth.flames-up.local`;
}

function isInternalOAuthEmail(email: unknown): boolean {
  return String(email || '').toLowerCase().endsWith('@oauth.flames-up.local');
}

function isApplePrivateRelayEmail(email: unknown): boolean {
  return String(email || '').toLowerCase().endsWith('@privaterelay.appleid.com');
}

function publicUserEmail(email: unknown): string {
  return isInternalOAuthEmail(email) ? '' : String(email || '');
}

function safeDisplayNameFromEmail(email: unknown): string {
  const clean = normalizeOptionalEmail(email);
  if (!clean || isInternalOAuthEmail(clean) || isApplePrivateRelayEmail(clean)) return '';
  return cleanText(clean.split('@')[0], 80);
}

function getErrorCode(error: any): string {
  return String(error?.code || error?.message || '');
}

function getJwtSecret(c: any): string {
  const secret = String(c.env.JWT_SECRET || '').trim();
  if (!secret || secret === 'REPLACE_WITH_YOUR_JWT_SECRET') {
    throw new Error('JWT_SECRET_MISSING');
  }
  return secret;
}

function getAgoraConfig(c: any) {
  const appId = String(c.env.AGORA_APP_ID || '').trim();
  const appCertificate = String(c.env.AGORA_APP_CERTIFICATE || '').trim();
  if (!appId || !appCertificate) {
    throw new Error('AGORA_NOT_CONFIGURED');
  }
  return { appId, appCertificate };
}

function getStripeConfig(c: any) {
  const secretKey = String(c.env.STRIPE_SECRET_KEY || '').trim();
  const publishableKey = String(c.env.STRIPE_PUBLISHABLE_KEY || '').trim();
  const defaultPriceId = String(c.env.STRIPE_DEFAULT_PRICE_ID || '').trim();
  return {
    secretKey,
    publishableKey,
    defaultPriceId,
    configured: secretKey.startsWith('sk_') || secretKey.startsWith('rk_'),
  };
}

function getFrontendUrl(c: any): string {
  return String(c.env.FRONTEND_URL || 'https://flames-up.com').trim().replace(/\/+$/, '') || 'https://flames-up.com';
}

function allowedStripeReturnUrl(c: any, value: unknown, fallbackPath: string): string {
  const frontendUrl = getFrontendUrl(c);
  const fallback = `${frontendUrl}${fallbackPath}`;
  const raw = String(value || '').trim();
  if (!raw) return fallback;
  try {
    const url = new URL(raw);
    const allowed = new Set([
      new URL(frontendUrl).origin,
      'https://flames-up.com',
      'https://www.flames-up.com',
    ]);
    return allowed.has(url.origin) ? url.toString() : fallback;
  } catch {
    return fallback;
  }
}

async function stripeApiRequest(c: any, path: string, params?: Record<string, string | number | boolean | null | undefined>, idempotencyKey?: string | null) {
  const stripe = getStripeConfig(c);
  if (!stripe.configured) {
    return { ok: false, status: 503, data: { detail: 'Stripe is not configured yet.', code: 'STRIPE_NOT_CONFIGURED' } };
  }

  const body = new URLSearchParams();
  for (const [key, value] of Object.entries(params || {})) {
    if (value === undefined || value === null || value === '') continue;
    body.append(key, String(value));
  }

  const headers: Record<string, string> = {
    Authorization: `Bearer ${stripe.secretKey}`,
    'Content-Type': 'application/x-www-form-urlencoded',
  };
  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;

  const response = await fetch(`https://api.stripe.com/v1${path}`, {
    method: 'POST',
    headers,
    body,
  });
  const data: any = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, data };
}

async function stripeApiGet(c: any, path: string) {
  const stripe = getStripeConfig(c);
  if (!stripe.configured) {
    return { ok: false, status: 503, data: { detail: 'Stripe is not configured yet.', code: 'STRIPE_NOT_CONFIGURED' } };
  }
  const response = await fetch(`https://api.stripe.com/v1${path}`, {
    method: 'GET',
    headers: { Authorization: `Bearer ${stripe.secretKey}` },
  });
  const data: any = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, data };
}

const PREMIUM_PLAN = {
  id: 'monthly',
  label: 'Flames Up Premium',
  amount_cents: 499,
  currency: 'usd',
  interval: 'month',
};

const PREMIUM_FEATURES = [
  'Anonymous Notes up to 5 times per day',
  'Custom profile background',
  'Background music playback',
  'Premium profile badge',
];

function getPremiumPriceId(c: any): string {
  return cleanText(c.env.STRIPE_PREMIUM_PRICE_ID, 120);
}

function stripeUnixToIso(value: unknown): string {
  const seconds = Number(value || 0);
  if (!Number.isFinite(seconds) || seconds <= 0) return '';
  return new Date(seconds * 1000).toISOString();
}

function premiumStatusIsActive(status: unknown, until: unknown): boolean {
  const cleanStatus = String(status || '').toLowerCase();
  if (!['active', 'trialing'].includes(cleanStatus)) return false;
  const untilDate = String(until || '');
  if (!untilDate) return true;
  const time = Date.parse(untilDate);
  return !Number.isFinite(time) || time > Date.now();
}

function userHasActivePremium(user: any): boolean {
  return Number(user?.is_premium || 0) === 1 && premiumStatusIsActive(user?.premium_status || 'active', user?.premium_until);
}

function premiumPayloadFromUser(user: any, anonymousNotesUsed = 0) {
  const used = Math.max(0, Number(anonymousNotesUsed || 0));
  return {
    is_premium: userHasActivePremium(user),
    plan: user?.premium_plan || '',
    status: user?.premium_status || '',
    premium_until: user?.premium_until || '',
    monthly_price: '$4.99/month',
    amount_cents: PREMIUM_PLAN.amount_cents,
    currency: PREMIUM_PLAN.currency,
    interval: PREMIUM_PLAN.interval,
    anonymous_notes_used_today: used,
    anonymous_notes_remaining_today: Math.max(0, 5 - used),
    features: PREMIUM_FEATURES,
  };
}

async function getAnonymousNotesUsedToday(db: D1Database, userId: string): Promise<number> {
  await ensureNotesSchema(db);
  const row: any = await db.prepare(
    `SELECT COUNT(*) AS count
     FROM notes
     WHERE user_id = ? AND anonymous = 1
       AND COALESCE(status, 'active') = 'active'
       AND date(created_at) = date('now')`
  ).bind(userId).first();
  return Math.max(0, Number(row?.count || 0));
}

async function getPremiumUser(c: any, userId: string): Promise<any> {
  await ensurePremiumSchema(c.env.DB);
  return c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
}

async function upsertPremiumSubscription(c: any, input: {
  userId: string;
  stripeCustomerId?: string;
  stripeSubscriptionId?: string;
  stripeCheckoutSessionId?: string;
  priceId?: string;
  status?: string;
  currentPeriodEnd?: string;
  cancelAtPeriodEnd?: boolean;
}) {
  await ensurePremiumSchema(c.env.DB);
  const userId = cleanText(input.userId, 80);
  if (!userId) return { processed: false };
  const stripeSubscriptionId = cleanText(input.stripeSubscriptionId, 140);
  const stripeCheckoutSessionId = cleanText(input.stripeCheckoutSessionId, 140);
  const stripeCustomerId = cleanText(input.stripeCustomerId, 140);
  const priceId = cleanText(input.priceId, 140);
  const status = cleanText(input.status || 'active', 40) || 'active';
  const currentPeriodEnd = cleanText(input.currentPeriodEnd, 40);
  const cancelAtPeriodEnd = input.cancelAtPeriodEnd ? 1 : 0;
  const ts = now();

  let existing: any = null;
  if (stripeSubscriptionId) {
    existing = await c.env.DB.prepare('SELECT * FROM premium_subscriptions WHERE stripe_subscription_id = ?')
      .bind(stripeSubscriptionId)
      .first();
  }
  if (!existing && stripeCheckoutSessionId) {
    existing = await c.env.DB.prepare('SELECT * FROM premium_subscriptions WHERE stripe_checkout_session_id = ?')
      .bind(stripeCheckoutSessionId)
      .first();
  }

  if (existing) {
    await c.env.DB.prepare(
      `UPDATE premium_subscriptions
       SET user_id = ?, stripe_customer_id = ?, stripe_subscription_id = ?, stripe_checkout_session_id = ?,
           price_id = ?, status = ?, current_period_end = ?, cancel_at_period_end = ?, updated_at = ?
       WHERE id = ?`
    ).bind(
      userId,
      stripeCustomerId || existing.stripe_customer_id || '',
      stripeSubscriptionId || existing.stripe_subscription_id || '',
      stripeCheckoutSessionId || existing.stripe_checkout_session_id || '',
      priceId || existing.price_id || '',
      status,
      currentPeriodEnd || existing.current_period_end || null,
      cancelAtPeriodEnd,
      ts,
      existing.id
    ).run();
  } else {
    await c.env.DB.prepare(
      `INSERT INTO premium_subscriptions
       (id, user_id, stripe_customer_id, stripe_subscription_id, stripe_checkout_session_id, price_id, status, current_period_end, cancel_at_period_end, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      uuid(),
      userId,
      stripeCustomerId,
      stripeSubscriptionId,
      stripeCheckoutSessionId,
      priceId,
      status,
      currentPeriodEnd || null,
      cancelAtPeriodEnd,
      ts,
      ts
    ).run();
  }

  const isPremium = premiumStatusIsActive(status, currentPeriodEnd) ? 1 : 0;
  await c.env.DB.prepare(
    `UPDATE users
     SET is_premium = ?, premium_plan = ?, premium_status = ?, premium_until = ?,
         premium_stripe_customer_id = COALESCE(NULLIF(?, ''), premium_stripe_customer_id),
         premium_stripe_subscription_id = COALESCE(NULLIF(?, ''), premium_stripe_subscription_id),
         updated_at = datetime('now')
     WHERE id = ?`
  ).bind(
    isPremium,
    PREMIUM_PLAN.id,
    status,
    currentPeriodEnd || null,
    stripeCustomerId,
    stripeSubscriptionId,
    userId
  ).run();

  return { processed: true, is_premium: isPremium === 1 };
}

async function expirePremiumCheckout(c: any, session: any) {
  await ensurePremiumSchema(c.env.DB);
  const sessionId = cleanText(session?.id, 140);
  if (!sessionId) return;
  await c.env.DB.prepare("UPDATE premium_subscriptions SET status = 'expired', updated_at = ? WHERE stripe_checkout_session_id = ? AND status = 'pending'")
    .bind(now(), sessionId)
    .run();
}

async function activatePremiumFromCheckoutSession(c: any, session: any) {
  await ensurePremiumSchema(c.env.DB);
  const metadata = session?.metadata || {};
  const userId = cleanText(metadata.user_id || session?.client_reference_id, 80);
  const subscriptionId = cleanText(session?.subscription, 140);
  const customerId = cleanText(session?.customer, 140);
  if (!userId || !subscriptionId) return { processed: false };

  let subscription: any = null;
  const subscriptionResponse = await stripeApiGet(c, `/subscriptions/${encodeURIComponent(subscriptionId)}`);
  if (subscriptionResponse.ok) subscription = subscriptionResponse.data;
  const item = subscription?.items?.data?.[0] || {};
  const fallbackStatus = session?.payment_status === 'paid' || session?.status === 'complete' ? 'active' : 'pending';
  return upsertPremiumSubscription(c, {
    userId,
    stripeCustomerId: cleanText(subscription?.customer || customerId, 140),
    stripeSubscriptionId: subscriptionId,
    stripeCheckoutSessionId: cleanText(session?.id, 140),
    priceId: cleanText(item?.price?.id || metadata.price_id || getPremiumPriceId(c), 140),
    status: cleanText(subscription?.status || fallbackStatus, 40) || 'active',
    currentPeriodEnd: stripeUnixToIso(subscription?.current_period_end),
    cancelAtPeriodEnd: !!subscription?.cancel_at_period_end,
  });
}

async function syncPremiumFromSubscription(c: any, subscription: any) {
  await ensurePremiumSchema(c.env.DB);
  const subscriptionId = cleanText(subscription?.id, 140);
  const customerId = cleanText(subscription?.customer, 140);
  let userId = cleanText(subscription?.metadata?.user_id, 80);
  if (!userId && subscriptionId) {
    const existing: any = await c.env.DB.prepare('SELECT user_id FROM premium_subscriptions WHERE stripe_subscription_id = ?')
      .bind(subscriptionId)
      .first();
    userId = cleanText(existing?.user_id, 80);
  }
  if (!userId && customerId) {
    const existing: any = await c.env.DB.prepare('SELECT id FROM users WHERE premium_stripe_customer_id = ?')
      .bind(customerId)
      .first();
    userId = cleanText(existing?.id, 80);
  }
  if (!userId) return { processed: false };
  const item = subscription?.items?.data?.[0] || {};
  return upsertPremiumSubscription(c, {
    userId,
    stripeCustomerId: customerId,
    stripeSubscriptionId: subscriptionId,
    priceId: cleanText(item?.price?.id || '', 140),
    status: cleanText(subscription?.status || 'canceled', 40) || 'canceled',
    currentPeriodEnd: stripeUnixToIso(subscription?.current_period_end),
    cancelAtPeriodEnd: !!subscription?.cancel_at_period_end,
  });
}

const COIN_PACKAGES = [
  { id: 'coins_100', label: '100 coins', coins: 100, amount_cents: 99 },
  { id: 'coins_600', label: '600 coins', coins: 600, amount_cents: 499 },
  { id: 'coins_1300', label: '1,300 coins', coins: 1300, amount_cents: 999 },
  { id: 'coins_3000', label: '3,000 coins', coins: 3000, amount_cents: 1999 },
];

const COIN_TRANSACTION_TYPES = new Set([
  'purchase',
  'spend',
  'refund',
  'bonus',
  'gift_sent',
  'gift_received',
  'boost',
  'admin_adjustment',
]);

function publicCoinPackages() {
  return COIN_PACKAGES.map((pack) => ({
    ...pack,
    price: `$${(pack.amount_cents / 100).toFixed(2)}`,
  }));
}

function resolveCoinPurchase(body: any): { package_id: string; coins: number; amount_cents: number; label: string; custom: boolean } | null {
  const packageId = cleanText(body.package_id || body.packageId, 80);
  const found = COIN_PACKAGES.find((pack) => pack.id === packageId);
  if (found) {
    return { package_id: found.id, coins: found.coins, amount_cents: found.amount_cents, label: found.label, custom: false };
  }

  const coins = clampNumber(body.coins || body.custom_coins || body.amount, 100, 50000, 0);
  if (!coins) return null;
  return {
    package_id: 'custom',
    coins,
    // Custom coins keep a simple 1 coin = 1 cent rate; fixed packages include bonus coins.
    amount_cents: coins,
    label: `${coins.toLocaleString('en-US')} coins`,
    custom: true,
  };
}

function coinMetadataJson(value: Record<string, unknown> = {}): string {
  const safe: Record<string, unknown> = {};
  for (const [key, raw] of Object.entries(value)) {
    if (raw === undefined || raw === null) continue;
    if (typeof raw === 'number' || typeof raw === 'boolean') {
      safe[key] = raw;
    } else {
      safe[key] = cleanText(raw, 500);
    }
  }
  return JSON.stringify(safe).slice(0, 4000);
}

async function getCoinBalance(db: D1Database, userId: string): Promise<any> {
  await ensureWalletSchema(db);
  const ts = now();
  await db.prepare('INSERT INTO coin_balances (user_id, balance, lifetime_purchased, lifetime_spent, updated_at) VALUES (?, 0, 0, 0, ?) ON CONFLICT(user_id) DO NOTHING')
    .bind(userId, ts)
    .run();
  const balance: any = await db.prepare('SELECT user_id, balance, lifetime_purchased, lifetime_spent, updated_at FROM coin_balances WHERE user_id = ?')
    .bind(userId)
    .first();
  return balance || { user_id: userId, balance: 0, lifetime_purchased: 0, lifetime_spent: 0, updated_at: ts };
}

async function reserveCoinIdempotencyKey(db: D1Database, key: string, userId: string, type: string): Promise<boolean> {
  if (!key) return true;
  try {
    await db.prepare('INSERT INTO coin_idempotency_keys (key, user_id, type, created_at) VALUES (?, ?, ?, ?)')
      .bind(key, userId, type, now())
      .run();
    return true;
  } catch (error: any) {
    const message = String(error?.message || '').toLowerCase();
    if (message.includes('unique') || message.includes('constraint')) return false;
    throw error;
  }
}

async function applyCoinDelta(c: any, input: {
  userId: string;
  type: string;
  amount: number;
  relatedUserId?: string;
  relatedId?: string;
  stripeSessionId?: string;
  stripePaymentIntentId?: string;
  idempotencyKey?: string;
  status?: string;
  metadata?: Record<string, unknown>;
}) {
  await ensureWalletSchema(c.env.DB);
  const userId = cleanText(input.userId, 80);
  const type = cleanText(input.type, 40);
  const amount = Math.trunc(Number(input.amount || 0));
  if (!userId || !COIN_TRANSACTION_TYPES.has(type) || amount === 0) {
    throw new Error('COINS_INVALID_TRANSACTION');
  }

  const idempotencyKey = cleanText(input.idempotencyKey, 160);
  if (idempotencyKey) {
    const existing: any = await c.env.DB.prepare('SELECT * FROM coin_transactions WHERE idempotency_key = ?')
      .bind(idempotencyKey)
      .first();
    if (existing) {
      const balance = await getCoinBalance(c.env.DB, userId);
      return { balance, transaction: existing, duplicate: true };
    }
    const reserved = await reserveCoinIdempotencyKey(c.env.DB, idempotencyKey, userId, type);
    if (!reserved) {
      const balance = await getCoinBalance(c.env.DB, userId);
      return { balance, transaction: null, duplicate: true };
    }
  }

  const ts = now();
  await c.env.DB.prepare('INSERT INTO coin_balances (user_id, balance, lifetime_purchased, lifetime_spent, updated_at) VALUES (?, 0, 0, 0, ?) ON CONFLICT(user_id) DO NOTHING')
    .bind(userId, ts)
    .run();

  const isPurchase = type === 'purchase' && amount > 0;
  const isSpend = ['spend', 'gift_sent', 'boost'].includes(type) && amount < 0;
  const update = await c.env.DB.prepare(
    `UPDATE coin_balances
     SET balance = balance + ?,
         lifetime_purchased = lifetime_purchased + ?,
         lifetime_spent = lifetime_spent + ?,
         updated_at = ?
     WHERE user_id = ? AND (? > 0 OR balance >= ?)`
  ).bind(
    amount,
    isPurchase ? amount : 0,
    isSpend ? Math.abs(amount) : 0,
    ts,
    userId,
    amount,
    Math.abs(amount)
  ).run();

  if (d1Changes(update) === 0) {
    if (idempotencyKey) {
      await c.env.DB.prepare('DELETE FROM coin_idempotency_keys WHERE key = ?').bind(idempotencyKey).run();
    }
    throw new Error('COINS_INSUFFICIENT');
  }

  const balance = await getCoinBalance(c.env.DB, userId);
  const transaction = {
    id: uuid(),
    user_id: userId,
    type,
    amount,
    balance_after: Number(balance.balance || 0),
    status: cleanText(input.status || 'completed', 40) || 'completed',
    related_user_id: cleanText(input.relatedUserId, 80),
    related_id: cleanText(input.relatedId, 120),
    stripe_session_id: cleanText(input.stripeSessionId, 120),
    stripe_payment_intent_id: cleanText(input.stripePaymentIntentId, 120),
    idempotency_key: idempotencyKey,
    metadata: coinMetadataJson(input.metadata || {}),
    created_at: ts,
  };

  // Wallet ledger: every backend balance mutation is recorded here for audit/history.
  await c.env.DB.prepare(
    `INSERT INTO coin_transactions
     (id, user_id, type, amount, balance_after, status, related_user_id, related_id, stripe_session_id, stripe_payment_intent_id, idempotency_key, metadata, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    transaction.id,
    transaction.user_id,
    transaction.type,
    transaction.amount,
    transaction.balance_after,
    transaction.status,
    transaction.related_user_id,
    transaction.related_id,
    transaction.stripe_session_id,
    transaction.stripe_payment_intent_id,
    transaction.idempotency_key,
    transaction.metadata,
    transaction.created_at
  ).run();

  return { balance, transaction, duplicate: false };
}

function sanitizeCoinTransaction(row: any) {
  return {
    id: row.id,
    type: row.type,
    amount: Number(row.amount || 0),
    balance_after: Number(row.balance_after || 0),
    status: row.status || 'completed',
    related_user_id: row.related_user_id || '',
    related_id: row.related_id || '',
    stripe_session_id: row.stripe_session_id || '',
    stripe_payment_intent_id: row.stripe_payment_intent_id || '',
    metadata: parseJsonObject(row.metadata),
    created_at: row.created_at,
  };
}

async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(payload));
  return Array.from(new Uint8Array(signature)).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function constantTimeEqualHex(a: string, b: string): boolean {
  const left = String(a || '');
  const right = String(b || '');
  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    diff |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }
  return diff === 0;
}

async function verifyStripeWebhookSignature(rawBody: string, signatureHeader: string, secret: string): Promise<boolean> {
  if (!secret || !signatureHeader) return false;
  const parts = signatureHeader.split(',').map((part) => part.trim());
  const timestamp = parts.find((part) => part.startsWith('t='))?.slice(2) || '';
  const signatures = parts.filter((part) => part.startsWith('v1=')).map((part) => part.slice(3));
  const timestampSeconds = Number(timestamp);
  if (!timestamp || signatures.length === 0 || !Number.isFinite(timestampSeconds)) return false;
  if (Math.abs(Math.floor(Date.now() / 1000) - timestampSeconds) > 300) return false;

  const expected = await hmacSha256Hex(secret, `${timestamp}.${rawBody}`);
  return signatures.some((signature) => constantTimeEqualHex(signature, expected));
}

async function completeCoinPurchaseFromSession(c: any, session: any) {
  await ensureWalletSchema(c.env.DB);
  const sessionId = cleanText(session?.id, 120);
  const paymentIntentId = cleanText(session?.payment_intent, 120);
  const metadata = session?.metadata || {};
  const orderId = cleanText(metadata.wallet_order_id, 120);
  if (!sessionId && !orderId) return { processed: false };

  let order: any = null;
  if (orderId) {
    order = await c.env.DB.prepare('SELECT * FROM coin_purchase_orders WHERE id = ?').bind(orderId).first();
  }
  if (!order && sessionId) {
    order = await c.env.DB.prepare('SELECT * FROM coin_purchase_orders WHERE stripe_session_id = ?').bind(sessionId).first();
  }
  if (!order) return { processed: false };
  if (String(order.status || '') === 'completed') return { processed: true, duplicate: true };

  await c.env.DB.prepare(
    `UPDATE coin_purchase_orders
     SET status = 'completed', stripe_session_id = COALESCE(stripe_session_id, ?), stripe_payment_intent_id = ?, updated_at = ?
     WHERE id = ?`
  ).bind(sessionId, paymentIntentId, now(), order.id).run();

  const result = await applyCoinDelta(c, {
    userId: order.user_id,
    type: 'purchase',
    amount: Number(order.coins || 0),
    stripeSessionId: sessionId,
    stripePaymentIntentId: paymentIntentId,
    idempotencyKey: `stripe_checkout_${sessionId || order.id}`,
    metadata: {
      order_id: order.id,
      package_id: order.package_id,
      amount_cents: Number(order.amount_cents || 0),
      currency: order.currency || 'usd',
    },
  });

  return { processed: true, result };
}

async function markCoinPurchaseExpired(c: any, session: any) {
  const sessionId = cleanText(session?.id, 120);
  if (!sessionId) return;
  await ensureWalletSchema(c.env.DB);
  await c.env.DB.prepare("UPDATE coin_purchase_orders SET status = 'expired', updated_at = ? WHERE stripe_session_id = ? AND status = 'pending'")
    .bind(now(), sessionId)
    .run();
}

async function refundCoinPurchase(c: any, payload: any) {
  await ensureWalletSchema(c.env.DB);
  const refundId = cleanText(payload?.id, 120);
  const paymentIntentId = cleanText(payload?.payment_intent, 120);
  const chargeId = cleanText(payload?.charge, 120);
  const amountRefunded = Number(payload?.amount_refunded || payload?.amount || 0);
  if (!paymentIntentId && !chargeId) return { processed: false };

  const order: any = paymentIntentId
    ? await c.env.DB.prepare('SELECT * FROM coin_purchase_orders WHERE stripe_payment_intent_id = ?').bind(paymentIntentId).first()
    : null;
  if (!order) return { processed: false };

  const orderCents = Math.max(1, Number(order.amount_cents || 0));
  const refundCents = Math.max(1, Math.min(orderCents, amountRefunded || orderCents));
  const coins = Math.max(1, Math.min(Number(order.coins || 0), Math.round(Number(order.coins || 0) * (refundCents / orderCents))));
  const idempotencyKey = `stripe_refund_${refundId || chargeId || paymentIntentId}`;
  await c.env.DB.prepare('UPDATE coin_purchase_orders SET status = ?, updated_at = ? WHERE id = ?')
    .bind(refundCents >= orderCents ? 'refunded' : 'partially_refunded', now(), order.id)
    .run();

  const currentBalance = await getCoinBalance(c.env.DB, order.user_id);
  const debitCoins = Math.min(coins, Number(currentBalance.balance || 0));
  if (debitCoins <= 0) {
    const existing: any = await c.env.DB.prepare('SELECT * FROM coin_transactions WHERE idempotency_key = ?')
      .bind(idempotencyKey)
      .first();
    if (existing) return { processed: true, duplicate: true };
    const reserved = await reserveCoinIdempotencyKey(c.env.DB, idempotencyKey, order.user_id, 'refund');
    if (!reserved) return { processed: true, duplicate: true };
    const transaction = {
      id: uuid(),
      user_id: order.user_id,
      type: 'refund',
      amount: 0,
      balance_after: Number(currentBalance.balance || 0),
      status: 'completed',
      related_user_id: '',
      related_id: order.id,
      stripe_session_id: '',
      stripe_payment_intent_id: paymentIntentId,
      idempotency_key: idempotencyKey,
      metadata: coinMetadataJson({ order_id: order.id, refund_id: refundId, charge_id: chargeId, refund_cents: refundCents, unrecovered_coins: coins }),
      created_at: now(),
    };
    await c.env.DB.prepare(
      `INSERT INTO coin_transactions
       (id, user_id, type, amount, balance_after, status, related_user_id, related_id, stripe_session_id, stripe_payment_intent_id, idempotency_key, metadata, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      transaction.id,
      transaction.user_id,
      transaction.type,
      transaction.amount,
      transaction.balance_after,
      transaction.status,
      transaction.related_user_id,
      transaction.related_id,
      transaction.stripe_session_id,
      transaction.stripe_payment_intent_id,
      transaction.idempotency_key,
      transaction.metadata,
      transaction.created_at
    ).run();
    return { processed: true, result: { balance: currentBalance, transaction } };
  }

  const result = await applyCoinDelta(c, {
    userId: order.user_id,
    type: 'refund',
    amount: -debitCoins,
    stripePaymentIntentId: paymentIntentId,
    idempotencyKey,
    metadata: {
      order_id: order.id,
      refund_id: refundId,
      charge_id: chargeId,
      refund_cents: refundCents,
      requested_refund_coins: coins,
      unrecovered_coins: coins - debitCoins,
    },
  });
  return { processed: true, result };
}

function normalizeAgoraChannel(value: unknown): string {
  const channel = String(value || '')
    .trim()
    .replace(/[^a-zA-Z0-9_ -]/g, '_')
    .replace(/\s+/g, '_')
    .slice(0, 63);

  if (!channel || new TextEncoder().encode(channel).length >= 64) {
    throw new Error('AGORA_INVALID_CHANNEL');
  }
  return channel;
}

function normalizeAgoraRole(value: unknown): { label: 'host' | 'audience'; rtcRole: number } {
  const role = String(value || '').trim().toLowerCase();
  if (role === 'audience' || role === 'subscriber') {
    return { label: 'audience', rtcRole: RtcRole.SUBSCRIBER };
  }
  return { label: 'host', rtcRole: RtcRole.PUBLISHER };
}

function getAgoraTokenTtl(c: any): number {
  const raw = Number.parseInt(String(c.env.AGORA_TOKEN_TTL_SECONDS || '3600'), 10);
  if (!Number.isFinite(raw)) return 3600;
  return Math.min(Math.max(raw, 60), 24 * 60 * 60);
}

async function numericAgoraUid(userId: string): Promise<number> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(userId));
  const view = new DataView(digest);
  return (view.getUint32(0) % 2147483646) + 1;
}

const ACTIVE_CALL_STATUSES = ['ringing', 'accepted', 'connecting', 'active'];

function buildCaptroCallChannel(callId: string): string {
  return normalizeAgoraChannel(`captro_${callId.replace(/-/g, '_').slice(0, 48)}`);
}

function callTimeoutAt(seconds = 42): string {
  return new Date(Date.now() + seconds * 1000).toISOString();
}

function safeCallPayload(row: any) {
  if (!row) return null;
  return {
    id: row.id,
    call_id: row.id,
    caller_user_id: row.caller_id,
    callee_user_id: row.callee_id,
    caller_name: row.caller_name || '',
    caller_avatar: row.caller_avatar || '',
    callee_name: row.callee_name || '',
    callee_avatar: row.callee_avatar || '',
    call_type: row.call_type || 'video',
    status: row.status || 'failed',
    room_id: row.room_id || row.channel_name || row.id,
    channel_name: row.channel_name || row.room_id || row.id,
    push_delivery_status: row.push_delivery_status || '',
    created_at: row.created_at || '',
    answered_at: row.answered_at || '',
    ended_at: row.ended_at || '',
    timeout_at: row.timeout_at || '',
  };
}

async function expireRingingCalls(db: D1Database) {
  const timestamp = now();
  await db.prepare(
    `UPDATE call_sessions
     SET status = 'missed', ended_at = ?, updated_at = ?
     WHERE status = 'ringing' AND timeout_at <= ?`
  ).bind(timestamp, timestamp, timestamp).run();
}

async function getVisibleCallForUser(db: D1Database, callId: string, userId: string) {
  await expireRingingCalls(db);
  return db.prepare('SELECT * FROM call_sessions WHERE id = ? AND (caller_id = ? OR callee_id = ?) LIMIT 1')
    .bind(publicId(callId, 120), userId, userId)
    .first();
}

async function hasActiveCallForUser(db: D1Database, userId: string): Promise<boolean> {
  await expireRingingCalls(db);
  const placeholders = ACTIVE_CALL_STATUSES.map(() => '?').join(', ');
  const activeCallSql = [
    'SELECT id FROM call_sessions',
    `WHERE (caller_id = ? OR callee_id = ?) AND status IN (${placeholders})`,
    'LIMIT 1',
  ].join(' ');
  const row: any = await db.prepare(activeCallSql).bind(userId, userId, ...ACTIVE_CALL_STATUSES).first();
  return !!row;
}

function getApnsConfig(c: any) {
  const teamId = String(c.env.APNS_TEAM_ID || '').trim();
  const keyId = String(c.env.APNS_KEY_ID || '').trim();
  const bundleId = String(c.env.APNS_BUNDLE_ID || '').trim();
  const privateKey = String(c.env.APNS_PRIVATE_KEY || c.env.APNS_VOIP_PRIVATE_KEY || '').replace(/\\n/g, '\n').trim();
  const environment = String(c.env.APNS_ENVIRONMENT || c.env.ENVIRONMENT || 'production').toLowerCase();
  if (!teamId || !keyId || !bundleId || !privateKey) return null;
  return { teamId, keyId, bundleId, privateKey, environment };
}

async function signApnsJwt(config: { teamId: string; keyId: string; privateKey: string }) {
  const { importPKCS8, SignJWT } = await import('jose');
  const key = await importPKCS8(config.privateKey, 'ES256');
  return new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: config.keyId })
    .setIssuer(config.teamId)
    .setIssuedAt()
    .sign(key);
}

async function sendVoipPushForCall(c: any, call: any): Promise<string> {
  const config = getApnsConfig(c);
  if (!config) return 'voip_not_configured';

  const tokens = await c.env.DB.prepare(
    `SELECT token, bundle_id, environment
     FROM voip_push_tokens
     WHERE user_id = ? AND is_active = 1
     ORDER BY last_seen_at DESC
     LIMIT 8`
  ).bind(call.callee_id).all();
  const rows = (tokens.results || []) as any[];
  if (!rows.length) return 'no_voip_tokens';

  const jwt = await signApnsJwt(config);
  const isSandbox = config.environment === 'development' || config.environment === 'sandbox';
  const baseURL = isSandbox ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
  const payloadCall = safeCallPayload(call) || {};
  const isRinging = String(call.status || 'ringing') === 'ringing';
  const payload = {
    aps: {
      alert: {
        title: isRinging ? 'Captro Video Call' : 'Captro Call Update',
        body: isRinging ? `${call.caller_name || 'Someone'} is calling you` : 'Call ended',
      },
      sound: 'default',
    },
    ...payloadCall,
  };

  let sent = 0;
  let failed = 0;
  for (const row of rows) {
    const token = String(row.token || '').trim();
    if (!token) continue;
    const topic = String(row.bundle_id || config.bundleId).trim() || config.bundleId;
    const response = await fetch(`${baseURL}/3/device/${token}`, {
      method: 'POST',
      headers: {
        authorization: `bearer ${jwt}`,
        'apns-topic': `${topic}.voip`,
        'apns-push-type': 'voip',
        'apns-priority': '10',
        'apns-expiration': '0',
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    if (response.ok) {
      sent += 1;
    } else {
      failed += 1;
      if (response.status === 400 || response.status === 410) {
        await c.env.DB.prepare('UPDATE voip_push_tokens SET is_active = 0 WHERE token = ?').bind(token).run();
      }
    }
  }

  if (sent > 0 && failed === 0) return `voip_sent:${sent}`;
  if (sent > 0) return `voip_partial:${sent}/${sent + failed}`;
  return 'voip_failed';
}

async function sendAlertPushForNotification(c: any, input: {
  userId: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
}): Promise<string> {
  const config = getApnsConfig(c);
  if (!config) return 'apns_not_configured';
  await ensureProductionReadinessSchema(c.env.DB);

  const tokens = await c.env.DB.prepare(
    `SELECT token, bundle_id, environment
     FROM push_tokens
     WHERE user_id = ? AND is_active = 1
     ORDER BY last_seen_at DESC
     LIMIT 8`
  ).bind(input.userId).all();
  const rows = (tokens.results || []) as any[];
  if (!rows.length) return 'no_push_tokens';

  const jwt = await signApnsJwt(config);
  let sent = 0;
  let failed = 0;
  for (const row of rows) {
    const token = String(row.token || '').trim();
    if (!token) continue;
    const rowEnvironment = String(row.environment || config.environment).toLowerCase();
    const isSandbox = rowEnvironment === 'development' || rowEnvironment === 'sandbox';
    const baseURL = isSandbox ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
    const topic = String(row.bundle_id || config.bundleId).trim() || config.bundleId;
    const response = await fetch(`${baseURL}/3/device/${token}`, {
      method: 'POST',
      headers: {
        authorization: `bearer ${jwt}`,
        'apns-topic': topic,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600),
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        aps: {
          alert: {
            title: cleanText(input.title, 120),
            body: cleanText(input.body, 180),
          },
          sound: 'default',
        },
        notification_type: cleanText(input.type, 60),
        data: safeNotificationData(input.data),
      }),
    });
    if (response.ok) {
      sent += 1;
    } else {
      failed += 1;
      if (response.status === 400 || response.status === 410) {
        await c.env.DB.prepare('UPDATE push_tokens SET is_active = 0, updated_at = ? WHERE token = ?')
          .bind(now(), token)
          .run();
      }
    }
  }

  if (sent > 0 && failed === 0) return `apns_sent:${sent}`;
  if (sent > 0) return `apns_partial:${sent}/${sent + failed}`;
  return 'apns_failed';
}

const MAPBOX_SEARCH_BOX_API_BASE = 'https://api.mapbox.com/search/searchbox/v1';
const MAPBOX_GEOCODING_API_BASE = 'https://api.mapbox.com/search/geocode/v6';

function uniq(values: string[]): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function parsePreferenceList(value: unknown): string[] {
  if (!value) return [];
  if (Array.isArray(value)) return uniq(value.map((item) => String(item).toLowerCase()));

  const text = String(value).trim();
  if (!text) return [];

  try {
    const parsed = JSON.parse(text);
    if (Array.isArray(parsed)) return uniq(parsed.map((item) => String(item).toLowerCase()));
  } catch {}

  return uniq(text.split(/[,|/]+/).map((item) => item.toLowerCase()));
}

function getMapboxAccessToken(c: any): string {
  const token = String(c.env.MAPBOX_ACCESS_TOKEN || '').trim();
  if (!token) throw new Error('MAPBOX_ACCESS_TOKEN_MISSING');
  return token;
}

function mapboxProximity(location: { lat?: string; lng?: string }): string {
  const lat = Number(location.lat);
  const lng = Number(location.lng);
  if (Number.isFinite(lat) && Number.isFinite(lng)) return `${lng},${lat}`;
  return '-74.006,40.7128';
}

function mapboxFeatureAddress(properties: any): string {
  return properties?.full_address || [properties?.address, properties?.place_formatted].filter(Boolean).join(', ') || properties?.place_formatted || properties?.name || 'Mapbox place';
}

function mapboxCoordinates(feature: any) {
  const properties = feature?.properties || {};
  const coordinates = properties?.coordinates || {};
  const geometry = Array.isArray(feature?.geometry?.coordinates) ? feature.geometry.coordinates : [];
  const lng = Number(coordinates.longitude ?? geometry[0]);
  const lat = Number(coordinates.latitude ?? geometry[1]);
  return {
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
  };
}

function mapboxFeatureToPlace(feature: any, fallbackId: string) {
  const properties = feature?.properties || {};
  const coords = mapboxCoordinates(feature);
  const address = mapboxFeatureAddress(properties);

  return {
    place_id: properties.mapbox_id || fallbackId,
    name: properties.name || properties.name_preferred || 'Mapbox place',
    vicinity: address,
    formatted_address: address,
    rating: null,
    user_ratings_total: null,
    open_now: null,
    lat: coords.lat,
    lng: coords.lng,
    types: properties.poi_category || properties.poi_category_ids || [],
    photo_url: null,
    mapbox_id: properties.mapbox_id || fallbackId,
    mapbox_url: coords.lat !== null && coords.lng !== null ? `https://www.mapbox.com/search?query=${encodeURIComponent(properties.name || address)}&center=${coords.lng},${coords.lat}` : '',
  };
}

function mapboxContextName(context: any, key: string): string {
  const value = context?.[key];
  if (!value) return '';
  if (typeof value === 'string') return cleanText(value, 80);
  return cleanText(value.name || value.text || value.name_preferred || '', 80);
}

function mapboxFeatureToBroadLocation(feature: any) {
  const properties = feature?.properties || {};
  const context = properties.context || {};
  const featureType = cleanText(properties.feature_type || properties.type || '', 40).toLowerCase();
  const name = cleanText(properties.name || properties.name_preferred || '', 80);
  const city = featureType === 'place' || featureType === 'locality'
    ? name
    : (mapboxContextName(context, 'place') || mapboxContextName(context, 'locality') || name);
  const region = mapboxContextName(context, 'region');
  const country = mapboxContextName(context, 'country');
  const label = normalizeDisplayLocationLabel(city, region, country, '');
  return {
    city,
    region,
    country,
    label,
    display_location_label: label,
    display_location_source: 'mapbox_reverse_geocode',
  };
}

async function ensurePhoneAuthSchema(db: D1Database) {
  const statements = [
    'ALTER TABLE users ADD COLUMN phone TEXT',
    'ALTER TABLE users ADD COLUMN phone_verified INTEGER DEFAULT 0',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL',
    `CREATE TABLE IF NOT EXISTS phone_login_codes (
      id TEXT PRIMARY KEY,
      phone TEXT NOT NULL,
      code_hash TEXT NOT NULL,
      attempts INTEGER DEFAULT 0,
      expires_at TEXT NOT NULL,
      consumed_at TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    )`,
    'CREATE INDEX IF NOT EXISTS idx_phone_login_codes_phone ON phone_login_codes(phone, created_at DESC)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  phoneAuthSchemaReady = true;
}

async function ensureCommentSchema(db: D1Database) {
  if (commentSchemaReady) return;

  const statements = [
    'ALTER TABLE comments ADD COLUMN parent_id TEXT',
    'ALTER TABLE comments ADD COLUMN likes_count INTEGER DEFAULT 0',
    'ALTER TABLE comments ADD COLUMN pinned_at TEXT',
    'ALTER TABLE comments ADD COLUMN hidden_at TEXT',
    'ALTER TABLE comments ADD COLUMN hidden_by_user_id TEXT',
    `CREATE TABLE IF NOT EXISTS comment_likes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      comment_id TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(user_id, comment_id)
    )`,
    'CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments(parent_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_comments_post_pinned ON comments(post_id, pinned_at DESC, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_comment_likes_comment ON comment_likes(comment_id)',
    'CREATE INDEX IF NOT EXISTS idx_comment_likes_user ON comment_likes(user_id)',
  ];

  for (const statement of statements) {
    try {
      await runSchemaStatement(db, statement);
    } catch (error: any) {
      if (!isIgnorableSchemaError(error, statement)) {
        throw error;
      }
    }
  }

  commentSchemaReady = true;
}

function createPhoneCode(): string {
  const values = new Uint32Array(1);
  crypto.getRandomValues(values);
  return (100000 + (values[0] % 900000)).toString();
}

function getTwilioVerifyConfig(c: any) {
  const accountSid = String(c.env.TWILIO_ACCOUNT_SID || '').trim();
  const authToken = String(c.env.TWILIO_AUTH_TOKEN || '').trim();
  const serviceSid = String(c.env.TWILIO_VERIFY_SERVICE_SID || c.env.TWILIO_SERVICE_SID || '').trim();
  if (!accountSid || !authToken || !serviceSid) return null;
  return { accountSid, authToken, serviceSid };
}

function parseRetryAfterSeconds(value: string | null): number | undefined {
  const raw = String(value || '').trim();
  if (!raw) return undefined;
  const seconds = Number(raw);
  if (Number.isFinite(seconds) && seconds > 0) return Math.min(Math.ceil(seconds), 300);

  const retryAt = Date.parse(raw);
  if (!Number.isNaN(retryAt)) {
    return Math.min(Math.max(1, Math.ceil((retryAt - Date.now()) / 1000)), 300);
  }
  return undefined;
}

function parseTwilioVerifyFailure(message: string) {
  const [, rawStatus, twilioCode, rawRetryAfter] = message.split(':');
  const status = Number(rawStatus);
  const retryAfter = Number(rawRetryAfter);
  return {
    status: Number.isFinite(status) ? status : 0,
    twilioCode: twilioCode && twilioCode !== 'unknown' ? twilioCode : '',
    retryAfter: Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter : undefined,
  };
}

function isTwilioVerifyRateLimited(failure: ReturnType<typeof parseTwilioVerifyFailure>) {
  return failure.status === 429 || failure.twilioCode === '60203' || failure.twilioCode === '20429';
}

function twilioVerifyStartErrorResponse(c: any, errorMessage: string) {
  const failure = parseTwilioVerifyFailure(errorMessage);
  if (isTwilioVerifyRateLimited(failure)) {
    return c.json({
      detail: 'A verification code was already sent. Enter that code or wait before requesting a new one.',
      code: 'PHONE_VERIFICATION_RATE_LIMITED',
      retry_after: failure.retryAfter || 60,
    }, 429);
  }

  if (failure.status === 400) {
    return c.json({
      detail: 'Twilio could not send a code to that phone number. Check the number and try again.',
      code: 'PHONE_VERIFY_SEND_REJECTED',
    }, 400);
  }

  if (failure.status === 401 || failure.status === 403 || failure.status === 404) {
    return c.json({
      detail: 'Phone verification provider is not configured correctly. Check the Twilio Verify Service SID and auth settings.',
      code: 'PHONE_PROVIDER_CONFIG',
    }, 502);
  }

  return c.json({
    detail: 'Could not send verification code. Check Twilio Verify settings.',
    code: 'PHONE_VERIFY_START_FAILED',
  }, 502);
}

async function startTwilioVerification(c: any, phone: string): Promise<boolean> {
  const config = getTwilioVerifyConfig(c);
  if (!config) return false;

  const body = new URLSearchParams({
    To: phone,
    Channel: 'sms',
  });

  let response: Response;
  try {
    response = await fetch(`https://verify.twilio.com/v2/Services/${encodeURIComponent(config.serviceSid)}/Verifications`, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${btoa(`${config.accountSid}:${config.authToken}`)}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
    });
  } catch {
    throw new Error('PHONE_VERIFY_START_FAILED:network');
  }

  if (!response.ok) {
    const data: any = await response.json().catch(() => ({}));
    const retryAfter = parseRetryAfterSeconds(response.headers.get('Retry-After'));
    throw new Error(`PHONE_VERIFY_START_FAILED:${response.status}:${data.code || 'unknown'}:${retryAfter || ''}`);
  }

  return true;
}

async function checkTwilioVerification(c: any, phone: string, code: string): Promise<boolean> {
  const config = getTwilioVerifyConfig(c);
  if (!config) return false;

  const body = new URLSearchParams({
    To: phone,
    Code: code,
  });

  let response: Response;
  try {
    response = await fetch(`https://verify.twilio.com/v2/Services/${encodeURIComponent(config.serviceSid)}/VerificationCheck`, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${btoa(`${config.accountSid}:${config.authToken}`)}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
    });
  } catch {
    throw new Error('PHONE_VERIFY_CHECK_FAILED:network');
  }

  if (!response.ok) {
    if (response.status >= 500) {
      const data: any = await response.json().catch(() => ({}));
      throw new Error(`PHONE_VERIFY_CHECK_FAILED:${response.status}:${data.code || 'unknown'}`);
    }
    return false;
  }

  const data: any = await response.json().catch(() => ({}));
  return data.valid === true || data.status === 'approved';
}

async function sendLegacyPhoneCode(c: any, phone: string, code: string): Promise<'legacy_sms' | 'development'> {
  const sid = c.env.TWILIO_ACCOUNT_SID;
  const token = c.env.TWILIO_AUTH_TOKEN;
  const from = c.env.TWILIO_FROM_PHONE;
  if (!sid || !token || !from) return 'development';

  const body = new URLSearchParams({
    To: phone,
    From: from,
    Body: `Your Flames-Up sign-in code is ${code}. It expires in 10 minutes.`,
  });

  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${btoa(`${sid}:${token}`)}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });

  if (!response.ok) {
    throw new Error('PHONE_SMS_FAILED');
  }

  return 'legacy_sms';
}

async function findOrCreatePhoneUser(c: any, phone: string, fullName?: string) {
  let user: any = await c.env.DB.prepare('SELECT * FROM users WHERE phone = ?').bind(phone).first();
  if (!user) {
    const id = uuid();
    const digits = phone.replace(/\D/g, '');
    const username = pendingUsernameForUser(id);
    const safeName = String(fullName || '').trim() || 'Flames User';
    const email = `${digits}@phone.flames-up.local`;
    const generatedPasswordHash = await hashPassword(`phone_${phone}_${uuid()}`);

    await c.env.DB.prepare(
      'INSERT INTO users (id, email, username, full_name, password_hash, phone, phone_verified) VALUES (?, ?, ?, ?, ?, ?, 1)'
    ).bind(id, email, username, safeName, generatedPasswordHash, phone).run();
    user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
    await recordAbuseSignals(c, id, 'phone_signup', { username, display_name: safeName });
  } else if (!user.phone_verified) {
    await c.env.DB.prepare('UPDATE users SET phone_verified = 1, updated_at = datetime(\'now\') WHERE id = ?').bind(user.id).run();
    user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(user.id).first();
  }

  return user;
}

function authUserPayload(user: any) {
  const onboardingRequired = usernameNeedsOnboarding(user);
  return {
    id: user.id,
    email: publicUserEmail(user.email),
    phone: user.phone,
    phone_verified: !!user.phone_verified,
    username: publicUsernameFor(user),
    username_required: onboardingRequired,
    onboarding_required: onboardingRequired,
    full_name: user.full_name,
    profile_image: user.profile_image,
    cover_image: user.cover_image,
    profile_background_image: user.profile_background_image || user.cover_image || '',
    bio: user.bio,
    city: user.city,
    age: user.age,
    looking_for: user.looking_for,
    interests: user.interests,
    social_website: user.social_website,
    social_tiktok: user.social_tiktok,
    social_instagram: user.social_instagram,
    followers_count: user.followers_count,
    following_count: user.following_count,
    posts_count: user.posts_count,
    is_admin: !!user.is_admin,
    is_creator: !!user.is_creator,
    is_publisher: !!user.is_publisher,
    is_verified: !!user.is_verified,
    is_private: !!user.is_private,
    is_premium: userHasActivePremium(user),
    premium_status: user.premium_status || '',
    premium_plan: user.premium_plan || '',
    premium_until: user.premium_until || '',
    language: normalizeLanguage(user.language),
  };
}

async function requirePhoneVerified(c: any, action = 'continue') {
  void c;
  void action;
  return null;
}

function ownerUsernames(c: any): string[] {
  return String(c.env.OWNER_USERNAMES || '')
    .split(',')
    .map((value) => value.replace(/^@/, '').trim().toLowerCase())
    .filter(Boolean);
}

function ownerEmails(c: any): string[] {
  return String(c.env.OWNER_EMAILS || '')
    .split(',')
    .map((value) => normalizeOptionalEmail(value))
    .filter(Boolean);
}

function isOwnerUsername(c: any, username: unknown): boolean {
  const clean = String(username || '').replace(/^@/, '').trim().toLowerCase();
  return !!clean && ownerUsernames(c).includes(clean);
}

function isOwnerEmail(c: any, email: unknown): boolean {
  const clean = normalizeOptionalEmail(email);
  return !!clean && ownerEmails(c).includes(clean);
}

async function requireOwnerOrAdmin(c: any): Promise<any> {
  const userId = getUserId(c);
  const user: any = await c.env.DB.prepare('SELECT id, email, username, full_name, is_admin FROM users WHERE id = ?')
    .bind(userId)
    .first();
  if (!user?.is_admin && !isOwnerUsername(c, user?.username) && !isOwnerEmail(c, user?.email)) {
    throw new Error('FORBIDDEN');
  }
  return user;
}

async function verifyGoogleIdToken(c: any, idToken: string) {
  const allowedAudiences = parseAudiences(c.env.GOOGLE_OAUTH_CLIENT_IDS, c.env.GOOGLE_OAUTH_CLIENT_ID);
  if (allowedAudiences.length === 0) {
    throw new Error('GOOGLE_OAUTH_NOT_CONFIGURED');
  }

  const response = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`);
  if (!response.ok) {
    throw new Error('GOOGLE_TOKEN_INVALID');
  }

  const data: any = await response.json();
  if (!allowedAudiences.includes(String(data.aud || ''))) {
    throw new Error('GOOGLE_AUDIENCE_INVALID');
  }

  const issuer = String(data.iss || '');
  if (!['accounts.google.com', 'https://accounts.google.com'].includes(issuer)) {
    throw new Error('GOOGLE_ISSUER_INVALID');
  }
  if (!data.sub || !data.email) {
    throw new Error('GOOGLE_PROFILE_INVALID');
  }
  if (String(data.email_verified) !== 'true') {
    throw new Error('GOOGLE_EMAIL_UNVERIFIED');
  }

  return {
    subject: String(data.sub),
    email: String(data.email).toLowerCase(),
    fullName: String(data.name || data.email.split('@')[0]),
    profileImage: data.picture ? String(data.picture) : '',
  };
}

async function verifyAppleIdToken(c: any, idToken: string) {
  const { createRemoteJWKSet, jwtVerify } = await import('jose');
  const jwks = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
  const verifyOptions: any = { issuer: 'https://appleid.apple.com' };
  const allowedAudiences = parseAudiences(c.env.APPLE_OAUTH_AUDIENCES, c.env.APPLE_OAUTH_AUDIENCE);
  if (allowedAudiences.length > 0) {
    verifyOptions.audience = allowedAudiences;
  }

  const { payload } = await jwtVerify(idToken, jwks, verifyOptions);
  if (!payload.sub) {
    throw new Error('APPLE_SUBJECT_MISSING');
  }

  const email = normalizeOptionalEmail(payload.email);
  const emailVerified = payload.email_verified === true || payload.email_verified === 'true' || !email;
  if (!emailVerified) {
    throw new Error('APPLE_EMAIL_UNVERIFIED');
  }

  return {
    subject: String(payload.sub),
    email,
    fullName: safeDisplayNameFromEmail(email),
    profileImage: '',
  };
}

async function findOrCreateOAuthUser(
  c: any,
  provider: 'google' | 'apple',
  subject: string,
  email: string,
  fullName: string,
  profileImage: string
) {
  const normalizedSubject = String(subject || '').trim();
  const providedEmail = normalizeOptionalEmail(email);
  const normalizedEmail = providedEmail || (provider === 'apple' ? internalOAuthEmail(provider, normalizedSubject) : '');
  const safeFullName = normalizeOptionalName(fullName);

  if (!normalizedSubject) {
    throw new Error('OAUTH_SUBJECT_REQUIRED');
  }

  let user: any = await c.env.DB.prepare(
    'SELECT * FROM users WHERE oauth_provider = ? AND oauth_subject = ?'
  ).bind(provider, normalizedSubject).first();

  if (user) {
    if (providedEmail && isInternalOAuthEmail(user.email)) {
      const emailOwner: any = await c.env.DB.prepare('SELECT id FROM users WHERE LOWER(email) = ? AND id != ?')
        .bind(providedEmail, user.id)
        .first();
      if (!emailOwner) {
        await c.env.DB.prepare('UPDATE users SET email = ?, updated_at = datetime(\'now\') WHERE id = ?')
          .bind(providedEmail, user.id)
          .run();
        user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(user.id).first();
      }
    }
    return user;
  }

  if (!normalizedEmail) {
    throw new Error('EMAIL_REQUIRED');
  }

  user = await c.env.DB.prepare('SELECT * FROM users WHERE LOWER(email) = ?').bind(normalizedEmail).first();
  if (user) {
    await c.env.DB.prepare(
      'UPDATE users SET oauth_provider = ?, oauth_subject = ?, full_name = CASE WHEN full_name = \'\' OR full_name IS NULL THEN ? ELSE full_name END, profile_image = CASE WHEN profile_image = \'\' OR profile_image IS NULL THEN ? ELSE profile_image END, updated_at = datetime(\'now\') WHERE id = ?'
    ).bind(provider, normalizedSubject, safeFullName || user.full_name || `${provider} user`, profileImage || '', user.id).run();
    const refreshed = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(user.id).first();
    return refreshed;
  }

  const id = uuid();
  const username = pendingUsernameForUser(id);
  const generatedPasswordHash = await hashPassword(`${provider}_${normalizedSubject}_${uuid()}`);
  const safeName = safeFullName || safeDisplayNameFromEmail(providedEmail) || (provider === 'apple' ? 'Apple User' : 'Google User');

  await c.env.DB.prepare(
    'INSERT INTO users (id, email, username, full_name, password_hash, profile_image, oauth_provider, oauth_subject) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
  ).bind(id, normalizedEmail, username, safeName, generatedPasswordHash, profileImage || '', provider, normalizedSubject).run();

  await recordAbuseSignals(c, id, `${provider}_signup`, { username, display_name: safeName });
  return c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
}

// ═══════════════════════════════════════════════════════════════════════════════
function getSupabaseUrl(c: any): string {
  const url = String(c.env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
  if (!url || !url.startsWith('https://')) throw new Error('SUPABASE_NOT_CONFIGURED');
  return url;
}

async function verifySupabaseAccessToken(c: any, accessToken: string) {
  const token = String(accessToken || '').trim();
  if (!token) throw new Error('SUPABASE_TOKEN_REQUIRED');
  const { createRemoteJWKSet, jwtVerify } = await import('jose');
  const supabaseUrl = getSupabaseUrl(c);
  const issuer = String(c.env.SUPABASE_JWT_ISSUER || `${supabaseUrl}/auth/v1`).replace(/\/+$/, '');
  const jwks = createRemoteJWKSet(new URL(`${supabaseUrl}/auth/v1/.well-known/jwks.json`));
  const { payload } = await jwtVerify(token, jwks, { issuer });
  if (!payload.sub) throw new Error('SUPABASE_SUBJECT_MISSING');
  return payload as any;
}

async function findOrCreateSupabaseUser(c: any, payload: any, extras: any = {}) {
  await ensureOAuthSchema(c.env.DB);
  await ensureSupabaseAuthSchema(c.env.DB);
  const supabaseUserId = String(payload.sub || '').trim();
  const email = normalizeOptionalEmail(payload.email || extras.email);
  const metadata = payload.user_metadata && typeof payload.user_metadata === 'object' ? payload.user_metadata : {};
  const safeFullName = normalizeOptionalName(extras.full_name || metadata.full_name || metadata.name || email.split('@')[0] || 'Flames User');
  const profileImage = cleanText(metadata.avatar_url || metadata.picture || extras.profile_image || '', 1000);

  if (!supabaseUserId) throw new Error('SUPABASE_SUBJECT_MISSING');

  let user: any = await c.env.DB.prepare('SELECT * FROM users WHERE supabase_user_id = ?').bind(supabaseUserId).first();
  if (user) return user;
  if (!email) throw new Error('EMAIL_REQUIRED');

  user = await c.env.DB.prepare('SELECT * FROM users WHERE LOWER(email) = ?').bind(email).first();
  if (user) {
    await c.env.DB.prepare(
      `UPDATE users SET
         supabase_user_id = ?,
         full_name = CASE WHEN full_name = '' OR full_name IS NULL THEN ? ELSE full_name END,
         profile_image = CASE WHEN profile_image = '' OR profile_image IS NULL THEN ? ELSE profile_image END,
         updated_at = datetime('now')
       WHERE id = ?`
    ).bind(supabaseUserId, safeFullName, profileImage, user.id).run();
    return c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(user.id).first();
  }

  const idOwner = await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(supabaseUserId).first();
  const id = idOwner ? uuid() : supabaseUserId;
  const username = pendingUsernameForUser(id);
  const generatedPasswordHash = await hashPassword(`supabase_${supabaseUserId}_${uuid()}`);

  await c.env.DB.prepare(
    'INSERT INTO users (id, email, username, full_name, password_hash, profile_image, supabase_user_id, oauth_provider, oauth_subject) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
  ).bind(id, email, username, safeFullName || username, generatedPasswordHash, profileImage, supabaseUserId, 'supabase', supabaseUserId).run();

  await recordAbuseSignals(c, id, 'supabase_signup', { username, display_name: safeFullName || username });
  return c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
}

async function resolveSupabaseSessionUser(c: any, token: string) {
  const supabasePayload = await verifySupabaseAccessToken(c, token);
  const user = await findOrCreateSupabaseUser(c, supabasePayload, {
    email: supabasePayload.email,
  });
  const userId = String(user?.id || '');
  if (!userId) throw new Error('USER_NOT_FOUND');

  return {
    userId,
    payload: {
      sub: userId,
      userId,
      auth_provider: 'supabase',
      supabase_sub: String(supabasePayload.sub || ''),
      exp: supabasePayload.exp,
    },
    user,
  };
}

function getSupabaseServiceRoleKey(c: any): string {
  const key = String(c.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
  if (!key) throw new Error('SUPABASE_SERVICE_ROLE_MISSING');
  return key;
}

async function updateSupabaseAuthUser(c: any, supabaseUserId: unknown, payload: { email?: string; password?: string }) {
  const id = String(supabaseUserId || '').trim();
  const body = Object.fromEntries(
    Object.entries(payload).filter(([, value]) => typeof value === 'string' && value.trim().length > 0)
  );
  if (!id || Object.keys(body).length === 0) return;

  const serviceRoleKey = getSupabaseServiceRoleKey(c);
  const response = await fetch(`${getSupabaseUrl(c)}/auth/v1/admin/users/${encodeURIComponent(id)}`, {
    method: 'PUT',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_AUTH_UPDATE_FAILED:${response.status}:${text.slice(0, 200)}`);
  }
}

function isUuidText(value: unknown): string | null {
  const text = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text) ? text : null;
}

function toPgTime(value: unknown): string | null {
  const text = String(value || '').trim();
  if (!text) return null;
  const parsed = new Date(text.replace(' ', 'T'));
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function parseJsonObject(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value as Record<string, unknown>;
  const text = String(value || '').trim();
  if (!text) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function legacyMediaPayload(row: any) {
  const images = parseJsonArray(row.images);
  const mediaTypes = parseJsonArray(row.media_types);
  const dimensions = parseJsonArray(row.media_dimensions);
  const urls = images.length ? images : row.image ? [row.image] : [];
  return urls.map((url: any, index: number) => ({
    url: String(url || ''),
    type: mediaTypes[index] || (String(url || '').startsWith('cfstream:') ? 'video' : 'image'),
    width: Number(dimensions[index]?.width || 0),
    height: Number(dimensions[index]?.height || 0),
    ratio: Number(dimensions[index]?.ratio || 0),
  })).filter((item) => item.url);
}

function legacyUserTransferPayload(row: any) {
  return {
    id: String(row.id || ''),
    supabase_user_id: isUuidText(row.supabase_user_id),
    email: cleanText(row.email, 320) || null,
    username: cleanText(row.username, 80) || null,
    full_name: cleanText(row.full_name, 160) || null,
    avatar_url: cleanText(row.profile_image, 1200) || null,
    cover_url: cleanText(row.cover_image, 1200) || null,
    bio: cleanText(row.bio, 800),
    city: cleanText(row.city, 160),
    is_private: Number(row.is_private || 0) === 1,
    is_verified: Number(row.is_verified || 0) === 1,
    counts: {
      followers_count: Number(row.followers_count || 0),
      following_count: Number(row.following_count || 0),
      posts_count: Number(row.posts_count || 0),
    },
    profile: {
      age: row.age ? String(row.age) : '',
      looking_for: parseJsonArray(row.looking_for),
      interests: parseJsonArray(row.interests),
      social_website: cleanText(row.social_website, 500),
      social_tiktok: cleanText(row.social_tiktok, 180),
      social_instagram: cleanText(row.social_instagram, 180),
      phone_verified: Number(row.phone_verified || 0) === 1,
      language: normalizeLanguage(row.language),
    },
    metadata: {
      source: 'cloudflare_d1_transfer',
      status: cleanText(row.status || 'active', 40),
      oauth_provider: cleanText(row.oauth_provider, 40),
      oauth_subject: cleanText(row.oauth_subject, 180),
    },
    legacy_created_at: toPgTime(row.created_at),
    legacy_updated_at: toPgTime(row.updated_at),
  };
}

function legacyPostTransferPayload(row: any) {
  const editorOverlays = parseJsonArray(row.editor_overlays);
  const primaryCategory = normalizeDiscoverCategory(row.primary_category || row.category || row.post_type || 'lifestyle', false) || 'lifestyle';
  return {
    legacy_post_id: String(row.id || ''),
    user_id: isUuidText(row.supabase_user_id),
    app_user_id: cleanText(row.user_id, 120) || null,
    title: cleanText(row.title, 180) || null,
    content: cleanText(row.content, 4000),
    visibility: normalizeVisibility(row.visibility),
    status: cleanText(row.status || 'active', 40) === 'removed' ? 'removed' : 'active',
    post_type: cleanText(row.post_type || row.category || 'general', 80),
    category: primaryCategory,
    location: cleanText(row.location || row.place_name, 180) || null,
    media: legacyMediaPayload(row),
    media_dimensions: parseJsonArray(row.media_dimensions),
    editor_data: {
      overlays: editorOverlays,
      filterData: editorOverlays.find((item: any) => item?.type === 'filter') || null,
      textOverlays: editorOverlays.filter((item: any) => item?.type === 'text'),
    },
    product_tags: [],
    tagged_users: parseJsonArray(row.tagged_users),
    metadata: {
      source: 'cloudflare_d1_transfer',
      image: cleanText(row.image, 1200),
      media_backup_ids: parseJsonArray(row.media_backup_ids),
      discover_category: {
        primary_category: primaryCategory,
        confidence: clampFloat(row.category_confidence, 0, 1, 0),
        source: normalizeCategorySource(row.category_source),
        status: normalizeCategoryStatus(row.category_status),
        tags: sanitizeAutoCategoryTags(row.tags_json),
      },
      place: {
        id: cleanText(row.place_id, 160),
        name: cleanText(row.place_name, 180),
        lat: row.place_lat ?? null,
        lng: row.place_lng ?? null,
        verified_checkin: Number(row.is_verified_checkin || 0) === 1,
      },
      audio: {
        provider: cleanText(row.audio_provider, 40),
        track_id: cleanText(row.audio_track_id, 120),
        title: cleanText(row.audio_title, 180),
        artist: cleanText(row.audio_artist, 180),
        artwork_url: cleanText(row.audio_artwork_url, 1200),
        stream_url: cleanText(row.audio_stream_url, 2200),
        start_time: Number(row.audio_start_time || 0),
        duration: Number(row.audio_duration || 0),
      },
      raw: parseJsonObject(row.metadata),
    },
    likes_count: Math.max(0, Number(row.likes_count || 0)),
    comments_count: Math.max(0, Number(row.comments_count || 0)),
    saves_count: Math.max(0, Number(row.saves_count || 0)),
    legacy_created_at: toPgTime(row.created_at),
    legacy_updated_at: toPgTime(row.updated_at),
  };
}

async function supabaseAdminUpsert(c: any, table: string, rows: any[], onConflict: string) {
  if (!rows.length) return { table, count: 0 };
  const url = `${getSupabaseUrl(c)}/rest/v1/${table}?on_conflict=${encodeURIComponent(onConflict)}`;
  const serviceRoleKey = getSupabaseServiceRoleKey(c);
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify(rows),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_UPSERT_FAILED:${table}:${response.status}:${text.slice(0, 500)}`);
  }
  return { table, count: rows.length };
}

async function supabaseAdminUpsertSafe(c: any, table: string, rows: any[], onConflict: string) {
  try {
    return await supabaseAdminUpsert(c, table, rows, onConflict);
  } catch (error: any) {
    const code = getErrorCode(error);
    if (!code.includes('SUPABASE_SERVICE_ROLE_MISSING') && !code.includes('SUPABASE_NOT_CONFIGURED')) {
      console.warn(JSON.stringify({ event: 'supabase_write_through_failed', table, code: code.slice(0, 180) }));
    }
    return { table, count: 0, skipped: true };
  }
}

function runBackgroundTask(c: any, label: string, task: () => Promise<void>) {
  const promise = task().catch((error: any) => {
    console.warn(JSON.stringify({ event: label, code: getErrorCode(error).slice(0, 180) }));
  });
  if (c.executionCtx?.waitUntil) {
    c.executionCtx.waitUntil(promise);
  } else {
    void promise;
  }
}

function workersAiLabelsFromResult(result: any): AutoCategoryLabel[] {
  const raw = Array.isArray(result)
    ? result
    : Array.isArray(result?.result)
      ? result.result
      : Array.isArray(result?.labels)
        ? result.labels
        : Array.isArray(result?.predictions)
          ? result.predictions
          : [];
  return sanitizeAutoCategoryLabels(raw.map((item: any) => ({
    label: item?.label || item?.class || item?.name,
    confidence: item?.score ?? item?.confidence ?? item?.probability,
    source: 'workers_ai',
  }))).slice(0, 12);
}

async function classifyImageWithWorkersAi(env: Env, imageUrl: string): Promise<AutoCategoryLabel[]> {
  if (!env.AI || !imageUrl || !/^https:\/\//i.test(imageUrl)) return [];
  const response = await fetch(imageUrl, {
    headers: { accept: 'image/*' },
  });
  if (!response.ok) return [];
  const contentLength = Number(response.headers.get('content-length') || 0);
  if (contentLength > 4_000_000) return [];
  const imageBytes = await response.arrayBuffer();
  if (!imageBytes.byteLength || imageBytes.byteLength > 4_000_000) return [];
  const result = await env.AI.run('@cf/microsoft/resnet-50', {
    image: Array.from(new Uint8Array(imageBytes)),
  });
  return workersAiLabelsFromResult(result);
}

async function refinePostCategoryWithBackendAi(c: any, postId: string) {
  if (!c.env.AI) return;
  await ensureAutoCategorySchema(c.env.DB);
  const row: any = await c.env.DB.prepare(
    `SELECT id, content, title, image, images, media_types, media_dimensions, location, place_name, post_type,
            primary_category, category_confidence, category_signals_json, tags_json
     FROM posts
     WHERE id = ?
     LIMIT 1`
  ).bind(postId).first();
  if (!row) return;

  const currentConfidence = clampFloat(row.category_confidence, 0, 1, 0);
  const mediaUrls = sanitizeMediaReferences(row.images, row.image);
  const mediaTypes = sanitizeMediaTypes(row.media_types, mediaUrls.length || 1);
  const primaryUrl = mediaUrls[0] || safeMediaReference(row.image);
  const primaryType = mediaTypes[0] || (isVideoMediaUrl(primaryUrl) ? 'video' : 'image');
  if (currentConfidence >= 0.75 && primaryType !== 'video') return;

  const thumbnailVariant = c.env.CLOUDFLARE_IMAGES_THUMBNAIL_VARIANT || '';
  const feedVariant = c.env.CLOUDFLARE_IMAGES_FEED_VARIANT || '';
  const mediaPreviewUrl = primaryType === 'video'
    ? streamThumbnailUrl(primaryUrl)
    : posterDeliveryUrl(primaryUrl, primaryType, thumbnailVariant) || feedDeliveryUrl(primaryUrl, primaryType, feedVariant);
  const backendLabels = await classifyImageWithWorkersAi(c.env, mediaPreviewUrl);
  if (!backendLabels.length) return;

  const backendCategory = categoryFromLabels(backendLabels);
  const currentSignals = parseJsonObject(row.category_signals_json);
  const result = autoCategoryEngine({
    caption: [row.title, row.content].filter(Boolean).join('\n\n'),
    mediaType: primaryType,
    postType: row.post_type,
    hashtags: sanitizeAutoCategoryTags(row.tags_json),
    location: row.location,
    placeName: row.place_name,
    appleLabels: sanitizeAutoCategoryLabels((currentSignals as any).apple_labels),
    appleCategoryGuess: cleanText((currentSignals as any).apple_category_guess, 40),
    appleConfidence: clampFloat((currentSignals as any).apple_confidence, 0, 1, 0),
    backendLabels,
    backendCategoryGuess: backendCategory.category,
    backendConfidence: backendCategory.confidence,
  });
  await c.env.DB.prepare(
    `UPDATE posts
     SET primary_category = ?, category_confidence = ?, category_source = ?, category_status = ?,
         category_signals_json = ?, tags_json = ?, updated_at = datetime('now')
     WHERE id = ?`
  ).bind(
    result.primary_category,
    result.category_confidence,
    result.category_source,
    result.category_status,
    JSON.stringify(result.signals),
    JSON.stringify(result.tags),
    postId
  ).run();
}

async function supabaseAdminDeleteSafe(c: any, table: string, filters: Record<string, string>) {
  try {
    const query = Object.entries(filters)
      .map(([key, value]) => `${encodeURIComponent(key)}=eq.${encodeURIComponent(value)}`)
      .join('&');
    const url = `${getSupabaseUrl(c)}/rest/v1/${table}?${query}`;
    const serviceRoleKey = getSupabaseServiceRoleKey(c);
    const response = await fetch(url, {
      method: 'DELETE',
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        Prefer: 'return=minimal',
      },
    });
    if (!response.ok) {
      const text = await response.text().catch(() => '');
      throw new Error(`SUPABASE_DELETE_FAILED:${table}:${response.status}:${text.slice(0, 500)}`);
    }
    return { table, deleted: true };
  } catch (error: any) {
    const code = getErrorCode(error);
    if (!code.includes('SUPABASE_SERVICE_ROLE_MISSING') && !code.includes('SUPABASE_NOT_CONFIGURED')) {
      console.warn(JSON.stringify({ event: 'supabase_delete_through_failed', table, code: code.slice(0, 180) }));
    }
    return { table, deleted: false, skipped: true };
  }
}

async function mirrorLegacyUserToSupabase(c: any, userId: string) {
  const row: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  if (!row) return;
  await supabaseAdminUpsertSafe(c, 'app_users', [legacyUserTransferPayload(row)], 'id');
}

async function mirrorLegacyPostToSupabase(c: any, postId: string) {
  const row: any = await c.env.DB.prepare(`
    SELECT p.*, u.supabase_user_id
    FROM posts p
    LEFT JOIN users u ON u.id = p.user_id
    WHERE p.id = ?
    LIMIT 1
  `).bind(postId).first();
  if (!row) return;
  await supabaseAdminUpsertSafe(c, 'app_posts', [legacyPostTransferPayload(row)], 'legacy_post_id');
}

async function mirrorLegacyCommentToSupabase(c: any, commentId: string) {
  const row: any = await c.env.DB.prepare(`
    SELECT cm.*, u.supabase_user_id
    FROM comments cm
    LEFT JOIN users u ON u.id = cm.user_id
    WHERE cm.id = ?
    LIMIT 1
  `).bind(commentId).first();
  if (!row) return;
  const payload = {
    legacy_comment_id: cleanText(row.id, 120),
    legacy_post_id: cleanText(row.post_id, 120),
    app_user_id: cleanText(row.user_id, 120) || null,
    user_id: isUuidText(row.supabase_user_id),
    body: cleanText(row.content || row.body, 1200) || ' ',
    status: cleanText(row.status || 'active', 40) === 'removed' ? 'removed' : 'active',
    metadata: {
      source: 'cloudflare_d1_write_through',
      parent_id: cleanText(row.parent_id, 120),
      likes_count: Number(row.likes_count || 0),
    },
    legacy_created_at: toPgTime(row.created_at),
  };
  await supabaseAdminUpsertSafe(c, 'post_comments', [payload], 'legacy_comment_id');
}

async function mirrorLegacyInteractionToSupabase(
  c: any,
  postId: string,
  userId: string,
  kind: 'like' | 'save' | 'repost',
  active: boolean,
  collection = ''
) {
  if (!active) {
    await supabaseAdminDeleteSafe(c, 'app_post_interactions', {
      legacy_post_id: postId,
      app_user_id: userId,
      kind,
    });
    return;
  }
  await supabaseAdminUpsertSafe(c, 'app_post_interactions', [{
    legacy_post_id: cleanText(postId, 120),
    app_user_id: cleanText(userId, 120),
    kind,
    collection: cleanText(collection, 120) || null,
    metadata: { source: 'cloudflare_d1_write_through' },
    legacy_created_at: now(),
  }], 'legacy_post_id,app_user_id,kind');
}

async function mirrorLegacyFollowToSupabase(c: any, followerId: string, followingId: string, active: boolean) {
  if (!active) {
    await supabaseAdminDeleteSafe(c, 'app_follows', {
      app_follower_id: followerId,
      app_following_id: followingId,
    });
    return;
  }
  await supabaseAdminUpsertSafe(c, 'app_follows', [{
    app_follower_id: cleanText(followerId, 120),
    app_following_id: cleanText(followingId, 120),
    metadata: { source: 'cloudflare_d1_write_through' },
    legacy_created_at: now(),
  }], 'app_follower_id,app_following_id');
}

async function transferLegacyUsersToSupabase(c: any, limit: number, offset: number) {
  const rows = await c.env.DB.prepare('SELECT * FROM users ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
  const payload = (rows.results as any[]).map(legacyUserTransferPayload).filter((row) => row.id);
  return supabaseAdminUpsert(c, 'app_users', payload, 'id');
}

async function transferLegacyPostsToSupabase(c: any, limit: number, offset: number) {
  const rows = await c.env.DB.prepare(`
    SELECT p.*, u.supabase_user_id
    FROM posts p
    LEFT JOIN users u ON u.id = p.user_id
    ORDER BY p.created_at
    LIMIT ? OFFSET ?
  `).bind(limit, offset).all();
  const payload = (rows.results as any[]).map(legacyPostTransferPayload).filter((row) => row.legacy_post_id);
  return supabaseAdminUpsert(c, 'app_posts', payload, 'legacy_post_id');
}

async function transferLegacyCommentsToSupabase(c: any, limit: number, offset: number) {
  const rows = await c.env.DB.prepare(`
    SELECT c.*, u.supabase_user_id
    FROM comments c
    LEFT JOIN users u ON u.id = c.user_id
    ORDER BY c.created_at
    LIMIT ? OFFSET ?
  `).bind(limit, offset).all();
  const payload = (rows.results as any[]).map((row: any) => ({
    legacy_comment_id: cleanText(row.id, 120),
    legacy_post_id: cleanText(row.post_id, 120),
    app_user_id: cleanText(row.user_id, 120) || null,
    user_id: isUuidText(row.supabase_user_id),
    body: cleanText(row.content || row.body, 1200) || ' ',
    status: cleanText(row.status || 'active', 40) === 'removed' ? 'removed' : 'active',
    metadata: {
      source: 'cloudflare_d1_transfer',
      parent_id: cleanText(row.parent_id, 120),
      likes_count: Number(row.likes_count || 0),
    },
    legacy_created_at: toPgTime(row.created_at),
  })).filter((row: any) => row.legacy_comment_id && row.legacy_post_id);
  return supabaseAdminUpsert(c, 'post_comments', payload, 'legacy_comment_id');
}

async function transferLegacyInteractionsToSupabase(c: any, limit: number, offset: number) {
  const likes = await c.env.DB.prepare('SELECT user_id, post_id, created_at FROM likes ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
  const saves = await c.env.DB.prepare('SELECT user_id, post_id, collection, created_at FROM saved_posts ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
  const rows = [
    ...(likes.results as any[]).map((row) => ({ ...row, kind: 'like' })),
    ...(saves.results as any[]).map((row) => ({ ...row, kind: 'save' })),
  ];
  const payload = rows.map((row: any) => ({
    legacy_post_id: cleanText(row.post_id, 120),
    app_user_id: cleanText(row.user_id, 120),
    kind: row.kind,
    collection: cleanText(row.collection, 120) || null,
    metadata: { source: 'cloudflare_d1_transfer' },
    legacy_created_at: toPgTime(row.created_at),
  })).filter((row) => row.legacy_post_id && row.app_user_id);
  return supabaseAdminUpsert(c, 'app_post_interactions', payload, 'legacy_post_id,app_user_id,kind');
}

async function transferLegacyFollowsToSupabase(c: any, limit: number, offset: number) {
  const rows = await c.env.DB.prepare('SELECT follower_id, following_id, created_at FROM follows ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
  const payload = (rows.results as any[]).map((row: any) => ({
    app_follower_id: cleanText(row.follower_id, 120),
    app_following_id: cleanText(row.following_id, 120),
    metadata: { source: 'cloudflare_d1_transfer' },
    legacy_created_at: toPgTime(row.created_at),
  })).filter((row) => row.app_follower_id && row.app_following_id);
  return supabaseAdminUpsert(c, 'app_follows', payload, 'app_follower_id,app_following_id');
}

// AUTH
// ═══════════════════════════════════════════════════════════════════════════════
api.post('/auth/supabase', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 140_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'auth_supabase', clientIp(c), 60, 300);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const payload = await verifySupabaseAccessToken(c, body.access_token || body.token);
    const user = await findOrCreateSupabaseUser(c, payload, body);
    const token = await createToken(user.id, getJwtSecret(c));
    runBackgroundTask(c, 'supabase_login_profile_write_through_failed', async () => {
      await mirrorLegacyUserToSupabase(c, user.id);
    });
    return c.json({ access_token: token, token_type: 'bearer', user: authUserPayload(user) });
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'SUPABASE_NOT_CONFIGURED') return c.json({ detail: 'Supabase auth is not configured on the backend.' }, 503);
    if (code === 'SUPABASE_TOKEN_REQUIRED') return c.json({ detail: 'Supabase access token is required.' }, 400);
    if (code === 'EMAIL_REQUIRED') return c.json({ detail: 'Supabase account email is required.' }, 400);
    if (code === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    if (code.startsWith('ERR_JWS_') || code.startsWith('ERR_JWT_') || code.startsWith('ERR_JWKS_')) {
      return c.json({ detail: 'Invalid Supabase session.' }, 401);
    }
    console.error('Supabase auth bridge failed:', code, error?.message || error);
    return c.json({ detail: 'Could not finish Supabase sign in.' }, 500);
  }
});

api.post('/auth/register', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 80_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'auth_register', clientIp(c), 8, 300);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'auth_register_daily', clientIp(c), 20, 86400);
    if (dailyLimited) return dailyLimited;
    const jwtSecret = getJwtSecret(c);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['email', 'password', 'username', 'full_name', 'fullName']);
    if (unknown) return unknown;
    const email = normalizeOptionalEmail(body.email);
    const password = String(body.password || '');
    const username = normalizeOptionalName(body.username);
    const fullName = normalizeOptionalName(body.full_name || body.fullName);
    if (!email || !password || !username || !fullName)
      return c.json({ detail: 'All fields required' }, 400);
    if (password.length < 8 || password.length > 200) {
      return c.json({ detail: 'Password must be between 8 and 200 characters.' }, 400);
    }
    const usernameCheck = validateUsernameForAccount(username);
    if (!usernameCheck.ok) return c.json({ detail: usernameCheck.detail }, 400);
    const safeUsername = usernameCheck.username;
    const existing = await c.env.DB.prepare('SELECT id FROM users WHERE LOWER(email) = ? OR LOWER(username) = ?')
      .bind(email, safeUsername.toLowerCase()).first();
    if (existing) {
      await logSecurityEvent(c, 'signup_duplicate_blocked', '', { username: safeUsername });
      return c.json({ detail: 'Email or username already exists' }, 400);
    }
    const id = uuid();
    const hash = await hashPassword(password);
    await c.env.DB.prepare(
      'INSERT INTO users (id, email, username, full_name, password_hash) VALUES (?, ?, ?, ?, ?)'
    ).bind(id, email, safeUsername, fullName, hash).run();
    // Security-sensitive: store only hashed abuse signals for admin review of possible ban evasion.
    await recordAbuseSignals(c, id, 'signup', { username: safeUsername, display_name: fullName });
    await logSecurityEvent(c, 'signup_created', id, { username: safeUsername });
    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
    const token = await createToken(id, jwtSecret);
    return c.json({ access_token: token, token_type: 'bearer', user: authUserPayload(user) });
  } catch (error: any) {
    if (getErrorCode(error) === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    return c.json({ detail: 'Could not create account.' }, 500);
  }
});

api.post('/auth/login', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 60_000);
    if (bodyTooLarge) return bodyTooLarge;
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['email', 'password']);
    if (unknown) return unknown;
    const email = normalizeOptionalEmail(body.email);
    const password = String(body.password || '');
    if (!email || !password) return c.json({ detail: 'Invalid email or password.' }, 401);
    const limited = await enforceRateLimit(c, 'auth_login', `${clientIp(c)}:${email}`, 20, 300);
    if (limited) return limited;
    const ipLimited = await enforceRateLimit(c, 'auth_login_ip', clientIp(c), 80, 300);
    if (ipLimited) return ipLimited;

    const jwtSecret = getJwtSecret(c);
    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).first();
    if (!user || !(await verifyPassword(password, user.password_hash))) {
      if (user?.id) await recordAbuseSignals(c, user.id, 'failed_login', {});
      await logSecurityEvent(c, 'login_failed', user?.id || '', { reason: user ? 'password' : 'credentials' });
      return c.json({ detail: 'Invalid email or password.' }, 401);
    }
    if (['banned', 'suspended', 'deleted'].includes(String(user.status || 'active'))) {
      await recordAbuseSignals(c, user.id, 'banned_login', {});
      await logSecurityEvent(c, 'login_banned_blocked', user.id, {});
      return c.json({ detail: 'This account cannot be used.' }, 403);
    }
    // Auto-migrate legacy SHA-256 hash to bcrypt on successful login
    if (user.password_hash && !user.password_hash.startsWith('$2')) {
      try {
        const bcryptHash = await hashPassword(password);
        await c.env.DB.prepare('UPDATE users SET password_hash = ? WHERE id = ?').bind(bcryptHash, user.id).run();
      } catch {}
    }
    const token = await createToken(user.id, jwtSecret);
    return c.json({ access_token: token, token_type: 'bearer', user: authUserPayload(user) });
  } catch (error: any) {
    if (getErrorCode(error) === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    return c.json({ detail: 'Could not log in' }, 500);
  }
});

api.post('/auth/phone/start', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 40_000);
    if (bodyTooLarge) return bodyTooLarge;
    const body: any = await c.req.json().catch(() => ({}));
    const normalizedPhone = normalizePhone(body.phone);
    if (!normalizedPhone) return c.json({ detail: 'Enter a valid phone number with country code.' }, 400);
    const limited = await enforceRateLimit(c, 'phone_start', `${clientIp(c)}:${normalizedPhone}`, 5, 600);
    if (limited) return limited;
    await ensurePhoneAuthSchema(c.env.DB);

    const startedWithVerify = await startTwilioVerification(c, normalizedPhone);
    if (startedWithVerify) {
      return c.json({
        detail: 'We sent a sign-in code to your phone.',
        delivery: 'twilio_verify',
      });
    }

    const code = createPhoneCode();
    const jwtSecret = getJwtSecret(c);
    const codeHash = await sha256Hex(`${normalizedPhone}:${code}:${jwtSecret}`);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    await c.env.DB.prepare(
      'INSERT INTO phone_login_codes (id, phone, code_hash, expires_at) VALUES (?, ?, ?, ?)'
    ).bind(uuid(), normalizedPhone, codeHash, expiresAt).run();

    const delivery = await sendLegacyPhoneCode(c, normalizedPhone, code);
    const payload: any = {
      detail: delivery === 'legacy_sms'
        ? 'We sent a sign-in code to your phone.'
        : 'Twilio Verify is not configured yet, so use the development code shown here.',
      delivery,
    };

    if (delivery === 'development') {
      payload.dev_code = code;
    }

    return c.json(payload);
  } catch (error: any) {
    const code = String(error?.message || '');
    if (code === 'PHONE_INVALID') return c.json({ detail: 'Enter a valid phone number with country code.' }, 400);
    if (code === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    if (code.startsWith('PHONE_VERIFY_START_FAILED')) return twilioVerifyStartErrorResponse(c, code);
    if (code === 'PHONE_SMS_FAILED') return c.json({ detail: 'Could not send SMS code. Check Twilio settings.' }, 502);
    console.error(JSON.stringify({ event: 'phone_login_start_failed', error: code.slice(0, 180) }));
    return c.json({ detail: 'Could not start phone sign in. Please try again in a moment.', code: 'PHONE_START_FAILED' }, 500);
  }
});

api.post('/auth/phone/verify', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 40_000);
    if (bodyTooLarge) return bodyTooLarge;
    const body: any = await c.req.json().catch(() => ({}));
    const normalizedPhone = normalizePhone(body.phone);
    if (!normalizedPhone) return c.json({ detail: 'Enter a valid phone number with country code.' }, 400);
    const limited = await enforceRateLimit(c, 'phone_verify', `${clientIp(c)}:${normalizedPhone}`, 12, 600);
    if (limited) return limited;
    const code = body.code;
    const normalizedCode = String(code || '').replace(/\D/g, '');
    if (normalizedCode.length !== 6) {
      return c.json({ detail: 'Enter the 6-digit verification code.' }, 400);
    }
    await ensurePhoneAuthSchema(c.env.DB);

    if (getTwilioVerifyConfig(c)) {
      const verified = await checkTwilioVerification(c, normalizedPhone, normalizedCode);
      if (!verified) {
        return c.json({ detail: 'Invalid or expired verification code.' }, 401);
      }

      const user = await findOrCreatePhoneUser(c, normalizedPhone, body.full_name);
      const token = await createToken(user.id, getJwtSecret(c));
      return c.json({ access_token: token, token_type: 'bearer', user: authUserPayload(user) });
    }

    const phoneCode: any = await c.env.DB.prepare(
      'SELECT * FROM phone_login_codes WHERE phone = ? AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1'
    ).bind(normalizedPhone).first();

    if (!phoneCode) return c.json({ detail: 'No active code for this phone number.' }, 401);
    if ((phoneCode.attempts || 0) >= 5) return c.json({ detail: 'Too many attempts. Request a new code.' }, 429);
    if (Date.parse(phoneCode.expires_at) < Date.now()) return c.json({ detail: 'Code expired. Request a new code.' }, 401);

    const jwtSecret = getJwtSecret(c);
    const expectedHash = await sha256Hex(`${normalizedPhone}:${normalizedCode}:${jwtSecret}`);
    if (expectedHash !== phoneCode.code_hash) {
      await c.env.DB.prepare('UPDATE phone_login_codes SET attempts = attempts + 1 WHERE id = ?').bind(phoneCode.id).run();
      return c.json({ detail: 'Invalid verification code.' }, 401);
    }

    await c.env.DB.prepare('UPDATE phone_login_codes SET consumed_at = datetime(\'now\') WHERE id = ?').bind(phoneCode.id).run();

    const user = await findOrCreatePhoneUser(c, normalizedPhone, body.full_name);

    const token = await createToken(user.id, jwtSecret);
    return c.json({ access_token: token, token_type: 'bearer', user: authUserPayload(user) });
  } catch (error: any) {
    const code = String(error?.message || '');
    if (code === 'PHONE_INVALID') return c.json({ detail: 'Enter a valid phone number with country code.' }, 400);
    if (code === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    if (code.startsWith('PHONE_VERIFY_CHECK_FAILED')) return c.json({ detail: 'Could not check verification code. Try again.', code }, 502);
    return c.json({ detail: 'Could not verify phone sign in.' }, 500);
  }
});

api.get('/auth/oauth/config', async (c) => {
  const googleAudiences = parseAudiences(c.env.GOOGLE_OAUTH_CLIENT_IDS, c.env.GOOGLE_OAUTH_CLIENT_ID);
  const appleAudiences = parseAudiences(c.env.APPLE_OAUTH_AUDIENCES, c.env.APPLE_OAUTH_AUDIENCE);
  return c.json({
    google: {
      backend_configured: googleAudiences.length > 0,
      required_secret: 'GOOGLE_OAUTH_CLIENT_IDS',
    },
    apple: {
      audience_configured: appleAudiences.length > 0,
      required_secret: 'APPLE_OAUTH_AUDIENCES',
    },
  });
});

api.post('/auth/oauth/google', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 120_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'oauth_google', clientIp(c), 30, 300);
    if (limited) return limited;
    await ensureOAuthSchema(c.env.DB);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['id_token', 'idToken']);
    if (unknown) return unknown;
    const id_token = String(body.id_token || body.idToken || '');
    if (!id_token) return c.json({ detail: 'id_token is required' }, 400);

    const googleProfile = await verifyGoogleIdToken(c, id_token);
    const user = await findOrCreateOAuthUser(
      c,
      'google',
      googleProfile.subject,
      googleProfile.email,
      googleProfile.fullName,
      googleProfile.profileImage
    );
    const token = await createToken(user.id, getJwtSecret(c));
    return c.json({ access_token: token, token_type: 'bearer', user: authUserPayload(user) });
  } catch (error: any) {
    const code = String(error?.message || '');
    if (code === 'GOOGLE_OAUTH_NOT_CONFIGURED') {
      return c.json({ detail: 'Google sign in is not configured on the backend. Set GOOGLE_OAUTH_CLIENT_IDS in Cloudflare to your Google OAuth client ID.' }, 503);
    }
    if (code === 'GOOGLE_AUDIENCE_INVALID') return c.json({ detail: 'Google client audience mismatch' }, 401);
    if (code === 'GOOGLE_EMAIL_UNVERIFIED') return c.json({ detail: 'Google account email is not verified' }, 401);
    if (code.startsWith('GOOGLE_')) return c.json({ detail: 'Invalid Google token' }, 401);
    if (code === 'EMAIL_REQUIRED') return c.json({ detail: 'Google account email is required' }, 400);
    if (code === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    return c.json({ detail: 'Google OAuth login failed' }, 401);
  }
});

api.post('/auth/oauth/apple', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 120_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'oauth_apple', clientIp(c), 30, 300);
    if (limited) return limited;
    await ensureOAuthSchema(c.env.DB);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['id_token', 'idToken', 'email', 'full_name', 'fullName', 'apple_user', 'appleUser']);
    if (unknown) return unknown;
    const idToken = String(body.id_token || body.idToken || '');
    if (!idToken) return c.json({ detail: 'id_token is required' }, 400);

    const appleProfile = await verifyAppleIdToken(c, idToken);
    const clientEmail = normalizeOptionalEmail(body.email);
    const clientFullName = normalizeOptionalName(body.full_name || body.fullName);
    const appleSubject = String(appleProfile.subject || body.apple_user || body.appleUser || '').trim();
    const user = await findOrCreateOAuthUser(
      c,
      'apple',
      appleSubject,
      appleProfile.email || clientEmail,
      clientFullName || appleProfile.fullName || 'Apple User',
      appleProfile.profileImage
    );
    const token = await createToken(user.id, getJwtSecret(c));
    return c.json({ access_token: token, token_type: 'bearer', user: authUserPayload(user) });
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'EMAIL_REQUIRED') return c.json({ detail: 'Apple account email is required on first sign-in' }, 400);
    if (code === 'OAUTH_SUBJECT_REQUIRED') return c.json({ detail: 'Apple account identifier was missing' }, 400);
    if (code === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    if (code === 'ERR_JWT_CLAIM_VALIDATION_FAILED' && error?.claim === 'aud') return c.json({ detail: 'Apple audience mismatch' }, 401);
    if (code === 'ERR_JWT_CLAIM_VALIDATION_FAILED') return c.json({ detail: 'Invalid Apple token claims' }, 401);
    if (code === 'ERR_JWS_SIGNATURE_VERIFICATION_FAILED') return c.json({ detail: 'Invalid Apple token signature' }, 401);
    if (code === 'ERR_JWT_EXPIRED') return c.json({ detail: 'Apple token expired. Please try again.' }, 401);
    if (code.startsWith('ERR_JWS_') || code.startsWith('ERR_JWT_') || code.startsWith('ERR_JWKS_')) {
      return c.json({ detail: 'Invalid Apple token' }, 401);
    }
    if (code.startsWith('APPLE_')) return c.json({ detail: 'Invalid Apple token' }, 401);
    return c.json({ detail: 'Apple OAuth login failed' }, 401);
  }
});

api.get('/auth/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await ensurePremiumSchema(c.env.DB);
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  if (!user) return c.json({ detail: 'User not found' }, 404);
  return c.json(authUserPayload(user));
});

// ═══════════════════════════════════════════════════════════════════════════════
// USERS
// ═══════════════════════════════════════════════════════════════════════════════
api.put('/users/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const bodyTooLarge = rejectLargeRequest(c, 200_000);
  if (bodyTooLarge) return bodyTooLarge;
  const limited = await enforceRateLimit(c, 'account_update', userId, 60, 60);
  if (limited) return limited;
  await ensurePremiumSchema(c.env.DB);
  const body = await c.req.json();
  const unknown = rejectUnknownFields(c, body, ['full_name', 'fullName', 'bio', 'profile_image', 'profileImage', 'cover_image', 'coverImage', 'profile_background_image', 'profileBackgroundImage', 'city', 'username', 'age', 'looking_for', 'lookingFor', 'interests', 'social_website', 'socialWebsite', 'social_tiktok', 'socialTiktok', 'social_instagram', 'socialInstagram', 'is_private', 'isPrivate', 'language']);
  if (unknown) return unknown;
  if (body.fullName !== undefined && body.full_name === undefined) body.full_name = body.fullName;
  if (body.profileImage !== undefined && body.profile_image === undefined) body.profile_image = body.profileImage;
  if (body.coverImage !== undefined && body.cover_image === undefined) body.cover_image = body.coverImage;
  if (body.profileBackgroundImage !== undefined && body.profile_background_image === undefined) body.profile_background_image = body.profileBackgroundImage;
  if (body.lookingFor !== undefined && body.looking_for === undefined) body.looking_for = body.lookingFor;
  if (body.socialWebsite !== undefined && body.social_website === undefined) body.social_website = body.socialWebsite;
  if (body.socialTiktok !== undefined && body.social_tiktok === undefined) body.social_tiktok = body.socialTiktok;
  if (body.socialInstagram !== undefined && body.social_instagram === undefined) body.social_instagram = body.socialInstagram;
  if (body.isPrivate !== undefined && body.is_private === undefined) body.is_private = body.isPrivate;
  const currentUser: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  const wantsCustomBackground = body.profile_background_image !== undefined || body.cover_image !== undefined;
  if (wantsCustomBackground && !userHasActivePremium(currentUser)) {
    return c.json({ detail: 'Custom profile background is a Premium feature.', code: 'PREMIUM_REQUIRED' }, 403);
  }
  const fields = ['full_name', 'bio', 'profile_image', 'cover_image', 'profile_background_image', 'city', 'username', 'age', 'looking_for', 'interests', 'social_website', 'social_tiktok', 'social_instagram', 'is_private', 'language'];
  const updates: string[] = []; const values: any[] = [];
  for (const f of fields) {
    if (body[f] !== undefined) {
      updates.push(`${f} = ?`);
      if (f === 'is_private') values.push(normalizeSqlBoolean(body[f]));
      else if (f === 'language') values.push(normalizeLanguage(body[f]));
      else if (f === 'profile_image' || f === 'cover_image' || f === 'profile_background_image') values.push(safeMediaReference(body[f]));
      else if (f === 'social_website') values.push(safeExternalUrl(body[f]));
      else if (f === 'bio') values.push(cleanMultilineText(body[f], 500));
      else if (f === 'age') values.push(clampNumber(body[f], 13, 120, 0));
      else if (f === 'username') {
        const usernameCheck = validateUsernameForAccount(body[f]);
        if (!usernameCheck.ok) return c.json({ detail: usernameCheck.detail }, 400);
        const existing: any = await c.env.DB.prepare('SELECT id FROM users WHERE LOWER(username) = ? AND id != ?')
          .bind(usernameCheck.username.toLowerCase(), userId)
          .first();
        if (existing) return c.json({ detail: 'Username is not available.' }, 409);
        values.push(usernameCheck.username);
      }
      else values.push(cleanText(body[f], 240));
    }
  }
  if (updates.length === 0) return c.json({ detail: 'Nothing to update' }, 400);
  values.push(userId);
  const updateUserSql = `UPDATE users SET ${updates.join(', ')}, updated_at = datetime('now') WHERE id = ?`;
  await c.env.DB.prepare(updateUserSql).bind(...values).run();
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  if (body.username !== undefined && strictUsernameSlug(currentUser?.username) !== strictUsernameSlug(user?.username)) {
    await logSecurityEvent(c, 'username_changed', userId, { previous_username: currentUser?.username || '', new_username: user?.username || '' });
  }
  await recordAbuseSignals(c, userId, 'profile_update', {
    username: user.username,
    display_name: user.full_name,
    bio: user.bio,
    links: [user.social_website, user.social_tiktok, user.social_instagram].filter(Boolean),
  });
  return c.json(safeUserPayload(user, { includePrivate: true }));
});

api.delete('/users/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'account_delete', userId, 3, 86400);
  if (limited) return limited;
  await ensureGovernanceSchema(c.env.DB);
  await ensurePremiumSchema(c.env.DB);
  const user: any = await c.env.DB.prepare('SELECT id, is_admin FROM users WHERE id = ?').bind(userId).first();
  if (!user) return c.json({ detail: 'User not found.' }, 404);
  if (user.is_admin) return c.json({ detail: 'Admin accounts must be removed by another admin.' }, 403);

  const ts = now();
  // Security-sensitive: soft-delete the account so moderation/audit records remain intact and unrelated data is not cascaded away.
  await c.env.DB.prepare(
    `UPDATE users SET
       status = 'deleted',
       email = ?,
       username = ?,
       full_name = 'Deleted user',
       bio = '',
       profile_image = '',
       cover_image = '',
       profile_background_image = '',
       social_website = '',
       social_tiktok = '',
       social_instagram = '',
       updated_at = datetime('now')
     WHERE id = ?`
  ).bind(`deleted_${userId}@deleted.flames-up.local`, `deleted_${userId.slice(0, 12)}`, userId).run();
  await c.env.DB.prepare("UPDATE posts SET status = 'removed', removed_at = ?, removed_reason = 'Account deleted' WHERE user_id = ? AND COALESCE(status, 'active') != 'removed'")
    .bind(ts, userId).run();
  await logSecurityEvent(c, 'account_soft_deleted', userId, {});
  return c.json({ deleted: true, soft_deleted: true });
});

api.put('/users/me/email', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const bodyTooLarge = rejectLargeRequest(c, 60_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'account_email', userId, 10, 600);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const email = normalizeOptionalEmail(body.email || body.new_email);

    if (!email) return c.json({ detail: 'Enter a valid email address.' }, 400);

    const currentUser: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
    if (!currentUser) return c.json({ detail: 'User not found' }, 404);

    const owner: any = await c.env.DB.prepare('SELECT id FROM users WHERE LOWER(email) = ? AND id != ?')
      .bind(email, userId)
      .first();
    if (owner) return c.json({ detail: 'That email is already used by another account.' }, 409);

    if (currentUser.supabase_user_id) {
      await updateSupabaseAuthUser(c, currentUser.supabase_user_id, { email });
    }

    await c.env.DB.prepare('UPDATE users SET email = ?, updated_at = datetime(\'now\') WHERE id = ?')
      .bind(email, userId)
      .run();
    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
    await logSecurityEvent(c, 'email_updated', userId, {});
    return c.json(authUserPayload(user));
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code.startsWith('SUPABASE_AUTH_UPDATE_FAILED') || code === 'SUPABASE_SERVICE_ROLE_MISSING' || code === 'SUPABASE_NOT_CONFIGURED') {
      return c.json({ detail: 'Could not update the login email right now.' }, 503);
    }
    return c.json({ detail: 'Could not update email.' }, 500);
  }
});

api.put('/users/me/password', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const bodyTooLarge = rejectLargeRequest(c, 60_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'account_password', userId, 8, 600);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const newPassword = String(body.new_password || body.password || '');

    if (!newPassword) return c.json({ detail: 'New password is required.' }, 400);
    if (newPassword.length < 8) return c.json({ detail: 'New password must be at least 8 characters.' }, 400);

    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
    if (!user) return c.json({ detail: 'User not found' }, 404);

    if (user.supabase_user_id) {
      await updateSupabaseAuthUser(c, user.supabase_user_id, { password: newPassword });
    }

    const newHash = await hashPassword(newPassword);
    await c.env.DB.prepare('UPDATE users SET password_hash = ?, updated_at = datetime(\'now\') WHERE id = ?')
      .bind(newHash, userId)
      .run();
    await logSecurityEvent(c, 'password_updated', userId, {});
    return c.json({ detail: 'Password updated.' });
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code.startsWith('SUPABASE_AUTH_UPDATE_FAILED') || code === 'SUPABASE_SERVICE_ROLE_MISSING' || code === 'SUPABASE_NOT_CONFIGURED') {
      return c.json({ detail: 'Could not update the login password right now.' }, 503);
    }
    return c.json({ detail: 'Could not update password.' }, 500);
  }
});

api.post('/users/me/phone/start', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const bodyTooLarge = rejectLargeRequest(c, 40_000);
    if (bodyTooLarge) return bodyTooLarge;
    const body: any = await c.req.json().catch(() => ({}));
    const normalizedPhone = normalizePhone(body.phone);
    const limited = await enforceRateLimit(c, 'account_phone_start', `${userId}:${normalizedPhone || clientIp(c)}`, 5, 600);
    if (limited) return limited;
    await ensurePhoneAuthSchema(c.env.DB);

    const owner: any = await c.env.DB.prepare('SELECT id FROM users WHERE phone = ? AND id != ?')
      .bind(normalizedPhone, userId)
      .first();
    if (owner) return c.json({ detail: 'That phone number is already verified on another account.' }, 409);

    const startedWithVerify = await startTwilioVerification(c, normalizedPhone);
    if (startedWithVerify) {
      return c.json({
        detail: 'We sent a verification code to your phone.',
        delivery: 'twilio_verify',
      });
    }

    const code = createPhoneCode();
    const jwtSecret = getJwtSecret(c);
    const codeHash = await sha256Hex(`${normalizedPhone}:${code}:${jwtSecret}`);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    await c.env.DB.prepare(
      'INSERT INTO phone_login_codes (id, phone, code_hash, expires_at) VALUES (?, ?, ?, ?)'
    ).bind(uuid(), normalizedPhone, codeHash, expiresAt).run();

    const delivery = await sendLegacyPhoneCode(c, normalizedPhone, code);
    const payload: any = {
      detail: delivery === 'legacy_sms'
        ? 'We sent a verification code to your phone.'
        : 'Twilio Verify is not configured yet, so use the development code shown here.',
      delivery,
    };
    if (delivery === 'development') payload.dev_code = code;

    return c.json(payload);
  } catch (error: any) {
    const code = String(error?.message || '');
    if (code === 'PHONE_INVALID') return c.json({ detail: 'Enter a valid phone number with country code.' }, 400);
    if (code === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    if (code.startsWith('PHONE_VERIFY_START_FAILED')) return twilioVerifyStartErrorResponse(c, code);
    if (code === 'PHONE_SMS_FAILED') return c.json({ detail: 'Could not send SMS code. Check Twilio settings.' }, 502);
    console.error(JSON.stringify({ event: 'phone_verification_start_failed', error: code.slice(0, 180) }));
    return c.json({ detail: 'Could not start phone verification. Please try again in a moment.', code: 'PHONE_START_FAILED' }, 500);
  }
});

api.post('/users/me/phone/verify', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const bodyTooLarge = rejectLargeRequest(c, 40_000);
    if (bodyTooLarge) return bodyTooLarge;
    const body: any = await c.req.json().catch(() => ({}));
    const normalizedPhone = normalizePhone(body.phone);
    const limited = await enforceRateLimit(c, 'account_phone_verify', `${userId}:${normalizedPhone || clientIp(c)}`, 12, 600);
    if (limited) return limited;
    const normalizedCode = String(body.code || '').replace(/\D/g, '');
    if (normalizedCode.length !== 6) {
      return c.json({ detail: 'Enter the 6-digit verification code.' }, 400);
    }
    await ensurePhoneAuthSchema(c.env.DB);

    const owner: any = await c.env.DB.prepare('SELECT id FROM users WHERE phone = ? AND id != ?')
      .bind(normalizedPhone, userId)
      .first();
    if (owner) return c.json({ detail: 'That phone number is already verified on another account.' }, 409);

    if (getTwilioVerifyConfig(c)) {
      const verified = await checkTwilioVerification(c, normalizedPhone, normalizedCode);
      if (!verified) return c.json({ detail: 'Invalid or expired verification code.' }, 401);
    } else {
      const phoneCode: any = await c.env.DB.prepare(
        'SELECT * FROM phone_login_codes WHERE phone = ? AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1'
      ).bind(normalizedPhone).first();

      if (!phoneCode) return c.json({ detail: 'No active code for this phone number.' }, 401);
      if ((phoneCode.attempts || 0) >= 5) return c.json({ detail: 'Too many attempts. Request a new code.' }, 429);
      if (Date.parse(phoneCode.expires_at) < Date.now()) return c.json({ detail: 'Code expired. Request a new code.' }, 401);

      const jwtSecret = getJwtSecret(c);
      const expectedHash = await sha256Hex(`${normalizedPhone}:${normalizedCode}:${jwtSecret}`);
      if (expectedHash !== phoneCode.code_hash) {
        await c.env.DB.prepare('UPDATE phone_login_codes SET attempts = attempts + 1 WHERE id = ?').bind(phoneCode.id).run();
        return c.json({ detail: 'Invalid verification code.' }, 401);
      }

      await c.env.DB.prepare('UPDATE phone_login_codes SET consumed_at = datetime(\'now\') WHERE id = ?').bind(phoneCode.id).run();
    }

    await c.env.DB.prepare('UPDATE users SET phone = ?, phone_verified = 1, updated_at = datetime(\'now\') WHERE id = ?')
      .bind(normalizedPhone, userId)
      .run();
    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
    return c.json(authUserPayload(user));
  } catch (error: any) {
    const code = String(error?.message || '');
    if (code === 'PHONE_INVALID') return c.json({ detail: 'Enter a valid phone number with country code.' }, 400);
    if (code === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    if (code.startsWith('PHONE_VERIFY_CHECK_FAILED')) return c.json({ detail: 'Could not check verification code. Try again.', code }, 502);
    return c.json({ detail: 'Could not verify phone number.' }, 500);
  }
});

api.put('/users/me/username', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const bodyTooLarge = rejectLargeRequest(c, 20_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'username_claim', userId, 30, 300);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['username']);
    if (unknown) return unknown;
    const usernameCheck = validateUsernameForAccount(body.username);
    if (!usernameCheck.ok) {
      return c.json({
        available: false,
        username: usernameCheck.username,
        code: usernameCheck.code || 'invalid_format',
        reason: usernameCheck.detail,
      }, 400);
    }
    const currentUser: any = await c.env.DB.prepare('SELECT username FROM users WHERE id = ?').bind(userId).first();
    const existing: any = await c.env.DB.prepare('SELECT id FROM users WHERE LOWER(username) = ? AND id != ?')
      .bind(usernameCheck.username.toLowerCase(), userId)
      .first();
    if (existing) {
      return c.json({
        available: false,
        username: usernameCheck.username,
        code: 'taken',
        reason: 'Username is already taken.',
      }, 409);
    }

    await c.env.DB.prepare('UPDATE users SET username = ?, updated_at = datetime(\'now\') WHERE id = ?')
      .bind(usernameCheck.username, userId)
      .run();
    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
    await recordAbuseSignals(c, userId, 'username_claim', { username: usernameCheck.username });
    await logSecurityEvent(c, 'username_changed', userId, { previous_username: currentUser?.username || '', new_username: usernameCheck.username });
    return c.json(authUserPayload(user));
  } catch (error: any) {
    console.error('Username claim failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not save username.' }, 500);
  }
});

api.get('/users/search/:query', authMiddleware, async (c) => {
  const limited = await enforceRateLimit(c, 'user_search', getUserId(c), 120, 60);
  if (limited) return limited;
  const q = cleanText(c.req.param('query'), 80);
  if (q.length < 2) return c.json([]);
  const r = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio FROM users WHERE username LIKE ? OR full_name LIKE ? LIMIT 20').bind(`%${q}%`, `%${q}%`).all();
  return c.json((r.results as any[]).map((user) => safeUserPayload(user)));
});

// Exact username check (no auth required for registration flow)
api.get('/users/check-username/:username', async (c) => {
  const limited = await enforceRateLimit(c, 'username_check', clientIp(c), 80, 60);
  if (limited) return limited;
  const usernameCheck = validateUsernameForAccount(c.req.param('username'));
  const username = usernameCheck.username;
  if (!usernameCheck.ok) {
    return c.json({
      available: false,
      username,
      code: usernameCheck.code || 'invalid_format',
      reason: usernameCheck.detail,
    });
  }
  const user: any = await c.env.DB.prepare('SELECT id FROM users WHERE LOWER(username) = ?').bind(username.toLowerCase()).first();
  return c.json({
    available: !user,
    username,
    code: user ? 'taken' : 'available',
    reason: user ? 'Username is already taken.' : 'Username available',
  });
});

api.get('/users/:userId', authMiddleware, async (c) => {
  const viewerId = getUserId(c);
  await ensurePremiumSchema(c.env.DB);
  const targetUserId = c.req.param('userId');
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(targetUserId).first();
  if (!user) return c.json({ detail: 'User not found' }, 404);
  const safe = safeUserPayload(user);
  const follow: any = viewerId && viewerId !== targetUserId
    ? await c.env.DB.prepare('SELECT id FROM follows WHERE follower_id = ? AND following_id = ? LIMIT 1').bind(viewerId, targetUserId).first()
    : null;
  const block: any = viewerId && viewerId !== targetUserId
    ? await c.env.DB.prepare('SELECT blocker_id, blocked_id FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1')
      .bind(viewerId, targetUserId, targetUserId, viewerId)
      .first()
    : null;
  const viewerHasBlocked = block?.blocker_id === viewerId && block?.blocked_id === targetUserId;
  const viewerBlockedBy = block?.blocker_id === targetUserId && block?.blocked_id === viewerId;
  const canView = await canViewUserContent(c.env.DB, viewerId, user);
  if (!canView) {
    return c.json({
      id: safe.id,
      username: safe.username,
      full_name: safe.full_name,
      profile_image: safe.profile_image,
      followers_count: safe.followers_count,
      following_count: safe.following_count,
      posts_count: safe.posts_count,
      is_following: !!follow,
      viewer_has_blocked: viewerHasBlocked,
      viewer_blocked_by: viewerBlockedBy,
      is_private: true,
      privacy_locked: true,
    });
  }
  return c.json({ ...safe, is_following: !!follow, viewer_has_blocked: viewerHasBlocked, viewer_blocked_by: viewerBlockedBy });
});

api.post('/users/:userId/follow', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const targetId = c.req.param('userId');
  if (userId === targetId) return c.json({ detail: 'Cannot follow yourself' }, 400);
  const limited = await enforceRateLimit(c, 'follow', userId, 120, 60);
  if (limited) return limited;
  const body: any = await c.req.json().catch(() => ({}));
  const requested = optionalBoolean(body.following ?? body.followed ?? body.value);
  const target: any = await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(targetId).first();
  if (!target) return c.json({ detail: 'User not found' }, 404);
  await ensureAbuseProtectionSchema(c.env.DB);
  const block: any = await c.env.DB.prepare('SELECT id FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1')
    .bind(userId, targetId, targetId, userId)
    .first();
  if (block) return c.json({ detail: 'You cannot follow this profile.' }, 403);

  let nextFollowing = requested;
  if (nextFollowing === null) {
    const ex = await c.env.DB.prepare('SELECT id FROM follows WHERE follower_id = ? AND following_id = ?').bind(userId, targetId).first();
    nextFollowing = !ex;
  }

  let changed = false;
  if (nextFollowing) {
    const results = await c.env.DB.batch([
      c.env.DB.prepare('INSERT OR IGNORE INTO follows (id, follower_id, following_id) VALUES (?, ?, ?)').bind(uuid(), userId, targetId),
      c.env.DB.prepare('UPDATE users SET following_count = COALESCE(following_count, 0) + 1 WHERE id = ? AND changes() > 0').bind(userId),
      c.env.DB.prepare('UPDATE users SET followers_count = COALESCE(followers_count, 0) + 1 WHERE id = ? AND changes() > 0').bind(targetId),
    ]);
    changed = d1Changes(results?.[0]) > 0;
  } else {
    const results = await c.env.DB.batch([
      c.env.DB.prepare('DELETE FROM follows WHERE follower_id = ? AND following_id = ?').bind(userId, targetId),
      c.env.DB.prepare('UPDATE users SET following_count = MAX(0, COALESCE(following_count, 0) - 1) WHERE id = ? AND changes() > 0').bind(userId),
      c.env.DB.prepare('UPDATE users SET followers_count = MAX(0, COALESCE(followers_count, 0) - 1) WHERE id = ? AND changes() > 0').bind(targetId),
    ]);
    changed = d1Changes(results?.[0]) > 0;
  }

  if (nextFollowing && changed) {
    try {
      const me: any = await c.env.DB.prepare('SELECT full_name FROM users WHERE id = ?').bind(userId).first();
      await insertNotificationOnce(c, {
        userId: targetId,
        type: 'follow',
        title: 'New Follower',
        body: `${me?.full_name || 'Someone'} started following you`,
        data: { from_user_id: userId },
        dedupeKey: `follow:${userId}:${targetId}`,
        dedupeSeconds: 86400,
      });
    } catch {}
  }
  if (changed) {
    runBackgroundTask(c, 'supabase_follow_write_through_failed', async () => {
      await mirrorLegacyUserToSupabase(c, userId);
      await mirrorLegacyUserToSupabase(c, targetId);
      await mirrorLegacyFollowToSupabase(c, userId, targetId, !!nextFollowing);
    });
  }

  const counts: any = await c.env.DB.prepare(
    `SELECT
       (SELECT following_count FROM users WHERE id = ?) AS following_count,
       (SELECT followers_count FROM users WHERE id = ?) AS followers_count`
  ).bind(userId, targetId).first();
  return c.json({
    following: !!nextFollowing,
    following_count: Number(counts?.following_count || 0),
    followers_count: Number(counts?.followers_count || 0),
  });
});

api.post('/users/:userId/block', authMiddleware, async (c) => {
  const blockerId = getUserId(c);
  const blockedId = c.req.param('userId');
  if (blockerId === blockedId) return c.json({ detail: 'You cannot block yourself.' }, 400);
  const limited = await enforceRateLimit(c, 'block_user', blockerId, 40, 60);
  if (limited) return limited;
  await ensureAbuseProtectionSchema(c.env.DB);
  const target: any = await c.env.DB.prepare('SELECT id FROM users WHERE id = ? LIMIT 1').bind(blockedId).first();
  if (!target) return c.json({ detail: 'User not found' }, 404);
  await c.env.DB.batch([
    c.env.DB.prepare('INSERT OR IGNORE INTO blocks (id, blocker_id, blocked_id, created_at) VALUES (?, ?, ?, datetime(\'now\'))').bind(uuid(), blockerId, blockedId),
    c.env.DB.prepare('DELETE FROM follows WHERE (follower_id = ? AND following_id = ?) OR (follower_id = ? AND following_id = ?)').bind(blockerId, blockedId, blockedId, blockerId),
  ]);
  await logSecurityEvent(c, 'user_blocked', blockerId, { blocked_id: blockedId });
  return c.json({ blocked: true });
});

api.delete('/users/:userId/block', authMiddleware, async (c) => {
  const blockerId = getUserId(c);
  const blockedId = c.req.param('userId');
  const limited = await enforceRateLimit(c, 'unblock_user', blockerId, 40, 60);
  if (limited) return limited;
  await ensureAbuseProtectionSchema(c.env.DB);
  await c.env.DB.prepare('DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?').bind(blockerId, blockedId).run();
  return c.json({ blocked: false });
});

api.get('/blocks', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'blocks_read', userId, 60, 60);
  if (limited) return limited;
  await ensureAbuseProtectionSchema(c.env.DB);
  const rows = await c.env.DB.prepare(
    `SELECT b.blocked_id, b.created_at, u.username, u.full_name, u.profile_image
     FROM blocks b JOIN users u ON u.id = b.blocked_id
     WHERE b.blocker_id = ?
     ORDER BY b.created_at DESC LIMIT 100`
  ).bind(userId).all();
  return c.json((rows.results as any[]).map((row) => ({
    blocked_id: row.blocked_id,
    created_at: row.created_at,
    user: safeUserPayload({ id: row.blocked_id, username: row.username, full_name: row.full_name, profile_image: row.profile_image }),
  })));
});

// ═══════════════════════════════════════════════════════════════════════════════
// POSTS (with Check-In support)
// ═══════════════════════════════════════════════════════════════════════════════
// Music proxy: Audius powers the post creation sound picker without exposing provider internals.
api.get('/music/audius/trending', async (c) => {
  try {
    await ensureAudioSchema(c.env.DB);
    const limited = await enforceRateLimit(c, 'audius_trending', (await getOptionalUserId(c)) || clientIp(c), 120, 60);
    if (limited) return limited;
    const limit = clampNumber(c.req.query('limit'), 1, 50, 50);
    const time = ['week', 'month', 'allTime'].includes(String(c.req.query('time') || ''))
      ? String(c.req.query('time'))
      : 'week';
    const tracks = await cachedJson(
      c,
      `audius:trending:${time}:${limit}`,
      600,
      () => fetchAudiusTracks('/tracks/trending', { time, limit })
    );
    const hidden = await c.env.DB.prepare("SELECT track_id FROM hidden_sounds WHERE provider = 'audius'").all();
    const hiddenIds = new Set((hidden.results as any[]).map((row) => String(row.track_id)));
    return c.json({ tracks: (tracks as any[]).filter((track) => !hiddenIds.has(String(track.track_id))) });
  } catch (error: any) {
    console.log('Audius trending failed:', error?.message || error);
    return c.json({ detail: 'Music is temporarily unavailable.', tracks: [] }, 503);
  }
});

api.get('/music/audius/search', async (c) => {
  try {
    await ensureAudioSchema(c.env.DB);
    const limited = await enforceRateLimit(c, 'audius_search', (await getOptionalUserId(c)) || clientIp(c), 90, 60);
    if (limited) return limited;
    const q = cleanText(c.req.query('q') || c.req.query('query'), 90);
    if (q.length < 2) return c.json({ tracks: [] });
    const limit = clampNumber(c.req.query('limit'), 1, 50, 50);
    const cacheKey = `audius:search:${q.toLowerCase()}:${limit}`;
    const tracks = await cachedJson(
      c,
      cacheKey,
      300,
      () => fetchAudiusTracks('/tracks/search', { query: q, limit })
    );
    const hidden = await c.env.DB.prepare("SELECT track_id FROM hidden_sounds WHERE provider = 'audius'").all();
    const hiddenIds = new Set((hidden.results as any[]).map((row) => String(row.track_id)));
    return c.json({ tracks: (tracks as any[]).filter((track) => !hiddenIds.has(String(track.track_id))) });
  } catch (error: any) {
    console.log('Audius search failed:', error?.message || error);
    return c.json({ detail: 'Music search is temporarily unavailable.', tracks: [] }, 503);
  }
});

// Server-side Giphy proxy for Notes GIF picking. The API key stays in Cloudflare secrets,
// never in the native app bundle or client code.
api.get('/gifs/search', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'giphy_search', userId || clientIp(c), 80, 60);
    if (limited) return limited;
    const apiKey = String(c.env.GIPHY_API_KEY || '').trim();
    if (!apiKey) return c.json({ detail: 'GIF search is not configured yet.', gifs: [] }, 503);
    const query = cleanText(c.req.query('q') || c.req.query('query'), 80);
    if (query.length < 2) return c.json({ gifs: [] });
    const limit = clampNumber(c.req.query('limit'), 1, 32, 24);
    const offset = clampNumber(c.req.query('offset'), 0, 500, 0);
    const cacheKey = `giphy:search:${query.toLowerCase()}:${limit}:${offset}`;
    const gifs = await cachedJson(c, cacheKey, 180, async () => {
      const params = new URLSearchParams({
        api_key: apiKey,
        q: query,
        limit: String(limit),
        offset: String(offset),
        rating: 'pg-13',
        lang: 'en',
      });
      const response = await fetch(`https://api.giphy.com/v1/gifs/search?${params.toString()}`, {
        headers: { Accept: 'application/json' },
      });
      if (!response.ok) throw new Error(`Giphy returned ${response.status}`);
      const data: any = await response.json();
      const rows = Array.isArray(data?.data) ? data.data : [];
      return rows.map((gif: any) => {
        const images = gif?.images || {};
        const original = images.original || {};
        const preview = images.fixed_width_small || images.fixed_width || images.downsized || original;
        return {
          id: publicId(gif?.id, 80),
          title: cleanText(gif?.title, 120),
          preview_url: String(preview.webp || preview.url || '').slice(0, 500),
          media_url: String(original.webp || original.url || preview.webp || preview.url || '').slice(0, 500),
          width: clampNumber(original.width, 1, 4096, 0),
          height: clampNumber(original.height, 1, 4096, 0),
        };
      }).filter((gif: any) => gif.id && gif.media_url);
    });
    return c.json({ gifs });
  } catch (error: any) {
    console.log('Giphy search failed:', error?.message || error);
    return c.json({ detail: 'GIF search is temporarily unavailable.', gifs: [] }, 503);
  }
});

api.get('/music/audius/stream/:trackId', async (c) => {
  try {
    await ensureAudioSchema(c.env.DB);
    const limited = await enforceRateLimit(c, 'audius_stream_lookup', (await getOptionalUserId(c)) || clientIp(c), 180, 60);
    if (limited) return limited;
    const trackId = cleanText(c.req.param('trackId'), 80);
    if (!trackId) return c.json({ detail: 'Track id is required.' }, 400);
    const hidden = await c.env.DB.prepare("SELECT track_id FROM hidden_sounds WHERE provider = 'audius' AND track_id = ?")
      .bind(trackId)
      .first();
    if (hidden) return c.json({ detail: 'This sound is unavailable.' }, 404);

    const response = await fetch(audiusUrl(`/tracks/${encodeURIComponent(trackId)}`, {}), {
      headers: { Accept: 'application/json' },
    });
    if (!response.ok) throw new Error(`Audius returned ${response.status}`);
    const data: any = await response.json();
    const track = normalizeAudiusTrack(data?.data || {});
    if (!track.stream_url) return c.json({ detail: 'Track stream is unavailable.' }, 404);
    return c.json(track);
  } catch (error: any) {
    console.log('Audius stream failed:', error?.message || error);
    return c.json({ detail: 'Could not load this sound.' }, 503);
  }
});

api.get('/music/audius/favorites', authMiddleware, async (c) => {
  try {
    await ensureAudioSchema(c.env.DB);
    const userId = getUserId(c);
    const rows = await c.env.DB.prepare(
      `SELECT fs.track_id, fs.title, fs.artist, fs.artist_id, fs.artist_handle, fs.artist_profile_image,
              fs.artwork_url, fs.duration, fs.genre, fs.play_count, fs.favorite_count
       FROM favorite_sounds fs
       LEFT JOIN hidden_sounds hs ON hs.provider = fs.provider AND hs.track_id = fs.track_id
       WHERE fs.user_id = ? AND fs.provider = 'audius' AND hs.track_id IS NULL
       ORDER BY fs.created_at DESC
       LIMIT 100`
    ).bind(userId).all();
    const tracks = (rows.results as any[]).map((row) => ({
      id: String(row.track_id || ''),
      track_id: String(row.track_id || ''),
      title: String(row.title || 'Untitled track'),
      artist: String(row.artist || 'Audius artist'),
      artist_id: String(row.artist_id || ''),
      artist_handle: String(row.artist_handle || ''),
      artist_profile_image: String(row.artist_profile_image || ''),
      artwork_url: String(row.artwork_url || ''),
      duration: Number(row.duration || 0),
      genre: String(row.genre || ''),
      play_count: Number(row.play_count || 0),
      favorite_count: Number(row.favorite_count || 0),
    })).filter((track) => track.id);
    return c.json({ tracks });
  } catch (error: any) {
    console.log('Audius favorites failed:', error?.message || error);
    return c.json({ detail: 'Could not load favorite sounds.', tracks: [] }, 500);
  }
});

api.post('/music/audius/favorites', authMiddleware, async (c) => {
  try {
    await ensureAudioSchema(c.env.DB);
    const userId = getUserId(c);
    const body: any = await c.req.json().catch(() => ({}));
    const trackId = cleanText(body.track_id || body.id || body.audio_track_id, 80);
    if (!trackId) return c.json({ detail: 'Track id is required.' }, 400);

    const hidden = await c.env.DB.prepare("SELECT track_id FROM hidden_sounds WHERE provider = 'audius' AND track_id = ?")
      .bind(trackId)
      .first();
    if (hidden) return c.json({ detail: 'This sound is unavailable.' }, 400);

    const title = cleanText(body.title || body.audio_title || 'Untitled track', 180);
    const artist = cleanText(body.artist || body.audio_artist || 'Audius artist', 120);
    const artistId = cleanText(body.artist_id || body.audio_artist_id || '', 80);
    const artistHandle = cleanText(body.artist_handle || body.audio_artist_handle || '', 120);
    const artistProfileImage = cleanText(body.artist_profile_image || body.audio_artist_profile_image || '', 1000);
    const artworkUrl = cleanText(body.artwork_url || body.audio_artwork_url || '', 1000);
    const duration = clampNumber(body.duration || body.audio_duration, 0, 60 * 60 * 6, 0);
    const genre = cleanText(body.genre || '', 80);
    const playCount = clampNumber(body.play_count, 0, 1000000000, 0);
    const favoriteCount = clampNumber(body.favorite_count, 0, 1000000000, 0);
    const ts = now();

    await c.env.DB.prepare(
      `INSERT INTO favorite_sounds (
         id, user_id, provider, track_id, title, artist, artist_id, artist_handle, artist_profile_image,
         artwork_url, duration, genre, play_count, favorite_count, created_at, updated_at
       )
       VALUES (?, ?, 'audius', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, provider, track_id) DO UPDATE SET
         title = excluded.title,
         artist = excluded.artist,
         artist_id = excluded.artist_id,
         artist_handle = excluded.artist_handle,
         artist_profile_image = excluded.artist_profile_image,
         artwork_url = excluded.artwork_url,
         duration = excluded.duration,
         genre = excluded.genre,
         play_count = excluded.play_count,
         favorite_count = excluded.favorite_count,
         updated_at = excluded.updated_at`
    ).bind(
      uuid(), userId, trackId, title, artist, artistId, artistHandle, artistProfileImage,
      artworkUrl, duration, genre, playCount, favoriteCount, ts, ts
    ).run();

    return c.json({
      favorite: true,
      track: {
        id: trackId, track_id: trackId, title, artist, artist_id: artistId, artist_handle: artistHandle,
        artist_profile_image: artistProfileImage, artwork_url: artworkUrl, duration, genre, play_count: playCount,
        favorite_count: favoriteCount,
      },
    });
  } catch (error: any) {
    console.log('Audius favorite save failed:', error?.message || error);
    return c.json({ detail: 'Could not save this sound.' }, 500);
  }
});

api.delete('/music/audius/favorites/:trackId', authMiddleware, async (c) => {
  try {
    await ensureAudioSchema(c.env.DB);
    const userId = getUserId(c);
    const trackId = cleanText(c.req.param('trackId'), 80);
    if (!trackId) return c.json({ detail: 'Track id is required.' }, 400);
    await c.env.DB.prepare("DELETE FROM favorite_sounds WHERE user_id = ? AND provider = 'audius' AND track_id = ?")
      .bind(userId, trackId)
      .run();
    return c.json({ favorite: false, track_id: trackId });
  } catch (error: any) {
    console.log('Audius favorite remove failed:', error?.message || error);
    return c.json({ detail: 'Could not remove this sound.' }, 500);
  }
});

api.get('/music/feed', authMiddleware, async (c) => {
  try {
    await ensureAiMusicSchema(c.env.DB);
    const userId = getUserId(c);
    const limit = clampNumber(c.req.query('limit'), 1, 60, 30);
    const rows = await c.env.DB.prepare(`
      SELECT m.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
        EXISTS(SELECT 1 FROM ai_music_interactions i WHERE i.music_id = m.id AND i.user_id = ? AND i.kind = 'like') AS liked,
        EXISTS(SELECT 1 FROM ai_music_interactions i WHERE i.music_id = m.id AND i.user_id = ? AND i.kind = 'save') AS saved,
        EXISTS(SELECT 1 FROM ai_music_interactions i WHERE i.music_id = m.id AND i.user_id = ? AND i.kind = 'repost') AS reposted
      FROM ai_music_posts m
      LEFT JOIN users u ON u.id = m.user_id
      WHERE COALESCE(m.status, 'pending') = 'generated' AND COALESCE(m.is_public, 0) = 1
      ORDER BY m.created_at DESC
      LIMIT ?
    `).bind(userId, userId, userId, limit).all();
    return c.json({ posts: (rows.results as any[]).map((row) => publicAiMusicPayload(row, row)) });
  } catch (error: any) {
    console.log('AI music feed failed:', error?.message || error);
    return c.json({ detail: 'Could not load music posts.', posts: [] }, 500);
  }
});

async function serveAiMusicAudio(c: any) {
  if (!c.env.MEDIA_BACKUP) return c.json({ detail: 'Music storage is not configured.' }, 503);
  try {
    await ensureAiMusicSchema(c.env.DB);
    const musicId = cleanText(c.req.param('musicId'), 80);
    const music: any = await c.env.DB.prepare(
      "SELECT * FROM ai_music_posts WHERE id = ? AND COALESCE(status, 'pending') = 'generated'"
    ).bind(musicId).first();
    if (!music || !music.audio_r2_key) return c.json({ detail: 'Music not found.' }, 404);

    const head = await c.env.MEDIA_BACKUP.head(music.audio_r2_key);
    if (!head) return c.json({ detail: 'Music file not found.' }, 404);

    const range = parseByteRange(c.req.header('range'), head.size || 0);
    if (range === 'invalid') {
      return new Response(null, {
        status: 416,
        headers: {
          'accept-ranges': 'bytes',
          'content-range': `bytes */${head.size || 0}`,
        },
      });
    }

    const object = range
      ? await c.env.MEDIA_BACKUP.get(music.audio_r2_key, { range: { offset: range.offset, length: range.length } })
      : await c.env.MEDIA_BACKUP.get(music.audio_r2_key);
    if (!object) return c.json({ detail: 'Music file not found.' }, 404);

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('content-type', headers.get('content-type') || 'audio/mpeg');
    headers.set('etag', head.httpEtag || object.httpEtag);
    headers.set('accept-ranges', 'bytes');
    headers.set('cache-control', 'public, max-age=86400');
    headers.set('x-content-type-options', 'nosniff');
    headers.set('content-length', String(range ? range.length : head.size || object.size || 0));
    if (range) headers.set('content-range', `bytes ${range.offset}-${range.end}/${head.size}`);

    return new Response(c.req.method === 'HEAD' ? null : object.body, { status: range ? 206 : 200, headers });
  } catch (error: any) {
    console.log('AI music audio failed:', error?.message || error);
    return c.json({ detail: 'Could not load audio.' }, 500);
  }
}

api.get('/music/audio/:musicId', serveAiMusicAudio);
api.on('HEAD', '/music/audio/:musicId', serveAiMusicAudio);

api.post('/music/generate', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 60_000);
    if (bodyTooLarge) return bodyTooLarge;
    await ensureAiMusicSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'music_generate', userId, 10, 60);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'music_generate_daily', userId, 35, 86400);
    if (dailyLimited) return dailyLimited;
    const body: any = await c.req.json().catch(() => ({}));
    const { text: promptText, lines } = normalizeAiMusicPrompt(body.prompt_text || body.lyrics_text || body.text || body.prompt);
    const mood = normalizeAiMusicMood(body.mood);
    const style = normalizeAiMusicStyle(body.style);

    if (lines.length < 1) return c.json({ detail: 'Write 1 to 6 original lines first.' }, 400);
    if (lines.length > 6) return c.json({ detail: 'Keep it short: 1 to 6 lines.' }, 400);
    const moderation = moderateAiMusicPrompt(promptText);
    if (!moderation.ok) return c.json({ detail: moderation.detail || 'That text cannot be generated right now.' }, 400);
    if (!c.env.ELEVENLABS_API_KEY) return c.json({ detail: 'Music generation is not configured yet.' }, 503);
    if (!c.env.MEDIA_BACKUP) return c.json({ detail: 'Music storage is not configured yet.' }, 503);

    const dailyLimit = await aiMusicSettingNumber(c.env.DB, 'music_daily_generation_limit', c.env.MUSIC_DAILY_GENERATION_LIMIT, 1, 50, 5);
    const cooldownSeconds = await aiMusicSettingNumber(c.env.DB, 'music_generation_cooldown_seconds', c.env.MUSIC_GENERATION_COOLDOWN_SECONDS, 0, 3600, 60);
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const generatedToday: any = await c.env.DB.prepare(
      'SELECT COUNT(*) AS count FROM ai_music_posts WHERE user_id = ? AND created_at >= ?'
    ).bind(userId, cutoff).first();
    if (Number(generatedToday?.count || 0) >= dailyLimit) {
      return c.json({ detail: `Daily music limit reached. Try again tomorrow.` }, 429);
    }

    const latest: any = await c.env.DB.prepare(
      'SELECT created_at FROM ai_music_posts WHERE user_id = ? ORDER BY created_at DESC LIMIT 1'
    ).bind(userId).first();
    const latestTime = latest?.created_at ? Date.parse(latest.created_at) : 0;
    if (cooldownSeconds > 0 && latestTime && Date.now() - latestTime < cooldownSeconds * 1000) {
      const wait = Math.ceil((cooldownSeconds * 1000 - (Date.now() - latestTime)) / 1000);
      return c.json({ detail: `Wait ${wait}s before generating another music post.` }, 429);
    }

    const id = uuid();
    const ts = now();
    await c.env.DB.prepare(
      `INSERT INTO ai_music_posts
       (id, user_id, provider, prompt_text, lyrics_text, mood, style, audio_duration, waveform_data, status, is_public, created_at, updated_at)
       VALUES (?, ?, 'elevenlabs', ?, ?, ?, ?, 20, ?, 'pending', 0, ?, ?)`
    ).bind(id, userId, promptText, promptText, mood, style, JSON.stringify(buildWaveformData(promptText)), ts, ts).run();

    const prompt = buildAiMusicPrompt(promptText, mood, style);
    const response = await fetch('https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128', {
      method: 'POST',
      headers: {
        'xi-api-key': c.env.ELEVENLABS_API_KEY,
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg',
      },
      body: JSON.stringify({
        model_id: 'music_v1',
        prompt,
        music_length_ms: 20000,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => '');
      await c.env.DB.prepare("UPDATE ai_music_posts SET status = 'failed', updated_at = ? WHERE id = ?")
        .bind(now(), id)
        .run();
      const providerError = errorText.toLowerCase();
      let safeDetail = `Music generation failed at ElevenLabs (HTTP ${response.status}).`;
      let clientStatus: 400 | 429 | 502 | 503 = 502;
      if (response.status === 401) {
        safeDetail = 'ElevenLabs API key was rejected. Re-save ELEVENLABS_API_KEY in Cloudflare.';
        clientStatus = 503;
      } else if (response.status === 403) {
        safeDetail = 'ElevenLabs Music API is not enabled for this key or workspace.';
        clientStatus = 503;
      } else if (response.status === 402) {
        safeDetail = 'ElevenLabs needs enough credits or a plan that supports music generation.';
        clientStatus = 503;
      } else if (response.status === 422 || providerError.includes('bad_prompt')) {
        safeDetail = 'That text could not be generated. Use safer original words and avoid copied lyrics or real-artist imitation.';
        clientStatus = 400;
      } else if (response.status === 429) {
        safeDetail = 'ElevenLabs is rate limiting music generation. Try again in a moment.';
        clientStatus = 429;
      }
      console.log('ElevenLabs music failed:', response.status, errorText.slice(0, 280));
      return c.json({ detail: safeDetail }, clientStatus);
    }

    const audioBuffer = await response.arrayBuffer();
    if (!audioBuffer.byteLength) {
      await c.env.DB.prepare("UPDATE ai_music_posts SET status = 'failed', updated_at = ? WHERE id = ?")
        .bind(now(), id)
        .run();
      return c.json({ detail: 'Music generation returned an empty file.' }, 502);
    }

    const key = `ai-music/${userId}/${id}.mp3`;
    await c.env.MEDIA_BACKUP.put(key, audioBuffer, {
      httpMetadata: { contentType: 'audio/mpeg' },
      customMetadata: {
        userId,
        provider: 'elevenlabs',
        mood,
        style,
      },
    });

    const audioUrl = aiMusicAudioUrl(c, id);
    const updatedAt = now();
    await c.env.DB.prepare(
      "UPDATE ai_music_posts SET audio_url = ?, audio_r2_key = ?, status = 'generated', updated_at = ? WHERE id = ?"
    ).bind(audioUrl, key, updatedAt, id).run();

    const row: any = await c.env.DB.prepare(`
      SELECT m.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM ai_music_posts m
      LEFT JOIN users u ON u.id = m.user_id
      WHERE m.id = ?
    `).bind(id).first();
    return c.json({ post: publicAiMusicPayload(row) }, 201);
  } catch (error: any) {
    console.log('AI music generate failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not generate music right now.' }, 500);
  }
});

api.post('/music/:musicId/publish', authMiddleware, async (c) => {
  try {
    await ensureAiMusicSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'music_publish', userId, 60, 60);
    if (limited) return limited;
    const musicId = cleanText(c.req.param('musicId'), 80);
    const row: any = await c.env.DB.prepare('SELECT * FROM ai_music_posts WHERE id = ?').bind(musicId).first();
    if (!row) return c.json({ detail: 'Music post not found.' }, 404);
    if (row.user_id !== userId) return c.json({ detail: 'You can only publish your own music.' }, 403);
    if (row.status !== 'generated') return c.json({ detail: 'Music is not ready yet.' }, 400);
    await c.env.DB.prepare('UPDATE ai_music_posts SET is_public = 1, updated_at = ? WHERE id = ?')
      .bind(now(), musicId)
      .run();
    return c.json({ published: true, id: musicId });
  } catch (error: any) {
    console.log('AI music publish failed:', error?.message || error);
    return c.json({ detail: 'Could not publish music post.' }, 500);
  }
});

api.post('/music/:musicId/interactions', authMiddleware, async (c) => {
  try {
    await ensureAiMusicSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'music_interaction', userId, 300, 60);
    if (limited) return limited;
    const musicId = cleanText(c.req.param('musicId'), 80);
    const body: any = await c.req.json().catch(() => ({}));
    const kind = ['like', 'save', 'repost', 'use_sound'].includes(String(body.kind)) ? String(body.kind) : 'like';
    const music: any = await c.env.DB.prepare("SELECT id FROM ai_music_posts WHERE id = ? AND COALESCE(status, 'pending') = 'generated'")
      .bind(musicId)
      .first();
    if (!music) return c.json({ detail: 'Music post not found.' }, 404);

    const existing: any = await c.env.DB.prepare('SELECT id FROM ai_music_interactions WHERE music_id = ? AND user_id = ? AND kind = ?')
      .bind(musicId, userId, kind)
      .first();
    const ts = now();
    let active = true;
    if (existing && kind !== 'use_sound') {
      await c.env.DB.prepare('DELETE FROM ai_music_interactions WHERE id = ?').bind(existing.id).run();
      active = false;
    } else if (!existing) {
      await c.env.DB.prepare('INSERT INTO ai_music_interactions (id, music_id, user_id, kind, created_at) VALUES (?, ?, ?, ?, ?)')
        .bind(uuid(), musicId, userId, kind, ts)
        .run();
    }

    const column = kind === 'save' ? 'saves_count' : kind === 'repost' ? 'reposts_count' : kind === 'like' ? 'likes_count' : '';
    if (column) {
      const delta = active ? 1 : -1;
      const updateMusicSql = `UPDATE ai_music_posts SET ${column} = MAX(0, COALESCE(${column}, 0) + ?), updated_at = ? WHERE id = ?`;
      await c.env.DB.prepare(updateMusicSql)
        .bind(delta, ts, musicId)
        .run();
    }
    return c.json({ active, kind, id: musicId });
  } catch (error: any) {
    console.log('AI music interaction failed:', error?.message || error);
    return c.json({ detail: 'Could not update this music post.' }, 500);
  }
});

api.post('/music/:musicId/report', authMiddleware, async (c) => {
  try {
    await ensureAiMusicSchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'music_report', userId, 12, 60);
    if (limited) return limited;
    const musicId = cleanText(c.req.param('musicId'), 80);
    const body: any = await c.req.json().catch(() => ({}));
    const music: any = await c.env.DB.prepare('SELECT * FROM ai_music_posts WHERE id = ?').bind(musicId).first();
    if (!music) return c.json({ detail: 'Music post not found.' }, 404);
    if (music.user_id === userId) return c.json({ detail: 'You cannot report your own music post.' }, 400);
    const reason = normalizeReportReason(body.reason || 'other');
    const ts = now();
    const reportResults = await c.env.DB.batch([
      c.env.DB.prepare('INSERT OR IGNORE INTO ai_music_reports (id, music_id, reporter_id, reason, created_at) VALUES (?, ?, ?, ?, ?)')
        .bind(uuid(), musicId, userId, reason, ts),
      c.env.DB.prepare('UPDATE ai_music_posts SET reports_count = COALESCE(reports_count, 0) + 1, updated_at = ? WHERE id = ? AND changes() > 0')
        .bind(ts, musicId),
    ]);
    if (d1Changes(reportResults?.[0]) > 0) {
      await c.env.DB.prepare(
        `INSERT INTO reports
         (id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, created_at, updated_at)
         VALUES (?, ?, ?, 'sound', 'ai_music', ?, ?, ?, 'pending', ?, ?)`
      ).bind(uuid(), userId, music.user_id, reason, cleanMultilineText(body.details || music.prompt_text || '', 1000), musicId, ts, ts).run();
    }
    return c.json({ reported: true });
  } catch (error: any) {
    console.log('AI music report failed:', error?.message || error);
    return c.json({ detail: 'Could not report music post.' }, 500);
  }
});

api.get('/music/:musicId/comments', authMiddleware, async (c) => {
  try {
    await ensureAiMusicSchema(c.env.DB);
    const musicId = cleanText(c.req.param('musicId'), 80);
    const exists = await c.env.DB.prepare("SELECT id FROM ai_music_posts WHERE id = ? AND COALESCE(status, 'pending') = 'generated'")
      .bind(musicId)
      .first();
    if (!exists) return c.json({ detail: 'Music post not found.' }, 404);
    const rows = await c.env.DB.prepare(`
      SELECT ac.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM ai_music_comments ac
      LEFT JOIN users u ON u.id = ac.user_id
      WHERE ac.music_id = ? AND COALESCE(ac.status, 'active') = 'active'
      ORDER BY ac.created_at ASC
      LIMIT 120
    `).bind(musicId).all();
    return c.json({
      comments: (rows.results as any[]).map((row) => ({
        id: row.id,
        music_id: row.music_id,
        user_id: row.user_id,
        parent_id: row.parent_id || '',
        body: row.body || '',
        likes_count: Number(row.likes_count || 0),
        created_at: row.created_at,
        user: {
          id: row.user_id,
          username: row.user_username || '',
          full_name: row.user_full_name || '',
          profile_image: row.user_profile_image || '',
        },
      })),
    });
  } catch (error: any) {
    console.log('AI music comments failed:', error?.message || error);
    return c.json({ detail: 'Could not load comments.', comments: [] }, 500);
  }
});

api.post('/music/:musicId/comments', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 80_000);
    if (bodyTooLarge) return bodyTooLarge;
    await ensureAiMusicSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'music_comment', userId, 90, 60);
    if (limited) return limited;
    const musicId = cleanText(c.req.param('musicId'), 80);
    const body: any = await c.req.json().catch(() => ({}));
    const text = cleanText(body.body || body.text || body.comment, 500);
    if (text.length < 1) return c.json({ detail: 'Write a comment first.' }, 400);
    const exists = await c.env.DB.prepare("SELECT id FROM ai_music_posts WHERE id = ? AND COALESCE(status, 'pending') = 'generated'")
      .bind(musicId)
      .first();
    if (!exists) return c.json({ detail: 'Music post not found.' }, 404);
    const id = uuid();
    const ts = now();
    await c.env.DB.prepare(
      "INSERT INTO ai_music_comments (id, music_id, user_id, parent_id, body, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'active', ?, ?)"
    ).bind(id, musicId, userId, cleanText(body.parent_id, 80), text, ts, ts).run();
    await c.env.DB.prepare('UPDATE ai_music_posts SET comments_count = COALESCE(comments_count, 0) + 1, updated_at = ? WHERE id = ?')
      .bind(ts, musicId)
      .run();
    const row: any = await c.env.DB.prepare(`
      SELECT ac.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM ai_music_comments ac
      LEFT JOIN users u ON u.id = ac.user_id
      WHERE ac.id = ?
    `).bind(id).first();
    return c.json({
      comment: {
        id: row.id,
        music_id: row.music_id,
        user_id: row.user_id,
        parent_id: row.parent_id || '',
        body: row.body || '',
        likes_count: Number(row.likes_count || 0),
        created_at: row.created_at,
        user: {
          id: row.user_id,
          username: row.user_username || '',
          full_name: row.user_full_name || '',
          profile_image: row.user_profile_image || '',
        },
      },
    }, 201);
  } catch (error: any) {
    console.log('AI music comment create failed:', error?.message || error);
    return c.json({ detail: 'Could not post comment.' }, 500);
  }
});

api.get('/music/:musicId', authMiddleware, async (c) => {
  try {
    await ensureAiMusicSchema(c.env.DB);
    const userId = getUserId(c);
    const musicId = cleanText(c.req.param('musicId'), 80);
    const row: any = await c.env.DB.prepare(`
      SELECT m.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
        EXISTS(SELECT 1 FROM ai_music_interactions i WHERE i.music_id = m.id AND i.user_id = ? AND i.kind = 'like') AS liked,
        EXISTS(SELECT 1 FROM ai_music_interactions i WHERE i.music_id = m.id AND i.user_id = ? AND i.kind = 'save') AS saved,
        EXISTS(SELECT 1 FROM ai_music_interactions i WHERE i.music_id = m.id AND i.user_id = ? AND i.kind = 'repost') AS reposted
      FROM ai_music_posts m
      LEFT JOIN users u ON u.id = m.user_id
      WHERE m.id = ? AND (COALESCE(m.is_public, 0) = 1 OR m.user_id = ?)
    `).bind(userId, userId, userId, musicId, userId).first();
    if (!row) return c.json({ detail: 'Music post not found.' }, 404);
    return c.json({ post: publicAiMusicPayload(row, row) });
  } catch (error: any) {
    console.log('AI music detail failed:', error?.message || error);
    return c.json({ detail: 'Could not load music post.' }, 500);
  }
});

api.post('/posts', authMiddleware, async (c) => {
  const phoneGate = await requirePhoneVerified(c, 'create posts');
  if (phoneGate) return phoneGate;
  const bodyTooLarge = rejectLargeRequest(c, 1_500_000);
  if (bodyTooLarge) return bodyTooLarge;
  await ensureMediaBackupSchema(c.env.DB);
  await ensureAudioSchema(c.env.DB);
  await ensurePostEditorSchema(c.env.DB);
  await ensureReliabilitySchema(c.env.DB);
  await ensureGovernanceSchema(c.env.DB);
  await ensureAutoCategorySchema(c.env.DB);
  await ensureLocationSchema(c.env.DB);
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'post_create', userId, 30, 60);
  if (limited) return limited;
  const restricted = await enforceUserRestriction(c, userId, 'posting');
  if (restricted) return restricted;
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image, city FROM users WHERE id = ?').bind(userId).first();
  const b = await c.req.json().catch(() => ({}));
  const clientRequestId = getClientRequestId(c, b);
  if (clientRequestId) {
    const existing: any = await c.env.DB.prepare(
      `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
       FROM posts p JOIN users u ON p.user_id = u.id
       WHERE p.user_id = ? AND p.client_request_id = ?
       LIMIT 1`
    ).bind(userId, clientRequestId).first();
    if (existing) return c.json({ ...postPayload(existing, [], c.env), idempotent_replay: true });
  }
  const id = uuid();
  const postType = cleanText(b.post_type || b.category || 'general', 50) || 'general';
  const placeProvider = normalizeAppleMapKitProvider(b.place_provider || b.provider) || (b.place_name ? 'apple_mapkit' : '');
  const placeProviderId = cleanText(b.place_provider_id || b.place_id, 160);
  const placeName = cleanText(b.place_name, 180);
  const placeFormattedAddress = cleanText(b.place_formatted_address || b.location, 260);
  const placeCategory = cleanText(b.place_category || b.category_hint, 80);
  const placeCity = cleanText(b.place_city, 80);
  const placeRegion = cleanText(b.place_region, 80);
  const placeCountry = cleanText(b.place_country, 80);
  if ((placeName || placeFormattedAddress) && looksLikePrivatePlace(placeName, placeFormattedAddress, placeCategory)) {
    return c.json({ detail: 'Private home-style addresses cannot be added as public place tags.' }, 400);
  }
  const isCheckin = postType === 'check_in' && placeProviderId ? 1 : 0;
  const location = placeFormattedAddress || placeName || null;
  const displayCity = cleanText(b.display_city, 80);
  const displayRegion = cleanText(b.display_region, 80);
  const displayCountry = cleanText(b.display_country, 80);
  const displayLocationSource = normalizeDisplayLocationSource(b.display_location_source || (displayCity || displayCountry ? 'manual' : 'none'));
  let displayLocationVisibility = normalizeDisplayLocationVisibility(b.display_location_visibility);
  let displayLocationLabel = normalizeDisplayLocationLabel(displayCity, displayRegion, displayCountry, cleanText(b.display_location_label, 120));
  if (!displayLocationLabel && displayLocationVisibility !== 'hidden') {
    displayLocationLabel = normalizeDisplayLocationLabel(cleanText(user?.city, 120), '', '', '');
  }
  if (!displayLocationLabel) displayLocationVisibility = 'hidden';
  const visibility = normalizeVisibility(b.visibility);
  const postTitle = cleanText(b.title || b.headline, 180);
  const postContent = cleanMultilineText(b.content, 5000);
  const imageUrls = sanitizeMediaReferences(b.images, b.image);
  const primaryImage = safeMediaReference(b.image) || imageUrls[0] || null;
  const mediaTypes = sanitizeMediaTypes(b.media_types, imageUrls.length || (primaryImage ? 1 : 0));
  const explicitTags = sanitizeAutoCategoryTags([...(parseJsonArray(b.tags)), ...(parseJsonArray(b.hashtags))]);
  const mediaTypeHint = mediaTypes.includes('video') ? 'video' : 'image';
  const autoCategory = autoCategoryFromBody(b, {
    caption: [postTitle, postContent].filter(Boolean).join('\n\n'),
    mediaType: mediaTypeHint,
    postType,
    hashtags: explicitTags,
    location,
    placeName: placeName || null,
  });
  const placeLat = b.place_lat == null ? null : clampFloat(b.place_lat, -90, 90, 0);
  const placeLng = b.place_lng == null ? null : clampFloat(b.place_lng, -180, 180, 0);
  const backupIds = parseJsonArray(b.media_backup_ids).map(String).filter(Boolean);
  const mediaDimensions = sanitizeMediaDimensions(b.media_dimensions);
  const editorOverlays = sanitizePostEditorOverlays(b.editor_overlays);
  const taggedUsers = sanitizeTaggedUsers(b.tagged_users);
  const audioProvider = b.audio_provider === 'audius' ? 'audius' : '';
  const audioTrackId = audioProvider ? cleanText(b.audio_track_id, 80) : '';
  const audioTitle = audioProvider ? cleanText(b.audio_title, 180) : '';
  const audioArtist = audioProvider ? cleanText(b.audio_artist, 120) : '';
  const audioArtworkUrl = audioProvider ? cleanText(b.audio_artwork_url, 1000) : '';
  const audioStreamUrl = audioProvider ? cleanText(b.audio_stream_url, 2200) : '';
  const audioStartTime = audioProvider ? clampNumber(b.audio_start_time, 0, 60 * 60 * 6, 0) : 0;
  const audioDuration = audioProvider ? clampNumber(b.audio_duration, 5, 30, 15) : 0;

  if (audioProvider && !audioTrackId) {
    return c.json({ detail: 'Audio track id is required.' }, 400);
  }
  if (audioProvider) {
    const hidden = await c.env.DB.prepare("SELECT track_id FROM hidden_sounds WHERE provider = 'audius' AND track_id = ?")
      .bind(audioTrackId)
      .first();
    if (hidden) return c.json({ detail: 'This sound is unavailable.' }, 400);
  }
  const insertResults = await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT OR IGNORE INTO posts (
       id, user_id, title, content, image, images, media_types, media_backup_ids, media_dimensions, location,
       display_city, display_region, display_country, display_location_label, display_location_source, display_location_visibility,
       post_type,
       place_id, place_name, place_provider, place_provider_id, place_formatted_address, place_category, place_city, place_region, place_country,
       place_lat, place_lng, is_verified_checkin, visibility,
       editor_overlays, tagged_users,
       primary_category, category_confidence, category_source, category_status, category_signals_json, tags_json,
       audio_provider, audio_track_id, audio_title, audio_artist, audio_artwork_url, audio_stream_url,
       audio_start_time, audio_duration, client_request_id
     )
     VALUES (${Array(47).fill('?').join(', ')})`
    ).bind(id, userId, postTitle, postContent, primaryImage, JSON.stringify(imageUrls), JSON.stringify(mediaTypes),
    JSON.stringify(backupIds), JSON.stringify(mediaDimensions), location,
    displayCity, displayRegion, displayCountry, displayLocationLabel, displayLocationSource, displayLocationVisibility,
    postType,
    placeProviderId || null, placeName || null, placeProvider, placeProviderId, placeFormattedAddress, placeCategory, placeCity, placeRegion, placeCountry,
    placeLat, placeLng, isCheckin, visibility,
    JSON.stringify(editorOverlays), JSON.stringify(taggedUsers),
    autoCategory.primary_category, autoCategory.category_confidence, autoCategory.category_source, autoCategory.category_status, JSON.stringify(autoCategory.signals), JSON.stringify(autoCategory.tags),
    audioProvider, audioTrackId, audioTitle, audioArtist, audioArtworkUrl, audioStreamUrl, audioStartTime, audioDuration, clientRequestId),
    c.env.DB.prepare('UPDATE users SET posts_count = COALESCE(posts_count, 0) + 1 WHERE id = ? AND changes() > 0').bind(userId),
  ]);
  const inserted = d1Changes(insertResults?.[0]) > 0;
  if (!inserted && clientRequestId) {
    const existing: any = await c.env.DB.prepare(
      `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
       FROM posts p JOIN users u ON p.user_id = u.id
       WHERE p.user_id = ? AND p.client_request_id = ?
       LIMIT 1`
    ).bind(userId, clientRequestId).first();
    if (existing) return c.json({ ...postPayload(existing, [], c.env), idempotent_replay: true });
  }
  if (!inserted) return c.json({ detail: 'Could not create post. Please retry.' }, 409);
  if (placeName || placeFormattedAddress || placeProviderId) {
    await c.env.DB.prepare(
      `INSERT OR REPLACE INTO post_places
       (id, post_id, provider, provider_place_id, name, formatted_address, latitude, longitude, category, city, region, country, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      uuid(), id, placeProvider || 'apple_mapkit', placeProviderId, placeName, placeFormattedAddress,
      placeLat, placeLng, placeCategory, placeCity, placeRegion, placeCountry, now()
    ).run();
  }
  await attachMediaBackupsToPost(c.env.DB, userId, id, backupIds);
  await recordAbuseSignals(c, userId, 'post_create', {
    product_links: editorOverlays.filter((item: any) => item?.type === 'product' && item.link).map((item: any) => item.link),
  });
  runBackgroundTask(c, 'supabase_post_write_through_failed', async () => {
    await mirrorLegacyUserToSupabase(c, userId);
    await mirrorLegacyPostToSupabase(c, id);
  });
  runBackgroundTask(c, 'post_category_refinement_failed', async () => {
    await refinePostCategoryWithBackendAi(c, id);
  });
  if (visibility === 'public' || visibility === 'followers') {
    runBackgroundTask(c, 'post_follower_notifications_failed', async () => {
      const followers = await c.env.DB.prepare(
        `SELECT follower_id
         FROM follows
         WHERE following_id = ? AND follower_id != ?
         ORDER BY created_at DESC
         LIMIT 250`
      ).bind(userId, userId).all();
      const authorName = cleanText(user?.full_name || user?.username || 'Someone you follow', 80);
      const body = cleanText(postTitle || postContent || 'Shared a new post', 120);
      await Promise.allSettled((followers.results as any[]).map((row) => insertNotificationOnce(c, {
        userId: cleanText(row.follower_id, 120),
        type: 'new_post',
        title: `${authorName} posted`,
        body,
        data: { post_id: id, from_user_id: userId },
        dedupeKey: `new_post:${id}:${row.follower_id}`,
        dedupeSeconds: 604800,
      })));
    });
  }
  const createdPost = { id, user_id: userId, user_username: user?.username, user_full_name: user?.full_name,
    user_profile_image: user?.profile_image, title: postTitle, content: postContent, image: primaryImage, images: imageUrls,
    media_types: mediaTypes, media_backup_ids: backupIds, media_dimensions: mediaDimensions, editor_overlays: editorOverlays, tagged_users: taggedUsers,
    primary_category: autoCategory.primary_category, category_confidence: autoCategory.category_confidence,
    category_source: autoCategory.category_source, category_status: autoCategory.category_status,
    category_signals_json: JSON.stringify(autoCategory.signals), tags_json: JSON.stringify(autoCategory.tags),
    location,
    display_city: displayCity, display_region: displayRegion, display_country: displayCountry,
    display_location_label: displayLocationLabel, display_location_source: displayLocationSource,
    display_location_visibility: displayLocationVisibility,
    post_type: postType, place_id: placeProviderId, place_name: placeName,
    place_provider: placeProvider, place_provider_id: placeProviderId, place_formatted_address: placeFormattedAddress,
    place_category: placeCategory, place_city: placeCity, place_region: placeRegion, place_country: placeCountry,
    place_lat: placeLat, place_lng: placeLng, is_verified_checkin: !!isCheckin,
    audio_provider: audioProvider, audio_track_id: audioTrackId, audio_title: audioTitle, audio_artist: audioArtist,
    audio_artwork_url: audioArtworkUrl, audio_stream_url: audioStreamUrl, audio_start_time: audioStartTime, audio_duration: audioDuration,
    client_request_id: clientRequestId, visibility, likes_count: 0, comments_count: 0, liked_by: [], created_at: now() };
  return c.json(postPayload(createdPost, [], c.env));
});

api.get('/posts/feed', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'feed_read', userId, 240, 60);
  if (limited) return limited;
  await ensurePrivacySchema(c.env.DB);
  await ensureGovernanceSchema(c.env.DB);
  await ensurePostEditorSchema(c.env.DB);
  await ensureLocationSchema(c.env.DB);
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '20', 1, 50, 20);
  const feedSql = [
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
       EXISTS (SELECT 1 FROM follows fl WHERE fl.follower_id = ? AND fl.following_id = p.user_id) AS is_following,
       EXISTS (SELECT 1 FROM likes lk WHERE lk.user_id = ? AND lk.post_id = p.id) AS is_liked,
       EXISTS (SELECT 1 FROM saved_posts sp WHERE sp.user_id = ? AND sp.post_id = p.id) AS saved,
       COALESCE(p.likes_count, 0) AS live_likes_count,
       COALESCE(p.comments_count, 0) AS live_comments_count,
       COALESCE(p.saves_count, 0) AS live_saves_count
     FROM posts p JOIN users u ON p.user_id = u.id`,
    `WHERE ${visiblePostWhere('u', 'p')}`,
    'ORDER BY p.created_at DESC LIMIT ? OFFSET ?',
  ].join(' ');
  const posts = await c.env.DB.prepare(feedSql).bind(userId, userId, userId, ...visiblePostBindValues(userId), limit, skip).all();
  const response = c.json((posts.results as any[]).map((p) => feedPostPayload(p, [], c.env)));
  response.headers.set('cache-control', 'private, max-age=6');
  return response;
});

api.get('/posts/world-board', async (c) => {
  try {
    await ensurePrivacySchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    await ensurePostEditorSchema(c.env.DB);
    await ensureLocationSchema(c.env.DB);
    const limited = await enforceRateLimit(c, 'public_world_board', clientIp(c), 180, 60);
    if (limited) return limited;
    const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
    const limit = clampNumber(c.req.query('limit') || '40', 1, 50, 40);
    const payload = await cachedJson(c, `posts:world-board:v8:${skip}:${limit}`, 8, async () => {
      const worldBoardSql = [
        `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
           COALESCE(p.likes_count, 0) AS live_likes_count,
           COALESCE(p.comments_count, 0) AS live_comments_count,
           0 AS live_saves_count
         FROM posts p JOIN users u ON p.user_id = u.id`,
        `WHERE ${publicPostWhere('u', 'p')}`,
        'ORDER BY p.created_at DESC LIMIT ? OFFSET ?',
      ].join(' ');
      const posts = await c.env.DB.prepare(worldBoardSql).bind(limit, skip).all();
      return (posts.results as any[]).map((p) => feedPostPayload(p, [], c.env));
    });
    const response = c.json(payload);
    response.headers.set('cache-control', 'public, max-age=4, s-maxage=8');
    return response;
  } catch {
    return c.json({ detail: 'Could not load world board.' }, 500);
  }
});

api.get('/posts/nearby-feed', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'nearby_feed_read', userId, 180, 60);
  if (limited) return limited;
  await ensurePrivacySchema(c.env.DB);
  await ensureGovernanceSchema(c.env.DB);
  await ensurePostEditorSchema(c.env.DB);
  await ensureLocationSchema(c.env.DB);
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '24', 1, 50, 24);
  const nearbyFeedSql = [
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
       COALESCE(p.likes_count, 0) AS live_likes_count,
       COALESCE(p.comments_count, 0) AS live_comments_count,
       COALESCE(p.saves_count, 0) AS live_saves_count
     FROM posts p JOIN users u ON p.user_id = u.id`,
    `WHERE ${visiblePostWhere('u', 'p')}`,
    'ORDER BY p.created_at DESC LIMIT ? OFFSET ?',
  ].join(' ');
  const posts = await c.env.DB.prepare(nearbyFeedSql).bind(...visiblePostBindValues(userId), limit, skip).all();
  const response = c.json((posts.results as any[]).map((p) => feedPostPayload(p, [], c.env)));
  response.headers.set('cache-control', 'private, max-age=6');
  return response;
});

api.get('/posts/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const postId = c.req.param('postId');
  await ensureLocationSchema(c.env.DB);
  const postByIdSql = [
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
       EXISTS (SELECT 1 FROM follows fl WHERE fl.follower_id = ? AND fl.following_id = p.user_id) AS is_following,
       EXISTS (SELECT 1 FROM likes lk WHERE lk.user_id = ? AND lk.post_id = p.id) AS is_liked,
       EXISTS (SELECT 1 FROM saved_posts sp WHERE sp.user_id = ? AND sp.post_id = p.id) AS saved,
       (SELECT COUNT(*) FROM likes lk_count WHERE lk_count.post_id = p.id) AS live_likes_count,
       (SELECT COUNT(*) FROM comments cm_count WHERE cm_count.post_id = p.id AND COALESCE(cm_count.status, 'active') NOT IN ('removed', 'hidden')) AS live_comments_count,
       (SELECT COUNT(*) FROM saved_posts sp_count WHERE sp_count.post_id = p.id) AS live_saves_count
     FROM posts p JOIN users u ON p.user_id = u.id`,
    `WHERE p.id = ? AND ${visiblePostWhere('u', 'p')}`,
  ].join(' ');
  const p: any = await c.env.DB.prepare(postByIdSql).bind(userId, userId, userId, postId, ...visiblePostBindValues(userId)).first();
  if (!p) return c.json({ detail: 'Post not found' }, 404);
  const likes = await c.env.DB.prepare('SELECT user_id FROM likes WHERE post_id = ?').bind(postId).all();
  return c.json(postPayload(p, likes.results.map((l: any) => l.user_id), c.env));
});

api.post('/posts/:postId/like', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  await ensureGovernanceSchema(c.env.DB);
  const limited = await enforceRateLimit(c, 'post_like', userId, 300, 60);
  if (limited) return limited;
  const body: any = await c.req.json().catch(() => ({}));
  const requested = optionalBoolean(body.liked ?? body.like ?? body.value);
  const likeVisiblePostSql = [
    'SELECT p.id, p.user_id FROM posts p JOIN users u ON p.user_id = u.id',
    `WHERE p.id = ? AND ${visiblePostWhere('u', 'p')}`,
  ].join(' ');
  const visiblePost = await c.env.DB.prepare(likeVisiblePostSql).bind(postId, ...visiblePostBindValues(userId)).first();
  if (!visiblePost) return c.json({ detail: 'Post not found' }, 404);

  let nextLiked = requested;
  if (nextLiked === null) {
    const ex = await c.env.DB.prepare('SELECT id FROM likes WHERE user_id = ? AND post_id = ?').bind(userId, postId).first();
    nextLiked = !ex;
  }

  let changed = false;
  if (nextLiked) {
    const result = await c.env.DB.prepare('INSERT OR IGNORE INTO likes (id, user_id, post_id) VALUES (?, ?, ?)')
      .bind(uuid(), userId, postId)
      .run();
    changed = d1Changes(result) > 0;
  } else {
    const result = await c.env.DB.prepare('DELETE FROM likes WHERE user_id = ? AND post_id = ?')
      .bind(userId, postId)
      .run();
    changed = d1Changes(result) > 0;
  }
  const engagement = await getPostEngagementState(c.env.DB, postId, userId);

  if (nextLiked && changed && (visiblePost as any).user_id !== userId) {
    try {
      const me: any = await c.env.DB.prepare('SELECT full_name FROM users WHERE id = ?').bind(userId).first();
      await insertNotificationOnce(c, {
        userId: (visiblePost as any).user_id,
        type: 'like',
        title: 'New Like',
        body: `${me?.full_name || 'Someone'} liked your post`,
        data: { post_id: postId, from_user_id: userId, actor_name: me?.full_name || 'Someone' },
        dedupeKey: `like:${userId}:${postId}`,
        dedupeSeconds: 86400,
      });
    } catch {}
  }
  if (changed) {
    runBackgroundTask(c, 'supabase_like_write_through_failed', async () => {
      await mirrorLegacyInteractionToSupabase(c, postId, userId, 'like', !!nextLiked);
    });
  }

  return c.json({
    liked: engagement.liked,
    likes_count: engagement.likes_count,
    comments_count: engagement.comments_count,
    saved: engagement.saved,
    saves_count: engagement.saves_count,
  });
});

api.delete('/posts/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  await ensureGovernanceSchema(c.env.DB);
  const post: any = await c.env.DB.prepare('SELECT user_id FROM posts WHERE id = ?').bind(postId).first();
  if (!post) return c.json({ detail: 'Post not found' }, 404);
  if (post.user_id !== userId) return c.json({ detail: 'Not your post' }, 403);
  await c.env.DB.prepare("UPDATE posts SET status = 'removed', removed_at = ?, removed_reason = 'Deleted by creator' WHERE id = ?")
    .bind(now(), postId).run();
  await c.env.DB.prepare('UPDATE users SET posts_count = MAX(0, posts_count - 1) WHERE id = ?').bind(userId).run();
  await logSecurityEvent(c, 'post_soft_deleted', userId, { post_id: postId });
  return c.json({ deleted: true, soft_deleted: true });
});

api.put('/posts/:postId/visibility', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const postId = c.req.param('postId');
  await ensurePrivacySchema(c.env.DB);
  const body: any = await c.req.json().catch(() => ({}));
  const requestedVisibility = typeof body.visibility === 'string' ? body.visibility.trim().toLowerCase() : '';
  if (!['public', 'followers', 'friends', 'private'].includes(requestedVisibility)) {
    return c.json({ detail: 'Invalid visibility.' }, 400);
  }
  const visibility = normalizeVisibility(requestedVisibility);

  const post: any = await c.env.DB.prepare(
    "SELECT id, user_id FROM posts WHERE id = ? AND COALESCE(status, 'active') != 'removed'"
  ).bind(postId).first();
  if (!post) return c.json({ detail: 'Post not found' }, 404);
  if (post.user_id !== userId) return c.json({ detail: 'Not your post' }, 403);

  await c.env.DB.prepare('UPDATE posts SET visibility = ? WHERE id = ?').bind(visibility, postId).run();
  await logSecurityEvent(c, 'post_visibility_updated', userId, { post_id: postId, visibility });

  const updated: any = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
       EXISTS (SELECT 1 FROM follows fl WHERE fl.follower_id = ? AND fl.following_id = p.user_id) AS is_following,
       EXISTS (SELECT 1 FROM likes lk WHERE lk.user_id = ? AND lk.post_id = p.id) AS is_liked,
       EXISTS (SELECT 1 FROM saved_posts sp WHERE sp.user_id = ? AND sp.post_id = p.id) AS saved,
       (SELECT COUNT(*) FROM likes lk_count WHERE lk_count.post_id = p.id) AS live_likes_count,
       (SELECT COUNT(*) FROM comments cm_count WHERE cm_count.post_id = p.id AND COALESCE(cm_count.status, 'active') NOT IN ('removed', 'hidden')) AS live_comments_count,
       (SELECT COUNT(*) FROM saved_posts sp_count WHERE sp_count.post_id = p.id) AS live_saves_count
     FROM posts p JOIN users u ON p.user_id = u.id
     WHERE p.id = ?`
  ).bind(userId, userId, userId, postId).first();
  if (!updated) return c.json({ detail: 'Post not found' }, 404);

  return c.json(postPayload(updated, [], c.env));
});

api.put('/posts/:postId/pin', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const postId = c.req.param('postId');
  await ensurePrivacySchema(c.env.DB);
  const body: any = await c.req.json().catch(() => ({}));
  const requested = optionalBoolean(body.pinned ?? body.pin ?? body.value);
  const shouldPin = requested === null ? true : requested;

  const post: any = await c.env.DB.prepare(
    "SELECT id, user_id FROM posts WHERE id = ? AND COALESCE(status, 'active') != 'removed'"
  ).bind(postId).first();
  if (!post) return c.json({ detail: 'Post not found' }, 404);
  if (post.user_id !== userId) return c.json({ detail: 'Not your post' }, 403);

  const pinnedAt = shouldPin ? now() : null;
  await c.env.DB.prepare('UPDATE posts SET pinned_at = ? WHERE id = ? AND user_id = ?')
    .bind(pinnedAt, postId, userId)
    .run();
  await logSecurityEvent(c, shouldPin ? 'post_pinned' : 'post_unpinned', userId, { post_id: postId });

  const updated: any = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
       EXISTS (SELECT 1 FROM follows fl WHERE fl.follower_id = ? AND fl.following_id = p.user_id) AS is_following,
       EXISTS (SELECT 1 FROM likes lk WHERE lk.user_id = ? AND lk.post_id = p.id) AS is_liked,
       EXISTS (SELECT 1 FROM saved_posts sp WHERE sp.user_id = ? AND sp.post_id = p.id) AS saved,
       (SELECT COUNT(*) FROM likes lk_count WHERE lk_count.post_id = p.id) AS live_likes_count,
       (SELECT COUNT(*) FROM comments cm_count WHERE cm_count.post_id = p.id AND COALESCE(cm_count.status, 'active') NOT IN ('removed', 'hidden')) AS live_comments_count,
       (SELECT COUNT(*) FROM saved_posts sp_count WHERE sp_count.post_id = p.id) AS live_saves_count
     FROM posts p JOIN users u ON p.user_id = u.id
     WHERE p.id = ?`
  ).bind(userId, userId, userId, postId).first();
  if (!updated) return c.json({ detail: 'Post not found' }, 404);

  return c.json(postPayload(updated, [], c.env));
});

api.get('/users/:userId/posts', authMiddleware, async (c) => {
  const viewerId = getUserId(c);
  const targetId = c.req.param('userId');
  await ensurePrivacySchema(c.env.DB);
  await ensureGovernanceSchema(c.env.DB);
  await ensurePostEditorSchema(c.env.DB);
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '60', 1, 100, 60);
  const owner: any = await c.env.DB.prepare('SELECT id, is_private FROM users WHERE id = ?').bind(targetId).first();
  if (!owner) return c.json({ detail: 'User not found' }, 404);
  if (!(await canViewUserContent(c.env.DB, viewerId, owner))) return c.json([]);
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
       EXISTS (SELECT 1 FROM likes lk WHERE lk.user_id = ? AND lk.post_id = p.id) AS is_liked,
       EXISTS (SELECT 1 FROM saved_posts sp WHERE sp.user_id = ? AND sp.post_id = p.id) AS saved,
       (SELECT COUNT(*) FROM likes lk_count WHERE lk_count.post_id = p.id) AS live_likes_count,
       (SELECT COUNT(*) FROM comments cm_count WHERE cm_count.post_id = p.id AND COALESCE(cm_count.status, 'active') NOT IN ('removed', 'hidden')) AS live_comments_count,
       (SELECT COUNT(*) FROM saved_posts sp_count WHERE sp_count.post_id = p.id) AS live_saves_count
     FROM posts p JOIN users u ON p.user_id = u.id
     WHERE p.user_id = ? AND COALESCE(p.status, 'active') != 'removed' AND (
       COALESCE(p.visibility, 'public') = 'public'
       OR p.user_id = ?
       OR (COALESCE(p.visibility, 'public') = 'followers' AND (
         EXISTS (SELECT 1 FROM follows fl WHERE fl.follower_id = ? AND fl.following_id = p.user_id)
         OR EXISTS (SELECT 1 FROM friendships f2 WHERE f2.user_id = ? AND f2.friend_id = p.user_id)
       ))
       OR (COALESCE(p.visibility, 'public') = 'friends' AND EXISTS (SELECT 1 FROM friendships f3 WHERE f3.user_id = ? AND f3.friend_id = p.user_id))
     )
      ORDER BY p.pinned_at IS NULL, p.pinned_at DESC, p.created_at DESC
      LIMIT ? OFFSET ?`
  ).bind(viewerId, viewerId, targetId, viewerId, viewerId, viewerId, viewerId, limit, skip).all();
  return c.json((posts.results as any[]).map((p) => feedPostPayload(p, [], c.env)));
});

// Comments
api.post('/posts/:postId/comments', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 100_000);
    if (bodyTooLarge) return bodyTooLarge;
    await ensurePrivacySchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    await ensureCommentSchema(c.env.DB);
    await ensureReliabilitySchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'comment_create', userId, 40, 60);
    if (limited) return limited;
    const restricted = await enforceUserRestriction(c, userId, 'commenting');
    if (restricted) return restricted;
    const postId = c.req.param('postId');
    const body: any = await c.req.json().catch(() => ({}));
    const content = cleanMultilineText(body.content, 1200);
    const parentId = body.parent_id ? publicId(body.parent_id, 120) : null;
    const clientRequestId = getClientRequestId(c, body);
    if (!content) return c.json({ detail: 'Comment cannot be empty.' }, 400);
    if (content.length > 1200) return c.json({ detail: 'Comment is too long.' }, 400);

    const commentVisiblePostSql = [
      'SELECT p.id, p.user_id FROM posts p JOIN users u ON p.user_id = u.id',
      `WHERE p.id = ? AND ${visiblePostWhere('u', 'p')}`,
    ].join(' ');
    const visiblePost: any = await c.env.DB.prepare(commentVisiblePostSql).bind(postId, ...visiblePostBindValues(userId)).first();
    if (!visiblePost) return c.json({ detail: 'Post not found' }, 404);

    let parent: any = null;
    if (parentId) {
      parent = await c.env.DB.prepare("SELECT id, user_id FROM comments WHERE id = ? AND post_id = ? AND COALESCE(status, 'active') NOT IN ('removed', 'hidden')")
        .bind(parentId, postId)
        .first();
      if (!parent) return c.json({ detail: 'Comment to reply to was not found.' }, 404);
    }

    const recentDuplicate: any = await c.env.DB.prepare(
      "SELECT id FROM comments WHERE user_id = ? AND post_id = ? AND content = ? AND created_at > datetime('now', '-30 seconds') LIMIT 1"
    ).bind(userId, postId, content).first();
    if (recentDuplicate) {
      await logSecurityEvent(c, 'duplicate_comment_blocked', userId, { post_id: postId });
      return c.json({ detail: 'You already posted that comment. Try again in a moment.' }, 429);
    }

    const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image FROM users WHERE id = ?').bind(userId).first();
    const id = uuid();
    const createdAt = now();
    const insertResult = await c.env.DB.prepare('INSERT OR IGNORE INTO comments (id, user_id, post_id, parent_id, content, client_request_id) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(id, userId, postId, parentId, content, clientRequestId)
      .run();
    const inserted = d1Changes(insertResult) > 0;
    if (!inserted && clientRequestId) {
      const existing: any = await c.env.DB.prepare(
        `SELECT c.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
                CASE WHEN cl.id IS NULL THEN 0 ELSE 1 END AS liked_by_me
         FROM comments c
         JOIN users u ON c.user_id = u.id
         LEFT JOIN comment_likes cl ON cl.comment_id = c.id AND cl.user_id = ?
         WHERE c.user_id = ? AND c.client_request_id = ?
         LIMIT 1`
      ).bind(userId, userId, clientRequestId).first();
      if (existing) return c.json({
        ...existing,
        user_username: publicUsernameFor({ username: existing.user_username }),
        user_profile_image: safeMediaReference(existing.user_profile_image),
        liked_by_me: !!existing.liked_by_me,
        idempotent_replay: true,
      });
    }
    if (!inserted) return c.json({ detail: 'Could not post comment. Please retry.' }, 409);
    const engagement = await getPostEngagementState(c.env.DB, postId, userId);

    try {
      const notifyUserId = parent?.user_id && parent.user_id !== userId ? parent.user_id : visiblePost.user_id;
      if (notifyUserId && notifyUserId !== userId) {
        await insertNotificationOnce(c, {
          userId: notifyUserId,
          type: parentId ? 'comment_reply' : 'comment',
          title: parentId ? 'New Reply' : 'New Comment',
          body: `${user?.full_name || 'Someone'} ${parentId ? 'replied to your comment' : 'commented on your post'}`,
          data: { post_id: postId, comment_id: id, parent_id: parentId, from_user_id: userId, actor_name: user?.full_name || 'Someone' },
          dedupeKey: `comment:${userId}:${postId}:${parentId || 'root'}:${content.slice(0, 80)}`,
          dedupeSeconds: 300,
        });
      }
    } catch {}

    runBackgroundTask(c, 'supabase_comment_write_through_failed', async () => {
      await mirrorLegacyCommentToSupabase(c, id);
      await mirrorLegacyPostToSupabase(c, postId);
    });

    return c.json({
      id,
      user_id: userId,
      post_id: postId,
      post_user_id: visiblePost.user_id,
      parent_id: parentId,
      content,
      client_request_id: clientRequestId,
      likes_count: 0,
      post_comments_count: engagement.comments_count,
      liked_by_me: false,
      pinned_at: null,
      is_pinned: false,
      user_username: publicUsernameFor(user),
      user_full_name: user?.full_name,
      user_profile_image: safeMediaReference(user?.profile_image),
      created_at: createdAt,
    });
  } catch (error: any) {
    console.error('Comment create failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not post comment.', code: 'COMMENT_CREATE_FAILED' }, 500);
  }
});

api.get('/posts/:postId/comments', authMiddleware, async (c) => {
  try {
    await ensurePrivacySchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    await ensureCommentSchema(c.env.DB);
    const userId = getUserId(c);
    const limit = clampNumber(c.req.query('limit') || '80', 1, 100, 80);
    const commentsSql = [
      `SELECT c.*, p.user_id AS post_user_id, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
              CASE WHEN c.pinned_at IS NULL THEN 0 ELSE 1 END AS is_pinned,
              CASE WHEN cl.id IS NULL THEN 0 ELSE 1 END AS liked_by_me
       FROM comments c
       JOIN posts p ON c.post_id = p.id
       JOIN users owner ON p.user_id = owner.id
       JOIN users u ON c.user_id = u.id
       LEFT JOIN comment_likes cl ON cl.comment_id = c.id AND cl.user_id = ?
       WHERE c.post_id = ? AND COALESCE(c.status, 'active') NOT IN ('removed', 'hidden')`,
      `AND ${visiblePostWhere('owner', 'p')}`,
      'ORDER BY c.pinned_at IS NULL, c.pinned_at DESC, COALESCE(c.parent_id, c.id), c.parent_id IS NOT NULL, c.created_at ASC',
      'LIMIT ?',
    ].join(' ');
    const r = await c.env.DB.prepare(commentsSql).bind(userId, c.req.param('postId'), ...visiblePostBindValues(userId), limit).all();

    return c.json((r.results as any[]).map((comment) => ({
      ...comment,
      user_username: publicUsernameFor({ username: comment.user_username }),
      user_profile_image: safeMediaReference(comment.user_profile_image),
      likes_count: Number(comment.likes_count || 0),
      is_pinned: !!comment.is_pinned,
      liked_by_me: !!comment.liked_by_me,
    })));
  } catch (error: any) {
    console.error('Comment load failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load comments.' }, 500);
  }
});

api.post('/comments/:commentId/like', authMiddleware, async (c) => {
  try {
    await ensurePrivacySchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    await ensureCommentSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'comment_like', userId, 300, 60);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const requested = optionalBoolean(body.liked ?? body.like ?? body.value);
    const commentId = c.req.param('commentId');
    const visibleCommentSql = [
      `SELECT c.id, c.likes_count
       FROM comments c
       JOIN posts p ON c.post_id = p.id
       JOIN users owner ON p.user_id = owner.id
       WHERE c.id = ? AND COALESCE(c.status, 'active') NOT IN ('removed', 'hidden')`,
      `AND ${visiblePostWhere('owner', 'p')}`,
    ].join(' ');
    const comment: any = await c.env.DB.prepare(visibleCommentSql).bind(commentId, ...visiblePostBindValues(userId)).first();
    if (!comment) return c.json({ detail: 'Comment not found' }, 404);

    let nextLiked = requested;
    if (nextLiked === null) {
      const existing: any = await c.env.DB.prepare('SELECT id FROM comment_likes WHERE user_id = ? AND comment_id = ?')
        .bind(userId, commentId)
        .first();
      nextLiked = !existing;
    }

    let likesCount = 0;
    if (nextLiked) {
      const results = await c.env.DB.batch([
        c.env.DB.prepare('INSERT OR IGNORE INTO comment_likes (id, user_id, comment_id) VALUES (?, ?, ?)')
          .bind(uuid(), userId, commentId),
        c.env.DB.prepare('UPDATE comments SET likes_count = COALESCE(likes_count, 0) + 1 WHERE id = ? AND changes() > 0')
          .bind(commentId),
        c.env.DB.prepare('SELECT likes_count FROM comments WHERE id = ?').bind(commentId),
      ]);
      likesCount = Number((results?.[2] as any)?.results?.[0]?.likes_count || 0);
    } else {
      const results = await c.env.DB.batch([
        c.env.DB.prepare('DELETE FROM comment_likes WHERE user_id = ? AND comment_id = ?')
          .bind(userId, commentId),
        c.env.DB.prepare('UPDATE comments SET likes_count = MAX(0, COALESCE(likes_count, 0) - 1) WHERE id = ? AND changes() > 0')
          .bind(commentId),
        c.env.DB.prepare('SELECT likes_count FROM comments WHERE id = ?').bind(commentId),
      ]);
      likesCount = Number((results?.[2] as any)?.results?.[0]?.likes_count || 0);
    }

    return c.json({ liked: !!nextLiked, likes_count: likesCount });
  } catch (error: any) {
    console.error('Comment like failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not update comment like.' }, 500);
  }
});

api.post('/comments/:commentId/pin', authMiddleware, async (c) => {
  try {
    await ensurePrivacySchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    await ensureCommentSchema(c.env.DB);
    const userId = getUserId(c);
    const commentId = c.req.param('commentId');
    const body: any = await c.req.json().catch(() => ({}));
    const requested = optionalBoolean(body.pinned ?? body.pin ?? body.value);
    const shouldPin = requested === null ? true : requested;
    const comment: any = await c.env.DB.prepare(
      `SELECT c.id, c.post_id, c.pinned_at, p.user_id AS post_user_id
       FROM comments c
       JOIN posts p ON c.post_id = p.id
       WHERE c.id = ? AND COALESCE(c.status, 'active') NOT IN ('removed', 'hidden')`
    ).bind(commentId).first();
    if (!comment) return c.json({ detail: 'Comment not found' }, 404);
    if (comment.post_user_id !== userId) return c.json({ detail: 'Only the creator can pin comments.' }, 403);

    const pinnedAt = shouldPin ? now() : null;
    if (shouldPin) {
      await c.env.DB.batch([
        c.env.DB.prepare('UPDATE comments SET pinned_at = NULL WHERE post_id = ?').bind(comment.post_id),
        c.env.DB.prepare('UPDATE comments SET pinned_at = ? WHERE id = ?').bind(pinnedAt, commentId),
      ]);
    } else {
      await c.env.DB.prepare('UPDATE comments SET pinned_at = NULL WHERE id = ?').bind(commentId).run();
    }
    await logSecurityEvent(c, shouldPin ? 'comment_pinned' : 'comment_unpinned', userId, { comment_id: commentId, post_id: comment.post_id });
    return c.json({ pinned: shouldPin, pinned_at: pinnedAt });
  } catch (error: any) {
    console.error('Comment pin failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not update pinned comment.' }, 500);
  }
});

api.delete('/comments/:commentId', authMiddleware, async (c) => {
  try {
    await ensurePrivacySchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    await ensureCommentSchema(c.env.DB);
    const userId = getUserId(c);
    const commentId = c.req.param('commentId');
    const comment: any = await c.env.DB.prepare(
      `SELECT c.id, c.user_id, c.post_id
       FROM comments c
       WHERE c.id = ? AND COALESCE(c.status, 'active') NOT IN ('removed', 'hidden')`
    ).bind(commentId).first();
    if (!comment) return c.json({ detail: 'Comment not found' }, 404);
    if (comment.user_id !== userId) return c.json({ detail: 'Not your comment' }, 403);

    await c.env.DB.prepare("UPDATE comments SET status = 'removed', removed_at = ?, removed_reason = 'Deleted by commenter', pinned_at = NULL WHERE id = ?")
      .bind(now(), commentId)
      .run();
    const engagement = await getPostEngagementState(c.env.DB, comment.post_id, userId);
    await logSecurityEvent(c, 'comment_deleted', userId, { comment_id: commentId, post_id: comment.post_id });
    return c.json({ deleted: true, comments_count: engagement.comments_count });
  } catch (error: any) {
    console.error('Comment delete failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not delete comment.' }, 500);
  }
});

api.post('/comments/:commentId/hide', authMiddleware, async (c) => {
  try {
    await ensurePrivacySchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    await ensureCommentSchema(c.env.DB);
    const userId = getUserId(c);
    const commentId = c.req.param('commentId');
    const comment: any = await c.env.DB.prepare(
      `SELECT c.id, c.post_id, p.user_id AS post_user_id
       FROM comments c
       JOIN posts p ON c.post_id = p.id
       WHERE c.id = ? AND COALESCE(c.status, 'active') NOT IN ('removed', 'hidden')`
    ).bind(commentId).first();
    if (!comment) return c.json({ detail: 'Comment not found' }, 404);
    if (comment.post_user_id !== userId) return c.json({ detail: 'Only the creator can hide comments.' }, 403);

    await c.env.DB.prepare("UPDATE comments SET status = 'hidden', hidden_at = ?, hidden_by_user_id = ?, removed_reason = 'Hidden by creator', pinned_at = NULL WHERE id = ?")
      .bind(now(), userId, commentId)
      .run();
    const engagement = await getPostEngagementState(c.env.DB, comment.post_id, userId);
    await logSecurityEvent(c, 'comment_hidden', userId, { comment_id: commentId, post_id: comment.post_id });
    return c.json({ hidden: true, comments_count: engagement.comments_count });
  } catch (error: any) {
    console.error('Comment hide failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not hide comment.' }, 500);
  }
});

// Statuses
function groupStatusRows(rows: any[], viewerId: string) {
  const grouped = new Map<string, any>();
  for (const s of rows) {
    const uid = s.user_id;
    if (!grouped.has(uid)) {
      grouped.set(uid, {
        user_id: uid,
        user_username: publicUsernameFor({ username: s.user_username }),
        user_full_name: s.user_full_name,
        user_profile_image: s.user_profile_image,
        statuses: [],
        has_unviewed: false,
      });
    }
    const parsed = { ...s, viewed_by: JSON.parse(s.viewed_by || '[]') };
    grouped.get(uid)!.statuses.push(parsed);
    if (!parsed.viewed_by.includes(viewerId)) {
      grouped.get(uid)!.has_unviewed = true;
    }
  }
  return Array.from(grouped.values());
}

api.post('/statuses', authMiddleware, async (c) => {
  const phoneGate = await requirePhoneVerified(c, 'share stories');
  if (phoneGate) return phoneGate;
  await ensureAudioSchema(c.env.DB);
  const userId = getUserId(c); const b = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image, city FROM users WHERE id = ?').bind(userId).first();
  const storyLifetimeMs = 7 * 24 * 60 * 60 * 1000;
  const id = uuid(); const expiresAt = new Date(Date.now() + storyLifetimeMs).toISOString();
  const visibility = normalizeVisibility(b.visibility);
  const audioProvider = b.audio_provider === 'audius' ? 'audius' : '';
  const audioTrackId = audioProvider ? cleanText(b.audio_track_id, 80) : '';
  const audioTitle = audioProvider ? cleanText(b.audio_title, 180) : '';
  const audioArtist = audioProvider ? cleanText(b.audio_artist, 120) : '';
  const audioArtworkUrl = audioProvider ? cleanText(b.audio_artwork_url, 1000) : '';
  const audioStreamUrl = audioProvider ? cleanText(b.audio_stream_url, 2200) : '';
  const audioStartTime = audioProvider ? clampNumber(b.audio_start_time, 0, 60 * 60 * 6, 0) : 0;
  const audioDuration = audioProvider ? clampNumber(b.audio_duration, 5, 30, 15) : 0;
  if (audioProvider && !audioTrackId) {
    return c.json({ detail: 'Audio track id is required.' }, 400);
  }
  if (audioProvider) {
    const hidden = await c.env.DB.prepare("SELECT track_id FROM hidden_sounds WHERE provider = 'audius' AND track_id = ?")
      .bind(audioTrackId)
      .first();
    if (hidden) return c.json({ detail: 'This sound is unavailable.' }, 400);
  }
  await c.env.DB.prepare(
    `INSERT INTO statuses (
      id, user_id, content, image, background_color, text_color, visibility, expires_at,
      audio_provider, audio_track_id, audio_title, audio_artist, audio_artwork_url, audio_stream_url,
      audio_start_time, audio_duration
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(
      id, userId, b.content || '', b.image || null, b.background_color || '#1B4332', b.text_color || '#FFFFFF', visibility, expiresAt,
      audioProvider, audioTrackId, audioTitle, audioArtist, audioArtworkUrl, audioStreamUrl, audioStartTime, audioDuration
    ).run();
  return c.json({
    id, user_id: userId, content: b.content, image: b.image, background_color: b.background_color, text_color: b.text_color,
    visibility, user_username: publicUsernameFor(user), user_full_name: user?.full_name, user_profile_image: user?.profile_image,
    audio_provider: audioProvider, audio_track_id: audioTrackId, audio_title: audioTitle, audio_artist: audioArtist,
    audio_artwork_url: audioArtworkUrl, audio_stream_url: audioStreamUrl, audio_start_time: audioStartTime, audio_duration: audioDuration,
    viewed_by: [], created_at: now(), expires_at: expiresAt,
  });
});

api.get('/statuses', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const statusesSql = [
    'SELECT s.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image',
    'FROM statuses s JOIN users u ON s.user_id = u.id',
    `WHERE s.created_at >= datetime('now', '-7 days') AND ${visibleStatusWhere('u', 's')}`,
    'ORDER BY s.created_at DESC',
  ].join(' ');
  const r = await c.env.DB.prepare(statusesSql).bind(userId, userId).all();
  return c.json(groupStatusRows(r.results as any[], userId));
});

api.get('/statuses/friends', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const r = await c.env.DB.prepare(
    `SELECT s.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM statuses s JOIN users u ON s.user_id = u.id
     WHERE s.created_at >= datetime('now', '-7 days')
       AND s.user_id != ?
       AND COALESCE(s.visibility, 'public') != 'private'
       AND EXISTS (SELECT 1 FROM friendships f WHERE f.user_id = ? AND f.friend_id = s.user_id)
     ORDER BY s.created_at DESC`
  ).bind(userId, userId).all();
  return c.json(groupStatusRows(r.results as any[], userId));
});

api.post('/statuses/:statusId/view', authMiddleware, async (c) => {
  const userId = getUserId(c); const statusId = c.req.param('statusId');
  const statusViewSql = [
    'SELECT s.viewed_by FROM statuses s JOIN users u ON s.user_id = u.id',
    `WHERE s.id = ? AND ${visibleStatusWhere('u', 's')}`,
  ].join(' ');
  const s: any = await c.env.DB.prepare(statusViewSql).bind(statusId, userId, userId).first();
  if (!s) return c.json({ detail: 'Not found' }, 404);
  const vb: string[] = JSON.parse(s.viewed_by || '[]');
  if (!vb.includes(userId)) { vb.push(userId); await c.env.DB.prepare('UPDATE statuses SET viewed_by = ? WHERE id = ?').bind(JSON.stringify(vb), statusId).run(); }
  return c.json({ viewed: true });
});

api.delete('/statuses/:statusId', authMiddleware, async (c) => {
  const userId = getUserId(c); const statusId = c.req.param('statusId');
  const story: any = await c.env.DB.prepare('SELECT user_id FROM statuses WHERE id = ?').bind(statusId).first();
  if (!story) return c.json({ detail: 'Story not found' }, 404);
  if (story.user_id !== userId) return c.json({ detail: 'Not your story' }, 403);
  await c.env.DB.prepare('DELETE FROM statuses WHERE id = ? AND user_id = ?').bind(statusId, userId).run();
  await logSecurityEvent(c, 'story_deleted', userId, { status_id: statusId });
  return c.json({ deleted: true });
});

// Messages (with media support)
async function requireGroupMember(c: any, groupId: string, userId: string) {
  const member = await c.env.DB.prepare('SELECT id FROM group_chat_members WHERE group_id = ? AND user_id = ?')
    .bind(groupId, userId)
    .first();
  return !!member;
}

api.get('/conversations', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await touchUserPresence(c.env.DB, userId);
  await ensureAbuseProtectionSchema(c.env.DB);
  const limit = clampNumber(c.req.query('limit') || '60', 1, 100, 60);
  const msgs = await c.env.DB.prepare(`
    WITH ranked_messages AS (
      SELECT
        m.*,
        CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END AS other_id,
        ROW_NUMBER() OVER (
          PARTITION BY CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END
          ORDER BY datetime(m.created_at) DESC
        ) AS rn
      FROM messages m
      WHERE (m.sender_id = ? OR m.receiver_id = ?)
    )
    SELECT
      m.*,
      u.username,
      u.full_name,
      u.profile_image,
      up.last_seen_at AS other_last_seen_at,
      EXISTS (
        SELECT 1 FROM message_typing mt
        WHERE mt.user_id = u.id
          AND mt.peer_id = ?
          AND mt.is_typing = 1
          AND datetime(mt.updated_at) > datetime('now', '-10 seconds')
      ) AS other_is_typing
      ,
      (SELECT COUNT(*)
       FROM messages unread
       WHERE unread.sender_id = u.id
         AND unread.receiver_id = ?
         AND unread.is_read = 0) AS unread_total
    FROM ranked_messages m
    JOIN users u ON m.other_id = u.id
    LEFT JOIN user_presence up ON up.user_id = u.id
    WHERE m.rn = 1
      AND NOT EXISTS (
        SELECT 1 FROM blocks b
        WHERE (b.blocker_id = ? AND b.blocked_id = u.id)
           OR (b.blocker_id = u.id AND b.blocked_id = ?)
      )
    ORDER BY m.created_at DESC
    LIMIT ?
  `).bind(userId, userId, userId, userId, userId, userId, userId, userId, limit).all();
  const map = new Map<string, any>();
  for (const m of msgs.results as any[]) {
    const oid = m.sender_id === userId ? m.receiver_id : m.sender_id;
    if (!map.has(oid)) {
      let preview = m.content || '';
      if (!preview && m.media_type === 'video') preview = 'Sent a video';
      else if (!preview && m.media_type === 'voice') preview = 'Sent a voice message';
      else if (!preview && m.media_type === 'file') preview = 'Sent a file';
      else if (!preview && (m.media_url || m.image)) preview = 'Sent a photo';
      map.set(oid, {
        id: `conv-${oid}`,
        participants: [userId, oid],
        other_user: {
          id: oid,
          username: m.username,
          full_name: m.full_name,
          profile_image: safeMediaReference(m.profile_image),
          last_seen_at: m.other_last_seen_at || null,
          is_online: isPresenceOnline(m.other_last_seen_at),
          is_typing: Number(m.other_is_typing || 0) > 0,
        },
        last_message: preview,
        last_message_time: m.created_at,
        unread_count: Number(m.unread_total || 0),
      });
    }
  }
  const directConversations = Array.from(map.values());

  let groupConversations: any[] = [];
  try {
    const groups = await c.env.DB.prepare(`
      SELECT
        g.id,
        g.name,
        g.created_at,
        COUNT(all_members.user_id) AS member_count,
        last_message.content AS last_message,
        last_message.media_url AS last_media_url,
        last_message.media_type AS last_media_type,
        last_message.created_at AS last_message_time,
        sender.username AS last_sender_username
      FROM group_chats g
      JOIN group_chat_members my_membership ON my_membership.group_id = g.id AND my_membership.user_id = ?
      LEFT JOIN group_chat_members all_members ON all_members.group_id = g.id
      LEFT JOIN group_messages last_message ON last_message.id = (
        SELECT id FROM group_messages WHERE group_id = g.id ORDER BY created_at DESC LIMIT 1
      )
      LEFT JOIN users sender ON sender.id = last_message.sender_id
      GROUP BY g.id
      ORDER BY COALESCE(last_message.created_at, g.created_at) DESC
      LIMIT ?
    `).bind(userId, limit).all();

    groupConversations = (groups.results as any[]).map((g) => ({
      id: `group-${g.id}`,
      type: 'group',
      group_id: g.id,
      group_name: g.name,
      member_count: Number(g.member_count || 0),
      last_message: (() => {
        const sender = g.last_sender_username || 'Someone';
        if (g.last_message) return `${sender}: ${g.last_message}`;
        if (g.last_media_type === 'video') return `${sender}: Sent a video`;
        if (g.last_media_type === 'voice') return `${sender}: Sent a voice message`;
        if (g.last_media_type === 'file') return `${sender}: Sent a file`;
        if (g.last_media_url) return `${sender}: Sent a photo`;
        return 'Group created';
      })(),
      last_message_time: g.last_message_time || g.created_at,
      unread_count: 0,
    }));
  } catch {
    groupConversations = [];
  }

  return c.json([...directConversations, ...groupConversations].sort((a, b) => Date.parse(b.last_message_time || '') - Date.parse(a.last_message_time || '')));
});

api.post('/presence/touch', authMiddleware, async (c) => {
  await touchUserPresence(c.env.DB, getUserId(c));
  return c.json({ ok: true, touched_at: now() });
});

api.post('/messages', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await touchUserPresence(c.env.DB, userId);
  const limited = await enforceRateLimit(c, 'message_send', userId, 45, 60);
  if (limited) return limited;
  const dailyLimited = await enforceRateLimit(c, 'message_send_daily', userId, 600, 86400);
  if (dailyLimited) return dailyLimited;
  const restricted = await enforceUserRestriction(c, userId, 'messaging');
  if (restricted) return restricted;
  const bodyTooLarge = rejectLargeRequest(c, 120_000);
  if (bodyTooLarge) return bodyTooLarge;
  const b = await c.req.json().catch(() => ({}));
  const unknown = rejectUnknownFields(c, b, ['receiver_id', 'receiverId', 'content', 'media_url', 'mediaUrl', 'media_type', 'mediaType', 'client_request_id', 'clientRequestId', 'idempotency_key', 'request_id']);
  if (unknown) return unknown;
  const receiverId = publicId(b.receiver_id || b.receiverId, 120);
  const content = cleanMultilineText(b.content, 2000);
  const mediaUrl = normalizedMediaReferenceForStorage(c, safeMediaReference(b.media_url || b.mediaUrl));
  const requestedMediaType = String(b.media_type || b.mediaType || '').toLowerCase();
  const mediaType = requestedMediaType.includes('video')
    ? 'video'
    : requestedMediaType.includes('voice') || requestedMediaType.includes('audio')
      ? 'voice'
      : requestedMediaType.includes('file') || requestedMediaType.includes('document')
        ? 'file'
        : mediaUrl ? 'image' : null;
  const invalidPeer = await validateDirectMessagePeer(c, userId, receiverId);
  if (invalidPeer) return invalidPeer;
  if (!content && !mediaUrl) return c.json({ detail: 'Message is empty.' }, 400);
  if (content && !mediaUrl) {
    const recentDuplicate: any = await c.env.DB.prepare(
      "SELECT id FROM messages WHERE sender_id = ? AND receiver_id = ? AND content = ? AND created_at > datetime('now', '-30 seconds') LIMIT 1"
    ).bind(userId, receiverId, content).first();
    if (recentDuplicate) {
      await logSecurityEvent(c, 'duplicate_message_blocked', userId, { receiver_id: receiverId });
      return c.json({ detail: 'You already sent that message. Try again in a moment.' }, 429);
    }
  }
  const id = uuid();
  await c.env.DB.prepare('INSERT INTO messages (id, sender_id, receiver_id, content, media_url, media_type) VALUES (?, ?, ?, ?, ?, ?)').bind(id, userId, receiverId, content, mediaUrl || null, mediaType).run();
  await attachMediaBackupToMessage(c.env.DB, userId, id, mediaUrl, 'message_id');
  runBackgroundTask(c, 'message_notification_failed', async () => {
    const sender: any = await c.env.DB.prepare('SELECT username, full_name FROM users WHERE id = ?').bind(userId).first();
    const senderName = cleanText(sender?.full_name || sender?.username || 'Someone', 80);
    const privatePreview = mediaType === 'voice'
      ? 'Sent you a voice message'
      : mediaType === 'video'
        ? 'Sent you a video'
        : mediaType === 'file'
          ? 'Sent you a file'
        : mediaUrl
          ? 'Sent you a photo'
          : 'Sent you a message';
    await insertNotificationOnce(c, {
      userId: receiverId,
      type: 'message',
      title: `${senderName} messaged you`,
      body: privatePreview,
      data: { sender_id: userId, conversation_id: userId, message_id: id, actor_name: senderName },
      dedupeKey: `message:${id}`,
      dedupeSeconds: 86400,
    });
  });
  await c.env.DB.prepare('UPDATE message_typing SET is_typing = 0, updated_at = ? WHERE user_id = ? AND peer_id = ?')
    .bind(now(), userId, receiverId)
    .run()
    .catch(() => {});
  return c.json(await messagePayload(c, { id, sender_id: userId, receiver_id: receiverId, content, media_url: mediaUrl || null, media_type: mediaType, created_at: now() }));
});

api.get('/messages/presence/:userId', authMiddleware, async (c) => {
  const myId = getUserId(c);
  const peerId = publicId(c.req.param('userId'), 120);
  await touchUserPresence(c.env.DB, myId);
  const limited = await enforceRateLimit(c, 'message_presence', myId, 160, 60);
  if (limited) return limited;
  const invalidPeer = await validateDirectMessagePeer(c, myId, peerId);
  if (invalidPeer) return invalidPeer;
  const presence: any = await c.env.DB.prepare('SELECT last_seen_at FROM user_presence WHERE user_id = ?')
    .bind(peerId)
    .first();
  const typing: any = await c.env.DB.prepare(`
    SELECT id FROM message_typing
    WHERE user_id = ? AND peer_id = ? AND is_typing = 1 AND datetime(updated_at) > datetime('now', '-10 seconds')
    LIMIT 1
  `).bind(peerId, myId).first();
  return c.json({
    user_id: peerId,
    last_seen_at: presence?.last_seen_at || null,
    is_online: isPresenceOnline(presence?.last_seen_at),
    is_typing: !!typing,
  });
});

api.post('/messages/typing', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await touchUserPresence(c.env.DB, userId);
  const limited = await enforceRateLimit(c, 'message_typing', userId, 120, 60);
  if (limited) return limited;
  const bodyTooLarge = rejectLargeRequest(c, 20_000);
  if (bodyTooLarge) return bodyTooLarge;
  const body: any = await c.req.json().catch(() => ({}));
  const unknown = rejectUnknownFields(c, body, ['peer_id', 'peerId', 'is_typing', 'isTyping', 'typing']);
  if (unknown) return unknown;
  const peerId = publicId(body.peer_id || body.peerId, 120);
  const isTyping = optionalBoolean(body.is_typing ?? body.isTyping ?? body.typing) === true;
  if (!peerId || peerId === userId) return c.json({ typing: false });
  const invalidPeer = await validateDirectMessagePeer(c, userId, peerId);
  if (invalidPeer) return invalidPeer;
  const timestamp = now();
  await c.env.DB.prepare(`
    INSERT INTO message_typing (id, user_id, peer_id, is_typing, updated_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(user_id, peer_id) DO UPDATE SET
      is_typing = excluded.is_typing,
      updated_at = excluded.updated_at
  `).bind(uuid(), userId, peerId, isTyping ? 1 : 0, timestamp).run();
  return c.json({ typing: isTyping, updated_at: timestamp });
});

api.get('/messages/:userId', authMiddleware, async (c) => {
  const myId = getUserId(c);
  const oid = publicId(c.req.param('userId'), 120);
  await touchUserPresence(c.env.DB, myId);
  const limited = await enforceRateLimit(c, 'message_read', myId, 160, 60);
  if (limited) return limited;
  const invalidPeer = await validateDirectMessagePeer(c, myId, oid);
  if (invalidPeer) return invalidPeer;
  const limit = clampNumber(c.req.query('limit') || '80', 1, 100, 80);
  const before = cleanText(c.req.query('before') || '', 60);
  await c.env.DB.prepare('UPDATE messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0').bind(oid, myId).run();
  const beforeClause = before ? "AND datetime(created_at) < datetime(?)" : '';
  const binds = before ? [myId, oid, oid, myId, before, limit] : [myId, oid, oid, myId, limit];
  const directMessagesSql = `
    SELECT * FROM (
      SELECT * FROM messages
      WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
        ${beforeClause}
      ORDER BY created_at DESC
      LIMIT ?
    )
    ORDER BY created_at ASC
  `;
  const r = await c.env.DB.prepare(directMessagesSql).bind(...binds).all();
  const messages = await Promise.all((r.results as any[]).map((row) => messagePayload(c, row)));
  return c.json(messages);
});

api.post('/group-chats', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'group_chat_create', userId, 20, 60);
  if (limited) return limited;
  const dailyLimited = await enforceRateLimit(c, 'group_chat_create_daily', userId, 80, 86400);
  if (dailyLimited) return dailyLimited;
  const bodyTooLarge = rejectLargeRequest(c, 40_000);
  if (bodyTooLarge) return bodyTooLarge;
  const body: any = await c.req.json().catch(() => ({}));
  const unknown = rejectUnknownFields(c, body, ['member_ids', 'memberIds', 'name']);
  if (unknown) return unknown;
  const rawMemberIds = Array.isArray(body.member_ids) ? body.member_ids : Array.isArray(body.memberIds) ? body.memberIds : [];
  const memberIds = Array.isArray(rawMemberIds)
    ? rawMemberIds.map((id: any) => publicId(id, 120)).filter((id: string) => id && id !== userId)
    : [];
  const uniqueMemberIds = Array.from(new Set(memberIds)).slice(0, 50);
  if (uniqueMemberIds.length < 2) return c.json({ detail: 'Select at least two people for a group chat.' }, 400);
  await ensureAbuseProtectionSchema(c.env.DB);
  const memberPlaceholders = uniqueMemberIds.map(() => '?').join(', ');
  const existingMembersSql = `SELECT id FROM users WHERE id IN (${memberPlaceholders})`;
  const existingMembers = await c.env.DB.prepare(existingMembersSql)
    .bind(...uniqueMemberIds)
    .all();
  if ((existingMembers.results as any[]).length !== uniqueMemberIds.length) {
    return c.json({ detail: 'One or more selected people could not be found.' }, 400);
  }
  const blockedMemberSql = `
    SELECT id FROM blocks
    WHERE (blocker_id = ? AND blocked_id IN (${memberPlaceholders}))
       OR (blocked_id = ? AND blocker_id IN (${memberPlaceholders}))
    LIMIT 1
  `;
  const blockedMember = await c.env.DB.prepare(blockedMemberSql).bind(userId, ...uniqueMemberIds, userId, ...uniqueMemberIds).first();
  if (blockedMember) return c.json({ detail: 'A blocked profile cannot be added to this group.' }, 403);

  const groupId = uuid();
  const name = String(body.name || '').trim().slice(0, 80) || 'New group';
  await c.env.DB.prepare('INSERT INTO group_chats (id, name, created_by) VALUES (?, ?, ?)').bind(groupId, name, userId).run();
  await c.env.DB.prepare('INSERT INTO group_chat_members (id, group_id, user_id, role) VALUES (?, ?, ?, ?)')
    .bind(uuid(), groupId, userId, 'owner')
    .run();

  for (const memberId of uniqueMemberIds) {
    await c.env.DB.prepare('INSERT OR IGNORE INTO group_chat_members (id, group_id, user_id, role) VALUES (?, ?, ?, ?)')
      .bind(uuid(), groupId, memberId, 'member')
      .run();
  }

  const messageId = uuid();
  await c.env.DB.prepare('INSERT INTO group_messages (id, group_id, sender_id, content) VALUES (?, ?, ?, ?)')
    .bind(messageId, groupId, userId, 'Created the group')
    .run();

  return c.json({ id: groupId, name, member_count: uniqueMemberIds.length + 1, created_by: userId, created_at: now() });
});

api.get('/group-chats/:groupId/messages', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const groupId = publicId(c.req.param('groupId'), 120);
  const limited = await enforceRateLimit(c, 'group_message_read', userId, 160, 60);
  if (limited) return limited;
  if (!await requireGroupMember(c, groupId, userId)) return c.json({ detail: 'Group not found' }, 404);
  const limit = clampNumber(c.req.query('limit') || '80', 1, 100, 80);
  const before = cleanText(c.req.query('before') || '', 60);

  const group: any = await c.env.DB.prepare(`
    SELECT g.*, COUNT(m.user_id) AS member_count
    FROM group_chats g
    LEFT JOIN group_chat_members m ON m.group_id = g.id
    WHERE g.id = ?
    GROUP BY g.id
  `).bind(groupId).first();
  const groupMessagesSql = `
    SELECT gm.*, u.username, u.full_name, u.profile_image
    FROM group_messages gm
    JOIN users u ON u.id = gm.sender_id
    WHERE gm.group_id = ?
      ${before ? "AND datetime(gm.created_at) < datetime(?)" : ''}
    ORDER BY gm.created_at DESC
    LIMIT ?
  `;
  const messages = await c.env.DB.prepare(groupMessagesSql).bind(...(before ? [groupId, before, limit] : [groupId, limit])).all();

  const signedMessages = await Promise.all([...(messages.results as any[])].reverse().map((row) => messagePayload(c, row)));
  return c.json({ group, messages: signedMessages });
});

api.post('/group-chats/:groupId/messages', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const groupId = publicId(c.req.param('groupId'), 120);
  const limited = await enforceRateLimit(c, 'group_message_send', userId, 60, 60);
  if (limited) return limited;
  const dailyLimited = await enforceRateLimit(c, 'group_message_send_daily', userId, 800, 86400);
  if (dailyLimited) return dailyLimited;
  const bodyTooLarge = rejectLargeRequest(c, 120_000);
  if (bodyTooLarge) return bodyTooLarge;
  if (!await requireGroupMember(c, groupId, userId)) return c.json({ detail: 'Group not found' }, 404);
  const body: any = await c.req.json().catch(() => ({}));
  const unknown = rejectUnknownFields(c, body, ['content', 'media_url', 'mediaUrl', 'media_type', 'mediaType', 'client_request_id', 'clientRequestId', 'idempotency_key', 'request_id']);
  if (unknown) return unknown;
  const content = cleanMultilineText(body.content, 2000);
  const mediaUrl = normalizedMediaReferenceForStorage(c, safeMediaReference(body.media_url || body.mediaUrl));
  const requestedMediaType = String(body.media_type || body.mediaType || '').toLowerCase();
  const mediaType = requestedMediaType.includes('video')
    ? 'video'
    : requestedMediaType.includes('voice') || requestedMediaType.includes('audio')
      ? 'voice'
      : requestedMediaType.includes('file') || requestedMediaType.includes('document')
        ? 'file'
        : mediaUrl ? 'image' : null;
  if (!content && !mediaUrl) return c.json({ detail: 'Message is empty' }, 400);
  if (content && !mediaUrl) {
    const recentDuplicate: any = await c.env.DB.prepare(
      "SELECT id FROM group_messages WHERE group_id = ? AND sender_id = ? AND content = ? AND created_at > datetime('now', '-30 seconds') LIMIT 1"
    ).bind(groupId, userId, content).first();
    if (recentDuplicate) {
      await logSecurityEvent(c, 'duplicate_group_message_blocked', userId, { group_id: groupId });
      return c.json({ detail: 'You already sent that message. Try again in a moment.' }, 429);
    }
  }

  const id = uuid();
  await c.env.DB.prepare('INSERT INTO group_messages (id, group_id, sender_id, content, media_url, media_type) VALUES (?, ?, ?, ?, ?, ?)')
    .bind(id, groupId, userId, content, mediaUrl || null, mediaType)
    .run();
  await attachMediaBackupToMessage(c.env.DB, userId, id, mediaUrl, 'group_message_id');
  await c.env.DB.prepare('UPDATE group_chats SET updated_at = datetime(\'now\') WHERE id = ?').bind(groupId).run();
  return c.json(await messagePayload(c, { id, group_id: groupId, sender_id: userId, content, media_url: mediaUrl || null, media_type: mediaType, created_at: now() }));
});

// Calls
api.post('/calls/voip-token', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const body: any = await c.req.json().catch(() => ({}));
  const token = String(body.token || '').trim().replace(/[^a-fA-F0-9]/g, '');
  if (token.length < 32) return c.json({ detail: 'Invalid VoIP token.' }, 400);
  await ensureAbuseProtectionSchema(c.env.DB);
  const timestamp = now();
  await c.env.DB.prepare(
    `INSERT INTO voip_push_tokens (id, user_id, token, device_id, bundle_id, environment, platform, is_active, last_seen_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?, 'ios', 1, ?, ?)
     ON CONFLICT(user_id, token) DO UPDATE SET
       device_id = excluded.device_id,
       bundle_id = excluded.bundle_id,
       environment = excluded.environment,
       is_active = 1,
       last_seen_at = excluded.last_seen_at`
  ).bind(
    uuid(),
    userId,
    token,
    cleanText(body.device_id || body.deviceId || '', 160),
    cleanText(body.bundle_id || body.bundleId || c.env.APNS_BUNDLE_ID || '', 160),
    cleanText(body.environment || 'production', 32),
    timestamp,
    timestamp
  ).run();
  return c.json({ ok: true });
});

api.post('/calls', authMiddleware, async (c) => {
  try {
    const phoneGate = await requirePhoneVerified(c, 'start video calls');
    if (phoneGate) return phoneGate;
    await ensureAbuseProtectionSchema(c.env.DB);
    await expireRingingCalls(c.env.DB);

    const callerId = getUserId(c);
    const body: any = await c.req.json().catch(() => ({}));
    const calleeId = publicId(body.callee_user_id || body.calleeUserId || body.user_id || body.userId || '', 120);
    if (!calleeId || calleeId === callerId) return c.json({ detail: 'Choose someone else to call.' }, 400);

    const blocked: any = await c.env.DB.prepare(
      'SELECT id FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1'
    ).bind(callerId, calleeId, calleeId, callerId).first();
    if (blocked) return c.json({ detail: 'This call is not available.' }, 403);

    if (await hasActiveCallForUser(c.env.DB, callerId) || await hasActiveCallForUser(c.env.DB, calleeId)) {
      return c.json({ detail: 'One of you is already in another call.' }, 409);
    }

    const caller: any = await c.env.DB.prepare('SELECT id, username, full_name, profile_image FROM users WHERE id = ? LIMIT 1').bind(callerId).first();
    const callee: any = await c.env.DB.prepare('SELECT id, username, full_name, profile_image FROM users WHERE id = ? LIMIT 1').bind(calleeId).first();
    if (!caller || !callee) return c.json({ detail: 'User not found.' }, 404);

    const callId = uuid();
    const timestamp = now();
    const timeoutAt = callTimeoutAt();
    const channel = buildCaptroCallChannel(callId);
    await c.env.DB.prepare(
      `INSERT INTO call_sessions
       (id, caller_id, callee_id, caller_name, caller_avatar, callee_name, callee_avatar, call_type, status, room_id, channel_name, push_delivery_status, created_at, timeout_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'video', 'ringing', ?, ?, '', ?, ?, ?)`
    ).bind(
      callId,
      callerId,
      calleeId,
      cleanText(caller.full_name || caller.username || 'Captro', 120),
      cleanText(caller.profile_image || '', 500),
      cleanText(callee.full_name || callee.username || 'Captro', 120),
      cleanText(callee.profile_image || '', 500),
      channel,
      channel,
      timestamp,
      timeoutAt,
      timestamp
    ).run();

    const call: any = await c.env.DB.prepare('SELECT * FROM call_sessions WHERE id = ?').bind(callId).first();
    await insertNotificationOnce(c, {
      userId: calleeId,
      type: 'incoming_call',
      title: 'Captro Video Call',
      body: `${call.caller_name || 'Someone'} is calling you`,
      data: { call_id: callId, caller_user_id: callerId, status: 'ringing' },
      dedupeKey: `incoming_call:${callId}`,
      dedupeSeconds: 90,
    });

    const pushStatus = await sendVoipPushForCall(c, call);
    await c.env.DB.prepare('UPDATE call_sessions SET push_delivery_status = ?, updated_at = ? WHERE id = ?')
      .bind(pushStatus, now(), callId)
      .run();
    const fresh: any = await c.env.DB.prepare('SELECT * FROM call_sessions WHERE id = ?').bind(callId).first();
    return c.json(safeCallPayload(fresh));
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'AGORA_INVALID_CHANNEL') return c.json({ detail: 'Invalid call channel.' }, 400);
    return c.json({ detail: 'Could not start the call.' }, 500);
  }
});

api.get('/calls/incoming', authMiddleware, async (c) => {
  await ensureAbuseProtectionSchema(c.env.DB);
  const userId = getUserId(c);
  await expireRingingCalls(c.env.DB);
  const row: any = await c.env.DB.prepare(
    `SELECT * FROM call_sessions
     WHERE callee_id = ? AND status = 'ringing' AND timeout_at > ?
     ORDER BY created_at DESC
     LIMIT 1`
  ).bind(userId, now()).first();
  return c.json({ call: safeCallPayload(row) });
});

api.get('/calls/:callId', authMiddleware, async (c) => {
  await ensureAbuseProtectionSchema(c.env.DB);
  const row: any = await getVisibleCallForUser(c.env.DB, c.req.param('callId'), getUserId(c));
  if (!row) return c.json({ detail: 'Call not found.' }, 404);
  return c.json(safeCallPayload(row));
});

api.post('/calls/:callId/accept', authMiddleware, async (c) => {
  await ensureAbuseProtectionSchema(c.env.DB);
  const userId = getUserId(c);
  const row: any = await getVisibleCallForUser(c.env.DB, c.req.param('callId'), userId);
  if (!row || row.callee_id !== userId) return c.json({ detail: 'Call not found.' }, 404);
  if (row.status !== 'ringing') return c.json(safeCallPayload(row));
  const timestamp = now();
  await c.env.DB.prepare("UPDATE call_sessions SET status = 'accepted', answered_at = ?, updated_at = ? WHERE id = ?")
    .bind(timestamp, timestamp, row.id)
    .run();
  const fresh: any = await c.env.DB.prepare('SELECT * FROM call_sessions WHERE id = ?').bind(row.id).first();
  await insertNotificationOnce(c, {
    userId: row.caller_id,
    type: 'call_accepted',
    title: 'Call accepted',
    body: `${fresh.callee_name || 'They'} joined your call`,
    data: { call_id: row.id, status: 'accepted' },
    dedupeKey: `call_accepted:${row.id}`,
    dedupeSeconds: 120,
  });
  return c.json(safeCallPayload(fresh));
});

api.post('/calls/:callId/decline', authMiddleware, async (c) => {
  await ensureAbuseProtectionSchema(c.env.DB);
  const userId = getUserId(c);
  const row: any = await getVisibleCallForUser(c.env.DB, c.req.param('callId'), userId);
  if (!row || row.callee_id !== userId) return c.json({ detail: 'Call not found.' }, 404);
  if (row.status === 'ringing') {
    const timestamp = now();
    await c.env.DB.prepare("UPDATE call_sessions SET status = 'declined', ended_at = ?, updated_at = ? WHERE id = ?")
      .bind(timestamp, timestamp, row.id)
      .run();
    await insertNotificationOnce(c, {
      userId: row.caller_id,
      type: 'call_declined',
      title: 'Call declined',
      body: `${row.callee_name || 'They'} declined your call`,
      data: { call_id: row.id, status: 'declined' },
      dedupeKey: `call_declined:${row.id}`,
      dedupeSeconds: 120,
    });
  }
  const fresh: any = await c.env.DB.prepare('SELECT * FROM call_sessions WHERE id = ?').bind(row.id).first();
  return c.json(safeCallPayload(fresh));
});

api.post('/calls/:callId/cancel', authMiddleware, async (c) => {
  await ensureAbuseProtectionSchema(c.env.DB);
  const userId = getUserId(c);
  const row: any = await getVisibleCallForUser(c.env.DB, c.req.param('callId'), userId);
  if (!row || row.caller_id !== userId) return c.json({ detail: 'Call not found.' }, 404);
  if (row.status === 'ringing') {
    const timestamp = now();
    await c.env.DB.prepare("UPDATE call_sessions SET status = 'cancelled', ended_at = ?, updated_at = ? WHERE id = ?")
      .bind(timestamp, timestamp, row.id)
      .run();
  }
  const fresh: any = await c.env.DB.prepare('SELECT * FROM call_sessions WHERE id = ?').bind(row.id).first();
  if (fresh?.status === 'cancelled') {
    const pushStatus = await sendVoipPushForCall(c, fresh);
    await c.env.DB.prepare('UPDATE call_sessions SET push_delivery_status = ?, updated_at = ? WHERE id = ?')
      .bind(pushStatus, now(), row.id)
      .run();
  }
  return c.json(safeCallPayload(fresh));
});

api.post('/calls/:callId/active', authMiddleware, async (c) => {
  await ensureAbuseProtectionSchema(c.env.DB);
  const userId = getUserId(c);
  const row: any = await getVisibleCallForUser(c.env.DB, c.req.param('callId'), userId);
  if (!row) return c.json({ detail: 'Call not found.' }, 404);
  if (['accepted', 'connecting', 'active'].includes(row.status)) {
    await c.env.DB.prepare("UPDATE call_sessions SET status = 'active', updated_at = ? WHERE id = ?")
      .bind(now(), row.id)
      .run();
  }
  const fresh: any = await c.env.DB.prepare('SELECT * FROM call_sessions WHERE id = ?').bind(row.id).first();
  return c.json(safeCallPayload(fresh));
});

api.post('/calls/:callId/end', authMiddleware, async (c) => {
  await ensureAbuseProtectionSchema(c.env.DB);
  const userId = getUserId(c);
  const row: any = await getVisibleCallForUser(c.env.DB, c.req.param('callId'), userId);
  if (!row) return c.json({ detail: 'Call not found.' }, 404);
  if (['accepted', 'connecting', 'active', 'ringing'].includes(row.status)) {
    const timestamp = now();
    const nextStatus = row.status === 'ringing' ? 'cancelled' : 'ended';
    await c.env.DB.prepare('UPDATE call_sessions SET status = ?, ended_at = ?, updated_at = ? WHERE id = ?')
      .bind(nextStatus, timestamp, timestamp, row.id)
      .run();
  }
  const fresh: any = await c.env.DB.prepare('SELECT * FROM call_sessions WHERE id = ?').bind(row.id).first();
  return c.json(safeCallPayload(fresh));
});

api.post('/calls/agora/token', authMiddleware, async (c) => {
  try {
    const phoneGate = await requirePhoneVerified(c, 'start video calls');
    if (phoneGate) return phoneGate;
    const userId = getUserId(c);
    const body: any = await c.req.json().catch(() => ({}));
    const { appId, appCertificate } = getAgoraConfig(c);
    const channel = normalizeAgoraChannel(body.channel);
    const role = normalizeAgoraRole(body.role);
    const uid = await numericAgoraUid(userId);
    const expiresIn = getAgoraTokenTtl(c);
    const token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channel,
      uid,
      role.rtcRole,
      expiresIn,
      expiresIn
    );

    return c.json({
      appId,
      channel,
      uid,
      role: role.label,
      mode: body.mode === 'live' ? 'live' : body.mode === 'voice' ? 'voice' : 'call',
      token,
      expires_in: expiresIn,
      expires_at: new Date(Date.now() + expiresIn * 1000).toISOString(),
    });
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'AGORA_NOT_CONFIGURED') return c.json({ detail: 'Agora calling is not configured.' }, 503);
    if (code === 'AGORA_INVALID_CHANNEL') return c.json({ detail: 'Invalid call channel.' }, 400);
    return c.json({ detail: 'Could not create call token.' }, 500);
  }
});

// Notifications
api.get('/notifications', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'notifications_read', userId, 180, 60);
    if (limited) return limited;
    await ensureAbuseProtectionSchema(c.env.DB);
    const limit = clampNumber(c.req.query('limit') || '50', 1, 80, 50);
    const before = cleanText(c.req.query('before') || '', 60);
    const notificationsSql = `SELECT * FROM notifications WHERE user_id = ? ${before ? 'AND datetime(created_at) < datetime(?)' : ''} ORDER BY created_at DESC LIMIT ?`;
    const r = await c.env.DB.prepare(notificationsSql).bind(...(before ? [userId, before, limit] : [userId, limit])).all();
    return c.json((r.results as any[]).map(safeNotificationPayload));
  } catch {
    // Auto-create table if missing
    await c.env.DB.prepare('CREATE TABLE IF NOT EXISTS notifications (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, type TEXT DEFAULT \'general\', title TEXT DEFAULT \'\', body TEXT DEFAULT \'\', data TEXT DEFAULT \'{}\', is_read INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime(\'now\')))').run();
    return c.json([]);
  }
});
api.get('/notifications/unread-count', authMiddleware, async (c) => {
  try {
    const r = await c.env.DB.prepare('SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0').bind(getUserId(c)).first();
    return c.json({ count: (r as any)?.count || 0 });
  } catch { return c.json({ count: 0 }); }
});
api.post('/notifications/mark-read', authMiddleware, async (c) => { await c.env.DB.prepare('UPDATE notifications SET is_read = 1 WHERE user_id = ?').bind(getUserId(c)).run(); return c.json({ marked: true }); });

api.post('/notifications/device-token', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'push_token_register', userId, 30, 60);
  if (limited) return limited;
  const bodyTooLarge = rejectLargeRequest(c, 20_000);
  if (bodyTooLarge) return bodyTooLarge;
  const body: any = await c.req.json().catch(() => ({}));
  const token = String(body.token || '').trim().replace(/[^a-fA-F0-9]/g, '');
  if (token.length < 32 || token.length > 512) return c.json({ detail: 'Invalid device token.' }, 400);
  await ensureProductionReadinessSchema(c.env.DB);
  const timestamp = now();
  await c.env.DB.prepare(
    `INSERT INTO push_tokens (id, user_id, token, device_id, bundle_id, environment, platform, is_active, last_seen_at, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, 'ios', 1, ?, ?, ?)
     ON CONFLICT(user_id, token) DO UPDATE SET
       device_id = excluded.device_id,
       bundle_id = excluded.bundle_id,
       environment = excluded.environment,
       is_active = 1,
       last_seen_at = excluded.last_seen_at,
       updated_at = excluded.updated_at`
  ).bind(
    uuid(),
    userId,
    token.toLowerCase(),
    cleanText(body.device_id || body.deviceId || '', 160),
    cleanText(body.bundle_id || body.bundleId || c.env.APNS_BUNDLE_ID || '', 160),
    cleanText(body.environment || c.env.APNS_ENVIRONMENT || 'production', 32),
    timestamp,
    timestamp,
    timestamp
  ).run();
  return c.json({ ok: true });
});

api.delete('/notifications/device-token', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const body: any = await c.req.json().catch(() => ({}));
  const token = String(body.token || '').trim().replace(/[^a-fA-F0-9]/g, '').toLowerCase();
  if (!token) return c.json({ ok: true });
  await ensureProductionReadinessSchema(c.env.DB);
  await c.env.DB.prepare('UPDATE push_tokens SET is_active = 0, updated_at = ? WHERE user_id = ? AND token = ?')
    .bind(now(), userId, token)
    .run();
  return c.json({ ok: true });
});

api.post('/client/events', async (c) => {
  const userId = await getOptionalUserId(c);
  const key = userId || clientIp(c);
  const limited = await enforceRateLimit(c, 'client_events', key, 80, 60);
  if (limited) return limited;
  const bodyTooLarge = rejectLargeRequest(c, 24_000);
  if (bodyTooLarge) return bodyTooLarge;
  const body: any = await c.req.json().catch(() => ({}));
  const eventName = cleanText(body.event_name || body.eventName || body.name, 80);
  if (!eventName || !/^[a-z0-9_.:-]{2,80}$/i.test(eventName)) return c.json({ detail: 'Invalid event name.' }, 400);
  const metadata = sanitizeClientEventMetadata(body.metadata || {});
  await ensureProductionReadinessSchema(c.env.DB);
  await c.env.DB.prepare(
    `INSERT INTO client_events (id, user_id, event_name, category, status, duration_ms, metadata, app_version, platform, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    uuid(),
    userId || '',
    eventName,
    cleanText(body.category || '', 40),
    cleanText(body.status || '', 40),
    clampNumber(body.duration_ms || body.durationMs || 0, 0, 600_000, 0),
    JSON.stringify(metadata),
    cleanText(body.app_version || body.appVersion || '', 40),
    cleanText(body.platform || 'ios', 20),
    now()
  ).run();
  return c.json({ accepted: true }, 202);
});

// Library
api.get('/library/liked', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '40', 1, 80, 40);
  const likedLibrarySql = [
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
       1 AS is_liked,
       EXISTS (SELECT 1 FROM saved_posts sp WHERE sp.user_id = ? AND sp.post_id = p.id) AS saved,
       (SELECT COUNT(*) FROM likes lk_count WHERE lk_count.post_id = p.id) AS live_likes_count,
       (SELECT COUNT(*) FROM comments cm_count WHERE cm_count.post_id = p.id AND COALESCE(cm_count.status, 'active') NOT IN ('removed', 'hidden')) AS live_comments_count,
       (SELECT COUNT(*) FROM saved_posts sp_count WHERE sp_count.post_id = p.id) AS live_saves_count
     FROM likes l JOIN posts p ON l.post_id = p.id JOIN users u ON p.user_id = u.id`,
    `WHERE l.user_id = ? AND ${visiblePostWhere('u', 'p')}`,
    'ORDER BY l.created_at DESC LIMIT ? OFFSET ?',
  ].join(' ');
  const r = await c.env.DB.prepare(likedLibrarySql).bind(userId, userId, ...visiblePostBindValues(userId), limit, skip).all();
  return c.json((r.results as any[]).map((p) => feedPostPayload(p, [], c.env)));
});
api.get('/library/saved', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const collection = c.req.query('collection');
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '40', 1, 80, 40);
  const savedLibraryBaseSql = [
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image, sp.collection,
      EXISTS (SELECT 1 FROM likes lk WHERE lk.user_id = ? AND lk.post_id = p.id) AS is_liked,
      1 AS saved,
      (SELECT COUNT(*) FROM likes lk_count WHERE lk_count.post_id = p.id) AS live_likes_count,
      (SELECT COUNT(*) FROM comments cm_count WHERE cm_count.post_id = p.id AND COALESCE(cm_count.status, 'active') NOT IN ('removed', 'hidden')) AS live_comments_count,
      (SELECT COUNT(*) FROM saved_posts sp_count WHERE sp_count.post_id = p.id) AS live_saves_count
    FROM saved_posts sp
    JOIN posts p ON sp.post_id = p.id
    JOIN users u ON p.user_id = u.id`,
    `WHERE sp.user_id = ? AND ${visiblePostWhere('u', 'p')}`,
  ];
  let sql = savedLibraryBaseSql.join(' ');
  const binds: any[] = [userId, userId, ...visiblePostBindValues(userId)];
  if (collection) {
    sql += ' AND sp.collection = ?';
    binds.push(collection);
  }
  sql += ' ORDER BY sp.created_at DESC LIMIT ? OFFSET ?';
  binds.push(limit, skip);
  const r = await c.env.DB.prepare(sql).bind(...binds).all();
  return c.json((r.results as any[]).map((p) => feedPostPayload(p, [], c.env)));
});
api.post('/library/save/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await ensureGovernanceSchema(c.env.DB);
  const limited = await enforceRateLimit(c, 'save_post', userId, 240, 60);
  if (limited) return limited;
  const postId = c.req.param('postId');
  const b = await c.req.json().catch(() => ({}));
  const collection = cleanText((b as any).collection || 'My Library', 80) || 'My Library';
  const saveVisiblePostSql = [
    'SELECT p.id FROM posts p JOIN users u ON p.user_id = u.id',
    `WHERE p.id = ? AND ${visiblePostWhere('u', 'p')} LIMIT 1`,
  ].join(' ');
  const post = await c.env.DB.prepare(saveVisiblePostSql).bind(postId, ...visiblePostBindValues(userId)).first();
  if (!post) return c.json({ detail: 'Post not found' }, 404);
  const existingSave = await c.env.DB.prepare('SELECT id FROM saved_posts WHERE user_id = ? AND post_id = ?').bind(userId, postId).first();
  if (existingSave) {
    await c.env.DB.prepare('UPDATE saved_posts SET collection = ? WHERE user_id = ? AND post_id = ?').bind(collection, userId, postId).run();
  } else {
    await c.env.DB.prepare('INSERT INTO saved_posts (id, user_id, post_id, collection) VALUES (?, ?, ?, ?)').bind(uuid(), userId, postId, collection).run();
  }
  try {
    await c.env.DB.prepare('INSERT INTO bookmarks (id, user_id, post_id, collection) VALUES (?, ?, ?, ?) ON CONFLICT(user_id, post_id) DO UPDATE SET collection = ?')
      .bind(uuid(), userId, postId, collection, collection).run();
  } catch {}
  const engagement = await getPostEngagementState(c.env.DB, postId, userId);
  runBackgroundTask(c, 'supabase_save_write_through_failed', async () => {
    await mirrorLegacyInteractionToSupabase(c, postId, userId, 'save', true, collection);
    await mirrorLegacyPostToSupabase(c, postId);
  });
  return c.json({
    saved: engagement.saved,
    collection,
    saves_count: engagement.saves_count,
    liked: engagement.liked,
    likes_count: engagement.likes_count,
    comments_count: engagement.comments_count,
  });
});
api.delete('/library/save/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await ensureGovernanceSchema(c.env.DB);
  const limited = await enforceRateLimit(c, 'save_post', userId, 240, 60);
  if (limited) return limited;
  const postId = c.req.param('postId');
  const existingSave = await c.env.DB.prepare('SELECT id FROM saved_posts WHERE user_id = ? AND post_id = ?').bind(userId, postId).first();
  if (existingSave) {
    await c.env.DB.prepare('DELETE FROM saved_posts WHERE user_id = ? AND post_id = ?').bind(userId, postId).run();
  }
  try { await c.env.DB.prepare('DELETE FROM bookmarks WHERE user_id = ? AND post_id = ?').bind(userId, postId).run(); } catch {}
  const engagement = await getPostEngagementState(c.env.DB, postId, userId);
  if (existingSave) {
    runBackgroundTask(c, 'supabase_unsave_write_through_failed', async () => {
      await mirrorLegacyInteractionToSupabase(c, postId, userId, 'save', false);
      await mirrorLegacyPostToSupabase(c, postId);
    });
  }
  return c.json({
    saved: engagement.saved,
    unsaved: true,
    saves_count: engagement.saves_count,
    liked: engagement.liked,
    likes_count: engagement.likes_count,
    comments_count: engagement.comments_count,
  });
});
api.get('/library/collections', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT collection, COUNT(*) as count FROM saved_posts WHERE user_id = ? GROUP BY collection').bind(getUserId(c)).all(); return c.json(r.results); });

// Friends
api.post('/friends/request/:userId', authMiddleware, async (c) => {
  const fid = getUserId(c);
  const tid = publicId(c.req.param('userId'), 120);
  if (fid === tid) return c.json({ detail: 'Cannot friend yourself' }, 400);
  const limited = await enforceRateLimit(c, 'friend_request', fid, 60, 60);
  if (limited) return limited;
  const target = await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(tid).first();
  if (!target) return c.json({ detail: 'User not found' }, 404);
  const ex = await c.env.DB.prepare('SELECT id, status FROM friend_requests WHERE from_user_id = ? AND to_user_id = ?').bind(fid, tid).first();
  if (ex) return c.json({ detail: 'Already sent', status: (ex as any).status }, 400);
  const id = uuid();
  await c.env.DB.prepare('INSERT INTO friend_requests (id, from_user_id, to_user_id) VALUES (?, ?, ?)').bind(id, fid, tid).run();
  return c.json({ id, status: 'pending' });
});
api.post('/friends/accept/:requestId', authMiddleware, async (c) => { const uid = getUserId(c); const rid = c.req.param('requestId'); const r: any = await c.env.DB.prepare('SELECT * FROM friend_requests WHERE id = ? AND to_user_id = ?').bind(rid, uid).first(); if (!r) return c.json({ detail: 'Not found' }, 404); await c.env.DB.prepare("UPDATE friend_requests SET status = 'accepted' WHERE id = ?").bind(rid).run(); await c.env.DB.prepare('INSERT OR IGNORE INTO friendships (id, user_id, friend_id) VALUES (?, ?, ?)').bind(uuid(), uid, r.from_user_id).run(); await c.env.DB.prepare('INSERT OR IGNORE INTO friendships (id, user_id, friend_id) VALUES (?, ?, ?)').bind(uuid(), r.from_user_id, uid).run(); return c.json({ accepted: true }); });
api.post('/friends/reject/:requestId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const requestId = publicId(c.req.param('requestId'), 120);
  const limited = await enforceRateLimit(c, 'friend_reject', userId, 120, 60);
  if (limited) return limited;
  const result = await c.env.DB.prepare("UPDATE friend_requests SET status = 'rejected' WHERE id = ? AND to_user_id = ?")
    .bind(requestId, userId)
    .run();
  if (d1Changes(result) === 0) return c.json({ detail: 'Request not found' }, 404);
  return c.json({ rejected: true });
});
api.get('/friends/requests', authMiddleware, async (c) => { const r = await c.env.DB.prepare(`SELECT fr.*, u.username, u.full_name, u.profile_image FROM friend_requests fr JOIN users u ON fr.from_user_id = u.id WHERE fr.to_user_id = ? AND fr.status = 'pending'`).bind(getUserId(c)).all(); return c.json(r.results); });
api.get('/friends', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT u.id, u.username, u.full_name, u.profile_image, u.bio FROM friendships f JOIN users u ON f.friend_id = u.id WHERE f.user_id = ?').bind(getUserId(c)).all(); return c.json(r.results); });
api.get('/friends/status/:userId', authMiddleware, async (c) => { const mid = getUserId(c); const oid = c.req.param('userId'); const f = await c.env.DB.prepare('SELECT id FROM friendships WHERE user_id = ? AND friend_id = ?').bind(mid, oid).first(); if (f) return c.json({ status: 'friends' }); const sr: any = await c.env.DB.prepare("SELECT id FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'").bind(mid, oid).first(); if (sr) return c.json({ status: 'request_sent', request_id: sr.id }); const rr: any = await c.env.DB.prepare("SELECT id FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'").bind(oid, mid).first(); if (rr) return c.json({ status: 'request_received', request_id: rr.id }); return c.json({ status: 'none' }); });
api.delete('/friends/:userId', authMiddleware, async (c) => { const mid = getUserId(c); const oid = c.req.param('userId'); await c.env.DB.prepare('DELETE FROM friendships WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)').bind(mid, oid, oid, mid).run(); return c.json({ removed: true }); });

// Recommendations
api.get('/recommendations', authMiddleware, async (c) => {
  try {
    await ensureRecommendationSchema(c.env.DB);
    const category = normalizeRecommendationCategory(c.req.query('category') || '');
    const rawCategory = cleanText(c.req.query('category'), 80).toLowerCase();
    const q = cleanText(c.req.query('q'), 120).toLowerCase();
    const limit = Math.min(80, Math.max(8, Number(c.req.query('limit') || 36)));
    const binds: any[] = [];
    let where = "WHERE COALESCE(r.status, 'active') = 'active'";
    if (rawCategory && rawCategory !== 'all') {
      where += ' AND r.category = ?';
      binds.push(category);
    }
    if (q) {
      where += ' AND (LOWER(r.title) LIKE ? OR LOWER(r.description) LIKE ? OR LOWER(r.creator_name) LIKE ? OR LOWER(r.tags) LIKE ?)';
      binds.push(`%${q}%`, `%${q}%`, `%${q}%`, `%${q}%`);
    }
    binds.push(limit);

    const recommendationsSql = `
      SELECT r.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM recommendations r
      LEFT JOIN users u ON u.id = r.user_id
      ${where}
      ORDER BY r.created_at DESC
      LIMIT ?
    `;
    const rows = await c.env.DB.prepare(recommendationsSql).bind(...binds).all();
    return c.json((rows.results as any[]).map(publicRecommendationPayload));
  } catch (error: any) {
    console.error('Recommendations list failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load recommendations.' }, 500);
  }
});

api.get('/recommendations/:recommendationId', authMiddleware, async (c) => {
  try {
    await ensureRecommendationSchema(c.env.DB);
    const recommendationId = c.req.param('recommendationId');
    const row: any = await c.env.DB.prepare(`
      SELECT r.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM recommendations r
      LEFT JOIN users u ON u.id = r.user_id
      WHERE r.id = ? AND COALESCE(r.status, 'active') = 'active'
    `).bind(recommendationId).first();
    if (!row) return c.json({ detail: 'Recommendation not found.' }, 404);
    return c.json(publicRecommendationPayload(row));
  } catch (error: any) {
    console.error('Recommendation detail failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load recommendation.' }, 500);
  }
});

api.post('/recommendations', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 120_000);
    if (bodyTooLarge) return bodyTooLarge;
    await ensureRecommendationSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'recommendation_create', userId, 40, 60);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const title = cleanText(body.title, 120);
    const description = cleanText(body.description, 1400);
    const externalUrl = safeExternalUrl(body.external_url || body.url || body.link);
    if (!title) return c.json({ detail: 'Add a title for your recommendation.' }, 400);
    if (!externalUrl) return c.json({ detail: 'Add a valid http or https link.' }, 400);

    const category = normalizeRecommendationCategory(body.category || body.type);
    const tags = normalizeRecommendationTags(body.tags, [category]);
    const meta = recommendationLinkMetadata(externalUrl, body.thumbnail_url || body.cover_url);
    const ts = now();
    const id = uuid();
    await c.env.DB.prepare(
      `INSERT INTO recommendations
       (id, user_id, title, description, category, tags, external_url, provider, external_id, embed_url, thumbnail_url, creator_name, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)`
    ).bind(
      id,
      userId,
      title,
      description,
      category,
      JSON.stringify(tags),
      externalUrl,
      meta.provider,
      meta.external_id,
      meta.embed_url,
      meta.thumbnail_url,
      cleanText(body.creator_name || body.author || body.artist, 120),
      ts,
      ts
    ).run();

    const row: any = await c.env.DB.prepare(`
      SELECT r.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM recommendations r
      LEFT JOIN users u ON u.id = r.user_id
      WHERE r.id = ?
    `).bind(id).first();
    return c.json(publicRecommendationPayload(row), 201);
  } catch (error: any) {
    console.error('Recommendation create failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not submit recommendation.' }, 500);
  }
});

api.post('/recommendations/:recommendationId/report', authMiddleware, async (c) => {
  try {
    await ensureRecommendationSchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'recommendation_report', userId, 12, 60);
    if (limited) return limited;
    const recommendationId = c.req.param('recommendationId');
    const body: any = await c.req.json().catch(() => ({}));
    const recommendation: any = await c.env.DB.prepare('SELECT * FROM recommendations WHERE id = ?').bind(recommendationId).first();
    if (!recommendation) return c.json({ detail: 'Recommendation not found.' }, 404);
    if (recommendation.user_id === userId) return c.json({ detail: 'You cannot report your own recommendation.' }, 400);
    const ts = now();
    const reason = normalizeReportReason(body.reason || 'other');
    const details = cleanMultilineText(body.details || '', 1000);
    const reportResults = await c.env.DB.batch([
      c.env.DB.prepare('INSERT OR IGNORE INTO recommendation_reports (id, recommendation_id, reporter_id, reason, created_at) VALUES (?, ?, ?, ?, ?)')
        .bind(uuid(), recommendationId, userId, reason, ts),
      c.env.DB.prepare('UPDATE recommendations SET reports_count = COALESCE(reports_count, 0) + 1, updated_at = ? WHERE id = ? AND changes() > 0')
        .bind(ts, recommendationId),
    ]);
    if (d1Changes(reportResults?.[0]) > 0) {
      await c.env.DB.prepare(
        `INSERT INTO reports
         (id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, created_at, updated_at)
         VALUES (?, ?, ?, 'recommendation', 'recommendation', ?, ?, ?, 'pending', ?, ?)`
      ).bind(uuid(), userId, recommendation.user_id, reason, details, recommendationId, ts, ts).run();
    }
    return c.json({ reported: true });
  } catch (error: any) {
    const message = String(error?.message || '').toLowerCase();
    if (message.includes('unique constraint')) return c.json({ reported: true });
    console.error('Recommendation report failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not report recommendation.' }, 500);
  }
});

// Notes
api.get('/notes', authMiddleware, async (c) => {
  try {
    await ensureNotesSchema(c.env.DB);
    const userId = getUserId(c);
    const limit = clampNumber(c.req.query('limit'), 5, 80, 36);
    const type = normalizeNoteType(c.req.query('type') || '');
    const rawType = cleanText(c.req.query('type'), 80).toLowerCase();
    const binds: any[] = [userId, userId];
    let where = "WHERE COALESCE(n.status, 'active') = 'active'";
    if (rawType && rawType !== 'all') {
      where += ' AND n.note_type = ?';
      binds.push(type);
    }
    binds.push(limit);
    const notesSql = `
      SELECT n.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
        EXISTS(SELECT 1 FROM note_interactions i WHERE i.note_id = n.id AND i.user_id = ? AND i.kind = 'reaction') AS reacted,
        EXISTS(SELECT 1 FROM note_interactions i WHERE i.note_id = n.id AND i.user_id = ? AND i.kind = 'save') AS saved
      FROM notes n
      LEFT JOIN users u ON u.id = n.user_id
      ${where}
      ORDER BY n.created_at DESC
      LIMIT ?
    `;
    const rows = await c.env.DB.prepare(notesSql).bind(...binds).all();
    return c.json((rows.results as any[]).map((row) => publicNotePayload(row)));
  } catch (error: any) {
    console.error('Notes list failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load notes.' }, 500);
  }
});

api.get('/notes/:noteId', authMiddleware, async (c) => {
  try {
    await ensureNotesSchema(c.env.DB);
    const userId = getUserId(c);
    const noteId = cleanText(c.req.param('noteId'), 80);
    const row: any = await c.env.DB.prepare(`
      SELECT n.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
        EXISTS(SELECT 1 FROM note_interactions i WHERE i.note_id = n.id AND i.user_id = ? AND i.kind = 'reaction') AS reacted,
        EXISTS(SELECT 1 FROM note_interactions i WHERE i.note_id = n.id AND i.user_id = ? AND i.kind = 'save') AS saved
      FROM notes n
      LEFT JOIN users u ON u.id = n.user_id
      WHERE n.id = ? AND COALESCE(n.status, 'active') = 'active'
    `).bind(userId, userId, noteId).first();
    if (!row) return c.json({ detail: 'Note not found.' }, 404);
    return c.json(publicNotePayload(row));
  } catch (error: any) {
    console.error('Note detail failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load note.' }, 500);
  }
});

api.post('/notes', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 80_000);
    if (bodyTooLarge) return bodyTooLarge;
    await ensureNotesSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'note_create', userId, 60, 60);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const noteBody = cleanText(body.body || body.text || body.content, 420);
    const mediaUrl = safeMediaReference(body.media_url || body.image_url || body.image);
    const mediaType = mediaUrl ? 'image' : '';
    const moderation = moderateCommunityText(noteBody);
    if (!moderation.ok) return c.json({ detail: moderation.detail || 'That note cannot be posted.' }, 400);
    if (noteBody.length < 2 && !mediaUrl) return c.json({ detail: 'Add text or a photo first.' }, 400);
    const noteType = normalizeNoteType(body.note_type || body.type);
    const mood = normalizeNoteMood(body.mood || body.color);
    const color = /^#[0-9a-f]{6}$/i.test(String(body.color || '')) ? String(body.color) : mood.color;
    const anonymous = normalizeSqlBoolean(body.anonymous);
    if (anonymous) {
      await ensurePremiumSchema(c.env.DB);
      const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
      if (!userHasActivePremium(user)) {
        return c.json({ detail: 'Anonymous Notes are a Premium feature.', code: 'PREMIUM_REQUIRED' }, 403);
      }
      const usedToday = await getAnonymousNotesUsedToday(c.env.DB, userId);
      if (usedToday >= 5) {
        return c.json({ detail: 'You used all 5 anonymous notes for today.', code: 'ANONYMOUS_NOTE_LIMIT' }, 429);
      }
    }
    const ts = now();
    const id = uuid();
    await c.env.DB.prepare(
      `INSERT INTO notes
       (id, user_id, body, note_type, mood, color, media_url, media_type, anonymous, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)`
    ).bind(id, userId, noteBody, noteType, mood.mood, color, mediaUrl, mediaType, anonymous, ts, ts).run();
    const row: any = await c.env.DB.prepare(`
      SELECT n.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM notes n LEFT JOIN users u ON u.id = n.user_id WHERE n.id = ?
    `).bind(id).first();
    return c.json(publicNotePayload(row), 201);
  } catch (error: any) {
    console.error('Note create failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not create note.' }, 500);
  }
});

api.post('/notes/:noteId/interactions', authMiddleware, async (c) => {
  try {
    await ensureNotesSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'note_interaction', userId, 300, 60);
    if (limited) return limited;
    const noteId = cleanText(c.req.param('noteId'), 80);
    const body: any = await c.req.json().catch(() => ({}));
    const kind = ['reaction', 'save', 'share'].includes(String(body.kind)) ? String(body.kind) : 'reaction';
    const value = cleanText(body.value || (kind === 'reaction' ? 'heart' : ''), 40);
    const note: any = await c.env.DB.prepare("SELECT id FROM notes WHERE id = ? AND COALESCE(status, 'active') = 'active'").bind(noteId).first();
    if (!note) return c.json({ detail: 'Note not found.' }, 404);
    const existing: any = await c.env.DB.prepare('SELECT id FROM note_interactions WHERE note_id = ? AND user_id = ? AND kind = ?')
      .bind(noteId, userId, kind)
      .first();
    if (existing && kind !== 'share') {
      await c.env.DB.prepare('DELETE FROM note_interactions WHERE id = ?').bind(existing.id).run();
      const column = kind === 'save' ? 'saves_count' : 'reactions_count';
      const decrementNoteSql = `UPDATE notes SET ${column} = MAX(0, COALESCE(${column}, 0) - 1), updated_at = ? WHERE id = ?`;
      await c.env.DB.prepare(decrementNoteSql).bind(now(), noteId).run();
      return c.json({ active: false, kind });
    }
    if (!existing || kind === 'share') {
      await c.env.DB.prepare('INSERT OR IGNORE INTO note_interactions (id, note_id, user_id, kind, value, created_at) VALUES (?, ?, ?, ?, ?, ?)')
        .bind(uuid(), noteId, userId, kind, value, now())
        .run();
      const column = kind === 'save' ? 'saves_count' : kind === 'share' ? 'shares_count' : 'reactions_count';
      const incrementNoteSql = `UPDATE notes SET ${column} = COALESCE(${column}, 0) + 1, updated_at = ? WHERE id = ?`;
      await c.env.DB.prepare(incrementNoteSql).bind(now(), noteId).run();
    }
    return c.json({ active: true, kind });
  } catch (error: any) {
    console.error('Note interaction failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not update note.' }, 500);
  }
});

api.get('/notes/:noteId/comments', authMiddleware, async (c) => {
  try {
    await ensureNotesSchema(c.env.DB);
    const noteId = cleanText(c.req.param('noteId'), 80);
    const rows = await c.env.DB.prepare(`
      SELECT nc.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
             EXISTS(SELECT 1 FROM note_comment_likes ncl WHERE ncl.comment_id = nc.id AND ncl.user_id = ?) AS liked_by_me
      FROM note_comments nc
      LEFT JOIN users u ON u.id = nc.user_id
      WHERE nc.note_id = ? AND COALESCE(nc.status, 'active') = 'active'
      ORDER BY nc.created_at ASC
      LIMIT 80
    `).bind(getUserId(c), noteId).all();
    return c.json((rows.results as any[]).map((comment) => ({
      id: comment.id,
      body: comment.body,
      parent_id: comment.parent_id || '',
      likes_count: Number(comment.likes_count || 0),
      liked_by_me: !!comment.liked_by_me,
      created_at: comment.created_at,
      user: {
        id: comment.user_id,
        username: comment.user_username || '',
        full_name: comment.user_full_name || '',
        profile_image: comment.user_profile_image || '',
      },
    })));
  } catch (error: any) {
    console.error('Note comments failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load note comments.' }, 500);
  }
});

api.post('/notes/:noteId/comments', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 80_000);
    if (bodyTooLarge) return bodyTooLarge;
    await ensureNotesSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'note_comment', userId, 90, 60);
    if (limited) return limited;
    const noteId = cleanText(c.req.param('noteId'), 80);
    const body: any = await c.req.json().catch(() => ({}));
    const commentBody = cleanText(body.body || body.text, 500);
    const moderation = moderateCommunityText(commentBody);
    if (!moderation.ok) return c.json({ detail: moderation.detail || 'That comment cannot be posted.' }, 400);
    const note: any = await c.env.DB.prepare("SELECT id FROM notes WHERE id = ? AND COALESCE(status, 'active') = 'active'").bind(noteId).first();
    if (!note) return c.json({ detail: 'Note not found.' }, 404);
    const ts = now();
    const id = uuid();
    await c.env.DB.prepare('INSERT INTO note_comments (id, note_id, user_id, parent_id, body, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
      .bind(id, noteId, userId, cleanText(body.parent_id, 80), commentBody, 'active', ts, ts)
      .run();
    await c.env.DB.prepare('UPDATE notes SET comments_count = COALESCE(comments_count, 0) + 1, updated_at = ? WHERE id = ?').bind(ts, noteId).run();
    return c.json({ id, body: commentBody, created_at: ts }, 201);
  } catch (error: any) {
    console.error('Note comment create failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not add comment.' }, 500);
  }
});

api.post('/note-comments/:commentId/like', authMiddleware, async (c) => {
  try {
    await ensureNotesSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'note_comment_like', userId, 300, 60);
    if (limited) return limited;
    const commentId = cleanText(c.req.param('commentId'), 80);
    const body: any = await c.req.json().catch(() => ({}));
    const requested = optionalBoolean(body.liked ?? body.like ?? body.value);
    const comment: any = await c.env.DB.prepare(
      "SELECT id, likes_count FROM note_comments WHERE id = ? AND COALESCE(status, 'active') = 'active'"
    ).bind(commentId).first();
    if (!comment) return c.json({ detail: 'Comment not found.' }, 404);

    let nextLiked = requested;
    if (nextLiked === null) {
      const existing: any = await c.env.DB.prepare('SELECT id FROM note_comment_likes WHERE user_id = ? AND comment_id = ?')
        .bind(userId, commentId)
        .first();
      nextLiked = !existing;
    }

    const ts = now();
    if (nextLiked) {
      const inserted = await c.env.DB.prepare('INSERT OR IGNORE INTO note_comment_likes (id, comment_id, user_id, created_at) VALUES (?, ?, ?, ?)')
        .bind(uuid(), commentId, userId, ts)
        .run();
      if (d1Changes(inserted) > 0) {
        await c.env.DB.prepare('UPDATE note_comments SET likes_count = COALESCE(likes_count, 0) + 1, updated_at = ? WHERE id = ?')
          .bind(ts, commentId)
          .run();
      }
    } else {
      const deleted = await c.env.DB.prepare('DELETE FROM note_comment_likes WHERE user_id = ? AND comment_id = ?')
        .bind(userId, commentId)
        .run();
      if (d1Changes(deleted) > 0) {
        await c.env.DB.prepare('UPDATE note_comments SET likes_count = MAX(0, COALESCE(likes_count, 0) - 1), updated_at = ? WHERE id = ?')
          .bind(ts, commentId)
          .run();
      }
    }

    const row: any = await c.env.DB.prepare('SELECT likes_count FROM note_comments WHERE id = ?').bind(commentId).first();
    return c.json({ liked: !!nextLiked, likes_count: Number(row?.likes_count || 0) });
  } catch (error: any) {
    console.error('Note comment like failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not update comment like.' }, 500);
  }
});

api.post('/notes/:noteId/report', authMiddleware, async (c) => {
  try {
    await ensureNotesSchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'note_report', userId, 12, 60);
    if (limited) return limited;
    const noteId = cleanText(c.req.param('noteId'), 80);
    const body: any = await c.req.json().catch(() => ({}));
    const note: any = await c.env.DB.prepare('SELECT id, user_id FROM notes WHERE id = ?').bind(noteId).first();
    if (!note) return c.json({ detail: 'Note not found.' }, 404);
    if (note.user_id === userId) return c.json({ detail: 'You cannot report your own note.' }, 400);
    const ts = now();
    const reason = normalizeReportReason(body.reason || 'other');
    const details = cleanMultilineText(body.details || '', 1000);
    const reportResults = await c.env.DB.batch([
      c.env.DB.prepare('INSERT OR IGNORE INTO note_reports (id, note_id, reporter_id, reason, details, created_at) VALUES (?, ?, ?, ?, ?, ?)')
        .bind(uuid(), noteId, userId, reason, details, ts),
      c.env.DB.prepare('UPDATE notes SET reports_count = COALESCE(reports_count, 0) + 1, updated_at = ? WHERE id = ? AND changes() > 0')
        .bind(ts, noteId),
    ]);
    if (d1Changes(reportResults?.[0]) > 0) {
      await c.env.DB.prepare(
        `INSERT INTO reports
         (id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, created_at, updated_at)
         VALUES (?, ?, ?, 'note', 'note', ?, ?, ?, 'pending', ?, ?)`
      ).bind(uuid(), userId, note.user_id, reason, details, noteId, ts, ts).run();
    }
    return c.json({ reported: true });
  } catch (error: any) {
    const message = String(error?.message || '').toLowerCase();
    if (message.includes('unique constraint')) return c.json({ reported: true });
    console.error('Note report failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not report note.' }, 500);
  }
});

// People
api.get('/people', authMiddleware, async (c) => {
  try {
    await ensurePeopleSchema(c.env.DB);
    const userId = getUserId(c);
    const q = cleanText(c.req.query('q'), 120).toLowerCase();
    const limit = clampNumber(c.req.query('limit'), 8, 80, 36);
    const profileRows = await c.env.DB.prepare(`
      SELECT p.*,
        EXISTS(SELECT 1 FROM people_interactions i WHERE i.profile_id = p.id AND i.user_id = ? AND i.kind = 'follow') AS followed,
        EXISTS(SELECT 1 FROM people_interactions i WHERE i.profile_id = p.id AND i.user_id = ? AND i.kind = 'save') AS saved
      FROM people_profiles p
      WHERE COALESCE(p.status, 'active') = 'active'
        AND (? = '' OR LOWER(p.name) LIKE ? OR LOWER(p.role) LIKE ? OR LOWER(p.bio) LIKE ? OR LOWER(p.known_for) LIKE ?)
      ORDER BY p.updated_at DESC
      LIMIT ?
    `).bind(userId, userId, q, `%${q}%`, `%${q}%`, `%${q}%`, `%${q}%`, limit).all();

    const people = (profileRows.results as any[]).map((row) => publicPeoplePayload(row));
    if (people.length < limit) {
      const userRows = await c.env.DB.prepare(`
        SELECT u.*,
          EXISTS(SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.following_id = u.id) AS followed
        FROM users u
        WHERE u.id != ?
          AND COALESCE(u.status, 'active') != 'banned'
          AND COALESCE(u.is_private, 0) = 0
          AND (COALESCE(u.full_name, '') != '' OR COALESCE(u.username, '') != '')
          AND (? = '' OR LOWER(u.full_name) LIKE ? OR LOWER(u.username) LIKE ? OR LOWER(u.bio) LIKE ? OR LOWER(u.interests) LIKE ?)
        ORDER BY COALESCE(u.followers_count, 0) DESC, u.updated_at DESC
        LIMIT ?
      `).bind(userId, userId, q, `%${q}%`, `%${q}%`, `%${q}%`, `%${q}%`, limit - people.length).all();
      people.push(...(userRows.results as any[]).map((u) => ({
        id: `user:${u.id}`,
        owner_user_id: u.id,
        name: u.full_name || u.username || 'Creator',
        role: u.is_creator ? 'creator' : 'local creator',
        category: 'creator',
        bio: u.bio || '',
        known_for: parseInterestValues(u.interests || u.looking_for).slice(0, 4).join(', '),
        city: u.city || u.location || '',
        profile_image: u.profile_image || '',
        instagram_url: safeOptionalUrl(u.social_instagram),
        tiktok_url: safeOptionalUrl(u.social_tiktok),
        youtube_url: '',
        website_url: safeOptionalUrl(u.social_website),
        source_url: '',
        claim_status: 'claimed',
        followers_count: Number(u.followers_count || 0),
        saves_count: 0,
        reports_count: 0,
        followed: Number(u.followed || 0) === 1,
        saved: false,
        created_at: u.created_at,
        updated_at: u.updated_at,
      })));
    }
    return c.json(people);
  } catch (error: any) {
    console.error('People list failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load people.' }, 500);
  }
});

api.get('/people/:profileId', authMiddleware, async (c) => {
  try {
    await ensurePeopleSchema(c.env.DB);
    const userId = getUserId(c);
    const profileId = cleanText(c.req.param('profileId'), 120);
    let profile: any = null;
    if (profileId.startsWith('user:')) {
      const targetId = profileId.slice(5);
      const u: any = await c.env.DB.prepare(`
        SELECT u.*, EXISTS(SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.following_id = u.id) AS followed
        FROM users u WHERE u.id = ? AND COALESCE(u.status, 'active') != 'banned'
      `).bind(userId, targetId).first();
      if (u) {
        profile = {
          id: `user:${u.id}`,
          owner_user_id: u.id,
          name: u.full_name || u.username || 'Creator',
          role: u.is_creator ? 'creator' : 'local creator',
          category: 'creator',
          bio: u.bio || '',
          known_for: parseInterestValues(u.interests || u.looking_for).slice(0, 6).join(', '),
          city: u.city || u.location || '',
          profile_image: u.profile_image || '',
          instagram_url: safeOptionalUrl(u.social_instagram),
          tiktok_url: safeOptionalUrl(u.social_tiktok),
          youtube_url: '',
          website_url: safeOptionalUrl(u.social_website),
          source_url: '',
          claim_status: 'claimed',
          followers_count: Number(u.followers_count || 0),
          saves_count: 0,
          reports_count: 0,
          followed: Number(u.followed || 0) === 1,
          saved: false,
          created_at: u.created_at,
          updated_at: u.updated_at,
        };
      }
    } else {
      const row: any = await c.env.DB.prepare(`
        SELECT p.*,
          EXISTS(SELECT 1 FROM people_interactions i WHERE i.profile_id = p.id AND i.user_id = ? AND i.kind = 'follow') AS followed,
          EXISTS(SELECT 1 FROM people_interactions i WHERE i.profile_id = p.id AND i.user_id = ? AND i.kind = 'save') AS saved
        FROM people_profiles p
        WHERE p.id = ? AND COALESCE(p.status, 'active') = 'active'
      `).bind(userId, userId, profileId).first();
      if (row) profile = publicPeoplePayload(row);
    }
    if (!profile) return c.json({ detail: 'People profile not found.' }, 404);
    const similarRows = await c.env.DB.prepare(`
      SELECT p.* FROM people_profiles p
      WHERE COALESCE(p.status, 'active') = 'active' AND p.id != ? AND (p.category = ? OR p.role = ?)
      ORDER BY p.updated_at DESC LIMIT 8
    `).bind(profileId, profile.category || 'creator', profile.role || 'creator').all();
    return c.json({ ...profile, similar_people: (similarRows.results as any[]).map((row) => publicPeoplePayload(row)) });
  } catch (error: any) {
    console.error('People detail failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load People profile.' }, 500);
  }
});

api.post('/people/:profileId/interactions', authMiddleware, async (c) => {
  try {
    await ensurePeopleSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'people_interaction', userId, 240, 60);
    if (limited) return limited;
    const profileId = cleanText(c.req.param('profileId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const kind = String(body.kind) === 'save' ? 'save' : 'follow';
    let active = optionalBoolean(body.active ?? body.following ?? body.saved ?? body.value);
    if (profileId.startsWith('user:') && kind === 'follow') {
      const targetId = profileId.slice(5);
      if (targetId === userId) return c.json({ detail: 'Cannot follow yourself.' }, 400);
      const target = await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(targetId).first();
      if (!target) return c.json({ detail: 'User not found.' }, 404);
      if (active === null) {
        const existing: any = await c.env.DB.prepare('SELECT id FROM follows WHERE follower_id = ? AND following_id = ?').bind(userId, targetId).first();
        active = !existing;
      }
      if (active) {
        const results = await c.env.DB.batch([
          c.env.DB.prepare('INSERT OR IGNORE INTO follows (id, follower_id, following_id) VALUES (?, ?, ?)').bind(uuid(), userId, targetId),
          c.env.DB.prepare('UPDATE users SET following_count = COALESCE(following_count, 0) + 1 WHERE id = ? AND changes() > 0').bind(userId),
          c.env.DB.prepare('UPDATE users SET followers_count = COALESCE(followers_count, 0) + 1 WHERE id = ? AND changes() > 0').bind(targetId),
        ]);
        if (d1Changes(results?.[0]) > 0) {
          runBackgroundTask(c, 'supabase_people_follow_write_through_failed', async () => {
            await mirrorLegacyUserToSupabase(c, userId);
            await mirrorLegacyUserToSupabase(c, targetId);
            await mirrorLegacyFollowToSupabase(c, userId, targetId, true);
          });
        }
      } else {
        const results = await c.env.DB.batch([
          c.env.DB.prepare('DELETE FROM follows WHERE follower_id = ? AND following_id = ?').bind(userId, targetId),
          c.env.DB.prepare('UPDATE users SET following_count = MAX(0, COALESCE(following_count, 0) - 1) WHERE id = ? AND changes() > 0').bind(userId),
          c.env.DB.prepare('UPDATE users SET followers_count = MAX(0, COALESCE(followers_count, 0) - 1) WHERE id = ? AND changes() > 0').bind(targetId),
        ]);
        if (d1Changes(results?.[0]) > 0) {
          runBackgroundTask(c, 'supabase_people_unfollow_write_through_failed', async () => {
            await mirrorLegacyUserToSupabase(c, userId);
            await mirrorLegacyUserToSupabase(c, targetId);
            await mirrorLegacyFollowToSupabase(c, userId, targetId, false);
          });
        }
      }
      return c.json({ active: !!active, kind });
    }
    if (active === null) {
      const existing: any = await c.env.DB.prepare('SELECT id FROM people_interactions WHERE profile_id = ? AND user_id = ? AND kind = ?')
        .bind(profileId, userId, kind)
        .first();
      active = !existing;
    }
    const column = kind === 'save' ? 'saves_count' : 'followers_count';
    if (active) {
      const incrementPeopleSql = `UPDATE people_profiles SET ${column} = COALESCE(${column}, 0) + 1, updated_at = ? WHERE id = ? AND changes() > 0`;
      await c.env.DB.batch([
        c.env.DB.prepare('INSERT OR IGNORE INTO people_interactions (id, profile_id, user_id, kind, created_at) VALUES (?, ?, ?, ?, ?)')
          .bind(uuid(), profileId, userId, kind, now()),
        c.env.DB.prepare(incrementPeopleSql)
          .bind(now(), profileId),
      ]);
    } else {
      const decrementPeopleSql = `UPDATE people_profiles SET ${column} = MAX(0, COALESCE(${column}, 0) - 1), updated_at = ? WHERE id = ? AND changes() > 0`;
      await c.env.DB.batch([
        c.env.DB.prepare('DELETE FROM people_interactions WHERE profile_id = ? AND user_id = ? AND kind = ?')
          .bind(profileId, userId, kind),
        c.env.DB.prepare(decrementPeopleSql)
          .bind(now(), profileId),
      ]);
    }
    return c.json({ active: !!active, kind });
  } catch (error: any) {
    console.error('People interaction failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not update People profile.' }, 500);
  }
});

api.post('/people/:profileId/claim', authMiddleware, async (c) => {
  try {
    await ensurePeopleSchema(c.env.DB);
    const userId = getUserId(c);
    const profileId = cleanText(c.req.param('profileId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const ts = now();
    await c.env.DB.prepare(
      'INSERT INTO people_claims (id, profile_id, user_id, message, evidence_url, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    ).bind(uuid(), profileId, userId, cleanText(body.message || 'I want to claim this profile.', 1000), safeOptionalUrl(body.evidence_url), 'pending', ts, ts).run();
    await c.env.DB.prepare("UPDATE people_profiles SET claim_status = 'pending', updated_at = ? WHERE id = ?").bind(ts, profileId).run();
    return c.json({ claimed: true, status: 'pending' }, 201);
  } catch (error: any) {
    console.error('People claim failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not submit claim.' }, 500);
  }
});

api.post('/people/:profileId/report', authMiddleware, async (c) => {
  try {
    await ensurePeopleSchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'people_report', userId, 12, 60);
    if (limited) return limited;
    const profileId = cleanText(c.req.param('profileId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const ts = now();
    const reason = normalizeReportReason(body.reason || 'other');
    const details = cleanMultilineText(body.details || '', 1000);
    const reportResults = await c.env.DB.batch([
      c.env.DB.prepare('INSERT OR IGNORE INTO people_reports (id, profile_id, reporter_id, reason, details, created_at) VALUES (?, ?, ?, ?, ?, ?)')
        .bind(uuid(), profileId, userId, reason, details, ts),
      c.env.DB.prepare('UPDATE people_profiles SET reports_count = COALESCE(reports_count, 0) + 1, updated_at = ? WHERE id = ? AND changes() > 0')
        .bind(ts, profileId),
    ]);
    if (d1Changes(reportResults?.[0]) > 0) {
      await c.env.DB.prepare(
        `INSERT INTO reports
         (id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, created_at, updated_at)
         VALUES (?, ?, ?, 'people', 'people', ?, ?, ?, 'pending', ?, ?)`
      ).bind(uuid(), userId, profileId, reason || 'Wrong People profile info', details, profileId, ts, ts).run();
    }
    return c.json({ reported: true });
  } catch (error: any) {
    const message = String(error?.message || '').toLowerCase();
    if (message.includes('unique constraint')) return c.json({ reported: true });
    console.error('People report failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not report People profile.' }, 500);
  }
});

// Discover
api.get('/discover', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'discover_category_read', userId, 180, 60);
  if (limited) return limited;
  await ensurePrivacySchema(c.env.DB);
  await ensureGovernanceSchema(c.env.DB);
  await ensurePostEditorSchema(c.env.DB);
  await ensureLocationSchema(c.env.DB);
  await ensureAutoCategorySchema(c.env.DB);
  const rawCategory = c.req.query('category') || 'all';
  const category = normalizeDiscoverCategory(rawCategory, true);
  if (!category) return c.json({ detail: 'Unknown Discover category.' }, 400);
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '36', 1, 60, 36);
  const conditions = [
    visiblePostWhere('u', 'p'),
    "COALESCE(p.discover_blocked_at, '') = ''",
  ];
  const binds: any[] = [userId, userId, userId, ...visiblePostBindValues(userId)];
  if (category !== 'all') {
    const keywords = CATEGORY_KEYWORDS[category].slice(0, 18);
    const searchableText = "LOWER(COALESCE(p.title, '') || ' ' || COALESCE(p.content, '') || ' ' || COALESCE(p.location, '') || ' ' || COALESCE(p.place_name, '') || ' ' || COALESCE(p.tags_json, ''))";
    const keywordMatches = keywords.map(() => `${searchableText} LIKE ?`).join(' OR ');
    conditions.push(`(
      LOWER(COALESCE(NULLIF(p.primary_category, ''), NULLIF(p.category, ''), 'lifestyle')) = ?
      OR (
        LOWER(COALESCE(p.primary_category, '')) IN ('', 'lifestyle', 'general', 'place')
        AND (${keywordMatches})
      )
    )`);
    binds.push(category, ...keywords.map((keyword) => `%${keyword}%`));
  }
  const sql = [
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
       EXISTS (SELECT 1 FROM follows fl WHERE fl.follower_id = ? AND fl.following_id = p.user_id) AS is_following,
       EXISTS (SELECT 1 FROM likes lk WHERE lk.user_id = ? AND lk.post_id = p.id) AS is_liked,
       EXISTS (SELECT 1 FROM saved_posts sp WHERE sp.user_id = ? AND sp.post_id = p.id) AS saved,
       COALESCE(p.likes_count, 0) AS live_likes_count,
       COALESCE(p.comments_count, 0) AS live_comments_count,
       COALESCE(p.saves_count, 0) AS live_saves_count
     FROM posts p JOIN users u ON p.user_id = u.id`,
    `WHERE ${conditions.join(' AND ')}`,
    'ORDER BY p.created_at DESC LIMIT ? OFFSET ?',
  ].join(' ');
  const rows = await c.env.DB.prepare(sql).bind(...binds, limit, skip).all();
  const response = c.json((rows.results as any[]).map((post) => feedPostPayload(post, [], c.env)));
  response.headers.set('cache-control', 'private, max-age=8');
  return response;
});

api.get('/discover/trending', authMiddleware, async (c) => {
  const userId = getUserId(c);
    await ensurePrivacySchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    await ensurePostEditorSchema(c.env.DB);
    await ensureLocationSchema(c.env.DB);
  const limit = clampNumber(c.req.query('limit') || '20', 1, 40, 20);
  const discoverTrendingSql = [
    'SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image',
    'FROM posts p JOIN users u ON p.user_id = u.id',
    `WHERE ${visiblePostWhere('u', 'p')}`,
    'ORDER BY p.likes_count DESC, p.created_at DESC LIMIT ?',
  ].join(' ');
  const r = await c.env.DB.prepare(discoverTrendingSql).bind(...visiblePostBindValues(userId), limit).all();
  return c.json((r.results as any[]).map((p) => feedPostPayload(p, [], c.env)));
});
api.get('/discover/search', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'discover_search', userId, 100, 60);
  if (limited) return limited;
  await ensurePrivacySchema(c.env.DB);
  await ensureGovernanceSchema(c.env.DB);
  await ensurePostEditorSchema(c.env.DB);
  await ensureLocationSchema(c.env.DB);
  const q = cleanText(c.req.query('q'), 80);
  if (q.length < 2) return c.json({ posts: [], users: [] });
  const limit = clampNumber(c.req.query('limit') || '20', 1, 30, 20);
  const discoverSearchSql = [
    'SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image',
    'FROM posts p JOIN users u ON p.user_id = u.id',
    `WHERE p.content LIKE ? AND ${visiblePostWhere('u', 'p')}`,
    'LIMIT ?',
  ].join(' ');
  const posts = await c.env.DB.prepare(discoverSearchSql).bind(`%${q}%`, ...visiblePostBindValues(userId), limit).all();
  const users = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio, is_private FROM users WHERE username LIKE ? OR full_name LIKE ? LIMIT 10').bind(`%${q}%`, `%${q}%`).all();
  return c.json({ posts: (posts.results as any[]).map((p) => feedPostPayload(p, [], c.env)), users: (users.results as any[]).map((user) => safeUserPayload(user)) });
});
api.get('/discover/suggested-users', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'suggested_users_read', userId, 120, 60);
  if (limited) return limited;
  const r = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio, followers_count FROM users WHERE id != ? ORDER BY followers_count DESC LIMIT 10').bind(userId).all();
  return c.json((r.results as any[]).map((user) => safeUserPayload(user)));
});

// Uploads (Cloudflare Images + Stream direct upload)
api.post('/upload/image-direct', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'upload_image_direct', userId, 60, 60);
  if (limited) return limited;
  const dailyLimited = await enforceRateLimit(c, 'upload_image_direct_daily', userId, 250, 86400);
  if (dailyLimited) return dailyLimited;
  if (!c.env.CLOUDFLARE_ACCOUNT_ID || !c.env.CLOUDFLARE_IMAGES_TOKEN) {
    return c.json({ detail: 'Image upload is not configured.' }, 503);
  }
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/images/v2/direct_upload`, { method: 'POST', headers: { Authorization: `Bearer ${c.env.CLOUDFLARE_IMAGES_TOKEN}` } });
  const data: any = await res.json();
  if (!data.success) return c.json({ detail: 'Failed to get upload URL' }, 500);
  return c.json({ upload_url: data.result.uploadURL, image_id: data.result.id });
});

api.post('/upload/video-direct', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'upload_video_direct', userId, 40, 60);
  if (limited) return limited;
  const dailyLimited = await enforceRateLimit(c, 'upload_video_direct_daily', userId, 100, 86400);
  if (dailyLimited) return dailyLimited;
  if (!c.env.CLOUDFLARE_ACCOUNT_ID || !c.env.CLOUDFLARE_STREAM_TOKEN) {
    return c.json({ detail: 'Video upload is not configured.' }, 503);
  }
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/stream/direct_upload`, { method: 'POST', headers: { Authorization: `Bearer ${c.env.CLOUDFLARE_STREAM_TOKEN}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ maxDurationSeconds: 300, creator: userId }) });
  const data: any = await res.json();
  if (!data.success) return c.json({ detail: 'Failed to get upload URL' }, 500);
  return c.json({ upload_url: data.result.uploadURL, video_uid: data.result.uid });
});

// Stripe billing
api.get('/stripe/config', authMiddleware, async (c) => {
  const stripe = getStripeConfig(c);
  return c.json({
    connected: stripe.configured,
    publishable_key: stripe.publishableKey || '',
    default_price_configured: !!stripe.defaultPriceId,
  });
});

api.get('/stripe/account', authMiddleware, async (c) => {
  try {
    await requireOwnerOrAdmin(c);
    const stripe = getStripeConfig(c);
    if (!stripe.configured) return c.json({ connected: false, detail: 'Stripe is not configured yet.' }, 503);
    const response = await stripeApiGet(c, '/account');
    if (!response.ok) {
      console.error('Stripe account check failed:', response.status, response.data?.error?.code || 'stripe_error');
      return c.json({ connected: false, detail: 'Could not connect to Stripe.' }, response.status as any);
    }
    const account = response.data || {};
    return c.json({
      connected: true,
      account_id: account.id || '',
      country: account.country || '',
      default_currency: account.default_currency || '',
      charges_enabled: !!account.charges_enabled,
      payouts_enabled: !!account.payouts_enabled,
      details_submitted: !!account.details_submitted,
      business_name: account.business_profile?.name || account.settings?.dashboard?.display_name || '',
    });
  } catch (error: any) {
    const forbidden = String(error?.message || '') === 'FORBIDDEN';
    return c.json({ detail: forbidden ? 'Owner access required.' : 'Could not check Stripe account.' }, forbidden ? 403 : 500);
  }
});

api.post('/stripe/checkout/sessions', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 20_000);
    if (bodyTooLarge) return bodyTooLarge;
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'stripe_checkout_session', userId, 30, 60);
    if (limited) return limited;

    const body: any = await c.req.json().catch(() => ({}));
    const stripe = getStripeConfig(c);
    const priceId = cleanText(body.price_id || stripe.defaultPriceId, 120);
    if (!priceId || !priceId.startsWith('price_')) {
      return c.json({ detail: 'A valid Stripe price id is required.', code: 'STRIPE_PRICE_REQUIRED' }, 400);
    }

    const mode = ['payment', 'subscription'].includes(String(body.mode || 'payment')) ? String(body.mode || 'payment') : 'payment';
    const quantity = clampNumber(body.quantity, 1, 20, 1);
    const successUrl = allowedStripeReturnUrl(c, body.success_url || c.env.STRIPE_SUCCESS_URL, '/library?checkout=success&session_id={CHECKOUT_SESSION_ID}');
    const cancelUrl = allowedStripeReturnUrl(c, body.cancel_url || c.env.STRIPE_CANCEL_URL, '/library?checkout=cancelled');
    const requestId = getClientRequestId(c, body) || `checkout_${userId}_${Date.now()}`;
    const session = await stripeApiRequest(c, '/checkout/sessions', {
      mode,
      success_url: successUrl,
      cancel_url: cancelUrl,
      client_reference_id: userId,
      'line_items[0][price]': priceId,
      'line_items[0][quantity]': quantity,
      'metadata[user_id]': userId,
      'metadata[source]': 'flames-up',
    }, requestId);

    if (!session.ok) {
      const message = session.data?.error?.message || session.data?.detail || 'Could not create checkout session.';
      return c.json({ detail: message, code: session.data?.error?.code || 'STRIPE_CHECKOUT_FAILED' }, session.status as any);
    }
    return c.json({
      id: session.data.id,
      url: session.data.url,
      mode: session.data.mode,
      status: session.data.status,
    });
  } catch (error: any) {
    console.error('Stripe checkout failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not create checkout session.', code: 'STRIPE_CHECKOUT_FAILED' }, 500);
  }
});

api.get('/premium', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const user = await getPremiumUser(c, userId);
    if (!user) return c.json({ detail: 'User not found' }, 404);
    const used = await getAnonymousNotesUsedToday(c.env.DB, userId).catch(() => 0);
    const stripe = getStripeConfig(c);
    return c.json({
      ...premiumPayloadFromUser(user, used),
      stripe_connected: stripe.configured,
      price_configured: !!getPremiumPriceId(c),
    });
  } catch (error: any) {
    console.error('Premium load failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load Premium.', code: 'PREMIUM_LOAD_FAILED' }, 500);
  }
});

api.post('/premium/checkout', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 20_000);
    if (bodyTooLarge) return bodyTooLarge;
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'premium_checkout', userId, 8, 60);
    if (limited) return limited;

    await ensurePremiumSchema(c.env.DB);
    const body: any = await c.req.json().catch(() => ({}));
    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
    if (!user) return c.json({ detail: 'User not found' }, 404);
    if (userHasActivePremium(user)) {
      return c.json({ detail: 'Premium is already active on this account.', code: 'PREMIUM_ALREADY_ACTIVE' }, 409);
    }

    const stripe = getStripeConfig(c);
    if (!stripe.configured) {
      return c.json({ detail: 'Stripe is not configured yet.', code: 'STRIPE_NOT_CONFIGURED' }, 503);
    }

    const priceId = getPremiumPriceId(c);
    const successUrl = allowedStripeReturnUrl(c, body.success_url || c.env.STRIPE_SUCCESS_URL, '/wallet?premium=success&session_id={CHECKOUT_SESSION_ID}');
    const cancelUrl = allowedStripeReturnUrl(c, body.cancel_url || c.env.STRIPE_CANCEL_URL, '/wallet?premium=cancelled');
    const requestId = getClientRequestId(c, body) || `premium_${userId}_${Date.now()}`;
    const existingCustomer = cleanText(user.premium_stripe_customer_id, 140);
    const publicEmail = publicUserEmail(user.email);
    const checkoutParams: Record<string, string | number | boolean> = {
      mode: 'subscription',
      success_url: successUrl,
      cancel_url: cancelUrl,
      client_reference_id: userId,
      'line_items[0][quantity]': 1,
      'metadata[source]': 'flames-up-premium',
      'metadata[user_id]': userId,
      'metadata[plan]': PREMIUM_PLAN.id,
      'metadata[price_id]': priceId,
      'subscription_data[metadata][source]': 'flames-up-premium',
      'subscription_data[metadata][user_id]': userId,
      'subscription_data[metadata][plan]': PREMIUM_PLAN.id,
    };
    if (existingCustomer) checkoutParams.customer = existingCustomer;
    else if (publicEmail) checkoutParams.customer_email = publicEmail;
    if (priceId && priceId.startsWith('price_')) {
      checkoutParams['line_items[0][price]'] = priceId;
    } else {
      checkoutParams['line_items[0][price_data][currency]'] = PREMIUM_PLAN.currency;
      checkoutParams['line_items[0][price_data][unit_amount]'] = PREMIUM_PLAN.amount_cents;
      checkoutParams['line_items[0][price_data][recurring][interval]'] = PREMIUM_PLAN.interval;
      checkoutParams['line_items[0][price_data][product_data][name]'] = PREMIUM_PLAN.label;
      checkoutParams['line_items[0][price_data][product_data][metadata][source]'] = 'flames-up-premium';
    }

    const session = await stripeApiRequest(c, '/checkout/sessions', checkoutParams, requestId);
    if (!session.ok) {
      const message = session.data?.error?.message || session.data?.detail || 'Could not start Premium checkout.';
      return c.json({ detail: message, code: session.data?.error?.code || 'PREMIUM_CHECKOUT_FAILED' }, session.status as any);
    }

    await upsertPremiumSubscription(c, {
      userId,
      stripeCustomerId: cleanText(session.data.customer, 140),
      stripeCheckoutSessionId: cleanText(session.data.id, 140),
      priceId,
      status: 'pending',
    });

    return c.json({
      id: session.data.id,
      url: session.data.url,
      mode: session.data.mode,
      status: session.data.status,
      plan: PREMIUM_PLAN.id,
      amount_cents: PREMIUM_PLAN.amount_cents,
    });
  } catch (error: any) {
    console.error('Premium checkout failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not start Premium checkout.', code: 'PREMIUM_CHECKOUT_FAILED' }, 500);
  }
});

api.get('/wallet', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const balance = await getCoinBalance(c.env.DB, userId);
    const txRows: any = await c.env.DB.prepare(
      `SELECT * FROM coin_transactions
       WHERE user_id = ?
       ORDER BY created_at DESC
       LIMIT 30`
    ).bind(userId).all();
    const stripe = getStripeConfig(c);
    return c.json({
      balance: Number(balance.balance || 0),
      lifetime_purchased: Number(balance.lifetime_purchased || 0),
      lifetime_spent: Number(balance.lifetime_spent || 0),
      updated_at: balance.updated_at,
      packages: publicCoinPackages(),
      custom_purchase: { min_coins: 100, max_coins: 50000, cents_per_coin: 1 },
      stripe_connected: stripe.configured,
      transactions: (txRows.results || []).map(sanitizeCoinTransaction),
    });
  } catch (error: any) {
    console.error('Wallet load failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load wallet.', code: 'WALLET_LOAD_FAILED' }, 500);
  }
});

api.get('/wallet/transactions', authMiddleware, async (c) => {
  try {
    await ensureWalletSchema(c.env.DB);
    const userId = getUserId(c);
    const limit = clampNumber(c.req.query('limit'), 1, 100, 50);
    const rows: any = await c.env.DB.prepare(
      `SELECT * FROM coin_transactions
       WHERE user_id = ?
       ORDER BY created_at DESC
       LIMIT ?`
    ).bind(userId, limit).all();
    return c.json({ transactions: (rows.results || []).map(sanitizeCoinTransaction) });
  } catch (error: any) {
    console.error('Wallet history failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load wallet history.', code: 'WALLET_HISTORY_FAILED' }, 500);
  }
});

api.post('/wallet/checkout', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 20_000);
    if (bodyTooLarge) return bodyTooLarge;
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'wallet_checkout', userId, 12, 60);
    if (limited) return limited;

    await ensureWalletSchema(c.env.DB);
    const body: any = await c.req.json().catch(() => ({}));
    const purchase = resolveCoinPurchase(body);
    if (!purchase) {
      return c.json({ detail: 'Choose a coin package or enter at least 100 custom coins.', code: 'COIN_PACKAGE_REQUIRED' }, 400);
    }

    const stripe = getStripeConfig(c);
    if (!stripe.configured) {
      return c.json({ detail: 'Stripe is not configured yet.', code: 'STRIPE_NOT_CONFIGURED' }, 503);
    }

    const ts = now();
    const orderId = uuid();
    await c.env.DB.prepare(
      `INSERT INTO coin_purchase_orders
       (id, user_id, package_id, coins, amount_cents, currency, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 'usd', 'pending', ?, ?)`
    ).bind(orderId, userId, purchase.package_id, purchase.coins, purchase.amount_cents, ts, ts).run();

    const successUrl = allowedStripeReturnUrl(c, body.success_url || c.env.STRIPE_SUCCESS_URL, '/wallet?checkout=success&session_id={CHECKOUT_SESSION_ID}');
    const cancelUrl = allowedStripeReturnUrl(c, body.cancel_url || c.env.STRIPE_CANCEL_URL, '/wallet?checkout=cancelled');
    const requestId = getClientRequestId(c, body) || `wallet_checkout_${orderId}`;
    const session = await stripeApiRequest(c, '/checkout/sessions', {
      mode: 'payment',
      success_url: successUrl,
      cancel_url: cancelUrl,
      client_reference_id: userId,
      'line_items[0][price_data][currency]': 'usd',
      'line_items[0][price_data][product_data][name]': purchase.label,
      'line_items[0][price_data][product_data][metadata][coin_package]': purchase.package_id,
      'line_items[0][price_data][unit_amount]': purchase.amount_cents,
      'line_items[0][quantity]': 1,
      'metadata[source]': 'flames-up-wallet',
      'metadata[user_id]': userId,
      'metadata[wallet_order_id]': orderId,
      'metadata[coin_package]': purchase.package_id,
      'metadata[coins]': purchase.coins,
      'payment_intent_data[metadata][source]': 'flames-up-wallet',
      'payment_intent_data[metadata][user_id]': userId,
      'payment_intent_data[metadata][wallet_order_id]': orderId,
    }, requestId);

    if (!session.ok) {
      await c.env.DB.prepare("UPDATE coin_purchase_orders SET status = 'failed', updated_at = ? WHERE id = ?")
        .bind(now(), orderId)
        .run();
      const message = session.data?.error?.message || session.data?.detail || 'Could not create coin checkout.';
      return c.json({ detail: message, code: session.data?.error?.code || 'COIN_CHECKOUT_FAILED' }, session.status as any);
    }

    await c.env.DB.prepare('UPDATE coin_purchase_orders SET stripe_session_id = ?, updated_at = ? WHERE id = ?')
      .bind(session.data.id || '', now(), orderId)
      .run();

    return c.json({
      id: session.data.id,
      url: session.data.url,
      mode: session.data.mode,
      status: session.data.status,
      order_id: orderId,
      coins: purchase.coins,
      amount_cents: purchase.amount_cents,
    });
  } catch (error: any) {
    console.error('Coin checkout failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not start coin checkout.', code: 'COIN_CHECKOUT_FAILED' }, 500);
  }
});

api.post('/wallet/gifts', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 20_000);
    if (bodyTooLarge) return bodyTooLarge;
    const senderId = getUserId(c);
    const limited = await enforceRateLimit(c, 'coin_gift', senderId, 30, 60);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const receiverId = cleanText(body.to_user_id || body.receiver_id, 80);
    const amount = clampNumber(body.coins || body.amount, 1, 100000, 0);
    if (!receiverId || receiverId === senderId || amount <= 0) {
      return c.json({ detail: 'Choose a user and coin amount to send.', code: 'GIFT_INVALID' }, 400);
    }
    const receiver: any = await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(receiverId).first();
    if (!receiver) return c.json({ detail: 'That user was not found.', code: 'USER_NOT_FOUND' }, 404);
    const giftId = uuid();
    const requestId = getClientRequestId(c, body) || giftId;
    const note = cleanText(body.note, 240);
    const giftType = cleanText(body.gift_type || body.gift_label, 60);
    const postId = cleanText(body.post_id || body.related_post_id, 120);

    await applyCoinDelta(c, {
      userId: senderId,
      type: 'gift_sent',
      amount: -amount,
      relatedUserId: receiverId,
      relatedId: giftId,
      idempotencyKey: `gift_sent_${requestId}`,
      metadata: { note, gift_type: giftType, post_id: postId },
    });
    const received = await applyCoinDelta(c, {
      userId: receiverId,
      type: 'gift_received',
      amount,
      relatedUserId: senderId,
      relatedId: giftId,
      idempotencyKey: `gift_received_${requestId}`,
      metadata: { note, gift_type: giftType, post_id: postId },
    });

    try {
      const sender: any = await c.env.DB.prepare('SELECT username, full_name FROM users WHERE id = ?').bind(senderId).first();
      const senderName = sender?.full_name || sender?.username || 'Someone';
      await insertNotificationOnce(c, {
        userId: receiverId,
        type: 'coin_gift',
        title: 'New Gift',
        body: `${senderName} sent you ${amount} coins`,
        data: { gift_id: giftId, from_user_id: senderId, coins: amount, gift_type: giftType, post_id: postId },
        dedupeKey: `gift:${requestId}`,
        dedupeSeconds: 86400,
      });
    } catch {}

    return c.json({ sent: true, gift_id: giftId, balance: Number((await getCoinBalance(c.env.DB, senderId)).balance || 0), receiver_balance: Number(received.balance.balance || 0) });
  } catch (error: any) {
    if (String(error?.message || '') === 'COINS_INSUFFICIENT') {
      return c.json({ detail: 'Not enough coins for this gift.', code: 'COINS_INSUFFICIENT' }, 409);
    }
    console.error('Coin gift failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not send gift.', code: 'GIFT_FAILED' }, 500);
  }
});

api.post('/wallet/spend', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 20_000);
    if (bodyTooLarge) return bodyTooLarge;
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'coin_spend', userId, 60, 60);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const amount = clampNumber(body.coins || body.amount, 1, 100000, 0);
    const purpose = cleanText(body.purpose || body.reason, 40);
    const type = purpose === 'boost' ? 'boost' : 'spend';
    if (amount <= 0) return c.json({ detail: 'Enter a coin amount to spend.', code: 'SPEND_INVALID' }, 400);
    const result = await applyCoinDelta(c, {
      userId,
      type,
      amount: -amount,
      relatedId: cleanText(body.related_id || body.post_id, 120),
      idempotencyKey: getClientRequestId(c, body) || `${type}_${userId}_${uuid()}`,
      metadata: { purpose },
    });
    return c.json({ spent: true, balance: Number(result.balance.balance || 0), transaction: sanitizeCoinTransaction(result.transaction) });
  } catch (error: any) {
    if (String(error?.message || '') === 'COINS_INSUFFICIENT') {
      return c.json({ detail: 'Not enough coins.', code: 'COINS_INSUFFICIENT' }, 409);
    }
    console.error('Coin spend failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not spend coins.', code: 'SPEND_FAILED' }, 500);
  }
});

api.post('/admin/wallet/adjust', authMiddleware, async (c) => {
  try {
    await requireOwnerOrAdmin(c);
    const bodyTooLarge = rejectLargeRequest(c, 20_000);
    if (bodyTooLarge) return bodyTooLarge;
    const body: any = await c.req.json().catch(() => ({}));
    const userId = cleanText(body.user_id, 80);
    const amount = clampNumber(body.coins || body.amount, -1000000, 1000000, 0);
    if (!userId || amount === 0) {
      return c.json({ detail: 'Choose a user and a non-zero coin adjustment.', code: 'ADJUSTMENT_INVALID' }, 400);
    }
    const adjustmentType = amount > 0 && cleanText(body.type, 40) === 'bonus' ? 'bonus' : 'admin_adjustment';
    const target: any = await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(userId).first();
    if (!target) return c.json({ detail: 'That user was not found.', code: 'USER_NOT_FOUND' }, 404);
    const result = await applyCoinDelta(c, {
      userId,
      type: adjustmentType,
      amount,
      relatedUserId: getUserId(c),
      idempotencyKey: getClientRequestId(c, body) || `admin_adjust_${uuid()}`,
      metadata: { reason: cleanText(body.reason, 500) },
    });
    return c.json({ adjusted: true, balance: Number(result.balance.balance || 0), transaction: sanitizeCoinTransaction(result.transaction) });
  } catch (error: any) {
    if (String(error?.message || '') === 'COINS_INSUFFICIENT') {
      return c.json({ detail: 'Adjustment would make the user balance negative.', code: 'COINS_INSUFFICIENT' }, 409);
    }
    const forbidden = String(error?.message || '') === 'FORBIDDEN';
    console.error('Coin admin adjustment failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: forbidden ? 'Owner access required.' : 'Could not adjust wallet.', code: forbidden ? 'FORBIDDEN' : 'ADJUSTMENT_FAILED' }, forbidden ? 403 : 500);
  }
});

api.post('/stripe/webhook', async (c) => {
  const bodyTooLarge = rejectLargeRequest(c, 500_000);
  if (bodyTooLarge) return bodyTooLarge;
  const secret = String(c.env.STRIPE_WEBHOOK_SECRET || '').trim();
  if (!secret.startsWith('whsec_')) {
    return c.json({ detail: 'Stripe webhook is not configured.', code: 'STRIPE_WEBHOOK_NOT_CONFIGURED' }, 503);
  }

  const rawBody = await c.req.text();
  const signature = String(c.req.header('Stripe-Signature') || '');
  const valid = await verifyStripeWebhookSignature(rawBody, signature, secret);
  if (!valid) {
    return c.json({ detail: 'Invalid Stripe signature.', code: 'STRIPE_SIGNATURE_INVALID' }, 400);
  }

  try {
    const event = JSON.parse(rawBody);
    const object = event?.data?.object || {};
    if (event.type === 'checkout.session.completed') {
      const source = cleanText(object?.metadata?.source, 80);
      if (source === 'flames-up-premium' || object?.mode === 'subscription') {
        await activatePremiumFromCheckoutSession(c, object);
      } else {
        await completeCoinPurchaseFromSession(c, object);
      }
    } else if (event.type === 'checkout.session.expired') {
      const source = cleanText(object?.metadata?.source, 80);
      if (source === 'flames-up-premium' || object?.mode === 'subscription') {
        await expirePremiumCheckout(c, object);
      } else {
        await markCoinPurchaseExpired(c, object);
      }
    } else if (event.type === 'customer.subscription.updated' || event.type === 'customer.subscription.deleted') {
      await syncPremiumFromSubscription(c, object);
    } else if (event.type === 'charge.refunded' || event.type === 'refund.created') {
      await refundCoinPurchase(c, object);
    }
    return c.json({ received: true });
  } catch (error: any) {
    console.error('Stripe webhook failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Webhook processing failed.', code: 'STRIPE_WEBHOOK_FAILED' }, 500);
  }
});

// Reports
api.post('/reports', authMiddleware, async (c) => {
  try {
    return await submitReportRequest(c);
  } catch {
    return c.json({ detail: 'Could not submit report' }, 500);
  }
});

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
  const bodyTooLarge = rejectLargeRequest(c, 1_000_000);
  if (bodyTooLarge) return bodyTooLarge;
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'discover_post_create', userId, 30, 60);
  if (limited) return limited;
  const restricted = await enforceUserRestriction(c, userId, 'posting');
  if (restricted) return restricted;
  const b = await c.req.json().catch(() => ({}));
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image, is_publisher FROM users WHERE id = ?').bind(userId).first();
  if (!user?.is_publisher) return c.json({ detail: 'Publishers only' }, 403);
  const id = uuid();
  await c.env.DB.prepare('INSERT INTO discover_posts (id, user_id, content, image, images, category, location) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(id, userId, b.content || '', b.image || null, JSON.stringify(b.images || []), b.category || 'culture', b.location || '').run();
  return c.json({ id, user_id: userId, user_username: user.username, user_full_name: user.full_name, user_profile_image: safeMediaReference(user.profile_image), content: b.content, category: b.category, created_at: now() });
});

api.get('/discover/feed', authMiddleware, async (c) => {
  const category = c.req.query('category') || 'all';
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '30', 1, 60, 30);
  let sql = `SELECT dp.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image FROM discover_posts dp JOIN users u ON dp.user_id = u.id`;
  const binds: any[] = [];
  if (category !== 'all') {
    sql += ' WHERE dp.category = ?';
    binds.push(category);
  }
  sql += ' ORDER BY dp.created_at DESC LIMIT ? OFFSET ?';
  binds.push(limit, skip);
  const r = binds.length ? await c.env.DB.prepare(sql).bind(...binds).all() : await c.env.DB.prepare(sql).all();
  return c.json((r.results as any[]).map(p => {
    const images = sanitizeMediaReferences(p.images, p.image);
    return {
      ...p,
      image: safeMediaReference(p.image) || images[0] || '',
      images,
      user_username: publicUsernameFor({ username: p.user_username }),
      user_profile_image: safeMediaReference(p.user_profile_image),
    };
  }));
});

api.post('/discover/posts/:postId/like', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  const limited = await enforceRateLimit(c, 'discover_like', userId, 300, 60);
  if (limited) return limited;
  const body: any = await c.req.json().catch(() => ({}));
  const requested = optionalBoolean(body.liked ?? body.like ?? body.value);
  let nextLiked = requested;
  if (nextLiked === null) {
    const ex = await c.env.DB.prepare('SELECT id FROM discover_likes WHERE user_id = ? AND post_id = ?').bind(userId, postId).first();
    nextLiked = !ex;
  }
  const post = await c.env.DB.prepare('SELECT id FROM discover_posts WHERE id = ?').bind(postId).first();
  if (!post) return c.json({ detail: 'Post not found' }, 404);
  const results = nextLiked
    ? await c.env.DB.batch([
      c.env.DB.prepare('INSERT OR IGNORE INTO discover_likes (id, user_id, post_id) VALUES (?, ?, ?)').bind(uuid(), userId, postId),
      c.env.DB.prepare('UPDATE discover_posts SET likes_count = COALESCE(likes_count, 0) + 1 WHERE id = ? AND changes() > 0').bind(postId),
      c.env.DB.prepare('SELECT likes_count FROM discover_posts WHERE id = ?').bind(postId),
    ])
    : await c.env.DB.batch([
      c.env.DB.prepare('DELETE FROM discover_likes WHERE user_id = ? AND post_id = ?').bind(userId, postId),
      c.env.DB.prepare('UPDATE discover_posts SET likes_count = MAX(0, COALESCE(likes_count, 0) - 1) WHERE id = ? AND changes() > 0').bind(postId),
      c.env.DB.prepare('SELECT likes_count FROM discover_posts WHERE id = ?').bind(postId),
    ]);
  return c.json({ liked: !!nextLiked, likes_count: Number((results?.[2] as any)?.results?.[0]?.likes_count || 0) });
});

api.get('/discover/categories', async (c) => {
  return c.json([
    { id: 'all', name: 'All', icon: 'square.grid.2x2' },
    { id: 'photography', name: 'Photography', icon: 'camera' },
    { id: 'outdoors', name: 'Outdoors', icon: 'leaf' },
    { id: 'outfits', name: 'Outfits', icon: 'tshirt' },
    { id: 'travel', name: 'Travel', icon: 'airplane' },
    { id: 'events', name: 'Events', icon: 'calendar' },
    { id: 'nightlife', name: 'Nightlife', icon: 'moon.stars' },
    { id: 'art', name: 'Art', icon: 'paintpalette' },
    { id: 'lifestyle', name: 'Lifestyle', icon: 'sparkles' },
    { id: 'fitness', name: 'Fitness', icon: 'figure.run' },
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
type AdminRole = 'owner' | 'admin' | 'moderator' | 'support' | 'viewer';

type AdminContext = {
  userId: string;
  role: AdminRole;
  user: any;
};

const ADMIN_ROLE_ORDER: AdminRole[] = ['viewer', 'support', 'moderator', 'admin', 'owner'];
const ADMIN_PERMISSIONS: Record<AdminRole, Set<string>> = {
  owner: new Set(['*']),
  admin: new Set([
    'admin:read',
    'reports:read',
    'reports:write',
    'content:read',
    'content:write',
    'users:read',
    'users:private',
    'users:warn',
    'users:restrict',
    'users:suspend',
    'users:ban',
    'messages:reported:read',
    'messages:reported:write',
    'audit:read',
    'roles:write',
  ]),
  moderator: new Set([
    'admin:read',
    'reports:read',
    'reports:write',
    'content:read',
    'content:write',
    'users:read',
    'users:warn',
    'users:restrict',
    'messages:reported:read',
  ]),
  support: new Set([
    'admin:read',
    'reports:read',
    'content:read',
    'users:read',
    'messages:reported:read',
  ]),
  viewer: new Set([
    'admin:read',
    'reports:read',
    'content:read',
    'users:read',
  ]),
};

function normalizeAdminRole(value: unknown): AdminRole | '' {
  const role = cleanText(value, 40).toLowerCase().replace(/[\s-]+/g, '_');
  return ADMIN_ROLE_ORDER.includes(role as AdminRole) ? role as AdminRole : '';
}

function adminCan(role: AdminRole, permission: string): boolean {
  return ADMIN_PERMISSIONS[role]?.has('*') || ADMIN_PERMISSIONS[role]?.has(permission);
}

function adminPermissionList(role: AdminRole): string[] {
  if (role === 'owner') return ['*'];
  return Array.from(ADMIN_PERMISSIONS[role] || []).sort();
}

async function getAdminContext(c: any): Promise<AdminContext | null> {
  await ensureAdminModerationSchema(c.env.DB);
  const userId = getUserId(c);
  if (!userId) return null;
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  if (!user || ['banned', 'deleted'].includes(String(user.status || 'active'))) return null;

  let role = normalizeAdminRole(user.admin_role);
  const roleRow: any = await c.env.DB.prepare('SELECT role FROM admin_roles WHERE user_id = ?').bind(userId).first();
  role = normalizeAdminRole(roleRow?.role) || role;
  if (isOwnerUsername(c, user.username) || isOwnerEmail(c, user.email)) role = 'owner';
  if (!role && Number(user.is_admin || 0) === 1) role = 'admin';
  if (!role) return null;
  return { userId, role, user };
}

async function requireAdminRole(c: any, permission = 'admin:read'): Promise<AdminContext> {
  const admin = await getAdminContext(c);
  if (!admin || !adminCan(admin.role, permission)) throw new Error('FORBIDDEN');
  return admin;
}

const adminGuard = async (c: any, next: () => Promise<void>) => {
  try {
    await requireAdminRole(c, 'admin:read');
    await next();
  } catch {
    return c.json({ detail: 'Admin access required' }, 403);
  }
};

async function requireGovernanceAdmin(c: any): Promise<string> {
  const admin = await requireAdminRole(c, 'admin:read');
  return admin.userId;
}

function governanceError(c: any, error: any) {
  const message = String(error?.message || error || 'Governance request failed');
  if (message !== 'FORBIDDEN') console.error('Governance action failed:', message.slice(0, 180));
  return c.json({ detail: message === 'FORBIDDEN' ? 'Admin access required' : 'Governance request failed.' }, message === 'FORBIDDEN' ? 403 : 500);
}

async function logGovernanceAction(c: any, adminId: string, actionType: string, targetType: string, targetId: string, details: any = {}) {
  await ensureGovernanceSchema(c.env.DB);
  const ts = now();
  await c.env.DB.prepare(
    'INSERT INTO admin_actions (id, admin_id, action_type, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
  ).bind(uuid(), adminId, actionType, targetType, targetId, JSON.stringify(scrubLogMetadata(details || {})), ts).run();
  try {
    const admin = await getAdminContext(c);
    if (admin && admin.userId === adminId) {
      await c.env.DB.batch([
        c.env.DB.prepare(
          `INSERT INTO audit_logs (
             id, actor_admin_user_id, actor_role, action_type, target_type, target_id, target_user_id,
             reason, internal_note, before_state, after_state, ip_hash, request_id, created_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '{}', '{}', ?, ?, ?)`
        ).bind(uuid(), adminId, admin.role, cleanText(actionType, 80), cleanText(targetType, 60), publicId(targetId, 160), cleanText((details || {}).target_user_id || '', 120), cleanMultilineText((details || {}).reason || '', 800), cleanMultilineText((details || {}).note || (details || {}).admin_notes || '', 1000), await safeRequestIpHash(c), cleanText(c.get?.('requestId') || '', 120), ts),
        c.env.DB.prepare(
          `INSERT INTO moderation_actions (
             id, actor_admin_user_id, actor_role, action_type, target_type, target_id, target_user_id, reason, note, created_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).bind(uuid(), adminId, admin.role, cleanText(actionType, 80), cleanText(targetType, 60), publicId(targetId, 160), cleanText((details || {}).target_user_id || '', 120), cleanMultilineText((details || {}).reason || '', 800), cleanMultilineText((details || {}).note || (details || {}).admin_notes || '', 1000), ts),
      ]);
    }
  } catch {
    // Legacy governance routes still keep admin_actions if the richer audit schema is not ready yet.
  }
}

async function safeRequestIpHash(c: any): Promise<string> {
  const ip = clientIp(c);
  const secret = String(c.env.ABUSE_SIGNAL_SECRET || c.env.JWT_SECRET || 'captro-admin-audit');
  return sha256Hex(`${secret}:admin:${ip}`);
}

function safeJsonState(value: any): string {
  if (!value || typeof value !== 'object') return '{}';
  return JSON.stringify(scrubLogMetadata(value));
}

async function writeAdminAuditLog(c: any, admin: AdminContext, input: {
  actionType: string;
  targetType: string;
  targetId: string;
  targetUserId?: string;
  reason?: string;
  note?: string;
  beforeState?: Record<string, unknown>;
  afterState?: Record<string, unknown>;
}) {
  await ensureAdminModerationSchema(c.env.DB);
  const ts = now();
  const reason = cleanMultilineText(input.reason || '', 800);
  const note = cleanMultilineText(input.note || '', 1000);
  const targetUserId = publicId(input.targetUserId || '', 120);
  const requestId = cleanText(c.get?.('requestId') || c.req.header('X-Request-ID') || '', 120);
  const ipHash = await safeRequestIpHash(c);
  const actionType = cleanText(input.actionType, 80);
  const targetType = cleanText(input.targetType, 60);
  const targetId = publicId(input.targetId, 160);

  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO audit_logs (
         id, actor_admin_user_id, actor_role, action_type, target_type, target_id, target_user_id,
         reason, internal_note, before_state, after_state, ip_hash, request_id, created_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(uuid(), admin.userId, admin.role, actionType, targetType, targetId, targetUserId, reason, note, safeJsonState(input.beforeState), safeJsonState(input.afterState), ipHash, requestId, ts),
    c.env.DB.prepare(
      `INSERT INTO moderation_actions (
         id, actor_admin_user_id, actor_role, action_type, target_type, target_id,
         target_user_id, reason, note, created_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(uuid(), admin.userId, admin.role, actionType, targetType, targetId, targetUserId, reason, note, ts),
    c.env.DB.prepare(
      'INSERT INTO admin_actions (id, admin_id, action_type, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).bind(uuid(), admin.userId, actionType, targetType, targetId, JSON.stringify(scrubLogMetadata({ target_user_id: targetUserId, reason, note })), ts),
  ]);
}

async function requireAdminWriteRateLimit(c: any, admin: AdminContext, bucket = 'admin_write') {
  return enforceRateLimit(c, bucket, admin.userId, 80, 60);
}

function normalizeRestrictionType(value: unknown): string {
  const type = cleanText(value || 'all', 60).toLowerCase().replace(/[\s-]+/g, '_');
  return ['all', 'posting', 'commenting', 'messaging', 'discover', 'handshake'].includes(type) ? type : 'all';
}

async function userHasActiveRestriction(c: any, userId: string, type: 'posting' | 'commenting' | 'messaging' | 'discover' | 'handshake'): Promise<boolean> {
  await ensureAdminModerationSchema(c.env.DB);
  const row = await c.env.DB.prepare(
    `SELECT id FROM user_restrictions
     WHERE user_id = ?
       AND restriction_type IN ('all', ?)
       AND datetime(starts_at) <= datetime('now')
       AND (ends_at IS NULL OR ends_at = '' OR datetime(ends_at) > datetime('now'))
     LIMIT 1`
  ).bind(userId, type).first();
  return !!row;
}

async function enforceUserRestriction(c: any, userId: string, type: 'posting' | 'commenting' | 'messaging' | 'discover' | 'handshake') {
  if (!(await userHasActiveRestriction(c, userId, type))) return null;
  return c.json({ detail: `This account is temporarily restricted from ${type}.` }, 403);
}

api.delete('/admin/notes/:noteId', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensureNotesSchema(c.env.DB);
    const noteId = cleanText(c.req.param('noteId'), 80);
    await c.env.DB.prepare("UPDATE notes SET status = 'removed', updated_at = ? WHERE id = ?").bind(now(), noteId).run();
    await logGovernanceAction(c, adminId, 'remove_note', 'note', noteId);
    return c.json({ removed: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.put('/admin/people/:profileId', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensurePeopleSchema(c.env.DB);
    const profileId = cleanText(c.req.param('profileId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const fields = ['name', 'role', 'category', 'bio', 'known_for', 'city', 'profile_image', 'instagram_url', 'tiktok_url', 'youtube_url', 'website_url', 'source_url', 'status'];
    const updates: string[] = [];
    const values: any[] = [];
    for (const field of fields) {
      if (body[field] === undefined) continue;
      updates.push(`${field} = ?`);
      values.push(field.endsWith('_url') || field === 'source_url' ? safeOptionalUrl(body[field]) : cleanText(body[field], field === 'bio' || field === 'known_for' ? 1200 : 240));
    }
    if (updates.length === 0) return c.json({ detail: 'No fields to update.' }, 400);
    updates.push('updated_at = ?');
    values.push(now(), profileId);
    const updatePeopleProfileSql = `UPDATE people_profiles SET ${updates.join(', ')} WHERE id = ?`;
    await c.env.DB.prepare(updatePeopleProfileSql).bind(...values).run();
    await logGovernanceAction(c, adminId, 'edit_people_profile', 'people', profileId, body);
    return c.json({ updated: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.delete('/admin/people/:profileId', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensurePeopleSchema(c.env.DB);
    const profileId = cleanText(c.req.param('profileId'), 120);
    await c.env.DB.prepare("UPDATE people_profiles SET status = 'removed', updated_at = ? WHERE id = ?").bind(now(), profileId).run();
    await logGovernanceAction(c, adminId, 'remove_people_profile', 'people', profileId);
    return c.json({ removed: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/people/claims/:claimId/approve', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensurePeopleSchema(c.env.DB);
    const claimId = cleanText(c.req.param('claimId'), 120);
    const claim: any = await c.env.DB.prepare('SELECT * FROM people_claims WHERE id = ?').bind(claimId).first();
    if (!claim) return c.json({ detail: 'Claim not found.' }, 404);
    const ts = now();
    await c.env.DB.prepare("UPDATE people_claims SET status = 'approved', updated_at = ? WHERE id = ?").bind(ts, claimId).run();
    await c.env.DB.prepare("UPDATE people_profiles SET owner_user_id = ?, claim_status = 'claimed', updated_at = ? WHERE id = ?").bind(claim.user_id, ts, claim.profile_id).run();
    await logGovernanceAction(c, adminId, 'approve_people_claim', 'people_claim', claimId, claim);
    return c.json({ approved: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/people/claims/:claimId/reject', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensurePeopleSchema(c.env.DB);
    const claimId = cleanText(c.req.param('claimId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    await c.env.DB.prepare("UPDATE people_claims SET status = 'rejected', admin_notes = ?, updated_at = ? WHERE id = ?")
      .bind(cleanText(body.admin_notes || body.reason || '', 1000), now(), claimId).run();
    await logGovernanceAction(c, adminId, 'reject_people_claim', 'people_claim', claimId, body);
    return c.json({ rejected: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

async function maybeDeleteStreamAssets(c: any, post: any) {
  const values = [
    post?.image,
    ...parseJsonArray(post?.images),
  ].filter(Boolean).map(String);
  const streamIds = values
    .filter((value) => value.startsWith('cfstream:'))
    .map((value) => value.replace('cfstream:', '').trim())
    .filter(Boolean);

  if (!c.env.CLOUDFLARE_ACCOUNT_ID || !c.env.CLOUDFLARE_STREAM_TOKEN) {
    return { attempted: false, deleted: [], failed: streamIds };
  }

  const deleted: string[] = [];
  const failed: string[] = [];
  for (const uid of streamIds) {
    try {
      const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/stream/${uid}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${c.env.CLOUDFLARE_STREAM_TOKEN}` },
      });
      if (response.ok) deleted.push(uid);
      else failed.push(uid);
    } catch {
      failed.push(uid);
    }
  }
  return { attempted: streamIds.length > 0, deleted, failed };
}

api.post('/admin/music/sounds/:trackId/hide', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensureAudioSchema(c.env.DB);
    const trackId = cleanText(c.req.param('trackId'), 80);
    if (!trackId) return c.json({ detail: 'Track id is required.' }, 400);
    const body: any = await c.req.json().catch(() => ({}));
    const reason = cleanText(body.reason || 'Hidden by moderation', 300);
    await c.env.DB.prepare(
      "INSERT OR REPLACE INTO hidden_sounds (track_id, provider, reason, hidden_by, created_at) VALUES (?, 'audius', ?, ?, ?)"
    ).bind(trackId, reason, adminId, now()).run();
    await c.env.DB.prepare("UPDATE posts SET audio_hidden = 1 WHERE audio_provider = 'audius' AND audio_track_id = ?")
      .bind(trackId)
      .run();
    await logGovernanceAction(c, adminId, 'hide_sound', 'sound', trackId, { provider: 'audius', reason });
    return c.json({ hidden: true, track_id: trackId });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.delete('/admin/music/sounds/:trackId/hide', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensureAudioSchema(c.env.DB);
    const trackId = cleanText(c.req.param('trackId'), 80);
    if (!trackId) return c.json({ detail: 'Track id is required.' }, 400);
    await c.env.DB.prepare("DELETE FROM hidden_sounds WHERE provider = 'audius' AND track_id = ?")
      .bind(trackId)
      .run();
    await c.env.DB.prepare("UPDATE posts SET audio_hidden = 0 WHERE audio_provider = 'audius' AND audio_track_id = ?")
      .bind(trackId)
      .run();
    await logGovernanceAction(c, adminId, 'unhide_sound', 'sound', trackId, { provider: 'audius' });
    return c.json({ hidden: false, track_id: trackId });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/music/settings', authMiddleware, async (c) => {
  try {
    await requireGovernanceAdmin(c);
    await ensureAiMusicSchema(c.env.DB);
    const rows = await c.env.DB.prepare(
      "SELECT key, value FROM app_settings WHERE key IN ('music_daily_generation_limit', 'music_generation_cooldown_seconds')"
    ).all();
    const settings = Object.fromEntries((rows.results as any[]).map((row) => [row.key, row.value]));
    return c.json({
      daily_generation_limit: Number(settings.music_daily_generation_limit || c.env.MUSIC_DAILY_GENERATION_LIMIT || 5),
      cooldown_seconds: Number(settings.music_generation_cooldown_seconds || c.env.MUSIC_GENERATION_COOLDOWN_SECONDS || 60),
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.put('/admin/music/settings', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensureAiMusicSchema(c.env.DB);
    const body: any = await c.req.json().catch(() => ({}));
    const dailyLimit = clampNumber(body.daily_generation_limit, 1, 50, 5);
    const cooldown = clampNumber(body.cooldown_seconds, 0, 3600, 60);
    const ts = now();
    await c.env.DB.prepare(
      'INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at'
    ).bind('music_daily_generation_limit', String(dailyLimit), ts).run();
    await c.env.DB.prepare(
      'INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at'
    ).bind('music_generation_cooldown_seconds', String(cooldown), ts).run();
    await logGovernanceAction(c, adminId, 'update_ai_music_settings', 'settings', 'ai_music', { dailyLimit, cooldown });
    return c.json({ daily_generation_limit: dailyLimit, cooldown_seconds: cooldown });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.delete('/admin/music/:musicId', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensureAiMusicSchema(c.env.DB);
    const musicId = cleanText(c.req.param('musicId'), 80);
    const music: any = await c.env.DB.prepare('SELECT * FROM ai_music_posts WHERE id = ?').bind(musicId).first();
    if (!music) return c.json({ detail: 'Music post not found.' }, 404);
    await c.env.DB.prepare("UPDATE ai_music_posts SET status = 'removed', is_public = 0, updated_at = ? WHERE id = ?")
      .bind(now(), musicId)
      .run();
    await logGovernanceAction(c, adminId, 'remove_ai_music', 'ai_music', musicId, { provider: music.provider, user_id: music.user_id });
    return c.json({ removed: true, id: musicId });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/governance/posts/:postId/audio/remove', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensureAudioSchema(c.env.DB);
    const postId = c.req.param('postId');
    const body: any = await c.req.json().catch(() => ({}));
    await c.env.DB.prepare(
      `UPDATE posts
       SET audio_hidden = 1, audio_provider = '', audio_track_id = '', audio_title = '', audio_artist = '',
           audio_artwork_url = '', audio_stream_url = '', audio_start_time = 0, audio_duration = 0
       WHERE id = ?`
    ).bind(postId).run();
    await logGovernanceAction(c, adminId, 'remove_post_sound', 'post', postId, { reason: cleanText(body.reason, 300) });
    return c.json({ removed: true, post_id: postId });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/governance/me', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(adminId).first();
    return c.json(authUserPayload(user));
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/governance/stats', authMiddleware, async (c) => {
  try {
    await requireGovernanceAdmin(c);
    const [pendingReports, bannedUsers, removedPosts, activeUsers] = await Promise.all([
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM reports WHERE COALESCE(status, 'pending') = 'pending'").first(),
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM users WHERE COALESCE(status, 'active') = 'banned'").first(),
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM posts WHERE COALESCE(status, 'active') = 'removed'").first(),
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM users WHERE COALESCE(status, 'active') != 'banned'").first(),
    ]);
    return c.json({
      pending_reports: (pendingReports as any)?.count || 0,
      banned_users: (bannedUsers as any)?.count || 0,
      removed_posts: (removedPosts as any)?.count || 0,
      active_users: (activeUsers as any)?.count || 0,
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/governance/reports', authMiddleware, async (c) => {
  try {
    await requireGovernanceAdmin(c);
    const status = c.req.query('status') || 'pending';
    const bindings: string[] = [];
    let where = '';
    if (status !== 'all') {
      where = "WHERE COALESCE(r.status, 'pending') = ?";
      bindings.push(status);
    }
    const query = `
      SELECT
        r.id,
        r.reporter_id,
        r.reported_id,
        COALESCE(NULLIF(r.reported_type, ''), r.report_type, 'other') AS reported_type,
        r.report_type,
        r.reason,
        r.details,
        r.content_id,
        COALESCE(r.status, 'pending') AS status,
        r.admin_notes,
        r.action_taken,
        COALESCE(r.priority, 'normal') AS priority,
        r.reviewed_by,
        r.reviewed_at,
        r.created_at,
        r.updated_at,
        reporter.username AS reporter_username,
        reporter.full_name AS reporter_full_name,
        reporter.profile_image AS reporter_profile_image,
        target_user.username AS target_username,
        target_user.full_name AS target_full_name,
        target_user.profile_image AS target_profile_image,
        target_user.status AS target_status,
        p.id AS post_id,
        p.user_id AS post_user_id,
        p.content AS post_content,
        p.image AS post_image,
        p.images AS post_images,
        p.media_types AS post_media_types,
        p.status AS post_status,
        post_author.username AS post_author_username,
        post_author.full_name AS post_author_full_name
      FROM reports r
      LEFT JOIN users reporter ON reporter.id = r.reporter_id
      LEFT JOIN users target_user ON target_user.id = r.reported_id
      LEFT JOIN posts p ON p.id = COALESCE(r.content_id, CASE WHEN COALESCE(NULLIF(r.reported_type, ''), r.report_type) = 'post' THEN r.reported_id ELSE NULL END)
      LEFT JOIN users post_author ON post_author.id = p.user_id
      ${where}
      ORDER BY CASE COALESCE(r.priority, 'normal') WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END, r.created_at DESC
      LIMIT 100
    `;
    const result = bindings.length
      ? await c.env.DB.prepare(query).bind(...bindings).all()
      : await c.env.DB.prepare(query).all();
    return c.json((result.results as any[]).map((report) => ({
      ...report,
      post_images: parseJsonArray(report.post_images),
      post_media_types: parseJsonArray(report.post_media_types),
    })));
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/governance/reports/:reportId/resolve', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    const reportId = c.req.param('reportId');
    const body: any = await c.req.json().catch(() => ({}));
    const actionTaken = cleanText(body.action_taken || body.action || 'action_taken', 120);
    await c.env.DB.prepare(
      "UPDATE reports SET status = 'action_taken', admin_notes = ?, action_taken = ?, reviewed_by = ?, reviewed_at = ?, updated_at = ? WHERE id = ?"
    ).bind(cleanMultilineText(body.admin_notes || '', 1000), actionTaken, adminId, now(), now(), reportId).run();
    await logGovernanceAction(c, adminId, 'resolve_report', 'report', reportId, body);
    return c.json({ resolved: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/governance/reports/:reportId/dismiss', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    const reportId = c.req.param('reportId');
    const body: any = await c.req.json().catch(() => ({}));
    await c.env.DB.prepare(
      "UPDATE reports SET status = 'dismissed', admin_notes = ?, action_taken = 'dismissed', reviewed_by = ?, reviewed_at = ?, updated_at = ? WHERE id = ?"
    ).bind(cleanMultilineText(body.admin_notes || '', 1000), adminId, now(), now(), reportId).run();
    await logGovernanceAction(c, adminId, 'dismiss_report', 'report', reportId, body);
    return c.json({ dismissed: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/governance/reports/:reportId/status', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    const reportId = c.req.param('reportId');
    const body: any = await c.req.json().catch(() => ({}));
    const status = normalizeReportStatus(body.status, 'under_review');
    const actionTaken = cleanText(body.action_taken || body.action || status, 120);
    const adminNotes = cleanMultilineText(body.admin_notes || body.notes || '', 1000);
    const ts = now();
    await c.env.DB.prepare(
      'UPDATE reports SET status = ?, admin_notes = ?, action_taken = ?, reviewed_by = ?, reviewed_at = ?, updated_at = ? WHERE id = ?'
    ).bind(status, adminNotes, actionTaken, adminId, ts, ts, reportId).run();
    await logGovernanceAction(c, adminId, `report_${status}`, 'report', reportId, { status, action_taken: actionTaken, admin_notes: adminNotes });
    return c.json({ updated: true, status });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/governance/ban-evasion', authMiddleware, async (c) => {
  try {
    await requireGovernanceAdmin(c);
    await ensureAbuseProtectionSchema(c.env.DB);
    const status = normalizeReportStatus(c.req.query('status') || 'pending', 'pending');
    const rows = await c.env.DB.prepare(
      `SELECT f.*, u.username, u.full_name, u.profile_image, u.status AS user_status,
              matched.username AS matched_username, matched.full_name AS matched_full_name, matched.status AS matched_status
       FROM ban_evasion_flags f
       LEFT JOIN users u ON u.id = f.user_id
       LEFT JOIN users matched ON matched.id = f.matched_user_id
       WHERE COALESCE(f.status, 'pending') = ?
       ORDER BY f.created_at DESC
       LIMIT 100`
    ).bind(status).all();
    return c.json(rows.results || []);
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/governance/ban-evasion/:flagId/review', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensureAbuseProtectionSchema(c.env.DB);
    const flagId = c.req.param('flagId');
    const body: any = await c.req.json().catch(() => ({}));
    const status = normalizeReportStatus(body.status, 'under_review');
    const adminNotes = cleanMultilineText(body.admin_notes || body.notes || '', 1000);
    const ts = now();
    await c.env.DB.prepare(
      'UPDATE ban_evasion_flags SET status = ?, admin_notes = ?, reviewed_by = ?, reviewed_at = ?, updated_at = ? WHERE id = ?'
    ).bind(status, adminNotes, adminId, ts, ts, flagId).run();
    await logGovernanceAction(c, adminId, `ban_evasion_${status}`, 'ban_evasion_flag', flagId, { status, admin_notes: adminNotes });
    return c.json({ updated: true, status });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/governance/users/:userId/ban', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    const targetUserId = c.req.param('userId');
    if (targetUserId === adminId) return c.json({ detail: 'Admins cannot ban themselves.' }, 400);
    const body: any = await c.req.json().catch(() => ({}));
    const target: any = await c.env.DB.prepare('SELECT username, full_name, bio, social_website, social_tiktok, social_instagram FROM users WHERE id = ?').bind(targetUserId).first();
    if (!target) return c.json({ detail: 'User not found.' }, 404);
    await recordAbuseSignals(c, targetUserId, 'admin_ban', {
      username: target.username,
      display_name: target.full_name,
      bio: target.bio,
      links: [target.social_website, target.social_tiktok, target.social_instagram].filter(Boolean),
    });
    await c.env.DB.prepare("UPDATE users SET status = 'banned', banned_at = ?, ban_reason = ?, updated_at = datetime('now') WHERE id = ?")
      .bind(now(), body.reason || 'Banned by governance', targetUserId)
      .run();
    await logGovernanceAction(c, adminId, 'ban_user', 'user', targetUserId, body);
    return c.json({ banned: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/governance/users/:userId/suspend', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    const targetUserId = c.req.param('userId');
    if (targetUserId === adminId) return c.json({ detail: 'Admins cannot suspend themselves.' }, 400);
    const body: any = await c.req.json().catch(() => ({}));
    const reason = cleanMultilineText(body.reason || 'Suspended by governance', 500);
    await c.env.DB.prepare("UPDATE users SET status = 'suspended', ban_reason = ?, updated_at = datetime('now') WHERE id = ?")
      .bind(reason, targetUserId)
      .run();
    await logGovernanceAction(c, adminId, 'suspend_user', 'user', targetUserId, { reason });
    return c.json({ suspended: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/governance/users/:userId/unban', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    const targetUserId = c.req.param('userId');
    const body: any = await c.req.json().catch(() => ({}));
    await c.env.DB.prepare("UPDATE users SET status = 'active', banned_at = NULL, ban_reason = '', updated_at = datetime('now') WHERE id = ?")
      .bind(targetUserId)
      .run();
    await logGovernanceAction(c, adminId, 'unban_user', 'user', targetUserId, body);
    return c.json({ unbanned: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/governance/posts/:postId/remove', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    const postId = c.req.param('postId');
    const body: any = await c.req.json().catch(() => ({}));
    const post: any = await c.env.DB.prepare('SELECT * FROM posts WHERE id = ?').bind(postId).first();
    if (!post) return c.json({ detail: 'Post not found' }, 404);
    const stream = body.delete_stream ? await maybeDeleteStreamAssets(c, post) : { attempted: false, deleted: [], failed: [] };
    await c.env.DB.prepare("UPDATE posts SET status = 'removed', removed_at = ?, removed_reason = ? WHERE id = ?")
      .bind(now(), body.reason || 'Removed by governance', postId)
      .run();
    await logGovernanceAction(c, adminId, 'remove_post', 'post', postId, { ...body, stream });
    return c.json({ removed: true, stream });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/governance/comments/:commentId/remove', authMiddleware, async (c) => {
  try {
    const adminId = await requireGovernanceAdmin(c);
    await ensureGovernanceSchema(c.env.DB);
    const commentId = c.req.param('commentId');
    const body: any = await c.req.json().catch(() => ({}));
    const reason = cleanMultilineText(body.reason || 'Removed by governance', 500);
    await c.env.DB.prepare("UPDATE comments SET status = 'removed', removed_at = ?, removed_reason = ? WHERE id = ?")
      .bind(now(), reason, commentId)
      .run();
    await logGovernanceAction(c, adminId, 'remove_comment', 'comment', commentId, { reason });
    return c.json({ removed: true, soft_deleted: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/governance/actions', authMiddleware, async (c) => {
  try {
    await requireGovernanceAdmin(c);
    const result = await c.env.DB.prepare(`
      SELECT a.*, u.username AS admin_username, u.full_name AS admin_full_name
      FROM admin_actions a
      LEFT JOIN users u ON u.id = a.admin_id
      ORDER BY a.created_at DESC
      LIMIT 100
    `).all();
    return c.json((result.results as any[]).map((action) => ({
      ...action,
      details: action.details ? JSON.parse(action.details) : {},
    })));
  } catch (error: any) {
    return governanceError(c, error);
  }
});

function adminPageParams(c: any, defaultLimit = 50, maxLimit = 100) {
  const limit = clampNumber(c.req.query('limit') || defaultLimit, 1, maxLimit, defaultLimit);
  const page = clampNumber(c.req.query('page') || '1', 1, 1_000_000, 1);
  const offset = clampNumber(c.req.query('offset') || ((page - 1) * limit), 0, 1_000_000_000, 0);
  return { limit, page, offset };
}

function searchPattern(value: unknown): string {
  const query = cleanText(value, 120).toLowerCase();
  return query ? `%${query}%` : '';
}

function roleCanViewPrivateUserFields(role: AdminRole): boolean {
  return adminCan(role, 'users:private');
}

function adminUserPayload(row: any, role: AdminRole) {
  const payload: any = {
    id: row.id,
    username: publicUsernameFor(row),
    raw_username: cleanText(row.username, 80),
    full_name: cleanText(row.full_name, 120),
    profile_image: safeMediaReference(row.profile_image),
    bio: cleanMultilineText(row.bio, 500),
    city: cleanText(row.city, 120),
    status: cleanText(row.status || 'active', 40),
    suspended_until: row.suspended_until || null,
    banned_at: row.banned_at || null,
    ban_reason: cleanMultilineText(row.ban_reason, 500),
    warning_count: Number(row.warning_count || 0),
    followers_count: Number(row.followers_count || 0),
    following_count: Number(row.following_count || 0),
    posts_count: Number(row.posts_count || 0),
    report_count: Number(row.report_count || row.reports_count || 0),
    is_admin: Number(row.is_admin || 0) === 1,
    is_creator: Number(row.is_creator || 0) === 1,
    is_verified: Number(row.is_verified || 0) === 1,
    created_at: row.created_at || '',
    updated_at: row.updated_at || '',
  };
  if (roleCanViewPrivateUserFields(role)) {
    payload.email = publicUserEmail(row.email);
    payload.phone = row.phone || '';
  }
  return payload;
}

function adminPostPayload(row: any, env: Env) {
  const mediaUrls = sanitizeMediaReferences(row.images, row.image);
  const mediaTypes = parseJsonArray(row.media_types);
  const dimensions = parseJsonArray(row.media_dimensions);
  const primaryCategory = normalizeDiscoverCategory(row.primary_category || row.category || row.post_type || 'lifestyle', false) || 'lifestyle';
  const categoryConfidence = clampFloat(row.category_confidence, 0, 1, 0);
  const tags = sanitizeAutoCategoryTags(row.tags_json);
  const categorySignals = parseJsonObject(row.category_signals_json);
  const thumbnailVariant = env.CLOUDFLARE_IMAGES_THUMBNAIL_VARIANT || '';
  const feedVariant = env.CLOUDFLARE_IMAGES_FEED_VARIANT || '';
  const normalizedTypes = mediaTypes.length ? mediaTypes : mediaUrls.map((url) => isVideoMediaUrl(url) ? 'video' : 'image');
  const media = mediaUrls.map((url, index) => {
    const mediaType = String(normalizedTypes[index] || 'image').toLowerCase().includes('video') || isVideoMediaUrl(url) ? 'video' : 'image';
    const feedUrl = mediaType === 'video' ? streamPlaybackUrl(url) : feedDeliveryUrl(url, mediaType, feedVariant);
    const thumbnailUrl = mediaType === 'video'
      ? streamThumbnailUrl(url)
      : posterDeliveryUrl(url, mediaType, thumbnailVariant);
    const original = dimensions[index] || {};
    const width = Number(original.feed_width || original.width || original.original_width || 0) || null;
    const height = Number(original.feed_height || original.height || original.original_height || 0) || null;
    const aspectRatio = Number(original.feed_aspect_ratio || original.ratio || original.aspect_ratio || (width && height ? width / height : 0)) || null;
    return {
      type: mediaType,
      media_type: mediaType,
      feed_media_url: feedUrl,
      feedUrl,
      thumbnail_url: thumbnailUrl || feedUrl,
      thumbnailUrl: thumbnailUrl || feedUrl,
      poster_url: thumbnailUrl || '',
      posterUrl: thumbnailUrl || '',
      width,
      height,
      aspect_ratio: aspectRatio,
      aspectRatio,
    };
  });
  const first: any = media[0] || {};
  return {
    id: row.id,
    user_id: row.user_id,
    author: {
      id: row.user_id,
      username: publicUsernameFor({ username: row.user_username || row.username }),
      full_name: cleanText(row.user_full_name || row.full_name, 120),
      profile_image: safeMediaReference(row.user_profile_image || row.profile_image),
    },
    title: cleanText(row.title || '', 180),
    content: cleanMultilineText(row.content, 1200),
    category: primaryCategory,
    primary_category: primaryCategory,
    category_confidence: categoryConfidence,
    category_source: normalizeCategorySource(row.category_source),
    category_status: normalizeCategoryStatus(row.category_status),
    category_signals: categorySignals,
    category_signals_json: categorySignals,
    tags,
    visibility: cleanText(row.visibility || 'public', 40),
    status: cleanText(row.status || 'active', 40),
    removed_at: row.removed_at || null,
    removed_reason: cleanMultilineText(row.removed_reason, 500),
    discover_blocked_at: row.discover_blocked_at || null,
    discover_blocked_reason: cleanMultilineText(row.discover_blocked_reason, 500),
    display_location_label: normalizeDisplayLocationLabel(row.display_city || '', row.display_region || '', row.display_country || '', row.display_location_label || ''),
    display_location_visibility: normalizeDisplayLocationVisibility(row.display_location_visibility),
    display_location_source: normalizeDisplayLocationSource(row.display_location_source),
    exact_place: {
      provider: cleanText(row.place_provider, 40),
      provider_place_id: cleanText(row.place_provider_id || row.place_id, 160),
      name: cleanText(row.place_name, 180),
      formatted_address: cleanText(row.place_formatted_address || row.location, 260),
      category: cleanText(row.place_category, 80),
      city: cleanText(row.place_city, 80),
      region: cleanText(row.place_region, 80),
      country: cleanText(row.place_country, 80),
      latitude: row.place_lat == null ? null : clampFloat(row.place_lat, -90, 90, 0),
      longitude: row.place_lng == null ? null : clampFloat(row.place_lng, -180, 180, 0),
    },
    media_type: first.media_type || '',
    feed_media_url: first.feed_media_url || '',
    thumbnail_url: first.thumbnail_url || '',
    poster_url: first.poster_url || '',
    width: first.width || null,
    height: first.height || null,
    aspect_ratio: first.aspect_ratio || null,
    image: first.feed_media_url || '',
    images: media.map((item) => item.feed_media_url).filter(Boolean),
    feed_media_urls: media.map((item) => item.feed_media_url).filter(Boolean),
    thumbnail_urls: media.map((item) => item.thumbnail_url).filter(Boolean),
    poster_urls: media.map((item) => item.poster_url).filter(Boolean),
    media_types: media.map((item) => item.media_type),
    media,
    likes_count: Number(row.likes_count || 0),
    comments_count: Number(row.comments_count || 0),
    saves_count: Number(row.saves_count || 0),
    created_at: row.created_at || '',
    updated_at: row.updated_at || '',
  };
}

function adminCommentPayload(row: any) {
  return {
    id: row.id,
    user_id: row.user_id,
    post_id: row.post_id,
    parent_id: row.parent_id || null,
    content: cleanMultilineText(row.content, 1200),
    status: cleanText(row.status || 'active', 40),
    removed_at: row.removed_at || null,
    removed_reason: cleanMultilineText(row.removed_reason, 500),
    hidden_at: row.hidden_at || null,
    hidden_by_user_id: row.hidden_by_user_id || '',
    likes_count: Number(row.likes_count || 0),
    author: {
      id: row.user_id,
      username: publicUsernameFor({ username: row.user_username || row.username }),
      full_name: cleanText(row.user_full_name || row.full_name, 120),
      profile_image: safeMediaReference(row.user_profile_image || row.profile_image),
    },
    post_author_id: row.post_user_id || '',
    created_at: row.created_at || '',
    updated_at: row.updated_at || '',
  };
}

function reportTargetType(row: any): string {
  return normalizeReportTargetType(row?.reported_type || row?.report_type || 'other');
}

function adminReportSummary(row: any, env?: Env) {
  const type = reportTargetType(row);
  const targetPost = env && (row.post_id || row.post_image || row.post_images) ? adminPostPayload({
    id: row.post_id || row.reported_id,
    user_id: row.post_user_id || row.target_owner_user_id || '',
    content: row.post_content || '',
    title: row.post_title || '',
    image: row.post_image || '',
    images: row.post_images || '',
    media_types: row.post_media_types || '',
    media_dimensions: row.post_media_dimensions || '',
    status: row.post_status || '',
    user_username: row.target_username || '',
    user_full_name: row.target_full_name || '',
    user_profile_image: row.target_profile_image || '',
  }, env) : null;
  return {
    id: row.id,
    reporter_id: row.reporter_id,
    reported_id: row.reported_id,
    target_type: type,
    target_id: row.reported_id,
    target_owner_user_id: row.target_owner_user_id || row.post_user_id || row.comment_user_id || row.message_sender_id || '',
    reason: normalizeReportReason(row.reason),
    details: cleanMultilineText(row.details, 1000),
    status: normalizeReportStatus(row.status, 'pending'),
    priority: cleanText(row.priority || 'normal', 20),
    assigned_to: row.assigned_to || '',
    created_at: row.created_at || '',
    updated_at: row.updated_at || '',
    closed_at: row.closed_at || null,
    reporter: {
      id: row.reporter_id,
      username: publicUsernameFor({ username: row.reporter_username }),
      full_name: cleanText(row.reporter_full_name, 120),
      profile_image: safeMediaReference(row.reporter_profile_image),
    },
    target_user: {
      id: row.target_user_id || '',
      username: publicUsernameFor({ username: row.target_username }),
      full_name: cleanText(row.target_full_name, 120),
      profile_image: safeMediaReference(row.target_profile_image),
      status: cleanText(row.target_status || '', 40),
    },
    preview: cleanMultilineText(row.target_preview || row.post_content || row.comment_content || row.message_content || '', 400),
    target_media: targetPost?.media?.[0] || null,
  };
}

async function getAdminReportRow(c: any, reportId: string) {
  return c.env.DB.prepare(`
    SELECT
      r.*,
      reporter.username AS reporter_username,
      reporter.full_name AS reporter_full_name,
      reporter.profile_image AS reporter_profile_image,
      p.id AS post_id,
      p.user_id AS post_user_id,
      p.content AS post_content,
      p.title AS post_title,
      p.image AS post_image,
      p.images AS post_images,
      p.media_types AS post_media_types,
      p.status AS post_status,
      cm.id AS comment_id,
      cm.user_id AS comment_user_id,
      cm.content AS comment_content,
      cm.status AS comment_status,
      msg.id AS message_id,
      msg.sender_id AS message_sender_id,
      msg.receiver_id AS message_receiver_id,
      msg.content AS message_content,
      msg.media_type AS message_media_type,
      msg.status AS message_status,
      target_user.id AS target_user_id,
      target_user.username AS target_username,
      target_user.full_name AS target_full_name,
      target_user.profile_image AS target_profile_image,
      target_user.status AS target_status
    FROM reports r
    LEFT JOIN users reporter ON reporter.id = r.reporter_id
    LEFT JOIN posts p ON p.id = r.reported_id OR p.id = r.content_id
    LEFT JOIN comments cm ON cm.id = r.reported_id
    LEFT JOIN messages msg ON msg.id = r.reported_id
    LEFT JOIN users target_user ON target_user.id = COALESCE(NULLIF(r.target_owner_user_id, ''), p.user_id, cm.user_id, msg.sender_id, r.reported_id)
    WHERE r.id = ?
    LIMIT 1
  `).bind(reportId).first();
}

async function reportTargetPreview(c: any, report: any) {
  const type = reportTargetType(report);
  if (type === 'post' && (report.post_id || report.reported_id)) {
    const row: any = await c.env.DB.prepare(`
      SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM posts p
      LEFT JOIN users u ON u.id = p.user_id
      WHERE p.id = ?
      LIMIT 1
    `).bind(report.post_id || report.reported_id).first();
    return row ? { type: 'post', post: adminPostPayload(row, c.env) } : { type: 'post', missing: true };
  }
  if (type === 'comment' && (report.comment_id || report.reported_id)) {
    const row: any = await c.env.DB.prepare(`
      SELECT c.*, p.user_id AS post_user_id, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM comments c
      LEFT JOIN posts p ON p.id = c.post_id
      LEFT JOIN users u ON u.id = c.user_id
      WHERE c.id = ?
      LIMIT 1
    `).bind(report.comment_id || report.reported_id).first();
    return row ? { type: 'comment', comment: adminCommentPayload(row) } : { type: 'comment', missing: true };
  }
  if (type === 'message' && (report.message_id || report.reported_id)) {
    const row: any = await c.env.DB.prepare(`
      SELECT m.*, sender.username AS sender_username, sender.full_name AS sender_full_name, receiver.username AS receiver_username, receiver.full_name AS receiver_full_name
      FROM messages m
      LEFT JOIN users sender ON sender.id = m.sender_id
      LEFT JOIN users receiver ON receiver.id = m.receiver_id
      WHERE m.id = ?
      LIMIT 1
    `).bind(report.message_id || report.reported_id).first();
    if (!row) return { type: 'message', missing: true };
    return {
      type: 'message',
      message: {
        id: row.id,
        sender_id: row.sender_id,
        receiver_id: row.receiver_id,
        sender_username: publicUsernameFor({ username: row.sender_username }),
        sender_full_name: cleanText(row.sender_full_name, 120),
        receiver_username: publicUsernameFor({ username: row.receiver_username }),
        receiver_full_name: cleanText(row.receiver_full_name, 120),
        content: cleanMultilineText(row.content, 2000),
        media_type: cleanText(row.media_type, 40),
        status: cleanText(row.status || 'active', 40),
        created_at: row.created_at,
      },
    };
  }
  if ((type === 'profile' || type === 'user') && report.reported_id) {
    const row: any = await c.env.DB.prepare(`
      SELECT u.*,
        (SELECT COUNT(*) FROM reports rr WHERE rr.reported_id = u.id OR rr.target_owner_user_id = u.id) AS report_count
      FROM users u WHERE u.id = ? LIMIT 1
    `).bind(report.reported_id).first();
    return row ? { type: 'user', user: adminUserPayload(row, 'viewer') } : { type: 'user', missing: true };
  }
  return { type, missing: true };
}

async function adminReportDetail(c: any, report: any) {
  const notes = await c.env.DB.prepare(`
    SELECT n.*, u.username AS admin_username, u.full_name AS admin_full_name
    FROM moderation_notes n
    LEFT JOIN users u ON u.id = n.author_admin_user_id
    WHERE n.report_id = ?
    ORDER BY n.created_at DESC
    LIMIT 40
  `).bind(report.id).all();
  const actions = await c.env.DB.prepare(`
    SELECT a.*, u.username AS admin_username, u.full_name AS admin_full_name
    FROM moderation_actions a
    LEFT JOIN users u ON u.id = a.actor_admin_user_id
    WHERE a.target_id = ? OR a.target_user_id = ?
    ORDER BY a.created_at DESC
    LIMIT 30
  `).bind(report.reported_id || report.id, report.target_owner_user_id || report.reported_id || '').all();
  return {
    ...adminReportSummary(report, c.env),
    admin_notes: cleanMultilineText(report.admin_notes, 1000),
    action_taken: cleanText(report.action_taken, 120),
    reviewed_by: report.reviewed_by || '',
    reviewed_at: report.reviewed_at || null,
    target: await reportTargetPreview(c, report),
    notes: (notes.results as any[]).map((note) => ({
      id: note.id,
      note: cleanMultilineText(note.note, 1000),
      created_at: note.created_at,
      admin: {
        id: note.author_admin_user_id,
        username: publicUsernameFor({ username: note.admin_username }),
        full_name: cleanText(note.admin_full_name, 120),
      },
    })),
    previous_actions: (actions.results as any[]).map((action) => ({
      ...action,
      reason: cleanMultilineText(action.reason, 500),
      note: cleanMultilineText(action.note, 800),
    })),
  };
}

async function setReportStatus(c: any, admin: AdminContext, reportId: string, status: string, reason: string, note: string) {
  const before: any = await c.env.DB.prepare('SELECT id, status, reported_id, reported_type, report_type FROM reports WHERE id = ?').bind(reportId).first();
  if (!before) return c.json({ detail: 'Report not found.' }, 404);
  const normalizedStatus = normalizeReportStatus(status, 'under_review');
  const closedAt = ['action_taken', 'dismissed', 'closed', 'duplicate'].includes(normalizedStatus) ? now() : null;
  const ts = now();
  await c.env.DB.prepare(
    `UPDATE reports
     SET status = ?, admin_notes = ?, action_taken = ?, reviewed_by = ?, reviewed_at = ?, updated_at = ?, closed_at = COALESCE(?, closed_at)
     WHERE id = ?`
  ).bind(normalizedStatus, note, normalizedStatus, admin.userId, ts, ts, closedAt, reportId).run();
  await writeAdminAuditLog(c, admin, {
    actionType: `report_${normalizedStatus}`,
    targetType: 'report',
    targetId: reportId,
    targetUserId: before.reported_id || '',
    reason,
    note,
    beforeState: { status: before.status },
    afterState: { status: normalizedStatus },
  });
  const updated = await getAdminReportRow(c, reportId);
  return c.json({ report: await adminReportDetail(c, updated) });
}

api.get('/admin/health', authMiddleware, async (c) => {
  try {
    await requireAdminRole(c, 'admin:read');
    await ensureAdminModerationSchema(c.env.DB);
    const db: any = await c.env.DB.prepare('SELECT 1 AS ok').first();
    return c.json({
      status: 'ok',
      environment: c.env.ENVIRONMENT || 'production',
      timestamp: now(),
      version: c.env.WORKER_VERSION || API_VERSION,
      commit: c.env.SOURCE_COMMIT || '',
      database: Number(db?.ok || 0) === 1 ? 'ok' : 'unknown',
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/me', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'admin:read');
    return c.json({
      user: adminUserPayload(admin.user, admin.role),
      role: admin.role,
      permissions: adminPermissionList(admin.role),
      environment: c.env.ENVIRONMENT || 'production',
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/dashboard', authMiddleware, async (c) => {
  try {
    await requireAdminRole(c, 'admin:read');
    await ensureAdminModerationSchema(c.env.DB);
    const [openReports, urgentReports, reportsToday, postsRemovedToday, usersSuspendedToday, newAccountsToday, uploadFailures] = await Promise.all([
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM reports WHERE COALESCE(status, 'open') IN ('open', 'pending', 'under_review', 'escalated')").first(),
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM reports WHERE COALESCE(priority, 'normal') IN ('urgent', 'high') AND COALESCE(status, 'open') IN ('open', 'pending', 'under_review', 'escalated')").first(),
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM reports WHERE datetime(created_at) >= datetime('now', 'start of day')").first(),
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM posts WHERE datetime(removed_at) >= datetime('now', 'start of day')").first(),
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM users WHERE COALESCE(status, 'active') = 'suspended' AND datetime(updated_at) >= datetime('now', 'start of day')").first(),
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM users WHERE datetime(created_at) >= datetime('now', 'start of day')").first(),
      c.env.DB.prepare("SELECT COUNT(*) AS count FROM client_events WHERE event_name LIKE '%upload%' AND status LIKE '%fail%' AND datetime(created_at) >= datetime('now', '-24 hours')").first().catch(() => ({ count: 0 })),
    ]);
    const quick = await c.env.DB.prepare(`
      SELECT r.*, reporter.username AS reporter_username, reporter.full_name AS reporter_full_name, reporter.profile_image AS reporter_profile_image,
             p.id AS post_id, p.user_id AS post_user_id, p.content AS post_content, p.title AS post_title,
             p.image AS post_image, p.images AS post_images, p.media_types AS post_media_types,
             p.media_dimensions AS post_media_dimensions, p.status AS post_status,
             target.username AS target_username, target.full_name AS target_full_name, target.profile_image AS target_profile_image, target.status AS target_status,
             target.id AS target_user_id
      FROM reports r
      LEFT JOIN users reporter ON reporter.id = r.reporter_id
      LEFT JOIN posts p ON p.id = r.reported_id OR p.id = r.content_id
      LEFT JOIN users target ON target.id = COALESCE(NULLIF(r.target_owner_user_id, ''), p.user_id, r.reported_id)
      WHERE COALESCE(r.status, 'open') IN ('open', 'pending', 'under_review', 'escalated')
      ORDER BY CASE COALESCE(r.priority, 'normal') WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END, r.created_at DESC
      LIMIT 8
    `).all();
    return c.json({
      cards: {
        open_reports: Number((openReports as any)?.count || 0),
        urgent_reports: Number((urgentReports as any)?.count || 0),
        reports_today: Number((reportsToday as any)?.count || 0),
        posts_removed_today: Number((postsRemovedToday as any)?.count || 0),
        users_suspended_today: Number((usersSuspendedToday as any)?.count || 0),
        new_accounts_today: Number((newAccountsToday as any)?.count || 0),
        upload_failures_24h: Number((uploadFailures as any)?.count || 0),
      },
      queues: {
        new_reports: (quick.results as any[]).map((row) => adminReportSummary(row, c.env)),
      },
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/reports', authMiddleware, async (c) => {
  try {
    await requireAdminRole(c, 'reports:read');
    await ensureAdminModerationSchema(c.env.DB);
    const { limit, offset } = adminPageParams(c);
    const conditions: string[] = [];
    const binds: any[] = [];
    const statusQuery = cleanText(c.req.query('status') || 'open', 40).toLowerCase();
    if (statusQuery && statusQuery !== 'all') {
      if (statusQuery === 'open') {
        conditions.push("COALESCE(r.status, 'open') IN ('open', 'pending', 'under_review', 'escalated')");
      } else {
        conditions.push("COALESCE(r.status, 'pending') = ?");
        binds.push(normalizeReportStatus(statusQuery, 'pending'));
      }
    }
    const reason = cleanText(c.req.query('reason') || '', 80);
    if (reason && reason !== 'all') {
      conditions.push('r.reason = ?');
      binds.push(normalizeReportReason(reason));
    }
    const targetType = cleanText(c.req.query('target_type') || c.req.query('type') || '', 60);
    if (targetType && targetType !== 'all') {
      conditions.push("COALESCE(NULLIF(r.reported_type, ''), r.report_type, 'other') = ?");
      binds.push(normalizeReportTargetType(targetType));
    }
    const fromDate = cleanText(c.req.query('from') || '', 40);
    if (/^\d{4}-\d{2}-\d{2}/.test(fromDate)) {
      conditions.push('datetime(r.created_at) >= datetime(?)');
      binds.push(fromDate);
    }
    const search = searchPattern(c.req.query('search'));
    if (search) {
      conditions.push(`(
        LOWER(r.id) LIKE ? OR LOWER(r.reported_id) LIKE ? OR LOWER(r.reporter_id) LIKE ?
        OR LOWER(reporter.username) LIKE ? OR LOWER(target.username) LIKE ?
      )`);
      binds.push(search, search, search, search, search);
    }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const rows = await c.env.DB.prepare(`
      SELECT r.*, reporter.username AS reporter_username, reporter.full_name AS reporter_full_name, reporter.profile_image AS reporter_profile_image,
             p.id AS post_id, p.user_id AS post_user_id, p.content AS post_content, p.title AS post_title,
             p.image AS post_image, p.images AS post_images, p.media_types AS post_media_types,
             p.media_dimensions AS post_media_dimensions, p.status AS post_status,
             target.id AS target_user_id, target.username AS target_username, target.full_name AS target_full_name,
             target.profile_image AS target_profile_image, target.status AS target_status
      FROM reports r
      LEFT JOIN users reporter ON reporter.id = r.reporter_id
      LEFT JOIN posts p ON p.id = r.reported_id OR p.id = r.content_id
      LEFT JOIN users target ON target.id = COALESCE(NULLIF(r.target_owner_user_id, ''), p.user_id, r.reported_id)
      ${where}
      ORDER BY CASE COALESCE(r.priority, 'normal') WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END, r.created_at DESC
      LIMIT ? OFFSET ?
    `).bind(...binds, limit, offset).all();
    return c.json({
      results: (rows.results as any[]).map((row) => adminReportSummary(row, c.env)),
      pagination: { limit, offset, next_offset: offset + limit },
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/reports/:reportId', authMiddleware, async (c) => {
  try {
    await requireAdminRole(c, 'reports:read');
    await ensureAdminModerationSchema(c.env.DB);
    const reportId = publicId(c.req.param('reportId'), 120);
    const report = await getAdminReportRow(c, reportId);
    if (!report) return c.json({ detail: 'Report not found.' }, 404);
    return c.json({ report: await adminReportDetail(c, report) });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/reports/:reportId/status', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'reports:write');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_report_write');
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['status', 'reason', 'note', 'admin_notes']);
    if (unknown) return unknown;
    return setReportStatus(c, admin, publicId(c.req.param('reportId'), 120), body.status || 'under_review', cleanMultilineText(body.reason, 500), cleanMultilineText(body.note || body.admin_notes, 1000));
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/reports/:reportId/note', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'reports:write');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_report_note');
    if (limited) return limited;
    const reportId = publicId(c.req.param('reportId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['note']);
    if (unknown) return unknown;
    const note = cleanMultilineText(body.note, 1000);
    if (!note) return c.json({ detail: 'Internal note is required.' }, 400);
    const report: any = await c.env.DB.prepare('SELECT id, reported_id, reported_type, report_type FROM reports WHERE id = ?').bind(reportId).first();
    if (!report) return c.json({ detail: 'Report not found.' }, 404);
    await c.env.DB.prepare(
      'INSERT INTO moderation_notes (id, report_id, target_type, target_id, author_admin_user_id, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).bind(uuid(), reportId, reportTargetType(report), report.reported_id, admin.userId, note, now()).run();
    await writeAdminAuditLog(c, admin, { actionType: 'internal_note_added', targetType: 'report', targetId: reportId, targetUserId: report.reported_id, note });
    return c.json({ added: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/reports/:reportId/action', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'reports:write');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_report_action');
    if (limited) return limited;
    const reportId = publicId(c.req.param('reportId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['action', 'status', 'reason', 'note', 'admin_notes']);
    if (unknown) return unknown;
    const action = cleanText(body.action || body.status || 'under_review', 80).toLowerCase().replace(/[\s-]+/g, '_');
    const report = await getAdminReportRow(c, reportId);
    if (!report) return c.json({ detail: 'Report not found.' }, 404);
    const reason = cleanMultilineText(body.reason || 'Moderation action from report', 500);
    const note = cleanMultilineText(body.note || body.admin_notes || '', 1000);
    if (action === 'remove_content') {
      const type = reportTargetType(report);
      if (type === 'post' && (report.post_id || report.reported_id)) {
        await c.env.DB.prepare("UPDATE posts SET status = 'removed', removed_at = ?, removed_reason = ? WHERE id = ?")
          .bind(now(), reason, report.post_id || report.reported_id).run();
        await writeAdminAuditLog(c, admin, { actionType: 'content_removed_from_report', targetType: 'post', targetId: report.post_id || report.reported_id, targetUserId: report.post_user_id, reason, note });
      } else if (type === 'comment' && (report.comment_id || report.reported_id)) {
        await c.env.DB.prepare("UPDATE comments SET status = 'removed', removed_at = ?, removed_reason = ?, pinned_at = NULL WHERE id = ?")
          .bind(now(), reason, report.comment_id || report.reported_id).run();
        await writeAdminAuditLog(c, admin, { actionType: 'content_removed_from_report', targetType: 'comment', targetId: report.comment_id || report.reported_id, targetUserId: report.comment_user_id, reason, note });
      } else if (type === 'message' && (report.message_id || report.reported_id)) {
        await c.env.DB.prepare("UPDATE messages SET status = 'removed', removed_at = ?, removed_by = ?, removed_reason = ? WHERE id = ?")
          .bind(now(), admin.userId, reason, report.message_id || report.reported_id).run();
        await writeAdminAuditLog(c, admin, { actionType: 'message_removed_from_report', targetType: 'message', targetId: report.message_id || report.reported_id, targetUserId: report.message_sender_id, reason, note });
      }
      return setReportStatus(c, admin, reportId, 'action_taken', reason, note);
    }
    if (action === 'dismiss' || action === 'dismissed') return setReportStatus(c, admin, reportId, 'dismissed', reason, note);
    if (action === 'escalate' || action === 'escalated') return setReportStatus(c, admin, reportId, 'escalated', reason, note);
    if (action === 'close' || action === 'closed') return setReportStatus(c, admin, reportId, 'closed', reason, note);
    return setReportStatus(c, admin, reportId, body.status || 'under_review', reason, note);
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/users', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'users:read');
    await ensureAdminModerationSchema(c.env.DB);
    const { limit, offset } = adminPageParams(c);
    const search = searchPattern(c.req.query('search'));
    const status = cleanText(c.req.query('status') || '', 40);
    const conditions: string[] = [];
    const binds: any[] = [];
    if (search) {
      conditions.push('(LOWER(u.username) LIKE ? OR LOWER(u.full_name) LIKE ? OR LOWER(u.id) LIKE ? OR LOWER(u.email) LIKE ?)');
      binds.push(search, search, search, search);
    }
    if (status && status !== 'all') {
      conditions.push("COALESCE(u.status, 'active') = ?");
      binds.push(status);
    }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const rows = await c.env.DB.prepare(`
      SELECT u.*,
             (SELECT COUNT(*) FROM reports r WHERE r.reported_id = u.id OR r.target_owner_user_id = u.id) AS report_count
      FROM users u
      ${where}
      ORDER BY u.created_at DESC
      LIMIT ? OFFSET ?
    `).bind(...binds, limit, offset).all();
    return c.json({ results: (rows.results as any[]).map((row) => adminUserPayload(row, admin.role)), pagination: { limit, offset, next_offset: offset + limit } });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/users/:userId', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'users:read');
    await ensureAdminModerationSchema(c.env.DB);
    const targetUserId = publicId(c.req.param('userId'), 120);
    const row: any = await c.env.DB.prepare(`
      SELECT u.*,
             (SELECT COUNT(*) FROM reports r WHERE r.reported_id = u.id OR r.target_owner_user_id = u.id) AS report_count
      FROM users u WHERE u.id = ? LIMIT 1
    `).bind(targetUserId).first();
    if (!row) return c.json({ detail: 'User not found.' }, 404);
    const [restrictions, actions, posts] = await Promise.all([
      c.env.DB.prepare('SELECT * FROM user_restrictions WHERE user_id = ? ORDER BY created_at DESC LIMIT 50').bind(targetUserId).all(),
      c.env.DB.prepare('SELECT * FROM moderation_actions WHERE target_user_id = ? OR target_id = ? ORDER BY created_at DESC LIMIT 50').bind(targetUserId, targetUserId).all(),
      c.env.DB.prepare(`
        SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
        FROM posts p LEFT JOIN users u ON u.id = p.user_id
        WHERE p.user_id = ?
        ORDER BY p.created_at DESC
        LIMIT 12
      `).bind(targetUserId).all(),
    ]);
    return c.json({
      user: adminUserPayload(row, admin.role),
      restrictions: restrictions.results || [],
      actions: actions.results || [],
      recent_posts: (posts.results as any[]).map((post) => adminPostPayload(post, c.env)),
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/users/:userId/warn', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'users:warn');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_user_warn');
    if (limited) return limited;
    const targetUserId = publicId(c.req.param('userId'), 120);
    if (targetUserId === admin.userId) return c.json({ detail: 'Admins cannot warn themselves.' }, 400);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['reason', 'note']);
    if (unknown) return unknown;
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const target: any = await c.env.DB.prepare('SELECT id, warning_count FROM users WHERE id = ?').bind(targetUserId).first();
    if (!target) return c.json({ detail: 'User not found.' }, 404);
    await c.env.DB.prepare('UPDATE users SET warning_count = COALESCE(warning_count, 0) + 1, updated_at = datetime(\'now\') WHERE id = ?').bind(targetUserId).run();
    await insertNotificationOnce(c, {
      userId: targetUserId,
      type: 'moderation_warning',
      title: 'Captro safety warning',
      body: reason,
      data: { moderation_action: 'warning' },
      dedupeKey: `warn:${targetUserId}:${Date.now()}`,
      dedupeSeconds: 60,
    });
    await writeAdminAuditLog(c, admin, { actionType: 'user_warned', targetType: 'user', targetId: targetUserId, targetUserId, reason, note: body.note, beforeState: { warning_count: target.warning_count || 0 }, afterState: { warned: true } });
    return c.json({ warned: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/users/:userId/restrict', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'users:restrict');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_user_restrict');
    if (limited) return limited;
    const targetUserId = publicId(c.req.param('userId'), 120);
    if (targetUserId === admin.userId) return c.json({ detail: 'Admins cannot restrict themselves.' }, 400);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['restriction_type', 'type', 'reason', 'note', 'duration_hours', 'ends_at']);
    if (unknown) return unknown;
    const target = await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(targetUserId).first();
    if (!target) return c.json({ detail: 'User not found.' }, 404);
    const restrictionType = normalizeRestrictionType(body.restriction_type || body.type);
    const hours = clampNumber(body.duration_hours || 24, 1, 24 * 90, 24);
    const endsAt = cleanText(body.ends_at || '', 60) || new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    await c.env.DB.prepare(
      'INSERT INTO user_restrictions (id, user_id, restriction_type, reason, starts_at, ends_at, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    ).bind(uuid(), targetUserId, restrictionType, reason, now(), endsAt, admin.userId, now()).run();
    await writeAdminAuditLog(c, admin, { actionType: 'user_restricted', targetType: 'user', targetId: targetUserId, targetUserId, reason, note: body.note, afterState: { restriction_type: restrictionType, ends_at: endsAt } });
    return c.json({ restricted: true, restriction_type: restrictionType, ends_at: endsAt });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/users/:userId/suspend', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'users:suspend');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_user_suspend');
    if (limited) return limited;
    const targetUserId = publicId(c.req.param('userId'), 120);
    if (targetUserId === admin.userId) return c.json({ detail: 'Admins cannot suspend themselves.' }, 400);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['reason', 'note', 'duration_hours', 'ends_at']);
    if (unknown) return unknown;
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const hours = clampNumber(body.duration_hours || 24, 1, 24 * 90, 24);
    const suspendedUntil = cleanText(body.ends_at || '', 60) || new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
    const before: any = await c.env.DB.prepare('SELECT id, status FROM users WHERE id = ?').bind(targetUserId).first();
    if (!before) return c.json({ detail: 'User not found.' }, 404);
    await c.env.DB.prepare("UPDATE users SET status = 'suspended', suspended_until = ?, ban_reason = ?, updated_at = datetime('now') WHERE id = ?")
      .bind(suspendedUntil, reason, targetUserId).run();
    await writeAdminAuditLog(c, admin, { actionType: 'user_suspended', targetType: 'user', targetId: targetUserId, targetUserId, reason, note: body.note, beforeState: before, afterState: { status: 'suspended', suspended_until: suspendedUntil } });
    return c.json({ suspended: true, suspended_until: suspendedUntil });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/users/:userId/ban', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'users:ban');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_user_ban');
    if (limited) return limited;
    const targetUserId = publicId(c.req.param('userId'), 120);
    if (targetUserId === admin.userId) return c.json({ detail: 'Admins cannot ban themselves.' }, 400);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['reason', 'note']);
    if (unknown) return unknown;
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare('SELECT id, status, username, full_name FROM users WHERE id = ?').bind(targetUserId).first();
    if (!before) return c.json({ detail: 'User not found.' }, 404);
    await c.env.DB.prepare("UPDATE users SET status = 'banned', banned_at = ?, ban_reason = ?, updated_at = datetime('now') WHERE id = ?")
      .bind(now(), reason, targetUserId).run();
    await writeAdminAuditLog(c, admin, { actionType: 'user_banned', targetType: 'user', targetId: targetUserId, targetUserId, reason, note: body.note, beforeState: before, afterState: { status: 'banned' } });
    return c.json({ banned: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/users/:userId/unban', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'users:ban');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_user_unban');
    if (limited) return limited;
    const targetUserId = publicId(c.req.param('userId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['reason', 'note']);
    if (unknown) return unknown;
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare('SELECT id, status FROM users WHERE id = ?').bind(targetUserId).first();
    if (!before) return c.json({ detail: 'User not found.' }, 404);
    await c.env.DB.prepare("UPDATE users SET status = 'active', banned_at = NULL, suspended_until = NULL, ban_reason = '', updated_at = datetime('now') WHERE id = ?")
      .bind(targetUserId).run();
    await writeAdminAuditLog(c, admin, { actionType: 'user_unbanned', targetType: 'user', targetId: targetUserId, targetUserId, reason, note: body.note, beforeState: before, afterState: { status: 'active' } });
    return c.json({ unbanned: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/users/:userId/force-username-change', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'users:restrict');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_username_force_change');
    if (limited) return limited;
    const targetUserId = publicId(c.req.param('userId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare('SELECT id, username FROM users WHERE id = ?').bind(targetUserId).first();
    if (!before) return c.json({ detail: 'User not found.' }, 404);
    const pending = pendingUsernameForUser(targetUserId);
    await c.env.DB.prepare("UPDATE users SET username = ?, updated_at = datetime('now') WHERE id = ?").bind(pending, targetUserId).run();
    await writeAdminAuditLog(c, admin, { actionType: 'username_force_changed', targetType: 'user', targetId: targetUserId, targetUserId, reason, note: body.note, beforeState: { username: before.username }, afterState: { username_required: true } });
    return c.json({ username_required: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/posts', authMiddleware, async (c) => {
  try {
    await requireAdminRole(c, 'content:read');
    await ensureAdminModerationSchema(c.env.DB);
    await ensureAutoCategorySchema(c.env.DB);
    await ensureLocationSchema(c.env.DB);
    const { limit, offset } = adminPageParams(c);
    const status = cleanText(c.req.query('status') || 'all', 40);
    const category = cleanText(c.req.query('category') || '', 60).toLowerCase();
    const surface = cleanText(c.req.query('surface') || '', 40).toLowerCase();
    const search = searchPattern(c.req.query('search'));
    const conditions: string[] = [];
    const binds: any[] = [];
    if (status !== 'all') {
      conditions.push("COALESCE(p.status, 'active') = ?");
      binds.push(status);
    }
    if (category && category !== 'all') {
      const normalizedCategory = normalizeDiscoverCategory(category, false);
      if (!normalizedCategory) return c.json({ detail: 'Unknown category.' }, 400);
      conditions.push("LOWER(COALESCE(NULLIF(p.primary_category, ''), NULLIF(p.category, ''), 'lifestyle')) = ?");
      binds.push(normalizedCategory);
    }
    if (surface === 'discover') {
      conditions.push("COALESCE(p.discover_blocked_at, '') = ''");
    }
    if (search) {
      conditions.push('(LOWER(p.id) LIKE ? OR LOWER(p.content) LIKE ? OR LOWER(u.username) LIKE ?)');
      binds.push(search, search, search);
    }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const rows = await c.env.DB.prepare(`
      SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM posts p
      LEFT JOIN users u ON u.id = p.user_id
      ${where}
      ORDER BY p.created_at DESC
      LIMIT ? OFFSET ?
    `).bind(...binds, limit, offset).all();
    return c.json({ results: (rows.results as any[]).map((row) => adminPostPayload(row, c.env)), pagination: { limit, offset, next_offset: offset + limit } });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/posts/:postId', authMiddleware, async (c) => {
  try {
    await requireAdminRole(c, 'content:read');
    await ensureAdminModerationSchema(c.env.DB);
    await ensureAutoCategorySchema(c.env.DB);
    await ensureLocationSchema(c.env.DB);
    const postId = publicId(c.req.param('postId'), 120);
    const row: any = await c.env.DB.prepare(`
      SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM posts p LEFT JOIN users u ON u.id = p.user_id
      WHERE p.id = ?
      LIMIT 1
    `).bind(postId).first();
    if (!row) return c.json({ detail: 'Post not found.' }, 404);
    const actions = await c.env.DB.prepare(`
      SELECT a.*, u.username AS actor_username, u.full_name AS actor_full_name
      FROM moderation_actions a
      LEFT JOIN users u ON u.id = a.actor_admin_user_id
      WHERE a.target_type = 'post' AND a.target_id = ?
      ORDER BY a.created_at DESC
      LIMIT 30
    `).bind(postId).all();
    return c.json({ post: adminPostPayload(row, c.env), actions: actions.results || [] });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/posts/:postId/remove', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'content:write');
    await ensureAdminModerationSchema(c.env.DB);
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_post_remove');
    if (limited) return limited;
    const postId = publicId(c.req.param('postId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare('SELECT id, user_id, status FROM posts WHERE id = ?').bind(postId).first();
    if (!before) return c.json({ detail: 'Post not found.' }, 404);
    await c.env.DB.prepare("UPDATE posts SET status = 'removed', removed_at = ?, removed_reason = ? WHERE id = ?").bind(now(), reason, postId).run();
    await writeAdminAuditLog(c, admin, { actionType: 'post_removed', targetType: 'post', targetId: postId, targetUserId: before.user_id, reason, note: body.note, beforeState: before, afterState: { status: 'removed' } });
    return c.json({ removed: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/posts/:postId/restore', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'content:write');
    await ensureAdminModerationSchema(c.env.DB);
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_post_restore');
    if (limited) return limited;
    const postId = publicId(c.req.param('postId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare('SELECT id, user_id, status FROM posts WHERE id = ?').bind(postId).first();
    if (!before) return c.json({ detail: 'Post not found.' }, 404);
    await c.env.DB.prepare("UPDATE posts SET status = 'active', removed_at = NULL, removed_reason = '' WHERE id = ?").bind(postId).run();
    await writeAdminAuditLog(c, admin, { actionType: 'post_restored', targetType: 'post', targetId: postId, targetUserId: before.user_id, reason, note: body.note, beforeState: before, afterState: { status: 'active' } });
    return c.json({ restored: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/posts/:postId/mark-safe', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'content:write');
    await ensureAdminModerationSchema(c.env.DB);
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_post_mark_safe');
    if (limited) return limited;
    const postId = publicId(c.req.param('postId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['reason', 'note']);
    if (unknown) return unknown;
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare('SELECT id, user_id, status, discover_blocked_at FROM posts WHERE id = ?').bind(postId).first();
    if (!before) return c.json({ detail: 'Post not found.' }, 404);
    await c.env.DB.prepare("UPDATE posts SET status = 'active', removed_at = NULL, removed_reason = '', discover_blocked_at = NULL, discover_blocked_by = '', discover_blocked_reason = '', updated_at = datetime('now') WHERE id = ?")
      .bind(postId).run();
    await writeAdminAuditLog(c, admin, { actionType: 'post_marked_safe', targetType: 'post', targetId: postId, targetUserId: before.user_id, reason, note: body.note, beforeState: before, afterState: { status: 'active', discover_blocked: false } });
    return c.json({ marked_safe: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/posts/:postId/remove-from-discover', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'content:write');
    await ensureAdminModerationSchema(c.env.DB);
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_post_discover_remove');
    if (limited) return limited;
    const postId = publicId(c.req.param('postId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare('SELECT id, user_id, discover_blocked_at FROM posts WHERE id = ?').bind(postId).first();
    if (!before) return c.json({ detail: 'Post not found.' }, 404);
    await c.env.DB.prepare('UPDATE posts SET discover_blocked_at = ?, discover_blocked_by = ?, discover_blocked_reason = ? WHERE id = ?')
      .bind(now(), admin.userId, reason, postId).run();
    await writeAdminAuditLog(c, admin, { actionType: 'post_removed_from_discover', targetType: 'post', targetId: postId, targetUserId: before.user_id, reason, note: body.note, beforeState: before, afterState: { discover_blocked: true } });
    return c.json({ removed_from_discover: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/posts/:postId/location/clear', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'content:write');
    await ensureAdminModerationSchema(c.env.DB);
    await ensureLocationSchema(c.env.DB);
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_post_location_clear');
    if (limited) return limited;
    const postId = publicId(c.req.param('postId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['reason', 'note']);
    if (unknown) return unknown;
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare(
      `SELECT id, user_id, display_location_label, display_location_visibility, place_name, place_formatted_address, place_lat, place_lng
       FROM posts WHERE id = ? LIMIT 1`
    ).bind(postId).first();
    if (!before) return c.json({ detail: 'Post not found.' }, 404);
    await c.env.DB.batch([
      c.env.DB.prepare(
        `UPDATE posts
         SET display_city = '', display_region = '', display_country = '', display_location_label = '',
             display_location_source = 'none', display_location_visibility = 'hidden',
             location = NULL, place_id = NULL, place_name = NULL, place_lat = NULL, place_lng = NULL,
             place_provider = '', place_provider_id = '', place_formatted_address = '', place_category = '',
             place_city = '', place_region = '', place_country = '', updated_at = datetime('now')
         WHERE id = ?`
      ).bind(postId),
      c.env.DB.prepare('DELETE FROM post_places WHERE post_id = ?').bind(postId),
    ]);
    await writeAdminAuditLog(c, admin, {
      actionType: 'post_location_cleared',
      targetType: 'post',
      targetId: postId,
      targetUserId: before.user_id,
      reason,
      note: body.note,
      beforeState: before,
      afterState: { display_location_visibility: 'hidden', place_removed: true },
    });
    const row: any = await c.env.DB.prepare(`
      SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM posts p LEFT JOIN users u ON u.id = p.user_id
      WHERE p.id = ?
      LIMIT 1
    `).bind(postId).first();
    return c.json({ post: adminPostPayload(row, c.env) });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/posts/:postId/category', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'content:write');
    await ensureAdminModerationSchema(c.env.DB);
    await ensureAutoCategorySchema(c.env.DB);
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_post_category_change');
    if (limited) return limited;
    const postId = publicId(c.req.param('postId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['primary_category', 'category', 'reason', 'note']);
    if (unknown) return unknown;
    const category = normalizeDiscoverCategory(body.primary_category || body.category, false);
    if (!category) return c.json({ detail: 'Choose a valid Discover category.' }, 400);
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare(
      `SELECT id, user_id, primary_category, category_confidence, category_source, category_status, category_signals_json, tags_json
       FROM posts
       WHERE id = ?
       LIMIT 1`
    ).bind(postId).first();
    if (!before) return c.json({ detail: 'Post not found.' }, 404);
    const oldCategory = normalizeDiscoverCategory(before.primary_category || 'lifestyle', false) || 'lifestyle';
    const nextSignals = {
      ...parseJsonObject(before.category_signals_json),
      admin_changed_at: now(),
      admin_previous_category: oldCategory,
      admin_new_category: category,
      admin_reason: reason,
    };
    await c.env.DB.prepare(
      `UPDATE posts
       SET primary_category = ?, category_confidence = 1, category_source = 'admin_changed',
           category_status = 'admin_corrected', category_signals_json = ?, updated_at = datetime('now')
       WHERE id = ?`
    ).bind(category, JSON.stringify(nextSignals), postId).run();
    await writeAdminAuditLog(c, admin, {
      actionType: 'category_changed',
      targetType: 'post',
      targetId: postId,
      targetUserId: before.user_id,
      reason,
      note: body.note,
      beforeState: { old_category: oldCategory, category_source: before.category_source, category_status: before.category_status },
      afterState: { new_category: category, category_source: 'admin_changed', category_status: 'admin_corrected' },
    });
    const row: any = await c.env.DB.prepare(`
      SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM posts p LEFT JOIN users u ON u.id = p.user_id
      WHERE p.id = ?
      LIMIT 1
    `).bind(postId).first();
    return c.json({ post: adminPostPayload(row, c.env) });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/comments', authMiddleware, async (c) => {
  try {
    await requireAdminRole(c, 'content:read');
    await ensureAdminModerationSchema(c.env.DB);
    const { limit, offset } = adminPageParams(c);
    const status = cleanText(c.req.query('status') || 'all', 40);
    const search = searchPattern(c.req.query('search'));
    const conditions: string[] = [];
    const binds: any[] = [];
    if (status !== 'all') {
      conditions.push("COALESCE(c.status, 'active') = ?");
      binds.push(status);
    }
    if (search) {
      conditions.push('(LOWER(c.id) LIKE ? OR LOWER(c.content) LIKE ? OR LOWER(u.username) LIKE ?)');
      binds.push(search, search, search);
    }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const rows = await c.env.DB.prepare(`
      SELECT c.*, p.user_id AS post_user_id, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM comments c
      LEFT JOIN posts p ON p.id = c.post_id
      LEFT JOIN users u ON u.id = c.user_id
      ${where}
      ORDER BY c.created_at DESC
      LIMIT ? OFFSET ?
    `).bind(...binds, limit, offset).all();
    return c.json({ results: (rows.results as any[]).map(adminCommentPayload), pagination: { limit, offset, next_offset: offset + limit } });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/comments/:commentId/remove', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'content:write');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_comment_remove');
    if (limited) return limited;
    const commentId = publicId(c.req.param('commentId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare('SELECT id, user_id, post_id, status FROM comments WHERE id = ?').bind(commentId).first();
    if (!before) return c.json({ detail: 'Comment not found.' }, 404);
    await c.env.DB.prepare("UPDATE comments SET status = 'removed', removed_at = ?, removed_reason = ?, pinned_at = NULL WHERE id = ?")
      .bind(now(), reason, commentId).run();
    await writeAdminAuditLog(c, admin, { actionType: 'comment_removed', targetType: 'comment', targetId: commentId, targetUserId: before.user_id, reason, note: body.note, beforeState: before, afterState: { status: 'removed' } });
    return c.json({ removed: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/comments/:commentId/restore', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'content:write');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_comment_restore');
    if (limited) return limited;
    const commentId = publicId(c.req.param('commentId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const before: any = await c.env.DB.prepare('SELECT id, user_id, post_id, status FROM comments WHERE id = ?').bind(commentId).first();
    if (!before) return c.json({ detail: 'Comment not found.' }, 404);
    await c.env.DB.prepare("UPDATE comments SET status = 'active', removed_at = NULL, removed_reason = '', hidden_at = NULL, hidden_by_user_id = '', pinned_at = NULL WHERE id = ?")
      .bind(commentId).run();
    await writeAdminAuditLog(c, admin, { actionType: 'comment_restored', targetType: 'comment', targetId: commentId, targetUserId: before.user_id, reason, note: body.note, beforeState: before, afterState: { status: 'active' } });
    return c.json({ restored: true });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/messages/reported', authMiddleware, async (c) => {
  try {
    await requireAdminRole(c, 'messages:reported:read');
    await ensureAdminModerationSchema(c.env.DB);
    const { limit, offset } = adminPageParams(c);
    const rows = await c.env.DB.prepare(`
      SELECT r.*, m.sender_id AS message_sender_id, m.receiver_id AS message_receiver_id, m.content AS message_content,
             m.media_type AS message_media_type, m.status AS message_status,
             reporter.username AS reporter_username, reporter.full_name AS reporter_full_name, reporter.profile_image AS reporter_profile_image,
             sender.username AS target_username, sender.full_name AS target_full_name, sender.profile_image AS target_profile_image, sender.status AS target_status,
             sender.id AS target_user_id
      FROM reports r
      JOIN messages m ON m.id = r.reported_id
      LEFT JOIN users reporter ON reporter.id = r.reporter_id
      LEFT JOIN users sender ON sender.id = m.sender_id
      WHERE COALESCE(NULLIF(r.reported_type, ''), r.report_type, 'other') = 'message'
      ORDER BY r.created_at DESC
      LIMIT ? OFFSET ?
    `).bind(limit, offset).all();
    return c.json({ results: (rows.results as any[]).map((row) => adminReportSummary(row, c.env)), pagination: { limit, offset, next_offset: offset + limit } });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/messages/reported/:reportId', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'messages:reported:read');
    await ensureAdminModerationSchema(c.env.DB);
    const reportId = publicId(c.req.param('reportId'), 120);
    const report = await getAdminReportRow(c, reportId);
    if (!report || reportTargetType(report) !== 'message') return c.json({ detail: 'Reported message not found.' }, 404);
    const messageId = report.message_id || report.reported_id;
    const message: any = await c.env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(messageId).first();
    if (!message) return c.json({ detail: 'Message not found.' }, 404);
    const context = await c.env.DB.prepare(`
      SELECT id, sender_id, receiver_id, content, media_type, status, created_at
      FROM messages
      WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
        AND datetime(created_at) BETWEEN datetime(?, '-10 minutes') AND datetime(?, '+10 minutes')
      ORDER BY created_at ASC
      LIMIT 12
    `).bind(message.sender_id, message.receiver_id, message.receiver_id, message.sender_id, message.created_at, message.created_at).all();
    await writeAdminAuditLog(c, admin, { actionType: 'reported_message_viewed', targetType: 'message', targetId: messageId, targetUserId: message.sender_id, reason: 'Safety review', note: `Report ${reportId}` });
    return c.json({
      report: await adminReportDetail(c, report),
      privacy_warning: 'Reported message access is audit logged and limited to nearby context needed for safety review.',
      context: (context.results as any[]).map((row) => ({
        id: row.id,
        sender_id: row.sender_id,
        receiver_id: row.receiver_id,
        content: cleanMultilineText(row.content, 2000),
        media_type: cleanText(row.media_type, 40),
        status: cleanText(row.status || 'active', 40),
        created_at: row.created_at,
        is_reported: row.id === messageId,
      })),
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/messages/reported/:reportId/action', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'messages:reported:write');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_message_report_action');
    if (limited) return limited;
    const reportId = publicId(c.req.param('reportId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const action = cleanText(body.action || 'remove_message', 80).toLowerCase().replace(/[\s-]+/g, '_');
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const report = await getAdminReportRow(c, reportId);
    if (!report || reportTargetType(report) !== 'message') return c.json({ detail: 'Reported message not found.' }, 404);
    const messageId = report.message_id || report.reported_id;
    if (action === 'remove_message' || action === 'remove') {
      await c.env.DB.prepare("UPDATE messages SET status = 'removed', removed_at = ?, removed_by = ?, removed_reason = ? WHERE id = ?")
        .bind(now(), admin.userId, reason, messageId).run();
      await writeAdminAuditLog(c, admin, { actionType: 'reported_message_removed', targetType: 'message', targetId: messageId, targetUserId: report.message_sender_id, reason, note: body.note });
      return setReportStatus(c, admin, reportId, 'action_taken', reason, body.note || '');
    }
    return setReportStatus(c, admin, reportId, action === 'dismiss' ? 'dismissed' : 'under_review', reason, body.note || '');
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/audit-logs', authMiddleware, async (c) => {
  try {
    await requireAdminRole(c, 'audit:read');
    await ensureAdminModerationSchema(c.env.DB);
    const { limit, offset } = adminPageParams(c, 80, 150);
    const action = cleanText(c.req.query('action') || '', 80);
    const targetType = cleanText(c.req.query('target_type') || '', 60);
    const adminId = publicId(c.req.query('admin_id') || '', 120);
    const conditions: string[] = [];
    const binds: any[] = [];
    if (action) { conditions.push('a.action_type = ?'); binds.push(action); }
    if (targetType) { conditions.push('a.target_type = ?'); binds.push(targetType); }
    if (adminId) { conditions.push('a.actor_admin_user_id = ?'); binds.push(adminId); }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const rows = await c.env.DB.prepare(`
      SELECT a.*, u.username AS admin_username, u.full_name AS admin_full_name
      FROM audit_logs a
      LEFT JOIN users u ON u.id = a.actor_admin_user_id
      ${where}
      ORDER BY a.created_at DESC
      LIMIT ? OFFSET ?
    `).bind(...binds, limit, offset).all();
    return c.json({
      results: (rows.results as any[]).map((row) => ({
        id: row.id,
        actor_admin_user_id: row.actor_admin_user_id,
        actor_role: row.actor_role,
        actor_username: publicUsernameFor({ username: row.admin_username }),
        actor_full_name: cleanText(row.admin_full_name, 120),
        action_type: row.action_type,
        target_type: row.target_type,
        target_id: row.target_id,
        target_user_id: row.target_user_id || '',
        reason: cleanMultilineText(row.reason, 500),
        internal_note: cleanMultilineText(row.internal_note, 800),
        before_state: parseJsonObject(row.before_state),
        after_state: parseJsonObject(row.after_state),
        request_id: row.request_id || '',
        created_at: row.created_at,
      })),
      pagination: { limit, offset, next_offset: offset + limit },
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

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
  await ensureGovernanceSchema(c.env.DB);
  await c.env.DB.prepare("UPDATE posts SET status = 'removed', removed_at = ?, removed_reason = 'Removed by admin' WHERE id = ?")
    .bind(now(), postId).run();
  await logGovernanceAction(c, getUserId(c), 'remove_post', 'post', postId, { legacy_route: true });
  return c.json({ removed: true, soft_deleted: true });
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

// Admin: List all users
api.get('/admin/users', authMiddleware, adminGuard, async (c) => {
  await ensureAbuseProtectionSchema(c.env.DB);
  const search = c.req.query('search') || '';
  const role = c.req.query('role') || '';
  let sql = "SELECT id, email, username, full_name, profile_image, bio, city, is_admin, is_creator, is_publisher, is_verified, followers_count, posts_count, created_at, COALESCE(status, 'active') AS status, (SELECT COUNT(*) FROM ban_evasion_flags bef WHERE bef.user_id = users.id AND COALESCE(bef.status, 'pending') = 'pending') AS possible_ban_evasion FROM users";
  const conditions: string[] = [];
  const binds: any[] = [];
  if (search) { conditions.push('(username LIKE ? OR full_name LIKE ? OR email LIKE ?)'); binds.push(`%${search}%`, `%${search}%`, `%${search}%`); }
  if (role === 'admin') { conditions.push('is_admin = 1'); }
  else if (role === 'creator') { conditions.push('is_creator = 1'); }
  else if (role === 'publisher') { conditions.push('is_publisher = 1'); }
  if (conditions.length) sql += ' WHERE ' + conditions.join(' AND ');
  sql += ' ORDER BY created_at DESC LIMIT 100';
  const r = await c.env.DB.prepare(sql).bind(...binds).all();
  return c.json(r.results);
});

// Admin: Update user roles
api.put('/admin/users/:userId', authMiddleware, adminGuard, async (c) => {
  const userId = c.req.param('userId');
  const body = await c.req.json();
  const fields: string[] = []; const vals: any[] = [];
  if (body.is_admin !== undefined) { fields.push('is_admin = ?'); vals.push(body.is_admin ? 1 : 0); }
  if (body.is_creator !== undefined) { fields.push('is_creator = ?'); vals.push(body.is_creator ? 1 : 0); }
  if (body.is_publisher !== undefined) { fields.push('is_publisher = ?'); vals.push(body.is_publisher ? 1 : 0); }
  if (body.is_verified !== undefined) { fields.push('is_verified = ?'); vals.push(body.is_verified ? 1 : 0); }
  if (fields.length === 0) return c.json({ detail: 'No fields to update' }, 400);
  vals.push(userId);
  const updateAdminUserSql = `UPDATE users SET ${fields.join(', ')}, updated_at = datetime('now') WHERE id = ?`;
  await c.env.DB.prepare(updateAdminUserSql).bind(...vals).run();
  return c.json({ success: true, message: 'User roles updated' });
});

// Admin: List all posts (for moderation)
api.get('/admin/posts', authMiddleware, adminGuard, async (c) => {
  const search = c.req.query('search') || '';
  let sql = `SELECT p.id, p.user_id, p.content, p.image, p.images, p.post_type, p.likes_count, p.comments_count, p.created_at,
             u.username AS user_username, u.full_name AS user_full_name, u.email AS user_email, u.profile_image AS user_profile_image
             FROM posts p JOIN users u ON p.user_id = u.id`;
  const binds: any[] = [];
  if (search) { sql += ' WHERE p.content LIKE ?'; binds.push(`%${search}%`); }
  sql += ' ORDER BY p.created_at DESC LIMIT 100';
  const r = await c.env.DB.prepare(sql).bind(...binds).all();
  return c.json(r.results);
});

// Admin: Ban/Unban user
api.post('/admin/users/:userId/ban', authMiddleware, adminGuard, async (c) => {
  const userId = c.req.param('userId');
  await ensureGovernanceSchema(c.env.DB);
  const { banned, reason } = await c.req.json().catch(() => ({}));
  await c.env.DB.prepare("UPDATE users SET status = ?, banned_at = CASE WHEN ? = 1 THEN ? ELSE NULL END, ban_reason = ?, updated_at = datetime('now') WHERE id = ?")
    .bind(banned ? 'banned' : 'active', banned ? 1 : 0, now(), banned ? cleanMultilineText(reason || 'Banned by admin', 500) : '', userId)
    .run();
  await logGovernanceAction(c, getUserId(c), banned ? 'ban_user' : 'unban_user', 'user', userId, { legacy_route: true, reason });
  return c.json({ success: true, banned: !!banned });
});

api.get('/admin/reports', authMiddleware, adminGuard, async (c) => {
  const r = await c.env.DB.prepare('SELECT * FROM reports ORDER BY created_at DESC LIMIT 50').all();
  return c.json(r.results);
});

api.post('/admin/reports/:reportId/action', authMiddleware, adminGuard, async (c) => {
  await ensureGovernanceSchema(c.env.DB);
  const body: any = await c.req.json().catch(() => ({}));
  const action = cleanText(body.action || body.action_taken || 'action_taken', 120);
  const status = normalizeReportStatus(body.status || (action === 'dismissed' ? 'dismissed' : 'action_taken'), 'action_taken');
  const reportId = c.req.param('reportId');
  const ts = now();
  await c.env.DB.prepare(
    'UPDATE reports SET status = ?, action_taken = ?, admin_notes = ?, reviewed_by = ?, reviewed_at = ?, updated_at = ? WHERE id = ?'
  ).bind(status, action, cleanMultilineText(body.admin_notes || body.notes || '', 1000), getUserId(c), ts, ts, reportId).run();
  await logGovernanceAction(c, getUserId(c), `report_${status}`, 'report', reportId, { action });
  return c.json({ action, status, done: true });
});

api.get('/admin/media-backups', authMiddleware, adminGuard, async (c) => {
  await ensureMediaBackupSchema(c.env.DB);
  const limit = Math.min(parseInt(c.req.query('limit') || '100', 10) || 100, 500);
  const rows = await c.env.DB.prepare(
    `SELECT mb.*, u.username AS user_username, u.full_name AS user_full_name
     FROM media_backups mb
     LEFT JOIN users u ON u.id = mb.user_id
     ORDER BY mb.created_at DESC
     LIMIT ?`
  ).bind(limit).all();
  return c.json(rows.results || []);
});

api.get('/admin/media-backups/:backupId/download', authMiddleware, adminGuard, async (c) => {
  if (!c.env.MEDIA_BACKUP) return c.json({ detail: 'R2 backup bucket is not bound' }, 500);
  await ensureMediaBackupSchema(c.env.DB);
  const backup: any = await c.env.DB.prepare('SELECT * FROM media_backups WHERE id = ?').bind(c.req.param('backupId')).first();
  if (!backup) return c.json({ detail: 'Backup not found' }, 404);
  const object = await c.env.MEDIA_BACKUP.get(backup.r2_key);
  if (!object) return c.json({ detail: 'R2 object not found' }, 404);
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('etag', object.httpEtag);
  headers.set('content-disposition', `attachment; filename="${sanitizeMediaName(backup.original_filename || backup.id)}.${contentTypeExtension(backup.content_type || '')}"`);
  headers.set('cache-control', 'private, no-store');
  headers.set('x-content-type-options', 'nosniff');
  return new Response(object.body, { headers });
});

function parseByteRange(rangeHeader: string | undefined, size: number): { offset: number; length: number; end: number } | null | 'invalid' {
  if (!rangeHeader) return null;
  const match = /^bytes=(\d*)-(\d*)$/i.exec(rangeHeader.trim());
  if (!match || size <= 0) return 'invalid';

  const startText = match[1];
  const endText = match[2];
  if (!startText && !endText) return 'invalid';

  let start: number;
  let end: number;

  if (!startText) {
    const suffixLength = Number(endText);
    if (!Number.isFinite(suffixLength) || suffixLength <= 0) return 'invalid';
    start = Math.max(size - suffixLength, 0);
    end = size - 1;
  } else {
    start = Number(startText);
    end = endText ? Number(endText) : size - 1;
    if (!Number.isFinite(start) || !Number.isFinite(end)) return 'invalid';
  }

  if (start < 0 || start >= size || end < start) return 'invalid';
  end = Math.min(end, size - 1);
  return { offset: start, length: end - start + 1, end };
}

async function serveMediaBackup(c: any) {
  if (!c.env.MEDIA_BACKUP) return c.json({ detail: 'Media storage is not configured' }, 503);
  try {
    await ensureMediaBackupSchema(c.env.DB);
    const backup: any = await c.env.DB.prepare('SELECT * FROM media_backups WHERE id = ?')
      .bind(c.req.param('backupId'))
      .first();
    if (!backup) return c.json({ detail: 'Media not found' }, 404);
    const hasSignedAccess = await hasValidMediaAccessToken(c, backup.id);
    const viewerId = await getOptionalUserId(c);
    const limited = await enforceRateLimit(c, 'media_read', viewerId || clientIp(c), 600, 60);
    if (limited) return limited;

    if (hasSignedAccess) {
      // Signed URLs are issued only from authorized message APIs so AVPlayer can stream private chat media.
    } else if (backup.post_id) {
      const mediaVisiblePostSql = [
        'SELECT p.id FROM posts p JOIN users u ON p.user_id = u.id',
        `WHERE p.id = ? AND ${visiblePostWhere('u', 'p')} LIMIT 1`,
      ].join(' ');
      const visiblePost: any = await c.env.DB.prepare(mediaVisiblePostSql).bind(backup.post_id, ...visiblePostBindValues(viewerId)).first();
      if (!visiblePost) return c.json({ detail: 'Media not found' }, 404);
    } else if (!viewerId) {
      return c.json({ detail: 'Media not found' }, 404);
    } else if (backup.user_id !== viewerId) {
      const viewer: any = await c.env.DB.prepare('SELECT username, email, is_admin FROM users WHERE id = ?').bind(viewerId).first();
      if (!viewer?.is_admin && !isOwnerUsername(c, viewer?.username) && !isOwnerEmail(c, viewer?.email)) {
        await logSecurityEvent(c, 'unattached_media_access_denied', viewerId, { backup_id: backup.id });
        return c.json({ detail: 'Media not found' }, 404);
      }
    }

    const head = await c.env.MEDIA_BACKUP.head(backup.r2_key);
    if (!head) return c.json({ detail: 'Media file not found' }, 404);

    const range = parseByteRange(c.req.header('range'), head.size || 0);
    if (range === 'invalid') {
      return new Response(null, {
        status: 416,
        headers: {
          'accept-ranges': 'bytes',
          'content-range': `bytes */${head.size || 0}`,
        },
      });
    }

    const object = range
      ? await c.env.MEDIA_BACKUP.get(backup.r2_key, { range: { offset: range.offset, length: range.length } })
      : await c.env.MEDIA_BACKUP.get(backup.r2_key);
    if (!object) return c.json({ detail: 'Media file not found' }, 404);

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('etag', head.httpEtag || object.httpEtag);
    headers.set('accept-ranges', 'bytes');
    headers.set('cache-control', 'public, max-age=31536000, immutable');
    headers.set('cdn-cache-control', 'public, max-age=31536000, immutable');
    headers.set('cloudflare-cdn-cache-control', 'public, max-age=31536000, immutable');
    headers.set('x-content-type-options', 'nosniff');
    headers.set('content-length', String(range ? range.length : head.size || object.size || 0));
    if (range) headers.set('content-range', `bytes ${range.offset}-${range.end}/${head.size}`);

    const body = c.req.method === 'HEAD' ? null : object.body;
    return new Response(body, { status: range ? 206 : 200, headers });
  } catch (error: any) {
    console.error('Media fetch failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load media' }, 500);
  }
}

api.get('/media/:backupId', serveMediaBackup);
api.on('HEAD', '/media/:backupId', serveMediaBackup);

// Upload (Cloudflare Images)
api.post('/upload/image', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 18_000_000);
    if (bodyTooLarge) return bodyTooLarge;
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'upload_image', userId, 30, 60);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'upload_image_daily', userId, 160, 86400);
    if (dailyLimited) return dailyLimited;
    const body = await c.req.json();
    const base64Data = body.image || body.base64;
    if (!base64Data) return c.json({ detail: 'No image data provided' }, 400);

    const decoded = dataUriToBytes(base64Data, 'image/jpeg');
    const declaredType = normalizedContentType(decoded.contentType);
    if (!ALLOWED_IMAGE_TYPES.has(declaredType) || !extensionAllowed(body.filename, ALLOWED_IMAGE_EXTENSIONS)) {
      return c.json({ detail: 'Unsupported image type. Use JPG, PNG, or WebP.' }, 400);
    }
    const detectedType = detectImageContentType(decoded.bytes);
    if (!detectedType) {
      return c.json({ detail: 'Uploaded image data is not a supported image file.' }, 400);
    }
    if (declaredType !== 'image/jpg' && detectedType !== declaredType) {
      return c.json({ detail: 'Image file type does not match the uploaded data.' }, 400);
    }
    if (decoded.bytes.byteLength > 10_000_000) {
      return c.json({ detail: 'Image is too large.', max_bytes: 10_000_000 }, 413);
    }
    const processed = preserveOriginalImage(decoded.bytes, declaredType === 'image/jpg' ? 'image/jpeg' : declaredType);

    const blob = new Blob([bytesToArrayBuffer(processed.bytes)], { type: processed.contentType });
    const formData = new FormData();
    const fileExt = contentTypeExtension(processed.contentType, 'jpg');
    formData.append('file', blob, `${uuid()}.${fileExt}`);
    formData.append('metadata', JSON.stringify({ userId, backup: true, image_processing: processed.status }));

    if (c.env.CLOUDFLARE_ACCOUNT_ID && c.env.CLOUDFLARE_IMAGES_TOKEN) {
      const cfRes = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/images/v1`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${c.env.CLOUDFLARE_IMAGES_TOKEN}` },
        body: formData,
      });
      const cfData: any = await cfRes.json();
      if (cfData.success) {
        const imageId = cfData.result.id;
        const ACCOUNT_HASH = c.env.CLOUDFLARE_IMAGES_ACCOUNT_HASH || 'DY-IgVdOm-0zb0K5ZFnpKA';
        const deliveryUrl = `https://imagedelivery.net/${ACCOUNT_HASH}/${imageId}/public`;
        const backup = await storeMediaBackup(c, {
          userId,
          mediaKind: 'image',
          provider: 'cloudflare_images',
          providerId: imageId,
          deliveryUrl,
          contentType: processed.contentType,
          bytes: processed.bytes,
          originalFilename: body.filename || `upload.${fileExt}`,
        });
        return c.json({
          url: deliveryUrl,
          id: imageId,
          source: 'cloudflare_images',
          backup_id: backup?.id || null,
          size_bytes: backup?.size_bytes || processed.bytes.byteLength,
          checksum_sha256: backup?.checksum_sha256 || null,
          image_processing_status: processed.status,
        });
      }
      console.log('CF Images error:', JSON.stringify(cfData.errors));
    } else {
      console.log('CF Images is not configured; using R2 media storage.');
    }

    const backup = await storeMediaBackup(c, {
      userId,
      mediaKind: 'image',
      provider: 'r2_image',
      contentType: processed.contentType,
      bytes: processed.bytes,
      originalFilename: body.filename || `upload.${fileExt}`,
    });
    if (!backup) return c.json({ detail: 'Media storage is not configured.' }, 503);
    return c.json({
      url: backup.delivery_url,
      id: backup.id,
      source: 'r2_image',
      backup_id: backup.id,
      size_bytes: backup.size_bytes,
      checksum_sha256: backup.checksum_sha256,
      image_processing_status: processed.status,
    });
  } catch (e: any) {
    console.error('Image upload failed:', getErrorCode(e));
    return c.json({ detail: 'Upload failed. Please try again.' }, 500);
  }
});

api.post('/upload/base64-image', authMiddleware, async (c) => {
  // Alias for /upload/image
  const bodyTooLarge = rejectLargeRequest(c, 18_000_000);
  if (bodyTooLarge) return bodyTooLarge;
  const body = await c.req.json();
  const newReq = new Request(c.req.url.replace('base64-image', 'image'), {
    method: 'POST',
    headers: c.req.raw.headers,
    body: JSON.stringify(body),
  });
  return api.fetch(newReq, c.env);
});

api.post('/upload/file', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const bodyTooLarge = rejectLargeRequest(c, 26_000_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'upload_file', userId, 25, 60);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'upload_file_daily', userId, 120, 86400);
    if (dailyLimited) return dailyLimited;

    const formData = await c.req.raw.formData();
    const file = formData.get('file') as unknown as {
      type?: string;
      size?: number;
      name?: string;
      arrayBuffer?: () => Promise<ArrayBuffer>;
    } | null;
    if (!file || typeof file !== 'object' || typeof file.arrayBuffer !== 'function') {
      return c.json({ detail: 'No file provided' }, 400);
    }

    const fileType = normalizedContentType(file.type || '') || contentTypeFromFilename(file.name);
    const fileSize = Number(file.size || 0);
    if (!ALLOWED_FILE_TYPES.has(fileType) || !extensionAllowed(file.name, ALLOWED_FILE_EXTENSIONS)) {
      return c.json({ detail: 'Unsupported file type. Use PDF, TXT, Word, PowerPoint, or Excel files.' }, 400);
    }
    if (fileSize > 24_000_000) {
      return c.json({ detail: 'File is too large.', max_bytes: 24_000_000 }, 413);
    }

    const bytes = await file.arrayBuffer();
    const detectedType = detectDocumentContentType(new Uint8Array(bytes));
    if (!detectedType || !documentContentMatches(fileType, detectedType)) {
      await logSecurityEvent(c, 'file_upload_type_mismatch', userId, { declared_type: fileType, detected_type: detectedType || 'unknown' });
      return c.json({ detail: 'File type does not match the uploaded data.' }, 400);
    }
    const backup = await storeMediaBackup(c, {
      userId,
      mediaKind: 'file',
      provider: 'r2_file',
      contentType: fileType,
      bytes,
      originalFilename: file.name || `file.${contentTypeExtension(fileType, 'bin')}`,
    });
    if (!backup) return c.json({ detail: 'Media storage is not configured.' }, 503);

    return c.json({
      url: backup.delivery_url,
      id: backup.id,
      source: 'r2_file',
      backup_id: backup.id,
      size_bytes: backup.size_bytes,
      checksum_sha256: backup.checksum_sha256,
    });
  } catch (e: any) {
    console.error('File upload failed:', getErrorCode(e));
    return c.json({ detail: 'File upload failed. Please try again.' }, 500);
  }
});

api.post('/upload/audio', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const bodyTooLarge = rejectLargeRequest(c, 12_000_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'upload_audio', userId, 40, 60);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'upload_audio_daily', userId, 180, 86400);
    if (dailyLimited) return dailyLimited;

    const formData = await c.req.raw.formData();
    const file = formData.get('file') as unknown as {
      type?: string;
      size?: number;
      name?: string;
      arrayBuffer?: () => Promise<ArrayBuffer>;
    } | null;
    if (!file || typeof file !== 'object' || typeof file.arrayBuffer !== 'function') {
      return c.json({ detail: 'No audio file provided' }, 400);
    }

    const fileType = normalizedContentType(file.type || 'audio/m4a');
    const fileSize = Number(file.size || 0);
    if (!ALLOWED_AUDIO_TYPES.has(fileType) || !extensionAllowed(file.name, ALLOWED_AUDIO_EXTENSIONS)) {
      return c.json({ detail: 'Unsupported audio type. Use M4A, AAC, MP3, WAV, or WebM.' }, 400);
    }
    if (fileSize > 10_000_000) {
      return c.json({ detail: 'Audio is too large.', max_bytes: 10_000_000 }, 413);
    }

    const bytes = await file.arrayBuffer();
    const backup = await storeMediaBackup(c, {
      userId,
      mediaKind: 'audio',
      provider: 'r2_audio',
      contentType: fileType,
      bytes,
      originalFilename: file.name || `voice.${contentTypeExtension(fileType, 'm4a')}`,
    });
    if (!backup) return c.json({ detail: 'Media storage is not configured.' }, 503);

    return c.json({
      url: backup.delivery_url,
      id: backup.id,
      source: 'r2_audio',
      backup_id: backup.id,
      size_bytes: backup.size_bytes,
      checksum_sha256: backup.checksum_sha256,
    });
  } catch (e: any) {
    console.error('Audio upload failed:', getErrorCode(e));
    return c.json({ detail: 'Audio upload failed. Please try again.' }, 500);
  }
});

api.post('/upload/video', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'upload_video_direct', userId, 40, 60);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'upload_video_direct_daily', userId, 100, 86400);
    if (dailyLimited) return dailyLimited;
    if (!c.env.CLOUDFLARE_ACCOUNT_ID || !c.env.CLOUDFLARE_STREAM_TOKEN) {
      return c.json({ detail: 'Cloudflare Stream is not configured.' }, 503);
    }
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
    console.error('Video direct upload setup failed:', getErrorCode(e));
    return c.json({ detail: 'Video upload setup failed. Please try again.' }, 500);
  }
});

api.post('/upload/video-with-backup', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const maxBytes = maxBackupVideoBytes(c);
    const bodyTooLarge = rejectLargeRequest(c, maxBytes + 2_000_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'upload_video_backup', userId, 15, 60);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'upload_video_backup_daily', userId, 60, 86400);
    if (dailyLimited) return dailyLimited;
    const formData = await c.req.raw.formData();
    const file = formData.get('file') as unknown as {
      type?: string;
      size?: number;
      name?: string;
      arrayBuffer?: () => Promise<ArrayBuffer>;
    } | null;
    if (!file || typeof file !== 'object' || typeof file.arrayBuffer !== 'function') {
      return c.json({ detail: 'No video file provided' }, 400);
    }
    const fileType = normalizedContentType(file.type || 'video/mp4');
    const fileSize = Number(file.size || 0);
    if (!ALLOWED_VIDEO_TYPES.has(fileType) || !extensionAllowed(file.name, ALLOWED_VIDEO_EXTENSIONS)) {
      return c.json({ detail: 'Unsupported video type. Use MP4, MOV, or WebM.' }, 400);
    }
    if (fileSize > maxBytes) {
      return c.json({
        detail: 'Video is too large for Worker backup upload. Use direct Stream upload for this file.',
        max_bytes: maxBytes,
      }, 413);
    }

    const videoBytes = await file.arrayBuffer();
    const hasStreamConfig = !!(c.env.CLOUDFLARE_ACCOUNT_ID && c.env.CLOUDFLARE_STREAM_TOKEN);

    if (hasStreamConfig) {
      try {
        const directRes = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/stream/direct_upload`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${c.env.CLOUDFLARE_STREAM_TOKEN}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ maxDurationSeconds: 300, creator: userId }),
        });
        const directData: any = await directRes.json();
        if (directData.success) {
          const streamForm = new FormData();
          streamForm.append('file', new Blob([videoBytes], { type: fileType }), `${uuid()}.${contentTypeExtension(fileType, 'mp4')}`);
          const streamRes = await fetch(directData.result.uploadURL, { method: 'POST', body: streamForm });
          if (streamRes.ok) {
            const videoUid = directData.result.uid;
            const deliveryUrl = `cfstream:${videoUid}`;
            const backup = await storeMediaBackup(c, {
              userId,
              mediaKind: 'video',
              provider: 'cloudflare_stream',
              providerId: videoUid,
              deliveryUrl,
              contentType: fileType,
              bytes: videoBytes,
              originalFilename: file.name || 'upload.mp4',
            });

            return c.json({
              url: deliveryUrl,
              video_uid: videoUid,
              source: 'cloudflare_stream',
              backup_id: backup?.id || null,
              size_bytes: backup?.size_bytes || videoBytes.byteLength,
              checksum_sha256: backup?.checksum_sha256 || null,
            });
          }

          const errorText = await streamRes.text().catch(() => '');
          console.log('CF Stream upload failed, using R2 media storage:', streamRes.status, errorText.slice(0, 300));
        } else {
          console.log('CF Stream direct upload error, using R2 media storage:', JSON.stringify(directData.errors));
        }
      } catch (streamError: any) {
        console.log('CF Stream failed, using R2 media storage:', streamError?.message || streamError);
      }
    } else {
      console.log('CF Stream is not configured; using R2 media storage.');
    }

    const backup = await storeMediaBackup(c, {
      userId,
      mediaKind: 'video',
      provider: 'r2_video',
      contentType: fileType,
      bytes: videoBytes,
      originalFilename: file.name || 'upload.mp4',
    });
    if (!backup) return c.json({ detail: 'Media storage is not configured.' }, 503);

    return c.json({
      url: backup.delivery_url,
      video_uid: backup.id,
      source: 'r2_video',
      backup_id: backup.id,
      size_bytes: backup.size_bytes,
      checksum_sha256: backup.checksum_sha256,
    });
  } catch (e: any) {
    console.error('Video upload failed:', getErrorCode(e));
    return c.json({ detail: 'Video upload failed. Please try again.' }, 500);
  }
});

// Get video playback info from Cloudflare Stream
api.get('/stream/video/:videoUid', async (c) => {
  const uid = c.req.param('videoUid');
  try {
    const cacheKey = `stream:video:${uid}`;
    const cached = c.env.KV ? await c.env.KV.get(cacheKey, 'json').catch(() => null) : null;
    if (cached) {
      const response = c.json(cached);
      response.headers.set('cache-control', 'public, max-age=60, s-maxage=300');
      return response;
    }

    const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${c.env.CLOUDFLARE_ACCOUNT_ID}/stream/${uid}`, {
      headers: { 'Authorization': `Bearer ${c.env.CLOUDFLARE_STREAM_TOKEN}` },
    });
    const data: any = await res.json();
    if (!data.success || !data.result) return c.json({ detail: 'Video not found' }, 404);
    const v = data.result;
    const payload = {
      uid: v.uid,
      status: v.status?.state || 'unknown',
      duration: v.duration,
      thumbnail: v.thumbnail,
      preview: v.preview,
      playback: v.playback || {},
      hls: v.playback?.hls || null,
      dash: v.playback?.dash || null,
      ready: v.readyToStream || false,
    };
    if (c.env.KV) {
      await c.env.KV.put(cacheKey, JSON.stringify(payload), { expirationTtl: payload.ready ? 300 : 20 }).catch(() => undefined);
    }
    const response = c.json(payload);
    response.headers.set('cache-control', payload.ready ? 'public, max-age=60, s-maxage=300' : 'public, max-age=5, s-maxage=20');
    return response;
  } catch (e: any) {
    console.error('Stream fetch failed:', getErrorCode(e));
    return c.json({ detail: 'Stream fetch failed. Please try again.' }, 500);
  }
});

// Mapbox Places proxy.
async function mapboxPlacesNearbyHandler(c: any) {
  try {
    const identity = (await getOptionalUserId(c)) || clientIp(c);
    const limited = await enforceRateLimit(c, 'mapbox_places', identity, 60, 60);
    if (limited) return limited;
    const token = getMapboxAccessToken(c);
    const lat = String(clampFloat(c.req.query('lat') || 40.7128, -90, 90, 40.7128));
    const lng = String(clampFloat(c.req.query('lng') || -74.006, -180, 180, -74.006));
    const type = cleanText(c.req.query('type') || 'restaurant', 40) || 'restaurant';
    const keyword = cleanText(c.req.query('keyword') || '', 80);
    const query = keyword || type;
    const params = new URLSearchParams({
      q: query,
      language: 'en',
      limit: '10',
      country: 'US',
      types: 'poi',
      proximity: `${lng},${lat}`,
      access_token: token,
    });

    const res = await fetch(`${MAPBOX_SEARCH_BOX_API_BASE}/forward?${params.toString()}`);
    if (!res.ok) return c.json({ error: `Mapbox search failed: ${res.status}`, places: [] }, 502);

    const data: any = await res.json();
    const places = Array.isArray(data.features)
      ? data.features.map((feature: any, index: number) => mapboxFeatureToPlace(feature, `mapbox-${type}-${index}`))
      : [];
    return c.json(places);
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'MAPBOX_ACCESS_TOKEN_MISSING') {
      return c.json({ error: 'Mapbox access token is not configured', places: [] }, 503);
    }
    return c.json({ error: 'Mapbox places could not load', places: [] }, 500);
  }
}

async function mapboxPlaceDetailHandler(c: any) {
  const pid = c.req.param('placeId');
  try {
    const identity = (await getOptionalUserId(c)) || clientIp(c);
    const limited = await enforceRateLimit(c, 'mapbox_place_detail', identity, 90, 60);
    if (limited) return limited;
    const token = getMapboxAccessToken(c);
    const params = new URLSearchParams({
      session_token: crypto.randomUUID(),
      access_token: token,
      language: 'en',
    });
    const res = await fetch(`${MAPBOX_SEARCH_BOX_API_BASE}/retrieve/${encodeURIComponent(pid)}?${params.toString()}`);
    if (res.ok) {
      const data: any = await res.json();
      const feature = Array.isArray(data.features) ? data.features[0] : null;
      if (feature) {
        const place = mapboxFeatureToPlace(feature, pid);
        return c.json({
          ...place,
          address: place.formatted_address || place.vicinity,
          phone: '',
          website: '',
          price_level: null,
          url: place.mapbox_url,
          opening_hours: null,
          reviews: [],
          photos: [],
        });
      }
    }
  } catch {}

  const lat = c.req.query('lat');
  const lng = c.req.query('lng');
  return c.json({
    place_id: pid,
    mapbox_id: pid,
    name: cleanText(c.req.query('name') || 'Mapbox place', 160),
    address: cleanText(c.req.query('address') || '', 220),
    vicinity: cleanText(c.req.query('address') || '', 220),
    phone: '',
    rating: null,
    user_ratings_total: null,
    website: '',
    price_level: null,
    types: [],
    url: '',
    mapbox_url: lat && lng ? `https://www.mapbox.com/search?query=${encodeURIComponent(pid)}&center=${lng},${lat}` : '',
    lat: lat ? clampFloat(lat, -90, 90, 0) : null,
    lng: lng ? clampFloat(lng, -180, 180, 0) : null,
    opening_hours: null,
    reviews: [],
    photos: [],
  });
}

async function mapboxCitySearchHandler(c: any) {
  try {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'mapbox_city_search', userId, 45, 60);
    if (limited) return limited;
    const query = cleanText(c.req.query('q') || c.req.query('query') || '', 80);
    if (query.length < 2) return c.json({ locations: [] });
    const token = getMapboxAccessToken(c);
    const params = new URLSearchParams({
      q: query,
      language: 'en',
      limit: '8',
      types: 'place,region,country',
      access_token: token,
    });
    const proximity = cleanText(c.req.query('proximity'), 80);
    if (proximity) params.set('proximity', proximity);
    const res = await fetch(`${MAPBOX_SEARCH_BOX_API_BASE}/forward?${params.toString()}`);
    if (!res.ok) return c.json({ detail: 'Mapbox city search failed.', locations: [] }, 502);
    const data: any = await res.json();
    const locations = Array.isArray(data.features)
      ? data.features.map(mapboxFeatureToBroadLocation).filter((item: any) => item.label)
      : [];
    return c.json({ locations });
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'MAPBOX_ACCESS_TOKEN_MISSING') return c.json({ detail: 'Mapbox is not configured.', locations: [] }, 503);
    return c.json({ detail: 'City search could not load.', locations: [] }, 500);
  }
}

async function mapboxReverseBroadLocationHandler(c: any) {
  try {
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'mapbox_reverse_city', userId, 45, 60);
    if (limited) return limited;
    const lat = clampFloat(c.req.query('lat'), -90, 90, NaN);
    const lng = clampFloat(c.req.query('lng'), -180, 180, NaN);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return c.json({ detail: 'Approximate latitude and longitude are required.' }, 400);
    const token = getMapboxAccessToken(c);
    const params = new URLSearchParams({
      latitude: String(lat),
      longitude: String(lng),
      language: 'en',
      types: 'place,region,country',
      access_token: token,
    });
    const res = await fetch(`${MAPBOX_GEOCODING_API_BASE}/reverse?${params.toString()}`);
    if (!res.ok) return c.json({ detail: 'Mapbox reverse geocoding failed.' }, 502);
    const data: any = await res.json();
    const feature = Array.isArray(data.features) ? data.features[0] : null;
    if (!feature) return c.json({ location: null });
    return c.json({ location: mapboxFeatureToBroadLocation(feature) });
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'MAPBOX_ACCESS_TOKEN_MISSING') return c.json({ detail: 'Mapbox is not configured.' }, 503);
    return c.json({ detail: 'Broad location could not load.' }, 500);
  }
}

api.get('/mapbox-places/nearby', mapboxPlacesNearbyHandler);
api.get('/mapbox-places/:placeId', mapboxPlaceDetailHandler);
api.get('/mapbox-locations/cities', authMiddleware, mapboxCitySearchHandler);
api.get('/mapbox-locations/reverse', authMiddleware, mapboxReverseBroadLocationHandler);

// Health
api.get('/', (c) => c.json({ message: 'Captro API', version: API_VERSION, runtime: 'Cloudflare Workers + Hono + D1 + Supabase' }));
api.get('/health', async (c) => {
  const startedAt = Date.now();
  const dbStartedAt = Date.now();
  let databaseHealthy = false;
  try {
    const row: any = await c.env.DB.prepare('SELECT 1 AS ok').first();
    databaseHealthy = Number(row?.ok || 0) === 1;
  } catch {
    databaseHealthy = false;
  }
  const response = c.json({
    status: databaseHealthy ? 'healthy' : 'degraded',
    environment: c.env.ENVIRONMENT || 'unknown',
    service: WORKER_NAME,
    version: c.env.WORKER_VERSION || API_VERSION,
    commit: c.env.SOURCE_COMMIT || '',
    timestamp: now(),
    checks: {
      database: {
        configured: true,
        healthy: databaseHealthy,
        latency_ms: Date.now() - dbStartedAt,
      },
    },
    latency_ms: Date.now() - startedAt,
  }, databaseHealthy ? 200 : 503);
  response.headers.set('cache-control', 'no-store');
  return response;
});
api.get('/database/status', authMiddleware, async (c) => {
  try {
    await requireOwnerOrAdmin(c);
    const d1Check = await c.env.DB.prepare('SELECT 1 AS ok').first().then(() => true).catch(() => false);
    let kvCheck = false;
    if (c.env.KV) {
      const key = `health:database:${uuid()}`;
      await c.env.KV.put(key, 'ok', { expirationTtl: 60 });
      const value = await c.env.KV.get(key);
      await c.env.KV.delete(key).catch(() => undefined);
      kvCheck = value === 'ok';
    }
    return c.json({
      d1_sqlite: { configured: true, healthy: d1Check },
      kv_nosql: { configured: !!c.env.KV, healthy: kvCheck },
      postgres_hyperdrive: {
        configured: !!c.env.HYPERDRIVE,
        healthy: !!c.env.HYPERDRIVE,
        note: c.env.HYPERDRIVE ? 'Hyperdrive binding is available.' : 'Add a Hyperdrive binding after creating it with the Supabase Postgres connection string.',
      },
      supabase_postgres_jsonb: {
        configured: !!c.env.SUPABASE_URL,
        service_role_secret_set: !!c.env.SUPABASE_SERVICE_ROLE_KEY,
        note: 'Supabase stores relational data in Postgres and flexible NoSQL-style app_documents/editor metadata in JSONB.',
      },
      timestamp: now(),
    });
  } catch (error: any) {
    const forbidden = String(error?.message || '') === 'FORBIDDEN';
    return c.json({ detail: forbidden ? 'Owner access required.' : 'Could not check database status.', code: forbidden ? 'FORBIDDEN' : 'DATABASE_STATUS_FAILED' }, forbidden ? 403 : 500);
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// BOOKMARKS / SAVE SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

// Setup bookmarks table
api.post('/bookmarks/setup-db', authMiddleware, async (c) => {
  try {
    await requireOwnerOrAdmin(c);
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
  } catch (e: any) {
    const forbidden = String(e?.message || '') === 'FORBIDDEN';
    if (forbidden) return c.json({ detail: 'Owner access required.' }, 403);
    console.error('Bookmarks setup failed:', getErrorCode(e));
    return c.json({ success: true, message: 'Tables already exist or could not be changed now' });
  }
});

// Save/Bookmark a post
api.post('/bookmarks', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await ensureGovernanceSchema(c.env.DB);
  const limited = await enforceRateLimit(c, 'save_post', userId, 240, 60);
  if (limited) return limited;
  const { post_id, collection } = await c.req.json().catch(() => ({}));
  const postId = publicId(post_id, 120);
  if (!postId) return c.json({ detail: 'post_id required' }, 400);
  const id = uuid();
  try {
    const post = await c.env.DB.prepare('SELECT id FROM posts WHERE id = ?').bind(postId).first();
    if (!post) return c.json({ detail: 'Post not found' }, 404);
    const collectionName = cleanText(collection || 'saved', 80) || 'saved';
    const existingSave = await c.env.DB.prepare('SELECT id FROM saved_posts WHERE user_id = ? AND post_id = ?').bind(userId, postId).first();
    if (existingSave) {
      await c.env.DB.prepare('UPDATE saved_posts SET collection = ? WHERE user_id = ? AND post_id = ?').bind(collectionName, userId, postId).run();
    } else {
      await c.env.DB.prepare('INSERT INTO saved_posts (id, user_id, post_id, collection) VALUES (?, ?, ?, ?)').bind(uuid(), userId, postId, collectionName).run();
    }
    const engagement = await getPostEngagementState(c.env.DB, postId, userId);
    try {
      await c.env.DB.prepare('INSERT INTO bookmarks (id, user_id, post_id, collection) VALUES (?, ?, ?, ?) ON CONFLICT(user_id, post_id) DO UPDATE SET collection = ?')
        .bind(id, userId, postId, collectionName, collectionName).run();
    } catch {}
    runBackgroundTask(c, 'supabase_bookmark_write_through_failed', async () => {
      await mirrorLegacyInteractionToSupabase(c, postId, userId, 'save', true, collectionName);
      await mirrorLegacyPostToSupabase(c, postId);
    });
    return c.json({
      saved: engagement.saved,
      collection: collectionName,
      saves_count: engagement.saves_count,
      liked: engagement.liked,
      likes_count: engagement.likes_count,
      comments_count: engagement.comments_count,
    });
  } catch (e: any) {
    console.error('Bookmark save failed:', getErrorCode(e));
    return c.json({ detail: 'Save failed. Please try again.' }, 500);
  }
});

// Unsave/Remove bookmark
api.delete('/bookmarks/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await ensureGovernanceSchema(c.env.DB);
  const limited = await enforceRateLimit(c, 'save_post', userId, 240, 60);
  if (limited) return limited;
  const postId = publicId(c.req.param('postId'), 120);
  const existingSave = await c.env.DB.prepare('SELECT id FROM saved_posts WHERE user_id = ? AND post_id = ?').bind(userId, postId).first();
  if (existingSave) {
    await c.env.DB.prepare('DELETE FROM saved_posts WHERE user_id = ? AND post_id = ?').bind(userId, postId).run();
  }
  try { await c.env.DB.prepare('DELETE FROM bookmarks WHERE user_id = ? AND post_id = ?').bind(userId, postId).run(); } catch {}
  if (existingSave) {
    runBackgroundTask(c, 'supabase_bookmark_delete_write_through_failed', async () => {
      await mirrorLegacyInteractionToSupabase(c, postId, userId, 'save', false);
      await mirrorLegacyPostToSupabase(c, postId);
    });
  }
  const engagement = await getPostEngagementState(c.env.DB, postId, userId);
  return c.json({
    saved: engagement.saved,
    saves_count: engagement.saves_count,
    liked: engagement.liked,
    likes_count: engagement.likes_count,
    comments_count: engagement.comments_count,
  });
});

// Get saved posts by collection
api.get('/bookmarks', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const collection = cleanText(c.req.query('collection'), 80);
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
  const postId = c.req.param('postId');
  const r: any = await c.env.DB.prepare(
    `SELECT collection FROM bookmarks WHERE user_id = ? AND post_id = ?
     UNION
     SELECT collection FROM saved_posts WHERE user_id = ? AND post_id = ?
     LIMIT 1`
  ).bind(userId, postId, userId, postId).first();
  return c.json({ saved: !!r, collection: r?.collection || null });
});

// Save a place (My Spots)
api.post('/saved-places', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const { place_id, place_name, place_type, save_type } = await c.req.json().catch(() => ({}));
  const placeId = cleanText(place_id, 160);
  if (!placeId) return c.json({ detail: 'place_id required' }, 400);
  const id = uuid();
  try {
    await c.env.DB.prepare('INSERT INTO saved_places (id, user_id, place_id, place_name, place_type, save_type) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, place_id) DO UPDATE SET save_type = ?')
      .bind(id, userId, placeId, cleanText(place_name, 240), cleanText(place_type, 80), cleanText(save_type || 'want_to_go', 40), cleanText(save_type || 'want_to_go', 40)).run();
    return c.json({ saved: true });
  } catch (e: any) {
    console.error('Saved place failed:', getErrorCode(e));
    return c.json({ detail: 'Save failed. Please try again.' }, 500);
  }
});

// Get saved places (My Spots)
api.get('/saved-places', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const save_type = c.req.query('type');
  let q = 'SELECT * FROM saved_places WHERE user_id = ?';
  const binds: any[] = [userId];
  if (save_type) { q += ' AND save_type = ?'; binds.push(cleanText(save_type, 40)); }
  q += ' ORDER BY created_at DESC';
  const { results } = await c.env.DB.prepare(q).bind(...binds).all();
  return c.json({ places: results || [] });
});

// Remove saved place
api.delete('/saved-places/:placeId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  await c.env.DB.prepare('DELETE FROM saved_places WHERE user_id = ? AND place_id = ?').bind(userId, cleanText(c.req.param('placeId'), 160)).run();
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
  } catch (e: any) { console.error('Creator setup failed:', getErrorCode(e)); return c.json({ success: true, message: 'Tables already exist or could not be changed now' }); }
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
    console.error('Creator application failed:', getErrorCode(e));
    return c.json({ detail: 'Failed to submit application.' }, 500);
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
    const updateCreatorSql = `UPDATE creators SET ${fields.join(', ')} WHERE user_id = ?`;
    await c.env.DB.prepare(updateCreatorSql).bind(...vals).run();
    return c.json({ message: 'Creator profile updated' });
  } catch (e: any) { console.error('Creator profile update failed:', getErrorCode(e)); return c.json({ detail: 'Update failed' }, 500); }
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
    const creatorsSql = `
      SELECT c.*, u.full_name, u.username, u.profile_image, u.followers_count, u.posts_count
      FROM creators c JOIN users u ON c.user_id = u.id
      WHERE ${where} ORDER BY u.followers_count DESC, c.created_at DESC LIMIT ? OFFSET ?
    `;
    const { results } = await c.env.DB.prepare(creatorsSql).bind(...binds).all();
    const creators = (results || []).map((cr: any) => ({
      ...cr, portfolio_links: JSON.parse(cr.portfolio_links || '[]'),
      skills: JSON.parse(cr.skills || '[]'),
    }));
    return c.json({ creators, count: creators.length });
  } catch (e: any) { console.error('Creators list failed:', getErrorCode(e)); return c.json({ creators: [], count: 0 }); }
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
  } catch (e: any) { console.error('Creator detail failed:', getErrorCode(e)); return c.json({ detail: 'Error fetching creator' }, 500); }
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
  } catch (e: any) { console.error('Creator portfolio add failed:', getErrorCode(e)); return c.json({ detail: 'Failed to add portfolio item' }, 500); }
});

api.delete('/creators/portfolio/:itemId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const itemId = c.req.param('itemId');
  try {
    const creator: any = await c.env.DB.prepare('SELECT id FROM creators WHERE user_id = ?').bind(userId).first();
    if (!creator) return c.json({ detail: 'Not a creator' }, 403);
    await c.env.DB.prepare('DELETE FROM creator_portfolio_items WHERE id = ? AND creator_id = ?').bind(itemId, creator.id).run();
    return c.json({ message: 'Portfolio item removed' });
  } catch (e: any) { console.error('Creator portfolio delete failed:', getErrorCode(e)); return c.json({ detail: 'Delete failed' }, 500); }
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
  } catch (e: any) { console.error('Creator applications list failed:', getErrorCode(e)); return c.json({ applications: [] }); }
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
  } catch (e: any) { console.error('Creator approve failed:', getErrorCode(e)); return c.json({ detail: 'Approve failed' }, 500); }
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
  } catch (e: any) { console.error('Creator reject failed:', getErrorCode(e)); return c.json({ detail: 'Reject failed' }, 500); }
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
  } catch (e: any) { console.error('Creator badge remove failed:', getErrorCode(e)); return c.json({ detail: 'Remove badge failed' }, 500); }
});

// ═══════════════════════════════════════════════════════════════
// ADMIN GOVERNANCE ENDPOINTS
// ═══════════════════════════════════════════════════════════════

// Helper: check admin
const requireAdmin = async (c: any) => {
  const admin = await requireAdminRole(c, 'admin:read');
  return admin.userId;
};

api.post('/admin/supabase/transfer', authMiddleware, async (c) => {
  try {
    const adminId = await requireAdmin(c);
    const body: any = await c.req.json().catch(() => ({}));
    const limit = clampNumber(body.limit || c.req.query('limit'), 1, 1000, 500);
    const offset = clampNumber(body.offset || c.req.query('offset'), 0, 1_000_000_000, 0);
    const requestedTables = Array.isArray(body.tables) ? body.tables.map(String) : [];
    const allTables = ['users', 'posts', 'comments', 'interactions', 'follows'];
    const tables = requestedTables.length ? allTables.filter((table) => requestedTables.includes(table)) : allTables;
    if (!tables.length) return c.json({ detail: 'No valid transfer tables requested.' }, 400);

    const results: any[] = [];
    if (tables.includes('users')) results.push(await transferLegacyUsersToSupabase(c, limit, offset));
    if (tables.includes('posts')) results.push(await transferLegacyPostsToSupabase(c, limit, offset));
    if (tables.includes('comments')) results.push(await transferLegacyCommentsToSupabase(c, limit, offset));
    if (tables.includes('interactions')) results.push(await transferLegacyInteractionsToSupabase(c, limit, offset));
    if (tables.includes('follows')) results.push(await transferLegacyFollowsToSupabase(c, limit, offset));

    try {
      await supabaseAdminUpsert(c, 'app_documents', [{
        owner_id: null,
        collection: 'transfer_runs',
        document_key: `d1_${Date.now()}_${offset}`,
        visibility: 'private',
        document: {
          source: 'cloudflare_d1',
          admin_id: adminId,
          limit,
          offset,
          tables,
          results,
          created_at: now(),
        },
      }], 'owner_id,collection,document_key');
    } catch {}

    return c.json({
      ok: true,
      limit,
      offset,
      next_offset: offset + limit,
      results,
      note: 'Run again with the next_offset until every table returns 0 rows.',
    });
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'FORBIDDEN') return c.json({ detail: 'Admin only' }, 403);
    if (code === 'SUPABASE_NOT_CONFIGURED') return c.json({ detail: 'SUPABASE_URL is not configured.' }, 503);
    if (code === 'SUPABASE_SERVICE_ROLE_MISSING') {
      return c.json({
        detail: 'Set SUPABASE_SERVICE_ROLE_KEY as a Cloudflare Worker secret before transfer.',
        command: 'npx.cmd wrangler secret put SUPABASE_SERVICE_ROLE_KEY',
      }, 503);
    }
    console.error('Supabase transfer failed:', code, error?.message || error);
    return c.json({ detail: 'Supabase transfer failed.', code }, 500);
  }
});

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
      CREATE TABLE IF NOT EXISTS notifications (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'general',
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        data TEXT DEFAULT '{}',
        is_read INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (user_id) REFERENCES users(id)
      );
    `);
    return c.json({ message: 'Governance tables created' });
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// ── Applications ──

// Submit application (from main app)
api.post('/applications', authMiddleware, async (c) => {
  const body = await c.req.json();
  const { type } = body; // type: 'creator' | 'publisher'
  if (!type || !['creator', 'publisher'].includes(type)) return c.json({ detail: 'Invalid type' }, 400);
  return c.json({ detail: 'Creator and publisher applications have been removed from Flames Up.' }, 410);
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
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
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
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// ── Reports ──

// Submit report (from main app)
api.post('/reports', authMiddleware, async (c) => {
  return await submitReportRequest(c);
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
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Review report (admin)
api.put('/admin/reports/:id', authMiddleware, async (c) => {
  try {
    const adminId = await requireAdmin(c);
    const reportId = c.req.param('id');
    const body = await c.req.json();
    const { status, admin_notes, action_taken } = body;
    const ts = now();
    const normalizedStatus = normalizeReportStatus(status || action_taken || 'under_review', 'under_review');
    await c.env.DB.prepare(
      'UPDATE reports SET status = ?, admin_notes = ?, action_taken = ?, reviewed_by = ?, reviewed_at = ?, updated_at = ? WHERE id = ?'
    ).bind(normalizedStatus, cleanMultilineText(admin_notes || '', 1000), cleanText(action_taken || normalizedStatus, 120), adminId, ts, ts, reportId).run();

    await c.env.DB.prepare(
      'INSERT INTO admin_actions (id, admin_id, action_type, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).bind(crypto.randomUUID(), adminId, `report_${normalizedStatus}`, 'report', reportId, JSON.stringify(scrubLogMetadata({ admin_notes, action_taken })), ts).run();

    return c.json({ message: 'Report updated' });
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// ── Content Moderation ──

// Admin: Remove post
api.delete('/admin/posts/:postId', authMiddleware, async (c) => {
  try {
    const adminId = await requireAdmin(c);
    const postId = c.req.param('postId');
    const ts = now();
    await ensureGovernanceSchema(c.env.DB);
    await c.env.DB.prepare("UPDATE posts SET status = 'removed', removed_at = ?, removed_reason = 'Removed by admin' WHERE id = ?")
      .bind(ts, postId).run();

    await c.env.DB.prepare(
      'INSERT INTO admin_actions (id, admin_id, action_type, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).bind(crypto.randomUUID(), adminId, 'remove_post', 'post', postId, JSON.stringify({ soft_deleted: true }), ts).run();

    return c.json({ message: 'Post removed', soft_deleted: true });
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
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
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Admin: Get all users
api.get('/admin/users', authMiddleware, async (c) => {
  try {
    await requireAdmin(c);
    const r = await c.env.DB.prepare(
      'SELECT id, email, full_name, username, profile_image, is_admin, is_creator, is_publisher, is_verified, created_at FROM users ORDER BY created_at DESC LIMIT 200'
    ).all();
    return c.json(r.results);
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
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
    const updateTargetUserSql = `UPDATE users SET ${fields.join(', ')} WHERE id = ?`;
    await c.env.DB.prepare(updateTargetUserSql).bind(...vals).run();

    await c.env.DB.prepare(
      'INSERT INTO admin_actions (id, admin_id, action_type, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).bind(crypto.randomUUID(), adminId, 'update_user', 'user', targetUserId, JSON.stringify(body), ts).run();

    return c.json({ message: 'User updated' });
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Admin: Action log
api.get('/admin/actions', authMiddleware, async (c) => {
  try {
    await requireAdmin(c);
    const r = await c.env.DB.prepare(
      'SELECT a.*, u.full_name as admin_name FROM admin_actions a LEFT JOIN users u ON a.admin_id = u.id ORDER BY a.created_at DESC LIMIT 100'
    ).all();
    return c.json(r.results);
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
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
  } catch (e: any) { return c.json({ detail: e?.message === 'FORBIDDEN' ? 'Admin access required' : 'Request failed.' }, e?.message === 'FORBIDDEN' ? 403 : 500); }
});

// Mount API routes on app
app.route('/api', api);

export default app;
