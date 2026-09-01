// Captro Cloudflare Workers API — Hono + Supabase Postgres + Cloudflare Images/R2/Stream
// Deploy: wrangler deploy --env production --keep-vars
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import bcrypt from 'bcryptjs';
import { createCaptroScanRoutes } from './scan';

type MediaModerationJobMessage = {
  jobId: string;
  mediaId: string;
  userId: string;
  reason: 'upload_complete' | 'manual_retry' | 'admin_retry';
  caption?: string;
};

// ─── Types ───────────────────────────────────────────────────────────────────
interface Env {
  DB: D1Database;
  KV?: KVNamespace;
  HYPERDRIVE?: any;
  AI?: any;
  MEDIA_MODERATION_QUEUE?: Queue<MediaModerationJobMessage>;
  MEDIA_BACKUP?: R2Bucket;
  JWT_SECRET: string;
  CLOUDFLARE_ACCOUNT_ID: string;
  CLOUDFLARE_API_TOKEN?: string;
  CF_API_TOKEN?: string;
  CF_ACCOUNT_ID?: string;
  CF_ACCOUNT_HASH?: string;
  CLOUDFLARE_IMAGES_ACCOUNT_HASH?: string;
  CLOUDFLARE_IMAGES_TOKEN?: string;
  CLOUDFLARE_IMAGES_FEED_VARIANT?: string;
  CLOUDFLARE_IMAGES_THUMBNAIL_VARIANT?: string;
  CLOUDFLARE_IMAGES_REQUIRE_SIGNED_URLS?: string;
  CLOUDFLARE_IMAGES_PRESERVE_CONTENT_CREDENTIALS?: string;
  CLOUDFLARE_IMAGE_TRANSFORMS_ENABLED?: string;
  CLOUDFLARE_IMAGE_TRANSFORM_BASE_URL?: string;
  CLOUDFLARE_STREAM_TOKEN?: string;
  CLOUDFLARE_STREAM_REQUIRE_SIGNED_URLS?: string;
  RESEND_API_KEY?: string;
  EMAIL_FROM?: string;
  EMAIL_VERIFICATION_BASE_URL?: string;
  AI_IMAGE_MODERATION_MODEL?: string;
  AI_TEXT_MODERATION_MODEL?: string;
  AI_GENERATED_MEDIA_POLICY?: string;
  MALWARE_SCANNER_URL?: string;
  MALWARE_SCANNER_TOKEN?: string;
  MEDIA_MAX_IMAGE_BYTES?: string;
  MEDIA_MAX_VIDEO_BYTES?: string;
  C2PA_VERIFIER_URL?: string;
  C2PA_VERIFIER_TOKEN?: string;
  POST_ASSIST_MODEL?: string;
  MAPBOX_ACCESS_TOKEN?: string;
  ENVIRONMENT?: string;
  FRONTEND_URL: string;
  OWNER_USERNAMES?: string;
  OWNER_EMAILS?: string;
  GOOGLE_OAUTH_CLIENT_ID?: string;
  GOOGLE_OAUTH_CLIENT_IDS?: string;
  OAUTH_FALLBACK_SECRET?: string;
  SUPABASE_URL?: string;
  SUPABASE_ANON_KEY?: string;
  SUPABASE_PUBLISHABLE_KEY?: string;
  SUPABASE_JWT_ISSUER?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  DATABASE_PRIMARY?: string;
  APPLE_OAUTH_CLIENT_ID?: string;
  APPLE_OAUTH_CLIENT_SECRET?: string;
  APPLE_REVOKE_CLIENT_SECRET?: string;
  APPLE_OAUTH_AUDIENCE?: string;
  APPLE_OAUTH_AUDIENCES?: string;
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_AUTH_TOKEN?: string;
  TWILIO_VERIFY_SERVICE_SID?: string;
  TWILIO_SERVICE_SID?: string;
  TWILIO_FROM_PHONE?: string;
  APNS_TEAM_ID?: string;
  APNS_KEY_ID?: string;
  APNS_BUNDLE_ID?: string;
  APNS_PRIVATE_KEY?: string;
  APNS_ENVIRONMENT?: string;
  MEDIA_BACKUP_MAX_VIDEO_BYTES?: string;
  PUBLIC_API_BASE_URL?: string;
  SOURCE_COMMIT?: string;
  WORKER_VERSION?: string;
  DATA_RESET_VERSION?: string;
  DATA_RESET_AT?: string;
  STRIPE_SECRET_KEY?: string;
  STRIPE_PUBLISHABLE_KEY?: string;
  STRIPE_DEFAULT_PRICE_ID?: string;
  STRIPE_PREMIUM_PRICE_ID?: string;
  STRIPE_SUCCESS_URL?: string;
  STRIPE_CANCEL_URL?: string;
  STRIPE_WEBHOOK_SECRET?: string;
  VERYFI_CLIENT_ID?: string;
  VERYFI_CLIENT_SECRET?: string;
  VERYFI_USERNAME?: string;
  VERYFI_API_KEY?: string;
  VERYFI_BASE_URL?: string;
  RECEIPT_REWARD_CENTS?: string;
  INVOICE_REWARD_CENTS?: string;
  APP_STORE_CONNECT_API_ISSUER_ID?: string;
  APP_STORE_CONNECT_API_KEY_ID?: string;
  APP_STORE_CONNECT_API_KEY_BASE64?: string;
  APP_STORE_BUNDLE_ID?: string;
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
const WORKER_NAME = 'captro-api';

// Root handler
app.get('/', (c) => c.json({ name: 'Captro API', version: API_VERSION, status: 'live', docs: '/api/health' }));

const api = new Hono<HonoApp>();

// ─── CORS ────────────────────────────────────────────────────────────────────
const DEFAULT_ALLOWED_ORIGINS = [
  'https://captro.app',
  'https://www.captro.app',
  'https://admin.captro.app',
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
  detail: `${feature} has been removed from Captro.`,
}, 410);

api.all('/publisher/*', retiredFeature('Publisher tools'));
api.all('/admin/publisher-applications', retiredFeature('Publisher applications'));
api.all('/admin/publisher-applications/*', retiredFeature('Publisher applications'));
api.all('/creators', retiredFeature('Creator Hub'));
api.all('/creators/*', retiredFeature('Creator Hub'));

function appDataGeneration(env: Env): string {
  return cleanText(env.DATA_RESET_VERSION || env.WORKER_VERSION || env.SOURCE_COMMIT || '2026-06-15-production-reset-v1', 120)
    || '2026-06-15-production-reset-v1';
}

api.get('/system/data-state', (c) => {
  c.header('Cache-Control', 'no-store');
  return c.json({
    database: 'supabase_postgres',
    media_storage: 'cloudflare_images_stream',
    data_generation: appDataGeneration(c.env),
    data_reset_at: cleanText(c.env.DATA_RESET_AT || '2026-06-15T21:44:27Z', 80),
    app_data_cleared: true,
  });
});
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
api.all('/recommendations', retiredFeature('Recommendations'));
api.all('/recommendations/*', retiredFeature('Recommendations'));
api.all('/people', retiredFeature('People profiles'));
api.all('/people/*', retiredFeature('People profiles'));
api.all('/admin/people/*', retiredFeature('People profile admin tools'));
api.all('/premium', retiredFeature('Premium checkout'));
api.all('/premium/*', retiredFeature('Premium checkout'));
api.all('/places', retiredFeature('Legacy custom places'));
api.all('/places/*', retiredFeature('Legacy custom places'));
api.all('/saved-places', retiredFeature('Legacy saved places'));
api.all('/saved-places/*', retiredFeature('Legacy saved places'));
api.all('/discover/posts', retiredFeature('Legacy Discover posts'));
api.all('/discover/posts/*', retiredFeature('Legacy Discover posts'));
api.all('/admin/governance', retiredFeature('Legacy governance admin tools'));
api.all('/admin/governance/*', retiredFeature('Legacy governance admin tools'));
api.all('/admin/init-governance', retiredFeature('Legacy governance initialization'));
api.all('/admin/applications', retiredFeature('Creator and publisher applications'));
api.all('/admin/applications/*', retiredFeature('Creator and publisher applications'));
api.all('/admin/media-backups', retiredFeature('Legacy media backups'));
api.all('/admin/media-backups/*', retiredFeature('Legacy media backups'));

api.use('/admin/*', async (c, next) => {
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'admin');
  if (supabaseRequired) return supabaseRequired;
  await next();
});
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

function canonicalSupabaseRequestPayload(payload: any, user: any): any {
  const appUserId = publicId(user?.id, 120);
  if (!appUserId) return payload || {};
  const supabaseSub = isUuidText(user?.supabase_user_id || (payload as any)?.supabase_sub || (payload as any)?.supabaseSub);
  return {
    ...(payload || {}),
    sub: appUserId,
    userId: appUserId,
    supabase_sub: supabaseSub || undefined,
  };
}

// ─── Auth Middleware ──────────────────────────────────────────────────────────
const authMiddleware = async (c: any, next: () => Promise<void>) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return c.json({ detail: 'Not authenticated' }, 401);
  const token = authHeader.slice(7);
  let payload: any;
  let userId = '';
  let user: any = null;

  try {
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'auth_context');
    if (supabaseRequired) return supabaseRequired;
    const resolved = await resolveSupabaseSessionUser(c, token);
    payload = resolved.payload;
    userId = resolved.userId;
    user = resolved.user;
    c.set('jwtPayload', payload);
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'SUPABASE_NOT_CONFIGURED' || code === 'SUPABASE_SERVICE_ROLE_MISSING' || code === 'SUPABASE_AUTH_KEY_MISSING') {
      return c.json({ detail: 'Captro production database is not configured. Please try again later.', code: 'SUPABASE_PRIMARY_REQUIRED' }, 503);
    }
    return c.json({ detail: 'Invalid session. Please sign in again.', code: 'INVALID_TOKEN' }, 401);
  }

  if (!userId) return c.json({ detail: 'Invalid token', code: 'INVALID_TOKEN' }, 401);

  try {
    if (!user) return c.json({ detail: 'Session user was not found.', code: 'USER_NOT_FOUND' }, 401);

    const accountStatus = String(user?.status || 'active');
    const revokedAt = Date.parse(String(user?.session_revoked_at || ''));
    const issuedAt = Number((payload as any)?.iat || 0) * 1000;
    if (Number.isFinite(revokedAt) && revokedAt > 0 && (!issuedAt || issuedAt + 1000 < revokedAt)) {
      return c.json({ detail: 'Session expired. Please sign in again.', code: 'SESSION_REVOKED' }, 401);
    }
    const requestPath = new URL(c.req.url).pathname;
    const deletionAccessAllowed = requestPath === '/api/auth/me'
      || requestPath === '/api/account/restore'
      || requestPath === '/api/account/deletion-status';
    if (accountStatus === 'deletion_pending' && !deletionAccessAllowed) {
      return c.json({ detail: 'This account is pending deletion.', code: 'ACCOUNT_DELETION_PENDING' }, 403);
    }
    if (accountStatus === 'suspended') {
      const suspendedUntil = Date.parse(String(user?.suspended_until || ''));
      if (Number.isFinite(suspendedUntil) && suspendedUntil <= Date.now()) {
        await supabaseClearExpiredSuspension(c, userId).catch(() => {});
      } else {
        return c.json({ detail: 'This account is suspended.' }, 403);
      }
    } else if (accountStatus === 'banned' || accountStatus === 'deleted') {
      return c.json({ detail: 'This account cannot be used.' }, 403);
    }
    payload = canonicalSupabaseRequestPayload(payload, user);
    userId = String(payload?.sub || userId);
    c.set('jwtPayload', payload);
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
    if (!supabasePrimaryConfigured(c)) return '';
    const resolved = await resolveSupabaseSessionUser(c, token);
    const userId = resolved.userId;
    const user = resolved.user;

    const optionalStatus = String(user?.status || 'active');
    if (!user || optionalStatus === 'banned' || optionalStatus === 'deleted' || optionalStatus === 'deletion_pending') return '';
    if (optionalStatus === 'suspended') {
      const suspendedUntil = Date.parse(String(user?.suspended_until || ''));
      if (!Number.isFinite(suspendedUntil) || suspendedUntil > Date.now()) return '';
      await supabaseClearExpiredSuspension(c, userId).catch(() => {});
    }
    const canonicalPayload = canonicalSupabaseRequestPayload(resolved.payload, user);
    c.set('jwtPayload', canonicalPayload);
    return String(canonicalPayload?.sub || userId);
  } catch {
    return '';
  }
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
  const suffix = String(id || uuid()).replace(/[^a-z0-9]/gi, '').toLowerCase();
  return `pending_${suffix.slice(0, 12)}`;
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

async function ensureUniqueSupabaseUsername(c: any, desired: string, fallbackId: string): Promise<string> {
  const desiredSlug = strictUsernameSlug(desired);
  let base = (desiredSlug || usernameSlug(desired)).slice(0, 16).replace(/^\.+|\.+$/g, '');
  if (!validateUsernameForAccount(base, { allowGenerated: true }).ok || isReservedOrStaffUsername(base)) {
    return pendingUsernameForUser(fallbackId);
  }

  for (let attempt = 0; attempt < 100; attempt += 1) {
    const suffix = attempt === 0 ? '' : String(attempt).padStart(2, '0');
    const candidate = `${base.slice(0, Math.max(3, 20 - suffix.length))}${suffix}`;
    try {
      const rows = await supabaseAdminQueryRows(c, 'app_users', {
        select: 'id,username',
        filters: { username: postgrestEqFilter(candidate) },
        limit: 1,
      });
      if (!rows.length) return candidate;
    } catch (error: any) {
      console.warn(JSON.stringify({ event: 'supabase_username_lookup_failed', code: getErrorCode(error).slice(0, 180) }));
      break;
    }
  }

  return pendingUsernameForUser(fallbackId);
}

let phoneAuthSchemaReady = false;
let accountVerificationSchemaReady = false;
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
let peopleSchemaReady = false;
let reliabilitySchemaReady = false;
let walletSchemaReady = false;
let premiumSchemaReady = false;
let abuseProtectionSchemaReady = false;
let messagePresenceSchemaReady = false;
let productionReadinessSchemaReady = false;
let adminModerationSchemaReady = false;
let autoCategorySchemaReady = false;
let autoCategoryBackfillReady = false;
let locationSchemaReady = false;
let statusThoughtSchemaReady = false;
let statusLikeSchemaReady = false;
let mediaModerationSchemaReady = false;
let accountDeletionSchemaReady = false;
let groupChatSchemaReady = false;
let likeUniquenessSchemaReady = false;

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

async function ensureLikeUniquenessSchema(db: D1Database) {
  if (likeUniquenessSchemaReady) return;

  const statements = [
    `CREATE TABLE IF NOT EXISTS likes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      post_id TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`,
    `DELETE FROM likes
     WHERE id IN (
       SELECT id FROM (
         SELECT id,
                ROW_NUMBER() OVER (PARTITION BY user_id, post_id ORDER BY COALESCE(created_at, ''), id) AS rn
         FROM likes
       )
       WHERE rn > 1
     )`,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_likes_user_post_unique ON likes(user_id, post_id)',
    'ALTER TABLE posts ADD COLUMN likes_count INTEGER DEFAULT 0',
    `CREATE TABLE IF NOT EXISTS discover_likes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      post_id TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`,
    `DELETE FROM discover_likes
     WHERE id IN (
       SELECT id FROM (
         SELECT id,
                ROW_NUMBER() OVER (PARTITION BY user_id, post_id ORDER BY COALESCE(created_at, ''), id) AS rn
         FROM discover_likes
       )
       WHERE rn > 1
    )`,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_discover_likes_user_post_unique ON discover_likes(user_id, post_id)',
    `CREATE TABLE IF NOT EXISTS saved_posts (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      post_id TEXT NOT NULL,
      collection TEXT DEFAULT 'saved',
      created_at TEXT DEFAULT (datetime('now'))
    )`,
    `DELETE FROM saved_posts
     WHERE id IN (
       SELECT id FROM (
         SELECT id,
                ROW_NUMBER() OVER (PARTITION BY user_id, post_id ORDER BY COALESCE(created_at, ''), id) AS rn
         FROM saved_posts
       )
       WHERE rn > 1
     )`,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_saved_posts_user_post_unique ON saved_posts(user_id, post_id)',
    `INSERT OR IGNORE INTO likes (id, user_id, post_id, created_at)
     SELECT 'discover:' || user_id || ':' || post_id,
            user_id,
            post_id,
            COALESCE(created_at, datetime('now'))
     FROM discover_likes
     WHERE EXISTS (SELECT 1 FROM posts WHERE posts.id = discover_likes.post_id)`,
    `DELETE FROM likes
     WHERE id IN (
       SELECT id FROM (
         SELECT id,
                ROW_NUMBER() OVER (PARTITION BY user_id, post_id ORDER BY COALESCE(created_at, ''), id) AS rn
         FROM likes
       )
       WHERE rn > 1
     )`,
    `CREATE TABLE IF NOT EXISTS comment_likes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      comment_id TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`,
    `DELETE FROM comment_likes
     WHERE id IN (
       SELECT id FROM (
         SELECT id,
                ROW_NUMBER() OVER (PARTITION BY user_id, comment_id ORDER BY COALESCE(created_at, ''), id) AS rn
         FROM comment_likes
       )
       WHERE rn > 1
     )`,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_comment_likes_user_comment_unique ON comment_likes(user_id, comment_id)',
    'ALTER TABLE comments ADD COLUMN likes_count INTEGER DEFAULT 0',
    `CREATE TABLE IF NOT EXISTS status_likes (
      id TEXT PRIMARY KEY,
      status_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(status_id, user_id)
    )`,
    `DELETE FROM status_likes
     WHERE id IN (
       SELECT id FROM (
         SELECT id,
                ROW_NUMBER() OVER (PARTITION BY status_id, user_id ORDER BY COALESCE(created_at, ''), id) AS rn
         FROM status_likes
       )
       WHERE rn > 1
     )`,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_status_likes_status_user_unique ON status_likes(status_id, user_id)',
    `UPDATE posts
     SET likes_count = (
       SELECT COUNT(*)
       FROM likes
       WHERE likes.post_id = posts.id
     )`,
    `UPDATE comments
     SET likes_count = (
       SELECT COUNT(*)
       FROM comment_likes
       WHERE comment_likes.comment_id = comments.id
     )`,
    `UPDATE discover_posts
     SET likes_count = CASE
       WHEN EXISTS (SELECT 1 FROM posts WHERE posts.id = discover_posts.id) THEN (
         SELECT COUNT(*)
         FROM likes
         WHERE likes.post_id = discover_posts.id
       )
       ELSE (
         SELECT COUNT(*)
         FROM discover_likes
         WHERE discover_likes.post_id = discover_posts.id
       )
     END`,
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

  likeUniquenessSchemaReady = true;
}

async function reconcileLegacyDiscoverLikes(db: D1Database, postId: string) {
  await db.batch([
    db.prepare(
      `INSERT OR IGNORE INTO likes (id, user_id, post_id, created_at)
       SELECT 'discover:' || user_id || ':' || post_id,
              user_id,
              post_id,
              COALESCE(created_at, datetime('now'))
       FROM discover_likes
       WHERE post_id = ?
         AND EXISTS (SELECT 1 FROM posts WHERE posts.id = discover_likes.post_id)`
    ).bind(postId),
    db.prepare(
      `DELETE FROM likes
       WHERE post_id = ?
         AND id IN (
           SELECT id FROM (
             SELECT id,
                    ROW_NUMBER() OVER (PARTITION BY user_id, post_id ORDER BY COALESCE(created_at, ''), id) AS rn
             FROM likes
             WHERE post_id = ?
           )
           WHERE rn > 1
         )`
    ).bind(postId, postId),
  ]);
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

async function ensureGroupChatSchema(db: D1Database) {
  if (groupChatSchemaReady) return;

  const statements = [
    `CREATE TABLE IF NOT EXISTS group_chats (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      created_by TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY(created_by) REFERENCES users(id)
    )`,
    `CREATE TABLE IF NOT EXISTS group_chat_members (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      role TEXT DEFAULT 'member',
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(group_id, user_id),
      FOREIGN KEY(group_id) REFERENCES group_chats(id),
      FOREIGN KEY(user_id) REFERENCES users(id)
    )`,
    `CREATE TABLE IF NOT EXISTS group_messages (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      content TEXT NOT NULL,
      media_url TEXT,
      media_type TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY(group_id) REFERENCES group_chats(id),
      FOREIGN KEY(sender_id) REFERENCES users(id)
    )`,
    'CREATE INDEX IF NOT EXISTS idx_group_chat_members_user ON group_chat_members(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_group_chat_members_group ON group_chat_members(group_id)',
    'CREATE INDEX IF NOT EXISTS idx_group_messages_group ON group_messages(group_id, created_at)',
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

  groupChatSchemaReady = true;
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

function presenceKvKey(userId: string): string {
  return `presence:user:${safeRateLimitPart(userId)}`;
}

function typingKvKey(userId: string, peerId: string): string {
  return `presence:typing:${safeRateLimitPart(userId)}:${safeRateLimitPart(peerId)}`;
}

async function touchSupabasePrimaryPresence(c: any, userId: string): Promise<string> {
  const timestamp = now();
  if (!userId || !c.env.KV) return timestamp;
  await c.env.KV.put(presenceKvKey(userId), JSON.stringify({ last_seen_at: timestamp }), {
    expirationTtl: 4 * 60,
  }).catch((error: any) => {
    console.warn(JSON.stringify({
      event: 'kv_presence_touch_failed',
      request_id: c.get?.('requestId') || '',
      code: getErrorCode(error).slice(0, 160),
    }));
  });
  return timestamp;
}

async function readSupabasePrimaryPresence(c: any, userId: string): Promise<string | null> {
  if (!userId || !c.env.KV) return null;
  const cached: any = await c.env.KV.get(presenceKvKey(userId), 'json').catch(() => null);
  const lastSeenAt = cleanText(cached?.last_seen_at, 80);
  return lastSeenAt || null;
}

async function setSupabasePrimaryTyping(c: any, userId: string, peerId: string, isTyping: boolean): Promise<string> {
  const timestamp = now();
  if (!userId || !peerId || !c.env.KV) return timestamp;
  const key = typingKvKey(userId, peerId);
  if (isTyping) {
    await c.env.KV.put(key, JSON.stringify({ is_typing: true, updated_at: timestamp }), {
      expirationTtl: 15,
    }).catch((error: any) => {
      console.warn(JSON.stringify({
        event: 'kv_typing_write_failed',
        request_id: c.get?.('requestId') || '',
        code: getErrorCode(error).slice(0, 160),
      }));
    });
  } else {
    await c.env.KV.delete(key).catch((error: any) => {
      console.warn(JSON.stringify({
        event: 'kv_typing_delete_failed',
        request_id: c.get?.('requestId') || '',
        code: getErrorCode(error).slice(0, 160),
      }));
    });
  }
  return timestamp;
}

async function readSupabasePrimaryTyping(c: any, userId: string, peerId: string): Promise<boolean> {
  if (!userId || !peerId || !c.env.KV) return false;
  const cached: any = await c.env.KV.get(typingKvKey(userId, peerId), 'json').catch(() => null);
  return cached?.is_typing === true;
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

async function ensureStatusThoughtSchema(db: D1Database) {
  if (statusThoughtSchemaReady) return;
  await ensurePrivacySchema(db);
  await ensureAbuseProtectionSchema(db);

  const statements = [
    `CREATE TABLE IF NOT EXISTS status_thoughts (
      id TEXT PRIMARY KEY,
      status_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      body TEXT NOT NULL,
      status TEXT DEFAULT 'active',
      created_at TEXT NOT NULL,
      removed_at TEXT
    )`,
    'CREATE INDEX IF NOT EXISTS idx_status_thoughts_status_created ON status_thoughts(status_id, status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_status_thoughts_user_created ON status_thoughts(user_id, created_at)',
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

  statusThoughtSchemaReady = true;
}

async function ensureStatusLikeSchema(db: D1Database) {
  if (statusLikeSchemaReady) return;
  await ensurePrivacySchema(db);

  const statements = [
    `CREATE TABLE IF NOT EXISTS status_likes (
      id TEXT PRIMARY KEY,
      status_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(status_id, user_id)
    )`,
    'CREATE INDEX IF NOT EXISTS idx_status_likes_status ON status_likes(status_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_status_likes_user ON status_likes(user_id, created_at)',
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

  statusLikeSchemaReady = true;
}

async function ensurePostEditorSchema(db: D1Database) {
  if (postEditorSchemaReady) return;

  const statements = [
    "ALTER TABLE posts ADD COLUMN title TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN editor_overlays TEXT DEFAULT '[]'",
    "ALTER TABLE posts ADD COLUMN tagged_users TEXT DEFAULT '[]'",
    "ALTER TABLE posts ADD COLUMN media_dimensions TEXT DEFAULT '[]'",
    'ALTER TABLE posts ADD COLUMN saves_count INTEGER DEFAULT 0',
    'ALTER TABLE posts ADD COLUMN shares_count INTEGER DEFAULT 0',
    'ALTER TABLE posts ADD COLUMN views_count INTEGER DEFAULT 0',
    'CREATE INDEX IF NOT EXISTS idx_posts_type_created ON posts(post_type, created_at DESC)',
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
    "ALTER TABLE posts ADD COLUMN primary_category TEXT DEFAULT ''",
    'ALTER TABLE posts ADD COLUMN category_confidence REAL DEFAULT 0',
    "ALTER TABLE posts ADD COLUMN category_source TEXT DEFAULT 'fallback'",
    "ALTER TABLE posts ADD COLUMN category_status TEXT DEFAULT 'low_confidence'",
    "ALTER TABLE posts ADD COLUMN category_signals_json TEXT DEFAULT '{}'",
    "ALTER TABLE posts ADD COLUMN tags_json TEXT DEFAULT '[]'",
    "ALTER TABLE posts ADD COLUMN secondary_categories_json TEXT DEFAULT '[]'",
    "ALTER TABLE posts ADD COLUMN category_scores_json TEXT DEFAULT '{}'",
    "ALTER TABLE posts ADD COLUMN detected_objects_json TEXT DEFAULT '[]'",
    "ALTER TABLE posts ADD COLUMN detected_scene TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN place_type TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN user_selected_category TEXT DEFAULT ''",
    "ALTER TABLE posts ADD COLUMN caption_keywords_json TEXT DEFAULT '[]'",
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
  await backfillDiscoverCategories(db);
}

async function backfillDiscoverCategories(db: D1Database) {
  if (autoCategoryBackfillReady) return;
  const searchableSql = [
    "COALESCE(title, '')",
    "COALESCE(content, '')",
    "COALESCE(location, '')",
    "COALESCE(category, '')",
    "COALESCE(post_type, '')",
    "COALESCE(tags_json, '')",
    "COALESCE(category_signals_json, '')",
  ].join(" || ' ' || ");
  for (const category of DISCOVER_CATEGORIES) {
    const keywords = CATEGORY_KEYWORDS[category].slice(0, 28);
    const keywordMatches = keywords.map(() => `LOWER(${searchableSql}) LIKE ?`).join(' OR ');
    try {
      await db.prepare(`
        UPDATE posts
        SET primary_category = ?,
            category_confidence = MAX(COALESCE(category_confidence, 0), 0.56),
            secondary_categories_json = CASE
              WHEN COALESCE(secondary_categories_json, '') IN ('', '[]') THEN ?
              ELSE secondary_categories_json
            END,
            category_scores_json = CASE
              WHEN COALESCE(category_scores_json, '') IN ('', '{}') THEN ?
              ELSE category_scores_json
            END,
            category_source = CASE
              WHEN COALESCE(category_source, '') IN ('', 'fallback') THEN 'fallback'
              ELSE category_source
            END,
            category_status = CASE
              WHEN COALESCE(category_status, '') IN ('', 'pending') THEN 'low_confidence'
              ELSE category_status
            END
        WHERE (
          COALESCE(primary_category, '') IN ('', 'lifestyle', 'general', 'place')
          OR COALESCE(category_confidence, 0) < 0.50
        )
        AND (${keywordMatches})
      `).bind(category, JSON.stringify([category]), JSON.stringify({ [category]: 62 }), ...keywords.map((keyword) => `%${keyword}%`)).run();
    } catch (error) {
      console.warn('Discover category backfill skipped:', category, getErrorCode(error));
      break;
    }
  }
  autoCategoryBackfillReady = true;
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

async function ensureAccountDeletionSchema(db: D1Database) {
  if (accountDeletionSchemaReady) return;
  await ensureGovernanceSchema(db);
  await ensureProductionReadinessSchema(db);

  const statements = [
    "ALTER TABLE users ADD COLUMN deletion_requested_at TEXT",
    "ALTER TABLE users ADD COLUMN deletion_scheduled_at TEXT",
    "ALTER TABLE users ADD COLUMN deleted_at TEXT",
    "ALTER TABLE users ADD COLUMN session_revoked_at TEXT",
    `CREATE TABLE IF NOT EXISTS account_identities (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      provider TEXT NOT NULL,
      provider_user_id TEXT NOT NULL,
      email_hash TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(provider, provider_user_id)
    )`,
    `CREATE TABLE IF NOT EXISTS account_deletion_events (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      event_type TEXT NOT NULL,
      actor_user_id TEXT DEFAULT '',
      reason TEXT DEFAULT '',
      metadata TEXT DEFAULT '{}',
      request_id TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS deleted_account_safety_records (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      email_hash TEXT DEFAULT '',
      provider TEXT DEFAULT '',
      provider_user_id_hash TEXT DEFAULT '',
      status_at_deletion TEXT DEFAULT '',
      reason TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )`,
    'CREATE INDEX IF NOT EXISTS idx_users_deletion_pending ON users(status, deletion_scheduled_at)',
    'CREATE INDEX IF NOT EXISTS idx_account_identities_user ON account_identities(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_account_identities_email_hash ON account_identities(email_hash)',
    'CREATE INDEX IF NOT EXISTS idx_account_deletion_events_user ON account_deletion_events(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_deleted_account_safety_email ON deleted_account_safety_records(email_hash)',
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

  accountDeletionSchemaReady = true;
}

async function ensureMediaModerationSchema(db: D1Database) {
  if (mediaModerationSchemaReady) return;

  const statements = [
    "ALTER TABLE posts ADD COLUMN moderation_status TEXT DEFAULT 'approved'",
    "ALTER TABLE posts ADD COLUMN moderation_media_ids TEXT DEFAULT '[]'",
    'ALTER TABLE posts ADD COLUMN moderation_checked_at TEXT',
    `CREATE TABLE IF NOT EXISTS media_assets (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      post_id TEXT,
      media_type TEXT NOT NULL,
      storage_provider TEXT NOT NULL,
      storage_key TEXT NOT NULL,
      public_url TEXT,
      private_url TEXT,
      mime_type TEXT NOT NULL,
      file_size INTEGER DEFAULT 0,
      sha256_hash TEXT DEFAULT '',
      width INTEGER,
      height INTEGER,
      duration_seconds REAL,
      upload_status TEXT NOT NULL DEFAULT 'uploading',
      moderation_status TEXT NOT NULL DEFAULT 'uploading',
      rejection_code TEXT,
      rejection_message TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS moderation_jobs (
      id TEXT PRIMARY KEY,
      media_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      job_type TEXT NOT NULL DEFAULT 'media_pre_publish',
      status TEXT NOT NULL DEFAULT 'pending',
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT DEFAULT '',
      queued_at TEXT NOT NULL,
      started_at TEXT,
      completed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS moderation_results (
      id TEXT PRIMARY KEY,
      media_id TEXT NOT NULL,
      model_name TEXT NOT NULL,
      adult_explicit_score REAL DEFAULT 0,
      nudity_score REAL DEFAULT 0,
      sexual_context_score REAL DEFAULT 0,
      sexual_solicitation_score REAL DEFAULT 0,
      minor_safety_risk_score REAL DEFAULT 0,
      violence_score REAL DEFAULT 0,
      gore_score REAL DEFAULT 0,
      weapon_score REAL DEFAULT 0,
      hate_symbol_score REAL DEFAULT 0,
      ai_generated_likelihood REAL DEFAULT 0,
      spam_scam_score REAL DEFAULT 0,
      malware_status TEXT NOT NULL DEFAULT 'unknown',
      link_risk_score REAL DEFAULT 0,
      confidence REAL DEFAULT 0,
      decision TEXT NOT NULL,
      reasons TEXT NOT NULL DEFAULT '[]',
      raw_result TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS moderation_events (
      id TEXT PRIMARY KEY,
      media_id TEXT NOT NULL,
      actor_user_id TEXT DEFAULT '',
      actor_role TEXT DEFAULT '',
      event_type TEXT NOT NULL,
      decision TEXT DEFAULT '',
      reason TEXT DEFAULT '',
      note TEXT DEFAULT '',
      before_state TEXT DEFAULT '{}',
      after_state TEXT DEFAULT '{}',
      request_id TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )`,
    'CREATE INDEX IF NOT EXISTS idx_media_assets_user_created ON media_assets(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_media_assets_status_created ON media_assets(moderation_status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_media_assets_post ON media_assets(post_id)',
    'CREATE INDEX IF NOT EXISTS idx_media_assets_storage ON media_assets(storage_provider, storage_key)',
    'CREATE INDEX IF NOT EXISTS idx_media_assets_hash ON media_assets(sha256_hash)',
    'CREATE INDEX IF NOT EXISTS idx_media_assets_post_status ON media_assets(post_id, moderation_status)',
    'CREATE INDEX IF NOT EXISTS idx_posts_moderation_status_created ON posts(moderation_status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_moderation_jobs_status ON moderation_jobs(status, queued_at)',
    'CREATE INDEX IF NOT EXISTS idx_moderation_jobs_media ON moderation_jobs(media_id)',
    'CREATE INDEX IF NOT EXISTS idx_moderation_results_media_created ON moderation_results(media_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_moderation_events_media_created ON moderation_events(media_id, created_at)',
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

  mediaModerationSchemaReady = true;
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
  return `COALESCE(${alias}.status, 'active') = 'active' AND (${alias}.id = ? OR COALESCE(${alias}.is_private, 0) = 0 OR EXISTS (SELECT 1 FROM friendships f WHERE f.user_id = ? AND f.friend_id = ${alias}.id))
    AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = ${alias}.id) OR (b.blocker_id = ${alias}.id AND b.blocked_id = ?))`;
}

function visibleStatusWhere(userAlias = 'u', statusAlias = 's'): string {
  return `COALESCE(${userAlias}.status, 'active') = 'active' AND (${statusAlias}.user_id = ? OR (COALESCE(${statusAlias}.visibility, 'public') = 'public' AND COALESCE(${userAlias}.is_private, 0) = 0) OR EXISTS (SELECT 1 FROM friendships f WHERE f.user_id = ? AND f.friend_id = ${statusAlias}.user_id))`;
}

function visiblePostWhere(userAlias = 'u', postAlias = 'p'): string {
  return `COALESCE(${postAlias}.status, 'active') != 'removed' AND ${approvedPostModerationWhere(postAlias)} AND ${visibleAuthorWhere(userAlias)} AND (
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
  return `COALESCE(${postAlias}.status, 'active') != 'removed' AND ${approvedPostModerationWhere(postAlias)} AND COALESCE(${userAlias}.status, 'active') = 'active' AND COALESCE(${userAlias}.is_private, 0) = 0 AND COALESCE(${postAlias}.visibility, 'public') = 'public'`;
}

function approvedPostModerationWhere(postAlias = 'p'): string {
  return `COALESCE(${postAlias}.moderation_status, 'approved') = 'approved'`;
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

function cloudflareAccountId(env: Env): string {
  return cleanText(env.CLOUDFLARE_ACCOUNT_ID || env.CF_ACCOUNT_ID || '', 140);
}

function cloudflareImagesToken(env: Env): string {
  return cleanText(env.CLOUDFLARE_IMAGES_TOKEN || env.CLOUDFLARE_API_TOKEN || env.CF_API_TOKEN || '', 4096);
}

function cloudflareStreamToken(env: Env): string {
  return cleanText(env.CLOUDFLARE_STREAM_TOKEN || env.CLOUDFLARE_API_TOKEN || env.CF_API_TOKEN || '', 4096);
}

function cloudflareImagesAccountHash(env: Env): string {
  return cleanText(env.CLOUDFLARE_IMAGES_ACCOUNT_HASH || env.CF_ACCOUNT_HASH || '', 160);
}

function cloudflareImageDeliveryUrl(env: Env, imageId: string, variant = 'public'): string {
  const accountHash = cloudflareImagesAccountHash(env);
  const cleanImageId = cleanText(imageId, 180);
  const cleanVariant = cleanText(variant || 'public', 120) || 'public';
  return accountHash && cleanImageId
    ? `https://imagedelivery.net/${accountHash}/${cleanImageId}/${cleanVariant}`
    : '';
}

function cloudflareImagesRequireSignedUrls(env: Env): boolean {
  const value = cleanText(env.CLOUDFLARE_IMAGES_REQUIRE_SIGNED_URLS || '', 20).toLowerCase();
  return value === '1' || value === 'true' || value === 'yes';
}

function cloudflareStreamRequireSignedUrls(env: Env): boolean {
  const value = cleanText(env.CLOUDFLARE_STREAM_REQUIRE_SIGNED_URLS || '', 20).toLowerCase();
  return value === '1' || value === 'true' || value === 'yes';
}

function publicApiBaseUrl(env?: Env): string {
  const configured = cleanText(env?.PUBLIC_API_BASE_URL || '', 300).replace(/\/+$/, '');
  if (configured && /^https:\/\//i.test(configured)) return configured;
  return 'https://api.flames-up.com/api';
}

function cloudflareImageIdFromDeliveryUrl(env: Env | undefined, value: string): string {
  try {
    const parsed = new URL(value);
    if (!hostMatches(parsed.hostname, 'imagedelivery.net')) return '';
    const segments = parsed.pathname.split('/').filter(Boolean);
    if (segments.length < 3) return '';
    const accountHash = env ? cloudflareImagesAccountHash(env) : '';
    if (accountHash && segments[0] !== accountHash) return '';
    return cleanText(segments[1], 220);
  } catch {
    return '';
  }
}

function cloudflareImageProxyUrl(env: Env | undefined, imageId: string): string {
  const cleanImageId = cleanText(imageId, 220);
  return cleanImageId ? `${publicApiBaseUrl(env)}/media/cf-image/${encodeURIComponent(cleanImageId)}` : '';
}

function cloudflareImageProxyFallbackUrl(env: Env | undefined, value: string): string {
  const imageId = cloudflareImageIdFromDeliveryUrl(env, value);
  return imageId ? cloudflareImageProxyUrl(env, imageId) : '';
}

function cloudflareImageVariantUrl(env: Env, imageId: string, variants?: unknown, variant = 'public'): string {
  const urls = parseJsonArray(variants)
    .map((value) => safeMediaReference(value))
    .filter(Boolean);
  const preferred = urls.find((url) => url.endsWith(`/${variant}`)) || urls[0] || '';
  return preferred || cloudflareImageDeliveryUrl(env, imageId, variant);
}

function cloudflareImageTransformsEnabled(env?: Env): boolean {
  const value = cleanText(env?.CLOUDFLARE_IMAGE_TRANSFORMS_ENABLED || '', 20).toLowerCase();
  if (value === '0' || value === 'false' || value === 'no') return false;
  return true;
}

function cloudflareImageTransformBaseUrl(env?: Env): string {
  const configured = cleanText(env?.CLOUDFLARE_IMAGE_TRANSFORM_BASE_URL || '', 300).replace(/\/+$/, '');
  if (configured && /^https:\/\//i.test(configured)) return configured;
  return cloudflareImageTransformsEnabled(env) ? 'https://api.flames-up.com' : '';
}

function cloudflareImageTransformOptions(preset: 'feed' | 'thumbnail'): string {
  const metadata = 'metadata=copyright';
  if (preset === 'thumbnail') {
    return `width=480,quality=84,format=auto,${metadata}`;
  }
  return `width=1080,quality=92,format=auto,${metadata}`;
}

function canProxyThroughCloudflareImageTransform(url: URL): boolean {
  const host = url.hostname.toLowerCase();
  if (hostMatches(host, 'imagedelivery.net')) return false;
  if (hostMatches(host, 'videodelivery.net')) return false;
  return hostMatches(host, 'flames-up.com')
    || hostMatches(host, 'captro.app')
    || hostMatches(host, 'r2.dev')
    || hostMatches(host, 'workers.dev');
}

function cloudflareTransformedImageUrl(env: Env | undefined, url: string, preset: 'feed' | 'thumbnail'): string {
  if (!url || !cloudflareImageTransformsEnabled(env)) return url;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:') return url;
    if (parsed.pathname.includes('/cdn-cgi/image/')) return url;
    if (!canProxyThroughCloudflareImageTransform(parsed)) return url;
    const base = cloudflareImageTransformBaseUrl(env);
    if (!base) return url;
    return `${base}/cdn-cgi/image/${cloudflareImageTransformOptions(preset)}/${parsed.toString()}`;
  } catch {
    return url;
  }
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
  | 'events'
  | 'nightlife'
  | 'art';

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
  placeType?: string | null;
  userSelectedCategory?: string;
  detectedObjects?: string[];
  detectedScene?: string;
  captionKeywords?: string[];
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
  secondary_categories: DiscoverCategory[];
  category_scores: Record<DiscoverCategory, number>;
  detected_objects: string[];
  detected_scene: string;
  place_type: string;
  user_selected_category: DiscoverCategory | '';
  caption_keywords: string[];
};

const DISCOVER_CATEGORIES: DiscoverCategory[] = [
  'photography',
  'outdoors',
  'art',
  'nightlife',
  'outfits',
  'events',
];
const DEFAULT_DISCOVER_CATEGORY: DiscoverCategory = 'photography';

const CATEGORY_KEYWORDS: Record<DiscoverCategory, string[]> = {
  outfits: ['outfit', 'fit', 'fit check', 'clothes', 'style', 'fashion', 'streetwear', 'shoes', 'shoe', 'jacket', 'mirror selfie', 'clothing', 'accessories', 'sneakers', 'dress', 'apparel', 'person', 'full body pose'],
  events: ['event', 'events', 'concert', 'festival', 'meetup', 'show', 'game', 'crowd', 'stadium', 'venue', 'performance', 'birthday', 'wedding', 'audience', 'stage', 'party', 'celebration', 'ceremony', 'conference', 'ticket'],
  outdoors: ['outdoors', 'outdoor', 'outside', 'park', 'beach', 'hiking', 'trail', 'nature', 'mountain', 'lake', 'sunset', 'sunrise', 'trees', 'tree', 'forest', 'walking', 'landscape', 'snow', 'sky', 'water', 'river', 'ocean', 'sea', 'flower', 'plant', 'grass', 'garden', 'field', 'woods', 'camping'],
  nightlife: ['nightlife', 'night', 'club', 'bar', 'lounge', 'party', 'rooftop', 'dj', 'drinks', 'city night', 'after dark', 'dance', 'neon', 'dark', 'cocktail', 'evening'],
  photography: ['photography', 'portrait', 'camera', 'photo shoot', 'street photo', 'aesthetic', 'landscape shot', 'creative shot', 'close up', 'close-up', 'lens', 'film', 'macro', 'black and white', 'monochrome', 'composition'],
  art: ['art', 'drawing', 'painting', 'design', 'sketch', 'illustration', 'mural', 'gallery', 'creative work', 'museum', 'artist', 'craft', 'sculpture', 'visual art'],
};

function normalizeDiscoverCategory(value: unknown, allowAll = false): DiscoverCategory | 'all' | '' {
  const clean = cleanText(value, 40).toLowerCase().replace(/[éèê]/g, 'e').replace(/[\s-]+/g, '_');
  if (allowAll && clean === 'all') return 'all';
  const aliases: Record<string, DiscoverCategory> = {
    outfit: 'outfits',
    outdoor: 'outdoors',
    event: 'events',
    events: 'events',
  };
  const normalized = aliases[clean] || clean;
  return DISCOVER_CATEGORIES.includes(normalized as DiscoverCategory) ? normalized as DiscoverCategory : '';
}

function discoverCategorySearchTerms(category: DiscoverCategory): string[] {
  const aliases: Partial<Record<DiscoverCategory, string[]>> = {
    outfits: ['outfit', 'fit check', 'fashion', 'style', 'clothing'],
    outdoors: ['outdoor', 'outside', 'nature', 'park', 'beach', 'trail'],
    photography: ['photo', 'camera', 'portrait', 'street photo', 'landscape'],
    events: ['event', 'concert', 'festival', 'venue', 'stadium', 'performance'],
    nightlife: ['night life', 'club', 'bar', 'party', 'neon'],
  };
  const seen = new Set<string>();
  return [category, ...(CATEGORY_KEYWORDS[category] || []), ...(aliases[category] || [])]
    .map((term) => cleanText(term, 80).toLowerCase().trim())
    .filter((term) => term.length >= 3 && !seen.has(term) && seen.add(term))
    .slice(0, 28);
}

function discoverCategoryCondition(postAlias: string, category: DiscoverCategory, scoreThreshold = 24): { sql: string; binds: any[] } {
  const alias = postAlias.replace(/[^a-zA-Z0-9_]/g, '') || 'p';
  const terms = discoverCategorySearchTerms(category);
  const textExpression = `LOWER(
    COALESCE(${alias}.tags_json, '') || ' ' ||
    COALESCE(${alias}.caption_keywords_json, '') || ' ' ||
    COALESCE(${alias}.detected_objects_json, '') || ' ' ||
    COALESCE(${alias}.category_signals_json, '') || ' ' ||
    COALESCE(${alias}.content, '') || ' ' ||
    COALESCE(${alias}.title, '') || ' ' ||
    COALESCE(${alias}.location, '') || ' ' ||
    COALESCE(${alias}.display_location_label, '') || ' ' ||
    COALESCE(${alias}.place_name, '') || ' ' ||
    COALESCE(${alias}.place_category, '') || ' ' ||
    COALESCE(${alias}.place_type, '') || ' ' ||
    COALESCE(${alias}.detected_scene, '')
  )`;
  const keywordSql = terms.map(() => `${textExpression} LIKE ?`).join(' OR ');
  return {
    sql: `(
      COALESCE(json_extract(${alias}.category_scores_json, '$.${category}'), 0) >= ?
      OR (
        LOWER(COALESCE(NULLIF(${alias}.primary_category, ''), NULLIF(${alias}.category, ''), '')) = ?
        AND COALESCE(${alias}.category_confidence, 0) >= 0.50
      )
      OR LOWER(COALESCE(${alias}.user_selected_category, '')) = ?
      OR COALESCE(${alias}.secondary_categories_json, '') LIKE ?
      OR ${keywordSql}
    )`,
    binds: [
      scoreThreshold,
      category,
      category,
      `%"${category}"%`,
      ...terms.map((term) => `%${term}%`),
    ],
  };
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

function scoreCategoryFromText(
  scores: Record<DiscoverCategory, number>,
  text: string,
  weight: number,
  reasons?: Record<DiscoverCategory, string[]>,
  reasonPrefix = 'keyword'
) {
  if (!text) return;
  for (const category of DISCOVER_CATEGORIES) {
    for (const keyword of CATEGORY_KEYWORDS[category]) {
      if (categoryTextMatches(text, keyword)) {
        scores[category] += weight;
        reasons?.[category]?.push(`${reasonPrefix}: ${keyword}`);
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

function emptyCategoryScores(): Record<DiscoverCategory, number> {
  return Object.fromEntries(DISCOVER_CATEGORIES.map((category) => [category, 0])) as Record<DiscoverCategory, number>;
}

function emptyCategoryReasons(): Record<DiscoverCategory, string[]> {
  return Object.fromEntries(DISCOVER_CATEGORIES.map((category) => [category, [] as string[]])) as unknown as Record<DiscoverCategory, string[]>;
}

function addCategoryScore(
  scores: Record<DiscoverCategory, number>,
  reasons: Record<DiscoverCategory, string[]>,
  category: DiscoverCategory | '',
  amount: number,
  reason: string
) {
  if (!category || amount <= 0) return;
  scores[category] += amount;
  if (reason) reasons[category].push(reason);
}

function topCaptionKeywords(text: string, hashtags: string[]): string[] {
  const words = cleanMultilineText(text, 1200)
    .toLowerCase()
    .replace(/#[a-z0-9_.-]+/g, ' ')
    .split(/[^a-z0-9_.]+/g)
    .filter((word) => word.length >= 3 && !['the', 'and', 'for', 'with', 'this', 'that', 'from', 'today', 'about'].includes(word));
  return sanitizeAutoCategoryTags([...hashtags, ...words]).slice(0, 20);
}

function normalizePlaceType(input: AutoCategoryInput): string {
  return [
    input.placeType,
    input.placeName,
    input.location,
    input.postType,
  ].map((item) => cleanText(item, 180).toLowerCase()).filter(Boolean).join(' ');
}

function boostFromPlaceType(
  scores: Record<DiscoverCategory, number>,
  reasons: Record<DiscoverCategory, string[]>,
  placeType: string
) {
  if (!placeType) return;
  const mappings: Array<{ category: DiscoverCategory; keywords: string[]; weight: number }> = [
    { category: 'outdoors', keywords: ['park', 'beach', 'trail', 'hiking', 'lake', 'mountain', 'garden'], weight: 58 },
    { category: 'nightlife', keywords: ['bar', 'club', 'lounge', 'nightclub', 'rooftop'], weight: 58 },
    { category: 'events', keywords: ['event', 'concert', 'festival', 'meetup', 'show', 'game', 'crowd', 'stadium', 'venue', 'performance', 'birthday', 'wedding', 'stage'], weight: 58 },
    { category: 'art', keywords: ['gallery', 'museum', 'art', 'mural', 'studio'], weight: 52 },
  ];
  for (const mapping of mappings) {
    if (mapping.keywords.some((keyword) => categoryTextMatches(placeType, keyword))) {
      addCategoryScore(scores, reasons, mapping.category, mapping.weight, `place type: ${placeType.slice(0, 80)}`);
    }
  }
}

function boostFromDetectedObjects(
  scores: Record<DiscoverCategory, number>,
  reasons: Record<DiscoverCategory, string[]>,
  labels: string[],
  scene: string
) {
  const text = [...labels, scene].join(' ').toLowerCase();
  if (!text.trim()) return;
  scoreCategoryFromText(scores, text, 12, reasons, 'detected');

  const hasPerson = /\b(person|people|human|man|woman|face|portrait|full body)\b/.test(text);
  const hasClothing = /\b(clothing|clothes|shirt|pants|dress|shoes|sneaker|jacket|hat|fashion|accessory|outfit)\b/.test(text);
  if (hasPerson && hasClothing) {
    addCategoryScore(scores, reasons, 'outfits', 34, 'person + clothing/full-body signal');
  }

  if (/\b(tree|trees|sky|park|beach|trail|mountain|forest|lake|river|ocean|grass|flower|sunset)\b/.test(text)) {
    addCategoryScore(scores, reasons, 'outdoors', 28, 'nature/outdoor objects');
  }
  if (/\b(camera|lens|portrait|monochrome|macro|composition)\b/.test(text)) {
    addCategoryScore(scores, reasons, 'photography', 24, 'photo/camera composition objects');
  }
}

function autoCategoryEngine(input: AutoCategoryInput): AutoCategoryResult {
  const scores = emptyCategoryScores();
  const reasons = emptyCategoryReasons();
  const tags = new Set<string>();
  const caption = cleanMultilineText(input.caption || '', 5000).toLowerCase();
  const hashtags = sanitizeAutoCategoryTags([...(input.hashtags || []), ...collectHashtagsFromText(caption)]);
  const captionKeywords = topCaptionKeywords(caption, hashtags);
  const placeType = normalizePlaceType(input);
  const detectedObjects = sanitizeAutoCategoryTags(input.detectedObjects || []);
  const detectedScene = cleanText(input.detectedScene, 80).toLowerCase();
  const userSelectedCategory = normalizeDiscoverCategory(input.userSelectedCategory, false) as DiscoverCategory | '';
  const placeText = [input.location, input.placeName, input.placeType, input.postType].map((item) => cleanText(item, 160).toLowerCase()).filter(Boolean).join(' ');
  const appleGuess = normalizeDiscoverCategory(input.appleCategoryGuess, false) as DiscoverCategory | '';
  const backendGuess = normalizeDiscoverCategory(input.backendCategoryGuess, false) as DiscoverCategory | '';
  const appleConfidence = clampFloat(input.appleConfidence, 0, 1, 0);
  const backendConfidence = clampFloat(input.backendConfidence, 0, 1, 0);
  const appleLabels = sanitizeAutoCategoryLabels(input.appleLabels || []);
  const backendLabels = sanitizeAutoCategoryLabels(input.backendLabels || []);

  if (userSelectedCategory) addCategoryScore(scores, reasons, userSelectedCategory, 64, 'user selected category');
  if (backendGuess) addCategoryScore(scores, reasons, backendGuess, 45 * Math.max(backendConfidence, 0.55), 'backend AI category');
  if (appleGuess) addCategoryScore(scores, reasons, appleGuess, 30 * Math.max(appleConfidence, 0.55), 'Apple Vision category');
  scoreCategoryFromText(scores, caption, 18, reasons, 'caption');
  scoreCategoryFromText(scores, hashtags.join(' '), 28, reasons, 'hashtag');
  scoreCategoryFromText(scores, placeText, 18, reasons, 'place text');
  boostFromPlaceType(scores, reasons, placeType);

  for (const { category, confidence } of [categoryFromLabels(appleLabels), categoryFromLabels(backendLabels)]) {
    if (category) addCategoryScore(scores, reasons, category, Math.round(confidence * 30), 'vision/object labels');
  }
  boostFromDetectedObjects(
    scores,
    reasons,
    [
      ...detectedObjects,
      ...appleLabels.map((item) => item.label),
      ...backendLabels.map((item) => item.label),
    ],
    detectedScene
  );

  for (const tag of hashtags) tags.add(tag);
  for (const keyword of captionKeywords) tags.add(keyword);
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
  const winnerScore = winner?.score || 0;
  const hasCategorySignal = winnerScore >= 24;
  const rawConfidence = hasCategorySignal ? Math.min(0.99, Math.max(0, winnerScore / 85)) : 0;
  const confidence = Number(rawConfidence.toFixed(2));
  const isLow = !hasCategorySignal || confidence < 0.50;
  const primaryCategory = hasCategorySignal ? winner.category : DEFAULT_DISCOVER_CATEGORY;
  const normalizedScores = Object.fromEntries(
    DISCOVER_CATEGORIES.map((category) => [category, Number(Math.max(0, scores[category]).toFixed(1))])
  ) as Record<DiscoverCategory, number>;
  const secondaryCategories = DISCOVER_CATEGORIES
    .filter((category) => normalizedScores[category] >= 36 || category === primaryCategory)
    .sort((a, b) => normalizedScores[b] - normalizedScores[a])
    .slice(0, 5);
  const source: AutoCategorySource = backendGuess || backendLabels.length
    ? (appleGuess || appleLabels.length ? 'hybrid_ai' : 'backend_ai')
    : appleGuess || appleLabels.length
      ? 'apple_vision'
      : 'fallback';
  const status: AutoCategoryStatus = isLow ? 'low_confidence' : 'classified';

  return {
    primary_category: primaryCategory,
    category_confidence: hasCategorySignal ? Math.max(confidence, 0.35) : 0.35,
    category_source: hasCategorySignal ? source : 'fallback',
    category_status: status,
    tags: Array.from(tags).slice(0, 16),
    secondary_categories: secondaryCategories,
    category_scores: normalizedScores,
    detected_objects: Array.from(new Set([...detectedObjects, ...appleLabels.map((item) => item.label), ...backendLabels.map((item) => item.label)]))
      .map((item) => cleanText(item, 60).toLowerCase())
      .filter(Boolean)
      .slice(0, 24),
    detected_scene: detectedScene || primaryCategory,
    place_type: placeType.slice(0, 120),
    user_selected_category: userSelectedCategory,
    caption_keywords: captionKeywords,
    signals: {
      apple_category_guess: appleGuess || '',
      apple_confidence: appleConfidence || 0,
      apple_labels: appleLabels,
      backend_category_guess: backendGuess || '',
      backend_confidence: backendConfidence || 0,
      backend_labels: backendLabels,
      caption_hashtags: hashtags,
      caption_keywords: captionKeywords,
      detected_objects: detectedObjects,
      detected_scene: detectedScene,
      place_type: placeType,
      user_selected_category: userSelectedCategory,
      secondary_categories: secondaryCategories,
      category_scores: normalizedScores,
      scores: normalizedScores,
      debug_reasons: reasons,
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
    userSelectedCategory: body.primary_category || body.primaryCategory || body.discover_category || body.discoverCategory || body.user_selected_category || body.userSelectedCategory,
    detectedObjects: sanitizeAutoCategoryTags(body.detected_objects || body.detectedObjects),
    detectedScene: cleanText(body.detected_scene || body.detectedScene, 80),
    placeType: cleanText(body.google_place_type || body.googlePlaceType || body.place_type || body.placeType || body.place_category || body.placeCategory, 120),
    captionKeywords: sanitizeAutoCategoryTags(body.caption_keywords || body.captionKeywords),
  });
}

type PostAssistResult = {
  source: 'workers_ai' | 'fallback';
  ai_available: boolean;
  primary_category: DiscoverCategory;
  category_confidence: number;
  category_status: AutoCategoryStatus;
  headline_suggestions: string[];
  caption_suggestions: string[];
  tags: string[];
};

function postAssistModel(env: Env): string {
  return cleanText(env.POST_ASSIST_MODEL || '@cf/meta/llama-3.1-8b-instruct-fast', 120);
}

function cleanSuggestionList(value: unknown, maxItems: number, maxLength: number): string[] {
  const raw = Array.isArray(value) ? value : parseJsonArray(value);
  const seen = new Set<string>();
  return raw
    .map((item) => cleanMultilineText(item, maxLength).replace(/\s+/g, ' ').trim())
    .filter((item) => item.length >= 3 && !seen.has(item.toLowerCase()) && seen.add(item.toLowerCase()))
    .slice(0, maxItems);
}

function fallbackPostAssist(input: AutoCategoryInput, category: AutoCategoryResult): PostAssistResult {
  const place = cleanText(input.placeName || input.location || '', 80);
  const categoryLabel = category.primary_category.replace(/_/g, ' ');
  const captionSeed = cleanMultilineText(input.caption || '', 180).replace(/\s+/g, ' ').trim();
  const placeSuffix = place ? ` in ${place}` : '';
  const headlineSuggestions = cleanSuggestionList([
    captionSeed ? captionSeed.split(/[.!?\n]/)[0] : '',
    `${categoryLabel.charAt(0).toUpperCase()}${categoryLabel.slice(1)} moment${placeSuffix}`,
    place ? `A moment from ${place}` : 'Captured for today',
  ], 3, 72);
  const captionSuggestions = cleanSuggestionList([
    captionSeed,
    `A real ${categoryLabel} moment${placeSuffix}.`,
    place ? `Caught this at ${place}.` : 'Keeping this one for the memory.',
  ], 3, 260);
  return {
    source: 'fallback',
    ai_available: false,
    primary_category: category.primary_category,
    category_confidence: category.category_confidence,
    category_status: category.category_status,
    headline_suggestions: headlineSuggestions.length ? headlineSuggestions : ['Captured for today'],
    caption_suggestions: captionSuggestions.length ? captionSuggestions : ['Keeping this one for the memory.'],
    tags: category.tags,
  };
}

function workersAiText(result: any): string {
  if (typeof result === 'string') return result;
  if (typeof result?.response === 'string') return result.response;
  if (typeof result?.result?.response === 'string') return result.result.response;
  if (typeof result?.text === 'string') return result.text;
  if (typeof result?.result?.text === 'string') return result.result.text;
  const choice = result?.choices?.[0]?.message?.content || result?.result?.choices?.[0]?.message?.content;
  return typeof choice === 'string' ? choice : '';
}

function parseJsonObjectFromAi(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const response = (value as any).response;
    if (response && typeof response === 'object' && !Array.isArray(response)) return response;
  }
  const text = workersAiText(value).trim();
  if (!text) return {};
  const direct = parseJsonObject(text);
  if (Object.keys(direct).length) return direct;
  const match = text.match(/\{[\s\S]*\}/);
  return match ? parseJsonObject(match[0]) : {};
}

function normalizePostAssistAiPayload(raw: Record<string, unknown>, fallback: PostAssistResult): PostAssistResult {
  const aiCategory = normalizeDiscoverCategory(raw.primary_category || raw.category, false) as DiscoverCategory | '';
  const confidence = clampFloat(raw.category_confidence ?? raw.confidence, 0, 1, fallback.category_confidence);
  const headlineSuggestions = cleanSuggestionList(raw.headline_suggestions || raw.headlines || raw.titles, 4, 72);
  const captionSuggestions = cleanSuggestionList(raw.caption_suggestions || raw.captions, 4, 280);
  const tags = sanitizeAutoCategoryTags([...(fallback.tags || []), ...sanitizeAutoCategoryTags(raw.tags)]);
  return {
    source: 'workers_ai',
    ai_available: true,
    primary_category: aiCategory || fallback.primary_category,
    category_confidence: Number(Math.max(confidence, fallback.category_confidence).toFixed(2)),
    category_status: Math.max(confidence, fallback.category_confidence) >= 0.50 ? 'classified' : 'low_confidence',
    headline_suggestions: headlineSuggestions.length ? headlineSuggestions : fallback.headline_suggestions,
    caption_suggestions: captionSuggestions.length ? captionSuggestions : fallback.caption_suggestions,
    tags: tags.length ? tags : fallback.tags,
  };
}

async function generatePostAssistWithWorkersAi(env: Env, input: AutoCategoryInput, fallback: PostAssistResult): Promise<PostAssistResult> {
  if (!env.AI) return fallback;
  const payload = {
    existing_headline: cleanText((input as any).title || '', 120),
    existing_caption: cleanMultilineText(input.caption || '', 700),
    media_type: cleanText(input.mediaType || input.postType || 'image', 40),
    place: cleanText(input.placeName || '', 120),
    location: cleanText(input.location || '', 140),
    hashtags: sanitizeAutoCategoryTags(input.hashtags),
    apple_vision_guess: normalizeDiscoverCategory(input.appleCategoryGuess, false),
    apple_vision_confidence: clampFloat(input.appleConfidence, 0, 1, 0),
    apple_vision_labels: sanitizeAutoCategoryLabels(input.appleLabels).slice(0, 12),
    fallback_category: fallback.primary_category,
    allowed_categories: DISCOVER_CATEGORIES,
  };
  const result = await env.AI.run(postAssistModel(env), {
    messages: [
      {
        role: 'system',
        content: [
          'You are Captro Post Assist for a real social photo and short-video app.',
          'Write natural, human captions and short headlines. Keep it premium, simple, and not fake.',
          'Classify the post into exactly one allowed category. Do not invent unsupported categories.',
          'Return JSON only. Do not include markdown.',
        ].join(' '),
      },
      {
        role: 'user',
        content: JSON.stringify(payload),
      },
    ],
    max_tokens: 420,
    response_format: {
      type: 'json_schema',
      json_schema: {
        type: 'object',
        properties: {
          primary_category: { type: 'string', enum: DISCOVER_CATEGORIES },
          category_confidence: { type: 'number' },
          headline_suggestions: { type: 'array', items: { type: 'string' } },
          caption_suggestions: { type: 'array', items: { type: 'string' } },
          tags: { type: 'array', items: { type: 'string' } },
        },
        required: ['primary_category', 'category_confidence', 'headline_suggestions', 'caption_suggestions', 'tags'],
      },
    },
  });
  const parsed = parseJsonObjectFromAi(result);
  return Object.keys(parsed).length ? normalizePostAssistAiPayload(parsed, fallback) : fallback;
}

async function classifyPostMetadataWithWorkersAi(env: Env, input: AutoCategoryInput): Promise<{ category: DiscoverCategory | ''; confidence: number; labels: AutoCategoryLabel[] }> {
  if (!env.AI) return { category: '', confidence: 0, labels: [] };
  const base = autoCategoryEngine(input);
  const fallback = fallbackPostAssist(input, base);
  const assist = await generatePostAssistWithWorkersAi(env, input, fallback);
  const labels = sanitizeAutoCategoryLabels(assist.tags.map((tag) => ({ label: tag, confidence: 0.74, source: 'workers_ai_text' })));
  return {
    category: assist.primary_category,
    confidence: assist.category_confidence,
    labels,
  };
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
  const nowSeconds = Math.floor(Date.now() / 1000);
  const windowStart = Math.floor(nowSeconds / windowSeconds) * windowSeconds;
  const key = `${safeRateLimitPart(bucket)}:${safeRateLimitPart(identity)}:${windowStart}`;
  const updatedAt = now();
  if (c.env.KV) {
    try {
      const cached: any = await c.env.KV.get(key, 'json');
      const count = Math.max(0, Number(cached?.count || 0)) + 1;
      await c.env.KV.put(key, JSON.stringify({ window_start: windowStart, count, updated_at: updatedAt }), {
        expirationTtl: Math.max(60, windowSeconds + 30),
      });
      if (count > limit) {
        console.warn(JSON.stringify({ event: 'rate_limit_hit', request_id: c.get?.('requestId') || '', bucket: safeRateLimitPart(bucket), identity: safeRateLimitPart(identity), count, limit }));
        return c.json({ detail: 'Too many requests. Try again in a moment.', retry_after_seconds: windowSeconds }, 429);
      }
      return null;
    } catch (error: any) {
      console.warn(JSON.stringify({
        event: 'rate_limit_kv_unavailable',
        request_id: c.get?.('requestId') || '',
        bucket: safeRateLimitPart(bucket),
        code: safeRateLimitPart(getErrorCode(error)),
        fallback: 'd1',
      }));
    }
  }

  if (!c.env.KV && supabasePrimaryConfigured(c) && isProductionEnv(c)) {
    console.error(JSON.stringify({
      event: 'rate_limit_kv_missing',
      request_id: c.get?.('requestId') || '',
      bucket: safeRateLimitPart(bucket),
    }));
    return c.json({ detail: 'Temporary protection is unavailable. Please try again in a moment.' }, 503);
  }

  await ensureReliabilitySchema(c.env.DB);
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
  if (supabasePrimaryConfigured(c)) return supabaseValidateDirectMessagePeer(c, currentUserId, peerId);
  if (!peerId || peerId === currentUserId) {
    return c.json({ detail: 'Choose a valid recipient.' }, 400);
  }
  const peer = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND COALESCE(status, 'active') = 'active'").bind(peerId).first();
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
  'blocked_user',
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
    nudity: 'sexual_content',
    nudity_or_sexual_content: 'sexual_content',
    child_safety: 'minor_safety',
    child_safety_concern: 'minor_safety',
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
    if (supabasePrimaryConfigured(c)) {
      await writeSupabaseAuditLog(c, {
        actionType: `security_${cleanText(eventType, 70) || 'event'}`,
        actorUserId: userId || 'system',
        actorRole: userId ? 'user' : 'system',
        targetType: userId ? 'user' : 'security_event',
        targetId: userId || cleanText(eventType, 80) || 'event',
        reason: cleanText((metadata.reason as any) || '', 180),
        metadata,
      });
      return;
    }
    await ensureAbuseProtectionSchema(c.env.DB);
    await c.env.DB.prepare(
      'INSERT INTO security_events (id, event_type, user_id, ip, metadata, created_at) VALUES (?, ?, ?, ?, ?, ?)'
    ).bind(uuid(), cleanText(eventType, 80), cleanText(userId, 120), clientIp(c), JSON.stringify(scrubLogMetadata(metadata)), now()).run();
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'security_event_log_failed', type: cleanText(eventType, 80), code: getErrorCode(error) }));
  }
}

async function writeSupabaseAuditLog(c: any, input: {
  actionType: string;
  actorUserId?: string;
  actorRole?: string;
  targetType: string;
  targetId: string;
  targetUserId?: string;
  reason?: string;
  internalNote?: string;
  beforeState?: Record<string, unknown>;
  afterState?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}) {
  const ts = now();
  await supabaseAdminUpsert(c, 'app_audit_logs', [{
    id: uuid(),
    actor_admin_user_id: publicId(input.actorUserId || 'system', 120) || 'system',
    actor_role: cleanText(input.actorRole || 'system', 40),
    action_type: cleanText(input.actionType, 80),
    target_type: cleanText(input.targetType, 80),
    target_id: publicId(input.targetId || 'system', 120) || 'system',
    target_user_id: input.targetUserId ? publicId(input.targetUserId, 120) : null,
    reason: cleanText(input.reason || '', 300),
    internal_note: cleanMultilineText(input.internalNote || '', 600),
    before_state: input.beforeState || {},
    after_state: input.afterState || {},
    request_id: cleanText(c.get?.('requestId') || '', 120) || null,
    metadata: scrubLogMetadata(input.metadata || {}),
    created_at: ts,
  }], 'id');
}

async function recordTermsAcceptance(
  c: any,
  user: any,
  supabaseUserId: unknown,
  acceptance: { version: string; acceptedAt: string } | null,
  source: string
) {
  if (!acceptance) return;
  const userId = publicId(user?.id || '', 120);
  const authUserId = cleanText(supabaseUserId || user?.supabase_user_id, 160);
  if (!userId) return;
  if (authUserId) {
    try {
      const existing = await findSupabaseAuthUser(c, { id: authUserId });
      const currentMetadata = existing?.user_metadata && typeof existing.user_metadata === 'object' ? existing.user_metadata : {};
      await updateSupabaseAuthUser(c, authUserId, {
        user_metadata: {
          ...currentMetadata,
          ...termsAcceptanceMetadata(acceptance),
        },
      });
    } catch (error: any) {
      console.warn(JSON.stringify({
        event: 'terms_acceptance_auth_metadata_failed',
        user_id: userId,
        code: getErrorCode(error).slice(0, 160),
      }));
    }
  }
  await writeSupabaseAuditLog(c, {
    actionType: 'terms_accepted',
    actorUserId: userId,
    actorRole: 'user',
    targetType: 'user',
    targetId: userId,
    targetUserId: userId,
    reason: 'terms_acceptance',
    metadata: {
      terms_version: acceptance.version,
      terms_accepted_at: acceptance.acceptedAt,
      source: cleanText(source, 80),
      supabase_user_id: authUserId || null,
    },
  });
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
    if (supabasePrimaryConfigured(c)) {
      const signals = await buildAbuseSignals(c, fields);
      if (!signals.length) return;
      await writeSupabaseAuditLog(c, {
        actionType: 'abuse_signal_recorded',
        actorUserId: userId,
        actorRole: 'user',
        targetType: 'user',
        targetId: userId,
        targetUserId: userId,
        metadata: {
          source: cleanText(source, 80),
          signal_count: signals.length,
          signals: JSON.stringify(signals.slice(0, 24)),
        },
      });
      return;
    }
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

async function supabasePreferredNotificationLanguage(c: any, userId: string): Promise<'en' | 'fr' | 'es' | null> {
  if (!supabasePrimaryConfigured(c)) return null;
  const row = await getSupabaseAppUserRowByAnyId(c, userId);
  if (!row) return null;
  const profile = parseJsonObject(row.profile);
  const language = cleanText((profile as any).language || row.language || '', 8).toLowerCase().split('-')[0];
  return language === 'fr' || language === 'es' ? language : 'en';
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

  if (supabasePrimaryConfigured(c)) {
    if (dedupeKey) {
      const windowStart = new Date(Date.now() - Math.max(60, input.dedupeSeconds || 86400) * 1000).toISOString();
      const existing = await supabaseAdminQueryRows(c, 'app_notifications', {
        select: 'id,data',
        filters: {
          user_id: postgrestEqFilter(input.userId),
          type: postgrestEqFilter(type),
          created_at: `gte.${windowStart}`,
        },
        limit: 100,
      }).catch((error: any) => {
        console.warn(JSON.stringify({ event: 'supabase_notification_dedupe_failed', code: getErrorCode(error).slice(0, 180) }));
        return [];
      });
      if (existing.some((row) => cleanText((parseJsonObject(row.data) as any).dedupe_key, 160) === dedupeKey)) return false;
    }

    await supabaseAdminUpsert(c, 'app_notifications', [{
      id: uuid(),
      user_id: input.userId,
      type,
      title: cleanText(copy.title, 120),
      body: cleanText(copy.body, 300),
      content: cleanText(copy.body, 300),
      reference_id: cleanText((data.reference_id || data.post_id || data.message_id || '') as string, 160),
      data,
      is_read: false,
      created_at: now(),
      updated_at: now(),
    }], 'id');
  } else if (dedupeKey) {
    try {
      const existing = await c.env.DB.prepare(
        "SELECT id FROM notifications WHERE user_id = ? AND type = ? AND json_extract(data, '$.dedupe_key') = ? AND created_at > datetime('now', ?) LIMIT 1"
      ).bind(input.userId, type, dedupeKey, `-${Math.max(60, input.dedupeSeconds || 86400)} seconds`).first();
      if (existing) return false;
    } catch {
      // Older local D1 builds may not expose JSON functions; insert remains safe because engagement rows are idempotent.
    }
    await c.env.DB.prepare(
      'INSERT INTO notifications (id, user_id, type, title, body, data, is_read, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, datetime(\'now\'))'
    ).bind(uuid(), input.userId, type, cleanText(copy.title, 120), cleanText(copy.body, 300), JSON.stringify(data)).run();
  } else {
    await c.env.DB.prepare(
      'INSERT INTO notifications (id, user_id, type, title, body, data, is_read, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, datetime(\'now\'))'
    ).bind(uuid(), input.userId, type, cleanText(copy.title, 120), cleanText(copy.body, 300), JSON.stringify(data)).run();
  }

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
  const supabaseLanguage = await supabasePreferredNotificationLanguage(c, userId).catch(() => null);
  if (supabaseLanguage) return supabaseLanguage;
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
  if (supabasePrimaryConfigured(c)) {
    const supabaseTarget = await supabaseResolveReportTarget(c, reporterId, type, reportedId);
    if (supabaseTarget) return supabaseTarget;
    return { ok: false, status: 404, detail: 'Reported content was not found.' };
  }

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
        `WHERE s.id = ? AND s.created_at >= datetime('now', '-14 days') AND ${visibleStatusWhere('u', 's')} LIMIT 1`,
      ].join(' ');
      const row: any = await c.env.DB.prepare(storySql).bind(reportedId, reporterId, reporterId).first();
      if (!row) return { ok: false, status: 404, detail: 'Reported story was not found.' };
      if (row.user_id === reporterId) return { ok: false, status: 400, detail: 'You cannot report your own story.' };
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

async function supabaseResolveReportTarget(
  c: any,
  reporterId: string,
  type: string,
  reportedId: string
): Promise<{ ok: boolean; status?: number; detail?: string; contentId?: string; targetOwnerUserId?: string } | null> {
  if (!reportedId) return { ok: false, status: 400, detail: 'Choose something to report.' };
  const reporterAliases = await supabaseRelatedInteractionUserIds(c, reporterId);
  const reporterAliasSet = new Set(reporterAliases.map((value) => publicId(value, 120)).filter(Boolean));
  const isReporter = (value: unknown) => {
    const clean = publicId(value, 120);
    return !!clean && reporterAliasSet.has(clean);
  };

  try {
    if (type === 'post' || type === 'discover_post') {
      const [post] = await supabaseReadVisiblePosts(c, reporterId, { postId: reportedId, limit: 1 });
      if (!post) {
        return { ok: false, status: 404, detail: type === 'discover_post' ? 'Reported Discover post was not found.' : 'Reported post was not found.' };
      }
      const ownerId = publicId(post.user_id, 120);
      if (isReporter(ownerId)) return { ok: false, status: 400, detail: 'You cannot report your own content.' };
      return { ok: true, contentId: publicId(post.id || reportedId, 120), targetOwnerUserId: ownerId };
    }

    if (type === 'comment') {
      const rows = await supabaseAdminQueryRows(c, 'post_comments', {
        select: 'legacy_comment_id,legacy_post_id,app_user_id,user_id,status',
        filters: { legacy_comment_id: postgrestEqFilter(reportedId) },
        limit: 1,
      });
      const comment = rows[0];
      if (!comment || ['removed', 'hidden'].includes(cleanText(comment.status || 'active', 40))) {
        return { ok: false, status: 404, detail: 'Reported comment was not found.' };
      }
      const commentOwnerId = publicId(comment.app_user_id || comment.user_id, 120);
      if (isReporter(commentOwnerId)) return { ok: false, status: 400, detail: 'You cannot report your own comment.' };
      const postId = publicId(comment.legacy_post_id, 120);
      if (!postId) return { ok: false, status: 404, detail: 'Reported comment was not found.' };
      const visiblePost = await supabaseReadVisiblePosts(c, reporterId, { postId, limit: 1 });
      if (!visiblePost.length) return { ok: false, status: 404, detail: 'Reported comment was not found.' };
      return { ok: true, contentId: postId, targetOwnerUserId: commentOwnerId };
    }

    if (type === 'profile' || type === 'user') {
      const target = await supabaseUserByAnyId(c, reportedId);
      const targetId = publicId(target?.id, 120);
      if (!targetId) return { ok: false, status: 404, detail: 'Reported profile was not found.' };
      if (isReporter(targetId)) return { ok: false, status: 400, detail: 'You cannot report your own profile.' };
      return { ok: true, contentId: targetId, targetOwnerUserId: targetId };
    }

    if (type === 'message') {
      const rows = await supabaseAdminQueryRows(c, 'app_messages', {
        select: 'id,sender_id,receiver_id,status',
        filters: {
          id: postgrestEqFilter(reportedId),
          or: `(sender_id.${postgrestInFilter(reporterAliases)},receiver_id.${postgrestInFilter(reporterAliases)})`,
        },
        limit: 1,
      });
      const message = rows[0];
      if (!message || cleanText(message.status || 'sent', 40) === 'deleted') {
        return { ok: false, status: 404, detail: 'Reported message was not found.' };
      }
      const senderId = publicId(message.sender_id, 120);
      const receiverId = publicId(message.receiver_id, 120);
      const targetOwnerUserId = isReporter(senderId) ? receiverId : senderId;
      if (!targetOwnerUserId || isReporter(targetOwnerUserId)) return { ok: false, status: 400, detail: 'You cannot report your own message.' };
      return { ok: true, contentId: publicId(message.id || reportedId, 120), targetOwnerUserId };
    }
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_report_target_check_failed', type, code: getErrorCode(error).slice(0, 180) }));
    return { ok: false, status: 404, detail: 'Reported content was not found.' };
  }

  return null;
}

async function blockUserForReporter(c: any, blockerId: string, blockedId: string): Promise<boolean> {
  const cleanBlockedId = publicId(blockedId, 120);
  if (!cleanBlockedId || cleanBlockedId === blockerId) return false;
  if (supabasePrimaryConfigured(c)) {
    const result = await supabaseBlockUser(c, blockerId, cleanBlockedId);
    return result.status >= 200 && result.status < 300;
  }
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
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'report_submit');
  if (supabaseRequired) return supabaseRequired;
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

  const reporterAliases = supabasePrimaryConfigured(c) ? await supabaseRelatedInteractionUserIds(c, reporterId) : [reporterId];
  const existing: any = supabasePrimaryConfigured(c)
    ? (await supabaseAdminQueryRows(c, 'app_reports', {
      select: 'id',
      filters: {
        reporter_id: postgrestInFilter(reporterAliases),
        target_type: postgrestEqFilter(reportedType),
        target_id: postgrestEqFilter(reportedId),
        status: postgrestInFilter(['open', 'pending', 'under_review', 'reviewing', 'in_review', 'escalated']),
      },
      limit: 1,
    }))[0]
    : await c.env.DB.prepare(
      "SELECT id FROM reports WHERE reporter_id = ? AND reported_type = ? AND reported_id = ? AND COALESCE(status, 'open') IN ('open', 'pending', 'under_review', 'reviewing', 'escalated') LIMIT 1"
    ).bind(reporterId, reportedType, reportedId).first();
  if (existing) {
    await logSecurityEvent(c, 'duplicate_report_blocked', reporterId, { reported_type: reportedType, reason });
    const blocked = wantsBlock && target.targetOwnerUserId ? await blockUserForReporter(c, reporterId, target.targetOwnerUserId) : false;
    return c.json({ id: existing.id, reported: true, duplicate: true, blocked, hidden: wantsHideContent, error_code: 'report_duplicate' });
  }

  const id = uuid();
  const ts = now();
  if (supabasePrimaryConfigured(c)) {
    await supabaseAdminUpsert(c, 'app_reports', [{
      id,
      reporter_id: reporterId,
      target_type: reportedType,
      target_id: reportedId,
      target_owner_user_id: target.targetOwnerUserId || null,
      reason,
      details,
      status: 'open',
      priority,
      metadata: {
        content_id: target.contentId || '',
        hide_content_for_reporter: wantsHideContent,
        source: 'captro_user_report_flow',
      },
      legacy_created_at: ts,
      legacy_updated_at: ts,
      created_at: ts,
      updated_at: ts,
    }], 'id');
  } else {
    await c.env.DB.prepare(
      `INSERT INTO reports (
        id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, priority, target_owner_user_id, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?, ?)`
    ).bind(id, reporterId, reportedId, reportedType, reportedType, reason, details, target.contentId || '', priority, target.targetOwnerUserId || '', ts, ts).run();
  }
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
      const originalWidth = clampNumber(item?.original_width ?? item?.originalWidth ?? width, 0, 12000, 0);
      const originalHeight = clampNumber(item?.original_height ?? item?.originalHeight ?? height, 0, 12000, 0);
      const originalAspectRatio = clampFloat(
        item?.original_aspect_ratio
        ?? item?.originalAspectRatio
        ?? item?.aspect_ratio
        ?? item?.aspectRatio
        ?? item?.ratio
        ?? (originalWidth > 0 && originalHeight > 0 ? originalWidth / originalHeight : 0),
        0,
        4,
        0
      );
      const variant = supportedFeedMediaVariant({ ...item, width, height, original_width: originalWidth, original_height: originalHeight, original_aspect_ratio: originalAspectRatio });
      const ratio = clampFloat(item?.ratio || originalAspectRatio || (width > 0 && height > 0 ? width / height : 0), 0, 4, 0);
      const type = String(item?.media_type || item?.mediaType || item?.type || '').toLowerCase().includes('video') ? 'video' : 'image';
      if (!width && !height && !ratio && !originalWidth && !originalHeight && !item?.format) return null;
      return {
        width,
        height,
        ratio,
        format: variant.format,
        type,
        original_width: originalWidth || width || null,
        original_height: originalHeight || height || null,
        original_aspect_ratio: originalAspectRatio || ratio || null,
        feed_width: variant.feed_width,
        feed_height: variant.feed_height,
        feed_aspect_ratio: variant.feed_aspect_ratio,
        display_aspect_ratio: variant.feed_aspect_ratio,
        crop_mode: cleanText(item?.crop_mode || item?.cropMode || 'center_crop', 40),
        media_type: type,
      };
    })
    .filter(Boolean)
    .slice(0, 12);
}

function normalizeRecommendationCategory(value: unknown): string {
  const clean = String(value || '').trim().toLowerCase().replace(/[^a-z0-9 _-]/g, '').replace(/\s+/g, ' ');
  const allowed = new Set(['vibe', 'music', 'people', 'artist', 'movies', 'books', 'artists', 'videos', 'podcasts', 'places', 'apps', 'other']);
  if (clean === 'note' || clean === 'thought' || clean === 'poem') return 'other';
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
    /\b(free money|cashapp flip|telegram investment|whatsapp investment|click this link|login to verify|airdrop claim)\b/i,
    /\b(bit\.ly|tinyurl\.com|t\.me\/|wa\.me\/|grabify|iplogger)\b/i,
    /\b(nazi praise|exterminate all|racial slur)\b/i,
  ];
  if (blockedPatterns.some((pattern) => pattern.test(text))) {
    return { ok: false, detail: 'That needs moderation review before it can be posted.' };
  }
  return { ok: true };
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

const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/heic', 'image/heif']);
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
const ALLOWED_IMAGE_EXTENSIONS = new Set(['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif']);
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
  const ids = Array.from(new Set(backupIds.map(String).map((id) => id.trim()).filter(Boolean)));
  if (!ids.length) return;
  await ensureMediaBackupSchema(db);

  for (const backupId of ids) {
    await db.prepare('UPDATE media_backups SET post_id = ?, updated_at = ? WHERE id = ? AND user_id = ?')
      .bind(postId, now(), backupId, userId)
      .run();
  }
}

function mediaBackupIdsFromReferences(values: unknown[]): string[] {
  return Array.from(new Set(values.map(mediaBackupIdFromReference).filter(Boolean)));
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
  const rawMediaUrl = cleanText(row.media_url || '', 2500);
  let mediaUrl = rawMediaUrl ? await signedMessageMediaReference(c, rawMediaUrl) : rawMediaUrl;
  const rawMediaType = cleanText(row.media_type || '', 40).toLowerCase();
  const isVideoMessage = rawMediaType.includes('video') || isVideoMediaUrl(rawMediaUrl) || isVideoMediaUrl(mediaUrl);
  const streamPosterUrl = isVideoMessage ? streamThumbnailUrl(rawMediaUrl) : '';
  if (isVideoMessage && rawMediaUrl.startsWith('cfstream:')) mediaUrl = rawMediaUrl;
  const rawCreatedAt = cleanText(row.created_at || '', 80);
  const parsedCreatedAt = rawCreatedAt
    ? Date.parse(rawCreatedAt.includes('T') ? rawCreatedAt : `${rawCreatedAt.replace(' ', 'T')}Z`)
    : NaN;
  const thumbnailUrl = row.thumbnail_url || row.thumbnail || streamPosterUrl || null;
  const posterUrl = row.poster_url || row.poster || streamPosterUrl || thumbnailUrl || null;
  return {
    ...row,
    media_url: mediaUrl,
    status: row.status || 'sent',
    updated_at: row.updated_at || row.created_at || null,
    server_sequence: Number.isFinite(parsedCreatedAt) ? parsedCreatedAt : null,
    thumbnail_url: thumbnailUrl,
    poster_url: posterUrl,
  };
}

const FEED_MEDIA_WIDTH = 1080;
const FEED_MEDIA_HEIGHT = 1440;
const FEED_MEDIA_ASPECT_RATIO = FEED_MEDIA_WIDTH / FEED_MEDIA_HEIGHT;
const SUPPORTED_FEED_MEDIA_RATIOS = [
  { format: '4:5', feed_width: 1080, feed_height: 1350, feed_aspect_ratio: 1080 / 1350 },
  { format: '1:1', feed_width: 1080, feed_height: 1080, feed_aspect_ratio: 1 },
  { format: '3:4', feed_width: 1080, feed_height: 1440, feed_aspect_ratio: 1080 / 1440 },
  { format: '16:9', feed_width: 1920, feed_height: 1080, feed_aspect_ratio: 1920 / 1080 },
];
const DEFAULT_FEED_MEDIA_RATIO = SUPPORTED_FEED_MEDIA_RATIOS[2];

function supportedFeedMediaVariant(source: any = {}) {
  const format = cleanText(source?.format, 16);
  const explicit = SUPPORTED_FEED_MEDIA_RATIOS.find((item) => item.format === format);
  const width = Number(source?.original_width || source?.originalWidth || source?.width || 0);
  const height = Number(source?.original_height || source?.originalHeight || source?.height || 0);
  const ratio = Number(
    source?.original_aspect_ratio
    || source?.originalAspectRatio
    || source?.aspect_ratio
    || source?.aspectRatio
    || source?.ratio
    || (width > 0 && height > 0 ? width / height : 0)
    || source?.display_aspect_ratio
    || source?.displayAspectRatio
    || source?.feed_aspect_ratio
    || source?.feedAspectRatio
  );
  if (!Number.isFinite(ratio) || ratio <= 0) return explicit || DEFAULT_FEED_MEDIA_RATIO;
  return SUPPORTED_FEED_MEDIA_RATIOS.reduce((best, candidate) => (
    Math.abs(Math.log(candidate.feed_aspect_ratio / ratio)) < Math.abs(Math.log(best.feed_aspect_ratio / ratio)) ? candidate : best
  ), DEFAULT_FEED_MEDIA_RATIO);
}

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
  return lower.startsWith('cfstream:')
    || lower.includes('videodelivery.net')
    || lower.includes('cloudflarestream.com')
    || lower.includes('tiktok')
    || lower.includes('/manifest/video.m3u8')
    || /\.(mp4|mov|m4v|webm|m3u8)(\?|#|$)/.test(lower);
}

function postContainsVideoMedia(post: any): boolean {
  const mediaUrls = sanitizeMediaReferences(post?.images, post?.image);
  const mediaTypes = parseJsonArray(post?.media_types).map((item) => String(item || '').toLowerCase());
  const postType = String(post?.post_type || post?.media_type || post?.type || '').toLowerCase();
  return postType.includes('video') || mediaTypes.some((type) => type.includes('video')) || mediaUrls.some(isVideoMediaUrl);
}

function postHasRenderablePhotoMedia(post: any): boolean {
  const mediaUrls = sanitizeMediaReferences(post?.images, post?.image);
  if (!mediaUrls.length) return false;
  const mediaTypes = parseJsonArray(post?.media_types).map((item) => String(item || '').toLowerCase());
  return mediaUrls.some((url, index) => {
    const type = mediaTypes[index] || '';
    return !type.includes('video') && !isVideoMediaUrl(url);
  });
}

function supabaseAppPostHasRenderablePhotoMedia(row: any): boolean {
  const postType = String(row?.post_type || '').toLowerCase();
  if (postType === 'note' || postType.includes('video')) return false;
  const media = supabaseAppPostMedia(row);
  if (!media.mediaUrls.length) return false;
  return media.mediaUrls.some((url, index) => {
    const type = String(media.mediaTypes[index] || '').toLowerCase();
    return !type.includes('video') && !isVideoMediaUrl(url);
  });
}

function normalizeStoryDurationSeconds(value: unknown): 15 | 30 | 60 | 0 {
  const duration = Math.round(Number(value || 0));
  if (duration === 15 || duration === 30 || duration === 60) return duration;
  return 0;
}

function maxPostCounterAfterToggle(current: unknown, enabled: boolean, changed: boolean): number {
  const count = Math.max(0, Number(current || 0));
  if (!changed) return count;
  return enabled ? count + 1 : Math.max(0, count - 1);
}

function feedPhotoPostsOnly(posts: any[]): any[] {
  return posts.filter((post) => postHasRenderablePhotoMedia(post) && !postContainsVideoMedia(post) && String(post?.post_type || '').toLowerCase() !== 'note');
}

function feedPhotoPostWhere(postAlias = 'p'): string {
  const postType = `LOWER(COALESCE(${postAlias}.post_type, ''))`;
  const mediaTypes = `LOWER(COALESCE(${postAlias}.media_types, ''))`;
  const image = `LOWER(COALESCE(${postAlias}.image, ''))`;
  const images = `LOWER(COALESCE(${postAlias}.images, ''))`;
  const videoNeedles = [
    "'%video%'",
    "'%cfstream:%'",
    "'%videodelivery.net%'",
    "'%cloudflarestream.com%'",
    "'%tiktok%'",
    "'%.mp4%'",
    "'%.mov%'",
    "'%.m4v%'",
    "'%.webm%'",
    "'%.m3u8%'",
  ];
  const conditions = [
    `${postType} != 'note'`,
    ...videoNeedles.map((needle) => `${postType} NOT LIKE ${needle}`),
    ...videoNeedles.map((needle) => `${mediaTypes} NOT LIKE ${needle}`),
    ...videoNeedles.slice(1).map((needle) => `${image} NOT LIKE ${needle}`),
    ...videoNeedles.slice(1).map((needle) => `${images} NOT LIKE ${needle}`),
  ];
  return conditions.join(' AND ');
}

function feedDeliveryUrl(url: string, mediaType: string, variant: string, env?: Env): string {
  if (!url) return '';
  if (mediaType === 'video') return url;
  return cloudflareTransformedImageUrl(env, replaceCloudflareImageVariant(url, variant), 'feed');
}

function posterDeliveryUrl(url: string, mediaType: string, variant: string, env?: Env): string {
  if (!url) return '';
  if (mediaType !== 'video') return cloudflareTransformedImageUrl(env, replaceCloudflareImageVariant(url, variant), 'thumbnail');
  return streamThumbnailUrl(url);
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
    const variant = supportedFeedMediaVariant({ ...original, original_width: originalWidth, original_height: originalHeight, original_aspect_ratio: originalAspectRatio });
    return {
      ...original,
      original_width: originalWidth,
      original_height: originalHeight,
      original_aspect_ratio: originalAspectRatio,
      width: originalWidth,
      height: originalHeight,
      ratio: originalAspectRatio,
      format: variant.format,
      feed_width: variant.feed_width,
      feed_height: variant.feed_height,
      feed_aspect_ratio: variant.feed_aspect_ratio,
      display_aspect_ratio: variant.feed_aspect_ratio,
      crop_mode: cleanText(original.crop_mode || original.cropMode || 'center_crop', 40),
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

function normalizeCategoryScoresPayload(value: unknown): Record<string, number> {
  const raw = parseJsonObject(value);
  const scores: Record<string, number> = {};
  for (const category of DISCOVER_CATEGORIES) {
    const score = Number(raw[category] || 0);
    scores[category] = Number(Math.max(0, Number.isFinite(score) ? score : 0).toFixed(1));
  }
  return scores;
}

function normalizeSecondaryCategoriesPayload(value: unknown, primary: DiscoverCategory): DiscoverCategory[] {
  const categories = sanitizeAutoCategoryTags(value)
    .map((item) => normalizeDiscoverCategory(item, false) as DiscoverCategory | '')
    .filter((item): item is DiscoverCategory => !!item);
  return Array.from(new Set([primary, ...categories])).slice(0, 5);
}

function postPayload(post: any, likedBy: string[] = [], env?: Env) {
  const audioHidden = Number(post.audio_hidden || 0) === 1;
  const likesCount = Math.max(0, Number(post.live_likes_count ?? post.likes_count ?? 0));
  const commentsCount = Math.max(0, Number(post.live_comments_count ?? post.comments_count ?? 0));
  const savesCount = Math.max(0, Number(post.live_saves_count ?? post.saves_count ?? 0));
  const isLiked =
    post.is_liked === true || post.is_liked === 1 || post.is_liked === '1' ||
    post.viewer_liked === true || post.viewer_liked === 1 || post.viewer_liked === '1' ||
    post.liked_by_me === true || post.liked_by_me === 1 || post.liked_by_me === '1';
  const isSaved =
    post.is_saved === true || post.is_saved === 1 || post.is_saved === '1' ||
    post.saved === true || post.saved === 1 || post.saved === '1' ||
    post.viewer_saved === true || post.viewer_saved === 1 || post.viewer_saved === '1' ||
    post.saved_by_me === true || post.saved_by_me === 1 || post.saved_by_me === '1';
  const mediaUrls = sanitizeMediaReferences(post.images, post.image);
  const primaryMediaUrl = safeMediaReference(post.image) || mediaUrls[0] || '';
  const mediaTypes = parseJsonArray(post.media_types).map((item) => String(item || '').toLowerCase().includes('video') ? 'video' : 'image');
  while (mediaTypes.length < mediaUrls.length) mediaTypes.push(isVideoMediaUrl(mediaUrls[mediaTypes.length]) ? 'video' : 'image');
  const dimensions = parseJsonArray(post.media_dimensions);
  const feedVariant = env?.CLOUDFLARE_IMAGES_FEED_VARIANT || '';
  const thumbnailVariant = env?.CLOUDFLARE_IMAGES_THUMBNAIL_VARIANT || '';
  const feedMediaUrls = mediaUrls.map((url, index) => feedDeliveryUrl(url, mediaTypes[index] || 'image', feedVariant, env)).filter(Boolean);
  const thumbnailUrls = mediaUrls.map((url, index) => posterDeliveryUrl(url, mediaTypes[index] || 'image', thumbnailVariant, env)).filter(Boolean);
  const posterUrls = mediaUrls.map((url, index) => posterDeliveryUrl(url, mediaTypes[index] || 'image', thumbnailVariant, env)).filter(Boolean);
  const fallbackMediaUrls = mediaUrls.map((url, index) => {
    const renderedUrl = feedMediaUrls[index] || url;
    return cloudflareImageProxyFallbackUrl(env, renderedUrl) || cloudflareImageProxyFallbackUrl(env, url) || url;
  });
  const renderedMediaDimensions = feedMediaDimensions(mediaUrls, mediaTypes, dimensions);
  const primaryMediaDimensions = renderedMediaDimensions[0] || DEFAULT_FEED_MEDIA_RATIO;
  const primaryCategory = (normalizeDiscoverCategory(post.primary_category || post.category || post.post_type, false) || DEFAULT_DISCOVER_CATEGORY) as DiscoverCategory;
  const categoryConfidence = clampFloat(post.category_confidence, 0, 1, 0);
  const categoryScores = normalizeCategoryScoresPayload(post.category_scores_json || (parseJsonObject(post.category_signals_json) as any).category_scores);
  if (!categoryScores[primaryCategory]) categoryScores[primaryCategory] = Number(Math.max(categoryConfidence * 100, 45).toFixed(1));
  const secondaryCategories = normalizeSecondaryCategoriesPayload(post.secondary_categories_json, primaryCategory);
  const detectedObjects = sanitizeAutoCategoryTags(post.detected_objects_json || (parseJsonObject(post.category_signals_json) as any).detected_objects);
  const captionKeywords = sanitizeAutoCategoryTags(post.caption_keywords_json || (parseJsonObject(post.category_signals_json) as any).caption_keywords);
  const categoryDebug = parseJsonObject(post.category_signals_json);
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
    liked: isLiked,
    is_liked: isLiked,
    liked_by_me: isLiked,
    viewer_liked: isLiked,
    is_saved: isSaved,
    saved: isSaved,
    saved_by_me: isSaved,
    viewer_saved: isSaved,
    image: primaryMediaUrl,
    images: mediaUrls,
    feed_media_urls: feedMediaUrls,
    thumbnail_urls: thumbnailUrls,
    poster_urls: posterUrls,
    media_fallback_urls: fallbackMediaUrls,
    original_media_url: primaryMediaUrl,
    original_media_urls: mediaUrls,
    media_types: mediaTypes.slice(0, mediaUrls.length || mediaTypes.length),
    media_backup_ids: parseJsonArray(post.media_backup_ids),
    media_dimensions: renderedMediaDimensions,
    feed_width: Number(primaryMediaDimensions.feed_width || FEED_MEDIA_WIDTH),
    feed_height: Number(primaryMediaDimensions.feed_height || FEED_MEDIA_HEIGHT),
    feed_aspect_ratio: Number(primaryMediaDimensions.feed_aspect_ratio || FEED_MEDIA_ASPECT_RATIO),
    primary_category: primaryCategory,
    category: primaryCategory,
    category_confidence: categoryConfidence,
    category_source: normalizeCategorySource(post.category_source),
    category_status: normalizeCategoryStatus(post.category_status),
    secondary_categories: secondaryCategories,
    category_scores: categoryScores,
    detected_objects: detectedObjects,
    detected_scene: cleanText(post.detected_scene || (categoryDebug as any).detected_scene || '', 80),
    place_type: cleanText(post.place_type || (categoryDebug as any).place_type || '', 120),
    user_selected_category: normalizeDiscoverCategory(post.user_selected_category || (categoryDebug as any).user_selected_category, false),
    caption_keywords: captionKeywords,
    category_signals: categoryDebug,
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

const SUPABASE_APP_POST_SELECT = [
  'id',
  'legacy_post_id',
  'user_id',
  'app_user_id',
  'title',
  'content',
  'visibility',
  'status',
  'post_type',
  'category',
  'location',
  'media',
  'media_dimensions',
  'editor_data',
  'product_tags',
  'tagged_users',
  'metadata',
  'likes_count',
  'comments_count',
  'saves_count',
  'created_at',
  'updated_at',
  'legacy_created_at',
  'legacy_updated_at',
].join(',');

type SupabasePostReadOptions = {
  postId?: string;
  postIds?: string[];
  ownerId?: string;
  category?: DiscoverCategory | 'all';
  photoOnly?: boolean;
  search?: string;
  limit?: number;
  offset?: number;
  order?: 'newest' | 'trending';
};

function postgrestSearchTerm(value: string): string {
  return cleanText(value, 80).replace(/[(),*]/g, ' ').trim();
}

function supabaseAccountIdentityKeys(row: any): string[] {
  const keys: string[] = [];
  const provider = cleanText(row?.provider, 40);
  const providerUserId = cleanText(row?.provider_user_id, 240);
  const emailHash = cleanText(row?.email_hash, 160);
  if (provider && providerUserId) keys.push(`provider:${provider}:${providerUserId}`);
  if (emailHash) keys.push(`email:${emailHash}`);
  return keys;
}

async function supabaseAccountIdentityActorKeysMap(c: any, userIds: string[]): Promise<Map<string, string[]>> {
  const cleanUserIds = Array.from(new Set(userIds.map((value) => publicId(value, 120)).filter(Boolean)));
  const actorKeys = new Map<string, string[]>();
  if (!cleanUserIds.length) return actorKeys;

  try {
    const rows = await supabaseAdminQueryRows(c, 'app_account_identities', {
      select: 'user_id,provider,provider_user_id,email_hash',
      filters: { user_id: postgrestInFilter(cleanUserIds) },
      limit: Math.max(50, cleanUserIds.length * 8),
    });
    for (const row of rows) {
      const userId = publicId(row?.user_id, 120);
      const keys = supabaseAccountIdentityKeys(row);
      if (!userId || !keys.length) continue;
      const existing = actorKeys.get(userId) || [];
      actorKeys.set(userId, Array.from(new Set([...existing, ...keys])));
    }
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) {
      console.warn(JSON.stringify({ event: 'supabase_account_identity_actor_map_failed', code: getErrorCode(error).slice(0, 180) }));
    }
  }

  return actorKeys;
}

async function supabaseAccountIdentityAliasUserIds(c: any, userIds: string[]): Promise<string[]> {
  const cleanUserIds = Array.from(new Set(userIds.map((value) => publicId(value, 120)).filter(Boolean)));
  if (!cleanUserIds.length) return [];

  try {
    const ownedIdentities = await supabaseAdminQueryRows(c, 'app_account_identities', {
      select: 'user_id,provider,provider_user_id,email_hash',
      filters: { user_id: postgrestInFilter(cleanUserIds) },
      limit: Math.max(20, cleanUserIds.length * 8),
    });
    const identityKeys = new Set(ownedIdentities.flatMap(supabaseAccountIdentityKeys));
    if (!identityKeys.size) return [];

    const providerUserIds = Array.from(new Set(ownedIdentities.map((row) => cleanText(row?.provider_user_id, 240)).filter(Boolean)));
    const emailHashes = Array.from(new Set(ownedIdentities.map((row) => cleanText(row?.email_hash, 160)).filter(Boolean)));
    const orParts: string[] = [];
    if (providerUserIds.length) orParts.push(`provider_user_id.${postgrestInFilter(providerUserIds)}`);
    if (emailHashes.length) orParts.push(`email_hash.${postgrestInFilter(emailHashes)}`);
    if (!orParts.length) return [];

    const matchingIdentities = await supabaseAdminQueryRows(c, 'app_account_identities', {
      select: 'user_id,provider,provider_user_id,email_hash',
      filters: { or: `(${orParts.join(',')})` },
      limit: Math.max(100, (providerUserIds.length + emailHashes.length) * 20),
    });
    return Array.from(new Set(matchingIdentities
      .filter((row) => supabaseAccountIdentityKeys(row).some((key) => identityKeys.has(key)))
      .map((row) => publicId(row?.user_id, 120))
      .filter(Boolean)));
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) {
      console.warn(JSON.stringify({ event: 'supabase_account_identity_alias_failed', code: getErrorCode(error).slice(0, 180) }));
    }
    return [];
  }
}

async function supabaseAccountIdentityActorKeyMap(c: any, userIds: string[]): Promise<Map<string, string>> {
  const actorKeys = new Map<string, string>();
  const allActorKeys = await supabaseAccountIdentityActorKeysMap(c, userIds);
  for (const [userId, keys] of allActorKeys.entries()) {
    const key = keys[0];
    if (key) actorKeys.set(userId, key);
  }
  return actorKeys;
}

async function supabaseRelatedInteractionUserIds(c: any, userId: string): Promise<string[]> {
  const ids = new Set<string>();
  const cleanUserId = publicId(userId, 120);
  if (cleanUserId) ids.add(cleanUserId);

  const payload = c.get?.('jwtPayload') || {};
  const payloadSupabaseSub = isUuidText(payload?.supabase_sub || payload?.supabaseSub);
  if (payloadSupabaseSub) ids.add(payloadSupabaseSub);

  const directAuthId = isUuidText(cleanUserId);
  const orParts: string[] = [];
  if (cleanUserId) orParts.push(`id.eq.${cleanUserId}`);
  if (payloadSupabaseSub) orParts.push(`supabase_user_id.eq.${payloadSupabaseSub}`);
  if (directAuthId) orParts.push(`supabase_user_id.eq.${directAuthId}`);

  if (orParts.length) {
    try {
      const rows = await supabaseAdminQueryRows(c, 'app_users', {
        select: 'id,supabase_user_id',
        filters: { or: `(${orParts.join(',')})` },
        limit: 20,
      });
      for (const row of rows) {
        const appUserId = publicId(row?.id, 120);
        const authUserId = isUuidText(row?.supabase_user_id);
        if (appUserId) ids.add(appUserId);
        if (authUserId) ids.add(authUserId);
      }
    } catch (error: any) {
      console.warn(JSON.stringify({ event: 'supabase_identity_alias_read_failed', code: getErrorCode(error).slice(0, 180) }));
    }
  }

  const identityAliasUserIds = await supabaseAccountIdentityAliasUserIds(c, Array.from(ids));
  for (const aliasUserId of identityAliasUserIds) ids.add(aliasUserId);
  if (identityAliasUserIds.length) {
    try {
      const rows = await supabaseAdminQueryRows(c, 'app_users', {
        select: 'id,supabase_user_id',
        filters: { id: postgrestInFilter(identityAliasUserIds) },
        limit: Math.max(20, identityAliasUserIds.length),
      });
      for (const row of rows) {
        const appUserId = publicId(row?.id, 120);
        const authUserId = isUuidText(row?.supabase_user_id);
        if (appUserId) ids.add(appUserId);
        if (authUserId) ids.add(authUserId);
      }
    } catch (error: any) {
      console.warn(JSON.stringify({ event: 'supabase_identity_alias_user_read_failed', code: getErrorCode(error).slice(0, 180) }));
    }
  }

  return Array.from(ids);
}

async function supabaseUsersByAnyIds(c: any, ids: string[]): Promise<Map<string, any>> {
  const cleanIds = Array.from(new Set(ids.map((value) => publicId(value, 120)).filter(Boolean)));
  const map = new Map<string, any>();
  if (!cleanIds.length) return map;
  const appIds = cleanIds.filter((id) => !isUuidText(id) || true);
  const authIds = cleanIds.map((id) => isUuidText(id)).filter((id): id is string => !!id);

  try {
    if (appIds.length) {
      const rows = await supabaseAdminQueryRows(c, 'app_users', {
        select: 'id,supabase_user_id,username,full_name,avatar_url,cover_url,bio,city,is_private,is_verified,counts,profile,metadata',
        filters: { id: postgrestInFilter(appIds) },
        limit: Math.max(1, appIds.length),
      });
      for (const row of rows) {
        const appUserId = publicId(row?.id, 120);
        const authUserId = isUuidText(row?.supabase_user_id);
        if (appUserId) map.set(appUserId, row);
        if (authUserId) map.set(authUserId, row);
      }
    }
    if (authIds.length) {
      const rows = await supabaseAdminQueryRows(c, 'app_users', {
        select: 'id,supabase_user_id,username,full_name,avatar_url,cover_url,bio,city,is_private,is_verified,counts,profile,metadata',
        filters: { supabase_user_id: postgrestInFilter(authIds) },
        limit: Math.max(1, authIds.length),
      });
      for (const row of rows) {
        const appUserId = publicId(row?.id, 120);
        const authUserId = isUuidText(row?.supabase_user_id);
        if (appUserId) map.set(appUserId, row);
        if (authUserId) map.set(authUserId, row);
      }
    }
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_users_read_failed', code: getErrorCode(error).slice(0, 180) }));
  }
  return map;
}

async function supabaseBlockedUserIds(c: any, viewerId: string): Promise<Set<string>> {
  const aliases = await supabaseRelatedInteractionUserIds(c, viewerId);
  const blocked = new Set<string>();
  if (!aliases.length) return blocked;
  try {
    const rows = await supabaseAdminQueryRows(c, 'app_blocks', {
      select: 'blocker_id,blocked_id',
      filters: {
        or: `(blocker_id.${postgrestInFilter(aliases)},blocked_id.${postgrestInFilter(aliases)})`,
      },
      limit: Math.max(50, aliases.length * 20),
    });
    for (const row of rows) {
      const blockerId = publicId(row?.blocker_id, 120);
      const blockedId = publicId(row?.blocked_id, 120);
      if (blockerId && aliases.includes(blockerId) && blockedId) blocked.add(blockedId);
      if (blockedId && aliases.includes(blockedId) && blockerId) blocked.add(blockerId);
    }
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_blocks_read_failed', code: getErrorCode(error).slice(0, 180) }));
  }
  return blocked;
}

async function supabaseUserIdsAreBlocked(c: any, leftUserId: string, rightUserId: string): Promise<boolean> {
  const rightId = publicId(rightUserId, 120);
  if (!rightId) return false;
  const blocked = await supabaseBlockedUserIds(c, leftUserId);
  return blocked.has(rightId);
}

async function supabaseFollowingUserIds(c: any, viewerId: string, targetIds: string[]): Promise<Set<string>> {
  const aliases = await supabaseRelatedInteractionUserIds(c, viewerId);
  const cleanTargets = Array.from(new Set(targetIds.map((value) => publicId(value, 120)).filter(Boolean)));
  const following = new Set<string>();
  if (!aliases.length || !cleanTargets.length) return following;
  try {
    const rows = await supabaseAdminQueryRows(c, 'app_follows', {
      select: 'app_follower_id,app_following_id,status',
      filters: {
        app_follower_id: postgrestInFilter(aliases),
        app_following_id: postgrestInFilter(cleanTargets),
      },
      limit: Math.max(50, cleanTargets.length * aliases.length),
    });
    for (const row of rows) {
      if (cleanText(row?.status || 'active', 40) !== 'active') continue;
      const followingId = publicId(row?.app_following_id, 120);
      if (followingId) following.add(followingId);
    }
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_follows_read_failed', code: getErrorCode(error).slice(0, 180) }));
  }
  return following;
}

async function supabasePostCommentCounts(c: any, postRows: any[]): Promise<Map<string, number>> {
  const postIds = Array.from(new Set(postRows.map((row) => publicId(row?.legacy_post_id || row?.id, 120)).filter(Boolean)));
  const uuidIds = Array.from(new Set(postRows.map((row) => isUuidText(row?.id)).filter((value): value is string => !!value)));
  const counts = new Map<string, number>();
  for (const postId of postIds) counts.set(postId, 0);
  if (!postIds.length && !uuidIds.length) return counts;

  const addRows = (rows: any[]) => {
    for (const row of rows) {
      const status = cleanText(row?.status || 'active', 40);
      if (status === 'removed' || status === 'hidden') continue;
      const postId = publicId(row?.legacy_post_id || row?.post_id, 120);
      if (!postId) continue;
      counts.set(postId, (counts.get(postId) || 0) + 1);
    }
  };

  try {
    if (postIds.length) {
      addRows(await supabaseAdminQueryRows(c, 'post_comments', {
        select: 'legacy_post_id,post_id,status',
        filters: { legacy_post_id: postgrestInFilter(postIds) },
        limit: Math.max(1000, postIds.length * 300),
      }));
    }
    if (uuidIds.length) {
      addRows(await supabaseAdminQueryRows(c, 'post_comments', {
        select: 'legacy_post_id,post_id,status',
        filters: { post_id: postgrestInFilter(uuidIds) },
        limit: Math.max(1000, uuidIds.length * 300),
      }));
    }
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_comment_counts_failed', code: getErrorCode(error).slice(0, 180) }));
  }
  return counts;
}

async function supabasePostCommentCount(c: any, postId: string): Promise<number> {
  const rows = await supabasePostCommentCounts(c, [{ id: isUuidText(postId), legacy_post_id: postId }]);
  return rows.get(postId) || 0;
}

function supabaseCommentPayload(row: any, author: any, fallbackPostId: string, likedByMe = false) {
  const metadata = parseJsonObject(row?.metadata);
  const commentId = publicId(row?.legacy_comment_id || row?.id, 120);
  const appUserId = publicId(row?.app_user_id || author?.id, 120);
  const parentId = publicId((metadata as any).parent_legacy_id || row?.parent_id, 120);
  const likesCount = Math.max(0, Number((metadata as any).likes_count || 0));
  const pinnedAt = cleanText((metadata as any).pinned_at, 80) || null;
  return {
    id: commentId,
    supabase_comment_id: isUuidText(row?.id),
    user_id: appUserId,
    post_id: publicId(row?.legacy_post_id || row?.post_id || fallbackPostId, 120),
    parent_id: parentId || null,
    content: cleanMultilineText(row?.body, 1200),
    body: cleanMultilineText(row?.body, 1200),
    likes_count: likesCount,
    post_user_id: publicId((metadata as any).post_user_id, 120),
    liked_by_me: likedByMe,
    pinned_at: pinnedAt,
    is_pinned: !!pinnedAt,
    user_username: publicUsernameFor(author),
    user_full_name: author?.full_name,
    user_profile_image: safeMediaReference(author?.avatar_url),
    created_at: row?.legacy_created_at || row?.created_at,
    updated_at: row?.updated_at || row?.created_at,
  };
}

async function supabaseVisiblePostForComments(c: any, viewerId: string, postId: string) {
  const [post] = await supabaseReadVisiblePosts(c, viewerId, { postId, limit: 1 });
  return post || null;
}

function supabaseCommentPostFilter(post: any, postId: string): string {
  const legacyPostId = publicId(postId || post?.id, 120);
  const supabasePostId = isUuidText(post?.supabase_post_id || postId);
  const parts: string[] = [];
  if (legacyPostId) parts.push(`legacy_post_id.eq.${legacyPostId}`);
  if (supabasePostId) parts.push(`post_id.eq.${supabasePostId}`);
  return `(${parts.join(',')})`;
}

type SupabaseCommentIdentity = {
  requestedCommentId: string;
  legacyCommentId: string;
  commentUuid: string;
  legacyPostId: string;
  postUuid: string;
  metadata: Record<string, unknown>;
  row: any;
};

function supabaseCommentIdentityFromRow(row: any, requestedCommentId: string): SupabaseCommentIdentity {
  const requested = publicId(requestedCommentId, 120);
  const requestedUuid = isUuidText(requested);
  return {
    requestedCommentId: requested,
    legacyCommentId: publicId(row?.legacy_comment_id || (requestedUuid ? '' : requested), 120),
    commentUuid: isUuidText(row?.id) || requestedUuid || '',
    legacyPostId: publicId(row?.legacy_post_id, 120),
    postUuid: isUuidText(row?.post_id) || '',
    metadata: parseJsonObject(row?.metadata),
    row,
  };
}

function supabaseCommentRowOrFilter(identity: SupabaseCommentIdentity): string {
  const parts: string[] = [];
  if (identity.legacyCommentId) parts.push(`legacy_comment_id.eq.${identity.legacyCommentId}`);
  if (identity.commentUuid) parts.push(`id.eq.${identity.commentUuid}`);
  if (!parts.length && identity.requestedCommentId) parts.push(`legacy_comment_id.eq.${identity.requestedCommentId}`);
  return `(${parts.join(',')})`;
}

function supabaseCommentLikeOrFilter(identity: SupabaseCommentIdentity): string {
  const parts: string[] = [];
  if (identity.legacyCommentId) parts.push(`legacy_comment_id.eq.${identity.legacyCommentId}`);
  if (identity.commentUuid) parts.push(`comment_id.eq.${identity.commentUuid}`);
  if (!parts.length && identity.requestedCommentId) parts.push(`legacy_comment_id.eq.${identity.requestedCommentId}`);
  return `(${parts.join(',')})`;
}

async function supabaseResolveCommentIdentity(c: any, commentId: string): Promise<SupabaseCommentIdentity | null> {
  const cleanCommentId = publicId(commentId, 120);
  if (!cleanCommentId) return null;
  const rows = await supabaseAdminQueryRows(c, 'post_comments', {
    select: 'id,legacy_comment_id,legacy_post_id,post_id,app_user_id,user_id,body,status,metadata,created_at,updated_at,legacy_created_at',
    filters: {
      or: isUuidText(cleanCommentId)
        ? `(legacy_comment_id.eq.${cleanCommentId},id.eq.${cleanCommentId})`
        : `(legacy_comment_id.eq.${cleanCommentId})`,
    },
    limit: 1,
  });
  return rows[0] ? supabaseCommentIdentityFromRow(rows[0], cleanCommentId) : null;
}

async function supabaseViewerLikedCommentIds(c: any, commentRows: any[], userId: string): Promise<Set<string>> {
  const liked = new Set<string>();
  if (!commentRows.length) return liked;
  const legacyCommentIds = Array.from(new Set(commentRows.map((row) => publicId(row?.legacy_comment_id, 120)).filter(Boolean)));
  const commentUuids = Array.from(new Set(commentRows.map((row) => isUuidText(row?.id)).filter((value): value is string => !!value)));
  const orParts: string[] = [];
  if (legacyCommentIds.length) orParts.push(`legacy_comment_id.${postgrestInFilter(legacyCommentIds)}`);
  if (commentUuids.length) orParts.push(`comment_id.${postgrestInFilter(commentUuids)}`);
  if (!orParts.length) return liked;

  const addRows = (rows: any[]) => {
    for (const row of rows) {
      const legacyCommentId = publicId(row?.legacy_comment_id, 120);
      const commentUuid = isUuidText(row?.comment_id);
      if (legacyCommentId) liked.add(legacyCommentId);
      if (commentUuid) liked.add(commentUuid);
    }
  };

  try {
    const keys = await supabaseInteractionIdentityKeys(c, [userId]);
    if (keys.appUserIds.length) {
      addRows(await supabaseAdminSelectRows(c, 'post_comment_likes', {
        or: `(${orParts.join(',')})`,
        app_user_id: postgrestInFilter(keys.appUserIds),
      }, 'legacy_comment_id,comment_id', Math.max(1, commentRows.length * 2)));
    }
    if (keys.authUserIds.length) {
      addRows(await supabaseAdminSelectRows(c, 'post_comment_likes', {
        or: `(${orParts.join(',')})`,
        user_id: postgrestInFilter(keys.authUserIds),
      }, 'legacy_comment_id,comment_id', Math.max(1, commentRows.length * 2)));
    }
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) {
      console.warn(JSON.stringify({ event: 'supabase_comment_like_state_failed', code: getErrorCode(error).slice(0, 180) }));
    }
  }

  return liked;
}

async function supabaseViewerCommentLikeExists(c: any, identity: SupabaseCommentIdentity, userId: string): Promise<boolean> {
  try {
    const keys = await supabaseInteractionIdentityKeys(c, [userId]);
    if (keys.appUserIds.length) {
      const appRows = await supabaseAdminSelectRows(c, 'post_comment_likes', {
        or: supabaseCommentLikeOrFilter(identity),
        app_user_id: postgrestInFilter(keys.appUserIds),
      }, 'id', 1);
      if (appRows.length > 0) return true;
    }
    if (keys.authUserIds.length) {
      const authRows = await supabaseAdminSelectRows(c, 'post_comment_likes', {
        or: supabaseCommentLikeOrFilter(identity),
        user_id: postgrestInFilter(keys.authUserIds),
      }, 'id', 1);
      return authRows.length > 0;
    }
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) throw error;
  }
  return false;
}

async function supabaseDeleteCommentLikesForViewer(c: any, identity: SupabaseCommentIdentity, userId: string) {
  const keys = await supabaseInteractionIdentityKeys(c, [userId]);
  if (keys.appUserIds.length) {
    await supabaseAdminDeleteRows(c, 'post_comment_likes', {
      or: supabaseCommentLikeOrFilter(identity),
      app_user_id: postgrestInFilter(keys.appUserIds),
    });
  }
  if (keys.authUserIds.length) {
    await supabaseAdminDeleteRows(c, 'post_comment_likes', {
      or: supabaseCommentLikeOrFilter(identity),
      user_id: postgrestInFilter(keys.authUserIds),
    });
  }
}

async function supabaseCommentLikeActorCount(c: any, identity: SupabaseCommentIdentity): Promise<number> {
  let rows: any[] = [];
  try {
    rows = await supabaseAdminSelectRows(c, 'post_comment_likes', {
      or: supabaseCommentLikeOrFilter(identity),
    }, 'app_user_id,user_id,legacy_comment_id,comment_id', 10000);
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) throw error;
    return Math.max(0, Number((identity.metadata as any).likes_count || 0));
  }
  const appUserIds = rows.map((row) => publicId(row?.app_user_id, 120)).filter(Boolean);
  const appToAuth = await supabaseAuthUserIdMapForAppUserIds(c, appUserIds);
  const appToIdentityActor = await supabaseAccountIdentityActorKeyMap(c, appUserIds);
  const actors = new Set<string>();
  for (const row of rows) {
    const appUserId = publicId(row?.app_user_id, 120);
    const authUserId = isUuidText(row?.user_id) || appToAuth.get(appUserId) || '';
    const actor = cleanText(authUserId || appToIdentityActor.get(appUserId) || appUserId, 160);
    if (actor) actors.add(actor);
  }
  return actors.size;
}

async function supabasePatchCommentMetadata(c: any, identity: SupabaseCommentIdentity, patch: Record<string, unknown>) {
  const metadata = { ...identity.metadata, ...patch };
  await supabaseAdminPatchRows(c, 'post_comments', { or: supabaseCommentRowOrFilter(identity) }, {
    metadata,
    updated_at: now(),
  });
  identity.metadata = metadata;
}

async function supabaseSetCommentLike(c: any, commentId: string, userId: string, requested: boolean | null) {
  const identity = await supabaseResolveCommentIdentity(c, commentId);
  if (!identity || cleanText(identity.row?.status || 'active', 40) !== 'active') {
    return { status: 404 as const, body: { detail: 'Comment not found' } };
  }
  const postKey = identity.legacyPostId || identity.postUuid;
  const visiblePost = await supabaseVisiblePostForComments(c, userId, postKey);
  if (!visiblePost) return { status: 404 as const, body: { detail: 'Comment not found' } };

  let nextLiked = requested;
  if (nextLiked === null) {
    nextLiked = !(await supabaseViewerCommentLikeExists(c, identity, userId));
  }

  await supabaseDeleteCommentLikesForViewer(c, identity, userId);
  if (nextLiked) {
    const authUserId = await supabaseAuthUserIdForAppUserId(c, userId);
    const row: any = {
      legacy_comment_id: identity.legacyCommentId || identity.requestedCommentId,
      app_user_id: publicId(userId, 120),
      metadata: { source: 'cloudflare_worker_primary' },
      legacy_created_at: now(),
    };
    if (identity.commentUuid) row.comment_id = identity.commentUuid;
    if (authUserId) row.user_id = authUserId;
    await supabaseAdminUpsert(c, 'post_comment_likes', [row], 'legacy_comment_id,app_user_id');
  }

  const likesCount = await supabaseCommentLikeActorCount(c, identity);
  await supabasePatchCommentMetadata(c, identity, { likes_count: likesCount });
  return { status: 200 as const, body: { liked: !!nextLiked, likes_count: likesCount } };
}

async function supabaseSetCommentPinned(c: any, commentId: string, userId: string, requested: boolean | null) {
  const identity = await supabaseResolveCommentIdentity(c, commentId);
  if (!identity || cleanText(identity.row?.status || 'active', 40) !== 'active') {
    return { status: 404 as const, body: { detail: 'Comment not found' } };
  }
  const postKey = identity.legacyPostId || identity.postUuid;
  const visiblePost = await supabaseVisiblePostForComments(c, userId, postKey);
  if (!visiblePost) return { status: 404 as const, body: { detail: 'Comment not found' } };
  if (publicId(visiblePost?.user_id, 120) !== publicId(userId, 120)) {
    return { status: 403 as const, body: { detail: 'Only the creator can pin comments.' } };
  }

  const shouldPin = requested === null ? true : requested;
  const pinnedAt = shouldPin ? now() : null;
  if (shouldPin) {
    const rows = await supabaseAdminQueryRows(c, 'post_comments', {
      select: 'id,legacy_comment_id,legacy_post_id,post_id,metadata,status',
      filters: {
        or: supabaseCommentPostFilter(visiblePost, postKey),
        status: postgrestEqFilter('active'),
      },
      limit: 500,
    });
    for (const row of rows) {
      const rowIdentity = supabaseCommentIdentityFromRow(row, publicId(row?.legacy_comment_id || row?.id, 120));
      const isCurrent = (rowIdentity.legacyCommentId && rowIdentity.legacyCommentId === identity.legacyCommentId)
        || (rowIdentity.commentUuid && rowIdentity.commentUuid === identity.commentUuid);
      await supabasePatchCommentMetadata(c, rowIdentity, { pinned_at: isCurrent ? pinnedAt : null });
    }
  } else {
    await supabasePatchCommentMetadata(c, identity, { pinned_at: null });
  }
  return { status: 200 as const, body: { pinned: shouldPin, pinned_at: pinnedAt } };
}

async function supabaseCreatePostComment(c: any, input: {
  postId: string;
  userId: string;
  content: string;
  parentId?: string | null;
  clientRequestId?: string;
}) {
  const visiblePost = await supabaseVisiblePostForComments(c, input.userId, input.postId);
  if (!visiblePost) return { status: 404 as const, body: { detail: 'Post not found' } };

  const nowIso = now();
  const userRows = await supabaseUsersByAnyIds(c, [input.userId]);
  const user = userRows.get(input.userId) || await getSupabaseSessionUserByAnyId(c, input.userId);
  let parent: any = null;
  if (input.parentId) {
    const parentRows = await supabaseAdminQueryRows(c, 'post_comments', {
      select: 'id,legacy_comment_id,app_user_id,user_id,status,metadata',
      filters: {
        or: isUuidText(input.parentId)
          ? `(legacy_comment_id.eq.${input.parentId},id.eq.${input.parentId})`
          : `(legacy_comment_id.eq.${input.parentId})`,
        status: postgrestEqFilter('active'),
      },
      limit: 1,
    });
    parent = parentRows[0] || null;
    if (!parent) return { status: 404 as const, body: { detail: 'Comment to reply to was not found.' } };
  }

  const duplicateRows = await supabaseAdminQueryRows(c, 'post_comments', {
    select: 'id,legacy_comment_id,legacy_post_id,app_user_id,user_id,body,status,metadata,legacy_created_at,created_at,updated_at',
    filters: {
      legacy_post_id: postgrestEqFilter(input.postId),
      app_user_id: postgrestEqFilter(input.userId),
      body: postgrestEqFilter(input.content),
      created_at: `gte.${new Date(Date.now() - 30_000).toISOString()}`,
    },
    order: 'created_at.desc',
    limit: 1,
  }).catch(() => []);
  if (duplicateRows[0]) {
    return {
      status: 200 as const,
      body: {
        ...supabaseCommentPayload(duplicateRows[0], user, input.postId),
        post_comments_count: await supabasePostCommentCount(c, input.postId),
        idempotent_replay: true,
      },
    };
  }

  const id = uuid();
  const authUserId = await supabaseAuthUserIdForAppUserId(c, input.userId);
  const parentUuid = isUuidText(parent?.id);
  const row: any = {
    id,
    legacy_comment_id: id,
    legacy_post_id: input.postId,
    post_id: isUuidText(visiblePost?.supabase_post_id || ''),
    app_user_id: input.userId,
    user_id: authUserId || null,
    parent_id: parentUuid || null,
    body: input.content,
    status: 'active',
    metadata: {
      source: 'cloudflare_worker_primary',
      parent_legacy_id: publicId(input.parentId, 120),
      client_request_id: cleanText(input.clientRequestId, 160),
      post_user_id: publicId(visiblePost?.user_id, 120),
      likes_count: 0,
    },
    legacy_created_at: nowIso,
    created_at: nowIso,
    updated_at: nowIso,
  };
  await supabaseAdminUpsert(c, 'post_comments', [row], 'legacy_comment_id');
  const engagement = await getSupabasePostEngagementState(c, input.postId, input.userId);
  return {
    status: 200 as const,
    body: {
      ...supabaseCommentPayload(row, user, input.postId),
      post_user_id: visiblePost.user_id,
      post_comments_count: engagement.comments_count,
    },
  };
}

async function supabaseReadPostComments(c: any, postId: string, userId: string, limit: number) {
  const visiblePost = await supabaseVisiblePostForComments(c, userId, postId);
  if (!visiblePost) return { status: 404 as const, body: { detail: 'Post not found' } };
  const rows = await supabaseAdminQueryRows(c, 'post_comments', {
    select: 'id,post_id,user_id,parent_id,body,status,metadata,created_at,updated_at,legacy_comment_id,legacy_post_id,app_user_id,legacy_created_at',
    filters: {
      or: supabaseCommentPostFilter(visiblePost, postId),
      status: postgrestEqFilter('active'),
    },
    order: 'legacy_created_at.asc.nullslast,created_at.asc',
    limit,
  });
  const userIds = rows.flatMap((row) => [publicId(row?.app_user_id, 120), isUuidText(row?.user_id) || '']).filter(Boolean);
  const authors = await supabaseUsersByAnyIds(c, userIds);
  const likedCommentIds = await supabaseViewerLikedCommentIds(c, rows, userId);
  const comments = rows.map((row) => {
    const author = authors.get(publicId(row?.app_user_id, 120)) || authors.get(isUuidText(row?.user_id) || '') || {};
    const legacyCommentId = publicId(row?.legacy_comment_id, 120);
    const commentUuid = isUuidText(row?.id);
    const likedByMe = !!((legacyCommentId && likedCommentIds.has(legacyCommentId)) || (commentUuid && likedCommentIds.has(commentUuid)));
    return supabaseCommentPayload(row, author, postId, likedByMe);
  });
  comments.sort((a, b) => {
    if (a.is_pinned !== b.is_pinned) return a.is_pinned ? -1 : 1;
    const aParent = String(a.parent_id || a.id);
    const bParent = String(b.parent_id || b.id);
    if (aParent !== bParent) return aParent.localeCompare(bParent);
    return (Date.parse(String(a.created_at || '')) || 0) - (Date.parse(String(b.created_at || '')) || 0);
  });
  return { status: 200 as const, body: comments };
}

async function supabaseUpdateCommentStatus(c: any, commentId: string, userId: string, status: 'removed' | 'hidden') {
  const rows = await supabaseAdminQueryRows(c, 'post_comments', {
    select: 'id,legacy_comment_id,legacy_post_id,post_id,app_user_id,user_id,status,metadata',
    filters: {
      or: isUuidText(commentId)
        ? `(legacy_comment_id.eq.${commentId},id.eq.${commentId})`
        : `(legacy_comment_id.eq.${commentId})`,
    },
    limit: 1,
  });
  const comment = rows[0];
  if (!comment || cleanText(comment.status || 'active', 40) !== 'active') return { status: 404 as const, body: { detail: 'Comment not found' } };
  const identity = supabaseCommentIdentityFromRow(comment, commentId);
  const commentOwner = publicId(comment.app_user_id, 120);
  const metadata = parseJsonObject(comment.metadata);
  const postOwner = publicId((metadata as any).post_user_id, 120);
  if (status === 'removed' && commentOwner !== userId) return { status: 403 as const, body: { detail: 'Not your comment' } };
  if (status === 'hidden' && postOwner !== userId) return { status: 403 as const, body: { detail: 'Only the creator can hide comments.' } };
  const patch = {
    status,
    metadata: {
      ...metadata,
      hidden_by_user_id: status === 'hidden' ? userId : undefined,
      removed_reason: status === 'hidden' ? 'Hidden by creator' : 'Deleted by commenter',
      removed_at: now(),
      pinned_at: null,
    },
    updated_at: now(),
  };
  await supabaseAdminPatchRows(c, 'post_comments', { or: supabaseCommentRowOrFilter(identity) }, patch);
  const postId = publicId(comment.legacy_post_id || comment.post_id, 120);
  const engagement = await getSupabasePostEngagementState(c, postId, userId);
  return { status: 200 as const, body: status === 'hidden' ? { hidden: true, comments_count: engagement.comments_count } : { deleted: true, comments_count: engagement.comments_count } };
}

async function supabaseUserByAnyId(c: any, userId: string): Promise<any | null> {
  const rows = await supabaseUsersByAnyIds(c, [userId]);
  return rows.get(publicId(userId, 120)) || rows.get(isUuidText(userId) || '') || null;
}

async function supabaseFollowStats(c: any, userId: string) {
  const cleanUserId = publicId(userId, 120);
  if (!cleanUserId) return { followers_count: 0, following_count: 0 };
  const [followers, following] = await Promise.all([
    supabaseAdminQueryRows(c, 'app_follows', {
      select: 'app_follower_id,status',
      filters: { app_following_id: postgrestEqFilter(cleanUserId), status: postgrestEqFilter('active') },
      limit: 10000,
    }).catch(() => []),
    supabaseAdminQueryRows(c, 'app_follows', {
      select: 'app_following_id,status',
      filters: { app_follower_id: postgrestEqFilter(cleanUserId), status: postgrestEqFilter('active') },
      limit: 10000,
    }).catch(() => []),
  ]);
  return {
    followers_count: followers.length,
    following_count: following.length,
  };
}

async function supabaseBlockPair(c: any, firstUserId: string, secondUserId: string): Promise<any | null> {
  const first = publicId(firstUserId, 120);
  const second = publicId(secondUserId, 120);
  if (!first || !second || first === second) return null;
  const [forward, reverse] = await Promise.all([
    supabaseAdminQueryRows(c, 'app_blocks', {
      select: 'id,blocker_id,blocked_id,created_at',
      filters: { blocker_id: postgrestEqFilter(first), blocked_id: postgrestEqFilter(second) },
      limit: 1,
    }).catch(() => []),
    supabaseAdminQueryRows(c, 'app_blocks', {
      select: 'id,blocker_id,blocked_id,created_at',
      filters: { blocker_id: postgrestEqFilter(second), blocked_id: postgrestEqFilter(first) },
      limit: 1,
    }).catch(() => []),
  ]);
  return forward[0] || reverse[0] || null;
}

async function supabaseIsFollowing(c: any, followerId: string, followingId: string): Promise<boolean> {
  const follower = publicId(followerId, 120);
  const following = publicId(followingId, 120);
  if (!follower || !following || follower === following) return false;
  const rows = await supabaseAdminQueryRows(c, 'app_follows', {
    select: 'app_follower_id',
    filters: {
      app_follower_id: postgrestEqFilter(follower),
      app_following_id: postgrestEqFilter(following),
      status: postgrestEqFilter('active'),
    },
    limit: 1,
  }).catch(() => []);
  return rows.length > 0;
}

async function supabasePublicUserPayload(c: any, viewerId: string, targetId: string) {
  const target = await supabaseUserByAnyId(c, targetId);
  if (!target || supabaseUserStatus(target) !== 'active') return { status: 404 as const, body: { detail: 'User not found' } };
  const targetAppId = publicId(target.id, 120);
  const [followStats, isFollowing, block] = await Promise.all([
    supabaseFollowStats(c, targetAppId),
    viewerId && viewerId !== targetAppId ? supabaseIsFollowing(c, viewerId, targetAppId) : Promise.resolve(false),
    viewerId && viewerId !== targetAppId ? supabaseBlockPair(c, viewerId, targetAppId) : Promise.resolve(null),
  ]);
  const viewerHasBlocked = publicId(block?.blocker_id, 120) === viewerId && publicId(block?.blocked_id, 120) === targetAppId;
  const viewerBlockedBy = publicId(block?.blocker_id, 120) === targetAppId && publicId(block?.blocked_id, 120) === viewerId;
  const counts = parseJsonObject(target.counts);
  const safe = safeUserPayload({
    id: targetAppId,
    username: target.username,
    full_name: target.full_name,
    profile_image: target.avatar_url,
    cover_image: target.cover_url,
    bio: target.bio,
    city: target.city,
    is_private: target.is_private ? 1 : 0,
    is_verified: target.is_verified ? 1 : 0,
    followers_count: followStats.followers_count,
    following_count: followStats.following_count,
    posts_count: Number((counts as any).posts_count || 0),
  });
  const privacyLocked = !!target.is_private && viewerId !== targetAppId && !isFollowing;
  if (viewerBlockedBy || privacyLocked) {
    return {
      status: 200 as const,
      body: {
        id: safe.id,
        username: safe.username,
        full_name: safe.full_name,
        profile_image: safe.profile_image,
        followers_count: safe.followers_count,
        following_count: safe.following_count,
        posts_count: safe.posts_count,
        is_following: isFollowing,
        viewer_has_blocked: viewerHasBlocked,
        viewer_blocked_by: viewerBlockedBy,
        is_private: true,
        privacy_locked: true,
      },
    };
  }
  return { status: 200 as const, body: { ...safe, is_following: isFollowing, viewer_has_blocked: viewerHasBlocked, viewer_blocked_by: viewerBlockedBy } };
}

async function supabaseSetFollowState(c: any, followerId: string, followingId: string, requested: boolean | null) {
  const inputFollower = publicId(followerId, 120);
  const inputFollowing = publicId(followingId, 120);
  if (!inputFollower || !inputFollowing) return { status: 400 as const, body: { detail: 'Cannot follow yourself' } };
  const [followerRow, target] = await Promise.all([
    supabaseUserByAnyId(c, inputFollower),
    supabaseUserByAnyId(c, inputFollowing),
  ]);
  const follower = publicId(followerRow?.id || inputFollower, 120);
  const following = publicId(target?.id || inputFollowing, 120);
  if (!follower || !following || follower === following) return { status: 400 as const, body: { detail: 'Cannot follow yourself' } };
  if (!followerRow || supabaseUserStatus(followerRow) !== 'active') return { status: 403 as const, body: { detail: 'Your account cannot follow profiles right now.' } };
  if (!target || supabaseUserStatus(target) !== 'active') return { status: 404 as const, body: { detail: 'User not found' } };
  if (await supabaseBlockPair(c, follower, following)) return { status: 403 as const, body: { detail: 'You cannot follow this profile.' } };
  const wasFollowing = await supabaseIsFollowing(c, follower, following);
  const nextFollowing = requested === null ? !wasFollowing : requested;
  if (nextFollowing) {
    const [followerAuth, followingAuth] = await Promise.all([
      supabaseAuthUserIdForAppUserId(c, follower),
      supabaseAuthUserIdForAppUserId(c, following),
    ]);
    await supabaseAdminUpsert(c, 'app_follows', [{
      app_follower_id: follower,
      app_following_id: following,
      follower_id: followerAuth || null,
      following_id: followingAuth || null,
      status: 'active',
      metadata: { source: 'cloudflare_worker_primary' },
      legacy_created_at: now(),
      updated_at: now(),
    }], 'app_follower_id,app_following_id');
  } else {
    await supabaseAdminDeleteRows(c, 'app_follows', {
      app_follower_id: postgrestEqFilter(follower),
      app_following_id: postgrestEqFilter(following),
    });
  }
  const [followerStats, followingStats] = await Promise.all([
    supabaseFollowStats(c, follower),
    supabaseFollowStats(c, following),
  ]);
  return {
    status: 200 as const,
    body: {
      following: nextFollowing,
      following_count: followerStats.following_count,
      followers_count: followingStats.followers_count,
    },
  };
}

async function supabaseFriendshipExists(c: any, userId: string, friendId: string): Promise<boolean> {
  const user = publicId(userId, 120);
  const friend = publicId(friendId, 120);
  if (!user || !friend || user === friend) return false;
  const rows = await supabaseAdminQueryRows(c, 'app_friendships', {
    select: 'user_id',
    filters: {
      user_id: postgrestEqFilter(user),
      friend_id: postgrestEqFilter(friend),
    },
    limit: 1,
  }).catch(() => []);
  return rows.length > 0;
}

async function supabaseFriendRequestRows(c: any, filters: Record<string, string>, limit = 1): Promise<any[]> {
  return supabaseAdminQueryRows(c, 'app_friend_requests', {
    select: '*',
    filters,
    order: 'created_at.desc',
    limit,
  }).catch(() => []);
}

async function supabaseCreateFriendRequest(c: any, fromUserId: string, toUserId: string) {
  const [fromRow, toRow] = await Promise.all([
    supabaseUserByAnyId(c, fromUserId),
    supabaseUserByAnyId(c, toUserId),
  ]);
  const from = publicId(fromRow?.id || fromUserId, 120);
  const to = publicId(toRow?.id || toUserId, 120);
  if (!from || !to || from === to) return { status: 400 as const, body: { detail: 'Cannot friend yourself' } };
  if (!fromRow || supabaseUserStatus(fromRow) !== 'active') return { status: 403 as const, body: { detail: 'Your account cannot add friends right now.' } };
  if (!toRow || supabaseUserStatus(toRow) !== 'active') return { status: 404 as const, body: { detail: 'User not found' } };
  if (await supabaseBlockPair(c, from, to)) return { status: 403 as const, body: { detail: 'You cannot add this profile.' } };
  if (await supabaseFriendshipExists(c, from, to)) return { status: 400 as const, body: { detail: 'Already friends', status: 'friends' } };

  const [outgoing, incoming] = await Promise.all([
    supabaseFriendRequestRows(c, { from_user_id: postgrestEqFilter(from), to_user_id: postgrestEqFilter(to) }, 1),
    supabaseFriendRequestRows(c, { from_user_id: postgrestEqFilter(to), to_user_id: postgrestEqFilter(from), status: postgrestEqFilter('pending') }, 1),
  ]);
  if (incoming[0]) return { status: 400 as const, body: { detail: 'This user already sent you a request.', status: 'request_received', request_id: publicId(incoming[0].id, 120) } };
  const existing = outgoing[0];
  if (existing?.status === 'pending') return { status: 400 as const, body: { detail: 'Already sent', status: 'pending', request_id: publicId(existing.id, 120) } };

  const id = publicId(existing?.id, 120) || uuid();
  const ts = now();
  await supabaseAdminUpsert(c, 'app_friend_requests', [{
    id,
    from_user_id: from,
    to_user_id: to,
    status: 'pending',
    metadata: { source: 'cloudflare_worker_primary' },
    updated_at: ts,
    created_at: existing?.created_at || ts,
  }], 'from_user_id,to_user_id');
  return { status: 200 as const, body: { id, status: 'pending' } };
}

async function supabaseAcceptFriendRequest(c: any, userId: string, requestId: string) {
  const uid = publicId(userId, 120);
  const rid = publicId(requestId, 120);
  const rows = await supabaseFriendRequestRows(c, {
    id: postgrestEqFilter(rid),
    to_user_id: postgrestEqFilter(uid),
    status: postgrestEqFilter('pending'),
  }, 1);
  const request = rows[0];
  if (!request) return { status: 404 as const, body: { detail: 'Not found' } };
  const from = publicId(request.from_user_id, 120);
  const ts = now();
  await supabaseAdminPatchRows(c, 'app_friend_requests', { id: postgrestEqFilter(rid) }, { status: 'accepted', updated_at: ts });
  await supabaseAdminUpsert(c, 'app_friendships', [
    { user_id: uid, friend_id: from, metadata: { source: 'friend_request', request_id: rid }, created_at: ts, updated_at: ts },
    { user_id: from, friend_id: uid, metadata: { source: 'friend_request', request_id: rid }, created_at: ts, updated_at: ts },
  ], 'user_id,friend_id');
  return { status: 200 as const, body: { accepted: true } };
}

async function supabaseRejectFriendRequest(c: any, userId: string, requestId: string) {
  const uid = publicId(userId, 120);
  const rid = publicId(requestId, 120);
  const rows = await supabaseFriendRequestRows(c, {
    id: postgrestEqFilter(rid),
    to_user_id: postgrestEqFilter(uid),
    status: postgrestEqFilter('pending'),
  }, 1);
  if (!rows[0]) return { status: 404 as const, body: { detail: 'Request not found' } };
  await supabaseAdminPatchRows(c, 'app_friend_requests', { id: postgrestEqFilter(rid) }, { status: 'rejected', updated_at: now() });
  return { status: 200 as const, body: { rejected: true } };
}

async function supabaseFriendRequestsPayload(c: any, userId: string) {
  const uid = publicId(userId, 120);
  const rows = await supabaseFriendRequestRows(c, {
    to_user_id: postgrestEqFilter(uid),
    status: postgrestEqFilter('pending'),
  }, 80);
  const fromIds = Array.from(new Set(rows.map((row) => publicId(row.from_user_id, 120)).filter(Boolean)));
  const users = await supabaseUsersByAnyIds(c, fromIds);
  return rows.map((row) => {
    const sender = users.get(publicId(row.from_user_id, 120)) || {};
    return {
      id: publicId(row.id, 120),
      from_user_id: publicId(row.from_user_id, 120),
      to_user_id: publicId(row.to_user_id, 120),
      status: cleanText(row.status, 40) || 'pending',
      created_at: row.created_at,
      username: publicUsernameFor({ username: sender?.username }),
      full_name: cleanText(sender?.full_name, 160),
      profile_image: safeMediaReference(sender?.avatar_url),
    };
  });
}

async function supabaseFriendsPayload(c: any, userId: string) {
  const uid = publicId(userId, 120);
  const rows = await supabaseAdminQueryRows(c, 'app_friendships', {
    select: 'friend_id,created_at',
    filters: { user_id: postgrestEqFilter(uid) },
    order: 'created_at.desc',
    limit: 200,
  }).catch(() => []);
  const friendIds = Array.from(new Set(rows.map((row) => publicId(row.friend_id, 120)).filter(Boolean)));
  const users = await supabaseUsersByAnyIds(c, friendIds);
  return friendIds.map((friendId) => {
    const user = users.get(friendId) || {};
    return safeUserPayload({
      id: friendId,
      username: user?.username,
      full_name: user?.full_name,
      profile_image: user?.avatar_url,
      bio: user?.bio,
    });
  });
}

async function supabaseFriendStatus(c: any, viewerId: string, otherUserId: string) {
  const viewerRow = await supabaseUserByAnyId(c, viewerId);
  const otherRow = await supabaseUserByAnyId(c, otherUserId);
  const viewer = publicId(viewerRow?.id || viewerId, 120);
  const other = publicId(otherRow?.id || otherUserId, 120);
  if (!viewer || !other || viewer === other || !otherRow) return { status: 'none' };
  if (await supabaseFriendshipExists(c, viewer, other)) return { status: 'friends' };
  const [sent, received] = await Promise.all([
    supabaseFriendRequestRows(c, { from_user_id: postgrestEqFilter(viewer), to_user_id: postgrestEqFilter(other), status: postgrestEqFilter('pending') }, 1),
    supabaseFriendRequestRows(c, { from_user_id: postgrestEqFilter(other), to_user_id: postgrestEqFilter(viewer), status: postgrestEqFilter('pending') }, 1),
  ]);
  if (sent[0]) return { status: 'request_sent', request_id: publicId(sent[0].id, 120) };
  if (received[0]) return { status: 'request_received', request_id: publicId(received[0].id, 120) };
  return { status: 'none' };
}

async function supabaseRemoveFriend(c: any, userId: string, otherUserId: string) {
  const viewerRow = await supabaseUserByAnyId(c, userId);
  const otherRow = await supabaseUserByAnyId(c, otherUserId);
  const viewer = publicId(viewerRow?.id || userId, 120);
  const other = publicId(otherRow?.id || otherUserId, 120);
  if (!viewer || !other || viewer === other) return { removed: true };
  await Promise.all([
    supabaseAdminDeleteRows(c, 'app_friendships', { user_id: postgrestEqFilter(viewer), friend_id: postgrestEqFilter(other) }).catch(() => undefined),
    supabaseAdminDeleteRows(c, 'app_friendships', { user_id: postgrestEqFilter(other), friend_id: postgrestEqFilter(viewer) }).catch(() => undefined),
  ]);
  return { removed: true };
}

async function supabaseBlockUser(c: any, blockerId: string, blockedId: string) {
  const inputBlocker = publicId(blockerId, 120);
  const inputBlocked = publicId(blockedId, 120);
  if (!inputBlocker || !inputBlocked) return { status: 400 as const, body: { detail: 'You cannot block yourself.' } };
  const [blockerRow, target] = await Promise.all([
    supabaseUserByAnyId(c, inputBlocker),
    supabaseUserByAnyId(c, inputBlocked),
  ]);
  const blocker = publicId(blockerRow?.id || inputBlocker, 120);
  const blocked = publicId(target?.id || inputBlocked, 120);
  if (!blocker || !blocked || blocker === blocked) return { status: 400 as const, body: { detail: 'You cannot block yourself.' } };
  if (!blockerRow || supabaseUserStatus(blockerRow) !== 'active') return { status: 403 as const, body: { detail: 'Your account cannot block profiles right now.' } };
  if (!target) return { status: 404 as const, body: { detail: 'User not found' } };
  await supabaseAdminUpsert(c, 'app_blocks', [{
    id: `${blocker}:${blocked}`,
    blocker_id: blocker,
    blocked_id: blocked,
    metadata: { source: 'cloudflare_worker_primary' },
    legacy_created_at: now(),
    updated_at: now(),
  }], 'id');
  const safetyReportCreatedAt = now();
  await supabaseAdminUpsert(c, 'app_reports', [{
    id: `block:${blocker}:${blocked}`,
    reporter_id: blocker,
    target_type: 'user',
    target_id: blocked,
    target_owner_user_id: blocked,
    reason: 'blocked_user',
    details: 'User blocked from a Captro safety control.',
    status: 'open',
    priority: 'normal',
    metadata: {
      source: 'captro_block_user_flow',
      block_id: `${blocker}:${blocked}`,
      reviewer_note: 'Created automatically so developer moderation staff can review block-only abuse signals.',
    },
    legacy_created_at: safetyReportCreatedAt,
    legacy_updated_at: safetyReportCreatedAt,
    created_at: safetyReportCreatedAt,
    updated_at: safetyReportCreatedAt,
  }], 'id').catch((error) => {
    console.warn(JSON.stringify({ event: 'supabase_block_report_enqueue_failed', code: getErrorCode(error).slice(0, 180) }));
  });
  await Promise.all([
    supabaseAdminDeleteRows(c, 'app_follows', { app_follower_id: postgrestEqFilter(blocker), app_following_id: postgrestEqFilter(blocked) }).catch(() => undefined),
    supabaseAdminDeleteRows(c, 'app_follows', { app_follower_id: postgrestEqFilter(blocked), app_following_id: postgrestEqFilter(blocker) }).catch(() => undefined),
  ]);
  await logSecurityEvent(c, 'user_blocked', blocker, { blocked_id: blocked });
  return { status: 200 as const, body: { blocked: true } };
}

async function supabaseUnblockUser(c: any, blockerId: string, blockedId: string) {
  const blockerRow = await supabaseUserByAnyId(c, blockerId).catch(() => null);
  const blockedRow = await supabaseUserByAnyId(c, blockedId).catch(() => null);
  const blocker = publicId(blockerRow?.id || blockerId, 120);
  const blocked = publicId(blockedRow?.id || blockedId, 120);
  if (!blocker || !blocked) return { status: 400 as const, body: { detail: 'Invalid user.' } };
  await supabaseAdminDeleteRows(c, 'app_blocks', {
    blocker_id: postgrestEqFilter(blocker),
    blocked_id: postgrestEqFilter(blocked),
  });
  return { status: 200 as const, body: { blocked: false } };
}

async function supabaseListBlocks(c: any, userId: string) {
  const blocker = publicId(userId, 120);
  const rows = await supabaseAdminQueryRows(c, 'app_blocks', {
    select: 'blocked_id,created_at',
    filters: { blocker_id: postgrestEqFilter(blocker) },
    order: 'created_at.desc',
    limit: 100,
  });
  const blockedIds = rows.map((row) => publicId(row?.blocked_id, 120)).filter(Boolean);
  const users = await supabaseUsersByAnyIds(c, blockedIds);
  return rows.map((row) => {
    const blockedId = publicId(row?.blocked_id, 120);
    const user = users.get(blockedId) || {};
    return {
      blocked_id: blockedId,
      created_at: row.created_at,
      user: safeUserPayload({ id: blockedId, username: user.username, full_name: user.full_name, profile_image: user.avatar_url }),
    };
  });
}

async function supabaseViewerInteractionPostIds(c: any, userId: string, kind: 'like' | 'save', input: {
  collection?: string;
  limit?: number;
  offset?: number;
} = {}): Promise<string[]> {
  const aliases = await supabaseRelatedInteractionUserIds(c, userId);
  const keys = await supabaseInteractionIdentityKeys(c, aliases);
  const collection = cleanText(input.collection, 80);
  const rows: any[] = [];
  const select = 'legacy_post_id,post_id,collection,created_at,legacy_created_at,app_user_id,user_id';
  const pageLimit = clampNumber(input.limit || 40, 1, 100, 40);
  const offset = Math.max(0, Math.round(Number(input.offset || 0)));
  const queryLimit = Math.max(100, pageLimit + offset + 40);
  const appendRows = async (filters: Record<string, string>) => {
    if (collection) filters.collection = postgrestEqFilter(collection);
    rows.push(...await supabaseAdminQueryRows(c, 'app_post_interactions', {
      select,
      filters,
      order: 'created_at.desc.nullslast,legacy_created_at.desc.nullslast',
      limit: queryLimit,
    }));
  };

  if (keys.appUserIds.length) {
    await appendRows({
      app_user_id: postgrestInFilter(keys.appUserIds),
      kind: postgrestEqFilter(kind),
    });
  }
  if (keys.authUserIds.length) {
    await appendRows({
      user_id: postgrestInFilter(keys.authUserIds),
      kind: postgrestEqFilter(kind),
    });
  }

  rows.sort((a, b) => {
    const aTime = Date.parse(String(a?.created_at || a?.legacy_created_at || '')) || 0;
    const bTime = Date.parse(String(b?.created_at || b?.legacy_created_at || '')) || 0;
    return bTime - aTime;
  });
  const seen = new Set<string>();
  return rows
    .map((row) => publicId(row?.legacy_post_id || row?.post_id, 120))
    .filter((postId) => !!postId && !seen.has(postId) && seen.add(postId))
    .slice(offset, offset + pageLimit);
}

async function supabaseViewerSaveCollectionCounts(c: any, userId: string): Promise<Array<{ collection: string; count: number }>> {
  const aliases = await supabaseRelatedInteractionUserIds(c, userId);
  const keys = await supabaseInteractionIdentityKeys(c, aliases);
  const rows: any[] = [];
  const select = 'legacy_post_id,post_id,collection,app_user_id,user_id';
  const appendRows = async (filters: Record<string, string>) => {
    rows.push(...await supabaseAdminQueryRows(c, 'app_post_interactions', {
      select,
      filters,
      order: 'created_at.desc.nullslast,legacy_created_at.desc.nullslast',
      limit: 10000,
    }));
  };

  if (keys.appUserIds.length) {
    await appendRows({
      app_user_id: postgrestInFilter(keys.appUserIds),
      kind: postgrestEqFilter('save'),
    });
  }
  if (keys.authUserIds.length) {
    await appendRows({
      user_id: postgrestInFilter(keys.authUserIds),
      kind: postgrestEqFilter('save'),
    });
  }

  const byCollection = new Map<string, Set<string>>();
  for (const row of rows) {
    const postId = publicId(row?.legacy_post_id || row?.post_id, 120);
    if (!postId) continue;
    const collection = cleanText(row?.collection || 'saved', 80) || 'saved';
    const posts = byCollection.get(collection) || new Set<string>();
    posts.add(postId);
    byCollection.set(collection, posts);
  }

  return Array.from(byCollection.entries())
    .map(([collection, posts]) => ({ collection, count: posts.size }))
    .sort((a, b) => a.collection.localeCompare(b.collection));
}

function supabaseAppPostMedia(row: any) {
  const metadata = parseJsonObject(row?.metadata);
  const fallbackImage = safeMediaReference((metadata as any).image);
  const mediaRows = parseJsonArray(row?.media);
  const mediaUrls: string[] = [];
  const mediaTypes: string[] = [];
  const mediaDimensions: any[] = [];

  for (const media of mediaRows) {
    const mediaUrl = safeMediaReference(typeof media === 'string' ? media : media?.url || media?.feedMediaUrl || media?.feed_media_url);
    if (!mediaUrl) continue;
    const mediaType = cleanText(typeof media === 'object' ? media?.type || media?.media_type : '', 20).toLowerCase() || (isVideoMediaUrl(mediaUrl) ? 'video' : 'image');
    mediaUrls.push(mediaUrl);
    mediaTypes.push(mediaType.includes('video') ? 'video' : 'image');
    mediaDimensions.push({
      width: Number((media as any)?.width || 0),
      height: Number((media as any)?.height || 0),
      ratio: Number((media as any)?.ratio || (media as any)?.aspect_ratio || 0),
    });
  }

  if (!mediaUrls.length && fallbackImage) {
    mediaUrls.push(fallbackImage);
    mediaTypes.push(isVideoMediaUrl(fallbackImage) ? 'video' : 'image');
  }

  const explicitDimensions = parseJsonArray(row?.media_dimensions);
  return {
    mediaUrls,
    mediaTypes,
    mediaDimensions: explicitDimensions.length ? explicitDimensions : mediaDimensions,
  };
}

function supabaseUserStatus(row: any): string {
  const metadata = parseJsonObject(row?.metadata);
  const status = (cleanText((metadata as any).status || row?.status || 'active', 40) || 'active').toLowerCase();
  if (status === 'suspended') {
    const suspendedUntil = Date.parse(String((metadata as any).suspended_until || row?.suspended_until || ''));
    if (Number.isFinite(suspendedUntil) && suspendedUntil <= Date.now()) return 'active';
  }
  return status;
}

function supabaseAppPostMatchesCategory(row: any, category: DiscoverCategory | 'all' | undefined): boolean {
  if (!category || category === 'all') return true;
  const metadata = parseJsonObject(row?.metadata);
  const discover = parseJsonObject((metadata as any).discover_category);
  const primary = normalizeDiscoverCategory(row?.category || (discover as any).primary_category || row?.post_type, false);
  if (primary === category) return true;
  const terms = discoverCategorySearchTerms(category);
  const haystack = [
    row?.category,
    row?.post_type,
    row?.title,
    row?.content,
    row?.location,
    ...(sanitizeAutoCategoryTags((discover as any).tags)),
    ...Object.keys(parseJsonObject((metadata as any).category_scores || (discover as any).category_scores)).filter((key) => Number((metadata as any).category_scores?.[key] || (discover as any).category_scores?.[key] || 0) >= 24),
  ].join(' ').toLowerCase();
  return terms.some((term) => haystack.includes(term));
}

function supabaseAppPostVisibleToViewer(row: any, author: any, viewerIds: Set<string>, followingIds: Set<string>, blockedIds: Set<string>): boolean {
  if (!row || !author) return false;
  if (cleanText(row?.status || 'active', 40) !== 'active') return false;
  if (supabaseUserStatus(author) !== 'active') return false;
  const appUserId = publicId(row?.app_user_id || author?.id, 120);
  const authUserId = isUuidText(row?.user_id);
  const isOwner = viewerIds.has(appUserId) || (!!authUserId && viewerIds.has(authUserId));
  if (!isOwner && (blockedIds.has(appUserId) || (!!authUserId && blockedIds.has(authUserId)))) return false;
  const visibility = normalizeVisibility(row?.visibility);
  if (visibility === 'private') return isOwner;
  if (visibility === 'followers' || visibility === 'friends') return isOwner || followingIds.has(appUserId);
  if (author?.is_private && !isOwner && !followingIds.has(appUserId)) return false;
  return true;
}

function supabaseAppPostToLegacy(row: any, author: any, isFollowing: boolean, commentCount: number): any {
  const metadata = parseJsonObject(row?.metadata);
  const discover = parseJsonObject((metadata as any).discover_category);
  const raw = parseJsonObject((metadata as any).raw);
  const place = parseJsonObject((metadata as any).place);
  const audio = parseJsonObject((metadata as any).audio);
  const pinnedAt = cleanText((metadata as any).pinned_at, 80) || null;
  const { mediaUrls, mediaTypes, mediaDimensions } = supabaseAppPostMedia(row);
  const primaryCategory = (normalizeDiscoverCategory(row?.category || (discover as any).primary_category || row?.post_type, false) || DEFAULT_DISCOVER_CATEGORY) as DiscoverCategory;
  const appUserId = publicId(row?.app_user_id || author?.id, 120);
  return {
    id: publicId(row?.legacy_post_id || row?.id, 120),
    supabase_post_id: isUuidText(row?.id),
    user_id: appUserId,
    user_username: author?.username,
    user_full_name: author?.full_name,
    user_profile_image: author?.avatar_url,
    title: cleanText(row?.title, 180),
    content: cleanMultilineText(row?.content, 4000),
    image: mediaUrls[0] || '',
    images: mediaUrls,
    media_types: mediaTypes,
    media_dimensions: mediaDimensions,
    editor_overlays: parseJsonArray((row?.editor_data || {}).overlays),
    tagged_users: parseJsonArray(row?.tagged_users),
    primary_category: primaryCategory,
    category: primaryCategory,
    category_confidence: clampFloat((discover as any).confidence, 0, 1, 0),
    category_source: normalizeCategorySource((discover as any).source),
    category_status: normalizeCategoryStatus((discover as any).status),
    category_signals_json: JSON.stringify({ ...discover, raw }),
    tags_json: JSON.stringify(sanitizeAutoCategoryTags((discover as any).tags)),
    category_scores_json: JSON.stringify(parseJsonObject((metadata as any).category_scores || (discover as any).category_scores)),
    secondary_categories_json: JSON.stringify(sanitizeAutoCategoryTags((metadata as any).secondary_categories || (discover as any).secondary_categories)),
    detected_objects_json: JSON.stringify(sanitizeAutoCategoryTags((metadata as any).detected_objects || (discover as any).detected_objects)),
    detected_scene: cleanText((metadata as any).detected_scene || (discover as any).detected_scene, 80),
    place_type: cleanText((metadata as any).place_type || (discover as any).place_type, 120),
    user_selected_category: normalizeDiscoverCategory((metadata as any).user_selected_category || (discover as any).user_selected_category, false),
    caption_keywords_json: JSON.stringify(sanitizeAutoCategoryTags((metadata as any).caption_keywords || (discover as any).caption_keywords)),
    location: cleanText(row?.location || (place as any).name, 180),
    display_city: cleanText((raw as any).display_city || (metadata as any).display_city, 80),
    display_region: cleanText((raw as any).display_region || (metadata as any).display_region, 80),
    display_country: cleanText((raw as any).display_country || (metadata as any).display_country, 80),
    display_location_label: cleanText((raw as any).display_location_label || (metadata as any).display_location_label, 120),
    display_location_source: cleanText((raw as any).display_location_source || (metadata as any).display_location_source, 40),
    display_location_visibility: cleanText((raw as any).display_location_visibility || (metadata as any).display_location_visibility || 'public', 40),
    post_type: cleanText(row?.post_type || 'general', 80),
    place_id: cleanText((place as any).id, 160),
    place_name: cleanText((place as any).name, 180),
    place_provider: cleanText((place as any).provider || 'apple_mapkit', 40),
    place_provider_id: cleanText((place as any).id, 160),
    place_formatted_address: cleanText((place as any).formatted_address || row?.location, 260),
    place_category: cleanText((place as any).category, 80),
    place_city: cleanText((place as any).city, 80),
    place_region: cleanText((place as any).region, 80),
    place_country: cleanText((place as any).country, 80),
    place_lat: (place as any).latitude == null ? null : clampFloat((place as any).latitude, -90, 90, 0),
    place_lng: (place as any).longitude == null ? null : clampFloat((place as any).longitude, -180, 180, 0),
    removed_at: cleanText((metadata as any).removed_at, 80) || null,
    removed_reason: cleanMultilineText((metadata as any).removed_reason, 500),
    discover_blocked_at: cleanText((metadata as any).discover_blocked_at, 80) || null,
    discover_blocked_reason: cleanMultilineText((metadata as any).discover_blocked_reason, 500),
    is_verified_checkin: !!(place as any).verified_checkin,
    audio_provider: cleanText((audio as any).provider, 40),
    audio_track_id: cleanText((audio as any).track_id, 120),
    audio_title: cleanText((audio as any).title, 180),
    audio_artist: cleanText((audio as any).artist, 180),
    audio_artwork_url: safeMediaReference((audio as any).artwork_url),
    audio_stream_url: safeExternalUrl((audio as any).stream_url),
    audio_start_time: Number((audio as any).start_time || 0),
    audio_duration: Number((audio as any).duration || 0),
    visibility: normalizeVisibility(row?.visibility),
    pinned_at: pinnedAt,
    is_pinned: !!pinnedAt,
    moderation_status: 'approved',
    likes_count: Math.max(0, Number(row?.likes_count || 0)),
    comments_count: Math.max(0, commentCount || Number(row?.comments_count || 0)),
    saves_count: Math.max(0, Number(row?.saves_count || 0)),
    liked_by: [],
    is_following: isFollowing,
    created_at: row?.legacy_created_at || row?.created_at,
    updated_at: row?.legacy_updated_at || row?.updated_at,
  };
}

async function supabaseReadVisiblePosts(c: any, viewerId: string, options: SupabasePostReadOptions = {}): Promise<any[]> {
  const limit = clampNumber(options.limit || 20, 1, 100, 20);
  const offset = Math.max(0, Math.round(Number(options.offset || 0)));
  const filters: Record<string, string> = { status: postgrestEqFilter('active') };
  const postId = publicId(options.postId, 120);
  const postIds = Array.from(new Set((options.postIds || []).map((value) => publicId(value, 120)).filter(Boolean)));
  const ownerId = publicId(options.ownerId, 120);
  const search = postgrestSearchTerm(options.search || '');

  if (postIds.length) {
    const uuidPostIds = postIds.map((value) => isUuidText(value)).filter((value): value is string => !!value);
    const orParts = [`legacy_post_id.${postgrestInFilter(postIds)}`];
    if (uuidPostIds.length) orParts.push(`id.${postgrestInFilter(uuidPostIds)}`);
    filters.or = `(${orParts.join(',')})`;
  } else if (postId) {
    const uuidPostId = isUuidText(postId);
    filters.or = uuidPostId ? `(legacy_post_id.eq.${postId},id.eq.${postId})` : `(legacy_post_id.eq.${postId})`;
  } else if (ownerId) {
    const ownerUuid = isUuidText(ownerId);
    filters.or = ownerUuid ? `(app_user_id.eq.${ownerId},user_id.eq.${ownerId})` : `(app_user_id.eq.${ownerId})`;
  } else if (search) {
    filters.or = `(content.ilike.*${search}*,title.ilike.*${search}*,category.ilike.*${search}*,location.ilike.*${search}*)`;
  }

  const rowLimit = postIds.length
    ? postIds.length
    : postId
      ? 1
    : Math.min(300, Math.max(limit + offset + 20, options.category && options.category !== 'all' ? (limit + offset) * 4 : limit + offset));
  const rows = await supabaseAdminQueryRows(c, 'app_posts', {
    select: SUPABASE_APP_POST_SELECT,
    filters,
    order: options.order === 'trending'
      ? 'likes_count.desc.nullslast,legacy_created_at.desc.nullslast,created_at.desc'
      : 'legacy_created_at.desc.nullslast,created_at.desc',
    limit: rowLimit,
    offset: postIds.length || postId || ownerId || search || (options.category && options.category !== 'all') ? 0 : offset,
  });

  const isDiscoverQuery = options.category !== undefined;
  const photoOnly = options.photoOnly === true || isDiscoverQuery;
  const candidateRows = rows.filter((row) => {
    if ((photoOnly && !supabaseAppPostHasRenderablePhotoMedia(row)) || !supabaseAppPostMatchesCategory(row, options.category)) return false;
    if (!isDiscoverQuery) return true;
    const metadata = parseJsonObject(row?.metadata);
    return !cleanText((metadata as any).discover_blocked_at, 80);
  });
  const authorIds = candidateRows.flatMap((row) => [publicId(row?.app_user_id, 120), isUuidText(row?.user_id) || '']).filter(Boolean);
  const [viewerAliases, blockedIds, authorMap, commentCounts] = await Promise.all([
    supabaseRelatedInteractionUserIds(c, viewerId),
    supabaseBlockedUserIds(c, viewerId),
    supabaseUsersByAnyIds(c, authorIds),
    supabasePostCommentCounts(c, candidateRows),
  ]);
  const followingIds = await supabaseFollowingUserIds(c, viewerId, Array.from(new Set(authorIds.map((id) => publicId(id, 120)).filter(Boolean))));
  const viewerSet = new Set(viewerAliases);
  const rowsVisibleToViewer = candidateRows
    .filter((row) => {
      const author = authorMap.get(publicId(row?.app_user_id, 120)) || authorMap.get(isUuidText(row?.user_id) || '');
      return supabaseAppPostVisibleToViewer(row, author, viewerSet, followingIds, blockedIds);
    });
  if (ownerId) {
    rowsVisibleToViewer.sort((a, b) => {
      const aPinned = cleanText((parseJsonObject(a?.metadata) as any).pinned_at, 80);
      const bPinned = cleanText((parseJsonObject(b?.metadata) as any).pinned_at, 80);
      if (!!aPinned !== !!bPinned) return aPinned ? -1 : 1;
      if (aPinned && bPinned) return (Date.parse(bPinned) || 0) - (Date.parse(aPinned) || 0);
      return 0;
    });
  }
  const visibleRows = rowsVisibleToViewer
    .slice(postIds.length || postId || ownerId || search || (options.category && options.category !== 'all') ? offset : 0)
    .slice(0, limit);

  const mapped = visibleRows.map((row) => {
    const author = authorMap.get(publicId(row?.app_user_id, 120)) || authorMap.get(isUuidText(row?.user_id) || '');
    const id = publicId(row?.legacy_post_id || row?.id, 120);
    return supabaseAppPostToLegacy(row, author, followingIds.has(publicId(row?.app_user_id, 120)), commentCounts.get(id) || Number(row?.comments_count || 0));
  });
  const ordered = postIds.length
    ? mapped.sort((a, b) => postIds.indexOf(publicId(a?.id, 120)) - postIds.indexOf(publicId(b?.id, 120)))
    : mapped;
  return overlaySupabaseViewerEngagement(c, photoOnly ? feedPhotoPostsOnly(ordered) : ordered, viewerId);
}

function postgrestInFilter(values: string[]): string {
  const safeValues = values
    .map((value) => cleanText(value, 240))
    .filter(Boolean)
    .map((value) => `"${value.replace(/"/g, '""')}"`);
  return `in.(${safeValues.join(',')})`;
}

function postgrestEqFilter(value: string): string {
  return `eq.${cleanText(value, 240)}`;
}

function isSupabaseColumnShapeError(error: any): boolean {
  const code = getErrorCode(error).toLowerCase();
  return code.includes('pgrst204') || code.includes('column') || code.includes('schema cache');
}

function supabaseEngagementConfigured(c: any): boolean {
  return !!String(c.env.SUPABASE_URL || '').trim() && !!String(c.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
}

function databasePrimary(c: any): 'supabase_postgres' | 'legacy_d1' {
  return String(c?.env?.DATABASE_PRIMARY || '').trim().toLowerCase() === 'supabase_postgres'
    ? 'supabase_postgres'
    : 'legacy_d1';
}

function supabasePrimaryRequested(c: any): boolean {
  return databasePrimary(c) === 'supabase_postgres';
}

function supabasePrimaryConfigured(c: any): boolean {
  return supabasePrimaryRequested(c) && supabaseEngagementConfigured(c);
}

function supabasePrimaryRequestedForEnv(env: Env): boolean {
  return databasePrimary({ env }) === 'supabase_postgres';
}

function requireSupabasePrimaryDatabase(c: any, feature = 'app data') {
  if (supabasePrimaryConfigured(c)) return null;
  return c.json({
    detail: 'Captro production database is not configured. Please try again later.',
    code: 'SUPABASE_PRIMARY_REQUIRED',
    feature,
  }, 503);
}

function rejectLegacyUploadWhenSupabasePrimary(c: any, route: string) {
  if (!supabasePrimaryRequested(c)) return null;
  return c.json({
    detail: 'This upload path has moved. Please update the app and try again.',
    code: 'LEGACY_UPLOAD_DISABLED',
    route,
  }, 410);
}

async function supabaseAdminSelectRows(c: any, table: string, filters: Record<string, string>, select = '*', limit = 1000): Promise<any[]> {
  const url = new URL(`${getSupabaseUrl(c)}/rest/v1/${table}`);
  url.searchParams.set('select', select);
  for (const [key, value] of Object.entries(filters)) {
    url.searchParams.set(key, value);
  }
  if (limit > 0) url.searchParams.set('limit', String(limit));
  const response = await fetch(url.toString(), {
    headers: supabaseAdminAuthHeaders(c),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_SELECT_FAILED:${table}:${response.status}:${text.slice(0, 300)}`);
  }
  const data = await response.json().catch(() => []);
  return Array.isArray(data) ? data : [];
}

async function supabaseAdminQueryRows(c: any, table: string, input: {
  select?: string;
  filters?: Record<string, string>;
  order?: string;
  limit?: number;
  offset?: number;
} = {}): Promise<any[]> {
  const url = new URL(`${getSupabaseUrl(c)}/rest/v1/${table}`);
  url.searchParams.set('select', input.select || '*');
  for (const [key, value] of Object.entries(input.filters || {})) {
    url.searchParams.set(key, value);
  }
  if (input.order) url.searchParams.set('order', input.order);
  if (typeof input.limit === 'number' && input.limit > 0) url.searchParams.set('limit', String(input.limit));
  if (typeof input.offset === 'number' && input.offset > 0) url.searchParams.set('offset', String(input.offset));
  const response = await fetch(url.toString(), {
    headers: supabaseAdminAuthHeaders(c),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_QUERY_FAILED:${table}:${response.status}:${text.slice(0, 300)}`);
  }
  const data = await response.json().catch(() => []);
  return Array.isArray(data) ? data : [];
}

async function supabaseAdminCountRows(c: any, table: string, filters: Record<string, string>): Promise<number> {
  const url = new URL(`${getSupabaseUrl(c)}/rest/v1/${table}`);
  url.searchParams.set('select', '*');
  url.searchParams.set('limit', '1');
  for (const [key, value] of Object.entries(filters)) {
    url.searchParams.set(key, value);
  }
  const serviceRoleKey = getSupabaseServiceRoleKey(c);
  const response = await fetch(url.toString(), {
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      Prefer: 'count=exact',
    },
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_COUNT_FAILED:${table}:${response.status}:${text.slice(0, 300)}`);
  }
  const contentRange = response.headers.get('content-range') || response.headers.get('Content-Range') || '';
  const total = Number(contentRange.split('/').pop() || NaN);
  if (Number.isFinite(total)) return Math.max(0, total);
  const data = await response.json().catch(() => []);
  return Array.isArray(data) ? data.length : 0;
}

async function supabaseAdminDeleteRows(c: any, table: string, filters: Record<string, string>) {
  const url = new URL(`${getSupabaseUrl(c)}/rest/v1/${table}`);
  for (const [key, value] of Object.entries(filters)) {
    url.searchParams.set(key, value);
  }
  const serviceRoleKey = getSupabaseServiceRoleKey(c);
  const response = await fetch(url.toString(), {
    method: 'DELETE',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      Prefer: 'return=minimal',
    },
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_DELETE_FAILED:${table}:${response.status}:${text.slice(0, 300)}`);
  }
}

async function supabaseAdminDeleteRowsIfShapeExists(c: any, table: string, filters: Record<string, string>) {
  try {
    await supabaseAdminDeleteRows(c, table, filters);
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) throw error;
  }
}

async function supabaseAdminPatchRows(c: any, table: string, filters: Record<string, string>, patch: Record<string, unknown>) {
  const url = new URL(`${getSupabaseUrl(c)}/rest/v1/${table}`);
  for (const [key, value] of Object.entries(filters)) {
    url.searchParams.set(key, value);
  }
  const serviceRoleKey = getSupabaseServiceRoleKey(c);
  const response = await fetch(url.toString(), {
    method: 'PATCH',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify(patch),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_PATCH_FAILED:${table}:${response.status}:${text.slice(0, 300)}`);
  }
}

async function supabaseAdminSelectRowsIfShapeExists(c: any, table: string, filters: Record<string, string>, select = '*', limit = 1000): Promise<any[]> {
  try {
    return await supabaseAdminSelectRows(c, table, filters, select, limit);
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) throw error;
    return [];
  }
}

async function supabaseDeletePostInteractionsForUsers(c: any, postId: string, userIds: string[], kind: 'like' | 'save') {
  if (!userIds.length) return;
  const identity = await supabaseResolvePostIdentity(c, postId);
  const keys = await supabaseInteractionActorKeys(c, userIds);
  if (keys.actorKeys.length) {
    await supabaseAdminDeleteRowsIfShapeExists(c, 'app_post_interactions', {
      or: supabasePostIdentityOrFilter(identity),
      kind: postgrestEqFilter(kind),
      actor_key: postgrestInFilter(keys.actorKeys),
    });
  }
  if (keys.appUserIds.length) {
    await supabaseAdminDeleteRows(c, 'app_post_interactions', {
      or: supabasePostIdentityOrFilter(identity),
      kind: postgrestEqFilter(kind),
      app_user_id: postgrestInFilter(keys.appUserIds),
    });
  }
  if (keys.authUserIds.length) {
    await supabaseAdminDeleteRowsIfShapeExists(c, 'app_post_interactions', {
      or: supabasePostIdentityOrFilter(identity),
      kind: postgrestEqFilter(kind),
      user_id: postgrestInFilter(keys.authUserIds),
    });
  }
}

async function supabaseUpsertPostInteraction(c: any, postId: string, userId: string, kind: 'like' | 'save', collection = '') {
  const identity = await supabaseResolvePostIdentity(c, postId);
  const requestedUserId = cleanText(userId, 120);
  const keys = await supabaseInteractionActorKeys(c, [requestedUserId]);
  const appToAuth = await supabaseAuthUserIdMapForAppUserIds(c, keys.appUserIds);
  const appToIdentityActors = await supabaseAccountIdentityActorKeysMap(c, keys.appUserIds);
  const canonicalAppUserId = cleanText(
    keys.appUserIds.find((id) => appToAuth.has(id)) ||
      keys.appUserIds[0] ||
      requestedUserId,
    120
  );
  const authUserId = appToAuth.get(canonicalAppUserId) || keys.authUserIds[0] || '';
  const preferredIdentityActor = (appToIdentityActors.get(canonicalAppUserId) || [])[0] || '';
  const actorKey = cleanText(
    supabaseInteractionActorKey(authUserId || '', preferredIdentityActor, canonicalAppUserId),
    220
  );
  await supabaseDeletePostInteractionsForUsers(c, postId, [requestedUserId, canonicalAppUserId, ...(authUserId ? [authUserId] : []), ...keys.appUserIds, ...keys.authUserIds], kind);
  const baseRow: any = {
    legacy_post_id: cleanText(identity.legacyPostId || identity.requestedPostId, 120),
    app_user_id: canonicalAppUserId,
    kind,
    collection: kind === 'save' ? (cleanText(collection, 120) || 'saved') : null,
    metadata: { source: 'cloudflare_worker_primary' },
    legacy_created_at: now(),
  };
  if (identity.postUuid) baseRow.post_id = identity.postUuid;
  if (authUserId) baseRow.user_id = authUserId;
  if (actorKey) baseRow.actor_key = actorKey;
  if (identity.postUuid && authUserId) {
    await supabaseAdminDeleteRowsIfShapeExists(c, 'app_post_interactions', {
      post_id: postgrestEqFilter(identity.postUuid),
      user_id: postgrestEqFilter(authUserId),
      kind: postgrestEqFilter(kind),
    });
  }
  if (actorKey) {
    try {
      await supabaseAdminUpsert(c, 'app_post_interactions', [baseRow], 'legacy_post_id,kind,actor_key');
      return;
    } catch (error: any) {
      if (!isSupabaseColumnShapeError(error) && !getErrorCode(error).includes('42P10')) {
        throw error;
      }
    }
  }
  try {
    await supabaseAdminUpsert(c, 'app_post_interactions', [baseRow], 'legacy_post_id,app_user_id,kind');
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) {
      throw error;
    }
    delete baseRow.actor_key;
    delete baseRow.user_id;
    delete baseRow.post_id;
    await supabaseAdminUpsert(c, 'app_post_interactions', [baseRow], 'legacy_post_id,app_user_id,kind');
  }
}

async function supabaseViewerPostInteractionExists(c: any, postId: string, userIds: string[], kind: 'like' | 'save'): Promise<boolean> {
  if (!userIds.length) return false;
  const identity = await supabaseResolvePostIdentity(c, postId);
  const keys = await supabaseInteractionActorKeys(c, userIds);
  if (keys.actorKeys.length) {
    const actorRows = await supabaseAdminSelectRowsIfShapeExists(c, 'app_post_interactions', {
      or: supabasePostIdentityOrFilter(identity),
      kind: postgrestEqFilter(kind),
      actor_key: postgrestInFilter(keys.actorKeys),
    }, 'legacy_post_id', 1);
    if (actorRows.length > 0) return true;
  }
  if (keys.appUserIds.length) {
    const rows = await supabaseAdminSelectRows(c, 'app_post_interactions', {
      or: supabasePostIdentityOrFilter(identity),
      kind: postgrestEqFilter(kind),
      app_user_id: postgrestInFilter(keys.appUserIds),
    }, 'legacy_post_id', 1);
    if (rows.length > 0) return true;
  }
  if (!keys.authUserIds.length) return false;
  try {
    const legacyAuthRows = await supabaseAdminSelectRows(c, 'app_post_interactions', {
      or: supabasePostIdentityOrFilter(identity),
      kind: postgrestEqFilter(kind),
      user_id: postgrestInFilter(keys.authUserIds),
    }, 'legacy_post_id', 1);
    if (legacyAuthRows.length > 0) return true;
    return false;
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) throw error;
    return false;
  }
}

async function supabaseAuthUserIdForAppUserId(c: any, userId: string): Promise<string> {
  const cleanUserId = publicId(userId, 120);
  if (!cleanUserId) return '';
  const [authUserId] = await supabaseAuthUserIdsForAppUserIds(c, [cleanUserId]);
  return authUserId || '';
}

async function supabaseAuthUserIdMapForAppUserIds(c: any, userIds: string[]): Promise<Map<string, string>> {
  const ids = Array.from(new Set(userIds.map((value) => publicId(value, 120)).filter(Boolean)));
  const map = new Map<string, string>();
  if (!ids.length) return map;
  try {
    const rows = await supabaseAdminSelectRows(c, 'app_users', {
      id: postgrestInFilter(ids),
    }, 'id,supabase_user_id', Math.max(1, ids.length));
    for (const row of rows) {
      const appUserId = publicId(row?.id, 120);
      const authUserId = isUuidText(row?.supabase_user_id);
      if (appUserId && authUserId) map.set(appUserId, authUserId);
    }
  } catch {}
  return map;
}

async function supabaseAppUserIdsForAuthUserIds(c: any, authUserIds: string[]): Promise<string[]> {
  const ids = Array.from(new Set(authUserIds.map((value) => isUuidText(value)).filter((value): value is string => !!value)));
  if (!ids.length) return [];
  try {
    const rows = await supabaseAdminSelectRows(c, 'app_users', {
      supabase_user_id: postgrestInFilter(ids),
    }, 'id,supabase_user_id', Math.max(1, ids.length * 3));
    return Array.from(new Set(rows.map((row) => publicId(row?.id, 120)).filter((value): value is string => !!value)));
  } catch {
    return [];
  }
}

async function legacyD1AuthUserIdsForAppUserIds(c: any, ids: string[]): Promise<string[]> {
  const authIds = new Set<string>();
  if (!ids.length) return [];
  try {
    const placeholders = inPlaceholders(ids);
    const rows = await c.env.DB.prepare(`SELECT supabase_user_id FROM users WHERE id IN (${placeholders})`)
      .bind(...ids)
      .all();
    for (const row of rows.results as any[]) {
      const authId = isUuidText(row?.supabase_user_id);
      if (authId) authIds.add(authId);
    }
  } catch {}
  return Array.from(authIds);
}

async function supabaseAuthUserIdsForAppUserIds(c: any, userIds: string[]): Promise<string[]> {
  const ids = Array.from(new Set(userIds.map((value) => publicId(value, 120)).filter(Boolean)));
  const authIds = new Set<string>();
  const payloadSupabaseSub = isUuidText(c.get?.('jwtPayload')?.supabase_sub);
  if (payloadSupabaseSub) authIds.add(payloadSupabaseSub);
  if (!ids.length) return Array.from(authIds);
  try {
    const rows = await supabaseAdminSelectRows(c, 'app_users', {
      id: postgrestInFilter(ids),
    }, 'id,supabase_user_id', Math.max(1, ids.length));
    for (const row of rows) {
      const authId = isUuidText(row?.supabase_user_id);
      if (authId) authIds.add(authId);
    }
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_auth_alias_read_failed', code: getErrorCode(error).slice(0, 180) }));
  }
  return Array.from(authIds);
}

async function supabaseInteractionIdentityKeys(c: any, userIds: string[]) {
  const relatedUserIds = new Set<string>();
  for (const userId of userIds) {
    const cleanUserId = publicId(userId, 120);
    if (cleanUserId) relatedUserIds.add(cleanUserId);
    for (const relatedUserId of await supabaseRelatedInteractionUserIds(c, cleanUserId)) {
      relatedUserIds.add(relatedUserId);
    }
  }
  const related = Array.from(relatedUserIds);
  const mappedAuthUserIds = await supabaseAuthUserIdsForAppUserIds(c, related);
  const authUserIds = Array.from(new Set(mappedAuthUserIds));
  const appUserIdsFromAuth = await supabaseAppUserIdsForAuthUserIds(c, [...related, ...authUserIds]);
  return {
    appUserIds: Array.from(new Set([...related, ...appUserIdsFromAuth])).filter(Boolean),
    authUserIds,
  };
}

function supabaseInteractionActorKey(authUserId: string, identityActor: string, appUserId: string): string {
  const authId = isUuidText(authUserId);
  if (authId) return `auth:${authId}`;
  const identity = cleanText(identityActor, 220);
  if (identity) return identity;
  const appId = publicId(appUserId, 120);
  return appId ? `app:${appId}` : '';
}

function normalizeLegacyInteractionActorKey(raw: unknown): string {
  const clean = cleanText(raw, 220);
  if (!clean) return '';
  if (clean.startsWith('app:')) {
    const legacyAppId = isUuidText(clean.slice(4));
    if (legacyAppId) return `auth:${legacyAppId}`;
  }
  return clean;
}

function canonicalSupabaseInteractionActor(
  row: any,
  appToAuth: Map<string, string>,
  appToIdentityActor: Map<string, string>
): string {
  const appUserId = publicId(row?.app_user_id, 120);
  const authUserId = isUuidText(row?.user_id) || appToAuth.get(appUserId) || '';
  if (authUserId) return `auth:${authUserId}`;
  const identityActor = normalizeLegacyInteractionActorKey(appToIdentityActor.get(appUserId) || '');
  if (identityActor) return identityActor;
  const storedActor = normalizeLegacyInteractionActorKey(row?.actor_key);
  if (storedActor) return storedActor;
  const legacyAuthLikeAppId = isUuidText(appUserId);
  if (legacyAuthLikeAppId) return `auth:${legacyAuthLikeAppId}`;
  return supabaseInteractionActorKey('', '', appUserId);
}

async function supabaseInteractionActorKeys(c: any, userIds: string[]) {
  const keys = await supabaseInteractionIdentityKeys(c, userIds);
  const appToAuth = await supabaseAuthUserIdMapForAppUserIds(c, keys.appUserIds);
  const appToIdentityActor = await supabaseAccountIdentityActorKeyMap(c, keys.appUserIds);
  const appToIdentityActors = await supabaseAccountIdentityActorKeysMap(c, keys.appUserIds);
  const actorKeys = new Set<string>();
  for (const authUserId of keys.authUserIds) {
    const actorKey = supabaseInteractionActorKey(authUserId, '', '');
    if (actorKey) actorKeys.add(actorKey);
  }
  for (const appUserId of keys.appUserIds) {
    const actorKey = supabaseInteractionActorKey(appToAuth.get(appUserId) || '', appToIdentityActor.get(appUserId) || '', appUserId);
    if (actorKey) actorKeys.add(actorKey);
    for (const identityActor of appToIdentityActors.get(appUserId) || []) {
      const cleanIdentityActor = normalizeLegacyInteractionActorKey(identityActor);
      if (cleanIdentityActor) actorKeys.add(cleanIdentityActor);
    }
    const rawLegacyAppKey = cleanText(`app:${appUserId}`, 220);
    if (rawLegacyAppKey) actorKeys.add(rawLegacyAppKey);
  }
  return {
    ...keys,
    actorKeys: Array.from(actorKeys),
  };
}

type SupabasePostIdentity = {
  requestedPostId: string;
  legacyPostId: string;
  postUuid: string;
};

function supabasePostIdentityKeys(identity: SupabasePostIdentity): string[] {
  return Array.from(new Set([
    cleanText(identity.requestedPostId, 120),
    cleanText(identity.legacyPostId, 120),
    cleanText(identity.postUuid, 120),
  ].filter(Boolean)));
}

function supabasePostIdentityOrFilter(identity: SupabasePostIdentity): string {
  const parts: string[] = [];
  if (identity.legacyPostId) parts.push(`legacy_post_id.eq.${identity.legacyPostId}`);
  if (identity.postUuid) parts.push(`post_id.eq.${identity.postUuid}`);
  if (!parts.length && identity.requestedPostId) parts.push(`legacy_post_id.eq.${identity.requestedPostId}`);
  return `(${parts.join(',')})`;
}

function supabaseAppPostIdentityOrFilter(identity: SupabasePostIdentity): string {
  const parts: string[] = [];
  if (identity.legacyPostId) parts.push(`legacy_post_id.eq.${identity.legacyPostId}`);
  if (identity.postUuid) parts.push(`id.eq.${identity.postUuid}`);
  if (!parts.length && identity.requestedPostId) parts.push(`legacy_post_id.eq.${identity.requestedPostId}`);
  return `(${parts.join(',')})`;
}

async function supabaseResolvePostIdentity(c: any, postId: string): Promise<SupabasePostIdentity> {
  const requestedPostId = publicId(postId, 120);
  const requestedUuid = isUuidText(requestedPostId);
  const fallback: SupabasePostIdentity = {
    requestedPostId,
    legacyPostId: requestedUuid ? '' : requestedPostId,
    postUuid: requestedUuid || '',
  };
  if (!requestedPostId) return fallback;

  try {
    const filters: Record<string, string> = requestedUuid
      ? { or: `(id.eq.${requestedUuid},legacy_post_id.eq.${requestedPostId})` }
      : { legacy_post_id: postgrestEqFilter(requestedPostId) };
    const rows = await supabaseAdminQueryRows(c, 'app_posts', {
      select: 'id,legacy_post_id',
      filters,
      limit: 1,
    });
    const row = rows[0];
    if (!row) return fallback;
    return {
      requestedPostId,
      legacyPostId: publicId(row?.legacy_post_id || fallback.legacyPostId, 120),
      postUuid: isUuidText(row?.id) || fallback.postUuid,
    };
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) {
      console.warn(JSON.stringify({ event: 'supabase_post_identity_lookup_failed', code: getErrorCode(error).slice(0, 180) }));
    }
    return fallback;
  }
}

async function supabaseResolvePostIdentities(c: any, postIds: string[]): Promise<Map<string, SupabasePostIdentity>> {
  const cleanPostIds = Array.from(new Set(postIds.map((value) => publicId(value, 120)).filter(Boolean)));
  const map = new Map<string, SupabasePostIdentity>();
  for (const postId of cleanPostIds) {
    const requestedUuid = isUuidText(postId);
    map.set(postId, {
      requestedPostId: postId,
      legacyPostId: requestedUuid ? '' : postId,
      postUuid: requestedUuid || '',
    });
  }
  if (!cleanPostIds.length) return map;

  try {
    const uuidPostIds = cleanPostIds.map((value) => isUuidText(value)).filter((value): value is string => !!value);
    const orParts = [`legacy_post_id.${postgrestInFilter(cleanPostIds)}`];
    if (uuidPostIds.length) orParts.push(`id.${postgrestInFilter(uuidPostIds)}`);
    const rows = await supabaseAdminQueryRows(c, 'app_posts', {
      select: 'id,legacy_post_id',
      filters: { or: `(${orParts.join(',')})` },
      limit: Math.max(1, cleanPostIds.length * 2),
    });
    for (const row of rows) {
      const identity: SupabasePostIdentity = {
        requestedPostId: publicId(row?.legacy_post_id || row?.id, 120),
        legacyPostId: publicId(row?.legacy_post_id, 120),
        postUuid: isUuidText(row?.id) || '',
      };
      for (const key of supabasePostIdentityKeys(identity)) {
        if (map.has(key)) map.set(key, { ...identity, requestedPostId: key });
      }
    }
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) {
      console.warn(JSON.stringify({ event: 'supabase_post_identities_lookup_failed', code: getErrorCode(error).slice(0, 180) }));
    }
  }

  return map;
}

async function supabasePostInteractionActorCount(c: any, postId: string, kind: 'like' | 'save'): Promise<number> {
  const identity = await supabaseResolvePostIdentity(c, postId);
  const filters: Record<string, string> = {
    or: supabasePostIdentityOrFilter(identity),
    kind: postgrestEqFilter(kind),
  };
  let rows: any[];
  try {
    rows = await supabaseAdminSelectRows(c, 'app_post_interactions', filters, 'app_user_id,user_id,actor_key,legacy_post_id,post_id', 10000);
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) throw error;
    const fallbackFilters = {
      legacy_post_id: postgrestEqFilter(identity.legacyPostId || identity.requestedPostId),
      kind: postgrestEqFilter(kind),
    };
    rows = await supabaseAdminSelectRows(c, 'app_post_interactions', fallbackFilters, 'app_user_id', 10000);
  }
  const appUserIds = rows.map((row) => publicId(row?.app_user_id, 120)).filter(Boolean);
  const appToAuth = await supabaseAuthUserIdMapForAppUserIds(c, appUserIds);
  const appToIdentityActor = await supabaseAccountIdentityActorKeyMap(c, appUserIds);
  const actors = new Set<string>();
  for (const row of rows) {
    const actor = canonicalSupabaseInteractionActor(row, appToAuth, appToIdentityActor);
    if (actor) actors.add(actor);
  }
  return actors.size;
}

async function supabaseOwnedAppPost(c: any, postId: string, userId: string): Promise<{ status: 200; row: any; identity: SupabasePostIdentity } | { status: 403 | 404; body: any }> {
  const identity = await supabaseResolvePostIdentity(c, postId);
  const rows = await supabaseAdminQueryRows(c, 'app_posts', {
    select: SUPABASE_APP_POST_SELECT,
    filters: { or: supabaseAppPostIdentityOrFilter(identity) },
    limit: 1,
  });
  const row = rows[0];
  if (!row || cleanText(row?.status || 'active', 40) === 'removed') {
    return { status: 404, body: { detail: 'Post not found' } };
  }

  const ownerAliases = new Set(await supabaseRelatedInteractionUserIds(c, userId));
  ownerAliases.add(publicId(userId, 120));
  const appOwnerId = publicId(row?.app_user_id, 120);
  const authOwnerId = isUuidText(row?.user_id) || '';
  if (!ownerAliases.has(appOwnerId) && (!authOwnerId || !ownerAliases.has(authOwnerId))) {
    return { status: 403, body: { detail: 'Not your post' } };
  }
  return { status: 200, row, identity };
}

async function supabaseAdminPostForModeration(c: any, postId: string): Promise<{ row: any; identity: SupabasePostIdentity } | null> {
  const identity = await supabaseResolvePostIdentity(c, postId);
  const rows = await supabaseAdminQueryRows(c, 'app_posts', {
    select: SUPABASE_APP_POST_SELECT,
    filters: { or: supabaseAppPostIdentityOrFilter(identity) },
    limit: 1,
  });
  const row = rows[0];
  return row ? { row, identity } : null;
}

function supabasePostModerationTargetUserId(row: any): string {
  return publicId(row?.app_user_id, 120) || isUuidText(row?.user_id) || '';
}

async function supabaseAdminPostPayloads(c: any, rows: any[]): Promise<any[]> {
  const cleanRows = Array.isArray(rows) ? rows.filter(Boolean) : [];
  if (!cleanRows.length) return [];
  const authorIds = cleanRows
    .flatMap((row) => [publicId(row?.app_user_id, 120), isUuidText(row?.user_id) || ''])
    .filter(Boolean);
  const [authorMap, commentCounts] = await Promise.all([
    supabaseUsersByAnyIds(c, authorIds),
    supabasePostCommentCounts(c, cleanRows),
  ]);
  return cleanRows.map((row) => {
    const author = authorMap.get(publicId(row?.app_user_id, 120)) || authorMap.get(isUuidText(row?.user_id) || '') || {};
    const legacyPost = supabaseAppPostToLegacy(
      row,
      author,
      false,
      commentCounts.get(publicId(row?.legacy_post_id || row?.id, 120)) || Number(row?.comments_count || 0),
    );
    return adminPostPayload(legacyPost, c.env);
  });
}

async function supabaseAdminPostPayload(c: any, row: any): Promise<any | null> {
  const payloads = await supabaseAdminPostPayloads(c, row ? [row] : []);
  return payloads[0] || null;
}

function supabaseAdminPostPayloadMatchesSearch(payload: any, search: string): boolean {
  const query = cleanText(search, 120).toLowerCase();
  if (!query) return true;
  return [
    payload?.id,
    payload?.supabase_post_id,
    payload?.content,
    payload?.title,
    payload?.category,
    payload?.primary_category,
    payload?.display_location_label,
    payload?.exact_place?.name,
    payload?.author?.id,
    payload?.author?.username,
    payload?.author?.full_name,
  ].some((value) => String(value || '').toLowerCase().includes(query));
}

async function supabasePostInteractionActorCounts(c: any, postIds: string[]) {
  const cleanPostIds = Array.from(new Set(postIds.map((value) => publicId(value, 120)).filter(Boolean)));
  const counts = new Map<string, { likes_count: number; saves_count: number }>();
  for (const postId of cleanPostIds) {
    counts.set(postId, { likes_count: 0, saves_count: 0 });
  }
  if (!cleanPostIds.length) return counts;

  const identityMap = await supabaseResolvePostIdentities(c, cleanPostIds);
  const identities = Array.from(identityMap.values());
  const legacyPostIds = Array.from(new Set(identities.map((identity) => identity.legacyPostId).filter(Boolean)));
  const uuidPostIds = Array.from(new Set(identities.map((identity) => identity.postUuid).filter(Boolean)));
  const keyAliases = new Map<string, Set<string>>();
  for (const identity of identities) {
    const keys = supabasePostIdentityKeys(identity);
    for (const key of keys) {
      const aliases = keyAliases.get(key) || new Set<string>();
      for (const alias of keys) aliases.add(alias);
      keyAliases.set(key, aliases);
    }
  }

  const rows: any[] = [];
  const filters = {
    legacy_post_id: postgrestInFilter(legacyPostIds.length ? legacyPostIds : cleanPostIds),
    kind: postgrestInFilter(['like', 'save']),
  };
  try {
    rows.push(...await supabaseAdminSelectRows(c, 'app_post_interactions', filters, 'legacy_post_id,post_id,kind,app_user_id,user_id,actor_key', Math.max(1000, cleanPostIds.length * 500)));
  } catch (error: any) {
    if (!isSupabaseColumnShapeError(error)) throw error;
    rows.push(...await supabaseAdminSelectRows(c, 'app_post_interactions', filters, 'legacy_post_id,kind,app_user_id', Math.max(1000, cleanPostIds.length * 500)));
  }
  if (uuidPostIds.length) {
    const nativeRows = await supabaseAdminSelectRowsIfShapeExists(c, 'app_post_interactions', {
      post_id: postgrestInFilter(uuidPostIds),
      kind: postgrestInFilter(['like', 'save']),
    }, 'legacy_post_id,post_id,kind,app_user_id,user_id,actor_key', Math.max(1000, uuidPostIds.length * 500));
    rows.push(...nativeRows);
  }

  const appUserIds = rows.map((row) => publicId(row?.app_user_id, 120)).filter(Boolean);
  const appToAuth = await supabaseAuthUserIdMapForAppUserIds(c, appUserIds);
  const appToIdentityActor = await supabaseAccountIdentityActorKeyMap(c, appUserIds);
  const actorsByPostAndKind = new Map<string, Set<string>>();
  for (const row of rows) {
    const rowPostKeys = Array.from(new Set([
      publicId(row?.legacy_post_id, 120),
      publicId(row?.post_id, 120),
    ].filter(Boolean)));
    const kind = cleanText(row?.kind, 20);
    if (!rowPostKeys.length || (kind !== 'like' && kind !== 'save')) continue;
    const actor = canonicalSupabaseInteractionActor(row, appToAuth, appToIdentityActor);
    if (!actor) continue;
    const targetKeys = new Set<string>();
    for (const rowPostKey of rowPostKeys) {
      const aliases = keyAliases.get(rowPostKey);
      if (aliases?.size) {
        for (const alias of aliases) targetKeys.add(alias);
      } else {
        targetKeys.add(rowPostKey);
      }
    }
    for (const targetKey of targetKeys) {
      const key = `${targetKey}:${kind}`;
      const actors = actorsByPostAndKind.get(key) || new Set<string>();
      actors.add(actor);
      actorsByPostAndKind.set(key, actors);
    }
  }

  for (const postId of cleanPostIds) {
    counts.set(postId, {
      likes_count: actorsByPostAndKind.get(`${postId}:like`)?.size || 0,
      saves_count: actorsByPostAndKind.get(`${postId}:save`)?.size || 0,
    });
  }
  return counts;
}

async function d1PostCommentCount(db: D1Database, postId: string): Promise<number> {
  try {
    const row: any = await db.prepare(
      "SELECT COUNT(*) AS count FROM comments WHERE post_id = ? AND COALESCE(status, 'active') NOT IN ('removed', 'hidden')"
    ).bind(postId).first();
    return Math.max(0, Number(row?.count || 0));
  } catch {
    return 0;
  }
}

async function getSupabasePostEngagementState(c: any, postId: string, userId: string) {
  const identity = await supabaseResolvePostIdentity(c, postId);
  const legacyPostId = identity.legacyPostId || identity.requestedPostId;
  const relatedUserIds = await supabaseRelatedInteractionUserIds(c, userId);
  const commentsCount = await supabasePostCommentCount(c, legacyPostId);
  let liked = await supabaseViewerPostInteractionExists(c, legacyPostId || postId, relatedUserIds, 'like');
  let saved = await supabaseViewerPostInteractionExists(c, legacyPostId || postId, relatedUserIds, 'save');
  const [supabaseLikesCount, supabaseSavesCount] = await Promise.all([
    supabasePostInteractionActorCount(c, legacyPostId || postId, 'like'),
    supabasePostInteractionActorCount(c, legacyPostId || postId, 'save'),
  ]);
  const state = {
    // Supabase app_post_interactions is the canonical engagement table.
    // D1 counters are legacy/cache only and must not inflate counts after
    // refreshes or app restarts.
    likes_count: Math.max(0, supabaseLikesCount),
    comments_count: commentsCount,
    saves_count: Math.max(0, supabaseSavesCount),
    liked,
    saved,
    engagement_source: 'supabase',
  };
  try {
    const patch = {
      likes_count: state.likes_count,
      comments_count: state.comments_count,
      saves_count: state.saves_count,
      updated_at: now(),
    };
    if (legacyPostId) await supabaseAdminPatchRows(c, 'app_posts', { legacy_post_id: postgrestEqFilter(legacyPostId) }, patch);
    if (identity.postUuid) await supabaseAdminPatchRows(c, 'app_posts', { id: postgrestEqFilter(identity.postUuid) }, patch);
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_post_counter_repair_failed', code: getErrorCode(error).slice(0, 180) }));
  }
  return state;
}

async function getCanonicalPostEngagementState(c: any, postId: string, userId: string) {
  if (!supabasePrimaryConfigured(c)) throw new Error('SUPABASE_PRIMARY_REQUIRED:engagement_state');
  try {
    return await getSupabasePostEngagementState(c, postId, userId);
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_engagement_state_failed', code: getErrorCode(error).slice(0, 180) }));
    throw error;
  }
}

async function setCanonicalPostLikeState(c: any, postId: string, userId: string, requested: boolean | null) {
  if (!supabasePrimaryConfigured(c)) throw new Error('SUPABASE_PRIMARY_REQUIRED:engagement_like');
  const identity = await supabaseResolvePostIdentity(c, postId);
  const canonicalPostId = identity.legacyPostId || identity.postUuid || identity.requestedPostId || postId;
  const relatedUserIds = await supabaseRelatedInteractionUserIds(c, userId);
  const wasLiked = await supabaseViewerPostInteractionExists(c, canonicalPostId, relatedUserIds, 'like');
  const nextLiked = requested === null ? !wasLiked : requested;

  await supabaseDeletePostInteractionsForUsers(c, canonicalPostId, relatedUserIds, 'like');
  if (nextLiked) {
    await supabaseUpsertPostInteraction(c, canonicalPostId, userId, 'like');
  }

  const state = await getCanonicalPostEngagementState(c, canonicalPostId, userId);
  state.liked = nextLiked;
  const changed = nextLiked !== wasLiked;
  return { state, wasLiked, changed };
}

async function setCanonicalPostSaveState(c: any, postId: string, userId: string, saved: boolean, collection = 'saved') {
  const collectionName = cleanText(collection, 80) || 'saved';
  if (!supabasePrimaryConfigured(c)) throw new Error('SUPABASE_PRIMARY_REQUIRED:engagement_save');
  const identity = await supabaseResolvePostIdentity(c, postId);
  const canonicalPostId = identity.legacyPostId || identity.postUuid || identity.requestedPostId || postId;
  const relatedUserIds = await supabaseRelatedInteractionUserIds(c, userId);
  const wasSaved = await supabaseViewerPostInteractionExists(c, canonicalPostId, relatedUserIds, 'save');

  await supabaseDeletePostInteractionsForUsers(c, canonicalPostId, relatedUserIds, 'save');
  if (saved) {
    await supabaseUpsertPostInteraction(c, canonicalPostId, userId, 'save', collectionName);
  }

  const state = await getCanonicalPostEngagementState(c, canonicalPostId, userId);
  state.saved = saved;
  const changed = saved !== wasSaved;
  return { state, wasSaved, changed, collection: collectionName };
}

async function overlaySupabaseViewerEngagement(c: any, posts: any[], userId: string): Promise<any[]> {
  if (!posts.length || !supabaseEngagementConfigured(c) || !publicId(userId, 120)) return posts;
  const postIds = Array.from(new Set(posts.flatMap((post) => [
    cleanText(post?.id, 120),
    cleanText(post?.legacy_post_id, 120),
    cleanText(post?.supabase_post_id, 120),
  ]).filter(Boolean)));
  if (!postIds.length) return posts;
  try {
    const relatedUserIds = await supabaseRelatedInteractionUserIds(c, userId);
    const keys = await supabaseInteractionActorKeys(c, relatedUserIds);
    const identityMap = await supabaseResolvePostIdentities(c, postIds);
    const identities = Array.from(identityMap.values());
    const legacyPostIds = Array.from(new Set(identities.map((identity) => identity.legacyPostId).filter(Boolean)));
    const uuidPostIds = Array.from(new Set(identities.map((identity) => identity.postUuid).filter(Boolean)));
    const keyAliases = new Map<string, Set<string>>();
    for (const identity of identities) {
      const aliasKeys = supabasePostIdentityKeys(identity);
      for (const key of aliasKeys) {
        const aliases = keyAliases.get(key) || new Set<string>();
        for (const alias of aliasKeys) aliases.add(alias);
        keyAliases.set(key, aliases);
      }
    }
    const [counts, appRows] = await Promise.all([
      supabasePostInteractionActorCounts(c, postIds),
      keys.appUserIds.length
        ? supabaseAdminSelectRows(c, 'app_post_interactions', {
        legacy_post_id: postgrestInFilter(legacyPostIds.length ? legacyPostIds : postIds),
        app_user_id: postgrestInFilter(keys.appUserIds),
        kind: postgrestInFilter(['like', 'save']),
          }, 'legacy_post_id,post_id,kind', Math.max(1, postIds.length * 2 * Math.max(1, relatedUserIds.length)))
        : Promise.resolve([] as any[]),
    ]);
    const rows: any[] = [...appRows];
    if (keys.actorKeys.length) {
      const actorRows = await supabaseAdminSelectRowsIfShapeExists(c, 'app_post_interactions', {
        legacy_post_id: postgrestInFilter(legacyPostIds.length ? legacyPostIds : postIds),
        actor_key: postgrestInFilter(keys.actorKeys),
        kind: postgrestInFilter(['like', 'save']),
      }, 'legacy_post_id,post_id,kind', Math.max(1, postIds.length * 2 * keys.actorKeys.length));
      rows.push(...actorRows);
      if (uuidPostIds.length) {
        const nativeActorRows = await supabaseAdminSelectRowsIfShapeExists(c, 'app_post_interactions', {
          post_id: postgrestInFilter(uuidPostIds),
          actor_key: postgrestInFilter(keys.actorKeys),
          kind: postgrestInFilter(['like', 'save']),
        }, 'legacy_post_id,post_id,kind', Math.max(1, uuidPostIds.length * 2 * keys.actorKeys.length));
        rows.push(...nativeActorRows);
      }
    }
    if (uuidPostIds.length && keys.appUserIds.length) {
      const nativeAppRows = await supabaseAdminSelectRowsIfShapeExists(c, 'app_post_interactions', {
        post_id: postgrestInFilter(uuidPostIds),
        app_user_id: postgrestInFilter(keys.appUserIds),
        kind: postgrestInFilter(['like', 'save']),
      }, 'legacy_post_id,post_id,kind', Math.max(1, uuidPostIds.length * 2 * Math.max(1, relatedUserIds.length)));
      rows.push(...nativeAppRows);
    }
    if (keys.authUserIds.length) {
      try {
        const legacyAuthRows = await supabaseAdminSelectRows(c, 'app_post_interactions', {
          legacy_post_id: postgrestInFilter(legacyPostIds.length ? legacyPostIds : postIds),
          user_id: postgrestInFilter(keys.authUserIds),
          kind: postgrestInFilter(['like', 'save']),
        }, 'legacy_post_id,post_id,kind', Math.max(1, postIds.length * 2 * keys.authUserIds.length));
        rows.push(...legacyAuthRows);
        if (uuidPostIds.length) {
          const nativeAuthRows = await supabaseAdminSelectRowsIfShapeExists(c, 'app_post_interactions', {
            post_id: postgrestInFilter(uuidPostIds),
            user_id: postgrestInFilter(keys.authUserIds),
            kind: postgrestInFilter(['like', 'save']),
          }, 'legacy_post_id,post_id,kind', Math.max(1, uuidPostIds.length * 2 * keys.authUserIds.length));
          rows.push(...nativeAuthRows);
        }
      } catch (error: any) {
        if (!isSupabaseColumnShapeError(error)) throw error;
      }
    }
    const liked = new Set<string>();
    const saved = new Set<string>();
    for (const row of rows) {
      const rowPostIds = Array.from(new Set([
        cleanText(row?.legacy_post_id, 120),
        cleanText(row?.post_id, 120),
      ].filter(Boolean)));
      const kind = cleanText(row?.kind, 20);
      for (const rowPostId of rowPostIds) {
        const aliases = keyAliases.get(rowPostId) || new Set([rowPostId]);
        for (const alias of aliases) {
          if (kind === 'like') liked.add(alias);
          if (kind === 'save') saved.add(alias);
        }
      }
    }
    return posts.map((post) => {
      const postKeys = Array.from(new Set([
        cleanText(post?.id, 120),
        cleanText(post?.legacy_post_id, 120),
        cleanText(post?.supabase_post_id, 120),
      ].filter(Boolean)));
      if (!postKeys.length) return post;
      const postId = postKeys[0];
      const viewerLiked = postKeys.some((key) => liked.has(key));
      const viewerSaved = postKeys.some((key) => saved.has(key));
      const countState = postKeys.map((key) => counts.get(key)).find(Boolean);
      return {
        ...post,
        likes_count: countState?.likes_count ?? Math.max(0, Number(post?.likes_count || 0)),
        saves_count: countState?.saves_count ?? Math.max(0, Number(post?.saves_count || 0)),
        is_liked: viewerLiked ? 1 : 0,
        viewer_liked: viewerLiked,
        liked_by_me: viewerLiked,
        saved: viewerSaved ? 1 : 0,
        is_saved: viewerSaved,
        viewer_saved: viewerSaved,
        saved_by_me: viewerSaved,
      };
    });
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_engagement_overlay_failed', code: getErrorCode(error).slice(0, 180) }));
    return posts;
  }
}

function postEngagementResponse(state: any, extra: Record<string, unknown> = {}) {
  const liked = state?.liked === true || state?.liked === 1 || state?.liked === '1';
  const saved = state?.saved === true || state?.saved === 1 || state?.saved === '1';
  const likesCount = Math.max(0, Number(state?.likes_count || 0));
  const commentsCount = Math.max(0, Number(state?.comments_count || 0));
  const savesCount = Math.max(0, Number(state?.saves_count || 0));
  return {
    ...extra,
    liked,
    is_liked: liked,
    liked_by_me: liked,
    viewer_liked: liked,
    likes_count: likesCount,
    comments_count: commentsCount,
    saved,
    is_saved: saved,
    saved_by_me: saved,
    viewer_saved: saved,
    saves_count: savesCount,
    engagement_source: cleanText(state?.engagement_source, 40) || undefined,
  };
}

function inPlaceholders(values: unknown[]): string {
  return values.map(() => '?').join(', ');
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
    publicPayload.email_verified = accountEmailVerified(user);
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

function normalizeOptionalPhone(input: unknown): string {
  const text = String(input || '').trim();
  if (!text) return '';
  try {
    return normalizePhone(text);
  } catch {
    return '';
  }
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
  return `${provider}_${safeSubject}@oauth.flames-up.com`;
}

function isInternalOAuthEmail(email: unknown): boolean {
  const clean = String(email || '').toLowerCase();
  return clean.endsWith('@oauth.flames-up.com') || clean.endsWith('@oauth.flames-up.local');
}

function isApplePrivateRelayEmail(email: unknown): boolean {
  return String(email || '').toLowerCase().endsWith('@privaterelay.appleid.com');
}

function publicUserEmail(email: unknown): string {
  return isInternalOAuthEmail(email) ? '' : String(email || '');
}

function accountEmailVerified(user: any): boolean {
  if (user?.email_verified === true || user?.email_verified === 1 || user?.email_verified === '1') return true;
  const email = normalizeOptionalEmail(user?.email);
  if (!email || isInternalOAuthEmail(email)) return false;
  const provider = normalizeAuthProvider(user?.oauth_provider || (user?.supabase_user_id ? 'supabase' : 'email'));
  return provider === 'google' || provider === 'apple' || provider === 'supabase';
}

async function privacyHash(c: any, value: unknown): Promise<string> {
  const clean = String(value || '').trim().toLowerCase();
  if (!clean) return '';
  const pepper = String(c.env.ABUSE_SIGNAL_SECRET || c.env.JWT_SECRET || 'captro').trim();
  return sha256Hex(`${pepper}:privacy:${clean}`);
}

function normalizeAuthProvider(value: unknown): 'email' | 'apple' | 'google' | 'phone' | 'supabase' {
  const provider = String(value || '').trim().toLowerCase();
  if (provider === 'apple' || provider === 'google' || provider === 'phone' || provider === 'supabase') return provider as any;
  return 'email';
}

async function upsertAccountIdentity(
  c: any,
  input: { userId: string; provider: unknown; providerUserId?: unknown; email?: unknown }
) {
  const userId = String(input.userId || '').trim();
  const provider = normalizeAuthProvider(input.provider);
  const email = normalizeOptionalEmail(input.email);
  const fallbackProviderId = provider === 'email' && email ? await privacyHash(c, email) : '';
  const providerUserId = cleanText(input.providerUserId || fallbackProviderId, 240);
  if (!userId || !providerUserId) return;
  const emailHash = email ? await privacyHash(c, email) : '';
  const ts = now();
  if (supabasePrimaryConfigured(c)) {
    await supabaseAdminUpsert(c, 'app_account_identities', [{
      id: uuid(),
      user_id: userId,
      provider,
      provider_user_id: providerUserId,
      email_hash: emailHash || null,
      created_at: ts,
      updated_at: ts,
    }], 'provider,provider_user_id');
    return;
  }
  await ensureAccountDeletionSchema(c.env.DB);
  await c.env.DB.prepare(
    `INSERT INTO account_identities (id, user_id, provider, provider_user_id, email_hash, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(provider, provider_user_id) DO UPDATE SET
       user_id = excluded.user_id,
       email_hash = COALESCE(NULLIF(excluded.email_hash, ''), account_identities.email_hash),
       updated_at = excluded.updated_at`
  ).bind(uuid(), userId, provider, providerUserId, emailHash, ts, ts).run();
}

async function writeAccountDeletionEvent(c: any, userId: string, eventType: string, metadata: Record<string, unknown> = {}, actorUserId = userId) {
  if (supabasePrimaryConfigured(c)) {
    await writeSupabaseAuditLog(c, {
      actionType: `account_${cleanText(eventType, 70) || 'event'}`,
      actorUserId: actorUserId || userId,
      actorRole: 'user',
      targetType: 'user',
      targetId: userId,
      targetUserId: userId,
      reason: cleanText((metadata.reason as any) || '', 180),
      metadata,
    });
    return;
  }
  await ensureAccountDeletionSchema(c.env.DB);
  await c.env.DB.prepare(
    `INSERT INTO account_deletion_events (id, user_id, event_type, actor_user_id, reason, metadata, request_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    uuid(),
    userId,
    cleanText(eventType, 80),
    publicId(actorUserId || '', 120),
    cleanText((metadata.reason as any) || '', 180),
    safeJsonState(scrubLogMetadata(metadata)),
    cleanText(c.get?.('requestId') || '', 120),
    now(),
  ).run();
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
  label: 'Captro Premium',
  amount_cents: 499,
  currency: 'usd',
  interval: 'month',
};

const PREMIUM_FEATURES = [
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

function premiumPayloadFromUser(user: any) {
  return {
    is_premium: userHasActivePremium(user),
    plan: user?.premium_plan || '',
    status: user?.premium_status || '',
    premium_until: user?.premium_until || '',
    monthly_price: '$4.99/month',
    amount_cents: PREMIUM_PLAN.amount_cents,
    currency: PREMIUM_PLAN.currency,
    interval: PREMIUM_PLAN.interval,
    features: PREMIUM_FEATURES,
  };
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

  // Legacy coin ledger: every backend balance mutation is recorded here for audit/history.
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

function getApnsConfig(c: any) {
  const teamId = String(c.env.APNS_TEAM_ID || '').trim();
  const keyId = String(c.env.APNS_KEY_ID || '').trim();
  const bundleId = String(c.env.APNS_BUNDLE_ID || '').trim();
  const privateKey = String(c.env.APNS_PRIVATE_KEY || '').replace(/\\n/g, '\n').trim();
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

async function sendAlertPushForNotification(c: any, input: {
  userId: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
}): Promise<string> {
  const config = getApnsConfig(c);
  if (!config) return 'apns_not_configured';

  let rows: any[] = [];
  if (supabasePrimaryConfigured(c)) {
    rows = await supabaseAdminQueryRows(c, 'app_push_tokens', {
      select: 'id,token,bundle_id,environment',
      filters: {
        user_id: postgrestEqFilter(input.userId),
        is_active: 'eq.true',
      },
      order: 'last_seen_at.desc',
      limit: 8,
    }).catch((error: any) => {
      console.warn(JSON.stringify({ event: 'supabase_push_token_lookup_failed', code: getErrorCode(error).slice(0, 180) }));
      return [];
    });
  } else {
    await ensureProductionReadinessSchema(c.env.DB);
    const tokens = await c.env.DB.prepare(
      `SELECT token, bundle_id, environment
       FROM push_tokens
       WHERE user_id = ? AND is_active = 1
       ORDER BY last_seen_at DESC
       LIMIT 8`
    ).bind(input.userId).all();
    rows = (tokens.results || []) as any[];
  }
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
        if (supabasePrimaryConfigured(c)) {
          await supabaseAdminPatchRows(c, 'app_push_tokens', { id: postgrestEqFilter(cleanText(row.id, 120)) }, { is_active: false, updated_at: now() })
            .catch((error: any) => console.warn(JSON.stringify({ event: 'supabase_push_token_deactivate_failed', code: getErrorCode(error).slice(0, 180) })));
        } else {
          await c.env.DB.prepare('UPDATE push_tokens SET is_active = 0, updated_at = ? WHERE token = ?')
            .bind(now(), token)
            .run();
        }
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
  let value = context?.[key];
  if (!value && Array.isArray(context)) {
    value = context.find((entry: any) => {
      const id = cleanText(entry?.id || entry?.mapbox_id || '', 120).toLowerCase();
      const type = cleanText(entry?.feature_type || entry?.type || '', 60).toLowerCase();
      return type === key || id.startsWith(`${key}.`) || id.includes(`.${key}.`);
    });
  }
  if (!value) return '';
  if (typeof value === 'string') return cleanText(value, 80);
  return cleanText(value.name || value.text || value.name_preferred || value.properties?.name || '', 80);
}

function mapboxFeatureToBroadLocation(feature: any) {
  const properties = feature?.properties || {};
  const context = properties.context || {};
  const featureType = cleanText(properties.feature_type || properties.type || '', 40).toLowerCase();
  const name = cleanText(properties.name || properties.name_preferred || '', 80);
  const cityFromContext = mapboxContextName(context, 'place')
    || mapboxContextName(context, 'locality')
    || mapboxContextName(context, 'neighborhood');
  let city = cityFromContext;
  let region = mapboxContextName(context, 'region');
  let country = mapboxContextName(context, 'country');

  if (['place', 'locality', 'neighborhood'].includes(featureType)) {
    city = name || city;
  } else if (featureType === 'region') {
    region = name || region;
  } else if (featureType === 'country') {
    country = name || country;
  } else if (!city && name) {
    city = name;
  }

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
  if (phoneAuthSchemaReady) return;

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

async function ensureAccountVerificationSchema(db: D1Database) {
  if (accountVerificationSchemaReady) return;

  await ensurePhoneAuthSchema(db);

  const statements = [
    'ALTER TABLE users ADD COLUMN email_verified INTEGER DEFAULT 0',
    'CREATE INDEX IF NOT EXISTS idx_users_email_verified ON users(email_verified)',
    'CREATE INDEX IF NOT EXISTS idx_users_phone_verified ON users(phone_verified)',
    `CREATE TABLE IF NOT EXISTS email_verification_links (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      email TEXT NOT NULL,
      token_hash TEXT NOT NULL UNIQUE,
      expires_at TEXT NOT NULL,
      used_at TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    )`,
    'CREATE INDEX IF NOT EXISTS idx_email_verification_links_user ON email_verification_links(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_email_verification_links_token ON email_verification_links(token_hash)',
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

  accountVerificationSchemaReady = true;
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

type TwilioVerifyChannel = 'sms' | 'email';

function twilioVerifyStartErrorResponse(c: any, errorMessage: string, target: 'phone' | 'email' = 'phone') {
  const failure = parseTwilioVerifyFailure(errorMessage);
  const isEmail = target === 'email';
  const targetLabel = isEmail ? 'email address' : 'phone number';
  const codePrefix = isEmail ? 'EMAIL' : 'PHONE';
  if (isTwilioVerifyRateLimited(failure)) {
    return c.json({
      detail: 'A verification code was already sent. Enter that code or wait before requesting a new one.',
      code: `${codePrefix}_VERIFICATION_RATE_LIMITED`,
      retry_after: failure.retryAfter || 60,
    }, 429);
  }

  if (failure.status === 400) {
    return c.json({
      detail: `Twilio could not send a code to that ${targetLabel}. Check it and try again.`,
      code: `${codePrefix}_VERIFY_SEND_REJECTED`,
    }, 400);
  }

  if (failure.status === 401 || failure.status === 403 || failure.status === 404) {
    return c.json({
      detail: `${isEmail ? 'Email' : 'Phone'} verification provider is not configured correctly. Check the Twilio Verify Service SID and auth settings.`,
      code: `${codePrefix}_PROVIDER_CONFIG`,
    }, 502);
  }

  return c.json({
    detail: 'Could not send verification code. Check Twilio Verify settings.',
    code: `${codePrefix}_VERIFY_START_FAILED`,
  }, 502);
}

function randomUrlToken(bytes = 32): string {
  const values = new Uint8Array(bytes);
  crypto.getRandomValues(values);
  let binary = '';
  for (const value of values) binary += String.fromCharCode(value);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function emailVerificationBaseUrl(c: any): string {
  const configured = String(c.env.EMAIL_VERIFICATION_BASE_URL || c.env.PUBLIC_API_BASE_URL || '').trim();
  if (configured) return configured.replace(/\/+$/g, '');
  const url = new URL(c.req.url);
  return `${url.origin}/api`;
}

function emailVerificationLink(c: any, token: string): string {
  return `${emailVerificationBaseUrl(c)}/users/me/email/verify-link?token=${encodeURIComponent(token)}`;
}

async function sendEmailVerificationLink(c: any, email: string, link: string): Promise<boolean> {
  const apiKey = String(c.env.RESEND_API_KEY || '').trim();
  const from = String(c.env.EMAIL_FROM || '').trim();
  if (!apiKey || !from) return false;

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to: [email],
      subject: 'Verify your Captro email',
      text: `Tap this link to verify your Captro email:\n\n${link}\n\nThis link expires in 30 minutes. If you did not request it, you can ignore this email.`,
      html: `
        <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;line-height:1.55;color:#111;padding:24px">
          <h1 style="font-size:24px;margin:0 0 12px">Verify your Captro email</h1>
          <p>Tap the button below to verify your Captro account email.</p>
          <p style="margin:24px 0">
            <a href="${link}" style="display:inline-block;background:#0f2d18;color:#fff;text-decoration:none;padding:13px 20px;border-radius:999px;font-weight:700">Verify email</a>
          </p>
          <p style="color:#555;font-size:14px">This link expires in 30 minutes. If you did not request it, you can ignore this email.</p>
        </div>
      `,
    }),
  });

  if (!response.ok) {
    const safeStatus = response.status;
    throw new Error(`EMAIL_LINK_SEND_FAILED:${safeStatus}`);
  }
  return true;
}

async function startTwilioChannelVerification(c: any, to: string, channel: TwilioVerifyChannel): Promise<boolean> {
  const config = getTwilioVerifyConfig(c);
  if (!config) return false;

  const body = new URLSearchParams({
    To: to,
    Channel: channel,
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

async function startTwilioVerification(c: any, phone: string): Promise<boolean> {
  return startTwilioChannelVerification(c, phone, 'sms');
}

async function checkTwilioChannelVerification(c: any, to: string, code: string): Promise<boolean> {
  const config = getTwilioVerifyConfig(c);
  if (!config) return false;

  const body = new URLSearchParams({
    To: to,
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

async function checkTwilioVerification(c: any, phone: string, code: string): Promise<boolean> {
  return checkTwilioChannelVerification(c, phone, code);
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
  await ensureSupabaseAuthSchema(c.env.DB);
  let user: any = await c.env.DB.prepare('SELECT * FROM users WHERE phone = ?').bind(phone).first();
  if (!user) {
    const digits = phone.replace(/\D/g, '');
    const safeName = String(fullName || '').trim() || 'Flames User';
    const email = `${digits}@phone.flames-up.local`;
    const generatedPasswordHash = await hashPassword(`phone_${phone}_${uuid()}`);
    let supabaseUser: any = null;
    try {
      const result = await createOrFindSupabaseAuthUser(c, {
        phone,
        username: '',
        fullName: safeName,
        provider: 'phone',
      });
      supabaseUser = result.user;
    } catch (error: any) {
      console.warn(JSON.stringify({ event: 'supabase_phone_auth_mirror_failed', code: getErrorCode(error).slice(0, 160) }));
    }
    const preferredId = isUuidText(supabaseUser?.id);
    const idOwner = preferredId ? await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(preferredId).first() : null;
    const id = preferredId && !idOwner ? preferredId : uuid();
    const username = pendingUsernameForUser(id);

    await c.env.DB.prepare(
      'INSERT INTO users (id, email, username, full_name, password_hash, phone, phone_verified, supabase_user_id) VALUES (?, ?, ?, ?, ?, ?, 1, ?)'
    ).bind(id, email, username, safeName, generatedPasswordHash, phone, supabaseUser?.id || null).run();
    user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
    if (supabaseUser?.id) {
      runBackgroundTask(c, 'supabase_phone_metadata_sync_failed', async () => {
        await syncSupabaseAuthMetadataForUser(c, user);
      });
    }
    await recordAbuseSignals(c, id, 'phone_signup', { username, display_name: safeName });
  } else if (!user.phone_verified) {
    await c.env.DB.prepare('UPDATE users SET phone_verified = 1, updated_at = datetime(\'now\') WHERE id = ?').bind(user.id).run();
    user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(user.id).first();
  }

  if (user && !user.supabase_user_id) {
    try {
      const result = await createOrFindSupabaseAuthUser(c, {
        phone,
        username: publicUsernameFor(user),
        fullName: user.full_name,
        profileImage: user.profile_image,
        provider: 'phone',
        appUserId: user.id,
      });
      if (result.user?.id) {
        await linkSupabaseAuthUser(c, user.id, result.user.id);
        user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(user.id).first();
      }
    } catch (error: any) {
      console.warn(JSON.stringify({ event: 'supabase_phone_auth_link_failed', code: getErrorCode(error).slice(0, 160) }));
    }
  }

  return user;
}

function authUserPayload(user: any) {
  const onboardingRequired = usernameNeedsOnboarding(user);
  return {
    id: user.id,
    email: publicUserEmail(user.email),
    email_verified: accountEmailVerified(user),
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
    status: String(user.status || 'active'),
    deletion_requested_at: user.deletion_requested_at || null,
    deletion_scheduled_at: user.deletion_scheduled_at || null,
    auth_provider: normalizeAuthProvider(user.oauth_provider || (user.phone ? 'phone' : 'email')),
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

function safeOAuthDiagnosticCode(error: any): string {
  const raw = getErrorCode(error);
  const prefix = raw.split(':', 1)[0] || 'UNKNOWN';
  return cleanText(prefix, 80).replace(/[^A-Za-z0-9_.-]/g, '_') || 'UNKNOWN';
}

function logOAuthStage(
  c: any,
  provider: 'google' | 'apple',
  stage: string,
  outcome: 'started' | 'passed' | 'failed',
  error?: any,
  strategy?: string
) {
  const payload: Record<string, unknown> = {
    event: 'oauth_stage',
    request_id: c.get?.('requestId') || '',
    provider,
    stage: cleanText(stage, 60),
    outcome,
  };
  if (strategy) payload.strategy = cleanText(strategy, 40);
  if (error) payload.code = safeOAuthDiagnosticCode(error);
  const line = JSON.stringify(payload);
  if (outcome === 'failed') console.warn(line);
  else console.info(line);
}

async function verifyAppleIdToken(c: any, idToken: string, rawNonce = '') {
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
  const tokenNonce = cleanText(payload.nonce, 512);
  const nonce = cleanText(rawNonce, 512);
  if (tokenNonce) {
    if (!nonce) throw new Error('APPLE_NONCE_REQUIRED');
    const expectedNonce = await sha256Hex(nonce);
    if (tokenNonce !== expectedNonce) throw new Error('APPLE_NONCE_MISMATCH');
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
    await upsertAccountIdentity(c, { userId: user.id, provider, providerUserId: normalizedSubject, email: providedEmail || user.email });
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
    await upsertAccountIdentity(c, { userId: refreshed.id, provider, providerUserId: normalizedSubject, email: providedEmail || refreshed.email });
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
  await upsertAccountIdentity(c, { userId: id, provider, providerUserId: normalizedSubject, email: providedEmail || normalizedEmail });
  return c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
}

async function mirrorOAuthUserToSupabaseAuth(c: any, user: any, provider: 'google' | 'apple', subject: string) {
  if (!user?.id || user.supabase_user_id) return user;
  const email = normalizeOptionalEmail(user.email);
  if (!email || isInternalOAuthEmail(email)) return user;

  const result = await createOrFindSupabaseAuthUser(c, {
    email,
    username: publicUsernameFor(user),
    fullName: user.full_name,
    profileImage: user.profile_image,
    provider,
    oauthSubject: subject,
    appUserId: user.id,
  });
  if (result.user?.id) {
    await linkSupabaseAuthUser(c, user.id, result.user.id);
    await syncSupabaseAuthMetadataForUser(c, { ...user, supabase_user_id: result.user.id });
    return c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(user.id).first();
  }
  return user;
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
  try {
    const { payload } = await jwtVerify(token, jwks, { issuer });
    if (!payload.sub) throw new Error('SUPABASE_SUBJECT_MISSING');
    return payload as any;
  } catch (localVerifyError: any) {
    const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        apikey: getSupabaseAuthClientKey(c),
        Authorization: `Bearer ${token}`,
      },
    });
    if (!response.ok) {
      const text = await response.text().catch(() => '');
      throw new Error(`SUPABASE_TOKEN_USER_LOOKUP_FAILED:${response.status}:${text.slice(0, 160)}:${getErrorCode(localVerifyError).slice(0, 120)}`);
    }
    const user: any = await response.json().catch(() => ({}));
    const userId = isUuidText(user?.id);
    if (!userId) throw new Error('SUPABASE_SUBJECT_MISSING');
    const unsafePayload = decodeJwtPayloadUnsafe(token);
    return {
      ...unsafePayload,
      sub: userId,
      email: normalizeOptionalEmail(user?.email || unsafePayload?.email),
      phone: normalizeOptionalPhone(user?.phone || unsafePayload?.phone),
      app_metadata: user?.app_metadata && typeof user.app_metadata === 'object'
        ? user.app_metadata
        : (unsafePayload?.app_metadata || {}),
      user_metadata: user?.user_metadata && typeof user.user_metadata === 'object'
        ? user.user_metadata
        : (unsafePayload?.user_metadata || {}),
    };
  }
}

async function findOrCreateSupabaseUser(c: any, payload: any, extras: any = {}) {
  await ensureOAuthSchema(c.env.DB);
  await ensureSupabaseAuthSchema(c.env.DB);
  const supabaseUserId = String(payload.sub || '').trim();
  const email = normalizeOptionalEmail(payload.email || extras.email);
  const metadata = payload.user_metadata && typeof payload.user_metadata === 'object' ? payload.user_metadata : {};
  const safeFullName = normalizeOptionalName(extras.full_name || metadata.full_name || metadata.name || email.split('@')[0] || 'Flames User');
  const profileImage = cleanText(metadata.avatar_url || metadata.picture || extras.profile_image || '', 1000);
  const authProvider = normalizeAuthProvider(extras.auth_provider || extras.provider || payload.app_metadata?.provider || payload.app_metadata?.providers?.[0] || metadata.provider || 'supabase');
  const providerSubject = cleanText(extras.oauth_subject || extras.provider_user_id || (authProvider === 'supabase' ? supabaseUserId : ''), 240) || supabaseUserId;

  if (!supabaseUserId) throw new Error('SUPABASE_SUBJECT_MISSING');

  let user: any = await c.env.DB.prepare('SELECT * FROM users WHERE supabase_user_id = ?').bind(supabaseUserId).first();
  if (user) {
    if (['apple', 'google'].includes(authProvider) && providerSubject && (user.oauth_provider !== authProvider || user.oauth_subject !== providerSubject)) {
      await c.env.DB.prepare('UPDATE users SET oauth_provider = ?, oauth_subject = ?, updated_at = datetime(\'now\') WHERE id = ?')
        .bind(authProvider, providerSubject, user.id)
        .run();
      user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(user.id).first();
    }
    await upsertAccountIdentity(c, { userId: user.id, provider: authProvider, providerUserId: providerSubject, email: email || user.email });
    return user;
  }
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
    if (['apple', 'google'].includes(authProvider) && providerSubject) {
      await c.env.DB.prepare('UPDATE users SET oauth_provider = ?, oauth_subject = ?, updated_at = datetime(\'now\') WHERE id = ?')
        .bind(authProvider, providerSubject, user.id)
        .run();
    }
    const refreshed = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(user.id).first();
    await upsertAccountIdentity(c, { userId: refreshed.id, provider: authProvider, providerUserId: providerSubject, email: email || refreshed.email });
    return refreshed;
  }

  const idOwner = await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(supabaseUserId).first();
  const id = idOwner ? uuid() : supabaseUserId;
  const username = pendingUsernameForUser(id);
  const generatedPasswordHash = await hashPassword(`supabase_${supabaseUserId}_${uuid()}`);

  await c.env.DB.prepare(
    'INSERT INTO users (id, email, username, full_name, password_hash, profile_image, supabase_user_id, oauth_provider, oauth_subject) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
  ).bind(id, email, username, safeFullName || username, generatedPasswordHash, profileImage, supabaseUserId, authProvider, providerSubject).run();

  await recordAbuseSignals(c, id, 'supabase_signup', { username, display_name: safeFullName || username });
  await upsertAccountIdentity(c, { userId: id, provider: authProvider, providerUserId: providerSubject, email });
  return c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
}

const SUPABASE_APP_USER_SELECT = 'id,supabase_user_id,email,username,full_name,avatar_url,cover_url,bio,city,is_private,is_verified,counts,profile,metadata,phone,phone_verified,email_verified,legacy_created_at,legacy_updated_at,created_at,updated_at';

function supabaseAppUserToLegacyUser(row: any): any {
  const metadata = parseJsonObject(row?.metadata);
  const profile = parseJsonObject(row?.profile);
  const counts = parseJsonObject(row?.counts);
  const status = cleanText((metadata as any).status || 'active', 40) || 'active';
  return {
    id: publicId(row?.id, 120),
    supabase_user_id: isUuidText(row?.supabase_user_id),
    email: normalizeOptionalEmail(row?.email),
    username: cleanText(row?.username, 80),
    full_name: cleanText(row?.full_name, 160),
    profile_image: safeMediaReference(row?.avatar_url),
    cover_image: safeMediaReference(row?.cover_url),
    bio: cleanText(row?.bio, 800),
    city: cleanText(row?.city, 160),
    social_website: safeExternalUrl((profile as any).social_website),
    social_tiktok: cleanText((profile as any).social_tiktok, 120),
    social_instagram: cleanText((profile as any).social_instagram, 120),
    age: clampNumber((profile as any).age, 13, 120, 0),
    looking_for: cleanText((profile as any).looking_for, 120),
    interests: Array.isArray((profile as any).interests)
      ? JSON.stringify((profile as any).interests.map((item: unknown) => cleanText(item, 60)).filter(Boolean).slice(0, 24))
      : cleanText((profile as any).interests, 1000),
    profile_background_image: safeMediaReference((profile as any).profile_background_image || row?.cover_url),
    followers_count: Math.max(0, Number((counts as any).followers_count || 0)),
    following_count: Math.max(0, Number((counts as any).following_count || 0)),
    posts_count: Math.max(0, Number((counts as any).posts_count || 0)),
    is_private: row?.is_private ? 1 : 0,
    is_verified: row?.is_verified ? 1 : 0,
    phone: normalizeOptionalPhone(row?.phone),
    phone_verified: row?.phone_verified ? 1 : 0,
    email_verified: row?.email_verified ? 1 : 0,
    language: normalizeLanguage((profile as any).language),
    status,
    deletion_requested_at: cleanText((metadata as any).deletion_requested_at, 80),
    deletion_scheduled_at: cleanText((metadata as any).deletion_scheduled_at, 80),
    suspended_until: cleanText((metadata as any).suspended_until, 80),
    session_revoked_at: cleanText((metadata as any).session_revoked_at, 80),
    banned_at: cleanText((metadata as any).banned_at, 80),
    ban_reason: cleanText((metadata as any).ban_reason, 240),
    oauth_provider: cleanText((metadata as any).oauth_provider, 40),
    oauth_subject: cleanText((metadata as any).oauth_subject, 240),
    created_at: row?.legacy_created_at || row?.created_at,
    updated_at: row?.legacy_updated_at || row?.updated_at,
    source: 'supabase_postgres',
  };
}

async function getSupabaseSessionUserByAnyId(c: any, inputId: string): Promise<any | null> {
  const row = await getSupabaseAppUserRowByAnyId(c, inputId);
  return row ? supabaseAppUserToLegacyUser(row) : null;
}

async function supabaseClearExpiredSuspension(c: any, userId: string) {
  const row = await getSupabaseAppUserRowByAnyId(c, userId);
  if (!row) return;
  const metadata = parseJsonObject(row.metadata);
  metadata.status = 'active';
  delete metadata.suspended_until;
  await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(publicId(row.id, 120)) }, {
    metadata,
    updated_at: now(),
  });
}

async function getSupabaseAppUserRowByAnyId(c: any, inputId: string): Promise<any | null> {
  const cleanId = publicId(inputId, 120);
  if (!cleanId || !supabasePrimaryConfigured(c)) return null;
  const filters: Record<string, string> = isUuidText(cleanId)
    ? { or: `(id.eq.${cleanId},supabase_user_id.eq.${cleanId})` }
    : { id: postgrestEqFilter(cleanId) };
  const rows = await supabaseAdminQueryRows(c, 'app_users', {
    select: SUPABASE_APP_USER_SELECT,
    filters,
    limit: 1,
  }).catch((error: any) => {
    console.warn(JSON.stringify({ event: 'supabase_session_user_lookup_failed', code: getErrorCode(error).slice(0, 180) }));
    return [];
  });
  return rows[0] || null;
}

async function supabasePhoneOwnerId(c: any, phone: string): Promise<string> {
  if (!supabasePrimaryConfigured(c)) return '';
  const rows = await supabaseAdminQueryRows(c, 'app_users', {
    select: 'id',
    filters: { phone: postgrestEqFilter(phone) },
    limit: 2,
  }).catch((error: any) => {
    console.warn(JSON.stringify({ event: 'supabase_phone_owner_lookup_failed', code: getErrorCode(error).slice(0, 180) }));
    return [];
  });
  return cleanText(rows[0]?.id || '', 120);
}

async function supabaseExpireAccountVerificationTokens(c: any, userId: string, tokenType: string, target: string) {
  await supabaseAdminPatchRows(c, 'app_account_verification_tokens', {
    user_id: postgrestEqFilter(userId),
    token_type: postgrestEqFilter(tokenType),
    target: postgrestEqFilter(target),
    used_at: 'is.null',
  }, { used_at: now(), updated_at: now() });
}

async function supabaseCreateAccountVerificationToken(c: any, input: {
  userId: string;
  tokenType: string;
  target: string;
  tokenHash: string;
  expiresAt: string;
}) {
  await supabaseAdminUpsert(c, 'app_account_verification_tokens', [{
    id: uuid(),
    user_id: input.userId,
    token_type: input.tokenType,
    target: input.target,
    token_hash: input.tokenHash,
    attempts: 0,
    expires_at: input.expiresAt,
    created_at: now(),
    updated_at: now(),
  }], 'id');
}

async function supabaseLatestAccountVerificationToken(c: any, tokenType: string, target: string): Promise<any | null> {
  const rows = await supabaseAdminQueryRows(c, 'app_account_verification_tokens', {
    select: 'id,user_id,target,token_hash,attempts,expires_at,used_at,created_at',
    filters: {
      token_type: postgrestEqFilter(tokenType),
      target: postgrestEqFilter(target),
      used_at: 'is.null',
    },
    order: 'created_at.desc',
    limit: 1,
  });
  return rows[0] || null;
}

async function supabaseAccountVerificationTokenByHash(c: any, tokenType: string, tokenHash: string): Promise<any | null> {
  const rows = await supabaseAdminQueryRows(c, 'app_account_verification_tokens', {
    select: 'id,user_id,target,token_hash,attempts,expires_at,used_at,created_at',
    filters: {
      token_type: postgrestEqFilter(tokenType),
      token_hash: postgrestEqFilter(tokenHash),
      used_at: 'is.null',
    },
    limit: 1,
  });
  return rows[0] || null;
}

async function findOrCreateSupabaseAppUser(c: any, payload: any, extras: any = {}) {
  const supabaseUserId = isUuidText(payload?.sub);
  if (!supabaseUserId) throw new Error('SUPABASE_SUBJECT_MISSING');
  const email = normalizeOptionalEmail(payload.email || extras.email);
  const metadata = payload.user_metadata && typeof payload.user_metadata === 'object' ? payload.user_metadata : {};
  const safeFullName = normalizeOptionalName(extras.full_name || (metadata as any).full_name || (metadata as any).name || (email ? email.split('@')[0] : '') || 'Captro User');
  const requestedUsername = normalizeOptionalName(extras.username || (metadata as any).username || '');
  const requestedUsernameCheck = requestedUsername ? validateUsernameForAccount(requestedUsername) : { ok: false, username: '' };
  const profileImage = cleanText((metadata as any).avatar_url || (metadata as any).picture || extras.profile_image || '', 1000);
  const authProvider = normalizeAuthProvider(extras.auth_provider || extras.provider || payload.app_metadata?.provider || payload.app_metadata?.providers?.[0] || (metadata as any).provider || 'supabase');
  const providerSubject = cleanText(extras.oauth_subject || extras.provider_user_id || supabaseUserId, 240);
  const select = 'id,supabase_user_id,email,username,full_name,avatar_url,cover_url,bio,city,is_private,is_verified,counts,profile,metadata,phone,phone_verified,email_verified,legacy_created_at,legacy_updated_at,created_at,updated_at';

  let rows = await supabaseAdminQueryRows(c, 'app_users', {
    select,
    filters: { supabase_user_id: postgrestEqFilter(supabaseUserId) },
    limit: 1,
  });
  if (!rows.length && email) {
    rows = await supabaseAdminQueryRows(c, 'app_users', {
      select,
      filters: { email: postgrestEqFilter(email) },
      limit: 1,
    });
    if (rows[0] && !isUuidText(rows[0].supabase_user_id)) {
      await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(publicId(rows[0].id, 120)) }, {
        supabase_user_id: supabaseUserId,
        updated_at: now(),
      });
      rows[0].supabase_user_id = supabaseUserId;
    }
  }
  if (rows[0]) return supabaseAppUserToLegacyUser(rows[0]);

  const appUserId = supabaseUserId;
  const desiredUsername = requestedUsernameCheck.ok ? requestedUsernameCheck.username : pendingUsernameForUser(appUserId);
  const username = await ensureUniqueSupabaseUsername(c, desiredUsername, appUserId);
  const row = {
    id: appUserId,
    supabase_user_id: supabaseUserId,
    email: email || null,
    username,
    full_name: safeFullName || username,
    avatar_url: profileImage || null,
    cover_url: null,
    bio: '',
    city: '',
    is_private: false,
    is_verified: false,
    counts: { followers_count: 0, following_count: 0, posts_count: 0 },
    profile: { language: normalizeLanguage(extras.language), phone_verified: false },
    metadata: {
      source: 'supabase_auth_primary',
      status: 'active',
      oauth_provider: authProvider,
      oauth_subject: providerSubject,
    },
    created_at: now(),
    updated_at: now(),
  };
  await supabaseAdminUpsert(c, 'app_users', [row], 'id');
  return supabaseAppUserToLegacyUser(row);
}

async function resolveSupabaseSessionUser(c: any, token: string) {
  const supabasePayload = await verifySupabaseAccessToken(c, token);
  const user = await findOrCreateSupabaseAppUser(c, supabasePayload, { email: supabasePayload.email });
  const userId = String(user?.id || '');
  if (!userId) throw new Error('USER_NOT_FOUND');

  return {
    userId,
    payload: {
      sub: userId,
      userId,
      auth_provider: 'supabase',
      supabase_sub: String(supabasePayload.sub || ''),
      iat: supabasePayload.iat,
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

function getSupabaseAuthClientKey(c: any): string {
  const key = String(c.env.SUPABASE_ANON_KEY || c.env.SUPABASE_PUBLISHABLE_KEY || '').trim();
  if (!key) throw new Error('SUPABASE_AUTH_KEY_MISSING');
  return key;
}

function supabaseAuthProvider(provider: unknown): 'email' | 'phone' | 'google' | 'apple' | 'supabase' {
  const clean = String(provider || '').trim().toLowerCase();
  if (clean === 'phone' || clean === 'google' || clean === 'apple' || clean === 'supabase') return clean as any;
  return 'email';
}

function supabasePublicAuthHeaders(c: any): HeadersInit {
  const apiKey = getSupabaseAuthClientKey(c);
  return {
    apikey: apiKey,
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
}

function supabaseAdminAuthHeaders(c: any): HeadersInit {
  const serviceRoleKey = getSupabaseServiceRoleKey(c);
  return {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    'Content-Type': 'application/json',
  };
}

function supabaseAuthUserFromResponse(data: any): any {
  if (data?.user?.id) return data.user;
  if (data?.id) return data;
  return null;
}

function decodeJwtPayloadUnsafe(token: unknown): any {
  const raw = String(token || '').trim();
  const payload = raw.split('.')[1] || '';
  if (!payload) return {};
  try {
    const padded = payload.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(payload.length / 4) * 4, '=');
    return JSON.parse(atob(padded));
  } catch {
    return {};
  }
}

function supabaseOAuthSubjectFromSession(session: any, provider: 'google' | 'apple', idToken: unknown): string {
  const user = session?.user || {};
  const identities = Array.isArray(user?.identities) ? user.identities : [];
  for (const identity of identities) {
    if (String(identity?.provider || '').toLowerCase() !== provider) continue;
    const data = identity?.identity_data && typeof identity.identity_data === 'object' ? identity.identity_data : {};
    const subject = cleanText(data.sub || identity?.id || identity?.identity_id || '', 240);
    if (subject) return subject;
  }
  const payload = decodeJwtPayloadUnsafe(idToken);
  return cleanText(payload?.sub || user?.id || '', 240);
}

function supabaseOAuthProfileFromSession(session: any, idToken: unknown): { email: string; fullName: string; profileImage: string } {
  const user = session?.user || {};
  const metadata = user?.user_metadata && typeof user.user_metadata === 'object' ? user.user_metadata : {};
  const payload = decodeJwtPayloadUnsafe(idToken);
  const email = normalizeOptionalEmail(user?.email || payload?.email);
  return {
    email,
    fullName: normalizeOptionalName(metadata.full_name || metadata.name || metadata.display_name || payload?.name || safeDisplayNameFromEmail(email)),
    profileImage: safeMediaReference(metadata.avatar_url || metadata.picture || payload?.picture || ''),
  };
}

function supabaseProfileMetadata(input: {
  appUserId?: unknown;
  username?: unknown;
  fullName?: unknown;
  profileImage?: unknown;
  language?: unknown;
  phone?: unknown;
  emailVerified?: unknown;
  termsVersion?: unknown;
  termsAcceptedAt?: unknown;
}) {
  const metadata: Record<string, string> = {};
  const appUserId = cleanText(input.appUserId, 120);
  const username = cleanText(input.username, 80);
  const fullName = cleanText(input.fullName, 160);
  const profileImage = cleanText(input.profileImage, 1200);
  const language = normalizeLanguage(input.language);
  const phone = cleanText(input.phone, 40);

  if (appUserId) metadata.captro_user_id = appUserId;
  if (username) {
    metadata.username = username;
    metadata.captro_username = username;
  }
  if (fullName) {
    metadata.full_name = fullName;
    metadata.name = fullName;
    metadata.display_name = fullName;
  }
  if (profileImage) {
    metadata.avatar_url = profileImage;
    metadata.picture = profileImage;
  }
  if (language) metadata.language = language;
  if (phone) metadata.phone = phone;
  if (input.emailVerified === true || input.emailVerified === 1 || input.emailVerified === '1') {
    metadata.email_verified = 'true';
  }
  const terms = termsAcceptanceFromBody({
    termsVersion: input.termsVersion,
    termsAcceptedAt: input.termsAcceptedAt,
  });
  Object.assign(metadata, termsAcceptanceMetadata(terms));
  return metadata;
}

function supabaseProviderMetadata(provider: unknown, appUserId?: unknown, oauthSubject?: unknown) {
  const cleanProvider = supabaseAuthProvider(provider);
  const metadata: Record<string, any> = {
    provider: cleanProvider,
    providers: [cleanProvider],
    captro_auth_source: 'captro_worker',
  };
  const cleanAppUserId = cleanText(appUserId, 120);
  const cleanSubject = cleanText(oauthSubject, 240);
  if (cleanAppUserId) metadata.captro_user_id = cleanAppUserId;
  if (cleanSubject) metadata.oauth_subject = cleanSubject;
  return metadata;
}

function supabaseAuthCreatePayload(input: {
  email?: unknown;
  phone?: unknown;
  password?: unknown;
  username?: unknown;
  fullName?: unknown;
  profileImage?: unknown;
  provider?: 'email' | 'phone' | 'google' | 'apple' | 'supabase';
  oauthSubject?: unknown;
  appUserId?: unknown;
  termsVersion?: unknown;
  termsAcceptedAt?: unknown;
}) {
  const provider = supabaseAuthProvider(input.provider);
  const email = normalizeOptionalEmail(input.email);
  const phone = normalizeOptionalPhone(input.phone);
  const password = String(input.password || '');
  const body: any = {
    user_metadata: supabaseProfileMetadata({
      appUserId: input.appUserId,
      username: input.username,
      fullName: input.fullName,
      profileImage: input.profileImage,
      phone,
      termsVersion: input.termsVersion,
      termsAcceptedAt: input.termsAcceptedAt,
    }),
    app_metadata: supabaseProviderMetadata(provider, input.appUserId, input.oauthSubject),
  };

  if (email && (!isInternalOAuthEmail(email) || provider === 'google' || provider === 'apple')) {
    body.email = email;
    body.email_confirm = true;
  }
  if (phone) {
    body.phone = phone;
    body.phone_confirm = true;
  }
  if (password) body.password = password;
  if (!body.email && !body.phone) throw new Error('SUPABASE_AUTH_IDENTIFIER_REQUIRED');
  return body;
}

async function findSupabaseAuthUser(c: any, input: { email?: unknown; phone?: unknown; id?: unknown }) {
  const id = isUuidText(input.id);
  if (id) {
    const response = await fetch(`${getSupabaseUrl(c)}/auth/v1/admin/users/${encodeURIComponent(id)}`, {
      headers: supabaseAdminAuthHeaders(c),
    });
    if (response.ok) return supabaseAuthUserFromResponse(await response.json().catch(() => ({})));
    if (response.status !== 404) {
      const text = await response.text().catch(() => '');
      throw new Error(`SUPABASE_AUTH_LOOKUP_FAILED:${response.status}:${text.slice(0, 200)}`);
    }
  }

  const email = normalizeOptionalEmail(input.email);
  const phone = normalizeOptionalPhone(input.phone);
  const filter = email || phone;
  if (!filter) return null;
  const response = await fetch(`${getSupabaseUrl(c)}/auth/v1/admin/users?page=1&per_page=100&filter=${encodeURIComponent(filter)}`, {
    headers: supabaseAdminAuthHeaders(c),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_AUTH_LIST_FAILED:${response.status}:${text.slice(0, 200)}`);
  }
  const data: any = await response.json().catch(() => ({}));
  const users = Array.isArray(data?.users) ? data.users : Array.isArray(data) ? data : [];
  return users.find((user: any) => {
    const userEmail = normalizeOptionalEmail(user?.email);
    const userPhone = normalizeOptionalPhone(user?.phone);
    return (email && userEmail === email) || (phone && userPhone === phone);
  }) || null;
}

async function findSupabaseAuthUserForOAuthSubject(
  c: any,
  provider: unknown,
  oauthSubject: unknown
) {
  const cleanProvider = supabaseAuthProvider(provider);
  const cleanSubject = cleanText(oauthSubject, 240);
  if (!['google', 'apple'].includes(cleanProvider) || !cleanSubject) return null;

  const identities = await supabaseAdminQueryRows(c, 'app_account_identities', {
    select: 'user_id',
    filters: {
      provider: postgrestEqFilter(cleanProvider),
      provider_user_id: postgrestEqFilter(cleanSubject),
    },
    limit: 1,
  });
  const appUserId = publicId(identities[0]?.user_id, 120);
  if (!appUserId) return null;

  const appUsers = await supabaseAdminQueryRows(c, 'app_users', {
    select: 'supabase_user_id',
    filters: { id: postgrestEqFilter(appUserId) },
    limit: 1,
  });
  const supabaseUserId = isUuidText(appUsers[0]?.supabase_user_id);
  return supabaseUserId ? findSupabaseAuthUser(c, { id: supabaseUserId }) : null;
}

function mergedSupabaseProviderMetadata(existing: any, provider: unknown, appUserId?: unknown, oauthSubject?: unknown) {
  const next = supabaseProviderMetadata(provider, appUserId, oauthSubject);
  const current = existing?.app_metadata && typeof existing.app_metadata === 'object' ? existing.app_metadata : {};
  const providers = Array.from(new Set([
    ...(Array.isArray(current.providers) ? current.providers : []),
    ...(Array.isArray(next.providers) ? next.providers : []),
  ].map((value) => cleanText(value, 40)).filter(Boolean)));
  return {
    ...current,
    ...next,
    providers,
  };
}

async function updateExistingSupabaseAuthUser(c: any, existing: any, input: {
  password?: unknown;
  username?: unknown;
  fullName?: unknown;
  profileImage?: unknown;
  provider?: 'email' | 'phone' | 'google' | 'apple' | 'supabase';
  oauthSubject?: unknown;
  appUserId?: unknown;
  phone?: unknown;
  termsVersion?: unknown;
  termsAcceptedAt?: unknown;
}) {
  const currentMetadata = existing?.user_metadata && typeof existing.user_metadata === 'object' ? existing.user_metadata : {};
  const updatePayload: any = {
    user_metadata: {
      ...currentMetadata,
      ...supabaseProfileMetadata({
        appUserId: input.appUserId,
        username: input.username,
        fullName: input.fullName,
        profileImage: input.profileImage,
        phone: input.phone,
        termsVersion: input.termsVersion,
        termsAcceptedAt: input.termsAcceptedAt,
      }),
    },
    app_metadata: mergedSupabaseProviderMetadata(existing, input.provider, input.appUserId, input.oauthSubject),
  };
  if (input.password) updatePayload.password = String(input.password);
  await updateSupabaseAuthUser(c, existing.id, updatePayload);
  const refreshed = await findSupabaseAuthUser(c, { id: existing.id });
  return refreshed || existing;
}

async function createOrFindSupabaseAuthUser(c: any, input: {
  email?: unknown;
  phone?: unknown;
  password?: unknown;
  username?: unknown;
  fullName?: unknown;
  profileImage?: unknown;
  provider?: 'email' | 'phone' | 'google' | 'apple' | 'supabase';
  oauthSubject?: unknown;
  appUserId?: unknown;
  termsVersion?: unknown;
  termsAcceptedAt?: unknown;
}) {
  const subjectMatch = await findSupabaseAuthUserForOAuthSubject(c, input.provider, input.oauthSubject);
  if (subjectMatch?.id) {
    return {
      user: await updateExistingSupabaseAuthUser(c, subjectMatch, input),
      created: false,
    };
  }

  const body = supabaseAuthCreatePayload(input);
  const response = await fetch(`${getSupabaseUrl(c)}/auth/v1/admin/users`, {
    method: 'POST',
    headers: supabaseAdminAuthHeaders(c),
    body: JSON.stringify(body),
  });

  if (response.ok) {
    return { user: supabaseAuthUserFromResponse(await response.json().catch(() => ({}))), created: true };
  }

  const text = await response.text().catch(() => '');
  if ([400, 409, 422].includes(response.status) && /already|registered|exists|duplicate|unique/i.test(text)) {
    const existing = await findSupabaseAuthUser(c, { email: input.email, phone: input.phone });
    if (existing?.id) {
      return {
        user: await updateExistingSupabaseAuthUser(c, existing, input),
        created: false,
      };
    }
  }

  throw new Error(`SUPABASE_AUTH_CREATE_FAILED:${response.status}:${text.slice(0, 200)}`);
}

async function deleteSupabaseAuthUser(c: any, supabaseUserId: unknown) {
  const id = String(supabaseUserId || '').trim();
  if (!id) return;
  const response = await fetch(`${getSupabaseUrl(c)}/auth/v1/admin/users/${encodeURIComponent(id)}`, {
    method: 'DELETE',
    headers: supabaseAdminAuthHeaders(c),
  });
  if (!response.ok && response.status !== 404) {
    const text = await response.text().catch(() => '');
    console.warn(JSON.stringify({ event: 'supabase_auth_cleanup_failed', status: response.status, code: text.slice(0, 120) }));
  }
}

async function linkSupabaseAuthUser(c: any, appUserId: string, supabaseUserId: unknown) {
  const supabaseId = String(supabaseUserId || '').trim();
  if (!appUserId || !supabaseId) return;
  await ensureSupabaseAuthSchema(c.env.DB);
  const owner: any = await c.env.DB.prepare('SELECT id FROM users WHERE supabase_user_id = ? AND id != ? LIMIT 1')
    .bind(supabaseId, appUserId)
    .first();
  if (owner) throw new Error('SUPABASE_AUTH_LINK_CONFLICT');
  await c.env.DB.prepare('UPDATE users SET supabase_user_id = ?, updated_at = datetime(\'now\') WHERE id = ?')
    .bind(supabaseId, appUserId)
    .run();
}

async function syncSupabaseAuthMetadataForUser(c: any, user: any) {
  if (!user?.supabase_user_id) return;
  const existing = await findSupabaseAuthUser(c, { id: user.supabase_user_id }).catch(() => null);
  const currentMetadata = existing?.user_metadata && typeof existing.user_metadata === 'object' ? existing.user_metadata : {};
  await updateSupabaseAuthUser(c, user.supabase_user_id, {
    user_metadata: {
      ...currentMetadata,
      ...supabaseProfileMetadata({
        appUserId: user.id,
        username: publicUsernameFor(user),
        fullName: user.full_name,
        profileImage: user.profile_image,
        language: user.language,
        phone: user.phone,
      }),
    },
  });
}

async function signInSupabasePassword(c: any, email: string, password: string) {
  const response = await fetch(`${getSupabaseUrl(c)}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: supabasePublicAuthHeaders(c),
    body: JSON.stringify({ email, password }),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_PASSWORD_SIGN_IN_FAILED:${response.status}:${text.slice(0, 160)}`);
  }
  const data: any = await response.json().catch(() => ({}));
  if (!data?.access_token) throw new Error('SUPABASE_PASSWORD_SESSION_MISSING');
  return data;
}

async function refreshSupabaseSession(c: any, refreshToken: string) {
  const token = cleanText(refreshToken, 4096);
  if (!token) throw new Error('SUPABASE_REFRESH_TOKEN_REQUIRED');
  const response = await fetch(`${getSupabaseUrl(c)}/auth/v1/token?grant_type=refresh_token`, {
    method: 'POST',
    headers: supabasePublicAuthHeaders(c),
    body: JSON.stringify({ refresh_token: token }),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_REFRESH_FAILED:${response.status}:${text.slice(0, 180)}`);
  }
  const data: any = await response.json().catch(() => ({}));
  if (!data?.access_token) throw new Error('SUPABASE_REFRESH_SESSION_MISSING');
  return data;
}

function passwordResetRedirectTarget(rawValue: unknown): string {
  const fallback = 'https://captro-site.pages.dev/auth/reset-password/';
  const clean = cleanText(rawValue, 2048);
  if (!clean) return fallback;
  try {
    const url = new URL(clean);
    const scheme = String(url.protocol || '').toLowerCase();
    const host = String(url.hostname || '').toLowerCase();
    const path = String(url.pathname || '');
    if (scheme === 'captro:' && host === 'auth' && path === '/reset-password') return clean;
    if (scheme === 'https:' && host === 'captro-site.pages.dev' && (path === '/auth/reset-password' || path === '/auth/reset-password/')) return clean;
    if (scheme === 'https:' && (host === 'captro.app' || host === 'www.captro.app') && path === '/auth/reset-password') {
      const canonical = new URL(fallback);
      canonical.search = url.search;
      canonical.hash = url.hash;
      return canonical.toString();
    }
  } catch {}
  return fallback;
}

async function sendSupabasePasswordRecovery(c: any, email: string, redirectTo: string) {
  const url = new URL(`${getSupabaseUrl(c)}/auth/v1/recover`);
  url.searchParams.set('redirect_to', redirectTo);
  const response = await fetch(url.toString(), {
    method: 'POST',
    headers: supabasePublicAuthHeaders(c),
    body: JSON.stringify({ email }),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_PASSWORD_RECOVERY_FAILED:${response.status}:${text.slice(0, 180)}`);
  }
  return await response.json().catch(() => ({}));
}

async function updateSupabasePassword(c: any, accessToken: string, password: string) {
  const token = cleanText(accessToken, 8192);
  if (!token) throw new Error('SUPABASE_PASSWORD_RESET_TOKEN_REQUIRED');
  const nextPassword = String(password || '');
  if (nextPassword.length < 6) throw new Error('SUPABASE_PASSWORD_RESET_PASSWORD_TOO_SHORT');
  const response = await fetch(`${getSupabaseUrl(c)}/auth/v1/user`, {
    method: 'PUT',
    headers: {
      apikey: getSupabaseAuthClientKey(c),
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ password: nextPassword }),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_PASSWORD_UPDATE_FAILED:${response.status}:${text.slice(0, 180)}`);
  }
  return await response.json().catch(() => ({}));
}

async function oauthFallbackPassword(c: any, provider: 'google' | 'apple', subject: string): Promise<string> {
  const cleanSubject = cleanText(subject, 240);
  if (!cleanSubject) throw new Error('OAUTH_SUBJECT_REQUIRED');
  const secret = String(c.env.OAUTH_FALLBACK_SECRET || '').trim();
  if (!secret) throw new Error('OAUTH_FALLBACK_SECRET_MISSING');
  const digest = await sha256Hex(`${secret}:${provider}:${cleanSubject}:captro_supabase_oauth_v1`);
  return `Captro-${provider}-${digest.slice(0, 48)}!`;
}

async function signInSupabaseVerifiedOAuth(c: any, input: {
  provider: 'google' | 'apple';
  subject: string;
  email?: string;
  fullName?: string;
  profileImage?: string;
  termsVersion?: unknown;
  termsAcceptedAt?: unknown;
}) {
  const subject = cleanText(input.subject, 240);
  if (!subject) throw new Error('OAUTH_SUBJECT_REQUIRED');
  const email = normalizeOptionalEmail(input.email) || internalOAuthEmail(input.provider, subject);
  const fullName = normalizeOptionalName(input.fullName) || safeDisplayNameFromEmail(email) || (input.provider === 'apple' ? 'Apple User' : 'Google User');
  const profileImage = safeMediaReference(input.profileImage || '');
  const password = await oauthFallbackPassword(c, input.provider, subject);

  const authResult = await createOrFindSupabaseAuthUser(c, {
    email,
    password,
    fullName,
    profileImage,
    provider: input.provider,
    oauthSubject: subject,
    termsVersion: input.termsVersion,
    termsAcceptedAt: input.termsAcceptedAt,
  });
  if (!authResult.user?.id) throw new Error('SUPABASE_AUTH_CREATE_EMPTY');

  const sessionEmail = normalizeOptionalEmail(authResult.user.email) || email;
  const supabaseSession = await signInSupabasePassword(c, sessionEmail, password);
  const session = await issueCaptroTokenForSupabaseAccessToken(c, supabaseSession.access_token, {
    email: sessionEmail,
    full_name: fullName,
    profile_image: profileImage,
    auth_provider: input.provider,
    oauth_subject: subject,
  });
  await recordTermsAcceptance(c, session.user, authResult.user.id, termsAcceptanceFromBody(input), `${input.provider}_oauth_verified_bridge`);
  return { supabaseSession, user: session.user };
}

async function issueCaptroTokenForSupabaseAccessToken(c: any, supabaseAccessToken: string, extras: any = {}) {
  const payload = await verifySupabaseAccessToken(c, supabaseAccessToken);
  const user = await findOrCreateSupabaseAppUser(c, payload, extras);
  if (['banned', 'suspended', 'deleted'].includes(String(user.status || 'active'))) {
    await logSecurityEvent(c, 'login_banned_blocked', user.id, { provider: 'supabase' });
    throw new Error('ACCOUNT_DISABLED');
  }
  await upsertAccountIdentity(c, {
    userId: user.id,
    provider: extras.auth_provider || extras.provider || payload.app_metadata?.provider || payload.app_metadata?.providers?.[0] || user.oauth_provider || 'supabase',
    providerUserId: extras.oauth_subject || extras.provider_user_id || user.oauth_subject || payload.sub,
    email: payload.email || user.email,
  });
  runBackgroundTask(c, 'supabase_login_profile_write_through_failed', async () => {
    await syncSupabaseAuthMetadataForUser(c, user);
  });
  return { token: supabaseAccessToken, user };
}

function supabaseAuthSessionResponse(session: any, user: any) {
  const accessToken = String(session?.access_token || session?.token || '').trim();
  const refreshToken = String(session?.refresh_token || '').trim();
  const response: Record<string, unknown> = {
    access_token: accessToken,
    token: accessToken,
    token_type: String(session?.token_type || 'bearer').toLowerCase(),
    user: authUserPayload(user),
  };
  if (refreshToken) response.refresh_token = refreshToken;
  if (Number.isFinite(Number(session?.expires_in))) response.expires_in = Number(session.expires_in);
  if (Number.isFinite(Number(session?.expires_at))) response.expires_at = Number(session.expires_at);
  return response;
}

async function updateSupabaseAuthUser(c: any, supabaseUserId: unknown, payload: { email?: string; password?: string; phone?: string; user_metadata?: Record<string, unknown>; app_metadata?: Record<string, unknown> }) {
  const id = String(supabaseUserId || '').trim();
  const body: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(payload || {})) {
    if (typeof value === 'string' && value.trim().length > 0) body[key] = value.trim();
    else if (value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length > 0) body[key] = value;
  }
  if (!id || Object.keys(body).length === 0) return;

  const response = await fetch(`${getSupabaseUrl(c)}/auth/v1/admin/users/${encodeURIComponent(id)}`, {
    method: 'PUT',
    headers: supabaseAdminAuthHeaders(c),
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

function termsAcceptanceFromBody(body: any): { version: string; acceptedAt: string } | null {
  const version = cleanText(body?.terms_version || body?.termsVersion, 60);
  const acceptedAt = toPgTime(body?.terms_accepted_at || body?.termsAcceptedAt);
  if (!version || !acceptedAt) return null;
  return { version, acceptedAt };
}

function termsAcceptanceMetadata(acceptance: { version: string; acceptedAt: string } | null): Record<string, string> {
  if (!acceptance) return {};
  return {
    captro_terms_version: acceptance.version,
    captro_terms_accepted_at: acceptance.acceptedAt,
    captro_terms_source: 'ios_auth_gate',
  };
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
    email_verified: accountEmailVerified(row),
    phone: normalizeOptionalPhone(row.phone) || null,
    phone_verified: Number(row.phone_verified || 0) === 1,
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
  const primaryCategory = (normalizeDiscoverCategory(row.primary_category || row.category || row.post_type, false) || DEFAULT_DISCOVER_CATEGORY) as DiscoverCategory;
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

function supabasePrimaryPostCreatePayload(input: any) {
  const mediaUrls = sanitizeMediaReferences(input.imageUrls, input.primaryImage);
  const mediaTypes = sanitizeMediaTypes(input.mediaTypes, mediaUrls.length || 1);
  const mediaDimensions = feedMediaDimensions(mediaUrls, mediaTypes, input.mediaDimensions || []);
  const autoCategory = input.autoCategory || {};
  const primaryCategory = (normalizeDiscoverCategory(autoCategory.primary_category || input.postType, false) || DEFAULT_DISCOVER_CATEGORY) as DiscoverCategory;
  const editorOverlays = parseJsonArray(input.editorOverlays);
  const place = {
    id: cleanText(input.placeProviderId, 160),
    provider: cleanText(input.placeProvider || 'apple_mapkit', 40),
    name: cleanText(input.placeName, 180),
    formatted_address: cleanText(input.placeFormattedAddress, 260),
    category: cleanText(input.placeCategory, 80),
    city: cleanText(input.placeCity, 80),
    region: cleanText(input.placeRegion, 80),
    country: cleanText(input.placeCountry, 80),
    lat: input.placeLat ?? null,
    lng: input.placeLng ?? null,
    verified_checkin: !!input.isCheckin,
  };
  const audio = {
    provider: cleanText(input.audioProvider, 40),
    track_id: cleanText(input.audioTrackId, 120),
    title: cleanText(input.audioTitle, 180),
    artist: cleanText(input.audioArtist, 180),
    artwork_url: cleanText(input.audioArtworkUrl, 1200),
    stream_url: cleanText(input.audioStreamUrl, 2200),
    start_time: Number(input.audioStartTime || 0),
    duration: Number(input.audioDuration || 0),
  };
  const discoverCategory = {
    primary_category: primaryCategory,
    confidence: clampFloat(autoCategory.category_confidence, 0, 1, 0),
    source: normalizeCategorySource(autoCategory.category_source),
    status: normalizeCategoryStatus(autoCategory.category_status),
    tags: sanitizeAutoCategoryTags(autoCategory.tags),
    signals: parseJsonObject(autoCategory.signals),
    secondary_categories: sanitizeAutoCategoryTags(autoCategory.secondary_categories),
    category_scores: normalizeCategoryScoresPayload(autoCategory.category_scores),
    detected_objects: sanitizeAutoCategoryTags(autoCategory.detected_objects),
    detected_scene: cleanText(autoCategory.detected_scene, 80),
    place_type: cleanText(autoCategory.place_type || input.placeCategory, 120),
    user_selected_category: normalizeDiscoverCategory(autoCategory.user_selected_category, false),
    caption_keywords: sanitizeAutoCategoryTags(autoCategory.caption_keywords),
  };
  const raw = {
    image: mediaUrls[0] || '',
    images: mediaUrls,
    media_types: mediaTypes,
    media_backup_ids: parseJsonArray(input.backupIds),
    media_asset_ids: parseJsonArray(input.mediaAssetIds),
    display_city: cleanText(input.displayCity, 80),
    display_region: cleanText(input.displayRegion, 80),
    display_country: cleanText(input.displayCountry, 80),
    display_location_label: cleanText(input.displayLocationLabel, 120),
    display_location_source: cleanText(input.displayLocationSource, 40),
    display_location_visibility: cleanText(input.displayLocationVisibility, 40),
    client_request_id: cleanText(input.clientRequestId, 120),
  };
  return {
    id: isUuidText(input.id) || uuid(),
    legacy_post_id: cleanText(input.id, 120),
    user_id: isUuidText(input.authUserId || input.userId),
    app_user_id: cleanText(input.userId, 120) || null,
    title: cleanText(input.postTitle, 180) || null,
    content: cleanMultilineText(input.postContent, 4000),
    visibility: normalizeVisibility(input.visibility),
    status: 'active',
    post_type: cleanText(input.postType || 'general', 80),
    category: primaryCategory,
    location: cleanText(input.location || input.placeName, 180) || null,
    media: mediaUrls.map((url, index) => ({
      url,
      type: mediaTypes[index] || (isVideoMediaUrl(url) ? 'video' : 'image'),
      width: Number(mediaDimensions[index]?.width || mediaDimensions[index]?.feed_width || 0),
      height: Number(mediaDimensions[index]?.height || mediaDimensions[index]?.feed_height || 0),
      ratio: Number(mediaDimensions[index]?.ratio || mediaDimensions[index]?.feed_aspect_ratio || 0),
      feed_width: Number(mediaDimensions[index]?.feed_width || 0),
      feed_height: Number(mediaDimensions[index]?.feed_height || 0),
      feed_aspect_ratio: Number(mediaDimensions[index]?.feed_aspect_ratio || 0),
      display_aspect_ratio: Number(mediaDimensions[index]?.display_aspect_ratio || 0),
      crop_mode: cleanText(mediaDimensions[index]?.crop_mode || 'center_crop', 40),
    })),
    media_dimensions: mediaDimensions,
    editor_data: {
      overlays: editorOverlays,
      filterData: editorOverlays.find((item: any) => item?.type === 'filter') || null,
      textOverlays: editorOverlays.filter((item: any) => item?.type === 'text'),
      moderation: {
        status: 'approved',
        media_ids: parseJsonArray(input.mediaAssetIds),
        checked_at: input.createdAt,
      },
    },
    product_tags: editorOverlays.filter((item: any) => item?.type === 'product'),
    tagged_users: parseJsonArray(input.taggedUsers),
    metadata: {
      source: 'cloudflare_worker_supabase_primary',
      image: mediaUrls[0] || '',
      client_request_id: cleanText(input.clientRequestId, 120),
      media_backup_ids: parseJsonArray(input.backupIds),
      media_asset_ids: parseJsonArray(input.mediaAssetIds),
      discover_category: discoverCategory,
      category_scores: discoverCategory.category_scores,
      secondary_categories: discoverCategory.secondary_categories,
      detected_objects: discoverCategory.detected_objects,
      detected_scene: discoverCategory.detected_scene,
      place_type: discoverCategory.place_type,
      user_selected_category: discoverCategory.user_selected_category,
      caption_keywords: discoverCategory.caption_keywords,
      display_city: raw.display_city,
      display_region: raw.display_region,
      display_country: raw.display_country,
      display_location_label: raw.display_location_label,
      display_location_source: raw.display_location_source,
      display_location_visibility: raw.display_location_visibility,
      moderation_status: 'approved',
      place,
      audio,
      raw,
    },
    likes_count: 0,
    comments_count: 0,
    saves_count: 0,
    legacy_created_at: toPgTime(input.createdAt),
    legacy_updated_at: toPgTime(input.createdAt),
    created_at: toPgTime(input.createdAt),
    updated_at: toPgTime(input.createdAt),
  };
}

async function supabaseExistingPostByClientRequest(c: any, userId: string, clientRequestId: string, authorRow: any): Promise<any | null> {
  const cleanRequestId = cleanText(clientRequestId, 120);
  if (!cleanRequestId) return null;
  const rows = await supabaseAdminQueryRows(c, 'app_posts', {
    select: '*',
    filters: {
      app_user_id: postgrestEqFilter(userId),
      'metadata->>client_request_id': postgrestEqFilter(cleanRequestId),
    },
    order: 'created_at.desc',
    limit: 1,
  }).catch((error: any) => {
    console.warn(JSON.stringify({ event: 'supabase_post_idempotency_lookup_failed', code: getErrorCode(error).slice(0, 180) }));
    return [];
  });
  if (!rows[0]) return null;
  const commentCount = await supabasePostCommentCount(c, cleanText(rows[0].legacy_post_id || rows[0].id, 120)).catch(() => Number(rows[0].comments_count || 0));
  return supabaseAppPostToLegacy(rows[0], authorRow, false, commentCount);
}

async function supabaseIncrementAppUserPostCount(c: any, userId: string) {
  const row = await getSupabaseAppUserRowByAnyId(c, userId);
  if (!row?.id) return;
  const counts = parseJsonObject(row.counts);
  const current = Math.max(0, Number((counts as any).posts_count ?? (counts as any).posts ?? 0));
  await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(cleanText(row.id, 120)) }, {
    counts: {
      ...counts,
      posts_count: current + 1,
      posts: current + 1,
    },
    updated_at: now(),
  });
}

async function writeSupabasePrimaryPostPlace(c: any, input: any) {
  if (!input.placeName && !input.placeFormattedAddress && !input.placeProviderId) return;
  await supabaseAdminUpsert(c, 'app_post_places', [{
    id: uuid(),
    legacy_post_id: cleanText(input.id, 120),
    provider: cleanText(input.placeProvider || 'apple_mapkit', 40) || 'apple_mapkit',
    provider_place_id: cleanText(input.placeProviderId, 160) || null,
    name: cleanText(input.placeName, 180),
    formatted_address: cleanText(input.placeFormattedAddress, 260),
    latitude: input.placeLat ?? null,
    longitude: input.placeLng ?? null,
    category: cleanText(input.placeCategory, 80) || null,
    city: cleanText(input.placeCity, 80) || null,
    region: cleanText(input.placeRegion, 80) || null,
    country: cleanText(input.placeCountry, 80) || null,
    metadata: { source: 'cloudflare_worker_supabase_primary' },
    legacy_created_at: toPgTime(input.createdAt),
    updated_at: toPgTime(input.createdAt),
  }], 'legacy_post_id,provider');
}

async function notifySupabaseFollowersOfNewPost(c: any, input: {
  userId: string;
  postId: string;
  visibility: string;
  authorName: string;
  body: string;
}) {
  if (!(input.visibility === 'public' || input.visibility === 'followers')) return;
  const followers = await supabaseAdminQueryRows(c, 'app_follows', {
    select: 'app_follower_id',
    filters: {
      app_following_id: postgrestEqFilter(input.userId),
      status: postgrestEqFilter('active'),
    },
    order: 'created_at.desc',
    limit: 250,
  }).catch(() => []);
  const ts = now();
  await Promise.allSettled(followers
    .map((row) => cleanText(row?.app_follower_id, 120))
    .filter((id) => id && id !== input.userId)
    .map((followerId) => supabaseAdminUpsertSafe(c, 'app_notifications', [{
      id: `new_post:${input.postId}:${followerId}`,
      user_id: followerId,
      from_user_id: input.userId,
      type: 'new_post',
      title: `${cleanText(input.authorName, 80) || 'Someone you follow'} posted`,
      body: cleanText(input.body, 120) || 'Shared a new post',
      content: cleanText(input.body, 120) || 'Shared a new post',
      reference_id: input.postId,
      data: { post_id: input.postId, from_user_id: input.userId },
      is_read: false,
      legacy_created_at: ts,
      updated_at: ts,
    }], 'id')));
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

async function supabaseAdminInsertRows(c: any, table: string, rows: any[], select = '*'): Promise<any[]> {
  if (!rows.length) return [];
  const url = new URL(`${getSupabaseUrl(c)}/rest/v1/${table}`);
  if (select) url.searchParams.set('select', select);
  const serviceRoleKey = getSupabaseServiceRoleKey(c);
  const response = await fetch(url.toString(), {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify(rows),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`SUPABASE_INSERT_FAILED:${table}:${response.status}:${text.slice(0, 500)}`);
  }
  const data = await response.json().catch(() => []);
  return Array.isArray(data) ? data : [];
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

type CaptroMediaType = 'image' | 'video';
type MediaModerationStatus = 'uploading' | 'pending_moderation' | 'approved' | 'review_required' | 'rejected' | 'failed';
type MalwareStatus = 'clean' | 'malicious' | 'unknown' | 'not_scanned';
type ModerationDecision = 'approved' | 'review_required' | 'rejected';
type MediaOriginStatus =
  | 'not_checked'
  | 'not_applicable'
  | 'missing_credentials'
  | 'verified_original'
  | 'verified_edited'
  | 'ai_generated'
  | 'invalid'
  | 'verifier_unavailable';

type MediaModerationScores = {
  adult_explicit_score: number;
  nudity_score: number;
  sexual_context_score: number;
  sexual_solicitation_score: number;
  minor_safety_risk_score: number;
  violence_score: number;
  gore_score: number;
  weapon_score: number;
  hate_symbol_score: number;
  ai_generated_likelihood: number;
  spam_scam_score: number;
  malware_status: MalwareStatus;
  link_risk_score: number;
  confidence: number;
};

type C2paContentCredentialsSummary = {
  hasContentCredentials: boolean;
  verified: boolean;
  creator: string;
  createdAt: string | null;
  aiUsed: boolean;
  editHistorySummary: string;
  mediaOriginStatus: MediaOriginStatus;
  metadata: Record<string, unknown>;
};

const MEDIA_MODERATION_STATUS_VALUES = new Set<MediaModerationStatus>([
  'uploading',
  'pending_moderation',
  'approved',
  'review_required',
  'rejected',
  'failed',
]);

function normalizeMediaModerationStatus(value: unknown): MediaModerationStatus {
  const status = cleanText(value, 40) as MediaModerationStatus;
  return MEDIA_MODERATION_STATUS_VALUES.has(status) ? status : 'pending_moderation';
}

function normalizeMediaAssetType(value: unknown): CaptroMediaType | '' {
  const mediaType = cleanText(value, 40).toLowerCase();
  return mediaType === 'image' || mediaType === 'video' ? mediaType : '';
}

function mediaModerationMaxBytes(env: Env, mediaType: CaptroMediaType): number {
  const raw = Number(mediaType === 'video' ? env.MEDIA_MAX_VIDEO_BYTES : env.MEDIA_MAX_IMAGE_BYTES);
  if (Number.isFinite(raw) && raw > 0) return Math.min(raw, mediaType === 'video' ? 500_000_000 : 50_000_000);
  return mediaType === 'video' ? 250_000_000 : 25_000_000;
}

function isUnsafeUploadExtension(filename: unknown): boolean {
  const ext = fileExtension(filename);
  return ['exe', 'dll', 'bat', 'cmd', 'com', 'scr', 'ps1', 'sh', 'js', 'jar', 'zip', 'rar', '7z', 'tar', 'gz', 'svg', 'html', 'php'].includes(ext);
}

function validatePrePublishUploadInput(env: Env, body: any): { ok: true; mediaType: CaptroMediaType; mimeType: string; filename: string; fileSize: number } | { ok: false; detail: string; code: string; status: number } {
  const mediaType = normalizeMediaAssetType(body.media_type || body.mediaType || body.type);
  if (!mediaType) return { ok: false, detail: 'Upload must be an image or video.', code: 'invalid_media_type', status: 400 };

  const filename = cleanText(body.filename || body.file_name || (mediaType === 'video' ? 'captro-video.mp4' : 'captro-image.jpg'), 180);
  if (isUnsafeUploadExtension(filename)) return { ok: false, detail: 'This file type cannot be uploaded.', code: 'unsafe_extension', status: 400 };

  const mimeType = normalizedContentType(body.mime_type || body.mimeType || body.content_type || body.contentType);
  const allowedTypes = mediaType === 'video' ? ALLOWED_VIDEO_TYPES : ALLOWED_IMAGE_TYPES;
  const allowedExtensions = mediaType === 'video' ? ALLOWED_VIDEO_EXTENSIONS : ALLOWED_IMAGE_EXTENSIONS;
  if (!mimeType || !allowedTypes.has(mimeType) || !extensionAllowed(filename, allowedExtensions)) {
    return {
      ok: false,
      detail: mediaType === 'video' ? 'Unsupported video type. Use MP4, MOV, or WebM.' : 'Unsupported image type. Use JPG, PNG, WebP, HEIC, or HEIF.',
      code: 'unsupported_media_type',
      status: 400,
    };
  }

  const fileSize = Math.max(0, Math.round(Number(body.file_size || body.fileSize || body.size || 0)));
  const maxBytes = mediaModerationMaxBytes(env, mediaType);
  if (fileSize > maxBytes) {
    return { ok: false, detail: 'This upload is too large.', code: 'file_too_large', status: 413 };
  }

  return { ok: true, mediaType, mimeType, filename, fileSize };
}

function defaultModerationScores(overrides: Partial<MediaModerationScores> = {}): MediaModerationScores {
  return {
    adult_explicit_score: 0,
    nudity_score: 0,
    sexual_context_score: 0,
    sexual_solicitation_score: 0,
    minor_safety_risk_score: 0,
    violence_score: 0,
    gore_score: 0,
    weapon_score: 0,
    hate_symbol_score: 0,
    ai_generated_likelihood: 0,
    spam_scam_score: 0,
    malware_status: 'unknown',
    link_risk_score: 0,
    confidence: 0.7,
    ...overrides,
  };
}

function normalizeMediaOriginStatus(value: unknown): MediaOriginStatus {
  const status = cleanText(value, 60).toLowerCase();
  const allowed = new Set<MediaOriginStatus>([
    'not_checked',
    'not_applicable',
    'missing_credentials',
    'verified_original',
    'verified_edited',
    'ai_generated',
    'invalid',
    'verifier_unavailable',
  ]);
  return allowed.has(status as MediaOriginStatus) ? status as MediaOriginStatus : 'not_checked';
}

function defaultC2paSummary(mediaOriginStatus: MediaOriginStatus): C2paContentCredentialsSummary {
  return {
    hasContentCredentials: false,
    verified: false,
    creator: '',
    createdAt: null,
    aiUsed: false,
    editHistorySummary: '',
    mediaOriginStatus,
    metadata: {},
  };
}

function sanitizeC2paSummary(raw: any): C2paContentCredentialsSummary {
  const metadata = parseJsonObject(raw?.metadata || raw?.summary || raw);
  const aiUsed = raw?.ai_used === true
    || raw?.aiUsed === true
    || raw?.generated_by_ai === true
    || raw?.synthetic_media === true
    || /(^|[_ -])(ai|synthetic|generated)([_ -]|$)/i.test(String(raw?.media_origin_status || raw?.origin_status || ''));
  const verified = raw?.verified === true || raw?.c2pa_verified === true;
  const hasContentCredentials = raw?.has_content_credentials === true
    || raw?.hasContentCredentials === true
    || raw?.manifest_present === true
    || verified;
  const createdAt = cleanText(raw?.created_at || raw?.createdAt || raw?.claim_created_at || '', 80);
  const mediaOriginStatus = aiUsed
    ? 'ai_generated'
    : normalizeMediaOriginStatus(raw?.media_origin_status || raw?.origin_status || (verified ? 'verified_original' : hasContentCredentials ? 'invalid' : 'missing_credentials'));
  return {
    hasContentCredentials,
    verified,
    creator: cleanText(raw?.creator || raw?.c2pa_creator || raw?.claim_generator || '', 180),
    createdAt: createdAt && !Number.isNaN(Date.parse(createdAt)) ? new Date(createdAt).toISOString() : null,
    aiUsed,
    editHistorySummary: cleanMultilineText(raw?.edit_history_summary || raw?.editHistorySummary || raw?.history || '', 500),
    mediaOriginStatus,
    metadata: scrubLogMetadata({
      claim_generator: cleanText(raw?.claim_generator || raw?.claimGenerator || '', 160),
      ingredients_count: Math.max(0, Math.min(200, Number(raw?.ingredients_count || raw?.ingredientsCount || 0))),
      assertions: Array.isArray(raw?.assertions) ? raw.assertions.slice(0, 20).map((item: any) => cleanText(item, 120)) : [],
      raw_status: cleanText(raw?.status || raw?.verification_status || '', 80),
      ...metadata,
    }),
  };
}

async function fetchCloudflareImageBlobForVerification(env: Env, imageId: string): Promise<Blob | null> {
  const accountId = cloudflareAccountId(env);
  const token = cloudflareImagesToken(env);
  if (!accountId || !token || !imageId) return null;
  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/images/v1/${encodeURIComponent(imageId)}/blob`, {
    headers: { Authorization: `Bearer ${token}`, accept: 'image/*' },
  });
  if (!response.ok) return null;
  const contentLength = Number(response.headers.get('content-length') || 0);
  if (contentLength > 16_000_000) return null;
  const buffer = await response.arrayBuffer();
  if (!buffer.byteLength || buffer.byteLength > 16_000_000) return null;
  const type = response.headers.get('content-type') || 'application/octet-stream';
  return new Blob([buffer], { type });
}

async function inspectC2paContentCredentials(env: Env, asset: any): Promise<C2paContentCredentialsSummary> {
  if (normalizeMediaAssetType(asset?.media_type) !== 'image') return defaultC2paSummary('not_applicable');
  if (cleanText(asset?.storage_provider, 40) !== 'images') return defaultC2paSummary('not_applicable');
  const verifierUrl = cleanText(env.C2PA_VERIFIER_URL || '', 500);
  if (!verifierUrl || !/^https:\/\//i.test(verifierUrl)) return defaultC2paSummary('not_checked');
  try {
    const imageId = cleanText(asset?.storage_key, 220);
    const blob = await fetchCloudflareImageBlobForVerification(env, imageId);
    if (!blob) return defaultC2paSummary('verifier_unavailable');
    const formData = new FormData();
    formData.append('file', blob, `${imageId || 'captro-image'}.jpg`);
    formData.append('media_id', cleanText(asset?.id, 160));
    formData.append('storage_provider', 'cloudflare_images');
    const response = await fetch(verifierUrl, {
      method: 'POST',
      headers: {
        ...(env.C2PA_VERIFIER_TOKEN ? { Authorization: `Bearer ${env.C2PA_VERIFIER_TOKEN}` } : {}),
      },
      body: formData,
    });
    if (!response.ok) return defaultC2paSummary(response.status === 404 ? 'missing_credentials' : 'verifier_unavailable');
    const raw = await response.json().catch(() => ({}));
    return sanitizeC2paSummary(raw);
  } catch {
    return defaultC2paSummary('verifier_unavailable');
  }
}

function moderationDelay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function maxModerationScores(scores: MediaModerationScores[]): MediaModerationScores {
  return scores.reduce((acc, score) => ({
    adult_explicit_score: Math.max(acc.adult_explicit_score, score.adult_explicit_score),
    nudity_score: Math.max(acc.nudity_score, score.nudity_score),
    sexual_context_score: Math.max(acc.sexual_context_score, score.sexual_context_score),
    sexual_solicitation_score: Math.max(acc.sexual_solicitation_score, score.sexual_solicitation_score),
    minor_safety_risk_score: Math.max(acc.minor_safety_risk_score, score.minor_safety_risk_score),
    violence_score: Math.max(acc.violence_score, score.violence_score),
    gore_score: Math.max(acc.gore_score, score.gore_score),
    weapon_score: Math.max(acc.weapon_score, score.weapon_score),
    hate_symbol_score: Math.max(acc.hate_symbol_score, score.hate_symbol_score),
    ai_generated_likelihood: Math.max(acc.ai_generated_likelihood, score.ai_generated_likelihood),
    spam_scam_score: Math.max(acc.spam_scam_score, score.spam_scam_score),
    malware_status: score.malware_status === 'malicious' || acc.malware_status === 'malicious'
      ? 'malicious'
      : score.malware_status === 'clean' || acc.malware_status === 'clean'
        ? 'clean'
        : acc.malware_status,
    link_risk_score: Math.max(acc.link_risk_score, score.link_risk_score),
    confidence: Math.max(acc.confidence, score.confidence),
  }), defaultModerationScores({ confidence: 0 }));
}

function decideMediaModeration(scores: MediaModerationScores, mediaType: CaptroMediaType, aiGeneratedMediaPolicy = ''): { decision: ModerationDecision; reasons: string[]; rejectionCode: string; userMessage: string } {
  const reasons: string[] = [];
  const aiPolicy = cleanText(aiGeneratedMediaPolicy, 60).toLowerCase();
  const aiDisallowed = aiPolicy === 'disallow';
  const aiReviewEnabled = aiDisallowed || aiPolicy === 'review';
  if (scores.malware_status === 'malicious') reasons.push('malware_detected');
  if (scores.adult_explicit_score >= 0.85) reasons.push('explicit_sexual_content');
  if (scores.sexual_solicitation_score >= 0.90) reasons.push('sexual_solicitation');
  if (scores.minor_safety_risk_score >= 0.20) reasons.push('minor_safety_risk');
  if (scores.gore_score >= 0.90) reasons.push('graphic_gore');
  if (scores.hate_symbol_score >= 0.85) reasons.push('hate_symbol');
  if (scores.spam_scam_score >= 0.90 || scores.link_risk_score >= 0.90) reasons.push('spam_or_scam');
  if (aiDisallowed && scores.ai_generated_likelihood >= 0.92) reasons.push('ai_generated_media');

  if (reasons.length) {
    return {
      decision: 'rejected',
      reasons,
      rejectionCode: reasons[0],
      userMessage: "This upload can't be posted because it may break Captro's safety rules.",
    };
  }

  const strongestSafetySignal = Math.max(
    scores.adult_explicit_score,
    scores.nudity_score,
    scores.sexual_context_score,
    scores.sexual_solicitation_score,
    scores.minor_safety_risk_score,
    scores.violence_score,
    scores.gore_score,
    scores.weapon_score,
    scores.hate_symbol_score,
    scores.spam_scam_score,
    scores.link_risk_score,
  );

  if (scores.nudity_score >= 0.70
    || scores.sexual_context_score >= 0.70
    || scores.sexual_solicitation_score >= 0.60
    || scores.violence_score >= 0.80
    || scores.weapon_score >= 0.80
    || (aiReviewEnabled && scores.ai_generated_likelihood >= 0.85)
    || (scores.confidence < 0.45 && strongestSafetySignal >= 0.35)) {
    if (scores.nudity_score >= 0.70) reasons.push('nudity_review');
    if (scores.sexual_context_score >= 0.70) reasons.push('sexual_context_review');
    if (scores.sexual_solicitation_score >= 0.60) reasons.push('sexual_solicitation_review');
    if (scores.violence_score >= 0.80) reasons.push('violence_review');
    if (scores.weapon_score >= 0.80) reasons.push('weapon_review');
    if (aiReviewEnabled && scores.ai_generated_likelihood >= 0.85) reasons.push('ai_generated_review');
    if (scores.confidence < 0.45 && strongestSafetySignal >= 0.35) reasons.push('low_confidence_with_risk');
    return {
      decision: 'review_required',
      reasons,
      rejectionCode: '',
      userMessage: 'This upload needs a quick safety review before it can be posted.',
    };
  }

  return { decision: 'approved', reasons: [], rejectionCode: '', userMessage: '' };
}

function parseModerationJson(value: any): any {
  if (!value) return {};
  if (typeof value === 'object') return value;
  const text = String(value || '').trim();
  const fenced = /```(?:json)?\s*([\s\S]*?)```/i.exec(text)?.[1] || text;
  const start = fenced.indexOf('{');
  const end = fenced.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try { return JSON.parse(fenced.slice(start, end + 1)); } catch {}
  }
  try { return JSON.parse(fenced); } catch {}
  return {};
}

function textSafetyHeuristics(text: string): MediaModerationScores {
  const lower = text.toLowerCase();
  const unsafeLinks = /(bit\.ly|tinyurl|t\.me\/|telegram\.me|free\s+money|cashapp|crypto|airdrop|wallet\s+connect|login\s+here|verify\s+account)/i.test(text);
  const explicit = /(onlyfans|nude|sex|escort|hookup|send nudes|xxx)/i.test(text);
  const hate = /(swastika|kkk|nazi)/i.test(text);
  const violence = /(kill|shoot|stab|blood|gore)/i.test(text);
  return defaultModerationScores({
    adult_explicit_score: explicit ? 0.55 : 0,
    sexual_solicitation_score: explicit ? 0.75 : 0,
    hate_symbol_score: hate ? 0.75 : 0,
    violence_score: violence ? 0.55 : 0,
    spam_scam_score: unsafeLinks ? 0.82 : 0,
    link_risk_score: /https?:\/\//i.test(text) ? (unsafeLinks ? 0.85 : 0.25) : 0,
    confidence: lower ? 0.78 : 0.72,
    malware_status: 'not_scanned',
  });
}

function sanitizeModerationScores(raw: any, fallback: MediaModerationScores): MediaModerationScores {
  return defaultModerationScores({
    adult_explicit_score: clampFloat(raw.adult_explicit_score ?? raw.explicit_sexual_content ?? raw.sexual_explicit_score, 0, 1, fallback.adult_explicit_score),
    nudity_score: clampFloat(raw.nudity_score ?? raw.nudity, 0, 1, fallback.nudity_score),
    sexual_context_score: clampFloat(raw.sexual_context_score ?? raw.sexual_context, 0, 1, fallback.sexual_context_score),
    sexual_solicitation_score: clampFloat(raw.sexual_solicitation_score ?? raw.solicitation_score, 0, 1, fallback.sexual_solicitation_score),
    minor_safety_risk_score: clampFloat(raw.minor_safety_risk_score ?? raw.minor_risk, 0, 1, fallback.minor_safety_risk_score),
    violence_score: clampFloat(raw.violence_score ?? raw.violence, 0, 1, fallback.violence_score),
    gore_score: clampFloat(raw.gore_score ?? raw.gore, 0, 1, fallback.gore_score),
    weapon_score: clampFloat(raw.weapon_score ?? raw.weapons, 0, 1, fallback.weapon_score),
    hate_symbol_score: clampFloat(raw.hate_symbol_score ?? raw.hate_symbols, 0, 1, fallback.hate_symbol_score),
    ai_generated_likelihood: clampFloat(raw.ai_generated_likelihood ?? raw.ai_likelihood, 0, 1, fallback.ai_generated_likelihood),
    spam_scam_score: clampFloat(raw.spam_scam_score ?? raw.scam_score, 0, 1, fallback.spam_scam_score),
    malware_status: ['clean', 'malicious', 'unknown', 'not_scanned'].includes(cleanText(raw.malware_status, 30)) ? cleanText(raw.malware_status, 30) as MalwareStatus : fallback.malware_status,
    link_risk_score: clampFloat(raw.link_risk_score ?? raw.unsafe_link_score, 0, 1, fallback.link_risk_score),
    confidence: clampFloat(raw.confidence ?? raw.model_confidence, 0, 1, fallback.confidence),
  });
}

function mediaAssetPublicUrl(env: Env, asset: any): string {
  const provider = cleanText(asset?.storage_provider, 40);
  const key = cleanText(asset?.storage_key, 220);
  if (!key) return '';
  if (provider === 'images') return cloudflareImageDeliveryUrl(env, key, env.CLOUDFLARE_IMAGES_FEED_VARIANT || 'public');
  if (provider === 'stream') return `https://videodelivery.net/${key}/manifest/video.m3u8`;
  return safeMediaReference(asset?.public_url) || safeMediaReference(asset?.private_url);
}

function mediaAssetPreviewUrl(env: Env, asset: any): string {
  const provider = cleanText(asset?.storage_provider, 40);
  const key = cleanText(asset?.storage_key, 220);
  if (!key) return '';
  if (provider === 'images') return cloudflareImageDeliveryUrl(env, key, env.CLOUDFLARE_IMAGES_THUMBNAIL_VARIANT || 'public');
  if (provider === 'stream') return streamThumbnailUrl(`cfstream:${key}`);
  return safeMediaReference(asset?.public_url) || safeMediaReference(asset?.private_url);
}

function moderationSampleUrls(env: Env, asset: any): string[] {
  if (asset.media_type === 'video' && cleanText(asset.storage_provider, 40) === 'stream') {
    const key = cleanText(asset.storage_key, 220);
    return [0, 25, 50, 75, 95].map((pct) => `https://videodelivery.net/${key}/thumbnails/thumbnail.jpg?time=${pct}p&height=720`);
  }
  if (asset.media_type === 'image' && cleanText(asset.storage_provider, 40) === 'images') {
    const key = cleanText(asset.storage_key, 220);
    return key ? [`cfimage-api:${key}`] : [];
  }
  return [mediaAssetPreviewUrl(env, asset)].filter(Boolean);
}

async function runWorkersAiImageModeration(env: Env, imageUrl: string, caption: string): Promise<{ scores: MediaModerationScores; raw: any; modelName: string }> {
  const fallback = textSafetyHeuristics(caption);
  if (!env.AI || !imageUrl || (!/^https:\/\//i.test(imageUrl) && !imageUrl.startsWith('cfimage-api:'))) {
    return { scores: defaultModerationScores({ ...fallback, confidence: Math.min(fallback.confidence, 0.6) }), raw: { ai_available: !!env.AI, image_available: !!imageUrl }, modelName: 'heuristic_no_image' };
  }
  const modelName = cleanText(env.AI_IMAGE_MODERATION_MODEL || '@cf/meta/llama-3.2-11b-vision-instruct', 160);
  try {
    const imageId = imageUrl.startsWith('cfimage-api:') ? cleanText(imageUrl.replace('cfimage-api:', ''), 220) : '';
    let response: Response | null = null;
    for (let attempt = 0; attempt < 4; attempt += 1) {
      response = imageId
        ? await fetch(`https://api.cloudflare.com/client/v4/accounts/${cloudflareAccountId(env)}/images/v1/${imageId}/blob`, {
          headers: { Authorization: `Bearer ${cloudflareImagesToken(env)}`, accept: 'image/*' },
        })
        : await fetch(imageUrl, { headers: { accept: 'image/*' } });
      if (response.ok) break;
      if (![404, 409, 425, 429, 500, 502, 503, 504].includes(response.status) || attempt === 3) break;
      await moderationDelay(350 * (attempt + 1));
    }
    if (!response?.ok) throw new Error(`IMAGE_SAMPLE_FETCH_FAILED:${response?.status || 0}`);
    const imageBytes = await response.arrayBuffer();
    if (!imageBytes.byteLength || imageBytes.byteLength > 4_000_000) throw new Error('IMAGE_SAMPLE_TOO_LARGE');
    const prompt = `You are Captro's pre-publish media safety classifier. Return strict JSON only with numbers 0..1 for adult_explicit_score, nudity_score, sexual_context_score, sexual_solicitation_score, minor_safety_risk_score, violence_score, gore_score, weapon_score, hate_symbol_score, ai_generated_likelihood, spam_scam_score, link_risk_score, confidence, malware_status as "not_scanned", and reasons as an array. Check nudity, explicit sexual content, sexual solicitation, sexualized minors, violence/gore, weapons, hate symbols, scams/spam, unsafe links in caption, and AI-generated likelihood. Caption: ${caption || '(none)'}`;
    const result = await env.AI.run(modelName, {
      messages: [{ role: 'user', content: prompt }],
      image: Array.from(new Uint8Array(imageBytes)),
    });
    const raw = parseModerationJson(result?.response || result?.result || result?.text || result);
    return { scores: sanitizeModerationScores(raw, fallback), raw: raw || result || {}, modelName };
  } catch (error: any) {
    return {
      scores: defaultModerationScores({ ...fallback, confidence: Math.min(fallback.confidence, 0.55) }),
      raw: { error: getErrorCode(error).slice(0, 180), fallback: true },
      modelName,
    };
  }
}

async function scanMalwareInterface(env: Env, asset: any): Promise<MalwareStatus> {
  const scannerUrl = cleanText(env.MALWARE_SCANNER_URL, 400);
  if (!scannerUrl || !/^https:\/\//i.test(scannerUrl)) return 'unknown';
  try {
    const response = await fetch(scannerUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(env.MALWARE_SCANNER_TOKEN ? { Authorization: `Bearer ${env.MALWARE_SCANNER_TOKEN}` } : {}),
      },
      body: JSON.stringify({
        media_id: asset.id,
        provider: asset.storage_provider,
        storage_key: asset.storage_key,
        mime_type: asset.mime_type,
        file_size: asset.file_size,
        sha256_hash: asset.sha256_hash,
      }),
    });
    if (!response.ok) return 'unknown';
    const data: any = await response.json().catch(() => ({}));
    return data.status === 'malicious' ? 'malicious' : data.status === 'clean' ? 'clean' : 'unknown';
  } catch {
    return 'unknown';
  }
}

async function insertModerationEvent(db: D1Database, mediaId: string, eventType: string, input: { actorUserId?: string; actorRole?: string; decision?: string; reason?: string; note?: string; beforeState?: any; afterState?: any; requestId?: string } = {}) {
  await db.prepare(
    `INSERT INTO moderation_events
     (id, media_id, actor_user_id, actor_role, event_type, decision, reason, note, before_state, after_state, request_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    uuid(),
    mediaId,
    publicId(input.actorUserId || '', 120),
    cleanText(input.actorRole || '', 40),
    cleanText(eventType, 80),
    cleanText(input.decision || '', 40),
    cleanText(input.reason || '', 180),
    cleanMultilineText(input.note || '', 1000),
    safeJsonState(input.beforeState),
    safeJsonState(input.afterState),
    cleanText(input.requestId || '', 120),
    now(),
  ).run();
}

function supabaseCtxFromEnv(env: Env): any {
  return { env };
}

function supabasePrimaryConfiguredForEnv(env: Env): boolean {
  return supabasePrimaryRequestedForEnv(env)
    && !!String(env.SUPABASE_URL || '').trim()
    && !!String(env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
}

function supabaseMediaAssetToLegacy(row: any): any {
  return {
    ...row,
    post_id: row?.post_id || row?.legacy_post_id || null,
    created_at: row?.created_at || row?.legacy_created_at || '',
    updated_at: row?.updated_at || '',
  };
}

async function supabaseReadMediaAsset(c: any, mediaId: string, userId = ''): Promise<any | null> {
  const filters: Record<string, string> = { id: postgrestEqFilter(mediaId) };
  if (userId) filters.user_id = postgrestEqFilter(userId);
  const rows = await supabaseAdminQueryRows(c, 'app_media_assets', {
    select: '*',
    filters,
    limit: 1,
  });
  return rows[0] ? supabaseMediaAssetToLegacy(rows[0]) : null;
}

async function supabaseInsertMediaAsset(c: any, input: {
  id: string;
  userId: string;
  mediaType: CaptroMediaType;
  storageProvider: 'images' | 'stream';
  storageKey: string;
  privateUrl: string;
  mimeType: string;
  fileSize?: number;
  sha256Hash?: string;
  width?: number | null;
  height?: number | null;
  durationSeconds?: number | null;
  metadata?: Record<string, unknown>;
}) {
  const ts = now();
  await supabaseAdminUpsert(c, 'app_media_assets', [{
    id: input.id,
    user_id: input.userId,
    legacy_post_id: null,
    media_type: input.mediaType,
    storage_provider: input.storageProvider,
    storage_key: input.storageKey,
    public_url: null,
    private_url: input.privateUrl,
    mime_type: input.mimeType,
    file_size: Math.max(0, Math.round(Number(input.fileSize || 0))),
    sha256_hash: cleanText(input.sha256Hash || '', 80).toLowerCase(),
    width: input.width ?? null,
    height: input.height ?? null,
    duration_seconds: input.durationSeconds ?? null,
    upload_status: 'uploading',
    moderation_status: 'uploading',
    rejection_code: null,
    rejection_message: null,
    has_content_credentials: false,
    c2pa_verified: false,
    c2pa_creator: null,
    c2pa_created_at: null,
    c2pa_ai_used: false,
    c2pa_edit_history_summary: null,
    media_origin_status: input.mediaType === 'image' && input.storageProvider === 'images' ? 'not_checked' : 'not_applicable',
    c2pa_metadata: {},
    metadata: input.metadata || {},
    created_at: ts,
    updated_at: ts,
  }], 'id');
}

async function supabaseInsertModerationEvent(cOrEnv: any, mediaId: string, eventType: string, input: { actorUserId?: string; actorRole?: string; decision?: string; reason?: string; note?: string; beforeState?: any; afterState?: any; requestId?: string } = {}) {
  const c = cOrEnv?.env ? cOrEnv : supabaseCtxFromEnv(cOrEnv as Env);
  await supabaseAdminUpsert(c, 'app_moderation_events', [{
    id: uuid(),
    media_id: mediaId,
    actor_user_id: publicId(input.actorUserId || '', 120) || null,
    actor_role: cleanText(input.actorRole || '', 40) || null,
    event_type: cleanText(eventType, 80),
    decision: cleanText(input.decision || '', 40) || null,
    reason: cleanText(input.reason || '', 180) || null,
    note: cleanMultilineText(input.note || '', 1000) || null,
    before_state: parseJsonObject(safeJsonState(input.beforeState)),
    after_state: parseJsonObject(safeJsonState(input.afterState)),
    request_id: cleanText(input.requestId || '', 120) || null,
    created_at: now(),
  }], 'id');
}

async function processSupabaseMediaModerationJob(env: Env, message: MediaModerationJobMessage, requestId = '') {
  const c = supabaseCtxFromEnv(env);
  const mediaId = publicId(message.mediaId, 160);
  const jobId = publicId(message.jobId, 160);
  const startedAt = now();
  const jobRows = await supabaseAdminQueryRows(c, 'app_moderation_jobs', {
    select: 'id,attempts',
    filters: { id: postgrestEqFilter(jobId) },
    limit: 1,
  });
  await supabaseAdminPatchRows(c, 'app_moderation_jobs', { id: postgrestEqFilter(jobId) }, {
    status: 'running',
    attempts: Math.max(0, Number(jobRows[0]?.attempts || 0)) + 1,
    started_at: startedAt,
    updated_at: startedAt,
  });

  const asset = await supabaseReadMediaAsset(c, mediaId);
  if (!asset) throw new Error('MEDIA_ASSET_NOT_FOUND');
  const existingStatus = normalizeMediaModerationStatus(asset.moderation_status);
  if (['approved', 'review_required', 'rejected'].includes(existingStatus) && cleanText(asset.upload_status, 40) === 'uploaded') {
    const ts = now();
    await supabaseAdminPatchRows(c, 'app_moderation_jobs', { id: postgrestEqFilter(jobId) }, {
      status: 'completed',
      completed_at: ts,
      updated_at: ts,
    });
    return;
  }

  try {
    const c2paSummary = await inspectC2paContentCredentials(env, asset);
    const malwareStatus = await scanMalwareInterface(env, asset);
    const caption = cleanMultilineText(message.caption || '', 1000);
    const sampleScores: MediaModerationScores[] = [];
    const rawSamples: any[] = [];
    let modelName = 'heuristic';
    for (const sampleUrl of moderationSampleUrls(env, asset)) {
      const result = await runWorkersAiImageModeration(env, sampleUrl, caption);
      modelName = result.modelName;
      sampleScores.push(result.scores);
      rawSamples.push({ sample_url: sampleUrl.replace(/\?.*/, ''), result: scrubLogMetadata(result.raw) });
    }
    if (!sampleScores.length) {
      sampleScores.push(defaultModerationScores({ ...textSafetyHeuristics(caption), confidence: 0.55 }));
      rawSamples.push({ fallback: 'no_sample_available' });
    }
    const scores = maxModerationScores(sampleScores);
    scores.malware_status = malwareStatus === 'clean' || malwareStatus === 'malicious' ? malwareStatus : scores.malware_status;
    if (c2paSummary.aiUsed) {
      scores.ai_generated_likelihood = Math.max(scores.ai_generated_likelihood, 0.9);
      scores.confidence = Math.max(scores.confidence, 0.82);
    }
    const decision = decideMediaModeration(scores, normalizeMediaAssetType(asset.media_type) || 'image', env.AI_GENERATED_MEDIA_POLICY || '');
    const publicUrl = decision.decision === 'approved' ? mediaAssetPublicUrl(env, asset) : '';
    const ts = now();
    await supabaseAdminUpsert(c, 'app_moderation_results', [{
      id: uuid(),
      media_id: mediaId,
      model_name: modelName,
      adult_explicit_score: scores.adult_explicit_score,
      nudity_score: scores.nudity_score,
      sexual_context_score: scores.sexual_context_score,
      sexual_solicitation_score: scores.sexual_solicitation_score,
      minor_safety_risk_score: scores.minor_safety_risk_score,
      violence_score: scores.violence_score,
      gore_score: scores.gore_score,
      weapon_score: scores.weapon_score,
      hate_symbol_score: scores.hate_symbol_score,
      ai_generated_likelihood: scores.ai_generated_likelihood,
      spam_scam_score: scores.spam_scam_score,
      malware_status: scores.malware_status,
      link_risk_score: scores.link_risk_score,
      confidence: scores.confidence,
      decision: decision.decision,
      reasons: decision.reasons,
      raw_result: { samples: rawSamples, content_credentials: c2paSummary },
      created_at: ts,
    }], 'id');
    await supabaseAdminPatchRows(c, 'app_media_assets', { id: postgrestEqFilter(mediaId) }, {
      moderation_status: decision.decision,
      ...(publicUrl ? { public_url: publicUrl } : {}),
      rejection_code: decision.rejectionCode || null,
      rejection_message: decision.userMessage || null,
      has_content_credentials: c2paSummary.hasContentCredentials,
      c2pa_verified: c2paSummary.verified,
      c2pa_creator: c2paSummary.creator || null,
      c2pa_created_at: c2paSummary.createdAt,
      c2pa_ai_used: c2paSummary.aiUsed,
      c2pa_edit_history_summary: c2paSummary.editHistorySummary || null,
      media_origin_status: c2paSummary.mediaOriginStatus,
      c2pa_metadata: c2paSummary.metadata,
      updated_at: ts,
    });
    await supabaseAdminPatchRows(c, 'app_moderation_jobs', { id: postgrestEqFilter(jobId) }, {
      status: 'completed',
      completed_at: ts,
      updated_at: ts,
    });
    await supabaseInsertModerationEvent(c, mediaId, `moderation_${decision.decision}`, {
      decision: decision.decision,
      reason: decision.reasons.join(','),
      afterState: { moderation_status: decision.decision, scores },
      requestId,
    });
  } catch (error: any) {
    const ts = now();
    const code = getErrorCode(error).slice(0, 180);
    await Promise.allSettled([
      supabaseAdminPatchRows(c, 'app_moderation_jobs', { id: postgrestEqFilter(jobId) }, {
        status: 'failed',
        last_error: code,
        completed_at: ts,
        updated_at: ts,
      }),
      supabaseAdminPatchRows(c, 'app_media_assets', { id: postgrestEqFilter(mediaId) }, {
        moderation_status: 'failed',
        rejection_code: 'moderation_failed',
        rejection_message: 'This upload could not be checked. Please try again.',
        updated_at: ts,
      }),
    ]);
    await supabaseInsertModerationEvent(c, mediaId, 'moderation_failed', { reason: code, requestId });
    throw error;
  }
}

async function processMediaModerationJob(env: Env, message: MediaModerationJobMessage, requestId = '') {
  if (supabasePrimaryConfiguredForEnv(env)) {
    await processSupabaseMediaModerationJob(env, message, requestId);
    return;
  }
  throw new Error('SUPABASE_PRIMARY_REQUIRED:media_moderation');
}

async function createMediaModerationJob(c: any, mediaId: string, userId: string, caption = '', options: { enqueue?: boolean } = {}): Promise<string> {
  if (supabasePrimaryConfigured(c)) {
    const jobId = uuid();
    const ts = now();
    await supabaseAdminUpsert(c, 'app_moderation_jobs', [{
      id: jobId,
      media_id: mediaId,
      user_id: userId,
      job_type: 'media_pre_publish',
      status: 'pending',
      attempts: 0,
      queued_at: ts,
      created_at: ts,
      updated_at: ts,
      metadata: { reason: 'upload_complete' },
    }], 'id');
    const body: MediaModerationJobMessage = { jobId, mediaId, userId, reason: 'upload_complete', caption: cleanMultilineText(caption, 1000) };
    const shouldEnqueue = options.enqueue !== false;
    if (shouldEnqueue && c.env.MEDIA_MODERATION_QUEUE) {
      await c.env.MEDIA_MODERATION_QUEUE.send(body);
    } else if (shouldEnqueue) {
      runBackgroundTask(c, 'supabase_media_moderation_inline_failed', async () => {
        await processMediaModerationJob(c.env, body, c.get?.('requestId') || '');
      });
    }
    return jobId;
  }
  throw new Error('SUPABASE_PRIMARY_REQUIRED:media_moderation_job');
}

function parseMediaAssetIds(body: any): string[] {
  return Array.from(new Set([
    ...parseJsonArray(body.media_asset_ids),
    ...parseJsonArray(body.mediaAssetIds),
    ...parseJsonArray(body.media_ids),
    ...parseJsonArray(body.mediaIds),
    body.media_asset_id,
    body.mediaAssetId,
  ].flat().map((value) => publicId(value, 160)).filter(Boolean)));
}

async function approvedMediaAssetsForPost(c: any, userId: string, requestedMediaIds: string[], imageUrls: string[]) {
  if (supabasePrimaryConfigured(c)) {
    let assets: any[] = [];
    if (requestedMediaIds.length) {
      assets = (await supabaseAdminQueryRows(c, 'app_media_assets', {
        select: '*',
        filters: {
          user_id: postgrestEqFilter(userId),
          id: postgrestInFilter(requestedMediaIds),
        },
        limit: requestedMediaIds.length,
      })).map(supabaseMediaAssetToLegacy);
      if (assets.length !== requestedMediaIds.length) {
        return { ok: false, status: 404, detail: 'One upload was not found. Please upload again.', code: 'MEDIA_NOT_FOUND', assets };
      }
    } else if (imageUrls.length) {
      const imageIds = imageUrls
        .map((url) => cloudflareImageIdFromDeliveryUrl(c.env, safeMediaReference(url)))
        .filter(Boolean);
      const uniqueImageIds = Array.from(new Set(imageIds));
      if (imageIds.length !== imageUrls.length) {
        return {
          ok: false,
          status: 409,
          detail: 'Checking your upload before posting...',
          code: 'MEDIA_MODERATION_REQUIRED',
          assets: [] as any[],
        };
      }
      const rows = (await supabaseAdminQueryRows(c, 'app_media_assets', {
        select: '*',
        filters: {
          user_id: postgrestEqFilter(userId),
          storage_provider: postgrestEqFilter('images'),
          storage_key: postgrestInFilter(uniqueImageIds),
        },
        limit: uniqueImageIds.length,
      })).map(supabaseMediaAssetToLegacy);
      const byStorageKey = new Map(rows.map((row: any) => [cleanText(row?.storage_key, 220), row]));
      assets = imageIds.map((imageId) => byStorageKey.get(imageId)).filter(Boolean);
      if (rows.length !== uniqueImageIds.length || assets.length !== imageIds.length) {
        return {
          ok: false,
          status: 409,
          detail: 'Checking your upload before posting...',
          code: 'MEDIA_MODERATION_REQUIRED',
          assets,
        };
      }
    } else {
      return { ok: true, status: 200, detail: '', code: '', assets: [] as any[] };
    }

    const blocking = assets.find((asset) => normalizeMediaModerationStatus(asset.moderation_status) !== 'approved' || cleanText(asset.upload_status, 40) !== 'uploaded');
    if (blocking) {
      const status = normalizeMediaModerationStatus(blocking.moderation_status);
      const detail = status === 'rejected'
        ? "This upload can't be posted because it may break Captro's safety rules."
        : status === 'review_required'
          ? 'This upload needs a quick safety review before it can be posted.'
          : 'Checking your upload before posting...';
      return { ok: false, status: 409, detail, code: `MEDIA_${status.toUpperCase()}`, assets };
    }
    return { ok: true, status: 200, detail: '', code: '', assets };
  }

  return {
    ok: false,
    status: 503,
    detail: 'Captro production database is not configured. Please try again later.',
    code: 'SUPABASE_PRIMARY_REQUIRED',
    assets: [] as any[],
  };
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

async function writeLegacyUserToSupabaseCanonical(c: any, userId: string) {
  const row: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  if (!row) throw new Error('CANONICAL_USER_SOURCE_NOT_FOUND');
  await supabaseAdminUpsert(c, 'app_users', [legacyUserTransferPayload(row)], 'id');
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

async function writeLegacyPostToSupabaseCanonical(c: any, postId: string) {
  const row: any = await c.env.DB.prepare(`
    SELECT p.*, u.supabase_user_id
    FROM posts p
    LEFT JOIN users u ON u.id = p.user_id
    WHERE p.id = ?
    LIMIT 1
  `).bind(postId).first();
  if (!row) throw new Error('CANONICAL_POST_SOURCE_NOT_FOUND');
  await supabaseAdminUpsert(c, 'app_posts', [legacyPostTransferPayload(row)], 'legacy_post_id');
}

async function removeLegacyPostCacheAfterCanonicalFailure(c: any, postId: string, userId: string, reason: string) {
  const code = cleanText(reason || 'supabase_canonical_write_failed', 180);
  await c.env.DB.prepare(
    "UPDATE posts SET status = 'removed', removed_at = ?, removed_reason = ? WHERE id = ?"
  ).bind(now(), code, postId).run().catch(() => undefined);
  await c.env.DB.prepare('UPDATE users SET posts_count = MAX(0, COALESCE(posts_count, 0) - 1) WHERE id = ?')
    .bind(userId)
    .run()
    .catch(() => undefined);
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

function emptySupabaseTransferResult(target: string, skipped = false, detail = '') {
  return { target, requested: 0, upserted: 0, skipped, detail };
}

async function transferLegacyBlocksToSupabase(c: any, limit: number, offset: number) {
  try {
    const rows = await c.env.DB.prepare('SELECT id, blocker_id, blocked_id, created_at FROM blocks ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
    const payload = (rows.results as any[]).map((row: any) => ({
      id: cleanText(row.id, 120) || uuid(),
      blocker_id: cleanText(row.blocker_id, 120),
      blocked_id: cleanText(row.blocked_id, 120),
      metadata: { source: 'cloudflare_d1_transfer' },
      legacy_created_at: toPgTime(row.created_at),
    })).filter((row) => row.blocker_id && row.blocked_id);
    return payload.length ? supabaseAdminUpsert(c, 'app_blocks', payload, 'id') : emptySupabaseTransferResult('app_blocks');
  } catch (error: any) {
    return emptySupabaseTransferResult('app_blocks', true, getErrorCode(error).slice(0, 120));
  }
}

async function transferLegacyNotificationsToSupabase(c: any, limit: number, offset: number) {
  try {
    const rows = await c.env.DB.prepare('SELECT * FROM notifications ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
    const payload = (rows.results as any[]).map((row: any) => ({
      id: cleanText(row.id, 120) || uuid(),
      user_id: cleanText(row.user_id, 120),
      from_user_id: cleanText(row.from_user_id || row.actor_id || '', 120) || null,
      type: cleanText(row.type || 'general', 80) || 'general',
      title: cleanText(row.title || '', 160),
      body: cleanText(row.body || row.content || '', 500),
      content: cleanText(row.content || row.body || '', 500),
      reference_id: cleanText(row.reference_id || row.post_id || row.target_id || '', 120) || null,
      data: parseJsonObject(row.data),
      is_read: Number(row.is_read || 0) === 1,
      legacy_created_at: toPgTime(row.created_at),
    })).filter((row) => row.user_id && row.id);
    return payload.length ? supabaseAdminUpsert(c, 'app_notifications', payload, 'id') : emptySupabaseTransferResult('app_notifications');
  } catch (error: any) {
    return emptySupabaseTransferResult('app_notifications', true, getErrorCode(error).slice(0, 120));
  }
}

async function transferLegacyReportsToSupabase(c: any, limit: number, offset: number) {
  try {
    const rows = await c.env.DB.prepare('SELECT * FROM reports ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
    const payload = (rows.results as any[]).map((row: any) => {
      const targetType = cleanText(row.target_type || row.reported_type || row.report_type || 'other', 80) || 'other';
      const targetId = cleanText(row.target_id || row.reported_id || row.content_id || '', 120);
      return {
        id: cleanText(row.id, 120) || uuid(),
        reporter_id: cleanText(row.reporter_id, 120),
        target_type: targetType,
        target_id: targetId || cleanText(row.reported_id, 120) || 'unknown',
        target_owner_user_id: cleanText(row.target_owner_user_id || row.reported_user_id || row.reported_id || '', 120) || null,
        reason: cleanText(row.reason || 'other', 120) || 'other',
        details: cleanText(row.details || '', 1200),
        status: cleanText(row.status || 'open', 80) || 'open',
        priority: cleanText(row.priority || 'normal', 40) || 'normal',
        assigned_to: cleanText(row.assigned_to || '', 120) || null,
        reviewed_by: cleanText(row.reviewed_by || '', 120) || null,
        action_taken: cleanText(row.action_taken || '', 240) || null,
        admin_notes: cleanText(row.admin_notes || '', 1200),
        metadata: {
          source: 'cloudflare_d1_transfer',
          legacy_report_type: cleanText(row.report_type || '', 80),
          legacy_reported_id: cleanText(row.reported_id || '', 120),
        },
        legacy_created_at: toPgTime(row.created_at),
        legacy_updated_at: toPgTime(row.updated_at),
        closed_at: toPgTime(row.closed_at),
      };
    }).filter((row) => row.reporter_id && row.id);
    return payload.length ? supabaseAdminUpsert(c, 'app_reports', payload, 'id') : emptySupabaseTransferResult('app_reports');
  } catch (error: any) {
    return emptySupabaseTransferResult('app_reports', true, getErrorCode(error).slice(0, 120));
  }
}

async function transferLegacyMessagesToSupabase(c: any, limit: number, offset: number) {
  try {
    const rows = await c.env.DB.prepare('SELECT * FROM messages ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
    const payload = (rows.results as any[]).map((row: any) => ({
      id: cleanText(row.id, 120) || uuid(),
      sender_id: cleanText(row.sender_id, 120),
      receiver_id: cleanText(row.receiver_id, 120),
      conversation_id: cleanText(row.conversation_id || '', 120) || null,
      body: cleanText(row.content || row.body || '', 5000),
      media_url: cleanText(row.media_url || row.video_url || row.image_url || '', 1200) || null,
      media_type: cleanText(row.media_type || '', 80) || null,
      media: {
        source: 'cloudflare_d1_transfer',
        media_url: cleanText(row.media_url || '', 1200),
        media_type: cleanText(row.media_type || '', 80),
      },
      is_read: Number(row.is_read || 0) === 1,
      status: cleanText(row.status || 'sent', 80) || 'sent',
      legacy_created_at: toPgTime(row.created_at),
    })).filter((row) => row.sender_id && row.receiver_id && row.id);
    return payload.length ? supabaseAdminUpsert(c, 'app_messages', payload, 'id') : emptySupabaseTransferResult('app_messages');
  } catch (error: any) {
    return emptySupabaseTransferResult('app_messages', true, getErrorCode(error).slice(0, 120));
  }
}

async function transferLegacyGroupChatsToSupabase(c: any, limit: number, offset: number) {
  const results: any[] = [];
  try {
    const groups = await c.env.DB.prepare('SELECT * FROM group_chats ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
    const groupPayload = (groups.results as any[]).map((row: any) => ({
      id: cleanText(row.id, 120) || uuid(),
      name: cleanText(row.name || '', 160),
      created_by: cleanText(row.created_by, 120),
      metadata: { source: 'cloudflare_d1_transfer' },
      legacy_created_at: toPgTime(row.created_at),
    })).filter((row) => row.id && row.created_by);
    results.push(groupPayload.length ? await supabaseAdminUpsert(c, 'app_group_chats', groupPayload, 'id') : emptySupabaseTransferResult('app_group_chats'));
  } catch (error: any) {
    results.push(emptySupabaseTransferResult('app_group_chats', true, getErrorCode(error).slice(0, 120)));
  }
  try {
    const members = await c.env.DB.prepare('SELECT * FROM group_chat_members ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
    const memberPayload = (members.results as any[]).map((row: any) => ({
      id: cleanText(row.id, 120) || uuid(),
      group_id: cleanText(row.group_id, 120),
      user_id: cleanText(row.user_id, 120),
      role: cleanText(row.role || 'member', 80) || 'member',
      legacy_created_at: toPgTime(row.created_at),
    })).filter((row) => row.group_id && row.user_id);
    results.push(memberPayload.length ? await supabaseAdminUpsert(c, 'app_group_chat_members', memberPayload, 'id') : emptySupabaseTransferResult('app_group_chat_members'));
  } catch (error: any) {
    results.push(emptySupabaseTransferResult('app_group_chat_members', true, getErrorCode(error).slice(0, 120)));
  }
  try {
    const messages = await c.env.DB.prepare('SELECT * FROM group_messages ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
    const messagePayload = (messages.results as any[]).map((row: any) => ({
      id: cleanText(row.id, 120) || uuid(),
      group_id: cleanText(row.group_id, 120),
      sender_id: cleanText(row.sender_id, 120),
      body: cleanText(row.content || row.body || '', 5000),
      media_url: cleanText(row.media_url || '', 1200) || null,
      media_type: cleanText(row.media_type || '', 80) || null,
      media: { source: 'cloudflare_d1_transfer' },
      legacy_created_at: toPgTime(row.created_at),
    })).filter((row) => row.group_id && row.sender_id && row.id);
    results.push(messagePayload.length ? await supabaseAdminUpsert(c, 'app_group_messages', messagePayload, 'id') : emptySupabaseTransferResult('app_group_messages'));
  } catch (error: any) {
    results.push(emptySupabaseTransferResult('app_group_messages', true, getErrorCode(error).slice(0, 120)));
  }
  return { target: 'app_group_chat_bundle', results };
}

async function transferLegacyPostPlacesToSupabase(c: any, limit: number, offset: number) {
  try {
    const rows = await c.env.DB.prepare('SELECT * FROM post_places ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
    const payload = (rows.results as any[]).map((row: any) => ({
      id: cleanText(row.id, 120) || uuid(),
      legacy_post_id: cleanText(row.post_id, 120),
      provider: cleanText(row.provider || 'apple_mapkit', 80) || 'apple_mapkit',
      provider_place_id: cleanText(row.provider_place_id || '', 240) || null,
      name: cleanText(row.name || '', 240),
      formatted_address: cleanText(row.formatted_address || '', 500),
      latitude: row.latitude === null || row.latitude === undefined ? null : Number(row.latitude),
      longitude: row.longitude === null || row.longitude === undefined ? null : Number(row.longitude),
      category: cleanText(row.category || '', 120) || null,
      city: cleanText(row.city || '', 120) || null,
      region: cleanText(row.region || '', 120) || null,
      country: cleanText(row.country || '', 120) || null,
      metadata: { source: 'cloudflare_d1_transfer' },
      legacy_created_at: toPgTime(row.created_at),
    })).filter((row) => row.legacy_post_id && row.id);
    return payload.length ? supabaseAdminUpsert(c, 'app_post_places', payload, 'id') : emptySupabaseTransferResult('app_post_places');
  } catch (error: any) {
    return emptySupabaseTransferResult('app_post_places', true, getErrorCode(error).slice(0, 120));
  }
}

async function transferLegacyMediaAssetsToSupabase(c: any, limit: number, offset: number) {
  try {
    const rows = await c.env.DB.prepare('SELECT * FROM media_assets ORDER BY created_at LIMIT ? OFFSET ?').bind(limit, offset).all();
    const payload = (rows.results as any[]).map((row: any) => ({
      id: cleanText(row.id, 120) || uuid(),
      user_id: cleanText(row.user_id, 120),
      legacy_post_id: cleanText(row.post_id || '', 120) || null,
      media_type: cleanText(row.media_type || '', 40) || 'image',
      storage_provider: cleanText(row.storage_provider || '', 40) || 'images',
      storage_key: cleanText(row.storage_key || '', 600),
      public_url: cleanText(row.public_url || '', 1200) || null,
      private_url: cleanText(row.private_url || '', 1200) || null,
      mime_type: cleanText(row.mime_type || '', 120),
      file_size: Number(row.file_size || 0),
      sha256_hash: cleanText(row.sha256_hash || '', 80),
      width: row.width === null || row.width === undefined ? null : Number(row.width),
      height: row.height === null || row.height === undefined ? null : Number(row.height),
      duration_seconds: row.duration_seconds === null || row.duration_seconds === undefined ? null : Number(row.duration_seconds),
      upload_status: cleanText(row.upload_status || 'uploading', 80) || 'uploading',
      moderation_status: cleanText(row.moderation_status || 'uploading', 80) || 'uploading',
      rejection_code: cleanText(row.rejection_code || '', 120) || null,
      rejection_message: cleanText(row.rejection_message || '', 400) || null,
      metadata: { source: 'cloudflare_d1_transfer' },
      legacy_created_at: toPgTime(row.created_at),
    })).filter((row) => row.user_id && row.storage_key && row.id);
    return payload.length ? supabaseAdminUpsert(c, 'app_media_assets', payload, 'id') : emptySupabaseTransferResult('app_media_assets');
  } catch (error: any) {
    return emptySupabaseTransferResult('app_media_assets', true, getErrorCode(error).slice(0, 120));
  }
}

async function backfillLegacyUsersToSupabaseAuth(c: any, limit: number, offset: number) {
  await ensureSupabaseAuthSchema(c.env.DB);
  const rows = await c.env.DB.prepare(
    `SELECT id, email, phone, phone_verified, username, full_name, profile_image, oauth_provider, oauth_subject, supabase_user_id, status
     FROM users
     WHERE COALESCE(status, 'active') != 'deleted'
     ORDER BY created_at
     LIMIT ? OFFSET ?`
  ).bind(limit, offset).all();

  const result = {
    target: 'supabase_auth_users',
    processed: 0,
    linked: 0,
    already_linked: 0,
    skipped: 0,
    failed: 0,
    failures: [] as Array<{ user_id: string; code: string }>,
  };

  for (const row of (rows.results as any[])) {
    result.processed += 1;
    if (row.supabase_user_id) {
      result.already_linked += 1;
      continue;
    }

    const email = normalizeOptionalEmail(row.email);
    const phone = Number(row.phone_verified || 0) === 1 ? normalizeOptionalPhone(row.phone) : '';
    const provider = supabaseAuthProvider(row.oauth_provider || (phone ? 'phone' : 'email'));
    if ((!email || isInternalOAuthEmail(email)) && !phone) {
      result.skipped += 1;
      continue;
    }

    try {
      const authResult = await createOrFindSupabaseAuthUser(c, {
        email: email && !isInternalOAuthEmail(email) ? email : undefined,
        phone: phone || undefined,
        username: publicUsernameFor(row),
        fullName: row.full_name,
        profileImage: row.profile_image,
        provider,
        oauthSubject: row.oauth_subject,
        appUserId: row.id,
      });
      if (!authResult.user?.id) throw new Error('SUPABASE_AUTH_CREATE_EMPTY');
      await linkSupabaseAuthUser(c, row.id, authResult.user.id);
      await syncSupabaseAuthMetadataForUser(c, { ...row, supabase_user_id: authResult.user.id });
      await logSecurityEvent(c, 'supabase_auth_backfilled', row.id, { provider });
      result.linked += 1;
    } catch (error: any) {
      result.failed += 1;
      if (result.failures.length < 20) {
        result.failures.push({ user_id: String(row.id || ''), code: getErrorCode(error).slice(0, 160) });
      }
    }
  }

  return result;
}

// AUTH
// ═══════════════════════════════════════════════════════════════════════════════
api.post('/auth/supabase', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 140_000);
    if (bodyTooLarge) return bodyTooLarge;
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'auth_supabase');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'auth_supabase', clientIp(c), 60, 300);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const rawAccessToken = body.access_token || body.token;
    const session = await issueCaptroTokenForSupabaseAccessToken(c, rawAccessToken, body);
    return c.json(supabaseAuthSessionResponse({ access_token: rawAccessToken, token_type: 'bearer' }, session.user));
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'SUPABASE_NOT_CONFIGURED') return c.json({ detail: 'Supabase auth is not configured on the backend.' }, 503);
    if (code === 'SUPABASE_TOKEN_REQUIRED') return c.json({ detail: 'Supabase access token is required.' }, 400);
    if (code === 'EMAIL_REQUIRED') return c.json({ detail: 'Supabase account email is required.' }, 400);
    if (code === 'ACCOUNT_DISABLED') return c.json({ detail: 'This account cannot be used.' }, 403);
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
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'auth_register');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'auth_register', clientIp(c), 8, 300);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'auth_register_daily', clientIp(c), 20, 86400);
    if (dailyLimited) return dailyLimited;
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['email', 'password', 'username', 'full_name', 'fullName', 'terms_version', 'termsVersion', 'terms_accepted_at', 'termsAcceptedAt']);
    if (unknown) return unknown;
    const termsAcceptance = termsAcceptanceFromBody(body);
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
    const [emailMatches, usernameMatches] = await Promise.all([
      supabaseAdminQueryRows(c, 'app_users', {
        select: SUPABASE_APP_USER_SELECT,
        filters: { email: postgrestEqFilter(email) },
        limit: 1,
      }),
      supabaseAdminQueryRows(c, 'app_users', {
        select: SUPABASE_APP_USER_SELECT,
        filters: { username: postgrestEqFilter(safeUsername) },
        limit: 1,
      }),
    ]);
    const existing = emailMatches[0] || usernameMatches[0];
    if (existing) {
      const existingUser = supabaseAppUserToLegacyUser(existing);
      await logSecurityEvent(c, 'signup_duplicate_blocked', '', { username: safeUsername });
      if (String(existingUser.status || 'active') === 'deletion_pending') {
        return c.json({
          detail: 'This account is scheduled for deletion. Sign in to restore it.',
          code: 'ACCOUNT_DELETION_PENDING',
          deletion_scheduled_at: existingUser.deletion_scheduled_at || null,
        }, 409);
      }
      return c.json({ detail: 'Email or username already exists' }, 400);
    }

    const authResult = await createOrFindSupabaseAuthUser(c, {
      email,
      password,
      username: safeUsername,
      fullName,
      provider: 'email',
      termsVersion: termsAcceptance?.version,
      termsAcceptedAt: termsAcceptance?.acceptedAt,
    });
    if (!authResult.user?.id) throw new Error('SUPABASE_AUTH_CREATE_EMPTY');
    let appUser: any;
    try {
      appUser = await findOrCreateSupabaseAppUser(c, {
        sub: authResult.user.id,
        email,
        user_metadata: {
          username: safeUsername,
          full_name: fullName,
          ...termsAcceptanceMetadata(termsAcceptance),
        },
        app_metadata: {
          provider: 'email',
        },
      }, {
        email,
        username: safeUsername,
        full_name: fullName,
        provider: 'email',
        provider_user_id: authResult.user.id,
      });
    } catch (insertError) {
      if (authResult.created) await deleteSupabaseAuthUser(c, authResult.user.id);
      throw insertError;
    }

    await recordAbuseSignals(c, appUser.id, 'signup', { username: safeUsername, display_name: fullName });
    await upsertAccountIdentity(c, { userId: appUser.id, provider: 'email', providerUserId: authResult.user.id, email });
    await recordTermsAcceptance(c, appUser, authResult.user.id, termsAcceptance, 'email_register');
    await logSecurityEvent(c, 'signup_created', appUser.id, { username: safeUsername });
    runBackgroundTask(c, 'supabase_signup_metadata_sync_failed', async () => {
      await syncSupabaseAuthMetadataForUser(c, appUser);
    });
    const supabaseSession = await signInSupabasePassword(c, email, password);
    return c.json(supabaseAuthSessionResponse(supabaseSession, appUser));
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    if (code === 'SUPABASE_NOT_CONFIGURED' || code === 'SUPABASE_SERVICE_ROLE_MISSING') {
      return c.json({ detail: 'Supabase Authentication is not configured for account creation.' }, 503);
    }
    if (code.includes('23505') || code.toLowerCase().includes('duplicate key') || code.includes('app_users_username_lower_idx')) {
      return c.json({ detail: 'Email or username already exists' }, 400);
    }
    if (code.startsWith('SUPABASE_AUTH_CREATE_FAILED')) {
      return c.json({ detail: 'Could not create the Supabase Auth account.' }, 502);
    }
    console.warn(JSON.stringify({ event: 'auth_register_failed', code: code.slice(0, 180) }));
    return c.json({ detail: 'Could not create account.' }, 500);
  }
});

api.post('/auth/login', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 60_000);
    if (bodyTooLarge) return bodyTooLarge;
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'auth_login');
    if (supabaseRequired) return supabaseRequired;
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['email', 'password', 'terms_version', 'termsVersion', 'terms_accepted_at', 'termsAcceptedAt']);
    if (unknown) return unknown;
    const termsAcceptance = termsAcceptanceFromBody(body);
    const email = normalizeOptionalEmail(body.email);
    const password = String(body.password || '');
    if (!email || !password) return c.json({ detail: 'Invalid email or password.' }, 401);
    const limited = await enforceRateLimit(c, 'auth_login', `${clientIp(c)}:${email}`, 20, 300);
    if (limited) return limited;
    const ipLimited = await enforceRateLimit(c, 'auth_login_ip', clientIp(c), 80, 300);
    if (ipLimited) return ipLimited;

    try {
      const supabaseSession = await signInSupabasePassword(c, email, password);
      const session = await issueCaptroTokenForSupabaseAccessToken(c, supabaseSession.access_token, {
        email,
        full_name: supabaseSession.user?.user_metadata?.full_name || supabaseSession.user?.user_metadata?.name || '',
        profile_image: supabaseSession.user?.user_metadata?.avatar_url || supabaseSession.user?.user_metadata?.picture || '',
      });
      await recordTermsAcceptance(c, session.user, supabaseSession.user?.id, termsAcceptance, 'email_login');
      return c.json(supabaseAuthSessionResponse(supabaseSession, session.user));
    } catch (error: any) {
      const code = getErrorCode(error);
      if (code === 'ACCOUNT_DISABLED') return c.json({ detail: 'This account cannot be used.' }, 403);
      await logSecurityEvent(c, 'login_failed', '', { reason: 'supabase_password' });
      if (code === 'SUPABASE_AUTH_KEY_MISSING' || code === 'SUPABASE_NOT_CONFIGURED' || code === 'SUPABASE_SERVICE_ROLE_MISSING') {
        return c.json({ detail: 'Auth service is not configured.' }, 503);
      }
      if (code.startsWith('SUPABASE_PASSWORD_SIGN_IN_FAILED')) {
        return c.json({ detail: 'Invalid email or password.' }, 401);
      }
      console.warn(JSON.stringify({ event: 'supabase_password_login_failed', code: code.slice(0, 160) }));
      return c.json({ detail: 'Could not sign in right now.' }, 502);
    }
  } catch (error: any) {
    if (getErrorCode(error) === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    return c.json({ detail: 'Could not log in' }, 500);
  }
});

api.post('/auth/phone/start', async (c) => {
  try {
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'phone_sign_in_start');
    if (supabaseRequired) return supabaseRequired;
    return c.json({
      detail: 'Phone sign in is not available. Use email, Google, or Apple sign in.',
      code: 'PHONE_SIGN_IN_DISABLED',
    }, 410);
  } catch (error: any) {
    const code = String(error?.message || '');
    console.error(JSON.stringify({ event: 'phone_login_start_failed', error: code.slice(0, 180) }));
    return c.json({ detail: 'Could not start phone sign in. Please try again in a moment.', code: 'PHONE_START_FAILED' }, 500);
  }
});

api.post('/auth/phone/verify', async (c) => {
  try {
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'phone_sign_in_verify');
    if (supabaseRequired) return supabaseRequired;
    return c.json({
      detail: 'Phone sign in is not available. Use email, Google, or Apple sign in.',
      code: 'PHONE_SIGN_IN_DISABLED',
    }, 410);
  } catch (error: any) {
    const code = String(error?.message || '');
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
    session_bridge: {
      configured: Boolean(String(c.env.OAUTH_FALLBACK_SECRET || '').trim()),
      supabase_configured: Boolean(String(c.env.SUPABASE_URL || '').trim())
        && Boolean(String(c.env.SUPABASE_ANON_KEY || c.env.SUPABASE_PUBLISHABLE_KEY || '').trim())
        && Boolean(String(c.env.SUPABASE_SERVICE_ROLE_KEY || '').trim()),
    },
  });
});

api.post('/auth/refresh', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 40_000);
    if (bodyTooLarge) return bodyTooLarge;
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'auth_refresh');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'auth_refresh', clientIp(c), 60, 300);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const refreshToken = cleanText(body.refresh_token || body.refreshToken || '', 4096);
    if (!refreshToken) return c.json({ detail: 'refresh_token is required' }, 400);

    const session = await refreshSupabaseSession(c, refreshToken);
    const issued = await issueCaptroTokenForSupabaseAccessToken(c, session.access_token);
    return c.json(supabaseAuthSessionResponse(session, issued.user));
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'SUPABASE_REFRESH_TOKEN_REQUIRED') return c.json({ detail: 'refresh_token is required' }, 400);
    if (code.startsWith('SUPABASE_REFRESH_FAILED:400') || code.startsWith('SUPABASE_REFRESH_FAILED:401') || code.startsWith('SUPABASE_REFRESH_FAILED:403')) {
      return c.json({ detail: 'Invalid session. Please sign in again.', code: 'INVALID_TOKEN' }, 401);
    }
    if (code === 'ACCOUNT_DISABLED') return c.json({ detail: 'This account cannot be used.' }, 403);
    return c.json({ detail: 'Session refresh failed. Please sign in again.', code: 'SESSION_REFRESH_FAILED' }, 401);
  }
});

api.post('/auth/password/reset/request', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 20_000);
    if (bodyTooLarge) return bodyTooLarge;
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'password_reset_request');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'password_reset_request', clientIp(c), 12, 600);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['email', 'redirect_to', 'redirectTo']);
    if (unknown) return unknown;
    const email = normalizeOptionalEmail(body.email);
    if (!email) return c.json({ detail: 'A valid email is required.', code: 'EMAIL_REQUIRED' }, 400);
    const redirectTo = passwordResetRedirectTarget(body.redirect_to || body.redirectTo);
    await sendSupabasePasswordRecovery(c, email, redirectTo);
    await logSecurityEvent(c, 'password_reset_requested', '', { email_hash_hint: (await sha256Hex(email)).slice(0, 16), redirect_to: redirectTo.slice(0, 120) });
    return c.json({
      sent: true,
      detail: 'If that email belongs to a Captro account, we sent a password reset link.',
      redirect_to: redirectTo,
    });
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'SUPABASE_AUTH_KEY_MISSING' || code === 'SUPABASE_NOT_CONFIGURED') {
      return c.json({ detail: 'Password reset is not configured right now.' }, 503);
    }
    if (code.startsWith('SUPABASE_PASSWORD_RECOVERY_FAILED:429')) {
      return c.json({ detail: 'Too many reset attempts. Please wait a bit and try again.', code: 'RATE_LIMITED' }, 429);
    }
    console.warn(JSON.stringify({ event: 'password_reset_request_failed', code: code.slice(0, 180) }));
    return c.json({ detail: 'Could not send the reset email right now. Please try again later.', code: 'PASSWORD_RESET_REQUEST_FAILED' }, 502);
  }
});

api.post('/auth/password/reset/confirm', async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 40_000);
    if (bodyTooLarge) return bodyTooLarge;
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'password_reset_confirm');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'password_reset_confirm', clientIp(c), 12, 600);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['access_token', 'accessToken', 'refresh_token', 'refreshToken', 'password']);
    if (unknown) return unknown;
    const accessToken = cleanText(body.access_token || body.accessToken || '', 8192);
    const refreshToken = cleanText(body.refresh_token || body.refreshToken || '', 8192);
    const password = String(body.password || '');
    if (!accessToken) return c.json({ detail: 'Reset session is missing. Open the email link again.', code: 'RESET_TOKEN_REQUIRED' }, 400);
    if (password.length < 6) return c.json({ detail: 'Password must be at least 6 characters.', code: 'PASSWORD_TOO_SHORT' }, 400);

    await updateSupabasePassword(c, accessToken, password);
    let supabaseSession: any = { access_token: accessToken, refresh_token: refreshToken || undefined, token_type: 'bearer' };
    if (refreshToken) {
      try {
        supabaseSession = await refreshSupabaseSession(c, refreshToken);
      } catch (error: any) {
        console.warn(JSON.stringify({ event: 'password_reset_refresh_after_update_failed', code: getErrorCode(error).slice(0, 180) }));
      }
    }
    const session = await issueCaptroTokenForSupabaseAccessToken(c, supabaseSession.access_token, {
      password_reset_completed: true,
    });
    await logSecurityEvent(c, 'password_reset_completed', session.user.id, {});
    return c.json(supabaseAuthSessionResponse(supabaseSession, session.user));
  } catch (error: any) {
    const code = getErrorCode(error);
    if (code === 'SUPABASE_PASSWORD_RESET_TOKEN_REQUIRED') {
      return c.json({ detail: 'Reset session is missing. Open the email link again.', code: 'RESET_TOKEN_REQUIRED' }, 400);
    }
    if (code === 'SUPABASE_PASSWORD_RESET_PASSWORD_TOO_SHORT') {
      return c.json({ detail: 'Password must be at least 6 characters.', code: 'PASSWORD_TOO_SHORT' }, 400);
    }
    if (code.startsWith('SUPABASE_PASSWORD_UPDATE_FAILED:400') || code.startsWith('SUPABASE_PASSWORD_UPDATE_FAILED:401') || code.startsWith('SUPABASE_PASSWORD_UPDATE_FAILED:403')) {
      return c.json({ detail: 'This reset link is no longer valid. Request a new one and try again.', code: 'RESET_LINK_INVALID' }, 401);
    }
    if (code === 'ACCOUNT_DISABLED') return c.json({ detail: 'This account cannot be used.' }, 403);
    console.warn(JSON.stringify({ event: 'password_reset_confirm_failed', code: code.slice(0, 180) }));
    return c.json({ detail: 'Could not reset the password right now. Please try again later.', code: 'PASSWORD_RESET_CONFIRM_FAILED' }, 502);
  }
});

api.post('/auth/oauth/google', async (c) => {
  let stage = 'request_validation';
  try {
    const bodyTooLarge = rejectLargeRequest(c, 120_000);
    if (bodyTooLarge) return bodyTooLarge;
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'oauth_google');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'oauth_google', clientIp(c), 30, 300);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['id_token', 'idToken', 'access_token', 'accessToken', 'nonce', 'raw_nonce', 'rawNonce', 'terms_version', 'termsVersion', 'terms_accepted_at', 'termsAcceptedAt']);
    if (unknown) return unknown;
    const termsAcceptance = termsAcceptanceFromBody(body);
    const id_token = String(body.id_token || body.idToken || '');
    if (!id_token) return c.json({ detail: 'Google sign in did not return a credential.', code: 'GOOGLE_CREDENTIAL_MISSING' }, 400);

    logOAuthStage(c, 'google', 'credential_received', 'passed', undefined, 'verified_bridge');
    stage = 'credential_verification';
    logOAuthStage(c, 'google', stage, 'started', undefined, 'verified_bridge');
    const profile = await verifyGoogleIdToken(c, id_token);
    logOAuthStage(c, 'google', stage, 'passed', undefined, 'verified_bridge');

    stage = 'session_creation';
    logOAuthStage(c, 'google', stage, 'started', undefined, 'verified_bridge');
    const verifiedSession = await signInSupabaseVerifiedOAuth(c, {
      provider: 'google',
      subject: profile.subject,
      email: profile.email,
      fullName: profile.fullName,
      profileImage: profile.profileImage,
      termsVersion: termsAcceptance?.version,
      termsAcceptedAt: termsAcceptance?.acceptedAt,
    });
    logOAuthStage(c, 'google', stage, 'passed', undefined, 'verified_bridge');
    await logSecurityEvent(c, 'google_verified_oauth_session_created', verifiedSession.user.id, {
      provider: 'google',
      strategy: 'verified_bridge',
    });
    return c.json(supabaseAuthSessionResponse(verifiedSession.supabaseSession, verifiedSession.user));
  } catch (error: any) {
    const code = getErrorCode(error);
    logOAuthStage(c, 'google', stage, 'failed', error, 'verified_bridge');
    if (code === 'GOOGLE_OAUTH_NOT_CONFIGURED') {
      return c.json({ detail: 'Google sign in is temporarily unavailable.', code: 'GOOGLE_PROVIDER_CONFIGURATION' }, 503);
    }
    if (code === 'GOOGLE_AUDIENCE_INVALID') return c.json({ detail: 'Google sign in is not configured for this Captro build.', code: 'GOOGLE_AUDIENCE_MISMATCH' }, 401);
    if (code === 'GOOGLE_EMAIL_UNVERIFIED') return c.json({ detail: 'This Google account email is not verified.', code: 'GOOGLE_EMAIL_UNVERIFIED' }, 401);
    if (code.startsWith('GOOGLE_') || code === 'OAUTH_SUBJECT_REQUIRED') {
      return c.json({ detail: 'Could not verify the Google sign in response.', code: 'GOOGLE_PROVIDER_CREDENTIAL_INVALID' }, 401);
    }
    if (code === 'ACCOUNT_DISABLED') return c.json({ detail: 'This account cannot be used.', code: 'ACCOUNT_DISABLED' }, 403);
    if (code === 'EMAIL_REQUIRED') return c.json({ detail: 'Google account email is required.', code: 'GOOGLE_EMAIL_REQUIRED' }, 400);
    if (code === 'JWT_SECRET_MISSING' || code === 'OAUTH_FALLBACK_SECRET_MISSING' || code === 'SUPABASE_AUTH_KEY_MISSING' || code === 'SUPABASE_NOT_CONFIGURED' || code === 'SUPABASE_SERVICE_ROLE_MISSING') {
      return c.json({ detail: 'Google sign in is temporarily unavailable.', code: 'AUTH_PROVIDER_CONFIGURATION' }, 503);
    }
    return c.json({ detail: 'Could not finish Google sign in right now.', code: 'GOOGLE_CREDENTIAL_EXCHANGE_FAILED' }, 502);
  }
});

api.post('/auth/oauth/apple', async (c) => {
  let stage = 'request_validation';
  try {
    const bodyTooLarge = rejectLargeRequest(c, 120_000);
    if (bodyTooLarge) return bodyTooLarge;
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'oauth_apple');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'oauth_apple', clientIp(c), 30, 300);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['id_token', 'idToken', 'email', 'full_name', 'fullName', 'apple_user', 'appleUser', 'nonce', 'raw_nonce', 'rawNonce', 'terms_version', 'termsVersion', 'terms_accepted_at', 'termsAcceptedAt']);
    if (unknown) return unknown;
    const termsAcceptance = termsAcceptanceFromBody(body);
    const idToken = String(body.id_token || body.idToken || '');
    if (!idToken) return c.json({ detail: 'Apple sign in did not return a credential.', code: 'APPLE_CREDENTIAL_MISSING' }, 400);
    const rawNonce = cleanText(body.nonce || body.raw_nonce || body.rawNonce, 512);
    if (!rawNonce) return c.json({ detail: 'Apple sign in could not be securely completed.', code: 'APPLE_NONCE_REQUIRED' }, 400);

    const clientEmail = normalizeOptionalEmail(body.email);
    const clientFullName = normalizeOptionalName(body.full_name || body.fullName);
    logOAuthStage(c, 'apple', 'credential_received', 'passed', undefined, 'verified_bridge');
    stage = 'credential_verification';
    logOAuthStage(c, 'apple', stage, 'started', undefined, 'verified_bridge');
    const profile = await verifyAppleIdToken(c, idToken, rawNonce);
    logOAuthStage(c, 'apple', stage, 'passed', undefined, 'verified_bridge');

    const appleSubject = profile.subject || cleanText(body.apple_user || body.appleUser, 240);
    stage = 'session_creation';
    logOAuthStage(c, 'apple', stage, 'started', undefined, 'verified_bridge');
    const verifiedSession = await signInSupabaseVerifiedOAuth(c, {
      provider: 'apple',
      subject: appleSubject,
      email: profile.email || clientEmail || undefined,
      fullName: clientFullName || profile.fullName || 'Apple User',
      profileImage: profile.profileImage,
      termsVersion: termsAcceptance?.version,
      termsAcceptedAt: termsAcceptance?.acceptedAt,
    });
    logOAuthStage(c, 'apple', stage, 'passed', undefined, 'verified_bridge');
    await logSecurityEvent(c, 'apple_verified_oauth_session_created', verifiedSession.user.id, {
      provider: 'apple',
      strategy: 'verified_bridge',
    });
    return c.json(supabaseAuthSessionResponse(verifiedSession.supabaseSession, verifiedSession.user));
  } catch (error: any) {
    const code = getErrorCode(error);
    logOAuthStage(c, 'apple', stage, 'failed', error, 'verified_bridge');
    if (code === 'EMAIL_REQUIRED') return c.json({ detail: 'Apple account email is required on first sign-in.', code: 'APPLE_EMAIL_REQUIRED' }, 400);
    if (code === 'OAUTH_SUBJECT_REQUIRED' || code === 'APPLE_SUBJECT_MISSING') return c.json({ detail: 'Apple account identifier was missing.', code: 'APPLE_PROVIDER_CREDENTIAL_INVALID' }, 400);
    if (code === 'APPLE_NONCE_REQUIRED' || code === 'APPLE_NONCE_MISMATCH') return c.json({ detail: 'Apple sign in could not be securely completed.', code: 'APPLE_NONCE_INVALID' }, 401);
    if (code === 'JWT_SECRET_MISSING' || code === 'OAUTH_FALLBACK_SECRET_MISSING' || code === 'SUPABASE_AUTH_KEY_MISSING' || code === 'SUPABASE_NOT_CONFIGURED' || code === 'SUPABASE_SERVICE_ROLE_MISSING') {
      return c.json({ detail: 'Apple sign in is temporarily unavailable.', code: 'AUTH_PROVIDER_CONFIGURATION' }, 503);
    }
    if (code === 'ACCOUNT_DISABLED') return c.json({ detail: 'This account cannot be used.', code: 'ACCOUNT_DISABLED' }, 403);
    if (code === 'ERR_JWT_CLAIM_VALIDATION_FAILED' && error?.claim === 'aud') return c.json({ detail: 'Apple sign in is not configured for this Captro build.', code: 'APPLE_AUDIENCE_MISMATCH' }, 401);
    if (code === 'ERR_JWT_EXPIRED') return c.json({ detail: 'Apple sign in has expired. Please try again.', code: 'APPLE_PROVIDER_CREDENTIAL_EXPIRED' }, 401);
    if (code.startsWith('APPLE_') || code.startsWith('ERR_JWT_') || code.startsWith('ERR_JWS_') || code.startsWith('ERR_JWKS_')) {
      return c.json({ detail: 'Could not verify the Apple sign in response.', code: 'APPLE_PROVIDER_CREDENTIAL_INVALID' }, 401);
    }
    return c.json({ detail: 'Could not finish Apple sign in right now.', code: 'APPLE_CREDENTIAL_EXCHANGE_FAILED' }, 502);
  }
});

api.get('/auth/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'auth_me');
  if (supabaseRequired) return supabaseRequired;
  const user = await getSupabaseSessionUserByAnyId(c, userId);
  if (!user) return c.json({ detail: 'User not found' }, 404);
  return c.json(authUserPayload(user));
});

async function accountIdentityMatches(c: any, user: any, provider: string, providerUserId: string): Promise<boolean> {
  const cleanProvider = normalizeAuthProvider(provider);
  const cleanProviderUserId = cleanText(providerUserId, 240);
  if (!cleanProviderUserId) return false;
  if (normalizeAuthProvider(user.oauth_provider) === cleanProvider && cleanText(user.oauth_subject, 240) === cleanProviderUserId) return true;
  const rows = await supabaseAdminQueryRows(c, 'app_account_identities', {
    select: 'id',
    filters: {
      user_id: postgrestEqFilter(publicId(user.id, 120)),
      provider: postgrestEqFilter(cleanProvider),
      provider_user_id: postgrestEqFilter(cleanProviderUserId),
    },
    limit: 1,
  });
  return rows.length > 0;
}

async function verifyAccountDeletionReauth(c: any, user: any, body: any): Promise<{ ok: boolean; detail?: string; provider: string }> {
  const provider = normalizeAuthProvider(body.provider || user.oauth_provider || (user.phone ? 'phone' : 'email'));
  const password = String(body.password || '').trim();
  const idToken = String(body.id_token || body.idToken || '').trim();

  if (provider === 'google') {
    if (!idToken) return { ok: false, detail: 'Re-authenticate with Google before deleting this account.', provider };
    const profile = await verifyGoogleIdToken(c, idToken);
    if (!(await accountIdentityMatches(c, user, 'google', profile.subject))) {
      return { ok: false, detail: 'Google account did not match this Captro account.', provider };
    }
    await upsertAccountIdentity(c, { userId: user.id, provider: 'google', providerUserId: profile.subject, email: profile.email || user.email });
    return { ok: true, provider };
  }

  if (provider === 'apple') {
    if (!idToken) return { ok: false, detail: 'Re-authenticate with Apple before deleting this account.', provider };
    const profile = await verifyAppleIdToken(c, idToken);
    if (!(await accountIdentityMatches(c, user, 'apple', profile.subject))) {
      return { ok: false, detail: 'Apple account did not match this Captro account.', provider };
    }
    await upsertAccountIdentity(c, { userId: user.id, provider: 'apple', providerUserId: profile.subject, email: profile.email || user.email });
    return { ok: true, provider };
  }

  if (!password) return { ok: false, detail: 'Enter your password to delete this account.', provider: 'email' };
  if (user.supabase_user_id) {
    const email = normalizeOptionalEmail(user.email);
    if (!email || isInternalOAuthEmail(email)) return { ok: false, detail: 'Add a real email address before deleting this account.', provider: 'email' };
    try {
      const session = await signInSupabasePassword(c, email, password);
      const sessionUserId = isUuidText(session?.user?.id || session?.user?.sub);
      if (sessionUserId && sessionUserId !== user.supabase_user_id) {
        return { ok: false, detail: 'Password confirmation did not match this Captro account.', provider: 'email' };
      }
      return { ok: true, provider: 'email' };
    } catch {
      return { ok: false, detail: 'Password confirmation failed.', provider: 'email' };
    }
  }
  return { ok: false, detail: 'Supabase Auth identity is required before deleting this account.', provider: 'email' };
}

async function revokeProviderAccessBestEffort(c: any, user: any, provider: string, body: any) {
  const metadata: Record<string, unknown> = { provider };
  try {
    if (provider === 'google') {
      const token = cleanText(body.access_token || body.accessToken || '', 4096);
      if (token) {
        await fetch(`https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(token)}`, { method: 'POST' }).catch(() => null);
        metadata.google_revoke = 'requested';
      } else {
        metadata.google_revoke = 'token_not_available';
      }
    } else if (provider === 'apple') {
      const token = cleanText(body.authorization_code || body.authorizationCode || body.refresh_token || body.refreshToken || '', 4096);
      const clientId = cleanText(c.env.APPLE_OAUTH_CLIENT_ID || c.env.APPLE_OAUTH_AUDIENCE || c.env.APPLE_OAUTH_AUDIENCES?.split(',')?.[0] || '', 240);
      const clientSecret = String(c.env.APPLE_REVOKE_CLIENT_SECRET || c.env.APPLE_OAUTH_CLIENT_SECRET || '').trim();
      if (token && clientId && clientSecret) {
        const form = new URLSearchParams();
        form.set('client_id', clientId);
        form.set('client_secret', clientSecret);
        form.set('token', token);
        form.set('token_type_hint', body.refresh_token || body.refreshToken ? 'refresh_token' : 'authorization_code');
        await fetch('https://appleid.apple.com/auth/revoke', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: form.toString(),
        }).catch(() => null);
        metadata.apple_revoke = 'requested';
      } else {
        metadata.apple_revoke = token ? 'server_secret_not_configured' : 'token_not_available';
      }
    }
    if (user.supabase_user_id) {
      await updateSupabaseAuthUser(c, user.supabase_user_id, {
        user_metadata: { captro_user_id: user.id, account_status: 'deletion_pending' },
        app_metadata: { captro_account_status: 'deletion_pending' },
      }).catch(() => {});
      metadata.supabase_marked_pending = true;
    }
  } finally {
    await writeAccountDeletionEvent(c, user.id, 'provider_revoke_best_effort', metadata);
  }
}

async function requestAccountDeletion(c: any) {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'account_delete');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'account_delete', userId, 5, 86400);
  if (limited) return limited;
  const bodyTooLarge = rejectLargeRequest(c, 80_000);
  if (bodyTooLarge) return bodyTooLarge;
  const body: any = await c.req.json().catch(() => ({}));
  if (String(body.confirmation || '').trim() !== 'DELETE') {
    return c.json({ detail: 'Type DELETE to confirm account deletion.', code: 'confirmation_required' }, 400);
  }

  const currentRow = await getSupabaseAppUserRowByAnyId(c, userId);
  if (!currentRow) return c.json({ detail: 'User not found.' }, 404);
  const user = supabaseAppUserToLegacyUser(currentRow);
  const appUserId = publicId(user.id, 120);
  if (user.is_admin) return c.json({ detail: 'Admin accounts must be removed by another admin.' }, 403);
  if (String(user.status || 'active') === 'deletion_pending') {
    return c.json({
      deletion_pending: true,
      deletion_requested_at: user.deletion_requested_at || null,
      deletion_scheduled_at: user.deletion_scheduled_at || null,
    });
  }
  if (String(user.status || 'active') === 'deleted') {
    return c.json({ detail: 'This account has already been deleted.', code: 'account_deleted' }, 410);
  }

  const reauth = await verifyAccountDeletionReauth(c, user, body);
  if (!reauth.ok) return c.json({ detail: reauth.detail || 'Re-authentication is required.', code: 'reauth_required' }, 401);

  const requestedAt = now();
  const scheduledAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
  const metadata = parseJsonObject(currentRow.metadata);
  metadata.status = 'deletion_pending';
  metadata.deletion_requested_at = requestedAt;
  metadata.deletion_scheduled_at = scheduledAt;
  metadata.session_revoked_at = requestedAt;
  await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(appUserId) }, {
    metadata,
    updated_at: requestedAt,
  });
  await Promise.all([
    supabaseAdminPatchRows(c, 'app_push_tokens', { user_id: postgrestEqFilter(appUserId) }, { is_active: false, updated_at: requestedAt }).catch(() => undefined),
    supabaseAdminDeleteRowsIfShapeExists(c, 'app_notifications', { user_id: postgrestEqFilter(appUserId) }).catch(() => undefined),
    supabaseAdminDeleteRowsIfShapeExists(c, 'app_notifications', { from_user_id: postgrestEqFilter(appUserId) }).catch(() => undefined),
    supabaseAdminDeleteRowsIfShapeExists(c, 'app_post_interactions', { app_user_id: postgrestEqFilter(appUserId) }).catch(() => undefined),
    supabaseAdminDeleteRowsIfShapeExists(c, 'app_follows', { app_follower_id: postgrestEqFilter(appUserId) }).catch(() => undefined),
    supabaseAdminDeleteRowsIfShapeExists(c, 'app_follows', { app_following_id: postgrestEqFilter(appUserId) }).catch(() => undefined),
    supabaseAdminPatchRows(c, 'post_comments', { app_user_id: postgrestEqFilter(appUserId) }, { status: 'hidden', updated_at: requestedAt }).catch(() => undefined),
  ]);
  await updateSupabaseAuthUser(c, user.supabase_user_id, {
    user_metadata: { captro_user_id: appUserId, account_status: 'deletion_pending' },
    app_metadata: { captro_account_status: 'deletion_pending' },
  }).catch(() => {});
  runBackgroundTask(c, 'account_deletion_audit_failed', async () => {
    await writeAccountDeletionEvent(c, appUserId, 'deletion_requested', {
      provider: reauth.provider,
      deletion_scheduled_at: scheduledAt,
    });
    await logSecurityEvent(c, 'account_deletion_requested', appUserId, { provider: reauth.provider });
  });
  runBackgroundTask(c, 'provider_revoke_best_effort_failed', async () => {
    await revokeProviderAccessBestEffort(c, user, reauth.provider, body);
  });
  return c.json({
    deletion_pending: true,
    deletion_requested_at: requestedAt,
    deletion_scheduled_at: scheduledAt,
    detail: 'Account deletion is scheduled. Your public profile and content are hidden now.',
  });
}

async function restorePendingAccount(c: any) {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'account_restore');
  if (supabaseRequired) return supabaseRequired;
  const currentRow = await getSupabaseAppUserRowByAnyId(c, userId);
  if (!currentRow) return c.json({ detail: 'User not found.' }, 404);
  const user = supabaseAppUserToLegacyUser(currentRow);
  if (String(user.status || 'active') !== 'deletion_pending') {
    return c.json({ restored: false, user: authUserPayload(user) });
  }
  const metadata = parseJsonObject(currentRow.metadata);
  metadata.status = 'active';
  delete metadata.deletion_requested_at;
  delete metadata.deletion_scheduled_at;
  delete metadata.session_revoked_at;
  await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(publicId(user.id, 120)) }, {
    metadata,
    updated_at: now(),
  });
  await updateSupabaseAuthUser(c, user.supabase_user_id, {
    user_metadata: { captro_user_id: user.id, account_status: 'active' },
    app_metadata: { captro_account_status: 'active' },
  }).catch(() => {});
  const refreshed = await getSupabaseAppUserRowByAnyId(c, user.id);
  const restored = refreshed ? supabaseAppUserToLegacyUser(refreshed) : { ...user, status: 'active', deletion_requested_at: null, deletion_scheduled_at: null };
  runBackgroundTask(c, 'account_restore_audit_failed', async () => {
    await writeAccountDeletionEvent(c, user.id, 'deletion_restored', {});
    await logSecurityEvent(c, 'account_deletion_restored', user.id, {});
  });
  return c.json({ restored: true, user: authUserPayload(restored) });
}

api.get('/account/deletion-status', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'account_deletion_status');
  if (supabaseRequired) return supabaseRequired;
  const row = await getSupabaseAppUserRowByAnyId(c, userId);
  const user = row ? supabaseAppUserToLegacyUser(row) : null;
  return c.json({
    status: user?.status || 'active',
    deletion_pending: user?.status === 'deletion_pending',
    deletion_requested_at: user?.deletion_requested_at || null,
    deletion_scheduled_at: user?.deletion_scheduled_at || null,
  });
});

api.post('/account/delete', authMiddleware, requestAccountDeletion);
api.post('/account/restore', authMiddleware, restorePendingAccount);

// ═══════════════════════════════════════════════════════════════════════════════
// USERS
// ═══════════════════════════════════════════════════════════════════════════════
api.put('/users/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'profile_update');
  if (supabaseRequired) return supabaseRequired;
  const bodyTooLarge = rejectLargeRequest(c, 200_000);
  if (bodyTooLarge) return bodyTooLarge;
  const limited = await enforceRateLimit(c, 'account_update', userId, 60, 60);
  if (limited) return limited;
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

  const currentRow = await getSupabaseAppUserRowByAnyId(c, userId);
  if (!currentRow) return c.json({ detail: 'User not found' }, 404);

  const appUserId = publicId(currentRow.id, 120);
  const profile = parseJsonObject(currentRow.profile);
  const patch: Record<string, unknown> = {};
  let usernameChanged = false;

  if (body.full_name !== undefined) patch.full_name = cleanText(body.full_name, 160);
  if (body.bio !== undefined) patch.bio = cleanMultilineText(body.bio, 500);
  if (body.profile_image !== undefined) patch.avatar_url = safeMediaReference(body.profile_image) || null;
  if (body.cover_image !== undefined) patch.cover_url = safeMediaReference(body.cover_image) || null;
  if (body.city !== undefined) patch.city = cleanText(body.city, 160);
  if (body.is_private !== undefined) patch.is_private = normalizeSqlBoolean(body.is_private) === 1;

  if (body.username !== undefined) {
    const usernameCheck = validateUsernameForAccount(body.username);
    if (!usernameCheck.ok) return c.json({ detail: usernameCheck.detail }, 400);
    const existing = await supabaseAdminQueryRows(c, 'app_users', {
      select: 'id',
      filters: {
        username: postgrestEqFilter(usernameCheck.username),
        id: `neq.${cleanText(appUserId, 120)}`,
      },
      limit: 1,
    });
    if (existing.length) return c.json({ detail: 'Username is not available.' }, 409);
    patch.username = usernameCheck.username;
    usernameChanged = strictUsernameSlug(currentRow.username) !== strictUsernameSlug(usernameCheck.username);
  }

  if (body.language !== undefined) profile.language = normalizeLanguage(body.language);
  if (body.age !== undefined) profile.age = clampNumber(body.age, 13, 120, 0);
  if (body.looking_for !== undefined) profile.looking_for = cleanText(body.looking_for, 120);
  if (body.interests !== undefined) {
    const rawInterests = Array.isArray(body.interests)
      ? body.interests
      : String(body.interests || '').split(',');
    profile.interests = rawInterests
      .map((item: unknown) => cleanText(item, 60))
      .filter(Boolean)
      .slice(0, 24);
  }
  if (body.social_website !== undefined) profile.social_website = safeExternalUrl(body.social_website);
  if (body.social_tiktok !== undefined) profile.social_tiktok = cleanText(body.social_tiktok, 120);
  if (body.social_instagram !== undefined) profile.social_instagram = cleanText(body.social_instagram, 120);
  if (body.profile_background_image !== undefined) {
    profile.profile_background_image = safeMediaReference(body.profile_background_image);
  }

  const profileFields = ['language', 'age', 'looking_for', 'interests', 'social_website', 'social_tiktok', 'social_instagram', 'profile_background_image'];
  const profileChanged = profileFields.some((field) => body[field] !== undefined);
  if (profileChanged) patch.profile = profile;
  if (Object.keys(patch).length === 0) return c.json({ detail: 'Nothing to update' }, 400);
  patch.updated_at = now();

  await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(appUserId) }, patch);
  const refreshedRows = await supabaseAdminQueryRows(c, 'app_users', {
    select: SUPABASE_APP_USER_SELECT,
    filters: { id: postgrestEqFilter(appUserId) },
    limit: 1,
  });
  const user = refreshedRows[0] ? supabaseAppUserToLegacyUser(refreshedRows[0]) : supabaseAppUserToLegacyUser({ ...currentRow, ...patch });
  if (usernameChanged) {
    runBackgroundTask(c, 'username_change_security_log_failed', async () => {
      await logSecurityEvent(c, 'username_changed', appUserId, { previous_username: currentRow.username || '', new_username: user.username || '' });
    });
  }
  runBackgroundTask(c, 'profile_update_abuse_signal_failed', async () => {
    await recordAbuseSignals(c, appUserId, 'profile_update', {
      username: user.username,
      display_name: user.full_name,
      bio: user.bio,
      links: [user.social_website, user.social_tiktok, user.social_instagram].filter(Boolean),
    });
  });
  runBackgroundTask(c, 'supabase_profile_metadata_sync_failed', async () => {
    await syncSupabaseAuthMetadataForUser(c, user);
  });
  return c.json(safeUserPayload(user, { includePrivate: true }));
});

api.delete('/users/me', authMiddleware, async (c) => {
  return c.json({
    detail: 'Use POST /api/account/delete with DELETE confirmation and recent re-authentication.',
    code: 'ACCOUNT_DELETE_REAUTH_REQUIRED',
  }, 405);
});

api.put('/users/me/email', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'account_email_update');
    if (supabaseRequired) return supabaseRequired;
    const bodyTooLarge = rejectLargeRequest(c, 60_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'account_email', userId, 10, 600);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const email = normalizeOptionalEmail(body.email || body.new_email);

    if (!email) return c.json({ detail: 'Enter a valid email address.' }, 400);

    const currentRow = await getSupabaseAppUserRowByAnyId(c, userId);
    if (!currentRow) return c.json({ detail: 'User not found' }, 404);
    const appUserId = publicId(currentRow.id, 120);
    const owner = await supabaseAdminQueryRows(c, 'app_users', {
      select: 'id',
      filters: {
        email: postgrestEqFilter(email),
        id: `neq.${cleanText(appUserId, 120)}`,
      },
      limit: 1,
    });
    if (owner.length) return c.json({ detail: 'That email is already used by another account.' }, 409);

    let supabaseUserId = isUuidText(currentRow.supabase_user_id);
    if (supabaseUserId) {
      await updateSupabaseAuthUser(c, supabaseUserId, { email });
    } else {
      const user = supabaseAppUserToLegacyUser(currentRow);
      const result = await createOrFindSupabaseAuthUser(c, {
        email,
        username: publicUsernameFor(user),
        fullName: user.full_name,
        profileImage: user.profile_image,
        provider: 'email',
        appUserId,
      });
      supabaseUserId = isUuidText(result.user?.id);
    }

    await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(appUserId) }, {
      email,
      email_verified: false,
      ...(supabaseUserId ? { supabase_user_id: supabaseUserId } : {}),
      updated_at: now(),
    });
    const refreshedRows = await supabaseAdminQueryRows(c, 'app_users', {
      select: SUPABASE_APP_USER_SELECT,
      filters: { id: postgrestEqFilter(appUserId) },
      limit: 1,
    });
    const user = refreshedRows[0] ? supabaseAppUserToLegacyUser(refreshedRows[0]) : supabaseAppUserToLegacyUser({ ...currentRow, email, supabase_user_id: supabaseUserId });
    runBackgroundTask(c, 'email_update_security_log_failed', async () => {
      await logSecurityEvent(c, 'email_updated', appUserId, {});
    });
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
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'account_password_update');
    if (supabaseRequired) return supabaseRequired;
    const bodyTooLarge = rejectLargeRequest(c, 60_000);
    if (bodyTooLarge) return bodyTooLarge;
    const limited = await enforceRateLimit(c, 'account_password', userId, 8, 600);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const newPassword = String(body.new_password || body.password || '');

    if (!newPassword) return c.json({ detail: 'New password is required.' }, 400);
    if (newPassword.length < 8) return c.json({ detail: 'New password must be at least 8 characters.' }, 400);

    const currentRow = await getSupabaseAppUserRowByAnyId(c, userId);
    if (!currentRow) return c.json({ detail: 'User not found' }, 404);
    const appUserId = publicId(currentRow.id, 120);
    let supabaseUserId = isUuidText(currentRow.supabase_user_id);

    if (!supabaseUserId) {
      const user = supabaseAppUserToLegacyUser(currentRow);
      const email = normalizeOptionalEmail(user.email);
      if (!email || isInternalOAuthEmail(email)) {
        return c.json({ detail: 'Add a real email address before setting a password.', code: 'EMAIL_REQUIRED' }, 400);
      }
      const result = await createOrFindSupabaseAuthUser(c, {
        email,
        password: newPassword,
        username: publicUsernameFor(user),
        fullName: user.full_name,
        profileImage: user.profile_image,
        provider: 'email',
        appUserId,
      });
      supabaseUserId = isUuidText(result.user?.id);
      if (supabaseUserId) {
        await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(appUserId) }, {
          supabase_user_id: supabaseUserId,
          updated_at: now(),
        });
      }
    }

    if (!supabaseUserId) return c.json({ detail: 'Could not update the login password right now.' }, 503);
    await updateSupabaseAuthUser(c, supabaseUserId, { password: newPassword });
    runBackgroundTask(c, 'password_update_security_log_failed', async () => {
      await logSecurityEvent(c, 'password_updated', appUserId, {});
    });
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
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'account_phone_start');
    if (supabaseRequired) return supabaseRequired;
    const bodyTooLarge = rejectLargeRequest(c, 40_000);
    if (bodyTooLarge) return bodyTooLarge;
    const body: any = await c.req.json().catch(() => ({}));
    const normalizedPhone = normalizePhone(body.phone);
    const limited = await enforceRateLimit(c, 'account_phone_start', `${userId}:${normalizedPhone || clientIp(c)}`, 5, 600);
    if (limited) return limited;

    const ownerId = await supabasePhoneOwnerId(c, normalizedPhone);
    if (ownerId && ownerId !== userId) return c.json({ detail: 'That phone number is already verified on another account.' }, 409);

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

    await supabaseExpireAccountVerificationTokens(c, userId, 'phone', normalizedPhone).catch(() => undefined);
    await supabaseCreateAccountVerificationToken(c, {
      userId,
      tokenType: 'phone',
      target: normalizedPhone,
      tokenHash: codeHash,
      expiresAt,
    });

    const delivery = await sendLegacyPhoneCode(c, normalizedPhone, code);
    if (delivery === 'development') {
      return c.json({ detail: 'Phone verification is not configured yet.', code: 'PHONE_PROVIDER_CONFIG' }, 503);
    }
    const payload: any = {
      detail: 'We sent a verification code to your phone.',
      delivery,
    };

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
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'account_phone_verify');
    if (supabaseRequired) return supabaseRequired;
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

    const currentSupabaseRow = await getSupabaseAppUserRowByAnyId(c, userId);
    if (!currentSupabaseRow) return c.json({ detail: 'User not found' }, 404);
    const ownerId = await supabasePhoneOwnerId(c, normalizedPhone);
    if (ownerId && ownerId !== publicId(currentSupabaseRow.id, 120)) {
      return c.json({ detail: 'That phone number is already verified on another account.' }, 409);
    }

    if (getTwilioVerifyConfig(c)) {
      const verified = await checkTwilioVerification(c, normalizedPhone, normalizedCode);
      if (!verified) return c.json({ detail: 'Invalid or expired verification code.' }, 401);
    } else {
      const phoneCode = await supabaseLatestAccountVerificationToken(c, 'phone', normalizedPhone);
      if (!phoneCode) return c.json({ detail: 'No active code for this phone number.' }, 401);
      if (publicId(phoneCode.user_id, 120) !== publicId(currentSupabaseRow?.id, 120)) return c.json({ detail: 'Invalid verification code.' }, 401);
      if ((Number(phoneCode.attempts || 0)) >= 5) return c.json({ detail: 'Too many attempts. Request a new code.' }, 429);
      if (Date.parse(phoneCode.expires_at) < Date.now()) return c.json({ detail: 'Code expired. Request a new code.' }, 401);

      const jwtSecret = getJwtSecret(c);
      const expectedHash = await sha256Hex(`${normalizedPhone}:${normalizedCode}:${jwtSecret}`);
      if (expectedHash !== phoneCode.token_hash) {
        await supabaseAdminPatchRows(c, 'app_account_verification_tokens', { id: postgrestEqFilter(cleanText(phoneCode.id, 120)) }, {
          attempts: Number(phoneCode.attempts || 0) + 1,
          updated_at: now(),
        });
        return c.json({ detail: 'Invalid verification code.' }, 401);
      }

      await supabaseAdminPatchRows(c, 'app_account_verification_tokens', { id: postgrestEqFilter(cleanText(phoneCode.id, 120)) }, {
        used_at: now(),
        updated_at: now(),
      });
    }

    const appUserId = publicId(currentSupabaseRow.id, 120);
    await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(appUserId) }, {
      phone: normalizedPhone,
      phone_verified: true,
      updated_at: now(),
    });
    const refreshed = await getSupabaseAppUserRowByAnyId(c, appUserId);
    const user = supabaseAppUserToLegacyUser(refreshed || { ...currentSupabaseRow, phone: normalizedPhone, phone_verified: true });
    runBackgroundTask(c, 'supabase_phone_auth_metadata_update_failed', async () => {
      const supabaseUserId = isUuidText(currentSupabaseRow.supabase_user_id);
      if (supabaseUserId) {
        await updateSupabaseAuthUser(c, supabaseUserId, {
          phone: normalizedPhone,
          user_metadata: supabaseProfileMetadata({
            appUserId,
            username: publicUsernameFor(user),
            fullName: user.full_name,
            profileImage: user.profile_image,
            language: user.language,
            phone: normalizedPhone,
          }),
        });
      } else {
        const result = await createOrFindSupabaseAuthUser(c, {
          phone: normalizedPhone,
          username: publicUsernameFor(user),
          fullName: user.full_name,
          profileImage: user.profile_image,
          provider: 'phone',
          appUserId,
        });
        if (result.user?.id) await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(appUserId) }, { supabase_user_id: result.user.id, updated_at: now() });
      }
    });
    return c.json(authUserPayload(user));
  } catch (error: any) {
    const code = String(error?.message || '');
    if (code === 'PHONE_INVALID') return c.json({ detail: 'Enter a valid phone number with country code.' }, 400);
    if (code === 'JWT_SECRET_MISSING') return c.json({ detail: 'Auth service is not configured.' }, 503);
    if (code.startsWith('PHONE_VERIFY_CHECK_FAILED')) return c.json({ detail: 'Could not check verification code. Try again.', code }, 502);
    return c.json({ detail: 'Could not verify phone number.' }, 500);
  }
});

api.post('/users/me/email/link/start', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'account_email_link_start');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'email_verify_link', userId, 8, 60);
  if (limited) return limited;

  try {
    const body: any = await c.req.json().catch(() => ({}));
    const currentSupabaseRow = await getSupabaseAppUserRowByAnyId(c, userId);
    const currentUser: any = currentSupabaseRow ? supabaseAppUserToLegacyUser(currentSupabaseRow) : null;
    const accountEmail = normalizeOptionalEmail(currentUser?.email);
    const requestedEmail = normalizeOptionalEmail(body.email);
    if (!accountEmail) {
      return c.json({ detail: 'Add a real email address before verification.', code: 'EMAIL_MISSING' }, 400);
    }
    if (requestedEmail && requestedEmail !== accountEmail) {
      return c.json({ detail: 'Verify the email address already attached to this account.', code: 'EMAIL_MISMATCH' }, 400);
    }
    if (accountEmailVerified(currentUser)) {
      return c.json({ detail: 'Email is already verified.', verified: true });
    }

    const token = randomUrlToken(32);
    const tokenHash = await sha256Hex(`${token}:${c.env.JWT_SECRET}`);
    const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString();
    await supabaseExpireAccountVerificationTokens(c, publicId(currentUser.id, 120), 'email_link', accountEmail).catch(() => undefined);
    await supabaseCreateAccountVerificationToken(c, {
      userId: publicId(currentUser.id, 120),
      tokenType: 'email_link',
      target: accountEmail,
      tokenHash,
      expiresAt,
    });

    const sent = await sendEmailVerificationLink(c, accountEmail, emailVerificationLink(c, token));
    if (!sent) {
      return c.json({
        detail: 'Email verification links are not configured yet.',
        code: 'EMAIL_LINK_PROVIDER_CONFIG',
      }, 503);
    }

    return c.json({
      detail: 'We sent a verification link to your email.',
      delivery: 'email_link',
      expires_at: expiresAt,
    });
  } catch (error: any) {
    const code = getErrorCode(error);
    console.error(JSON.stringify({ event: 'email_verification_link_start_failed', error: code.slice(0, 180) }));
    if (code.startsWith('EMAIL_LINK_SEND_FAILED')) {
      return c.json({ detail: 'Could not send verification link. Try again in a moment.', code: 'EMAIL_LINK_SEND_FAILED' }, 502);
    }
    return c.json({ detail: 'Could not start email verification. Please try again in a moment.', code: 'EMAIL_LINK_START_FAILED' }, 500);
  }
});

api.get('/users/me/email/verify-link', async (c) => {
  const token = cleanText(c.req.query('token'), 512);
  const fail = (message = 'This email verification link is invalid or expired.') => c.html(
    `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Captro Email Verification</title></head><body style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f6f4f1;color:#111"><main style="min-height:100vh;display:grid;place-items:center;padding:24px"><section style="max-width:520px;background:#fff;border-radius:28px;padding:28px;box-shadow:0 20px 60px rgba(0,0,0,.08)"><h1 style="margin:0 0 10px;font-size:26px">Email not verified</h1><p style="font-size:16px;line-height:1.55;color:#555">${message}</p></section></main></body></html>`,
    400
  );
  if (!token || token.length < 24) return fail();

  const tokenHash = await sha256Hex(`${token}:${c.env.JWT_SECRET}`);
  if (supabasePrimaryConfigured(c)) {
    const row = await supabaseAccountVerificationTokenByHash(c, 'email_link', tokenHash).catch(() => null);
    if (!row || row.used_at) return fail();
    if (!row.expires_at || Date.parse(row.expires_at) < Date.now()) {
      if (row?.id) await supabaseAdminPatchRows(c, 'app_account_verification_tokens', { id: postgrestEqFilter(cleanText(row.id, 120)) }, { used_at: now(), updated_at: now() }).catch(() => undefined);
      return fail();
    }
    const appUser = await getSupabaseAppUserRowByAnyId(c, row.user_id);
    const accountEmail = normalizeOptionalEmail(appUser?.email);
    const tokenEmail = normalizeOptionalEmail(row.target);
    if (!appUser || !accountEmail || accountEmail !== tokenEmail) return fail();

    await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(publicId(appUser.id, 120)) }, {
      email_verified: true,
      updated_at: now(),
    });
    await supabaseAdminPatchRows(c, 'app_account_verification_tokens', { id: postgrestEqFilter(cleanText(row.id, 120)) }, {
      used_at: now(),
      updated_at: now(),
    });
    runBackgroundTask(c, 'supabase_email_auth_metadata_update_failed', async () => {
      const supabaseUserId = isUuidText(appUser.supabase_user_id);
      if (supabaseUserId) {
        await updateSupabaseAuthUser(c, supabaseUserId, {
          user_metadata: { email_verified: true },
        });
      }
    });
    return c.html(
      `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Captro Email Verified</title></head><body style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f6f4f1;color:#111"><main style="min-height:100vh;display:grid;place-items:center;padding:24px"><section style="max-width:520px;background:#fff;border-radius:28px;padding:28px;box-shadow:0 20px 60px rgba(0,0,0,.08)"><h1 style="margin:0 0 10px;font-size:26px">Email verified</h1><p style="font-size:16px;line-height:1.55;color:#555">Your Captro email is verified. You can return to the app.</p></section></main></body></html>`
    );
  }
  return fail('Email verification is temporarily unavailable. Please try again later.');
});

api.post('/users/me/email/start', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'account_email_start');
    if (supabaseRequired) return supabaseRequired;
    const bodyTooLarge = rejectLargeRequest(c, 20_000);
    if (bodyTooLarge) return bodyTooLarge;
    const body: any = await c.req.json().catch(() => ({}));

    const currentSupabaseRow = await getSupabaseAppUserRowByAnyId(c, userId);
    const currentUser: any = currentSupabaseRow ? supabaseAppUserToLegacyUser(currentSupabaseRow) : null;
    const accountEmail = normalizeOptionalEmail(currentUser?.email);
    const requestedEmail = normalizeOptionalEmail(body.email || accountEmail);
    if (!accountEmail || isInternalOAuthEmail(accountEmail)) {
      return c.json({ detail: 'Add a real email address before verification.', code: 'EMAIL_MISSING' }, 400);
    }
    if (requestedEmail !== accountEmail) {
      return c.json({ detail: 'Verify the email address already attached to this account.', code: 'EMAIL_MISMATCH' }, 400);
    }
    if (accountEmailVerified(currentUser)) {
      return c.json({ detail: 'Email is already verified.', delivery: 'already_verified' });
    }

    const limited = await enforceRateLimit(c, 'account_email_start', `${userId}:${accountEmail || clientIp(c)}`, 5, 600);
    if (limited) return limited;
    if (!getTwilioVerifyConfig(c)) {
      return c.json({ detail: 'Email verification is not configured yet.', code: 'EMAIL_PROVIDER_CONFIG' }, 503);
    }

    await startTwilioChannelVerification(c, accountEmail, 'email');
    return c.json({
      detail: 'We sent a verification code to your email.',
      delivery: 'twilio_verify',
    });
  } catch (error: any) {
    const code = String(error?.message || '');
    if (code.startsWith('PHONE_VERIFY_START_FAILED')) return twilioVerifyStartErrorResponse(c, code, 'email');
    console.error(JSON.stringify({ event: 'email_verification_start_failed', error: code.slice(0, 180) }));
    return c.json({ detail: 'Could not start email verification. Please try again in a moment.', code: 'EMAIL_START_FAILED' }, 500);
  }
});

api.post('/users/me/email/verify', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'account_email_verify');
    if (supabaseRequired) return supabaseRequired;
    const bodyTooLarge = rejectLargeRequest(c, 20_000);
    if (bodyTooLarge) return bodyTooLarge;
    const body: any = await c.req.json().catch(() => ({}));

    const currentSupabaseRow = await getSupabaseAppUserRowByAnyId(c, userId);
    const currentUser: any = currentSupabaseRow ? supabaseAppUserToLegacyUser(currentSupabaseRow) : null;
    const accountEmail = normalizeOptionalEmail(currentUser?.email);
    const requestedEmail = normalizeOptionalEmail(body.email || accountEmail);
    if (!accountEmail || isInternalOAuthEmail(accountEmail)) {
      return c.json({ detail: 'Add a real email address before verification.', code: 'EMAIL_MISSING' }, 400);
    }
    if (requestedEmail !== accountEmail) {
      return c.json({ detail: 'Verify the email address already attached to this account.', code: 'EMAIL_MISMATCH' }, 400);
    }
    const normalizedCode = String(body.code || '').replace(/\D/g, '');
    if (normalizedCode.length !== 6) {
      return c.json({ detail: 'Enter the 6-digit verification code.' }, 400);
    }

    const limited = await enforceRateLimit(c, 'account_email_verify', `${userId}:${accountEmail || clientIp(c)}`, 12, 600);
    if (limited) return limited;
    if (!getTwilioVerifyConfig(c)) {
      return c.json({ detail: 'Email verification is not configured yet.', code: 'EMAIL_PROVIDER_CONFIG' }, 503);
    }

    const verified = await checkTwilioChannelVerification(c, accountEmail, normalizedCode);
    if (!verified) return c.json({ detail: 'Invalid or expired verification code.' }, 401);

    const appUserId = publicId(currentUser.id, 120);
    await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(appUserId) }, {
      email_verified: true,
      updated_at: now(),
    });
    const refreshed = await getSupabaseAppUserRowByAnyId(c, appUserId);
    const user = supabaseAppUserToLegacyUser(refreshed || { ...currentSupabaseRow, email_verified: true });
    runBackgroundTask(c, 'supabase_email_verify_metadata_sync_failed', async () => {
      const supabaseUserId = isUuidText(currentSupabaseRow?.supabase_user_id);
      if (supabaseUserId) await updateSupabaseAuthUser(c, supabaseUserId, { user_metadata: { email_verified: true } });
    });
    return c.json(authUserPayload(user));
  } catch (error: any) {
    const code = String(error?.message || '');
    if (code.startsWith('PHONE_VERIFY_CHECK_FAILED')) return c.json({ detail: 'Could not check verification code. Try again.', code: 'EMAIL_VERIFY_CHECK_FAILED' }, 502);
    return c.json({ detail: 'Could not verify email address.' }, 500);
  }
});

api.put('/users/me/username', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'username_claim');
    if (supabaseRequired) return supabaseRequired;
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
    const currentRow = await getSupabaseAppUserRowByAnyId(c, userId);
    if (!currentRow) return c.json({ detail: 'User not found' }, 404);
    const appUserId = publicId(currentRow.id, 120);
    const existing = await supabaseAdminQueryRows(c, 'app_users', {
      select: 'id',
      filters: { username: postgrestEqFilter(usernameCheck.username) },
      limit: 2,
    });
    if (existing.some((row) => publicId(row.id, 120) !== appUserId)) {
      return c.json({
        available: false,
        username: usernameCheck.username,
        code: 'taken',
        reason: 'Username is already taken.',
      }, 409);
    }

    await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(appUserId) }, {
      username: usernameCheck.username,
      updated_at: now(),
    });
    const refreshed = await getSupabaseAppUserRowByAnyId(c, appUserId);
    const user = supabaseAppUserToLegacyUser(refreshed || { ...currentRow, username: usernameCheck.username });
    runBackgroundTask(c, 'username_security_log_failed', async () => {
      await recordAbuseSignals(c, appUserId, 'username_claim', { username: usernameCheck.username });
      await logSecurityEvent(c, 'username_changed', appUserId, { previous_username: currentRow?.username || '', new_username: usernameCheck.username });
      await syncSupabaseAuthMetadataForUser(c, user);
    });
    return c.json(authUserPayload(user));
  } catch (error: any) {
    console.error('Username claim failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not save username.' }, 500);
  }
});

api.get('/users/search/:query', authMiddleware, async (c) => {
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'user_search');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'user_search', getUserId(c), 120, 60);
  if (limited) return limited;
  const q = cleanText(c.req.param('query'), 80);
  if (q.length < 2) return c.json([]);
  const search = q.replace(/[%*,()]/g, '').slice(0, 80);
  if (search.length < 2) return c.json([]);
  const rows = await supabaseAdminQueryRows(c, 'app_users', {
    select: SUPABASE_APP_USER_SELECT,
    filters: { or: `(username.ilike.*${search}*,full_name.ilike.*${search}*)` },
    limit: 20,
  });
  return c.json(rows
    .map(supabaseAppUserToLegacyUser)
    .filter((user) => String(user.status || 'active') === 'active')
    .map((user) => safeUserPayload(user)));
});

// Exact username check (no auth required for registration flow)
api.get('/users/check-username/:username', async (c) => {
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'username_check');
  if (supabaseRequired) return supabaseRequired;
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
  const user: any = (await supabaseAdminQueryRows(c, 'app_users', {
    select: 'id',
    filters: { username: postgrestEqFilter(username) },
    limit: 1,
  }))[0];
  return c.json({
    available: !user,
    username,
    code: user ? 'taken' : 'available',
    reason: user ? 'Username is already taken.' : 'Username available',
  });
});

api.get('/users/:userId', authMiddleware, async (c) => {
  const viewerId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'profile_read');
  if (supabaseRequired) return supabaseRequired;
  const targetUserId = c.req.param('userId');
  const result = await supabasePublicUserPayload(c, viewerId, targetUserId);
  return c.json(result.body, result.status);
});

api.post('/users/:userId/follow', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const targetId = c.req.param('userId');
  if (userId === targetId) return c.json({ detail: 'Cannot follow yourself' }, 400);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'follow');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'follow', userId, 120, 60);
  if (limited) return limited;
  const body: any = await c.req.json().catch(() => ({}));
  const requested = optionalBoolean(body.following ?? body.followed ?? body.value);
  const result = await supabaseSetFollowState(c, userId, targetId, requested);
  return c.json(result.body, result.status);
});

api.post('/users/:userId/block', authMiddleware, async (c) => {
  const blockerId = getUserId(c);
  const blockedId = c.req.param('userId');
  if (blockerId === blockedId) return c.json({ detail: 'You cannot block yourself.' }, 400);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'block_user');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'block_user', blockerId, 40, 60);
  if (limited) return limited;
  const result = await supabaseBlockUser(c, blockerId, blockedId);
  return c.json(result.body, result.status);
});

api.delete('/users/:userId/block', authMiddleware, async (c) => {
  const blockerId = getUserId(c);
  const blockedId = c.req.param('userId');
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'unblock_user');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'unblock_user', blockerId, 40, 60);
  if (limited) return limited;
  const result = await supabaseUnblockUser(c, blockerId, blockedId);
  return c.json(result.body, result.status);
});

api.get('/blocks', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'blocks_read');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'blocks_read', userId, 60, 60);
  if (limited) return limited;
  return c.json(await supabaseListBlocks(c, userId));
});

// ═══════════════════════════════════════════════════════════════════════════════
// POSTS (with Check-In support)
// ═══════════════════════════════════════════════════════════════════════════════
async function supabaseAudiusHiddenTrackIds(c: any, trackIds: string[] = []): Promise<Set<string>> {
  const filters: Record<string, string> = { provider: postgrestEqFilter('audius') };
  const cleanIds = Array.from(new Set(trackIds.map((id) => cleanText(id, 80)).filter(Boolean)));
  if (cleanIds.length) filters.track_id = postgrestInFilter(cleanIds);
  const rows = await supabaseAdminQueryRows(c, 'app_hidden_sounds', {
    select: 'track_id',
    filters,
    limit: cleanIds.length || 1000,
  });
  return new Set(rows.map((row) => cleanText(row?.track_id, 80)).filter(Boolean));
}

async function supabaseAudiusTrackIsHidden(c: any, trackId: string): Promise<boolean> {
  if (!trackId) return false;
  const hidden = await supabaseAudiusHiddenTrackIds(c, [trackId]);
  return hidden.has(trackId);
}

function audiusFavoriteTrackPayload(row: any) {
  const trackId = String(row?.track_id || '');
  return {
    id: trackId,
    track_id: trackId,
    title: String(row?.title || 'Untitled track'),
    artist: String(row?.artist || 'Audius artist'),
    artist_id: String(row?.artist_id || ''),
    artist_handle: String(row?.artist_handle || ''),
    artist_profile_image: String(row?.artist_profile_image || ''),
    artwork_url: String(row?.artwork_url || ''),
    duration: Number(row?.duration || 0),
    genre: String(row?.genre || ''),
    play_count: Number(row?.play_count || 0),
    favorite_count: Number(row?.favorite_count || 0),
  };
}

// Music proxy: Audius powers the post creation sound picker without exposing provider internals.
api.get('/music/audius/trending', async (c) => {
  try {
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'music_audius_trending');
    if (supabaseRequired) return supabaseRequired;
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
    const hiddenIds = await supabaseAudiusHiddenTrackIds(c);
    return c.json({ tracks: (tracks as any[]).filter((track) => !hiddenIds.has(String(track.track_id))) });
  } catch (error: any) {
    console.log('Audius trending failed:', error?.message || error);
    return c.json({ detail: 'Music is temporarily unavailable.', tracks: [] }, 503);
  }
});

api.get('/music/audius/search', async (c) => {
  try {
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'music_audius_search');
    if (supabaseRequired) return supabaseRequired;
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
    const hiddenIds = await supabaseAudiusHiddenTrackIds(c);
    return c.json({ tracks: (tracks as any[]).filter((track) => !hiddenIds.has(String(track.track_id))) });
  } catch (error: any) {
    console.log('Audius search failed:', error?.message || error);
    return c.json({ detail: 'Music search is temporarily unavailable.', tracks: [] }, 503);
  }
});

api.get('/music/audius/stream/:trackId', async (c) => {
  try {
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'music_audius_stream');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'audius_stream_lookup', (await getOptionalUserId(c)) || clientIp(c), 180, 60);
    if (limited) return limited;
    const trackId = cleanText(c.req.param('trackId'), 80);
    if (!trackId) return c.json({ detail: 'Track id is required.' }, 400);
    const hidden = await supabaseAudiusTrackIsHidden(c, trackId);
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
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'music_audius_favorites_read');
    if (supabaseRequired) return supabaseRequired;
    const userId = getUserId(c);
    const rows = await supabaseAdminQueryRows(c, 'app_favorite_sounds', {
      select: 'track_id,title,artist,artist_id,artist_handle,artist_profile_image,artwork_url,duration,genre,play_count,favorite_count',
      filters: { user_id: postgrestEqFilter(userId), provider: postgrestEqFilter('audius') },
      order: 'created_at.desc',
      limit: 100,
    });
    const hiddenIds = await supabaseAudiusHiddenTrackIds(c, rows.map((row) => String(row.track_id || '')));
    return c.json({ tracks: rows.map(audiusFavoriteTrackPayload).filter((track) => track.id && !hiddenIds.has(track.id)) });
  } catch (error: any) {
    console.log('Audius favorites failed:', error?.message || error);
    return c.json({ detail: 'Could not load favorite sounds.', tracks: [] }, 500);
  }
});

api.post('/music/audius/favorites', authMiddleware, async (c) => {
  try {
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'music_audius_favorite_write');
    if (supabaseRequired) return supabaseRequired;
    const userId = getUserId(c);
    const body: any = await c.req.json().catch(() => ({}));
    const trackId = cleanText(body.track_id || body.id || body.audio_track_id, 80);
    if (!trackId) return c.json({ detail: 'Track id is required.' }, 400);

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

    if (await supabaseAudiusTrackIsHidden(c, trackId)) return c.json({ detail: 'This sound is unavailable.' }, 400);
    await supabaseAdminUpsert(c, 'app_favorite_sounds', [{
      id: uuid(),
      user_id: userId,
      provider: 'audius',
      track_id: trackId,
      title,
      artist,
      artist_id: artistId,
      artist_handle: artistHandle,
      artist_profile_image: artistProfileImage,
      artwork_url: artworkUrl,
      duration,
      genre,
      play_count: playCount,
      favorite_count: favoriteCount,
      metadata: { source: 'worker_audius_favorite' },
      created_at: ts,
      updated_at: ts,
    }], 'user_id,provider,track_id');

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
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'music_audius_favorite_delete');
    if (supabaseRequired) return supabaseRequired;
    const userId = getUserId(c);
    const trackId = cleanText(c.req.param('trackId'), 80);
    if (!trackId) return c.json({ detail: 'Track id is required.' }, 400);
    await supabaseAdminDeleteRows(c, 'app_favorite_sounds', {
      user_id: postgrestEqFilter(userId),
      provider: postgrestEqFilter('audius'),
      track_id: postgrestEqFilter(trackId),
    });
    return c.json({ favorite: false, track_id: trackId });
  } catch (error: any) {
    console.log('Audius favorite remove failed:', error?.message || error);
    return c.json({ detail: 'Could not remove this sound.' }, 500);
  }
});

api.post('/ai/post-assist', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'post_ai_assist', userId, 45, 60);
  if (limited) return limited;
  const tooLarge = rejectLargeRequest(c, 24_000);
  if (tooLarge) return tooLarge;
  const body = await c.req.json().catch(() => ({}));
  const unknown = rejectUnknownFields(c, body, [
    'title', 'headline', 'caption', 'content', 'media_type', 'mediaType', 'post_type', 'postType',
    'hashtags', 'tags', 'location', 'place_name', 'placeName',
    'apple_vision_labels', 'appleVisionLabels',
    'apple_vision_category_guess', 'appleVisionCategoryGuess',
    'apple_vision_confidence', 'appleVisionConfidence',
  ]);
  if (unknown) return unknown;

  const title = cleanText(body.title || body.headline, 120);
  const caption = cleanMultilineText(body.caption || body.content, 900);
  const hashtags = sanitizeAutoCategoryTags([...(parseJsonArray(body.hashtags)), ...(parseJsonArray(body.tags))]);
  const input: AutoCategoryInput & { title?: string } = {
    title,
    caption: [title, caption].filter(Boolean).join('\n\n'),
    mediaType: cleanText(body.media_type || body.mediaType, 40),
    postType: cleanText(body.post_type || body.postType, 60),
    hashtags,
    location: cleanText(body.location, 140),
    placeName: cleanText(body.place_name || body.placeName, 140),
    appleLabels: sanitizeAutoCategoryLabels(body.apple_vision_labels || body.appleVisionLabels),
    appleCategoryGuess: body.apple_vision_category_guess || body.appleVisionCategoryGuess,
    appleConfidence: clampFloat(body.apple_vision_confidence ?? body.appleVisionConfidence, 0, 1, 0),
  };
  const deterministicCategory = autoCategoryEngine(input);
  const fallback = fallbackPostAssist(input, deterministicCategory);

  try {
    const result = await generatePostAssistWithWorkersAi(c.env, input, fallback);
    return c.json({
      ...result,
      category: result.primary_category,
      ai_available: !!c.env.AI,
    });
  } catch (error: any) {
    console.warn(JSON.stringify({
      event: 'post_assist_ai_failed',
      request_id: c.get?.('requestId') || '',
      code: getErrorCode(error).slice(0, 160),
    }));
    return c.json({
      ...fallback,
      category: fallback.primary_category,
      ai_available: !!c.env.AI,
    });
  }
});

api.post('/posts', authMiddleware, async (c) => {
  const phoneGate = await requirePhoneVerified(c, 'create posts');
  if (phoneGate) return phoneGate;
  const bodyTooLarge = rejectLargeRequest(c, 1_500_000);
  if (bodyTooLarge) return bodyTooLarge;
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'post_create');
  if (supabaseRequired) return supabaseRequired;
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'post_create', userId, 30, 60);
  if (limited) return limited;
  const restricted = await enforceUserRestriction(c, userId, 'posting');
  if (restricted) return restricted;
  const b = await c.req.json().catch(() => ({}));
  const supabaseAuthorRow = await getSupabaseAppUserRowByAnyId(c, userId);
  const user: any = supabaseAuthorRow ? supabaseAppUserToLegacyUser(supabaseAuthorRow) : null;
  if (!user) return c.json({ detail: 'User not found.' }, 404);
  const clientRequestId = getClientRequestId(c, b);
  if (clientRequestId) {
    const existing = await supabaseExistingPostByClientRequest(c, userId, clientRequestId, supabaseAuthorRow);
    if (existing) return c.json({ ...postPayload(existing, [], c.env), idempotent_replay: true });
  }
  const id = uuid();
  let postType = cleanText(b.post_type || b.postType || b.type || b.category || 'general', 50).toLowerCase() || 'general';
  if (postType === 'media') postType = 'general';
  if (postType === 'note') {
    return c.json({ detail: 'Notes are no longer supported.', code: 'NOTES_RETIRED' }, 410);
  }
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
  let postTitle = cleanText(b.title || b.headline, 180);
  let postContent = cleanMultilineText(b.content || b.text, 5000);
  let imageUrls = sanitizeMediaReferences(b.images, b.image);
  let primaryImage = safeMediaReference(b.image) || imageUrls[0] || null;
  let mediaTypes = sanitizeMediaTypes(b.media_types, imageUrls.length || (primaryImage ? 1 : 0));
  const requestedPostType = String(b.post_type || b.postType || b.media_type || b.mediaType || '').toLowerCase();
  const hasVideoMedia = requestedPostType.includes('video') || mediaTypes.includes('video') || imageUrls.some(isVideoMediaUrl);
  if (hasVideoMedia) {
    return c.json({
      detail: 'Feed posts support photos only. Share videos to Stories instead.',
      code: 'FEED_POSTS_PHOTO_ONLY',
    }, 400);
  }
  const mediaAssetIds = parseMediaAssetIds(b);
  const mediaApproval = await approvedMediaAssetsForPost(c, userId, mediaAssetIds, imageUrls);
  if (!mediaApproval.ok) {
    return c.json({ detail: mediaApproval.detail, code: mediaApproval.code }, mediaApproval.status as any);
  }
  if (mediaApproval.assets.some((asset: any) => normalizeMediaAssetType(asset.media_type) === 'video')) {
    return c.json({
      detail: 'Feed posts support photos only. Share videos to Stories instead.',
      code: 'FEED_POSTS_PHOTO_ONLY',
    }, 400);
  }
  const approvedMediaAssetIds = Array.from(new Set([
    ...mediaAssetIds,
    ...mediaApproval.assets.map((asset: any) => publicId(asset?.id, 160)).filter(Boolean),
  ]));
  const moderatedImageUrls = mediaApproval.assets
    .map((asset: any) => safeMediaReference(asset.public_url) || mediaAssetPublicUrl(c.env, asset))
    .filter(Boolean);
  if (moderatedImageUrls.length) {
    imageUrls = moderatedImageUrls;
    primaryImage = imageUrls[0] || null;
    mediaTypes = sanitizeMediaTypes(b.media_types, imageUrls.length || (primaryImage ? 1 : 0));
  }
  const explicitTags = sanitizeAutoCategoryTags([...(parseJsonArray(b.tags)), ...(parseJsonArray(b.hashtags))]);
  const mediaTypeHint = mediaTypes.includes('video') ? 'video' : 'image';
  const categoryLocationSignals = [
    location,
    displayLocationLabel,
    displayCity,
    displayRegion,
    displayCountry,
    placeCategory,
  ].filter(Boolean).join(' ');
  let autoCategory = autoCategoryFromBody(b, {
    caption: [postTitle, postContent].filter(Boolean).join('\n\n'),
    mediaType: mediaTypeHint,
    postType,
    hashtags: explicitTags,
    location: categoryLocationSignals || location,
    placeType: placeCategory,
    placeName: [placeName, placeCategory].filter(Boolean).join(' ') || null,
  });
  const placeLat = b.place_lat == null ? null : clampFloat(b.place_lat, -90, 90, 0);
  const placeLng = b.place_lng == null ? null : clampFloat(b.place_lng, -180, 180, 0);
  const backupIds = Array.from(new Set([
    ...parseJsonArray(b.media_backup_ids).map(String).filter(Boolean),
    ...mediaBackupIdsFromReferences([primaryImage, ...imageUrls]),
  ]));
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
    const hidden = await supabaseAudiusTrackIsHidden(c, audioTrackId);
    if (hidden) return c.json({ detail: 'This sound is unavailable.' }, 400);
  }

  const createdAt = now();
  const supabaseInput = {
    id,
    userId,
    authUserId: supabaseAuthorRow?.supabase_user_id || userId,
    postTitle,
    postContent,
    primaryImage,
    imageUrls,
    mediaTypes,
    backupIds,
    mediaDimensions,
    location,
    displayCity,
    displayRegion,
    displayCountry,
    displayLocationLabel,
    displayLocationSource,
    displayLocationVisibility,
    postType,
    placeProvider,
    placeProviderId,
    placeName,
    placeFormattedAddress,
    placeCategory,
    placeCity,
    placeRegion,
    placeCountry,
    placeLat,
    placeLng,
    isCheckin,
    visibility,
    mediaAssetIds: approvedMediaAssetIds,
    editorOverlays,
    taggedUsers,
    autoCategory,
    audioProvider,
    audioTrackId,
    audioTitle,
    audioArtist,
    audioArtworkUrl,
    audioStreamUrl,
    audioStartTime,
    audioDuration,
    clientRequestId,
    createdAt,
  };
  const supabasePostRow = supabasePrimaryPostCreatePayload(supabaseInput);
  let insertedPostRow = supabasePostRow;
  try {
    const insertedRows = await supabaseAdminInsertRows(c, 'app_posts', [supabasePostRow], SUPABASE_APP_POST_SELECT);
    insertedPostRow = insertedRows[0] || supabasePostRow;
    if (approvedMediaAssetIds.length) {
      await supabaseAdminPatchRows(c, 'app_media_assets', {
        user_id: postgrestEqFilter(userId),
        id: postgrestInFilter(approvedMediaAssetIds),
      }, {
        legacy_post_id: id,
        updated_at: createdAt,
      });
    }
    await writeSupabasePrimaryPostPlace(c, supabaseInput);
    await recordAbuseSignals(c, userId, 'post_create', {
      product_links: editorOverlays.filter((item: any) => item?.type === 'product' && item.link).map((item: any) => item.link),
    });
    await supabaseIncrementAppUserPostCount(c, userId).catch((error: any) => {
      console.warn(JSON.stringify({ event: 'supabase_post_count_increment_failed', code: getErrorCode(error).slice(0, 180) }));
    });
  } catch (error: any) {
    const code = getErrorCode(error).slice(0, 180);
    if (clientRequestId && code.includes('23505')) {
      const existing = await supabaseExistingPostByClientRequest(c, userId, clientRequestId, supabaseAuthorRow);
      if (existing) return c.json({ ...postPayload(existing, [], c.env), idempotent_replay: true });
    }
    console.error(JSON.stringify({ event: 'supabase_primary_post_create_failed', post_id: id, user_id: userId, code }));
    return c.json({
      detail: 'Could not save this post to the production database. Please retry.',
      code: 'SUPABASE_PRIMARY_WRITE_FAILED',
    }, 503);
  }

  runBackgroundTask(c, 'supabase_post_follower_notifications_failed', async () => {
    await notifySupabaseFollowersOfNewPost(c, {
      userId,
      postId: id,
      visibility,
      authorName: cleanText(user?.full_name || user?.username || 'Someone you follow', 80),
      body: cleanText(postTitle || postContent || 'Shared a new post', 120),
    });
  });

  const createdPost = {
    ...supabaseAppPostToLegacy(insertedPostRow, supabaseAuthorRow, false, 0),
    client_request_id: clientRequestId,
    moderation_status: 'approved',
    moderation_media_ids: JSON.stringify(approvedMediaAssetIds),
  };
  return c.json(postPayload(createdPost, [], c.env));
});

api.get('/posts/feed', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'feed_read');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'feed_read', userId, 240, 60);
  if (limited) return limited;
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '20', 1, 50, 20);
  try {
    const feedRows = await supabaseReadVisiblePosts(c, userId, { limit, offset: skip, order: 'newest' });
    const response = c.json(feedRows.map((p) => feedPostPayload(p, [], c.env)));
    response.headers.set('cache-control', 'no-store');
    return response;
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_feed_read_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load feed.' }, 500);
  }
});

api.get('/posts/world-board', async (c) => {
  try {
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'world_board_read');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'public_world_board', clientIp(c), 180, 60).catch((error: any) => {
      // Keep anonymous feed reads available if Cloudflare KV exhausts its
      // write quota. Mutating and authenticated routes retain strict limits.
      console.warn(JSON.stringify({
        event: 'public_world_board_rate_limit_unavailable',
        code: getErrorCode(error).slice(0, 180),
      }));
      return null;
    });
    if (limited) return limited;
    const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
    const limit = clampNumber(c.req.query('limit') || '40', 1, 50, 40);
    const viewerId = await getOptionalUserId(c);
    const posts = await supabaseReadVisiblePosts(c, viewerId, { limit, offset: skip, order: 'newest' });
    const response = c.json(posts.map((p) => feedPostPayload(p, [], c.env)));
    response.headers.set('cache-control', 'no-store');
    return response;
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_world_board_read_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load world board.' }, 500);
  }
});

api.get('/posts/nearby-feed', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'nearby_feed_read');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'nearby_feed_read', userId, 180, 60);
  if (limited) return limited;
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '24', 1, 50, 24);
  try {
    const posts = await supabaseReadVisiblePosts(c, userId, { limit, offset: skip, order: 'newest' });
    const response = c.json(posts.map((p) => feedPostPayload(p, [], c.env)));
    response.headers.set('cache-control', 'no-store');
    return response;
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_nearby_feed_read_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load nearby posts.' }, 500);
  }
});

api.get('/posts/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'post_read');
  if (supabaseRequired) return supabaseRequired;
  const postId = c.req.param('postId');
  try {
    const [post] = await supabaseReadVisiblePosts(c, userId, { postId, limit: 1 });
    if (!post) return c.json({ detail: 'Post not found' }, 404);
    const response = c.json(postPayload(post, [], c.env));
    response.headers.set('cache-control', 'no-store');
    return response;
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_post_read_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load post.' }, 500);
  }
});

api.post('/posts/:postId/like', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'post_like');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'post_like', userId, 300, 60);
  if (limited) return limited;
  const body: any = await c.req.json().catch(() => ({}));
  const requested = optionalBoolean(body.liked ?? body.like ?? body.value);
  try {
    const [visiblePost] = await supabaseReadVisiblePosts(c, userId, { postId, limit: 1 });
    if (!visiblePost) return c.json({ detail: 'Post not found' }, 404);
    const { state, changed } = await setCanonicalPostLikeState(c, postId, userId, requested);
    if (state.liked && changed && publicId((visiblePost as any).user_id, 120) !== userId) {
      runBackgroundTask(c, 'supabase_like_notification_failed', async () => {
        const me = await supabaseUserByAnyId(c, userId).catch(() => null);
        await insertNotificationOnce(c, {
          userId: publicId((visiblePost as any).user_id, 120),
          type: 'like',
          title: 'New Like',
          body: `${cleanText(me?.full_name || me?.username || 'Someone', 80)} liked your post`,
          data: { post_id: postId, from_user_id: userId, actor_name: cleanText(me?.full_name || me?.username || 'Someone', 80) },
          dedupeKey: `like:${userId}:${postId}`,
          dedupeSeconds: 86400,
        });
      });
    }
    return c.json(postEngagementResponse(state));
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_post_like_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not update like.' }, 500);
  }
});

api.delete('/posts/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'post_delete');
  if (supabaseRequired) return supabaseRequired;
  try {
    const owned = await supabaseOwnedAppPost(c, postId, userId);
    if (owned.status !== 200) return c.json(owned.body, owned.status);
    const metadata = parseJsonObject(owned.row?.metadata);
    await supabaseAdminPatchRows(c, 'app_posts', { or: supabaseAppPostIdentityOrFilter(owned.identity) }, {
      status: 'removed',
      metadata: {
        ...metadata,
        removed_at: now(),
        removed_reason: 'Deleted by creator',
      },
      updated_at: now(),
    });
    await logSecurityEvent(c, 'post_soft_deleted', userId, { post_id: postId });
    return c.json({ deleted: true, soft_deleted: true });
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_post_delete_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not delete post.' }, 500);
  }
});

api.put('/posts/:postId/visibility', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'post_visibility');
  if (supabaseRequired) return supabaseRequired;
  const postId = c.req.param('postId');
  const body: any = await c.req.json().catch(() => ({}));
  const requestedVisibility = typeof body.visibility === 'string' ? body.visibility.trim().toLowerCase() : '';
  if (!['public', 'followers', 'friends', 'private'].includes(requestedVisibility)) {
    return c.json({ detail: 'Invalid visibility.' }, 400);
  }
  const visibility = normalizeVisibility(requestedVisibility);

  try {
    const owned = await supabaseOwnedAppPost(c, postId, userId);
    if (owned.status !== 200) return c.json(owned.body, owned.status);
    await supabaseAdminPatchRows(c, 'app_posts', { or: supabaseAppPostIdentityOrFilter(owned.identity) }, {
      visibility,
      updated_at: now(),
    });
    await logSecurityEvent(c, 'post_visibility_updated', userId, { post_id: postId, visibility });
    const [updated] = await supabaseReadVisiblePosts(c, userId, { postId, limit: 1 });
    if (!updated) return c.json({ detail: 'Post not found' }, 404);
    return c.json(postPayload(updated, [], c.env));
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_post_visibility_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not update post visibility.' }, 500);
  }
});

api.put('/posts/:postId/pin', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'post_pin');
  if (supabaseRequired) return supabaseRequired;
  const postId = c.req.param('postId');
  const body: any = await c.req.json().catch(() => ({}));
  const requested = optionalBoolean(body.pinned ?? body.pin ?? body.value);
  const shouldPin = requested === null ? true : requested;

  try {
    const owned = await supabaseOwnedAppPost(c, postId, userId);
    if (owned.status !== 200) return c.json(owned.body, owned.status);
    const pinnedAt = shouldPin ? now() : null;
    const metadata = parseJsonObject(owned.row?.metadata);
    await supabaseAdminPatchRows(c, 'app_posts', { or: supabaseAppPostIdentityOrFilter(owned.identity) }, {
      metadata: {
        ...metadata,
        pinned_at: pinnedAt,
      },
      updated_at: now(),
    });
    await logSecurityEvent(c, shouldPin ? 'post_pinned' : 'post_unpinned', userId, { post_id: postId });
    const [updated] = await supabaseReadVisiblePosts(c, userId, { postId, limit: 1 });
    if (!updated) return c.json({ detail: 'Post not found' }, 404);
    return c.json(postPayload(updated, [], c.env));
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_post_pin_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not update pinned post.' }, 500);
  }
});

api.get('/users/:userId/posts', authMiddleware, async (c) => {
  const viewerId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'profile_posts_read');
  if (supabaseRequired) return supabaseRequired;
  const targetId = c.req.param('userId');
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '60', 1, 100, 60);
  try {
    const rows = await supabaseReadVisiblePosts(c, viewerId, { ownerId: targetId, limit, offset: skip, order: 'newest' });
    const response = c.json(rows.map((p) => feedPostPayload(p, [], c.env)));
    response.headers.set('cache-control', 'no-store');
    return response;
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_user_posts_read_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load profile posts.' }, 500);
  }
});

// Comments
api.post('/posts/:postId/comments', authMiddleware, async (c) => {
  try {
    const bodyTooLarge = rejectLargeRequest(c, 100_000);
    if (bodyTooLarge) return bodyTooLarge;
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'comment_create');
    if (supabaseRequired) return supabaseRequired;
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
    const result = await supabaseCreatePostComment(c, { postId, userId, content, parentId, clientRequestId: clientRequestId || undefined });
    return c.json(result.body, result.status);
  } catch (error: any) {
    console.error('Comment create failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not post comment.', code: 'COMMENT_CREATE_FAILED' }, 500);
  }
});

api.get('/posts/:postId/comments', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'comments_read');
    if (supabaseRequired) return supabaseRequired;
    const limit = clampNumber(c.req.query('limit') || '80', 1, 100, 80);
    const result = await supabaseReadPostComments(c, c.req.param('postId'), userId, limit);
    return c.json(result.body, result.status);
  } catch (error: any) {
    console.error('Comment load failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not load comments.' }, 500);
  }
});

api.post('/comments/:commentId/like', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'comment_like');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'comment_like', userId, 300, 60);
    if (limited) return limited;
    const body: any = await c.req.json().catch(() => ({}));
    const requested = optionalBoolean(body.liked ?? body.like ?? body.value);
    const commentId = c.req.param('commentId');
    const result = await supabaseSetCommentLike(c, commentId, userId, requested);
    return c.json(result.body, result.status);
  } catch (error: any) {
    console.error('Comment like failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not update comment like.' }, 500);
  }
});

api.post('/comments/:commentId/pin', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'comment_pin');
    if (supabaseRequired) return supabaseRequired;
    const commentId = c.req.param('commentId');
    const body: any = await c.req.json().catch(() => ({}));
    const requested = optionalBoolean(body.pinned ?? body.pin ?? body.value);
    const shouldPin = requested === null ? true : requested;
    const result = await supabaseSetCommentPinned(c, commentId, userId, requested);
    if (result.status === 200) {
      await logSecurityEvent(c, shouldPin ? 'comment_pinned' : 'comment_unpinned', userId, { comment_id: commentId });
    }
    return c.json(result.body, result.status);
  } catch (error: any) {
    console.error('Comment pin failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not update pinned comment.' }, 500);
  }
});

api.delete('/comments/:commentId', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'comment_delete');
    if (supabaseRequired) return supabaseRequired;
    const commentId = c.req.param('commentId');
    const result = await supabaseUpdateCommentStatus(c, commentId, userId, 'removed');
    return c.json(result.body, result.status);
  } catch (error: any) {
    console.error('Comment delete failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not delete comment.' }, 500);
  }
});

api.post('/comments/:commentId/hide', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'comment_hide');
    if (supabaseRequired) return supabaseRequired;
    const commentId = c.req.param('commentId');
    const result = await supabaseUpdateCommentStatus(c, commentId, userId, 'hidden');
    return c.json(result.body, result.status);
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
    const rawStatusImage = cleanText(s.image || '', 2200);
    const playableStatusImage = rawStatusImage.startsWith('cfstream:')
      ? rawStatusImage
      : isVideoMediaUrl(rawStatusImage) ? streamPlaybackUrl(rawStatusImage) : safeMediaReference(rawStatusImage);
    const parsed = {
      ...s,
      image: playableStatusImage,
      viewed_by: JSON.parse(s.viewed_by || '[]'),
      likes_count: Math.max(0, Number(s.likes_count || 0)),
      liked_by_me: s.liked_by_me === true || s.liked_by_me === 1 || s.liked_by_me === '1',
    };
    grouped.get(uid)!.statuses.push(parsed);
    if (!parsed.viewed_by.includes(viewerId)) {
      grouped.get(uid)!.has_unviewed = true;
    }
  }
  return Array.from(grouped.values());
}

function statusThoughtPayload(row: any) {
  return {
    id: row.id,
    status_id: row.status_id,
    user_id: row.user_id,
    body: cleanText(row.body, 180),
    created_at: row.created_at || '',
    user_username: publicUsernameFor({ username: row.user_username }),
    user_full_name: cleanText(row.user_full_name, 120),
    user_profile_image: safeMediaReference(row.user_profile_image),
  };
}

function supabaseUserIsActive(row: any): boolean {
  const metadata = parseJsonObject(row?.metadata);
  return cleanText((metadata as any).status || 'active', 40) === 'active';
}

function supabaseStoryToStatusRow(row: any, user: any, likesCount = 0, likedByMe = false, viewedByMe = false) {
  const audio = parseJsonObject(row?.audio);
  const metadata = parseJsonObject(row?.metadata);
  const createdAt = row?.legacy_created_at || row?.created_at || now();
  return {
    id: publicId(row?.id, 120),
    user_id: publicId(row?.user_id, 120),
    content: cleanMultilineText(row?.content || '', 2000),
    image: safeMediaReference(row?.media_url || ''),
    media_type: cleanText(row?.media_type || (metadata as any).media_type || '', 80),
    background_color: cleanText(row?.background_color || '#1B4332', 40),
    text_color: cleanText(row?.text_color || '#FFFFFF', 40),
    visibility: normalizeVisibility(row?.visibility),
    status: cleanText(row?.status || 'active', 40),
    duration_seconds: clampNumber(row?.duration_seconds, 0, 60, 0),
    expires_at: row?.expires_at || '',
    created_at: createdAt,
    updated_at: row?.updated_at || createdAt,
    viewed_by: JSON.stringify(viewedByMe ? [publicId(row?.viewer_id || '', 120)].filter(Boolean) : []),
    likes_count: Math.max(0, Number(likesCount || 0)),
    liked_by_me: !!likedByMe,
    user_username: publicUsernameFor({ username: user?.username }),
    user_full_name: cleanText(user?.full_name, 120),
    user_profile_image: safeMediaReference(user?.avatar_url || user?.profile_image || ''),
    audio_provider: cleanText((audio as any).provider, 40),
    audio_track_id: cleanText((audio as any).track_id, 120),
    audio_title: cleanText((audio as any).title, 180),
    audio_artist: cleanText((audio as any).artist, 180),
    audio_artwork_url: safeMediaReference((audio as any).artwork_url || ''),
    audio_stream_url: safeMediaReference((audio as any).stream_url || ''),
    audio_start_time: clampNumber((audio as any).start_time, 0, 60 * 60 * 6, 0),
    audio_duration: clampNumber((audio as any).duration, 0, 60, 0),
  };
}

function supabaseStoryIsVisibleToViewer(row: any, user: any, viewerId: string, blockedIds: Set<string>, followingIds: Set<string>, friendsOnly = false): boolean {
  const storyUserId = publicId(row?.user_id, 120);
  if (!storyUserId) return false;
  const viewerOwnStory = storyUserId === viewerId;
  if (!viewerOwnStory && blockedIds.has(storyUserId)) return false;
  if (!viewerOwnStory && !supabaseUserIsActive(user)) return false;
  if (cleanText(row?.status || 'active', 40) !== 'active') return false;
  const expiresAt = Date.parse(String(row?.expires_at || ''));
  if (Number.isFinite(expiresAt) && expiresAt <= Date.now()) return false;
  if (viewerOwnStory) return !friendsOnly;
  const visibility = normalizeVisibility(row?.visibility);
  if (visibility === 'private') return false;
  const followsAuthor = followingIds.has(storyUserId);
  if (friendsOnly) return followsAuthor;
  if (visibility === 'followers' || visibility === 'friends') return followsAuthor;
  return !user?.is_private;
}

async function supabaseReadVisibleStories(c: any, viewerId: string, friendsOnly = false): Promise<any[]> {
  const rows = await supabaseAdminQueryRows(c, 'app_stories', {
    select: '*',
    filters: {
      status: postgrestEqFilter('active'),
      expires_at: `gt.${now()}`,
    },
    order: 'created_at.desc',
    limit: 120,
  });
  if (!rows.length) return [];

  const authorIds = Array.from(new Set(rows.map((row) => publicId(row?.user_id, 120)).filter(Boolean)));
  const [users, blockedIds, followingIds] = await Promise.all([
    supabaseUsersByAnyIds(c, authorIds),
    supabaseBlockedUserIds(c, viewerId),
    supabaseFollowingUserIds(c, viewerId, authorIds),
  ]);
  const visible = rows.filter((row) => supabaseStoryIsVisibleToViewer(row, users.get(publicId(row?.user_id, 120)), viewerId, blockedIds, followingIds, friendsOnly));
  if (!visible.length) return [];

  const storyIds = visible.map((row) => publicId(row?.id, 120)).filter(Boolean);
  const [likeRows, viewRows] = await Promise.all([
    supabaseAdminQueryRows(c, 'app_story_likes', {
      select: 'story_id,user_id',
      filters: { story_id: postgrestInFilter(storyIds) },
      limit: Math.max(1000, storyIds.length * 200),
    }),
    supabaseAdminQueryRows(c, 'app_story_views', {
      select: 'story_id,user_id',
      filters: {
        story_id: postgrestInFilter(storyIds),
        user_id: postgrestEqFilter(viewerId),
      },
      limit: Math.max(50, storyIds.length),
    }),
  ]);

  const counts = new Map<string, number>();
  const likedByMe = new Set<string>();
  for (const row of likeRows) {
    const storyId = publicId(row?.story_id, 120);
    if (!storyId) continue;
    counts.set(storyId, (counts.get(storyId) || 0) + 1);
    if (publicId(row?.user_id, 120) === viewerId) likedByMe.add(storyId);
  }
  const viewedByMe = new Set(viewRows.map((row) => publicId(row?.story_id, 120)).filter(Boolean));

  return visible.map((row) => {
    const storyId = publicId(row?.id, 120);
    const user = users.get(publicId(row?.user_id, 120));
    return {
      ...supabaseStoryToStatusRow(row, user, counts.get(storyId) || 0, likedByMe.has(storyId), viewedByMe.has(storyId)),
      viewer_id: viewerId,
      viewed_by: JSON.stringify(viewedByMe.has(storyId) ? [viewerId] : []),
    };
  });
}

async function supabaseGetVisibleStory(c: any, storyId: string, viewerId: string): Promise<any | null> {
  const rows = await supabaseAdminQueryRows(c, 'app_stories', {
    select: '*',
    filters: {
      id: postgrestEqFilter(storyId),
      status: postgrestEqFilter('active'),
      expires_at: `gt.${now()}`,
    },
    limit: 1,
  });
  const row = rows[0];
  if (!row) return null;
  const userId = publicId(row?.user_id, 120);
  const [users, blockedIds, followingIds] = await Promise.all([
    supabaseUsersByAnyIds(c, [userId]),
    supabaseBlockedUserIds(c, viewerId),
    supabaseFollowingUserIds(c, viewerId, [userId]),
  ]);
  const user = users.get(userId);
  return supabaseStoryIsVisibleToViewer(row, user, viewerId, blockedIds, followingIds) ? row : null;
}

api.post('/statuses', authMiddleware, async (c) => {
  const phoneGate = await requirePhoneVerified(c, 'share stories');
  if (phoneGate) return phoneGate;
  const userId = getUserId(c); const b = await c.req.json();
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'story_create');
  if (supabaseRequired) return supabaseRequired;
  const storyLifetimeMs = 14 * 24 * 60 * 60 * 1000;
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
  const storyDurationSeconds = normalizeStoryDurationSeconds(b.duration || b.video_duration || b.video_duration_seconds || b.duration_seconds);
  const storyMediaType = String(b.media_type || b.mediaType || '').toLowerCase();
  const storyIsVideo = storyMediaType.includes('video') || isVideoMediaUrl(String(b.image || ''));
  if (storyIsVideo && !storyDurationSeconds) {
    return c.json({ detail: 'Story videos must be 15, 30, or 60 seconds.', code: 'STORY_VIDEO_DURATION_REQUIRED' }, 400);
  }
  if (audioProvider && !audioTrackId) {
    return c.json({ detail: 'Audio track id is required.' }, 400);
  }
  if (audioProvider && await supabaseAudiusTrackIsHidden(c, audioTrackId)) {
    return c.json({ detail: 'This sound is unavailable.' }, 400);
  }

  const users = await supabaseUsersByAnyIds(c, [userId]);
  const user = users.get(userId) || {};
  const createdAt = now();
  const mediaUrl = String(b.image || '').startsWith('cfstream:')
    ? String(b.image || '')
    : isVideoMediaUrl(String(b.image || '')) ? streamPlaybackUrl(String(b.image || '')) : safeMediaReference(String(b.image || ''));
  const audio = {
    provider: audioProvider,
    track_id: audioTrackId,
    title: audioTitle,
    artist: audioArtist,
    artwork_url: audioArtworkUrl,
    stream_url: audioStreamUrl,
    start_time: audioStartTime,
    duration: audioDuration,
  };
  await supabaseAdminUpsert(c, 'app_stories', [{
    id,
    user_id: userId,
    content: cleanMultilineText(b.content || '', 2000),
    media_url: mediaUrl || null,
    media_type: storyIsVideo ? 'video' : cleanText(storyMediaType || 'image', 40),
    background_color: cleanText(b.background_color || '#1B4332', 40),
    text_color: cleanText(b.text_color || '#FFFFFF', 40),
    visibility,
    status: 'active',
    duration_seconds: storyDurationSeconds || null,
    audio,
    metadata: {
      source: 'worker_status_create',
      original_media_url: cleanText(b.image || '', 2200),
    },
    legacy_created_at: createdAt,
    created_at: createdAt,
    updated_at: createdAt,
    expires_at: expiresAt,
  }], 'id');

  return c.json({
    id, user_id: userId, content: cleanMultilineText(b.content || '', 2000),
    image: mediaUrl,
    background_color: b.background_color, text_color: b.text_color,
    visibility, user_username: publicUsernameFor(user), user_full_name: user?.full_name, user_profile_image: user?.avatar_url || user?.profile_image,
    audio_provider: audioProvider, audio_track_id: audioTrackId, audio_title: audioTitle, audio_artist: audioArtist,
    audio_artwork_url: audioArtworkUrl, audio_stream_url: audioStreamUrl, audio_start_time: audioStartTime, audio_duration: audioDuration,
    viewed_by: [], likes_count: 0, liked_by_me: false, created_at: createdAt, expires_at: expiresAt,
  });
});

api.get('/statuses', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'stories_read');
  if (supabaseRequired) return supabaseRequired;
  const rows = await supabaseReadVisibleStories(c, userId);
  return c.json(groupStatusRows(rows, userId));
});

api.get('/statuses/friends', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'friends_stories_read');
  if (supabaseRequired) return supabaseRequired;
  const rows = await supabaseReadVisibleStories(c, userId, true);
  return c.json(groupStatusRows(rows, userId));
});

api.post('/statuses/:statusId/like', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'story_like');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'story_like', userId, 300, 60);
  if (limited) return limited;
  const statusId = publicId(c.req.param('statusId'), 120);
  const body: any = await c.req.json().catch(() => ({}));
  const requested = optionalBoolean(body.liked ?? body.like ?? body.value);

  const story = await supabaseGetVisibleStory(c, statusId, userId);
  if (!story) return c.json({ detail: 'Story not found' }, 404);
  if (publicId(story?.user_id, 120) === userId) {
    return c.json({ detail: 'You cannot like your own story.' }, 400);
  }
  const existingRows = await supabaseAdminQueryRows(c, 'app_story_likes', {
    select: 'story_id',
    filters: {
      story_id: postgrestEqFilter(statusId),
      user_id: postgrestEqFilter(userId),
    },
    limit: 1,
  });
  const nextLiked = requested ?? !existingRows[0];
  if (nextLiked) {
    await supabaseAdminUpsert(c, 'app_story_likes', [{
      story_id: statusId,
      user_id: userId,
      created_at: now(),
    }], 'story_id,user_id');
  } else {
    await supabaseAdminDeleteRows(c, 'app_story_likes', {
      story_id: postgrestEqFilter(statusId),
      user_id: postgrestEqFilter(userId),
    });
  }
  const [count, likedRows] = await Promise.all([
    supabaseAdminCountRows(c, 'app_story_likes', { story_id: postgrestEqFilter(statusId) }),
    supabaseAdminQueryRows(c, 'app_story_likes', {
      select: 'story_id',
      filters: {
        story_id: postgrestEqFilter(statusId),
        user_id: postgrestEqFilter(userId),
      },
      limit: 1,
    }),
  ]);
  return c.json({
    liked: !!likedRows[0],
    likes_count: Math.max(0, Number(count || 0)),
  });
});

api.post('/statuses/:statusId/view', authMiddleware, async (c) => {
  const userId = getUserId(c); const statusId = c.req.param('statusId');
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'story_view');
  if (supabaseRequired) return supabaseRequired;
  const cleanStatusId = publicId(statusId, 120);
  const story = await supabaseGetVisibleStory(c, cleanStatusId, userId);
  if (!story) return c.json({ detail: 'Not found' }, 404);
  await supabaseAdminUpsert(c, 'app_story_views', [{
    story_id: cleanStatusId,
    user_id: userId,
    created_at: now(),
  }], 'story_id,user_id');
  return c.json({ viewed: true });
});

api.get('/statuses/:statusId/thoughts', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'story_thoughts_read');
  if (supabaseRequired) return supabaseRequired;
  const statusId = publicId(c.req.param('statusId'), 120);
  const limit = clampNumber(c.req.query('limit') || '24', 1, 40, 24);
  const story = await supabaseGetVisibleStory(c, statusId, userId);
  if (!story) return c.json({ detail: 'Story not found' }, 404);
  const rows = await supabaseAdminQueryRows(c, 'app_story_thoughts', {
    select: '*',
    filters: {
      story_id: postgrestEqFilter(statusId),
      status: postgrestEqFilter('active'),
    },
    order: 'created_at.desc',
    limit,
  });
  const senderIds = Array.from(new Set(rows.map((row) => publicId(row?.user_id, 120)).filter(Boolean)));
  const [users, blockedIds] = await Promise.all([
    supabaseUsersByAnyIds(c, senderIds),
    supabaseBlockedUserIds(c, userId),
  ]);
  const payload = rows
    .filter((row) => {
      const thoughtUserId = publicId(row?.user_id, 120);
      return thoughtUserId && !blockedIds.has(thoughtUserId) && supabaseUserIsActive(users.get(thoughtUserId));
    })
    .reverse()
    .map((row) => {
      const user = users.get(publicId(row?.user_id, 120)) || {};
      return statusThoughtPayload({
        ...row,
        status_id: row.story_id,
        user_username: user.username,
        user_full_name: user.full_name,
        user_profile_image: user.avatar_url,
      });
    });
  return c.json(payload);
});

api.post('/statuses/:statusId/thoughts', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'story_thought_create');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'story_thought_create', userId, 40, 60);
  if (limited) return limited;
  const statusId = publicId(c.req.param('statusId'), 120);
  const body: any = await c.req.json().catch(() => ({}));
  const text = cleanText(body.body || body.text || body.thought || '', 180);
  if (!text) return c.json({ detail: 'Thought is required.' }, 400);

  const story = await supabaseGetVisibleStory(c, statusId, userId);
  if (!story) return c.json({ detail: 'Story not found' }, 404);
  const storyOwnerId = publicId(story?.user_id, 120);
  if (storyOwnerId && (await supabaseUserIdsAreBlocked(c, userId, storyOwnerId))) {
    return c.json({ detail: 'You cannot share a thought on this story.' }, 403);
  }
  const id = uuid();
  const createdAt = now();
  await supabaseAdminUpsert(c, 'app_story_thoughts', [{
    id,
    story_id: statusId,
    user_id: userId,
    body: text,
    status: 'active',
    created_at: createdAt,
    updated_at: createdAt,
  }], 'id');
  await logSecurityEvent(c, 'story_thought_created', userId, { status_id: statusId });

  const users = await supabaseUsersByAnyIds(c, [userId]);
  const user = users.get(userId) || {};
  return c.json(statusThoughtPayload({
    id,
    status_id: statusId,
    user_id: userId,
    body: text,
    created_at: createdAt,
    user_username: user.username,
    user_full_name: user.full_name,
    user_profile_image: user.avatar_url,
  }));
});

api.delete('/statuses/:statusId', authMiddleware, async (c) => {
  const userId = getUserId(c); const statusId = c.req.param('statusId');
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'story_delete');
  if (supabaseRequired) return supabaseRequired;
  const cleanStatusId = publicId(statusId, 120);
  const rows = await supabaseAdminQueryRows(c, 'app_stories', {
    select: 'id,user_id',
    filters: { id: postgrestEqFilter(cleanStatusId) },
    limit: 1,
  });
  const story = rows[0];
  if (!story) return c.json({ detail: 'Story not found' }, 404);
  if (publicId(story?.user_id, 120) !== userId) return c.json({ detail: 'Not your story' }, 403);
  await supabaseAdminPatchRows(c, 'app_stories', { id: postgrestEqFilter(cleanStatusId) }, {
    status: 'removed',
    updated_at: now(),
  });
  await logSecurityEvent(c, 'story_deleted', userId, { status_id: cleanStatusId });
  return c.json({ deleted: true });
});

// Messages (with media support)
async function requireGroupMember(c: any, groupId: string, userId: string) {
  const rows = await supabaseAdminQueryRows(c, 'app_group_chat_members', {
    select: 'id',
    filters: {
      group_id: postgrestEqFilter(groupId),
      user_id: postgrestEqFilter(userId),
    },
    limit: 1,
  });
  return !!rows[0];
}

function supabaseMessageToLegacy(row: any): any {
  const media = parseJsonObject(row?.media);
  return {
    ...row,
    content: cleanMultilineText(row?.content || row?.body, 2000),
    media_url: safeMediaReference(row?.media_url || (media as any).url || (media as any).playback_url || ''),
    media_type: cleanText(row?.media_type || (media as any).type, 40),
    thumbnail_url: safeMediaReference((media as any).thumbnail_url || (media as any).thumbnailUrl || ''),
    poster_url: safeMediaReference((media as any).poster_url || (media as any).posterUrl || ''),
    is_read: row?.is_read === true || row?.is_read === 1 || row?.is_read === '1' ? 1 : 0,
    created_at: row?.legacy_created_at || row?.created_at,
    updated_at: row?.updated_at || row?.created_at,
  };
}

async function supabaseValidateDirectMessagePeer(c: any, currentUserId: string, peerId: string) {
  if (!peerId || peerId === currentUserId) {
    return c.json({ detail: 'Choose a valid recipient.' }, 400);
  }
  const peer = await supabaseUserByAnyId(c, peerId);
  const peerStatus = cleanText(parseJsonObject(peer?.metadata).status || peer?.status || 'active', 40);
  if (!peer || peerStatus !== 'active') return c.json({ detail: 'Recipient not found.' }, 404);
  if (await supabaseBlockPair(c, currentUserId, peerId)) {
    await logSecurityEvent(c, 'blocked_message_access_denied', currentUserId, { peer_id: peerId });
    return c.json({ detail: 'You cannot message this profile.' }, 403);
  }
  return null;
}

async function supabaseDirectMessageRows(c: any, firstUserId: string, secondUserId: string, input: { limit: number; before?: string; after?: string }) {
  const first = publicId(firstUserId, 120);
  const second = publicId(secondUserId, 120);
  const limit = clampNumber(input.limit, 1, 100, 80);
  const baseFilters: Record<string, string> = {
    or: `(and(sender_id.eq.${first},receiver_id.eq.${second}),and(sender_id.eq.${second},receiver_id.eq.${first}))`,
  };
  const after = cleanText(input.after || '', 80);
  const before = cleanText(input.before || '', 80);
  if (after) baseFilters.created_at = `gt.${after}`;
  if (before) baseFilters.created_at = `lt.${before}`;
  const rows = await supabaseAdminQueryRows(c, 'app_messages', {
    select: '*',
    filters: baseFilters,
    order: after ? 'created_at.asc' : 'created_at.desc',
    limit,
  });
  const ordered = after ? rows : rows.reverse();
  return Promise.all(ordered.map((row) => messagePayload(c, supabaseMessageToLegacy(row))));
}

async function supabaseGroupMessageRows(c: any, groupId: string, input: { limit: number; before?: string; after?: string }) {
  const limit = clampNumber(input.limit, 1, 100, 80);
  const filters: Record<string, string> = { group_id: postgrestEqFilter(groupId) };
  const after = cleanText(input.after || '', 80);
  const before = cleanText(input.before || '', 80);
  if (after) filters.created_at = `gt.${after}`;
  if (before) filters.created_at = `lt.${before}`;
  const rows = await supabaseAdminQueryRows(c, 'app_group_messages', {
    select: '*',
    filters,
    order: after ? 'created_at.asc' : 'created_at.desc',
    limit,
  });
  const ordered = after ? rows : rows.reverse();
  return Promise.all(ordered.map((row) => messagePayload(c, supabaseMessageToLegacy(row))));
}

api.get('/conversations', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'conversations_read');
  if (supabaseRequired) return supabaseRequired;
  const limit = clampNumber(c.req.query('limit') || '60', 1, 100, 60);
  const blockedIds = await supabaseBlockedUserIds(c, userId);
  const directRows = await supabaseAdminQueryRows(c, 'app_messages', {
    select: '*',
    filters: { or: `(sender_id.eq.${userId},receiver_id.eq.${userId})` },
    order: 'created_at.desc',
    limit: Math.max(120, limit * 6),
  });
  const otherIds = Array.from(new Set(directRows.map((row) => publicId(row.sender_id === userId ? row.receiver_id : row.sender_id, 120)).filter(Boolean)));
  const users = await supabaseUsersByAnyIds(c, otherIds);
  const directMap = new Map<string, any>();
  const unreadCounts = new Map<string, number>();
  for (const row of directRows) {
    const otherId = publicId(row.sender_id === userId ? row.receiver_id : row.sender_id, 120);
    if (!otherId || blockedIds.has(otherId)) continue;
    if (row.receiver_id === userId && row.is_read !== true) unreadCounts.set(otherId, (unreadCounts.get(otherId) || 0) + 1);
    if (directMap.has(otherId)) continue;
    const user = users.get(otherId) || {};
    const legacyMessage = supabaseMessageToLegacy(row);
    let preview = legacyMessage.content || '';
    if (!preview && legacyMessage.media_type === 'video') preview = 'Sent a video';
    else if (!preview && legacyMessage.media_type === 'voice') preview = 'Sent a voice message';
    else if (!preview && legacyMessage.media_type === 'file') preview = 'Sent a file';
    else if (!preview && legacyMessage.media_url) preview = 'Sent a photo';
    directMap.set(otherId, {
      id: `conv-${otherId}`,
      participants: [userId, otherId],
      other_user: {
        id: otherId,
        username: user?.username,
        full_name: user?.full_name,
        profile_image: safeMediaReference(user?.avatar_url),
        last_seen_at: null,
        is_online: false,
        is_typing: false,
      },
      last_message: preview,
      last_message_time: legacyMessage.created_at,
      unread_count: unreadCounts.get(otherId) || 0,
    });
  }
  for (const [otherId, count] of unreadCounts.entries()) {
    const existing = directMap.get(otherId);
    if (existing) existing.unread_count = count;
  }
  if (directMap.size) {
    await Promise.all(Array.from(directMap.entries()).map(async ([otherId, conversation]) => {
      const [lastSeenAt, isTyping] = await Promise.all([
        readSupabasePrimaryPresence(c, otherId),
        readSupabasePrimaryTyping(c, otherId, userId),
      ]);
      conversation.other_user.last_seen_at = lastSeenAt;
      conversation.other_user.is_online = isPresenceOnline(lastSeenAt);
      conversation.other_user.is_typing = isTyping;
    }));
  }

  const memberships = await supabaseAdminQueryRows(c, 'app_group_chat_members', {
    select: 'group_id',
    filters: { user_id: postgrestEqFilter(userId) },
    order: 'created_at.desc',
    limit: 100,
  }).catch(() => []);
  const groupIds = Array.from(new Set(memberships.map((row) => publicId(row.group_id, 120)).filter(Boolean)));
  let groupConversations: any[] = [];
  if (groupIds.length) {
    const [groups, members, messages] = await Promise.all([
      supabaseAdminQueryRows(c, 'app_group_chats', {
        select: '*',
        filters: { id: postgrestInFilter(groupIds) },
        limit: groupIds.length,
      }).catch(() => []),
      supabaseAdminQueryRows(c, 'app_group_chat_members', {
        select: 'group_id,user_id',
        filters: { group_id: postgrestInFilter(groupIds) },
        limit: Math.max(100, groupIds.length * 60),
      }).catch(() => []),
      supabaseAdminQueryRows(c, 'app_group_messages', {
        select: '*',
        filters: { group_id: postgrestInFilter(groupIds) },
        order: 'created_at.desc',
        limit: Math.max(100, groupIds.length * 20),
      }).catch(() => []),
    ]);
    const memberCount = new Map<string, number>();
    for (const member of members) {
      const groupId = publicId(member.group_id, 120);
      memberCount.set(groupId, (memberCount.get(groupId) || 0) + 1);
    }
    const lastMessage = new Map<string, any>();
    for (const message of messages) {
      const groupId = publicId(message.group_id, 120);
      if (!lastMessage.has(groupId)) lastMessage.set(groupId, message);
    }
    const senderIds = Array.from(new Set(messages.map((row) => publicId(row.sender_id, 120)).filter(Boolean)));
    const senders = await supabaseUsersByAnyIds(c, senderIds);
    groupConversations = groups.map((group: any) => {
      const groupId = publicId(group.id, 120);
      const msg = lastMessage.get(groupId);
      const legacyMessage = msg ? supabaseMessageToLegacy(msg) : null;
      const sender = msg ? senders.get(publicId(msg.sender_id, 120)) || {} : {};
      const senderName = publicUsernameFor({ username: sender?.username }) || cleanText(sender?.full_name, 80) || 'Someone';
      return {
        id: `group-${groupId}`,
        type: 'group',
        group_id: groupId,
        group_name: cleanText(group.name || 'New group', 120),
        member_count: memberCount.get(groupId) || 0,
        last_message: legacyMessage
          ? legacyMessage.content
            ? `${senderName}: ${legacyMessage.content}`
            : legacyMessage.media_type === 'video'
              ? `${senderName}: Sent a video`
              : legacyMessage.media_type === 'voice'
                ? `${senderName}: Sent a voice message`
                : legacyMessage.media_type === 'file'
                  ? `${senderName}: Sent a file`
                  : legacyMessage.media_url
                    ? `${senderName}: Sent a photo`
                    : 'Group created'
          : 'Group created',
        last_message_time: legacyMessage?.created_at || group.legacy_created_at || group.created_at,
        unread_count: 0,
      };
    });
  }

  return c.json([...directMap.values(), ...groupConversations]
    .sort((a, b) => Date.parse(b.last_message_time || '') - Date.parse(a.last_message_time || ''))
    .slice(0, limit));
});

api.post('/presence/touch', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'presence_touch');
  if (supabaseRequired) return supabaseRequired;
  const touchedAt = await touchSupabasePrimaryPresence(c, userId);
  return c.json({ ok: true, touched_at: touchedAt });
});

api.post('/messages', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'message_send');
  if (supabaseRequired) return supabaseRequired;
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
    const recentDuplicate = await supabaseAdminQueryRows(c, 'app_messages', {
      select: 'id',
      filters: {
        sender_id: postgrestEqFilter(userId),
        receiver_id: postgrestEqFilter(receiverId),
        body: postgrestEqFilter(content),
        created_at: `gt.${new Date(Date.now() - 30_000).toISOString()}`,
      },
      limit: 1,
    });
    if (recentDuplicate[0]) {
      await logSecurityEvent(c, 'duplicate_message_blocked', userId, { receiver_id: receiverId });
      return c.json({ detail: 'You already sent that message. Try again in a moment.' }, 429);
    }
  }
  const id = uuid();
  const ts = now();
  const media: Record<string, unknown> = {};
  if (mediaUrl) media.url = mediaUrl;
  if (mediaType) media.type = mediaType;
  await supabaseAdminUpsert(c, 'app_messages', [{
    id,
    sender_id: userId,
    receiver_id: receiverId,
    body: content,
    media_url: mediaUrl || null,
    media_type: mediaType,
    media,
    is_read: false,
    status: 'sent',
    legacy_created_at: ts,
    created_at: ts,
    updated_at: ts,
  }], 'id');
  await setSupabasePrimaryTyping(c, userId, receiverId, false);
  runBackgroundTask(c, 'message_notification_failed', async () => {
    const sender = await supabaseUserByAnyId(c, userId);
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
  return c.json(await messagePayload(c, supabaseMessageToLegacy({ id, sender_id: userId, receiver_id: receiverId, body: content, media_url: mediaUrl || null, media_type: mediaType, media, created_at: ts, updated_at: ts, status: 'sent' })));
});

api.get('/messages/presence/:userId', authMiddleware, async (c) => {
  const myId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'message_presence');
  if (supabaseRequired) return supabaseRequired;
  const peerId = publicId(c.req.param('userId'), 120);
  await touchSupabasePrimaryPresence(c, myId);
  const limited = await enforceRateLimit(c, 'message_presence', myId, 160, 60);
  if (limited) return limited;
  const invalidPeer = await validateDirectMessagePeer(c, myId, peerId);
  if (invalidPeer) return invalidPeer;
  const lastSeenAt = await readSupabasePrimaryPresence(c, peerId);
  return c.json({
    user_id: peerId,
    last_seen_at: lastSeenAt,
    is_online: isPresenceOnline(lastSeenAt),
    is_typing: await readSupabasePrimaryTyping(c, peerId, myId),
  });
});

api.post('/messages/typing', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'message_typing');
  if (supabaseRequired) return supabaseRequired;
  await touchSupabasePrimaryPresence(c, userId);
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
  const updatedAt = await setSupabasePrimaryTyping(c, userId, peerId, isTyping);
  return c.json({ typing: isTyping, updated_at: updatedAt });
});

api.get('/messages/:userId', authMiddleware, async (c) => {
  const myId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'message_read');
  if (supabaseRequired) return supabaseRequired;
  const oid = publicId(c.req.param('userId'), 120);
  const limited = await enforceRateLimit(c, 'message_read', myId, 160, 60);
  if (limited) return limited;
  const invalidPeer = await validateDirectMessagePeer(c, myId, oid);
  if (invalidPeer) return invalidPeer;
  const limit = clampNumber(c.req.query('limit') || '80', 1, 100, 80);
  const before = cleanText(c.req.query('before') || '', 60);
  const after = cleanText(c.req.query('after') || '', 60);
  await supabaseAdminPatchRows(c, 'app_messages', {
    sender_id: postgrestEqFilter(oid),
    receiver_id: postgrestEqFilter(myId),
    is_read: 'eq.false',
  }, { is_read: true, updated_at: now() }).catch(() => undefined);
  return c.json(await supabaseDirectMessageRows(c, myId, oid, { limit, before, after }));
});

api.post('/group-chats', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'group_chat_create');
  if (supabaseRequired) return supabaseRequired;
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
  if (uniqueMemberIds.length < 1) return c.json({ detail: 'Select at least one person for a group chat.' }, 400);
  const users = await supabaseUsersByAnyIds(c, uniqueMemberIds);
  if (uniqueMemberIds.some((memberId) => !users.has(memberId))) {
    return c.json({ detail: 'One or more selected people could not be found.' }, 400);
  }
  for (const memberId of uniqueMemberIds) {
    if (await supabaseBlockPair(c, userId, memberId)) return c.json({ detail: 'A blocked profile cannot be added to this group.' }, 403);
  }
  const groupId = uuid();
  const name = cleanText(body.name || '', 80) || 'New group';
  const ts = now();
  await supabaseAdminUpsert(c, 'app_group_chats', [{
    id: groupId,
    name,
    created_by: userId,
    metadata: { source: 'cloudflare_worker_primary' },
    legacy_created_at: ts,
    created_at: ts,
    updated_at: ts,
  }], 'id');
  await supabaseAdminUpsert(c, 'app_group_chat_members', [
    { id: uuid(), group_id: groupId, user_id: userId, role: 'owner', legacy_created_at: ts, created_at: ts, updated_at: ts },
    ...uniqueMemberIds.map((memberId) => ({
      id: uuid(),
      group_id: groupId,
      user_id: memberId,
      role: 'member',
      legacy_created_at: ts,
      created_at: ts,
      updated_at: ts,
    })),
  ], 'group_id,user_id');
  const messageId = uuid();
  await supabaseAdminUpsert(c, 'app_group_messages', [{
    id: messageId,
    group_id: groupId,
    sender_id: userId,
    body: 'Created the group',
    media: {},
    legacy_created_at: ts,
    created_at: ts,
    updated_at: ts,
  }], 'id');

  return c.json({ id: groupId, name, member_count: uniqueMemberIds.length + 1, created_by: userId, created_at: ts });
});

api.get('/group-chats/:groupId/messages', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'group_messages_read');
  if (supabaseRequired) return supabaseRequired;
  const groupId = publicId(c.req.param('groupId'), 120);
  const limited = await enforceRateLimit(c, 'group_message_read', userId, 160, 60);
  if (limited) return limited;
  if (!await requireGroupMember(c, groupId, userId)) return c.json({ detail: 'Group not found' }, 404);
  const limit = clampNumber(c.req.query('limit') || '80', 1, 100, 80);
  const before = cleanText(c.req.query('before') || '', 60);
  const after = cleanText(c.req.query('after') || '', 60);
  const [groups, members] = await Promise.all([
    supabaseAdminQueryRows(c, 'app_group_chats', {
      select: '*',
      filters: { id: postgrestEqFilter(groupId) },
      limit: 1,
    }),
    supabaseAdminQueryRows(c, 'app_group_chat_members', {
      select: 'user_id',
      filters: { group_id: postgrestEqFilter(groupId) },
      limit: 200,
    }),
  ]);
  const group = groups[0];
  if (!group) return c.json({ detail: 'Group not found' }, 404);
  const messages = await supabaseGroupMessageRows(c, groupId, { limit, before, after });
  return c.json({
    group: {
      ...group,
      member_count: members.length,
      created_at: group.legacy_created_at || group.created_at,
    },
    messages,
  });
});

api.post('/group-chats/:groupId/messages', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'group_message_send');
  if (supabaseRequired) return supabaseRequired;
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
    const recentDuplicate = await supabaseAdminQueryRows(c, 'app_group_messages', {
      select: 'id',
      filters: {
        group_id: postgrestEqFilter(groupId),
        sender_id: postgrestEqFilter(userId),
        body: postgrestEqFilter(content),
        created_at: `gt.${new Date(Date.now() - 30_000).toISOString()}`,
      },
      limit: 1,
    });
    if (recentDuplicate[0]) {
      await logSecurityEvent(c, 'duplicate_group_message_blocked', userId, { group_id: groupId });
      return c.json({ detail: 'You already sent that message. Try again in a moment.' }, 429);
    }
  }
  const id = uuid();
  const ts = now();
  const media: Record<string, unknown> = {};
  if (mediaUrl) media.url = mediaUrl;
  if (mediaType) media.type = mediaType;
  await supabaseAdminUpsert(c, 'app_group_messages', [{
    id,
    group_id: groupId,
    sender_id: userId,
    body: content,
    media_url: mediaUrl || null,
    media_type: mediaType,
    media,
    legacy_created_at: ts,
    created_at: ts,
    updated_at: ts,
  }], 'id');
  await supabaseAdminPatchRows(c, 'app_group_chats', { id: postgrestEqFilter(groupId) }, { updated_at: ts }).catch(() => undefined);
  return c.json(await messagePayload(c, supabaseMessageToLegacy({ id, group_id: groupId, sender_id: userId, body: content, media_url: mediaUrl || null, media_type: mediaType, media, created_at: ts, updated_at: ts, status: 'sent' })));
});

// Notifications
api.get('/notifications', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'notifications_read');
    if (supabaseRequired) return supabaseRequired;
    const limited = await enforceRateLimit(c, 'notifications_read', userId, 180, 60);
    if (limited) return limited;
    const limit = clampNumber(c.req.query('limit') || '50', 1, 80, 50);
    const before = cleanText(c.req.query('before') || '', 60);
    const filters: Record<string, string> = { user_id: postgrestEqFilter(userId) };
    if (before) filters.created_at = `lt.${toPgTime(before) || before}`;
    const rows = await supabaseAdminQueryRows(c, 'app_notifications', {
      select: 'id,user_id,from_user_id,type,title,body,content,reference_id,data,is_read,created_at,updated_at',
      filters,
      order: 'created_at.desc',
      limit,
    });
    return c.json(rows.map(safeNotificationPayload));
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'notifications_read_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load notifications.' }, 500);
  }
});
api.get('/notifications/unread-count', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const supabaseRequired = requireSupabasePrimaryDatabase(c, 'notifications_unread_count');
    if (supabaseRequired) return supabaseRequired;
    const count = await supabaseAdminCountRows(c, 'app_notifications', {
      user_id: postgrestEqFilter(userId),
      is_read: 'eq.false',
    });
    return c.json({ count });
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'notifications_unread_count_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load notification count.' }, 500);
  }
});
api.post('/notifications/mark-read', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'notifications_mark_read');
  if (supabaseRequired) return supabaseRequired;
  await supabaseAdminPatchRows(c, 'app_notifications', { user_id: postgrestEqFilter(userId) }, { is_read: true, updated_at: now() });
  return c.json({ marked: true });
});

api.post('/notifications/device-token', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'push_token_register');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'push_token_register', userId, 30, 60);
  if (limited) return limited;
  const bodyTooLarge = rejectLargeRequest(c, 20_000);
  if (bodyTooLarge) return bodyTooLarge;
  const body: any = await c.req.json().catch(() => ({}));
  const token = String(body.token || '').trim().replace(/[^a-fA-F0-9]/g, '');
  if (token.length < 32 || token.length > 512) return c.json({ detail: 'Invalid device token.' }, 400);
  const timestamp = now();
  const normalizedToken = token.toLowerCase();
  const tokenHash = await sha256Hex(normalizedToken);
  await supabaseAdminUpsert(c, 'app_push_tokens', [{
    id: await sha256Hex(`${userId}:${tokenHash}`),
    user_id: userId,
    token_hash: tokenHash,
    token: normalizedToken,
    device_id: cleanText(body.device_id || body.deviceId || '', 160),
    bundle_id: cleanText(body.bundle_id || body.bundleId || c.env.APNS_BUNDLE_ID || '', 160),
    environment: cleanText(body.environment || c.env.APNS_ENVIRONMENT || 'production', 32),
    platform: 'ios',
    is_active: true,
    last_seen_at: timestamp,
    updated_at: timestamp,
  }], 'user_id,token_hash');
  return c.json({ ok: true });
});

api.delete('/notifications/device-token', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'push_token_delete');
  if (supabaseRequired) return supabaseRequired;
  const body: any = await c.req.json().catch(() => ({}));
  const token = String(body.token || '').trim().replace(/[^a-fA-F0-9]/g, '').toLowerCase();
  if (!token) return c.json({ ok: true });
  const tokenHash = await sha256Hex(token);
  await supabaseAdminPatchRows(c, 'app_push_tokens', {
    user_id: postgrestEqFilter(userId),
    token_hash: postgrestEqFilter(tokenHash),
  }, { is_active: false, updated_at: now() });
  return c.json({ ok: true });
});

api.post('/client/events', async (c) => {
  const userId = await getOptionalUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'client_events');
  if (supabaseRequired) return supabaseRequired;
  const key = userId || clientIp(c);
  const limited = await enforceRateLimit(c, 'client_events', key, 80, 60);
  if (limited) return limited;
  const bodyTooLarge = rejectLargeRequest(c, 24_000);
  if (bodyTooLarge) return bodyTooLarge;
  const body: any = await c.req.json().catch(() => ({}));
  const eventName = cleanText(body.event_name || body.eventName || body.name, 80);
  if (!eventName || !/^[a-z0-9_.:-]{2,80}$/i.test(eventName)) return c.json({ detail: 'Invalid event name.' }, 400);
  const metadata = sanitizeClientEventMetadata(body.metadata || {});
  await supabaseAdminUpsert(c, 'app_client_events', [{
    id: uuid(),
    user_id: userId || null,
    event_name: eventName,
    category: cleanText(body.category || '', 40),
    status: cleanText(body.status || '', 40),
    duration_ms: clampNumber(body.duration_ms || body.durationMs || 0, 0, 600_000, 0),
    metadata,
    app_version: cleanText(body.app_version || body.appVersion || '', 40),
    platform: cleanText(body.platform || 'ios', 20),
    created_at: now(),
  }], 'id');
  return c.json({ accepted: true }, 202);
});

// Library
api.get('/library/liked', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'liked_library_read');
  if (supabaseRequired) return supabaseRequired;
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '40', 1, 80, 40);
  try {
    const postIds = await supabaseViewerInteractionPostIds(c, userId, 'like', { limit, offset: skip });
    const rows = postIds.length ? await supabaseReadVisiblePosts(c, userId, { postIds, limit: postIds.length }) : [];
    return c.json(rows.map((p) => feedPostPayload(p, [], c.env)));
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_liked_library_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load liked posts.' }, 500);
  }
});
api.get('/library/saved', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'saved_library_read');
  if (supabaseRequired) return supabaseRequired;
  const collection = c.req.query('collection');
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '40', 1, 80, 40);
  try {
    const postIds = await supabaseViewerInteractionPostIds(c, userId, 'save', { collection, limit, offset: skip });
    const rows = postIds.length ? await supabaseReadVisiblePosts(c, userId, { postIds, limit: postIds.length }) : [];
    return c.json(rows.map((p) => feedPostPayload(p, [], c.env)));
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_saved_library_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load bookmarks.' }, 500);
  }
});
api.post('/library/save/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'library_save');
  if (supabaseRequired) return supabaseRequired;
  const postId = c.req.param('postId');
  const b = await c.req.json().catch(() => ({}));
  const collection = cleanText((b as any).collection || 'Bookmarks', 80) || 'Bookmarks';
  const limited = await enforceRateLimit(c, 'save_post', userId, 240, 60);
  if (limited) return limited;
  try {
    const [post] = await supabaseReadVisiblePosts(c, userId, { postId, limit: 1 });
    if (!post) return c.json({ detail: 'Post not found' }, 404);
    const { state: engagement } = await setCanonicalPostSaveState(c, postId, userId, true, collection);
    return c.json(postEngagementResponse(engagement, { collection }));
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_library_save_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not save post.' }, 500);
  }
});
api.delete('/library/save/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'library_unsave');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'save_post', userId, 240, 60);
  if (limited) return limited;
  const postId = c.req.param('postId');
  try {
    const { state: engagement } = await setCanonicalPostSaveState(c, postId, userId, false);
    return c.json(postEngagementResponse(engagement, { unsaved: true }));
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_library_unsave_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not remove bookmark.' }, 500);
  }
});
api.get('/library/collections', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'library_collections_read');
  if (supabaseRequired) return supabaseRequired;
  try {
    return c.json(await supabaseViewerSaveCollectionCounts(c, userId));
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_library_collections_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load bookmark collections.' }, 500);
  }
});

// Friends
api.post('/friends/request/:userId', authMiddleware, async (c) => {
  const fid = getUserId(c);
  const tid = publicId(c.req.param('userId'), 120);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'friend_request');
  if (supabaseRequired) return supabaseRequired;
  if (fid === tid) return c.json({ detail: 'Cannot friend yourself' }, 400);
  const limited = await enforceRateLimit(c, 'friend_request', fid, 60, 60);
  if (limited) return limited;
  const result = await supabaseCreateFriendRequest(c, fid, tid);
  return c.json(result.body, result.status);
});
api.post('/friends/accept/:requestId', authMiddleware, async (c) => {
  const uid = getUserId(c);
  const rid = c.req.param('requestId');
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'friend_accept');
  if (supabaseRequired) return supabaseRequired;
  const result = await supabaseAcceptFriendRequest(c, uid, rid);
  return c.json(result.body, result.status);
});
api.post('/friends/reject/:requestId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const requestId = publicId(c.req.param('requestId'), 120);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'friend_reject');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'friend_reject', userId, 120, 60);
  if (limited) return limited;
  const result = await supabaseRejectFriendRequest(c, userId, requestId);
  return c.json(result.body, result.status);
});
api.get('/friends/requests', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'friend_requests_read');
  if (supabaseRequired) return supabaseRequired;
  return c.json(await supabaseFriendRequestsPayload(c, userId));
});
api.get('/friends', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'friends_read');
  if (supabaseRequired) return supabaseRequired;
  return c.json(await supabaseFriendsPayload(c, userId));
});
api.get('/friends/status/:userId', authMiddleware, async (c) => {
  const mid = getUserId(c);
  const oid = c.req.param('userId');
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'friend_status_read');
  if (supabaseRequired) return supabaseRequired;
  return c.json(await supabaseFriendStatus(c, mid, oid));
});
api.delete('/friends/:userId', authMiddleware, async (c) => {
  const mid = getUserId(c);
  const oid = c.req.param('userId');
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'friend_remove');
  if (supabaseRequired) return supabaseRequired;
  return c.json(await supabaseRemoveFriend(c, mid, oid));
});

// Discover
api.get('/discover', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'discover_read');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'discover_category_read', userId, 180, 60);
  if (limited) return limited;
  const rawCategory = c.req.query('category') || 'all';
  const category = normalizeDiscoverCategory(rawCategory, true);
  if (!category) return c.json({ detail: 'Unknown Discover category.' }, 400);
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '36', 1, 60, 36);
  try {
    const discoverRows = await supabaseReadVisiblePosts(c, userId, { category, limit, offset: skip, order: 'newest' });
    const response = c.json(discoverRows.map((post) => feedPostPayload(post, [], c.env)));
    response.headers.set('cache-control', 'no-store');
    return response;
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_discover_read_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load Discover.' }, 500);
  }
});

api.get('/discover/trending', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'discover_trending_read');
  if (supabaseRequired) return supabaseRequired;
  const limit = clampNumber(c.req.query('limit') || '20', 1, 40, 20);
  try {
    const rows = await supabaseReadVisiblePosts(c, userId, { photoOnly: true, limit, order: 'trending' });
    const response = c.json(rows.map((p) => feedPostPayload(p, [], c.env)));
    response.headers.set('cache-control', 'no-store');
    return response;
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_discover_trending_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load trending posts.' }, 500);
  }
});
api.get('/discover/search', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'discover_search');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'discover_search', userId, 100, 60);
  if (limited) return limited;
  const q = cleanText(c.req.query('q'), 80);
  if (q.length < 2) return c.json({ posts: [], users: [] });
  const limit = clampNumber(c.req.query('limit') || '20', 1, 30, 20);
  try {
    const [posts, users] = await Promise.all([
      supabaseReadVisiblePosts(c, userId, { photoOnly: true, search: q, limit, order: 'newest' }),
      supabaseAdminQueryRows(c, 'app_users', {
        select: 'id,username,full_name,avatar_url,bio,city,is_private,is_verified,counts,profile,metadata',
        filters: {
          or: `(username.ilike.*${postgrestSearchTerm(q)}*,full_name.ilike.*${postgrestSearchTerm(q)}*)`,
        },
        limit: 10,
      }).catch(() => []),
    ]);
    return c.json({
      posts: posts.map((p) => feedPostPayload(p, [], c.env)),
      users: users
        .filter((user: any) => supabaseUserStatus(user) === 'active')
        .map((user: any) => safeUserPayload({
          id: user.id,
          username: user.username,
          full_name: user.full_name,
          profile_image: user.avatar_url,
          bio: user.bio,
          city: user.city,
          is_private: user.is_private,
          is_verified: user.is_verified,
          followers_count: Number(parseJsonObject(user.counts).followers_count || 0),
          following_count: Number(parseJsonObject(user.counts).following_count || 0),
          posts_count: Number(parseJsonObject(user.counts).posts_count || 0),
        })),
    });
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_discover_search_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not search Discover.' }, 500);
  }
});
api.get('/discover/suggested-users', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'suggested_users_read');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'suggested_users_read', userId, 120, 60);
  if (limited) return limited;
  try {
    const [viewerAliases, blockedIds, rows] = await Promise.all([
      supabaseRelatedInteractionUserIds(c, userId),
      supabaseBlockedUserIds(c, userId),
      supabaseAdminQueryRows(c, 'app_users', {
        select: SUPABASE_APP_USER_SELECT,
        order: 'created_at.desc',
        limit: 80,
      }),
    ]);
    const hiddenIds = new Set([...viewerAliases, ...blockedIds].filter(Boolean));
    const suggestions = rows
      .filter((row: any) => {
        const appUserId = publicId(row?.id, 120);
        const authUserId = isUuidText(row?.supabase_user_id);
        return appUserId && supabaseUserStatus(row) === 'active' && !hiddenIds.has(appUserId) && (!authUserId || !hiddenIds.has(authUserId));
      })
      .sort((a: any, b: any) => Number(parseJsonObject(b?.counts).followers_count || 0) - Number(parseJsonObject(a?.counts).followers_count || 0))
      .slice(0, 10)
      .map((row: any) => safeUserPayload(supabaseAppUserToLegacyUser(row)));
    return c.json(suggestions);
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_suggested_users_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load suggested users.' }, 500);
  }
});

// Pre-publish media moderation upload flow.
api.post('/media/upload-intent', authMiddleware, async (c) => {
  const bodyTooLarge = rejectLargeRequest(c, 24_000);
  if (bodyTooLarge) return bodyTooLarge;
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'media_upload_intent');
  if (supabaseRequired) return supabaseRequired;
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'media_upload_intent', userId, 80, 60);
  if (limited) return limited;
  const dailyLimited = await enforceRateLimit(c, 'media_upload_intent_daily', userId, 300, 86400);
  if (dailyLimited) return dailyLimited;

  const body: any = await c.req.json().catch(() => ({}));
  const validation = validatePrePublishUploadInput(c.env, body);
  if (!validation.ok) return c.json({ detail: validation.detail, code: validation.code }, validation.status as any);

  const accountId = cloudflareAccountId(c.env);
  const token = validation.mediaType === 'video' ? cloudflareStreamToken(c.env) : cloudflareImagesToken(c.env);
  if (!accountId || !token) {
    return c.json({ detail: validation.mediaType === 'video' ? 'Video upload is not configured.' : 'Image upload is not configured.' }, 503);
  }

  const sha256Hash = cleanText(body.sha256_hash || body.sha256Hash, 80).toLowerCase();
  if (sha256Hash && !/^[a-f0-9]{64}$/.test(sha256Hash)) {
    return c.json({ detail: 'Invalid upload checksum.', code: 'invalid_checksum' }, 400);
  }
  if (sha256Hash) {
    const duplicateCount = (await supabaseAdminQueryRows(c, 'app_media_assets', {
      select: 'id',
      filters: {
        user_id: postgrestEqFilter(userId),
        sha256_hash: postgrestEqFilter(sha256Hash),
        created_at: `gte.${new Date(Date.now() - 86400_000).toISOString()}`,
      },
      limit: 12,
    })).length;
    if (duplicateCount >= 12) {
      return c.json({ detail: 'Upload limit reached for this file. Try again later.', code: 'duplicate_upload_limit' }, 429);
    }
  }

  let uploadUrl = '';
  let storageKey = '';
  let storageProvider: 'images' | 'stream' = 'images';
  if (validation.mediaType === 'image') {
    const requireSignedURLs = cloudflareImagesRequireSignedUrls(c.env);
    const formData = new FormData();
    formData.append('requireSignedURLs', String(requireSignedURLs));
    formData.append('metadata', JSON.stringify({
      userId,
      filename: validation.filename,
      mimeType: validation.mimeType,
      moderation: 'pre_publish',
      source: 'captro_ios',
    }));
    const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/images/v2/direct_upload`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: formData,
    });
    const data: any = await res.json().catch(() => ({}));
    if (!data.success) {
      console.warn(JSON.stringify({ event: 'cf_images_upload_intent_failed', status: res.status, code: cleanText(data.errors?.[0]?.code, 80) }));
      return c.json({ detail: 'Could not prepare image upload.', code: 'upload_intent_failed' }, 502);
    }
    uploadUrl = String(data.result?.uploadURL || '');
    storageKey = cleanText(data.result?.id, 220);
    storageProvider = 'images';
  } else {
    const maxDurationSeconds = clampNumber(body.duration_seconds || body.durationSeconds || 60, 1, 60, 60);
    const requireSignedURLs = cloudflareStreamRequireSignedUrls(c.env);
    const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/direct_upload`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        maxDurationSeconds,
        creator: userId,
        requireSignedURLs,
        meta: { userId, moderation: 'pre_publish', filename: validation.filename },
      }),
    });
    const data: any = await res.json().catch(() => ({}));
    if (!data.success) {
      console.warn(JSON.stringify({ event: 'cf_stream_upload_intent_failed', status: res.status, code: cleanText(data.errors?.[0]?.code, 80) }));
      return c.json({ detail: 'Could not prepare video upload.', code: 'upload_intent_failed' }, 502);
    }
    uploadUrl = String(data.result?.uploadURL || '');
    storageKey = cleanText(data.result?.uid, 220);
    storageProvider = 'stream';
  }

  if (!uploadUrl || !storageKey) return c.json({ detail: 'Could not prepare upload.', code: 'upload_intent_failed' }, 502);
  const mediaId = uuid();
  const assetInput = {
    id: mediaId,
    userId,
    mediaType: validation.mediaType,
    storageProvider,
    storageKey,
    privateUrl: `${storageProvider}:${storageKey}`,
    mimeType: validation.mimeType,
    fileSize: validation.fileSize,
    sha256Hash,
    width: body.width == null ? null : clampNumber(body.width, 1, 10000, 0),
    height: body.height == null ? null : clampNumber(body.height, 1, 10000, 0),
    durationSeconds: body.duration_seconds == null && body.durationSeconds == null ? null : clampFloat(body.duration_seconds ?? body.durationSeconds, 0, 3600, 0),
    metadata: { source: 'media_upload_intent' },
  };
  await supabaseInsertMediaAsset(c, assetInput);
  await supabaseInsertModerationEvent(c, mediaId, 'upload_intent_created', {
    actorUserId: userId,
    reason: validation.mediaType,
    afterState: { storage_provider: storageProvider, mime_type: validation.mimeType, file_size: validation.fileSize },
    requestId: c.get?.('requestId') || '',
  });
  return c.json({
    media_id: mediaId,
    upload_url: uploadUrl,
    upload_method: storageProvider === 'stream' ? 'cloudflare_stream_direct' : 'cloudflare_images_direct',
    storage_provider: storageProvider,
    media_type: validation.mediaType,
    upload_status: 'uploading',
    moderation_status: 'uploading',
  }, 201);
});

api.post('/media/complete', authMiddleware, async (c) => {
  const bodyTooLarge = rejectLargeRequest(c, 32_000);
  if (bodyTooLarge) return bodyTooLarge;
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'media_upload_complete');
  if (supabaseRequired) return supabaseRequired;
  const userId = getUserId(c);
  const limited = await enforceRateLimit(c, 'media_upload_complete', userId, 120, 60);
  if (limited) return limited;
  const body: any = await c.req.json().catch(() => ({}));
  const mediaId = publicId(body.media_id || body.mediaId || body.id, 160);
  if (!mediaId) return c.json({ detail: 'Media id is required.', code: 'media_id_required' }, 400);

  const asset: any = await supabaseReadMediaAsset(c, mediaId, userId);
  if (!asset) return c.json({ detail: 'Upload not found.', code: 'media_not_found' }, 404);
  const currentStatus = normalizeMediaModerationStatus(asset.moderation_status);
  if (currentStatus === 'approved' || currentStatus === 'review_required' || currentStatus === 'rejected') {
    const currentPublicUrl = currentStatus === 'approved'
      ? (safeMediaReference(asset.public_url) || mediaAssetPublicUrl(c.env, asset))
      : '';
    return c.json({
      media_id: mediaId,
      upload_status: cleanText(asset.upload_status, 40),
      moderation_status: currentStatus,
      public_url: currentPublicUrl,
      rejection_code: cleanText(asset.rejection_code || '', 80),
      rejection_message: cleanText(asset.rejection_message || '', 240),
    });
  }

  const sha256Hash = cleanText(body.sha256_hash || body.sha256Hash || asset.sha256_hash, 80).toLowerCase();
  if (sha256Hash && !/^[a-f0-9]{64}$/.test(sha256Hash)) return c.json({ detail: 'Invalid upload checksum.', code: 'invalid_checksum' }, 400);
  const ts = now();
  const updatePatch = {
    upload_status: 'uploaded',
    moderation_status: 'pending_moderation',
    ...(sha256Hash ? { sha256_hash: sha256Hash } : {}),
    ...(Number(body.file_size || body.fileSize || 0) > 0 ? { file_size: Math.max(0, Math.round(Number(body.file_size || body.fileSize || 0))) } : {}),
    ...(body.width == null ? {} : { width: clampNumber(body.width, 1, 10000, 0) }),
    ...(body.height == null ? {} : { height: clampNumber(body.height, 1, 10000, 0) }),
    ...(body.duration_seconds == null && body.durationSeconds == null ? {} : { duration_seconds: clampFloat(body.duration_seconds ?? body.durationSeconds, 0, 3600, 0) }),
    updated_at: ts,
  };
  await supabaseAdminPatchRows(c, 'app_media_assets', { id: postgrestEqFilter(mediaId), user_id: postgrestEqFilter(userId) }, updatePatch);
  await supabaseInsertModerationEvent(c, mediaId, 'upload_completed', {
    actorUserId: userId,
    beforeState: { upload_status: asset.upload_status, moderation_status: asset.moderation_status },
    afterState: { upload_status: 'uploaded', moderation_status: 'pending_moderation' },
    requestId: c.get?.('requestId') || '',
  });
  const moderationCaption = cleanMultilineText(body.caption || body.content || body.title || '', 1000);
  const jobId = await createMediaModerationJob(c, mediaId, userId, moderationCaption, { enqueue: false });
  try {
    await processMediaModerationJob(c.env, { jobId, mediaId, userId, reason: 'upload_complete', caption: moderationCaption }, c.get?.('requestId') || '');
  } catch (error: any) {
    console.warn(JSON.stringify({
      event: 'media_moderation_complete_inline_failed',
      code: getErrorCode(error).slice(0, 180),
      media_id: mediaId,
    }));
  }
  const latest: any = await supabaseReadMediaAsset(c, mediaId, userId);
  const latestStatus = normalizeMediaModerationStatus(latest?.moderation_status);
  const latestUploadStatus = cleanText(latest?.upload_status, 40) || 'uploaded';
  const latestPublicUrl = latestStatus === 'approved'
    ? (safeMediaReference(latest?.public_url) || mediaAssetPublicUrl(c.env, latest))
    : '';
  const latestMessage = latestStatus === 'approved'
    ? ''
    : latestStatus === 'review_required'
      ? 'This upload needs a quick safety review before it can be posted.'
      : latestStatus === 'rejected'
        ? "This upload can't be posted because it may break Captro's safety rules."
        : latestStatus === 'failed'
          ? (cleanText(latest?.rejection_message, 240) || 'This upload could not be checked. Please try again.')
          : 'Checking your upload before posting...';
  return c.json({
    media_id: mediaId,
    job_id: jobId,
    upload_status: latestUploadStatus,
    moderation_status: latestStatus,
    public_url: latestPublicUrl,
    rejection_code: cleanText(latest?.rejection_code || '', 80),
    rejection_message: cleanText(latest?.rejection_message || '', 240),
    message: latestMessage,
  });
});

api.get('/media/:mediaId/status', authMiddleware, async (c) => {
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'media_status_read');
  if (supabaseRequired) return supabaseRequired;
  const userId = getUserId(c);
  const mediaId = publicId(c.req.param('mediaId'), 160);
  const asset: any = await supabaseReadMediaAsset(c, mediaId, userId);
  if (!asset) return c.json({ detail: 'Upload not found.' }, 404);
  return c.json({
    ...asset,
    public_url: normalizeMediaModerationStatus(asset.moderation_status) === 'approved'
      ? (safeMediaReference(asset.public_url) || mediaAssetPublicUrl(c.env, asset))
      : '',
  });
});

// Uploads (Cloudflare Images + Stream direct upload)
api.post('/upload/image-direct', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'image_direct_upload');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'upload_image_direct', userId, 60, 60);
  if (limited) return limited;
  const dailyLimited = await enforceRateLimit(c, 'upload_image_direct_daily', userId, 250, 86400);
  if (dailyLimited) return dailyLimited;
  const accountId = cloudflareAccountId(c.env);
  const token = cloudflareImagesToken(c.env);
  if (!accountId || !token) {
    return c.json({ detail: 'Image upload is not configured.' }, 503);
  }
  const body: any = await c.req.json().catch(() => ({}));
  const filename = cleanText(body.filename || body.file_name || 'captro-upload.jpg', 180);
  const mimeType = normalizedContentType(body.mime_type || body.mimeType || 'image/jpeg');
  if (mimeType && (!ALLOWED_IMAGE_TYPES.has(mimeType) || !extensionAllowed(filename, ALLOWED_IMAGE_EXTENSIONS))) {
    return c.json({ detail: 'Unsupported image type. Use JPG, PNG, or WebP.' }, 400);
  }
  const formData = new FormData();
  const requireSignedURLs = cloudflareImagesRequireSignedUrls(c.env);
  formData.append('requireSignedURLs', String(requireSignedURLs));
  formData.append('metadata', JSON.stringify({ userId, filename, mimeType: mimeType || 'image/jpeg', source: 'captro_ios', moderation: 'pre_publish' }));
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/images/v2/direct_upload`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: formData,
  });
  const data: any = await res.json();
  if (!data.success) {
    console.warn('CF Images direct upload setup failed:', res.status, data.errors?.[0]?.code || 'cloudflare_images_error');
    return c.json({ detail: 'Failed to get upload URL' }, 500);
  }
  const imageId = cleanText(data.result?.id, 180);
  const mediaId = uuid();
  await supabaseInsertMediaAsset(c, {
    id: mediaId,
    userId,
    mediaType: 'image',
    storageProvider: 'images',
    storageKey: imageId,
    privateUrl: `images:${imageId}`,
    mimeType: mimeType || 'image/jpeg',
    metadata: { source: 'legacy_image_direct' },
  });
  await supabaseInsertModerationEvent(c, mediaId, 'upload_intent_created', {
    actorUserId: userId,
    reason: 'legacy_image_direct',
    afterState: { storage_provider: 'images', mime_type: mimeType || 'image/jpeg' },
    requestId: c.get?.('requestId') || '',
  });
  return c.json({
    upload_url: data.result.uploadURL,
    media_id: mediaId,
    image_id: imageId,
    id: imageId,
    url: '',
    moderation_status: 'uploading',
    requires_moderation: true,
    source: 'cloudflare_images_direct',
  });
});

api.post('/upload/video-direct', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'video_direct_upload');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'upload_video_direct', userId, 40, 60);
  if (limited) return limited;
  const dailyLimited = await enforceRateLimit(c, 'upload_video_direct_daily', userId, 100, 86400);
  if (dailyLimited) return dailyLimited;
  const accountId = cloudflareAccountId(c.env);
  const token = cloudflareStreamToken(c.env);
  if (!accountId || !token) {
    return c.json({ detail: 'Video upload is not configured.' }, 503);
  }
  const requireSignedURLs = cloudflareStreamRequireSignedUrls(c.env);
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/direct_upload`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ maxDurationSeconds: 60, creator: userId, requireSignedURLs, meta: { userId, moderation: 'pre_publish' } }) });
  const data: any = await res.json();
  if (!data.success) return c.json({ detail: 'Failed to get upload URL' }, 500);
  const videoUid = cleanText(data.result.uid, 220);
  const mediaId = uuid();
  await supabaseInsertMediaAsset(c, {
    id: mediaId,
    userId,
    mediaType: 'video',
    storageProvider: 'stream',
    storageKey: videoUid,
    privateUrl: `stream:${videoUid}`,
    mimeType: 'video/mp4',
    metadata: { source: 'legacy_video_direct' },
  });
  await supabaseInsertModerationEvent(c, mediaId, 'upload_intent_created', {
    actorUserId: userId,
    reason: 'legacy_video_direct',
    afterState: { storage_provider: 'stream' },
    requestId: c.get?.('requestId') || '',
  });
  return c.json({ upload_url: data.result.uploadURL, video_uid: videoUid, media_id: mediaId, moderation_status: 'uploading', requires_moderation: true });
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
      'metadata[source]': 'captro',
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
      if (source === 'captro-premium' || source === 'flames-up-premium' || object?.mode === 'subscription') {
        await activatePremiumFromCheckoutSession(c, object);
      } else {
        await completeCoinPurchaseFromSession(c, object);
      }
    } else if (event.type === 'checkout.session.expired') {
      const source = cleanText(object?.metadata?.source, 80);
      if (source === 'captro-premium' || source === 'flames-up-premium' || object?.mode === 'subscription') {
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
// Discover posts (publisher content)
api.get('/discover/feed', authMiddleware, async (c) => {
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'discover_feed_read');
  if (supabaseRequired) return supabaseRequired;
  const category = c.req.query('category') || 'all';
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '30', 1, 60, 30);
  const normalizedCategory = normalizeDiscoverCategory(category, true);
  if (!normalizedCategory) return c.json({ detail: 'Unknown Discover category.' }, 400);
  try {
    const userId = getUserId(c);
    const rows = await supabaseReadVisiblePosts(c, userId, { category: normalizedCategory, limit, offset: skip, order: 'newest' });
    const response = c.json(rows.map((p) => feedPostPayload(p, [], c.env)));
    response.headers.set('cache-control', 'no-store');
    return response;
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_discover_feed_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load Discover.' }, 500);
  }
});

api.get('/discover/categories', async (c) => {
  return c.json([
    { id: 'all', name: 'All', icon: 'square.grid.2x2' },
    { id: 'photography', name: 'Photography', icon: 'camera' },
    { id: 'outdoors', name: 'Outdoors', icon: 'leaf' },
    { id: 'art', name: 'Art', icon: 'paintpalette' },
    { id: 'nightlife', name: 'Nightlife', icon: 'moon.stars' },
    { id: 'outfits', name: 'Outfits', icon: 'tshirt' },
    { id: 'events', name: 'Events', icon: 'calendar' },
  ]);
});

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
  const userId = getUserId(c);
  if (!userId) return null;
  if (!supabasePrimaryConfigured(c)) return null;

  const row = await getSupabaseAppUserRowByAnyId(c, userId);
  if (!row) return null;
  const legacy = supabaseAppUserToLegacyUser(row);
  if (['banned', 'deleted', 'deletion_pending'].includes(String(legacy.status || 'active'))) return null;

  const metadata = parseJsonObject(row?.metadata);
  let role = normalizeAdminRole((metadata as any).admin_role || (metadata as any).role);
  const candidateIds = Array.from(new Set([
    publicId(row?.id, 120),
    isUuidText(row?.supabase_user_id) || '',
    publicId(userId, 120),
  ].filter(Boolean)));
  if (candidateIds.length) {
    const roleRows = await supabaseAdminQueryRows(c, 'app_admin_roles', {
      select: 'user_id,role',
      filters: { user_id: postgrestInFilter(candidateIds) },
      limit: 10,
    }).catch((error: any) => {
      console.warn(JSON.stringify({ event: 'supabase_admin_role_lookup_failed', code: getErrorCode(error).slice(0, 180) }));
      return [];
    });
    role = normalizeAdminRole(roleRows.find((roleRow: any) => normalizeAdminRole(roleRow?.role))?.role) || role;
  }
  if (isOwnerUsername(c, legacy.username) || isOwnerEmail(c, legacy.email)) role = 'owner';
  if (!role && ((metadata as any).is_admin === true || Number((metadata as any).is_admin || 0) === 1)) role = 'admin';
  if (!role) return null;
  return { userId: publicId(row.id, 120), role, user: { ...legacy, admin_role: role } };
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
  const ts = now();
  if (!supabasePrimaryConfigured(c)) throw new Error('SUPABASE_PRIMARY_REQUIRED');
  const admin = await getAdminContext(c);
  const actorId = publicId(admin?.userId || adminId, 120);
  const actorRole = normalizeAdminRole(admin?.role) || 'admin';
  const requestId = cleanText(c.get?.('requestId') || c.req.header('X-Request-ID') || '', 120);
  const cleanActionType = cleanText(actionType, 80);
  const cleanTargetType = cleanText(targetType, 60);
  const cleanTargetId = publicId(targetId, 160);
  const targetUserId = cleanText((details || {}).target_user_id || '', 120);
  const reason = cleanMultilineText((details || {}).reason || '', 800);
  const note = cleanMultilineText((details || {}).note || (details || {}).admin_notes || '', 1000);
  await Promise.all([
    supabaseAdminUpsert(c, 'app_audit_logs', [{
      id: uuid(),
      actor_admin_user_id: actorId,
      actor_role: actorRole,
      action_type: cleanActionType,
      target_type: cleanTargetType,
      target_id: cleanTargetId,
      target_user_id: targetUserId,
      reason,
      internal_note: note,
      before_state: {},
      after_state: scrubLogMetadata(details || {}),
      request_id: requestId,
      metadata: { source: 'cloudflare_worker_governance' },
      legacy_created_at: ts,
      created_at: ts,
    }], 'id'),
    supabaseAdminUpsert(c, 'app_moderation_actions', [{
      id: uuid(),
      actor_admin_user_id: actorId,
      actor_role: actorRole,
      action_type: cleanActionType,
      target_type: cleanTargetType,
      target_id: cleanTargetId,
      target_user_id: targetUserId,
      reason,
      note,
      metadata: { request_id: requestId, source: 'cloudflare_worker_governance' },
      legacy_created_at: ts,
      created_at: ts,
      updated_at: ts,
    }], 'id'),
  ]);
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
  const ts = now();
  const reason = cleanMultilineText(input.reason || '', 800);
  const note = cleanMultilineText(input.note || '', 1000);
  const targetUserId = publicId(input.targetUserId || '', 120);
  const requestId = cleanText(c.get?.('requestId') || c.req.header('X-Request-ID') || '', 120);
  const actionType = cleanText(input.actionType, 80);
  const targetType = cleanText(input.targetType, 60);
  const targetId = publicId(input.targetId, 160);

  if (!supabasePrimaryConfigured(c)) throw new Error('SUPABASE_PRIMARY_REQUIRED');
  await Promise.all([
    supabaseAdminUpsert(c, 'app_audit_logs', [{
      id: uuid(),
      actor_admin_user_id: admin.userId,
      actor_role: admin.role,
      action_type: actionType,
      target_type: targetType,
      target_id: targetId,
      target_user_id: targetUserId,
      reason,
      internal_note: note,
      before_state: scrubLogMetadata(input.beforeState || {}),
      after_state: scrubLogMetadata(input.afterState || {}),
      request_id: requestId,
      metadata: { source: 'cloudflare_worker_primary' },
      legacy_created_at: ts,
      created_at: ts,
    }], 'id'),
    supabaseAdminUpsert(c, 'app_moderation_actions', [{
      id: uuid(),
      actor_admin_user_id: admin.userId,
      actor_role: admin.role,
      action_type: actionType,
      target_type: targetType,
      target_id: targetId,
      target_user_id: targetUserId,
      reason,
      note,
      metadata: { request_id: requestId, source: 'cloudflare_worker_primary' },
      legacy_created_at: ts,
      created_at: ts,
      updated_at: ts,
    }], 'id'),
  ]);
}

async function requireAdminWriteRateLimit(c: any, admin: AdminContext, bucket = 'admin_write') {
  return enforceRateLimit(c, bucket, admin.userId, 80, 60);
}

function normalizeRestrictionType(value: unknown): string {
  const type = cleanText(value || 'all', 60).toLowerCase().replace(/[\s-]+/g, '_');
  return ['all', 'posting', 'commenting', 'messaging', 'discover', 'handshake'].includes(type) ? type : 'all';
}

function supabaseUserRestrictionsFromMetadata(metadataValue: unknown): any[] {
  const metadata = parseJsonObject(metadataValue);
  const restrictions = Array.isArray((metadata as any).restrictions) ? (metadata as any).restrictions : [];
  return restrictions
    .map((restriction: any) => ({
      id: publicId(restriction?.id || '', 120) || uuid(),
      user_id: publicId(restriction?.user_id || '', 120),
      restriction_type: normalizeRestrictionType(restriction?.restriction_type || restriction?.type),
      reason: cleanMultilineText(restriction?.reason, 500),
      note: cleanMultilineText(restriction?.note, 500),
      starts_at: cleanText(restriction?.starts_at || restriction?.created_at || '', 80),
      ends_at: cleanText(restriction?.ends_at || '', 80),
      created_by: publicId(restriction?.created_by || '', 120),
      created_at: cleanText(restriction?.created_at || restriction?.starts_at || '', 80),
    }))
    .filter((restriction: any) => restriction.reason || restriction.ends_at || restriction.created_at)
    .sort((a: any, b: any) => (Date.parse(b.created_at || b.starts_at || '') || 0) - (Date.parse(a.created_at || a.starts_at || '') || 0))
    .slice(0, 100);
}

async function userHasActiveRestriction(c: any, userId: string, type: 'posting' | 'commenting' | 'messaging' | 'discover' | 'handshake'): Promise<boolean> {
  if (supabasePrimaryConfigured(c)) {
    const row = await getSupabaseAppUserRowByAnyId(c, userId);
    const restrictions = supabaseUserRestrictionsFromMetadata(row?.metadata);
    const currentTime = Date.now();
    return restrictions.some((restriction: any) => {
      const restrictionType = normalizeRestrictionType(restriction?.restriction_type || restriction?.type);
      if (restrictionType !== 'all' && restrictionType !== type) return false;
      const startsAt = Date.parse(String(restriction?.starts_at || restriction?.created_at || ''));
      const endsAt = Date.parse(String(restriction?.ends_at || ''));
      return (!Number.isFinite(startsAt) || startsAt <= currentTime)
        && (!Number.isFinite(endsAt) || endsAt > currentTime);
    });
  }
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

function adminSupabaseUserPayload(row: any, role: AdminRole, reportCount = 0) {
  const legacy = supabaseAppUserToLegacyUser(row);
  const metadata = parseJsonObject(row?.metadata);
  return adminUserPayload({
    ...legacy,
    report_count: reportCount,
    warning_count: Number((metadata as any).warning_count || 0),
    suspended_until: cleanText((metadata as any).suspended_until, 80),
    banned_at: cleanText((metadata as any).banned_at, 80),
    ban_reason: cleanMultilineText((metadata as any).ban_reason, 500),
  }, role);
}

async function supabaseAdminReportCountsForUsers(c: any, userIds: string[]): Promise<Map<string, number>> {
  const ids = Array.from(new Set(userIds.map((value) => publicId(value, 120)).filter(Boolean)));
  const counts = new Map<string, number>();
  if (!ids.length) return counts;
  const rows = await supabaseAdminQueryRows(c, 'app_reports', {
    select: 'target_owner_user_id',
    filters: { target_owner_user_id: postgrestInFilter(ids) },
    limit: Math.max(100, ids.length * 100),
  }).catch((error: any) => {
    console.warn(JSON.stringify({ event: 'supabase_admin_user_report_counts_failed', code: getErrorCode(error).slice(0, 180) }));
    return [];
  });
  for (const row of rows) {
    const id = publicId(row?.target_owner_user_id, 120);
    if (id) counts.set(id, (counts.get(id) || 0) + 1);
  }
  return counts;
}

async function supabaseAdminUserRows(c: any, input: { search?: string; status?: string; limit: number; offset: number }) {
  const search = cleanText(input.search || '', 120).toLowerCase();
  const status = cleanText(input.status || '', 40).toLowerCase();
  const rowLimit = Math.min(500, Math.max(input.limit + input.offset + 50, input.limit));
  const rows = await supabaseAdminQueryRows(c, 'app_users', {
    select: SUPABASE_APP_USER_SELECT,
    order: 'created_at.desc',
    limit: rowLimit,
  });
  return rows
    .filter((row) => {
      const legacy = supabaseAppUserToLegacyUser(row);
      if (status && status !== 'all' && cleanText(legacy.status || 'active', 40).toLowerCase() !== status) return false;
      if (!search) return true;
      return [
        legacy.id,
        legacy.username,
        legacy.full_name,
        legacy.email,
      ].some((value) => String(value || '').toLowerCase().includes(search));
    })
    .slice(input.offset, input.offset + input.limit);
}

async function supabasePatchUserModerationMetadata(c: any, targetUserId: string, mutate: (metadata: Record<string, any>, row: any) => Record<string, any>) {
  const row = await getSupabaseAppUserRowByAnyId(c, targetUserId);
  if (!row) return { row: null, before: null, metadata: null };
  const before = supabaseAppUserToLegacyUser(row);
  const metadata = mutate(parseJsonObject(row?.metadata) as Record<string, any>, row);
  await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(publicId(row.id, 120)) }, {
    metadata: scrubLogMetadata(metadata),
    updated_at: now(),
  });
  return { row, before, metadata };
}

function adminPostPayload(row: any, env: Env) {
  const mediaUrls = sanitizeMediaReferences(row.images, row.image);
  const mediaTypes = parseJsonArray(row.media_types);
  const dimensions = parseJsonArray(row.media_dimensions);
  const primaryCategory = (normalizeDiscoverCategory(row.primary_category || row.category || row.post_type, false) || DEFAULT_DISCOVER_CATEGORY) as DiscoverCategory;
  const categoryConfidence = clampFloat(row.category_confidence, 0, 1, 0);
  const tags = sanitizeAutoCategoryTags(row.tags_json);
  const categorySignals = parseJsonObject(row.category_signals_json);
  const categoryScores = normalizeCategoryScoresPayload(row.category_scores_json || (categorySignals as any).category_scores);
  const secondaryCategories = normalizeSecondaryCategoriesPayload(row.secondary_categories_json, primaryCategory);
  const thumbnailVariant = env.CLOUDFLARE_IMAGES_THUMBNAIL_VARIANT || '';
  const feedVariant = env.CLOUDFLARE_IMAGES_FEED_VARIANT || '';
  const normalizedTypes = mediaTypes.length ? mediaTypes : mediaUrls.map((url) => isVideoMediaUrl(url) ? 'video' : 'image');
  const normalizedDimensions = feedMediaDimensions(mediaUrls, normalizedTypes, dimensions);
  const media = mediaUrls.map((url, index) => {
    const mediaType = String(normalizedTypes[index] || 'image').toLowerCase().includes('video') || isVideoMediaUrl(url) ? 'video' : 'image';
    const feedUrl = mediaType === 'video' ? streamPlaybackUrl(url) : feedDeliveryUrl(url, mediaType, feedVariant, env);
    const thumbnailUrl = mediaType === 'video'
      ? streamThumbnailUrl(url)
      : posterDeliveryUrl(url, mediaType, thumbnailVariant, env);
    const original = normalizedDimensions[index] || dimensions[index] || {};
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
      original_width: original.original_width || null,
      original_height: original.original_height || null,
      original_aspect_ratio: original.original_aspect_ratio || null,
      feed_width: original.feed_width || width,
      feed_height: original.feed_height || height,
      feed_aspect_ratio: original.feed_aspect_ratio || aspectRatio,
      display_aspect_ratio: original.display_aspect_ratio || aspectRatio,
      format: original.format || supportedFeedMediaVariant(original).format,
      crop_mode: original.crop_mode || 'center_crop',
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
    secondary_categories: secondaryCategories,
    category_scores: categoryScores,
    detected_objects: sanitizeAutoCategoryTags(row.detected_objects_json || (categorySignals as any).detected_objects),
    detected_scene: cleanText(row.detected_scene || (categorySignals as any).detected_scene, 80),
    place_type: cleanText(row.place_type || (categorySignals as any).place_type, 120),
    user_selected_category: normalizeDiscoverCategory(row.user_selected_category || (categorySignals as any).user_selected_category, false),
    caption_keywords: sanitizeAutoCategoryTags(row.caption_keywords_json || (categorySignals as any).caption_keywords),
    category_debug: {
      reasons: (categorySignals as any).debug_reasons || {},
      summary: DISCOVER_CATEGORIES
        .filter((category) => categoryScores[category] > 0)
        .sort((a, b) => categoryScores[b] - categoryScores[a])
        .slice(0, 5)
        .map((category) => `${category} ${Math.round(categoryScores[category])} because ${(((categorySignals as any).debug_reasons || {})[category] || []).slice(0, 3).join(' + ') || 'saved category score'}`),
    },
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

function adminMediaModerationPayload(row: any, env: Env) {
  const result = row.result_raw_result ? parseJsonObject(row.result_raw_result) : {};
  const reasons = parseJsonArray(row.result_reasons);
  return {
    id: row.id,
    user_id: row.user_id,
    user: {
      id: row.user_id,
      username: publicUsernameFor({ username: row.user_username }),
      full_name: cleanText(row.user_full_name, 120),
      email: publicUserEmail(row.user_email),
      profile_image: safeMediaReference(row.user_profile_image),
    },
    post_id: row.post_id || null,
    media_type: normalizeMediaAssetType(row.media_type) || 'image',
    storage_provider: cleanText(row.storage_provider, 40),
    storage_key: cleanText(row.storage_key, 220),
    preview_url: mediaAssetPreviewUrl(env, row),
    public_url: normalizeMediaModerationStatus(row.moderation_status) === 'approved' ? (safeMediaReference(row.public_url) || mediaAssetPublicUrl(env, row)) : '',
    private_reference: cleanText(row.private_url, 260),
    mime_type: cleanText(row.mime_type, 120),
    file_size: Number(row.file_size || 0),
    sha256_hash: cleanText(row.sha256_hash, 80),
    width: row.width == null ? null : Number(row.width),
    height: row.height == null ? null : Number(row.height),
    duration_seconds: row.duration_seconds == null ? null : Number(row.duration_seconds),
    upload_status: cleanText(row.upload_status, 40),
    moderation_status: normalizeMediaModerationStatus(row.moderation_status),
    content_credentials: {
      has_content_credentials: row.has_content_credentials === true || Number(row.has_content_credentials || 0) === 1,
      c2pa_verified: row.c2pa_verified === true || Number(row.c2pa_verified || 0) === 1,
      c2pa_creator: cleanText(row.c2pa_creator, 180),
      c2pa_created_at: row.c2pa_created_at || null,
      c2pa_ai_used: row.c2pa_ai_used === true || Number(row.c2pa_ai_used || 0) === 1,
      c2pa_edit_history_summary: cleanMultilineText(row.c2pa_edit_history_summary, 500),
      media_origin_status: normalizeMediaOriginStatus(row.media_origin_status),
      metadata: scrubLogMetadata(parseJsonObject(row.c2pa_metadata)),
    },
    rejection_code: cleanText(row.rejection_code, 120),
    rejection_message: cleanMultilineText(row.rejection_message, 500),
    scores: {
      adult_explicit_score: clampFloat(row.adult_explicit_score, 0, 1, 0),
      nudity_score: clampFloat(row.nudity_score, 0, 1, 0),
      sexual_context_score: clampFloat(row.sexual_context_score, 0, 1, 0),
      sexual_solicitation_score: clampFloat(row.sexual_solicitation_score, 0, 1, 0),
      minor_safety_risk_score: clampFloat(row.minor_safety_risk_score, 0, 1, 0),
      violence_score: clampFloat(row.violence_score, 0, 1, 0),
      gore_score: clampFloat(row.gore_score, 0, 1, 0),
      weapon_score: clampFloat(row.weapon_score, 0, 1, 0),
      hate_symbol_score: clampFloat(row.hate_symbol_score, 0, 1, 0),
      ai_generated_likelihood: clampFloat(row.ai_generated_likelihood, 0, 1, 0),
      spam_scam_score: clampFloat(row.spam_scam_score, 0, 1, 0),
      link_risk_score: clampFloat(row.link_risk_score, 0, 1, 0),
      confidence: clampFloat(row.confidence, 0, 1, 0),
      malware_status: cleanText(row.malware_status || 'unknown', 40),
    },
    model_name: cleanText(row.model_name, 160),
    decision: cleanText(row.decision, 40),
    reasons,
    raw_result: scrubLogMetadata(result),
    caption: cleanMultilineText(row.post_content || row.post_title || '', 1000),
    created_at: row.created_at || '',
    updated_at: row.updated_at || '',
    result_created_at: row.result_created_at || null,
  };
}

async function supabaseAdminMediaModerationRows(c: any, input: {
  status?: MediaModerationStatus | '';
  mediaType?: CaptroMediaType | '';
  search?: string;
  limit: number;
  offset: number;
}): Promise<any[]> {
  const filters: Record<string, string> = {};
  if (input.status) {
    filters.moderation_status = postgrestEqFilter(input.status);
  } else {
    filters.moderation_status = postgrestInFilter(['review_required', 'failed']);
  }
  if (input.mediaType) filters.media_type = postgrestEqFilter(input.mediaType);
  const cleanSearch = String(input.search || '').replace(/^%|%$/g, '').trim().toLowerCase();
  if (cleanSearch) {
    const pattern = `*${cleanSearch.replace(/[*,()]/g, '')}*`;
    filters.or = `(id.ilike.${pattern},user_id.ilike.${pattern},sha256_hash.ilike.${pattern})`;
  }
  const assets = (await supabaseAdminQueryRows(c, 'app_media_assets', {
    select: '*',
    filters,
    order: 'created_at.desc',
    limit: input.limit,
    offset: input.offset,
  })).map(supabaseMediaAssetToLegacy);
  if (!assets.length) return [];

  const mediaIds = Array.from(new Set(assets.map((row) => publicId(row.id, 160)).filter(Boolean)));
  const userIds = Array.from(new Set(assets.map((row) => publicId(row.user_id, 120)).filter(Boolean)));
  const postIds = Array.from(new Set(assets.map((row) => publicId(row.legacy_post_id || row.post_id, 160)).filter(Boolean)));
  const [results, users, posts] = await Promise.all([
    mediaIds.length ? supabaseAdminQueryRows(c, 'app_moderation_results', {
      select: '*',
      filters: { media_id: postgrestInFilter(mediaIds) },
      order: 'created_at.desc',
      limit: Math.max(100, mediaIds.length * 6),
    }) : Promise.resolve([]),
    userIds.length ? supabaseAdminQueryRows(c, 'app_users', {
      select: 'id,email,username,full_name,avatar_url',
      filters: { id: postgrestInFilter(userIds) },
      limit: userIds.length,
    }) : Promise.resolve([]),
    postIds.length ? supabaseAdminQueryRows(c, 'app_posts', {
      select: 'legacy_post_id,title,content',
      filters: { legacy_post_id: postgrestInFilter(postIds) },
      limit: postIds.length,
    }) : Promise.resolve([]),
  ]);

  const latestResultByMedia = new Map<string, any>();
  for (const result of results) {
    const mediaId = publicId(result.media_id, 160);
    if (mediaId && !latestResultByMedia.has(mediaId)) latestResultByMedia.set(mediaId, result);
  }
  const userById = new Map(users.map((user: any) => [publicId(user.id, 120), user]));
  const postById = new Map(posts.map((post: any) => [publicId(post.legacy_post_id, 160), post]));

  return assets.map((asset) => {
    const result = latestResultByMedia.get(publicId(asset.id, 160)) || {};
    const user = userById.get(publicId(asset.user_id, 120)) || {};
    const post = postById.get(publicId(asset.legacy_post_id || asset.post_id, 160)) || {};
    return {
      ...asset,
      post_id: asset.legacy_post_id || asset.post_id || null,
      user_username: user.username,
      user_full_name: user.full_name,
      user_email: user.email,
      user_profile_image: user.avatar_url,
      post_title: post.title,
      post_content: post.content,
      model_name: result.model_name,
      adult_explicit_score: result.adult_explicit_score,
      nudity_score: result.nudity_score,
      sexual_context_score: result.sexual_context_score,
      sexual_solicitation_score: result.sexual_solicitation_score,
      minor_safety_risk_score: result.minor_safety_risk_score,
      violence_score: result.violence_score,
      gore_score: result.gore_score,
      weapon_score: result.weapon_score,
      hate_symbol_score: result.hate_symbol_score,
      ai_generated_likelihood: result.ai_generated_likelihood,
      spam_scam_score: result.spam_scam_score,
      malware_status: result.malware_status,
      link_risk_score: result.link_risk_score,
      confidence: result.confidence,
      decision: result.decision,
      result_reasons: JSON.stringify(result.reasons || []),
      result_raw_result: JSON.stringify(result.raw_result || {}),
      result_created_at: result.created_at || null,
    };
  });
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

async function supabaseAdminCommentPayloads(c: any, rows: any[]): Promise<any[]> {
  const cleanRows = Array.isArray(rows) ? rows.filter(Boolean) : [];
  if (!cleanRows.length) return [];
  const authorIds = cleanRows
    .flatMap((row) => [publicId(row?.app_user_id, 120), isUuidText(row?.user_id) || ''])
    .filter(Boolean);
  const postIds = Array.from(new Set(cleanRows.map((row) => publicId(row?.legacy_post_id, 120)).filter(Boolean)));
  const [authorMap, postRows] = await Promise.all([
    supabaseUsersByAnyIds(c, authorIds),
    postIds.length ? supabaseAdminQueryRows(c, 'app_posts', {
      select: 'legacy_post_id,app_user_id,user_id',
      filters: { legacy_post_id: postgrestInFilter(postIds) },
      limit: Math.max(1, postIds.length),
    }).catch((error: any) => {
      console.warn(JSON.stringify({ event: 'supabase_admin_comment_posts_failed', code: getErrorCode(error).slice(0, 180) }));
      return [];
    }) : Promise.resolve([]),
  ]);
  const postMap = new Map(postRows.map((row: any) => [publicId(row?.legacy_post_id, 120), row]));
  return cleanRows.map((row) => {
    const metadata = parseJsonObject(row?.metadata);
    const appUserId = publicId(row?.app_user_id, 120);
    const author = authorMap.get(appUserId) || authorMap.get(isUuidText(row?.user_id) || '') || {};
    const post = postMap.get(publicId(row?.legacy_post_id, 120)) || {};
    return adminCommentPayload({
      id: publicId(row?.legacy_comment_id || row?.id, 120),
      user_id: appUserId || isUuidText(row?.user_id) || '',
      post_id: publicId(row?.legacy_post_id || row?.post_id, 120),
      parent_id: publicId((metadata as any).parent_legacy_id || row?.parent_id, 120),
      content: cleanMultilineText(row?.body, 1200),
      status: cleanText(row?.status || 'active', 40),
      removed_at: cleanText((metadata as any).removed_at, 80) || null,
      removed_reason: cleanMultilineText((metadata as any).removed_reason, 500),
      hidden_at: cleanText((metadata as any).hidden_at, 80) || null,
      hidden_by_user_id: publicId((metadata as any).hidden_by_user_id, 120),
      likes_count: Number((metadata as any).likes_count || 0),
      user_username: author?.username,
      user_full_name: author?.full_name,
      user_profile_image: author?.avatar_url,
      post_user_id: publicId(post?.app_user_id || post?.user_id || (metadata as any).post_user_id, 120),
      created_at: row?.legacy_created_at || row?.created_at,
      updated_at: row?.updated_at || row?.created_at,
    });
  });
}

function supabaseAdminCommentPayloadMatchesSearch(payload: any, search: string): boolean {
  const query = cleanText(search, 120).toLowerCase();
  if (!query) return true;
  return [
    payload?.id,
    payload?.post_id,
    payload?.content,
    payload?.author?.id,
    payload?.author?.username,
    payload?.author?.full_name,
  ].some((value) => String(value || '').toLowerCase().includes(query));
}

function reportTargetType(row: any): string {
  return normalizeReportTargetType(row?.target_type || row?.reported_type || row?.report_type || 'other');
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
    reported_id: row.reported_id || row.target_id,
    target_type: type,
    target_id: row.target_id || row.reported_id,
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

async function supabaseEnrichAdminReportRows(c: any, reports: any[]): Promise<any[]> {
  if (!reports.length) return [];
  const reporterIds = reports.map((row) => publicId(row?.reporter_id, 120)).filter(Boolean);
  const ownerIds = reports.map((row) => publicId(row?.target_owner_user_id, 120)).filter(Boolean);
  const postIds = new Set<string>();
  const commentIds = new Set<string>();
  const messageIds = new Set<string>();

  for (const report of reports) {
    const targetType = normalizeReportTargetType(report?.target_type);
    const targetId = publicId(report?.target_id, 160);
    const metadata = parseJsonObject(report?.metadata);
    const contentId = publicId((metadata as any).content_id, 160);
    if ((targetType === 'post' || targetType === 'discover_post') && targetId) postIds.add(targetId);
    if (contentId) postIds.add(contentId);
    if (targetType === 'comment' && targetId) commentIds.add(targetId);
    if (targetType === 'message' && targetId) messageIds.add(targetId);
  }

  const [users, posts, comments, messages] = await Promise.all([
    supabaseUsersByAnyIds(c, [...reporterIds, ...ownerIds]),
    postIds.size
      ? supabaseAdminQueryRows(c, 'app_posts', {
        select: SUPABASE_APP_POST_SELECT,
        filters: { legacy_post_id: postgrestInFilter(Array.from(postIds)) },
        limit: Math.max(1, postIds.size),
      }).catch((error: any) => {
        console.warn(JSON.stringify({ event: 'supabase_admin_report_posts_failed', code: getErrorCode(error).slice(0, 180) }));
        return [];
      })
      : Promise.resolve([]),
    commentIds.size
      ? supabaseAdminQueryRows(c, 'post_comments', {
        select: 'legacy_comment_id,legacy_post_id,app_user_id,user_id,body,status,created_at,legacy_created_at',
        filters: { legacy_comment_id: postgrestInFilter(Array.from(commentIds)) },
        limit: Math.max(1, commentIds.size),
      }).catch((error: any) => {
        console.warn(JSON.stringify({ event: 'supabase_admin_report_comments_failed', code: getErrorCode(error).slice(0, 180) }));
        return [];
      })
      : Promise.resolve([]),
    messageIds.size
      ? supabaseAdminQueryRows(c, 'app_messages', {
        select: 'id,sender_id,receiver_id,body,media_url,media_type,status,created_at,legacy_created_at',
        filters: { id: postgrestInFilter(Array.from(messageIds)) },
        limit: Math.max(1, messageIds.size),
      }).catch((error: any) => {
        console.warn(JSON.stringify({ event: 'supabase_admin_report_messages_failed', code: getErrorCode(error).slice(0, 180) }));
        return [];
      })
      : Promise.resolve([]),
  ]);

  const postMap = new Map(posts.map((row: any) => [publicId(row?.legacy_post_id || row?.id, 160), row]));
  const commentMap = new Map(comments.map((row: any) => [publicId(row?.legacy_comment_id, 160), row]));
  const messageMap = new Map(messages.map((row: any) => [publicId(row?.id, 160), row]));

  return reports.map((report) => {
    const targetType = normalizeReportTargetType(report?.target_type);
    const targetId = publicId(report?.target_id, 160);
    const metadata = parseJsonObject(report?.metadata);
    const contentId = publicId((metadata as any).content_id, 160);
    const post = postMap.get(targetId) || postMap.get(contentId) || null;
    const comment = commentMap.get(targetId) || null;
    const message = messageMap.get(targetId) || null;
    const targetUserId = publicId(report?.target_owner_user_id || post?.app_user_id || comment?.app_user_id || message?.sender_id || targetId, 120);
    const reporter = users.get(publicId(report?.reporter_id, 120)) || {};
    const targetUser = users.get(targetUserId) || {};
    const media = post ? supabaseAppPostMedia(post) : { mediaUrls: [], mediaTypes: [], mediaDimensions: [] };
    return {
      ...report,
      reported_id: targetId,
      reported_type: targetType,
      report_type: targetType,
      content_id: contentId,
      created_at: report?.legacy_created_at || report?.created_at,
      updated_at: report?.legacy_updated_at || report?.updated_at,
      reporter_username: reporter?.username,
      reporter_full_name: reporter?.full_name,
      reporter_profile_image: reporter?.avatar_url,
      post_id: post ? publicId(post?.legacy_post_id || post?.id, 160) : '',
      post_user_id: publicId(post?.app_user_id || post?.user_id, 120),
      post_content: cleanMultilineText(post?.content, 4000),
      post_title: cleanText(post?.title, 180),
      post_image: media.mediaUrls[0] || '',
      post_images: JSON.stringify(media.mediaUrls),
      post_media_types: JSON.stringify(media.mediaTypes),
      post_media_dimensions: JSON.stringify(media.mediaDimensions),
      post_status: cleanText(post?.status, 40),
      comment_id: publicId(comment?.legacy_comment_id, 160),
      comment_user_id: publicId(comment?.app_user_id || comment?.user_id, 120),
      comment_content: cleanMultilineText(comment?.body, 1000),
      comment_status: cleanText(comment?.status, 40),
      message_id: publicId(message?.id, 160),
      message_sender_id: publicId(message?.sender_id, 120),
      message_receiver_id: publicId(message?.receiver_id, 120),
      message_content: cleanMultilineText(message?.body, 1000),
      message_media_type: cleanText(message?.media_type, 40),
      message_status: cleanText(message?.status, 40),
      target_user_id: targetUserId,
      target_username: targetUser?.username,
      target_full_name: targetUser?.full_name,
      target_profile_image: targetUser?.avatar_url,
      target_status: cleanText(parseJsonObject(targetUser?.metadata).status || 'active', 40),
    };
  });
}

async function getAdminReportRow(c: any, reportId: string) {
  if (supabasePrimaryConfigured(c)) {
    const rows = await supabaseAdminQueryRows(c, 'app_reports', {
      select: '*',
      filters: { id: postgrestEqFilter(reportId) },
      limit: 1,
    });
    const enriched = await supabaseEnrichAdminReportRows(c, rows);
    return enriched[0] || null;
  }
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

function adminReportedMessageContextPayload(row: any, reportedMessageId = '') {
  const id = publicId(row?.id, 160);
  return {
    id,
    sender_id: publicId(row?.sender_id, 120),
    receiver_id: publicId(row?.receiver_id, 120),
    content: cleanMultilineText(row?.body || row?.content, 2000),
    media_url: safeMediaReference(row?.media_url),
    media_type: cleanText(row?.media_type, 40),
    media: parseJsonObject(row?.media),
    status: cleanText(row?.status || 'active', 40),
    created_at: row?.legacy_created_at || row?.created_at,
    is_reported: !!reportedMessageId && id === reportedMessageId,
  };
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
  if (supabasePrimaryConfigured(c)) {
    const type = reportTargetType(report);
    let target: any = { type, missing: true };
    if ((type === 'post' || type === 'discover_post') && (report.post_id || report.reported_id)) {
      target = {
        type: 'post',
        post: adminPostPayload({
          id: report.post_id || report.reported_id,
          user_id: report.post_user_id || report.target_owner_user_id || '',
          content: report.post_content || '',
          title: report.post_title || '',
          image: report.post_image || '',
          images: report.post_images || '',
          media_types: report.post_media_types || '',
          media_dimensions: report.post_media_dimensions || '',
          status: report.post_status || '',
          user_username: report.target_username || '',
          user_full_name: report.target_full_name || '',
          user_profile_image: report.target_profile_image || '',
        }, c.env),
      };
    } else if (type === 'comment' && (report.comment_id || report.reported_id)) {
      target = {
        type: 'comment',
        comment: {
          id: report.comment_id || report.reported_id,
          post_id: report.content_id || '',
          user_id: report.comment_user_id || report.target_owner_user_id || '',
          content: cleanMultilineText(report.comment_content, 1000),
          status: cleanText(report.comment_status, 40),
        },
      };
    } else if (type === 'message' && (report.message_id || report.reported_id)) {
      target = {
        type: 'message',
        privacy_warning: true,
        message: {
          id: report.message_id || report.reported_id,
          sender_id: report.message_sender_id || '',
          receiver_id: report.message_receiver_id || '',
          content: cleanMultilineText(report.message_content, 1000),
          media_type: cleanText(report.message_media_type, 40),
          status: cleanText(report.message_status, 40),
        },
      };
    } else if ((type === 'profile' || type === 'user') && report.target_user_id) {
      target = {
        type: 'user',
        user: {
          id: report.target_user_id,
          username: publicUsernameFor({ username: report.target_username }),
          full_name: cleanText(report.target_full_name, 120),
          profile_image: safeMediaReference(report.target_profile_image),
          status: cleanText(report.target_status, 40),
        },
      };
    }
    const actionTargetId = publicId(report.reported_id || report.target_id || report.id, 160);
    const actionTargetUserId = publicId(report.target_owner_user_id || report.reported_id || '', 120);
    const actionFilters: Record<string, string> = actionTargetUserId
      ? { or: `(target_id.eq.${actionTargetId},target_user_id.eq.${actionTargetUserId})` }
      : { target_id: postgrestEqFilter(actionTargetId) };
    const actionRows = await supabaseAdminQueryRows(c, 'app_moderation_actions', {
      select: '*',
      filters: actionFilters,
      order: 'created_at.desc',
      limit: 30,
    }).catch(() => []);
    return {
      ...adminReportSummary(report, c.env),
      admin_notes: cleanMultilineText(report.admin_notes, 1000),
      action_taken: cleanText(report.action_taken, 120),
      reviewed_by: report.reviewed_by || '',
      reviewed_at: report.reviewed_at || null,
      target,
      notes: [],
      previous_actions: actionRows.map((action: any) => ({
        ...action,
        reason: cleanMultilineText(action.reason, 500),
        note: cleanMultilineText(action.note, 800),
      })),
    };
  }

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
  if (supabasePrimaryConfigured(c)) {
    const beforeRows = await supabaseAdminQueryRows(c, 'app_reports', {
      select: '*',
      filters: { id: postgrestEqFilter(reportId) },
      limit: 1,
    });
    const before = beforeRows[0];
    if (!before) return c.json({ detail: 'Report not found.' }, 404);
    const normalizedStatus = normalizeReportStatus(status, 'under_review');
    const ts = now();
    const patch: Record<string, unknown> = {
      status: normalizedStatus,
      admin_notes: note,
      action_taken: normalizedStatus,
      reviewed_by: admin.userId,
      updated_at: ts,
    };
    if (['action_taken', 'dismissed', 'closed', 'duplicate'].includes(normalizedStatus)) patch.closed_at = ts;
    await supabaseAdminPatchRows(c, 'app_reports', { id: postgrestEqFilter(reportId) }, patch);
    await writeAdminAuditLog(c, admin, {
      actionType: `report_${normalizedStatus}`,
      targetType: 'report',
      targetId: reportId,
      targetUserId: before.target_owner_user_id || before.target_id || '',
      reason,
      note,
      beforeState: { status: before.status },
      afterState: { status: normalizedStatus },
    });
    const updated = await getAdminReportRow(c, reportId);
    return c.json({ report: await adminReportDetail(c, updated) });
  }

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
    let database = 'unknown';
    if (supabasePrimaryConfigured(c)) {
      await supabaseAdminQueryRows(c, 'app_users', { select: 'id', limit: 1 });
      database = 'supabase_postgres';
    } else {
      await ensureAdminModerationSchema(c.env.DB);
      await ensureMediaModerationSchema(c.env.DB);
      const db: any = await c.env.DB.prepare('SELECT 1 AS ok').first();
      database = Number(db?.ok || 0) === 1 ? 'legacy_d1' : 'unknown';
    }
    return c.json({
      status: 'ok',
      environment: c.env.ENVIRONMENT || 'production',
      timestamp: now(),
      version: c.env.WORKER_VERSION || API_VERSION,
      commit: c.env.SOURCE_COMMIT || '',
      database,
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.get('/admin/moderation', authMiddleware, async (c) => {
  try {
    await requireAdminRole(c, 'content:read');
    const { limit, offset } = adminPageParams(c, 40, 100);
    const statusParam = cleanText(c.req.query('status') || '', 40);
    const status = statusParam ? normalizeMediaModerationStatus(statusParam) : '';
    const mediaType = normalizeMediaAssetType(c.req.query('media_type') || c.req.query('type'));
    const search = searchPattern(c.req.query('search'));
    if (supabasePrimaryConfigured(c)) {
      const rows = await supabaseAdminMediaModerationRows(c, {
        status,
        mediaType,
        search,
        limit,
        offset,
      });
      return c.json({
        results: rows.map((row) => adminMediaModerationPayload(row, c.env)),
        pagination: { limit, offset, next_offset: offset + limit },
      });
    }
    await ensureMediaModerationSchema(c.env.DB);
    const conditions = ['1 = 1'];
    const binds: any[] = [];
    if (status) {
      conditions.push('ma.moderation_status = ?');
      binds.push(status);
    } else {
      conditions.push("ma.moderation_status IN ('review_required', 'failed')");
    }
    if (mediaType) {
      conditions.push('ma.media_type = ?');
      binds.push(mediaType);
    }
    if (search) {
      conditions.push('(LOWER(ma.id) LIKE ? OR LOWER(ma.user_id) LIKE ? OR LOWER(u.username) LIKE ? OR LOWER(u.full_name) LIKE ? OR LOWER(ma.sha256_hash) LIKE ?)');
      binds.push(search, search, search, search, search);
    }
    const rows = await c.env.DB.prepare(`
      SELECT ma.*, u.username AS user_username, u.full_name AS user_full_name, u.email AS user_email, u.profile_image AS user_profile_image,
             p.title AS post_title, p.content AS post_content,
             mr.model_name, mr.adult_explicit_score, mr.nudity_score, mr.sexual_context_score,
             mr.sexual_solicitation_score, mr.minor_safety_risk_score, mr.violence_score,
             mr.gore_score, mr.weapon_score, mr.hate_symbol_score, mr.ai_generated_likelihood,
             mr.spam_scam_score, mr.malware_status, mr.link_risk_score, mr.confidence,
             mr.decision, mr.reasons AS result_reasons, mr.raw_result AS result_raw_result, mr.created_at AS result_created_at
      FROM media_assets ma
      LEFT JOIN users u ON u.id = ma.user_id
      LEFT JOIN posts p ON p.id = ma.post_id
      LEFT JOIN moderation_results mr ON mr.id = (
        SELECT id FROM moderation_results latest WHERE latest.media_id = ma.id ORDER BY latest.created_at DESC LIMIT 1
      )
      WHERE ${conditions.join(' AND ')}
      ORDER BY CASE ma.moderation_status WHEN 'review_required' THEN 0 WHEN 'failed' THEN 1 WHEN 'pending_moderation' THEN 2 ELSE 3 END, ma.created_at DESC
      LIMIT ? OFFSET ?
    `).bind(...binds, limit, offset).all();
    return c.json({
      results: (rows.results as any[]).map((row) => adminMediaModerationPayload(row, c.env)),
      pagination: { limit, offset, next_offset: offset + limit },
    });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/moderation/:id/approve', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'content:write');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_media_moderation_approve');
    if (limited) return limited;
    const mediaId = publicId(c.req.param('id'), 160);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['reason', 'note']);
    if (unknown) return unknown;
    const reason = cleanMultilineText(body.reason || 'Approved by admin review', 500);
    const note = cleanMultilineText(body.note || '', 1000);
    if (supabasePrimaryConfigured(c)) {
      const before: any = await supabaseReadMediaAsset(c, mediaId);
      if (!before) return c.json({ detail: 'Media asset not found.' }, 404);
      const publicUrl = mediaAssetPublicUrl(c.env, before);
      const ts = now();
      await supabaseAdminPatchRows(c, 'app_media_assets', { id: postgrestEqFilter(mediaId) }, {
        moderation_status: 'approved',
        ...(publicUrl ? { public_url: publicUrl } : {}),
        rejection_code: null,
        rejection_message: null,
        updated_at: ts,
      });
      await supabaseInsertModerationEvent(c, mediaId, 'admin_approved', {
        actorUserId: admin.userId,
        actorRole: admin.role,
        decision: 'approved',
        reason,
        note,
        beforeState: before,
        afterState: { moderation_status: 'approved', public_url: publicUrl },
        requestId: c.get?.('requestId') || '',
      });
      await writeAdminAuditLog(c, admin, { actionType: 'media_approved', targetType: 'media_asset', targetId: mediaId, targetUserId: before.user_id, reason, note, beforeState: { moderation_status: before.moderation_status }, afterState: { moderation_status: 'approved' } });
      const updated: any = await supabaseReadMediaAsset(c, mediaId);
      return c.json({ approved: true, media: adminMediaModerationPayload(updated, c.env) });
    }
    await ensureMediaModerationSchema(c.env.DB);
    const before: any = await c.env.DB.prepare('SELECT * FROM media_assets WHERE id = ? LIMIT 1').bind(mediaId).first();
    if (!before) return c.json({ detail: 'Media asset not found.' }, 404);
    const publicUrl = mediaAssetPublicUrl(c.env, before);
    const ts = now();
    await c.env.DB.prepare(
      "UPDATE media_assets SET moderation_status = 'approved', public_url = COALESCE(NULLIF(?, ''), public_url), rejection_code = '', rejection_message = '', updated_at = ? WHERE id = ?"
    ).bind(publicUrl, ts, mediaId).run();
    await insertModerationEvent(c.env.DB, mediaId, 'admin_approved', {
      actorUserId: admin.userId,
      actorRole: admin.role,
      decision: 'approved',
      reason,
      note,
      beforeState: before,
      afterState: { moderation_status: 'approved', public_url: publicUrl },
      requestId: c.get?.('requestId') || '',
    });
    await writeAdminAuditLog(c, admin, { actionType: 'media_approved', targetType: 'media_asset', targetId: mediaId, targetUserId: before.user_id, reason, note, beforeState: { moderation_status: before.moderation_status }, afterState: { moderation_status: 'approved' } });
    const updated: any = await c.env.DB.prepare('SELECT * FROM media_assets WHERE id = ? LIMIT 1').bind(mediaId).first();
    return c.json({ approved: true, media: adminMediaModerationPayload(updated, c.env) });
  } catch (error: any) {
    return governanceError(c, error);
  }
});

api.post('/admin/moderation/:id/reject', authMiddleware, async (c) => {
  try {
    const admin = await requireAdminRole(c, 'content:write');
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_media_moderation_reject');
    if (limited) return limited;
    const mediaId = publicId(c.req.param('id'), 160);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['reason', 'note', 'rejection_code']);
    if (unknown) return unknown;
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    const note = cleanMultilineText(body.note || '', 1000);
    const rejectionCode = cleanText(body.rejection_code || 'admin_rejected', 120);
    if (supabasePrimaryConfigured(c)) {
      const before: any = await supabaseReadMediaAsset(c, mediaId);
      if (!before) return c.json({ detail: 'Media asset not found.' }, 404);
      const userMessage = "This upload can't be posted because it may break Captro's safety rules.";
      await supabaseAdminPatchRows(c, 'app_media_assets', { id: postgrestEqFilter(mediaId) }, {
        moderation_status: 'rejected',
        public_url: null,
        rejection_code: rejectionCode,
        rejection_message: userMessage,
        updated_at: now(),
      });
      await supabaseInsertModerationEvent(c, mediaId, 'admin_rejected', {
        actorUserId: admin.userId,
        actorRole: admin.role,
        decision: 'rejected',
        reason,
        note,
        beforeState: before,
        afterState: { moderation_status: 'rejected', rejection_code: rejectionCode },
        requestId: c.get?.('requestId') || '',
      });
      await writeAdminAuditLog(c, admin, { actionType: 'media_rejected', targetType: 'media_asset', targetId: mediaId, targetUserId: before.user_id, reason, note, beforeState: { moderation_status: before.moderation_status }, afterState: { moderation_status: 'rejected', rejection_code: rejectionCode } });
      const updated: any = await supabaseReadMediaAsset(c, mediaId);
      return c.json({ rejected: true, media: adminMediaModerationPayload(updated, c.env) });
    }
    await ensureMediaModerationSchema(c.env.DB);
    const before: any = await c.env.DB.prepare('SELECT * FROM media_assets WHERE id = ? LIMIT 1').bind(mediaId).first();
    if (!before) return c.json({ detail: 'Media asset not found.' }, 404);
    const userMessage = "This upload can't be posted because it may break Captro's safety rules.";
    await c.env.DB.prepare(
      "UPDATE media_assets SET moderation_status = 'rejected', public_url = NULL, rejection_code = ?, rejection_message = ?, updated_at = ? WHERE id = ?"
    ).bind(rejectionCode, userMessage, now(), mediaId).run();
    await insertModerationEvent(c.env.DB, mediaId, 'admin_rejected', {
      actorUserId: admin.userId,
      actorRole: admin.role,
      decision: 'rejected',
      reason,
      note,
      beforeState: before,
      afterState: { moderation_status: 'rejected', rejection_code: rejectionCode },
      requestId: c.get?.('requestId') || '',
    });
    await writeAdminAuditLog(c, admin, { actionType: 'media_rejected', targetType: 'media_asset', targetId: mediaId, targetUserId: before.user_id, reason, note, beforeState: { moderation_status: before.moderation_status }, afterState: { moderation_status: 'rejected', rejection_code: rejectionCode } });
    const updated: any = await c.env.DB.prepare('SELECT * FROM media_assets WHERE id = ? LIMIT 1').bind(mediaId).first();
    return c.json({ rejected: true, media: adminMediaModerationPayload(updated, c.env) });
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
    if (supabasePrimaryConfigured(c)) {
      const todayStart = new Date();
      todayStart.setUTCHours(0, 0, 0, 0);
      const todayIso = todayStart.toISOString();
      const dayAgoIso = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
      const openStatuses = ['open', 'pending', 'under_review', 'in_review', 'escalated'];
      const [openReports, urgentReports, reportsToday, postsRemovedToday, usersSuspendedToday, newAccountsToday, uploadFailures, quickRows] = await Promise.all([
        supabaseAdminCountRows(c, 'app_reports', { status: postgrestInFilter(openStatuses) }),
        supabaseAdminCountRows(c, 'app_reports', { status: postgrestInFilter(openStatuses), priority: postgrestInFilter(['urgent', 'high']) }),
        supabaseAdminCountRows(c, 'app_reports', { created_at: `gte.${todayIso}` }),
        supabaseAdminCountRows(c, 'app_posts', { status: postgrestInFilter(['removed', 'deleted']), updated_at: `gte.${todayIso}` }),
        supabaseAdminCountRows(c, 'app_users', { status: postgrestEqFilter('suspended'), updated_at: `gte.${todayIso}` }),
        supabaseAdminCountRows(c, 'app_users', { created_at: `gte.${todayIso}` }),
        supabaseAdminCountRows(c, 'app_media_assets', { or: '(moderation_status.eq.failed,upload_status.eq.failed)', updated_at: `gte.${dayAgoIso}` }),
        supabaseAdminQueryRows(c, 'app_reports', {
          select: '*',
          filters: { status: postgrestInFilter(openStatuses) },
          order: 'created_at.desc',
          limit: 40,
        }),
      ]);
      const rank: Record<string, number> = { urgent: 0, high: 1, medium: 2, normal: 3 };
      const quick = (await supabaseEnrichAdminReportRows(c, quickRows))
        .sort((a, b) => (rank[cleanText(a.priority || 'normal', 20)] ?? 4) - (rank[cleanText(b.priority || 'normal', 20)] ?? 4))
        .slice(0, 8);
      return c.json({
        cards: {
          open_reports: openReports,
          urgent_reports: urgentReports,
          reports_today: reportsToday,
          posts_removed_today: postsRemovedToday,
          users_suspended_today: usersSuspendedToday,
          new_accounts_today: newAccountsToday,
          upload_failures_24h: uploadFailures,
        },
        queues: {
          new_reports: quick.map((row) => adminReportSummary(row, c.env)),
        },
      });
    }
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
    const { limit, offset } = adminPageParams(c);
    if (supabasePrimaryConfigured(c)) {
      const filters: Record<string, string> = {};
      const statusQuery = cleanText(c.req.query('status') || 'open', 40).toLowerCase();
      if (statusQuery && statusQuery !== 'all') {
        filters.status = statusQuery === 'open'
          ? postgrestInFilter(['open', 'pending', 'under_review', 'in_review', 'escalated'])
          : postgrestEqFilter(normalizeReportStatus(statusQuery, 'open'));
      }
      const reason = cleanText(c.req.query('reason') || '', 80);
      if (reason && reason !== 'all') filters.reason = postgrestEqFilter(normalizeReportReason(reason));
      const targetType = cleanText(c.req.query('target_type') || c.req.query('type') || '', 60);
      if (targetType && targetType !== 'all') filters.target_type = postgrestEqFilter(normalizeReportTargetType(targetType));
      const fromDate = cleanText(c.req.query('from') || '', 40);
      if (/^\d{4}-\d{2}-\d{2}/.test(fromDate)) filters.created_at = `gte.${fromDate}`;
      const search = postgrestSearchTerm(c.req.query('search') || '');
      if (search) {
        filters.or = `(id.ilike.*${search}*,target_id.ilike.*${search}*,reporter_id.ilike.*${search}*,target_owner_user_id.ilike.*${search}*)`;
      }
      const rows = await supabaseAdminQueryRows(c, 'app_reports', {
        select: '*',
        filters,
        order: 'created_at.desc',
        limit,
        offset,
      });
      const enriched = await supabaseEnrichAdminReportRows(c, rows);
      const rank: Record<string, number> = { urgent: 0, high: 1, medium: 2, normal: 3 };
      enriched.sort((a, b) => (rank[cleanText(a.priority || 'normal', 20)] ?? 4) - (rank[cleanText(b.priority || 'normal', 20)] ?? 4));
      return c.json({
        results: enriched.map((row) => adminReportSummary(row, c.env)),
        pagination: { limit, offset, next_offset: offset + limit },
      });
    }

    await ensureAdminModerationSchema(c.env.DB);
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
    if (!supabasePrimaryConfigured(c)) await ensureAdminModerationSchema(c.env.DB);
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
    if (supabasePrimaryConfigured(c)) {
      const report = await getAdminReportRow(c, reportId);
      if (!report) return c.json({ detail: 'Report not found.' }, 404);
      const ts = now();
      const metadata = parseJsonObject(report.metadata);
      const existingNotes = Array.isArray(metadata.internal_notes) ? metadata.internal_notes : [];
      const structuredNote = {
        id: uuid(),
        admin_user_id: admin.userId,
        admin_role: admin.role,
        note,
        created_at: ts,
      };
      const adminNotes = [cleanMultilineText(report.admin_notes, 4000), `[${ts}] ${note}`]
        .filter(Boolean)
        .join('\n\n')
        .slice(-8000);
      await supabaseAdminPatchRows(c, 'app_reports', { id: postgrestEqFilter(reportId) }, {
        admin_notes: adminNotes,
        metadata: {
          ...metadata,
          internal_notes: [...existingNotes, structuredNote].slice(-100),
        },
        updated_at: ts,
      });
      await writeAdminAuditLog(c, admin, {
        actionType: 'internal_note_added',
        targetType: 'report',
        targetId: reportId,
        targetUserId: report.target_owner_user_id || report.target_id || '',
        note,
      });
      return c.json({ added: true });
    }
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
      if (supabasePrimaryConfigured(c)) {
        const ts = now();
        if ((type === 'post' || type === 'discover_post') && (report.post_id || report.target_id || report.reported_id)) {
          const postId = report.post_id || report.target_id || report.reported_id;
          const identity = await supabaseResolvePostIdentity(c, postId);
          let existingPostRows: any[] = [];
          if (identity.legacyPostId || identity.requestedPostId) {
            existingPostRows = await supabaseAdminQueryRows(c, 'app_posts', {
              select: 'metadata',
              filters: { legacy_post_id: postgrestEqFilter(identity.legacyPostId || identity.requestedPostId) },
              limit: 1,
            }).catch(() => []);
          }
          if (!existingPostRows.length && identity.postUuid) {
            existingPostRows = await supabaseAdminQueryRows(c, 'app_posts', {
              select: 'metadata',
              filters: { id: postgrestEqFilter(identity.postUuid) },
              limit: 1,
            }).catch((error: any) => {
              if (!isSupabaseColumnShapeError(error)) throw error;
              return [];
            });
          }
          const metadata = parseJsonObject(existingPostRows[0]?.metadata);
          const patch = {
            status: 'removed',
            metadata: {
              ...metadata,
              removed_at: ts,
              removed_by: admin.userId,
              removal_reason: reason,
            },
            updated_at: ts,
          };
          if (identity.legacyPostId || identity.requestedPostId) {
            await supabaseAdminPatchRows(c, 'app_posts', { legacy_post_id: postgrestEqFilter(identity.legacyPostId || identity.requestedPostId) }, patch);
          }
          if (identity.postUuid) {
            await supabaseAdminPatchRows(c, 'app_posts', { id: postgrestEqFilter(identity.postUuid) }, patch).catch((error: any) => {
              if (!isSupabaseColumnShapeError(error)) throw error;
            });
          }
          await writeAdminAuditLog(c, admin, {
            actionType: 'content_removed_from_report',
            targetType: 'post',
            targetId: identity.legacyPostId || identity.requestedPostId || postId,
            targetUserId: report.post_user_id || report.target_owner_user_id || '',
            reason,
            note,
            afterState: { status: 'removed' },
          });
        } else if (type === 'comment' && (report.comment_id || report.target_id || report.reported_id)) {
          const commentId = report.comment_id || report.target_id || report.reported_id;
          const commentRows = await supabaseAdminQueryRows(c, 'post_comments', {
            select: 'metadata',
            filters: { legacy_comment_id: postgrestEqFilter(commentId) },
            limit: 1,
          }).catch(() => []);
          const metadata = parseJsonObject(commentRows[0]?.metadata);
          await supabaseAdminPatchRows(c, 'post_comments', { legacy_comment_id: postgrestEqFilter(commentId) }, {
            status: 'removed',
            metadata: {
              ...metadata,
              removed_at: ts,
              removed_by: admin.userId,
              removal_reason: reason,
            },
            updated_at: ts,
          });
          await writeAdminAuditLog(c, admin, {
            actionType: 'content_removed_from_report',
            targetType: 'comment',
            targetId: commentId,
            targetUserId: report.comment_user_id || report.target_owner_user_id || '',
            reason,
            note,
            afterState: { status: 'removed' },
          });
        } else if (type === 'message' && (report.message_id || report.target_id || report.reported_id)) {
          const messageId = report.message_id || report.target_id || report.reported_id;
          const messageRows = await supabaseAdminQueryRows(c, 'app_messages', {
            select: 'media',
            filters: { id: postgrestEqFilter(messageId) },
            limit: 1,
          }).catch(() => []);
          await supabaseAdminPatchRows(c, 'app_messages', { id: postgrestEqFilter(messageId) }, {
            status: 'removed',
            media: {
              ...parseJsonObject(messageRows[0]?.media),
              removed_at: ts,
              removed_by: admin.userId,
              removal_reason: reason,
            },
            updated_at: ts,
          });
          await writeAdminAuditLog(c, admin, {
            actionType: 'message_removed_from_report',
            targetType: 'message',
            targetId: messageId,
            targetUserId: report.message_sender_id || report.target_owner_user_id || '',
            reason,
            note,
            afterState: { status: 'removed' },
          });
        }
        return setReportStatus(c, admin, reportId, 'action_taken', reason, note);
      }
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
    const { limit, offset } = adminPageParams(c);
    const rawSearch = cleanText(c.req.query('search') || '', 120);
    const status = cleanText(c.req.query('status') || '', 40);
    if (supabasePrimaryConfigured(c)) {
      const rows = await supabaseAdminUserRows(c, { search: rawSearch, status, limit, offset });
      const reportCounts = await supabaseAdminReportCountsForUsers(c, rows.map((row) => publicId(row?.id, 120)));
      return c.json({
        results: rows.map((row) => adminSupabaseUserPayload(row, admin.role, reportCounts.get(publicId(row?.id, 120)) || 0)),
        pagination: { limit, offset, next_offset: offset + limit },
      });
    }
    await ensureAdminModerationSchema(c.env.DB);
    const search = searchPattern(c.req.query('search'));
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
    const targetUserId = publicId(c.req.param('userId'), 120);
    if (supabasePrimaryConfigured(c)) {
      const row = await getSupabaseAppUserRowByAnyId(c, targetUserId);
      if (!row) return c.json({ detail: 'User not found.' }, 404);
      const rowId = publicId(row.id, 120);
      const [reportCounts, actions, posts] = await Promise.all([
        supabaseAdminReportCountsForUsers(c, [rowId]),
        supabaseAdminQueryRows(c, 'app_moderation_actions', {
          select: '*',
          filters: { or: `(target_user_id.eq.${rowId},target_id.eq.${rowId})` },
          order: 'created_at.desc',
          limit: 50,
        }).catch((error: any) => {
          console.warn(JSON.stringify({ event: 'supabase_admin_user_actions_failed', code: getErrorCode(error).slice(0, 180) }));
          return [];
        }),
        supabaseReadVisiblePosts(c, rowId, { ownerId: rowId, limit: 12 }).catch((error: any) => {
          console.warn(JSON.stringify({ event: 'supabase_admin_user_posts_failed', code: getErrorCode(error).slice(0, 180) }));
          return [];
        }),
      ]);
      return c.json({
        user: adminSupabaseUserPayload(row, admin.role, reportCounts.get(rowId) || 0),
        restrictions: supabaseUserRestrictionsFromMetadata(row.metadata),
        actions,
        recent_posts: posts.map((post) => adminPostPayload(post, c.env)),
      });
    }
    await ensureAdminModerationSchema(c.env.DB);
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
    if (supabasePrimaryConfigured(c)) {
      const patched = await supabasePatchUserModerationMetadata(c, targetUserId, (metadata) => ({
        ...metadata,
        warning_count: Math.max(0, Number((metadata as any).warning_count || 0)) + 1,
        last_warning_reason: reason,
        last_warned_at: now(),
      }));
      if (!patched.row) return c.json({ detail: 'User not found.' }, 404);
      const canonicalUserId = publicId(patched.row.id, 120);
      await insertNotificationOnce(c, {
        userId: canonicalUserId,
        type: 'moderation_warning',
        title: 'Captro safety warning',
        body: reason,
        data: { moderation_action: 'warning' },
        dedupeKey: `warn:${canonicalUserId}:${Date.now()}`,
        dedupeSeconds: 60,
      }).catch((error: any) => {
        console.warn(JSON.stringify({ event: 'supabase_admin_warning_notification_failed', code: getErrorCode(error).slice(0, 180) }));
      });
      await writeAdminAuditLog(c, admin, {
        actionType: 'user_warned',
        targetType: 'user',
        targetId: canonicalUserId,
        targetUserId: canonicalUserId,
        reason,
        note: body.note,
        beforeState: { warning_count: Number((parseJsonObject(patched.row.metadata) as any).warning_count || 0) },
        afterState: { warning_count: Number((patched.metadata as any).warning_count || 0) },
      });
      return c.json({ warned: true });
    }
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
    const restrictionType = normalizeRestrictionType(body.restriction_type || body.type);
    const hours = clampNumber(body.duration_hours || 24, 1, 24 * 90, 24);
    const endsAt = cleanText(body.ends_at || '', 60) || new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    if (supabasePrimaryConfigured(c)) {
      const createdAt = now();
      const patched = await supabasePatchUserModerationMetadata(c, targetUserId, (metadata, row) => {
        const existing = supabaseUserRestrictionsFromMetadata(metadata);
        const canonicalUserId = publicId(row?.id, 120);
        return {
          ...metadata,
          restrictions: [{
            id: uuid(),
            user_id: canonicalUserId,
            restriction_type: restrictionType,
            reason,
            note: cleanMultilineText(body.note, 500),
            starts_at: createdAt,
            ends_at: endsAt,
            created_by: admin.userId,
            created_at: createdAt,
          }, ...existing].slice(0, 100),
        };
      });
      if (!patched.row) return c.json({ detail: 'User not found.' }, 404);
      const canonicalUserId = publicId(patched.row.id, 120);
      await writeAdminAuditLog(c, admin, { actionType: 'user_restricted', targetType: 'user', targetId: canonicalUserId, targetUserId: canonicalUserId, reason, note: body.note, afterState: { restriction_type: restrictionType, ends_at: endsAt } });
      return c.json({ restricted: true, restriction_type: restrictionType, ends_at: endsAt });
    }
    const target = await c.env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(targetUserId).first();
    if (!target) return c.json({ detail: 'User not found.' }, 404);
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
    if (supabasePrimaryConfigured(c)) {
      const patched = await supabasePatchUserModerationMetadata(c, targetUserId, (metadata) => ({
        ...metadata,
        status: 'suspended',
        suspended_until: suspendedUntil,
        ban_reason: reason,
      }));
      if (!patched.row) return c.json({ detail: 'User not found.' }, 404);
      const canonicalUserId = publicId(patched.row.id, 120);
      await writeAdminAuditLog(c, admin, { actionType: 'user_suspended', targetType: 'user', targetId: canonicalUserId, targetUserId: canonicalUserId, reason, note: body.note, beforeState: patched.before || {}, afterState: { status: 'suspended', suspended_until: suspendedUntil } });
      return c.json({ suspended: true, suspended_until: suspendedUntil });
    }
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
    if (supabasePrimaryConfigured(c)) {
      const bannedAt = now();
      const patched = await supabasePatchUserModerationMetadata(c, targetUserId, (metadata) => ({
        ...metadata,
        status: 'banned',
        banned_at: bannedAt,
        ban_reason: reason,
      }));
      if (!patched.row) return c.json({ detail: 'User not found.' }, 404);
      const canonicalUserId = publicId(patched.row.id, 120);
      await writeAdminAuditLog(c, admin, { actionType: 'user_banned', targetType: 'user', targetId: canonicalUserId, targetUserId: canonicalUserId, reason, note: body.note, beforeState: patched.before || {}, afterState: { status: 'banned', banned_at: bannedAt } });
      return c.json({ banned: true });
    }
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
    if (supabasePrimaryConfigured(c)) {
      const patched = await supabasePatchUserModerationMetadata(c, targetUserId, (metadata) => {
        const next = { ...metadata };
        next.status = 'active';
        delete next.banned_at;
        delete next.suspended_until;
        delete next.ban_reason;
        return next;
      });
      if (!patched.row) return c.json({ detail: 'User not found.' }, 404);
      const canonicalUserId = publicId(patched.row.id, 120);
      await writeAdminAuditLog(c, admin, { actionType: 'user_unbanned', targetType: 'user', targetId: canonicalUserId, targetUserId: canonicalUserId, reason, note: body.note, beforeState: patched.before || {}, afterState: { status: 'active' } });
      return c.json({ unbanned: true });
    }
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
    if (supabasePrimaryConfigured(c)) {
      const row = await getSupabaseAppUserRowByAnyId(c, targetUserId);
      if (!row) return c.json({ detail: 'User not found.' }, 404);
      const canonicalUserId = publicId(row.id, 120);
      const before = supabaseAppUserToLegacyUser(row);
      const pending = pendingUsernameForUser(canonicalUserId);
      const metadata = parseJsonObject(row.metadata);
      await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(canonicalUserId) }, {
        username: pending,
        metadata: scrubLogMetadata({
          ...metadata,
          username_required: true,
          username_force_change_reason: reason,
          username_force_changed_at: now(),
        }),
        updated_at: now(),
      });
      await writeAdminAuditLog(c, admin, { actionType: 'username_force_changed', targetType: 'user', targetId: canonicalUserId, targetUserId: canonicalUserId, reason, note: body.note, beforeState: { username: before.username }, afterState: { username_required: true, username: pending } });
      return c.json({ username_required: true });
    }
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
    const { limit, offset } = adminPageParams(c);
    const status = cleanText(c.req.query('status') || 'all', 40);
    const category = cleanText(c.req.query('category') || '', 60).toLowerCase();
    const surface = cleanText(c.req.query('surface') || '', 40).toLowerCase();
    const rawSearch = cleanText(c.req.query('search') || '', 120);

    if (supabasePrimaryConfigured(c)) {
      const normalizedCategory = category && category !== 'all'
        ? normalizeDiscoverCategory(category, false)
        : '';
      if (category && category !== 'all' && !normalizedCategory) return c.json({ detail: 'Unknown category.' }, 400);
      const filters: Record<string, string> = {};
      if (status !== 'all') filters.status = postgrestEqFilter(status);
      const needsMemoryFilter = !!normalizedCategory || surface === 'discover' || !!rawSearch;
      const rows = await supabaseAdminQueryRows(c, 'app_posts', {
        select: SUPABASE_APP_POST_SELECT,
        filters,
        order: 'legacy_created_at.desc.nullslast,created_at.desc',
        limit: needsMemoryFilter ? Math.min(1000, Math.max(offset + limit + 100, (offset + limit) * 5)) : limit,
        offset: needsMemoryFilter ? 0 : offset,
      });
      const postRows = rows.filter((row) => {
        if (normalizedCategory && !supabaseAppPostMatchesCategory(row, normalizedCategory)) return false;
        if (surface === 'discover') {
          const metadata = parseJsonObject(row?.metadata);
          if (cleanText((metadata as any).discover_blocked_at, 80)) return false;
        }
        return true;
      });
      const payloads = await supabaseAdminPostPayloads(c, postRows);
      const filtered = rawSearch ? payloads.filter((payload) => supabaseAdminPostPayloadMatchesSearch(payload, rawSearch)) : payloads;
      const results = needsMemoryFilter ? filtered.slice(offset, offset + limit) : filtered;
      return c.json({ results, pagination: { limit, offset, next_offset: offset + limit } });
    }

    await ensureAdminModerationSchema(c.env.DB);
    await ensurePostEditorSchema(c.env.DB);
    await ensureAutoCategorySchema(c.env.DB);
    await ensureLocationSchema(c.env.DB);
    const search = searchPattern(c.req.query('search'));
    const conditions: string[] = [];
    const binds: any[] = [];
    if (status !== 'all') {
      conditions.push("COALESCE(p.status, 'active') = ?");
      binds.push(status);
    }
    if (category && category !== 'all') {
      const normalizedCategory = normalizeDiscoverCategory(category, false);
      if (!normalizedCategory || normalizedCategory === 'all') return c.json({ detail: 'Unknown category.' }, 400);
      const categoryMatch = discoverCategoryCondition('p', normalizedCategory);
      conditions.push(categoryMatch.sql);
      binds.push(...categoryMatch.binds);
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
    const postId = publicId(c.req.param('postId'), 120);
    if (supabasePrimaryConfigured(c)) {
      const target = await supabaseAdminPostForModeration(c, postId);
      if (!target) return c.json({ detail: 'Post not found.' }, 404);
      const post = await supabaseAdminPostPayload(c, target.row);
      const actionTargetIds = supabasePostIdentityKeys(target.identity);
      const actions = await supabaseAdminQueryRows(c, 'app_moderation_actions', {
        select: '*',
        filters: {
          target_type: postgrestEqFilter('post'),
          target_id: postgrestInFilter(actionTargetIds.length ? actionTargetIds : [postId]),
        },
        order: 'created_at.desc',
        limit: 30,
      }).catch((error: any) => {
        console.warn(JSON.stringify({ event: 'supabase_admin_post_actions_failed', code: getErrorCode(error).slice(0, 180) }));
        return [];
      });
      return c.json({ post, actions });
    }
    await ensureAdminModerationSchema(c.env.DB);
    await ensureAutoCategorySchema(c.env.DB);
    await ensureLocationSchema(c.env.DB);
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
    if (supabasePrimaryConfigured(c)) {
      const target = await supabaseAdminPostForModeration(c, postId);
      if (!target) return c.json({ detail: 'Post not found.' }, 404);
      const before = target.row;
      const metadata = parseJsonObject(before?.metadata);
      const removedAt = now();
      await supabaseAdminPatchRows(c, 'app_posts', { or: supabaseAppPostIdentityOrFilter(target.identity) }, {
        status: 'removed',
        metadata: {
          ...metadata,
          removed_at: removedAt,
          removed_reason: reason,
          removed_by: admin.userId,
        },
        updated_at: removedAt,
      });
      await writeAdminAuditLog(c, admin, { actionType: 'post_removed', targetType: 'post', targetId: postId, targetUserId: supabasePostModerationTargetUserId(before), reason, note: body.note, beforeState: before, afterState: { status: 'removed' } });
      return c.json({ removed: true });
    }
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
    if (supabasePrimaryConfigured(c)) {
      const target = await supabaseAdminPostForModeration(c, postId);
      if (!target) return c.json({ detail: 'Post not found.' }, 404);
      const before = target.row;
      const metadata = parseJsonObject(before?.metadata);
      delete (metadata as any).removed_at;
      delete (metadata as any).removed_reason;
      delete (metadata as any).removed_by;
      await supabaseAdminPatchRows(c, 'app_posts', { or: supabaseAppPostIdentityOrFilter(target.identity) }, {
        status: 'active',
        metadata,
        updated_at: now(),
      });
      await writeAdminAuditLog(c, admin, { actionType: 'post_restored', targetType: 'post', targetId: postId, targetUserId: supabasePostModerationTargetUserId(before), reason, note: body.note, beforeState: before, afterState: { status: 'active' } });
      return c.json({ restored: true });
    }
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
    if (supabasePrimaryConfigured(c)) {
      const target = await supabaseAdminPostForModeration(c, postId);
      if (!target) return c.json({ detail: 'Post not found.' }, 404);
      const before = target.row;
      const metadata = parseJsonObject(before?.metadata);
      for (const key of ['removed_at', 'removed_reason', 'removed_by', 'discover_blocked_at', 'discover_blocked_by', 'discover_blocked_reason']) {
        delete (metadata as any)[key];
      }
      await supabaseAdminPatchRows(c, 'app_posts', { or: supabaseAppPostIdentityOrFilter(target.identity) }, {
        status: 'active',
        metadata,
        updated_at: now(),
      });
      await writeAdminAuditLog(c, admin, { actionType: 'post_marked_safe', targetType: 'post', targetId: postId, targetUserId: supabasePostModerationTargetUserId(before), reason, note: body.note, beforeState: before, afterState: { status: 'active', discover_blocked: false } });
      return c.json({ marked_safe: true });
    }
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
    if (supabasePrimaryConfigured(c)) {
      const target = await supabaseAdminPostForModeration(c, postId);
      if (!target) return c.json({ detail: 'Post not found.' }, 404);
      const before = target.row;
      const metadata = parseJsonObject(before?.metadata);
      await supabaseAdminPatchRows(c, 'app_posts', { or: supabaseAppPostIdentityOrFilter(target.identity) }, {
        metadata: {
          ...metadata,
          discover_blocked_at: now(),
          discover_blocked_by: admin.userId,
          discover_blocked_reason: reason,
        },
        updated_at: now(),
      });
      await writeAdminAuditLog(c, admin, { actionType: 'post_removed_from_discover', targetType: 'post', targetId: postId, targetUserId: supabasePostModerationTargetUserId(before), reason, note: body.note, beforeState: before, afterState: { discover_blocked: true } });
      return c.json({ removed_from_discover: true });
    }
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
    const limited = await requireAdminWriteRateLimit(c, admin, 'admin_post_location_clear');
    if (limited) return limited;
    const postId = publicId(c.req.param('postId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const unknown = rejectUnknownFields(c, body, ['reason', 'note']);
    if (unknown) return unknown;
    const reason = cleanMultilineText(body.reason, 500);
    if (!reason) return c.json({ detail: 'Reason is required.' }, 400);
    if (supabasePrimaryConfigured(c)) {
      const target = await supabaseAdminPostForModeration(c, postId);
      if (!target) return c.json({ detail: 'Post not found.' }, 404);
      const before = target.row;
      const metadata = parseJsonObject(before?.metadata);
      const raw = parseJsonObject((metadata as any).raw);
      delete (metadata as any).place;
      await supabaseAdminPatchRows(c, 'app_posts', { or: supabaseAppPostIdentityOrFilter(target.identity) }, {
        location: '',
        metadata: {
          ...metadata,
          raw: {
            ...raw,
            display_city: '',
            display_region: '',
            display_country: '',
            display_location_label: '',
            display_location_source: 'none',
            display_location_visibility: 'hidden',
          },
          display_city: '',
          display_region: '',
          display_country: '',
          display_location_label: '',
          display_location_source: 'none',
          display_location_visibility: 'hidden',
          place_type: '',
          location_cleared_at: now(),
          location_cleared_by: admin.userId,
          location_cleared_reason: reason,
        },
        updated_at: now(),
      });
      const legacyPostId = publicId(before?.legacy_post_id || postId, 120);
      if (legacyPostId) {
        await supabaseAdminDeleteRows(c, 'app_post_places', { legacy_post_id: postgrestEqFilter(legacyPostId) }).catch((error: any) => {
          console.warn(JSON.stringify({ event: 'supabase_admin_post_places_delete_failed', code: getErrorCode(error).slice(0, 180) }));
        });
      }
      await writeAdminAuditLog(c, admin, {
        actionType: 'post_location_cleared',
        targetType: 'post',
        targetId: postId,
        targetUserId: supabasePostModerationTargetUserId(before),
        reason,
        note: body.note,
        beforeState: before,
        afterState: { display_location_visibility: 'hidden', place_removed: true },
      });
      const refreshed = await supabaseAdminPostForModeration(c, postId);
      const post = refreshed ? await supabaseAdminPostPayload(c, refreshed.row) : null;
      return c.json({ post });
    }

    await ensureAdminModerationSchema(c.env.DB);
    await ensureLocationSchema(c.env.DB);
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
    if (supabasePrimaryConfigured(c)) {
      const target = await supabaseAdminPostForModeration(c, postId);
      if (!target) return c.json({ detail: 'Post not found.' }, 404);
      const before = target.row;
      const metadata = parseJsonObject(before?.metadata);
      const discover = parseJsonObject((metadata as any).discover_category);
      const oldCategory = normalizeDiscoverCategory(before?.category || (discover as any).primary_category || before?.post_type, false) || DEFAULT_DISCOVER_CATEGORY;
      const changedAt = now();
      const nextScores = { [category]: 100 };
      const nextDiscover = {
        ...discover,
        primary_category: category,
        confidence: 1,
        source: 'admin_changed',
        status: 'admin_corrected',
        secondary_categories: [category],
        category_scores: nextScores,
        admin_changed_at: changedAt,
        admin_previous_category: oldCategory,
        admin_new_category: category,
        admin_reason: reason,
      };
      await supabaseAdminPatchRows(c, 'app_posts', { or: supabaseAppPostIdentityOrFilter(target.identity) }, {
        category,
        metadata: {
          ...metadata,
          discover_category: nextDiscover,
          category_scores: nextScores,
          secondary_categories: [category],
          user_selected_category: category,
        },
        updated_at: changedAt,
      });
      await writeAdminAuditLog(c, admin, {
        actionType: 'category_changed',
        targetType: 'post',
        targetId: postId,
        targetUserId: supabasePostModerationTargetUserId(before),
        reason,
        note: body.note,
        beforeState: { old_category: oldCategory, category_source: (discover as any).source, category_status: (discover as any).status },
        afterState: { new_category: category, category_source: 'admin_changed', category_status: 'admin_corrected' },
      });
      const refreshed = await supabaseAdminPostForModeration(c, postId);
      const post = refreshed ? await supabaseAdminPostPayload(c, refreshed.row) : null;
      return c.json({ post });
    }

    await ensureAdminModerationSchema(c.env.DB);
    await ensureAutoCategorySchema(c.env.DB);
    const before: any = await c.env.DB.prepare(
      `SELECT id, user_id, primary_category, category_confidence, category_source, category_status, category_signals_json, tags_json
       FROM posts
       WHERE id = ?
       LIMIT 1`
    ).bind(postId).first();
    if (!before) return c.json({ detail: 'Post not found.' }, 404);
    const oldCategory = normalizeDiscoverCategory(before.primary_category, false) || DEFAULT_DISCOVER_CATEGORY;
    const nextSignals = {
      ...parseJsonObject(before.category_signals_json),
      admin_changed_at: now(),
      admin_previous_category: oldCategory,
      admin_new_category: category,
      admin_reason: reason,
    };
    const nextScores = { [category]: 100 };
    await c.env.DB.prepare(
      `UPDATE posts
       SET primary_category = ?, category_confidence = 1, category_source = 'admin_changed',
           category_status = 'admin_corrected', category_signals_json = ?,
           secondary_categories_json = ?, category_scores_json = ?, updated_at = datetime('now')
       WHERE id = ?`
    ).bind(category, JSON.stringify(nextSignals), JSON.stringify([category]), JSON.stringify(nextScores), postId).run();
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
    const { limit, offset } = adminPageParams(c);
    const status = cleanText(c.req.query('status') || 'all', 40);
    const rawSearch = cleanText(c.req.query('search') || '', 120);

    if (supabasePrimaryConfigured(c)) {
      const filters: Record<string, string> = {};
      if (status !== 'all') filters.status = postgrestEqFilter(status);
      const needsMemoryFilter = !!rawSearch;
      const rows = await supabaseAdminQueryRows(c, 'post_comments', {
        select: 'legacy_comment_id,legacy_post_id,app_user_id,user_id,body,status,metadata,legacy_created_at,created_at,updated_at',
        filters,
        order: 'legacy_created_at.desc.nullslast,created_at.desc',
        limit: needsMemoryFilter ? Math.min(1000, Math.max(offset + limit + 100, (offset + limit) * 5)) : limit,
        offset: needsMemoryFilter ? 0 : offset,
      });
      const payloads = await supabaseAdminCommentPayloads(c, rows);
      const filtered = rawSearch ? payloads.filter((payload) => supabaseAdminCommentPayloadMatchesSearch(payload, rawSearch)) : payloads;
      const results = needsMemoryFilter ? filtered.slice(offset, offset + limit) : filtered;
      return c.json({ results, pagination: { limit, offset, next_offset: offset + limit } });
    }

    await ensureAdminModerationSchema(c.env.DB);
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
    if (supabasePrimaryConfigured(c)) {
      const identity = await supabaseResolveCommentIdentity(c, commentId);
      if (!identity) return c.json({ detail: 'Comment not found.' }, 404);
      const removedAt = now();
      await supabaseAdminPatchRows(c, 'post_comments', { or: supabaseCommentRowOrFilter(identity) }, {
        status: 'removed',
        metadata: {
          ...identity.metadata,
          removed_at: removedAt,
          removed_reason: reason,
          pinned_at: null,
        },
        updated_at: removedAt,
      });
      if (identity.legacyPostId) await getSupabasePostEngagementState(c, identity.legacyPostId, admin.userId).catch(() => undefined);
      await writeAdminAuditLog(c, admin, {
        actionType: 'comment_removed',
        targetType: 'comment',
        targetId: commentId,
        targetUserId: publicId(identity.row?.app_user_id || identity.row?.user_id, 120),
        reason,
        note: body.note,
        beforeState: identity.row,
        afterState: { status: 'removed' },
      });
      return c.json({ removed: true });
    }
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
    if (supabasePrimaryConfigured(c)) {
      const identity = await supabaseResolveCommentIdentity(c, commentId);
      if (!identity) return c.json({ detail: 'Comment not found.' }, 404);
      const metadata = { ...identity.metadata };
      for (const key of ['removed_at', 'removed_reason', 'hidden_at', 'hidden_by_user_id', 'pinned_at']) {
        delete (metadata as any)[key];
      }
      await supabaseAdminPatchRows(c, 'post_comments', { or: supabaseCommentRowOrFilter(identity) }, {
        status: 'active',
        metadata,
        updated_at: now(),
      });
      if (identity.legacyPostId) await getSupabasePostEngagementState(c, identity.legacyPostId, admin.userId).catch(() => undefined);
      await writeAdminAuditLog(c, admin, {
        actionType: 'comment_restored',
        targetType: 'comment',
        targetId: commentId,
        targetUserId: publicId(identity.row?.app_user_id || identity.row?.user_id, 120),
        reason,
        note: body.note,
        beforeState: identity.row,
        afterState: { status: 'active' },
      });
      return c.json({ restored: true });
    }
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
    const { limit, offset } = adminPageParams(c);
    if (supabasePrimaryConfigured(c)) {
      const rows = await supabaseAdminQueryRows(c, 'app_reports', {
        select: '*',
        filters: { target_type: postgrestEqFilter('message') },
        order: 'created_at.desc',
        limit,
        offset,
      });
      const enriched = await supabaseEnrichAdminReportRows(c, rows);
      return c.json({
        results: enriched.map((row) => adminReportSummary(row, c.env)),
        pagination: { limit, offset, next_offset: offset + limit },
      });
    }
    await ensureAdminModerationSchema(c.env.DB);
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
    const reportId = publicId(c.req.param('reportId'), 120);
    const report = await getAdminReportRow(c, reportId);
    if (!report || reportTargetType(report) !== 'message') return c.json({ detail: 'Reported message not found.' }, 404);
    const messageId = report.message_id || report.reported_id;
    if (supabasePrimaryConfigured(c)) {
      const messageRows = await supabaseAdminQueryRows(c, 'app_messages', {
        select: 'id,sender_id,receiver_id,conversation_id,body,media_url,media_type,media,status,created_at,legacy_created_at',
        filters: { id: postgrestEqFilter(messageId) },
        limit: 1,
      });
      const message = messageRows[0];
      if (!message) return c.json({ detail: 'Message not found.' }, 404);
      const senderId = publicId(message.sender_id, 120);
      const receiverId = publicId(message.receiver_id, 120);
      const conversationId = publicId(message.conversation_id, 160);
      const contextFilters: Record<string, string> = {};
      if (conversationId) {
        contextFilters.conversation_id = postgrestEqFilter(conversationId);
      } else if (senderId && receiverId) {
        contextFilters.or = `(and(sender_id.eq.${senderId},receiver_id.eq.${receiverId}),and(sender_id.eq.${receiverId},receiver_id.eq.${senderId}))`;
      }
      let rawContext: any[] = [message];
      if (conversationId || (senderId && receiverId)) {
        rawContext = await supabaseAdminQueryRows(c, 'app_messages', {
          select: 'id,sender_id,receiver_id,conversation_id,body,media_url,media_type,media,status,created_at,legacy_created_at',
          filters: contextFilters,
          order: 'created_at.desc',
          limit: 50,
        }).catch((error: any) => {
          console.warn(JSON.stringify({ event: 'supabase_reported_message_context_failed', code: getErrorCode(error).slice(0, 180) }));
          return [message];
        });
      }
      const centerMs = Date.parse(cleanText(message.legacy_created_at || message.created_at, 80));
      const boundedContext = rawContext
        .filter((row) => {
          if (!Number.isFinite(centerMs)) return true;
          const rowMs = Date.parse(cleanText(row?.legacy_created_at || row?.created_at, 80));
          return Number.isFinite(rowMs) && Math.abs(rowMs - centerMs) <= 10 * 60 * 1000;
        })
        .sort((a, b) => Date.parse(cleanText(a?.legacy_created_at || a?.created_at, 80)) - Date.parse(cleanText(b?.legacy_created_at || b?.created_at, 80)))
        .slice(0, 12);
      const contextRows = boundedContext.some((row) => publicId(row?.id, 160) === messageId)
        ? boundedContext
        : [message, ...boundedContext.filter((row) => publicId(row?.id, 160) !== messageId)].slice(0, 12);
      await writeAdminAuditLog(c, admin, { actionType: 'reported_message_viewed', targetType: 'message', targetId: messageId, targetUserId: senderId, reason: 'Safety review', note: `Report ${reportId}` });
      return c.json({
        report: await adminReportDetail(c, report),
        privacy_warning: 'Reported message access is audit logged and limited to nearby context needed for safety review.',
        context: contextRows.map((row) => adminReportedMessageContextPayload(row, messageId)),
      });
    }
    await ensureAdminModerationSchema(c.env.DB);
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
    if (supabasePrimaryConfigured(c)) {
      if (action === 'remove_message' || action === 'remove') {
        const messageRows = await supabaseAdminQueryRows(c, 'app_messages', {
          select: 'id,sender_id,media,status',
          filters: { id: postgrestEqFilter(messageId) },
          limit: 1,
        });
        const message = messageRows[0];
        if (!message) return c.json({ detail: 'Message not found.' }, 404);
        await supabaseAdminPatchRows(c, 'app_messages', { id: postgrestEqFilter(messageId) }, {
          status: 'removed',
          media: {
            ...parseJsonObject(message.media),
            removed_at: now(),
            removed_by: admin.userId,
            removal_reason: reason,
          },
          updated_at: now(),
        });
        await writeAdminAuditLog(c, admin, { actionType: 'reported_message_removed', targetType: 'message', targetId: messageId, targetUserId: publicId(message.sender_id || report.message_sender_id, 120), reason, note: body.note });
        return setReportStatus(c, admin, reportId, 'action_taken', reason, body.note || '');
      }
      return setReportStatus(c, admin, reportId, action === 'dismiss' ? 'dismissed' : 'under_review', reason, body.note || '');
    }
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
    const { limit, offset } = adminPageParams(c, 80, 150);
    const action = cleanText(c.req.query('action') || '', 80);
    const targetType = cleanText(c.req.query('target_type') || '', 60);
    const adminId = publicId(c.req.query('admin_id') || '', 120);

    if (supabasePrimaryConfigured(c)) {
      const filters: Record<string, string> = {};
      if (action) filters.action_type = postgrestEqFilter(action);
      if (targetType) filters.target_type = postgrestEqFilter(targetType);
      if (adminId) filters.actor_admin_user_id = postgrestEqFilter(adminId);
      const rows = await supabaseAdminQueryRows(c, 'app_audit_logs', {
        select: '*',
        filters,
        order: 'created_at.desc',
        limit,
        offset,
      });
      const actorIds = rows.map((row: any) => publicId(row?.actor_admin_user_id, 120)).filter(Boolean);
      const actors = await supabaseUsersByAnyIds(c, actorIds);
      return c.json({
        results: rows.map((row: any) => {
          const actor = actors.get(publicId(row?.actor_admin_user_id, 120)) || {};
          return {
            id: row.id,
            actor_admin_user_id: row.actor_admin_user_id,
            actor_role: row.actor_role,
            actor_username: publicUsernameFor(actor),
            actor_full_name: cleanText(actor?.full_name, 120),
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
          };
        }),
        pagination: { limit, offset, next_offset: offset + limit },
      });
    }

    await ensureAdminModerationSchema(c.env.DB);
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
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'admin_stats');
  if (supabaseRequired) return supabaseRequired;
  const [users, posts, reports, pendingApplications] = await Promise.all([
    supabaseAdminCountRows(c, 'app_users', {}),
    supabaseAdminCountRows(c, 'app_posts', { status: postgrestInFilter(['active', 'under_review', 'removed']) }),
    supabaseAdminCountRows(c, 'app_reports', {}),
    supabaseAdminCountRows(c, 'app_documents', { collection: postgrestEqFilter('publisher_applications'), visibility: postgrestEqFilter('private') }).catch(() => 0),
  ]);
  return c.json({ total_users: users, total_posts: posts, total_reports: reports, pending_applications: pendingApplications });
});

api.get('/admin/reported-posts', authMiddleware, adminGuard, async (c) => {
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'admin_reported_posts');
  if (supabaseRequired) return supabaseRequired;
  const rows = await supabaseAdminQueryRows(c, 'app_reports', {
    filters: { target_type: postgrestEqFilter('post') },
    order: 'created_at.desc',
    limit: 100,
  });
  return c.json(await supabaseEnrichAdminReportRows(c, rows));
});

api.get('/admin/reported-accounts', authMiddleware, adminGuard, async (c) => {
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'admin_reported_accounts');
  if (supabaseRequired) return supabaseRequired;
  const rows = await supabaseAdminQueryRows(c, 'app_reports', {
    filters: { target_type: postgrestEqFilter('user') },
    order: 'created_at.desc',
    limit: 100,
  });
  return c.json(await supabaseEnrichAdminReportRows(c, rows));
});

api.post('/admin/remove-post/:postId', authMiddleware, adminGuard, async (c) => {
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'admin_remove_post_legacy');
  if (supabaseRequired) return supabaseRequired;
  const postId = c.req.param('postId');
  const identity = await supabaseResolvePostIdentity(c, postId);
  const patch = {
    status: 'removed',
    metadata: {
      removed_at: now(),
      removed_reason: 'Removed by admin',
      removed_by: getUserId(c),
    },
    updated_at: now(),
  };
  if (identity.legacyPostId || identity.requestedPostId) {
    await supabaseAdminPatchRows(c, 'app_posts', { legacy_post_id: postgrestEqFilter(identity.legacyPostId || identity.requestedPostId) }, patch).catch(() => undefined);
  }
  if (identity.postUuid) {
    await supabaseAdminPatchRows(c, 'app_posts', { id: postgrestEqFilter(identity.postUuid) }, patch).catch(() => undefined);
  }
  await logGovernanceAction(c, getUserId(c), 'remove_post', 'post', postId, { legacy_route: true, supabase_primary: true });
  return c.json({ removed: true, soft_deleted: true });
});

api.post('/admin/make-admin/:userId', authMiddleware, adminGuard, async (c) => {
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'admin_make_admin');
  if (supabaseRequired) return supabaseRequired;
  const targetUserId = publicId(c.req.param('userId'), 120);
  await supabaseAdminUpsert(c, 'app_admin_roles', [{
    user_id: targetUserId,
    role: 'admin',
    created_by: getUserId(c),
    updated_at: now(),
  }], 'user_id');
  await logGovernanceAction(c, getUserId(c), 'assign_admin_role', 'user', targetUserId, { legacy_route: true, supabase_primary: true });
  return c.json({ success: true });
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
    } else if (cleanText(backup.message_id, 120)) {
      const visibleMessage: any = await c.env.DB.prepare(
        'SELECT id FROM messages WHERE id = ? AND (sender_id = ? OR receiver_id = ?) LIMIT 1'
      ).bind(cleanText(backup.message_id, 120), viewerId, viewerId).first();
      if (!visibleMessage) return c.json({ detail: 'Media not found' }, 404);
    } else if (cleanText(backup.group_message_id, 120)) {
      const visibleGroupMessage: any = await c.env.DB.prepare(
        `SELECT gm.id
         FROM group_messages gm
         JOIN group_chat_members m ON m.group_id = gm.group_id
         WHERE gm.id = ? AND m.user_id = ?
         LIMIT 1`
      ).bind(cleanText(backup.group_message_id, 120), viewerId).first();
      if (!visibleGroupMessage) return c.json({ detail: 'Media not found' }, 404);
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

async function serveCloudflareImageProxy(c: any) {
  const imageId = publicId(c.req.param('imageId'), 220);
  if (!imageId) return c.json({ detail: 'Media not found' }, 404);

  const limited = await enforceRateLimit(c, 'cf_image_proxy_read', clientIp(c), 900, 60);
  if (limited) return limited;

  const accountId = cloudflareAccountId(c.env);
  const token = cloudflareImagesToken(c.env);
  if (!accountId || !token) return c.json({ detail: 'Media delivery is not configured' }, 503);

  await ensureGovernanceSchema(c.env.DB);
  await ensureMediaModerationSchema(c.env.DB);

  const visibleAsset: any = await c.env.DB.prepare(
    `SELECT ma.id
     FROM media_assets ma
     JOIN posts p ON p.id = ma.post_id
     JOIN users u ON u.id = p.user_id
     WHERE ma.storage_provider = 'images'
       AND ma.storage_key = ?
       AND COALESCE(ma.upload_status, 'uploaded') = 'uploaded'
       AND COALESCE(ma.moderation_status, 'approved') = 'approved'
       AND ${publicPostWhere('u', 'p')}
     LIMIT 1`
  ).bind(imageId).first();

  if (!visibleAsset) return c.json({ detail: 'Media not found' }, 404);

  const cacheKey = new Request(c.req.url, { method: 'GET' });
  try {
    const cached = await caches.default.match(cacheKey);
    if (cached) {
      return c.req.method === 'HEAD'
        ? new Response(null, { headers: cached.headers })
        : cached;
    }
  } catch {
    // Cache API is best-effort. The proxy still works without it.
  }

  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/images/v1/${encodeURIComponent(imageId)}/blob`, {
    headers: { Authorization: `Bearer ${token}`, accept: 'image/*' },
  });

  if (!res.ok) {
    const status = [403, 404, 409, 425].includes(res.status) ? 404 : 502;
    console.warn(JSON.stringify({
      event: 'cf_image_proxy_fetch_failed',
      status: res.status,
      image_id: imageId.slice(0, 24),
    }));
    return c.json({ detail: 'Media not ready' }, status as any);
  }

  const headers = new Headers();
  headers.set('content-type', res.headers.get('content-type') || 'image/jpeg');
  const contentLength = res.headers.get('content-length');
  if (contentLength) headers.set('content-length', contentLength);
  const etag = res.headers.get('etag');
  if (etag) headers.set('etag', etag);
  headers.set('cache-control', 'public, max-age=86400, stale-while-revalidate=604800');
  headers.set('cdn-cache-control', 'public, max-age=86400, stale-while-revalidate=604800');
  headers.set('cloudflare-cdn-cache-control', 'public, max-age=86400, stale-while-revalidate=604800');
  headers.set('x-content-type-options', 'nosniff');
  headers.set('vary', 'accept');

  const response = new Response(c.req.method === 'HEAD' ? null : res.body, { headers });
  if (c.req.method !== 'HEAD') {
    runBackgroundTask(c, 'cf_image_proxy_cache_put_failed', async () => {
      await caches.default.put(cacheKey, response.clone());
    });
  }
  return response;
}

api.get('/media/cf-image/:imageId', serveCloudflareImageProxy);
api.on('HEAD', '/media/cf-image/:imageId', serveCloudflareImageProxy);
api.get('/media/:backupId', serveMediaBackup);
api.on('HEAD', '/media/:backupId', serveMediaBackup);

// Upload (Cloudflare Images)
api.post('/upload/image', authMiddleware, async (c) => {
  try {
    const legacyDisabled = rejectLegacyUploadWhenSupabasePrimary(c, '/upload/image');
    if (legacyDisabled) return legacyDisabled;
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

    const accountId = cloudflareAccountId(c.env);
    const token = cloudflareImagesToken(c.env);
    if (accountId && token) {
      const cfRes = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/images/v1`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}` },
        body: formData,
      });
      const cfData: any = await cfRes.json();
      if (cfData.success) {
        const imageId = cfData.result.id;
        const deliveryUrl = cloudflareImageVariantUrl(c.env, imageId, cfData.result?.variants);
        const backup = await storeMediaBackup(c, {
          userId,
          mediaKind: 'image',
          provider: 'cloudflare_images',
          providerId: imageId,
          deliveryUrl: deliveryUrl || undefined,
          contentType: processed.contentType,
          bytes: processed.bytes,
          originalFilename: body.filename || `upload.${fileExt}`,
        });
        return c.json({
          url: deliveryUrl || backup?.delivery_url || '',
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
  const legacyDisabled = rejectLegacyUploadWhenSupabasePrimary(c, '/upload/base64-image');
  if (legacyDisabled) return legacyDisabled;
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
    const legacyDisabled = rejectLegacyUploadWhenSupabasePrimary(c, '/upload/video');
    if (legacyDisabled) return legacyDisabled;
    const userId = getUserId(c);
    const limited = await enforceRateLimit(c, 'upload_video_direct', userId, 40, 60);
    if (limited) return limited;
    const dailyLimited = await enforceRateLimit(c, 'upload_video_direct_daily', userId, 100, 86400);
    if (dailyLimited) return dailyLimited;
    const accountId = cloudflareAccountId(c.env);
    const token = cloudflareStreamToken(c.env);
    if (!accountId || !token) {
      return c.json({ detail: 'Cloudflare Stream is not configured.' }, 503);
    }
    // Get a direct upload URL from Cloudflare Stream
    const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/direct_upload`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ maxDurationSeconds: 60, creator: userId }),
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
    const legacyDisabled = rejectLegacyUploadWhenSupabasePrimary(c, '/upload/video-with-backup');
    if (legacyDisabled) return legacyDisabled;
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
    const accountId = cloudflareAccountId(c.env);
    const token = cloudflareStreamToken(c.env);
    const hasStreamConfig = !!(accountId && token);

    if (hasStreamConfig) {
      try {
        const directRes = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/direct_upload`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ maxDurationSeconds: 60, creator: userId }),
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
api.get('/stream/video/:videoUid', authMiddleware, async (c) => {
  const uid = publicId(c.req.param('videoUid'), 128);
  try {
    if (!uid || !/^[a-zA-Z0-9_-]{6,128}$/.test(uid)) return c.json({ detail: 'Video not found' }, 404);
    const accountId = cloudflareAccountId(c.env);
    const token = cloudflareStreamToken(c.env);
    if (!accountId || !token) return c.json({ detail: 'Cloudflare Stream is not configured.' }, 503);
    const cacheKey = `stream:video:${uid}`;
    const cached: any = c.env.KV ? await c.env.KV.get(cacheKey, 'json').catch(() => null) : null;
    if (cached && cached.ready !== false && cached.hls) {
      const response = c.json(cached);
      response.headers.set('cache-control', 'public, max-age=60, s-maxage=300');
      return response;
    }

    const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/${uid}`, {
      headers: { 'Authorization': `Bearer ${token}` },
    });
    const data: any = await res.json();
    if (!data.success || !data.result) return c.json({ detail: 'Video not found' }, 404);
    const v = data.result;
    const state = cleanText(v.status?.state || '', 40).toLowerCase();
    const fallbackHls = streamPlaybackUrl(`cfstream:${uid}`);
    const fallbackThumbnail = streamThumbnailUrl(`cfstream:${uid}`);
    const hls = safeExternalUrl(v.playback?.hls) || fallbackHls || null;
    const dash = safeExternalUrl(v.playback?.dash) || null;
    const thumbnail = safeExternalUrl(v.thumbnail) || fallbackThumbnail || null;
    const readyStates = new Set(['ready', 'readytostream', 'ready_to_stream', 'published']);
    const processingStates = new Set(['queued', 'pendingupload', 'downloading', 'encoding', 'inprogress', 'processing']);
    const ready = !!hls && (v.readyToStream === true || readyStates.has(state) || (!processingStates.has(state) && !!v.playback?.hls));
    const payload = {
      uid: v.uid,
      status: state || 'unknown',
      duration: v.duration,
      thumbnail,
      preview: safeExternalUrl(v.preview),
      playback: v.playback || {},
      hls,
      dash,
      ready,
    };
    if (c.env.KV && payload.ready) {
      await c.env.KV.put(cacheKey, JSON.stringify(payload), { expirationTtl: 300 }).catch(() => undefined);
    }
    const response = c.json(payload);
    response.headers.set('cache-control', payload.ready ? 'public, max-age=60, s-maxage=300' : 'no-store');
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
      types: 'place,locality,neighborhood,region,country',
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
      types: 'place,locality,neighborhood,region,country',
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
api.get('/', (c) => c.json({ message: 'Captro API', version: API_VERSION, runtime: 'Cloudflare Workers + Hono + Supabase Postgres + Cloudflare media storage' }));
api.get('/health', async (c) => {
  const startedAt = Date.now();
  const dbStartedAt = Date.now();
  let databaseHealthy = false;
  let primaryDatabase = databasePrimary(c);
  try {
    if (primaryDatabase === 'supabase_postgres' && c.env.SUPABASE_URL && c.env.SUPABASE_SERVICE_ROLE_KEY) {
      await supabaseAdminSelectRows(c, 'app_users', {}, 'id', 1);
      databaseHealthy = true;
    } else {
      primaryDatabase = 'legacy_d1';
      const row: any = await c.env.DB.prepare('SELECT 1 AS ok').first();
      databaseHealthy = Number(row?.ok || 0) === 1;
    }
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
        primary: primaryDatabase,
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
    const d1Check = databasePrimary(c) === 'legacy_d1'
      ? await c.env.DB.prepare('SELECT 1 AS ok').first().then(() => true).catch(() => false)
      : null;
    let kvCheck = false;
    if (c.env.KV) {
      const key = `health:database:${uuid()}`;
      await c.env.KV.put(key, 'ok', { expirationTtl: 60 });
      const value = await c.env.KV.get(key);
      await c.env.KV.delete(key).catch(() => undefined);
      kvCheck = value === 'ok';
    }
    let supabasePostgresHealthy = false;
    if (c.env.SUPABASE_URL && c.env.SUPABASE_SERVICE_ROLE_KEY) {
      try {
        await supabaseAdminSelectRows(c, 'app_users', {}, 'id', 1);
        supabasePostgresHealthy = true;
      } catch {
        supabasePostgresHealthy = false;
      }
    }
    return c.json({
      primary_database: {
        provider: 'supabase_postgres',
        configured: databasePrimary(c) === 'supabase_postgres',
        healthy: supabasePostgresHealthy,
        note: 'Supabase Postgres is the canonical Captro app database for profiles, posts, interactions, reports, chat metadata, admin roles, and audit records.',
      },
      d1_sqlite_legacy_cache: {
        configured: true,
        healthy: d1Check,
        role: databasePrimary(c) === 'legacy_d1'
          ? 'legacy database mode only'
          : 'disabled for Supabase-primary production; Cloudflare D1 is not the Captro source of truth.',
      },
      kv_nosql: { configured: !!c.env.KV, healthy: kvCheck },
      postgres_hyperdrive: {
        configured: !!c.env.HYPERDRIVE,
        healthy: !!c.env.HYPERDRIVE,
        note: c.env.HYPERDRIVE ? 'Hyperdrive binding is available.' : 'Add a Hyperdrive binding after creating it with the Supabase Postgres connection string.',
      },
      supabase_postgres_jsonb: {
        configured: !!c.env.SUPABASE_URL,
        service_role_secret_set: !!c.env.SUPABASE_SERVICE_ROLE_KEY,
        healthy: supabasePostgresHealthy,
        note: 'Supabase stores relational data in Postgres and flexible NoSQL-style app_documents/editor metadata in JSONB.',
      },
      supabase_authentication: {
        configured: !!c.env.SUPABASE_URL,
        service_role_secret_set: !!c.env.SUPABASE_SERVICE_ROLE_KEY,
        anon_key_set: !!c.env.SUPABASE_ANON_KEY,
        note: 'Captro account creation and social sign-in are bridged into Supabase Authentication and linked by users.supabase_user_id.',
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

api.post('/bookmarks/setup-db', authMiddleware, async (c) => {
  await requireOwnerOrAdmin(c);
  return c.json({
    detail: 'Legacy D1 bookmark setup is retired. Captro bookmarks are managed in Supabase.',
    code: 'LEGACY_D1_SETUP_RETIRED',
  }, 410);
});

// Save/Bookmark a post
api.post('/bookmarks', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'bookmark_save');
  if (supabaseRequired) return supabaseRequired;
  const { post_id, collection } = await c.req.json().catch(() => ({}));
  const postId = publicId(post_id, 120);
  if (!postId) return c.json({ detail: 'post_id required' }, 400);
  const limited = await enforceRateLimit(c, 'save_post', userId, 240, 60);
  if (limited) return limited;
  try {
    const [post] = await supabaseReadVisiblePosts(c, userId, { postId, limit: 1 });
    if (!post) return c.json({ detail: 'Post not found' }, 404);
    const collectionName = cleanText(collection || 'saved', 80) || 'saved';
    const { state: engagement } = await setCanonicalPostSaveState(c, postId, userId, true, collectionName);
    return c.json(postEngagementResponse(engagement, { collection: collectionName }));
  } catch (e: any) {
    console.warn(JSON.stringify({ event: 'supabase_bookmark_save_failed', code: getErrorCode(e).slice(0, 180) }));
    return c.json({ detail: 'Save failed. Please try again.' }, 500);
  }
});

// Unsave/Remove bookmark
api.delete('/bookmarks/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'bookmark_delete');
  if (supabaseRequired) return supabaseRequired;
  const limited = await enforceRateLimit(c, 'save_post', userId, 240, 60);
  if (limited) return limited;
  const postId = publicId(c.req.param('postId'), 120);
  try {
    const { state: engagement } = await setCanonicalPostSaveState(c, postId, userId, false);
    return c.json(postEngagementResponse(engagement));
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_bookmark_delete_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not remove bookmark.' }, 500);
  }
});

// Get saved posts by collection
api.get('/bookmarks', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'bookmarks_read');
  if (supabaseRequired) return supabaseRequired;
  const collection = cleanText(c.req.query('collection'), 80);
  const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
  const limit = clampNumber(c.req.query('limit') || '40', 1, 80, 40);
  try {
    const postIds = await supabaseViewerInteractionPostIds(c, userId, 'save', { collection, limit, offset: skip });
    const rows = postIds.length ? await supabaseReadVisiblePosts(c, userId, { postIds, limit: postIds.length }) : [];
    return c.json({
      bookmarks: rows.map((post) => {
        const payload = feedPostPayload(post, [], c.env);
        return {
          ...payload,
          post_id: payload.id,
          post_date: payload.created_at,
          collection: collection || 'saved',
        };
      }),
    });
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_bookmarks_read_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not load bookmarks.' }, 500);
  }
});

// Check if post is saved
api.get('/bookmarks/check/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const supabaseRequired = requireSupabasePrimaryDatabase(c, 'bookmark_check');
  if (supabaseRequired) return supabaseRequired;
  const postId = publicId(c.req.param('postId'), 120);
  try {
    const relatedUserIds = await supabaseRelatedInteractionUserIds(c, userId);
    const saved = await supabaseViewerPostInteractionExists(c, postId, relatedUserIds, 'save');
    let collection: string | null = null;
    if (saved) {
      const identity = await supabaseResolvePostIdentity(c, postId);
      const keys = await supabaseInteractionActorKeys(c, relatedUserIds);
      const rows: any[] = [];
      if (keys.actorKeys.length) {
        rows.push(...await supabaseAdminSelectRowsIfShapeExists(c, 'app_post_interactions', {
          or: supabasePostIdentityOrFilter(identity),
          kind: postgrestEqFilter('save'),
          actor_key: postgrestInFilter(keys.actorKeys),
        }, 'collection', 1));
      }
      if (!rows.length && keys.appUserIds.length) {
        rows.push(...await supabaseAdminSelectRows(c, 'app_post_interactions', {
          or: supabasePostIdentityOrFilter(identity),
          kind: postgrestEqFilter('save'),
          app_user_id: postgrestInFilter(keys.appUserIds),
        }, 'collection', 1));
      }
      if (!rows.length && keys.authUserIds.length) {
        rows.push(...await supabaseAdminSelectRowsIfShapeExists(c, 'app_post_interactions', {
          or: supabasePostIdentityOrFilter(identity),
          kind: postgrestEqFilter('save'),
          user_id: postgrestInFilter(keys.authUserIds),
        }, 'collection', 1));
      }
      collection = cleanText(rows[0]?.collection, 80) || null;
    }
    return c.json({ saved, collection });
  } catch (error: any) {
    console.warn(JSON.stringify({ event: 'supabase_bookmark_check_failed', code: getErrorCode(error).slice(0, 180) }));
    return c.json({ detail: 'Could not check bookmark state.' }, 500);
  }
});

// ADMIN GOVERNANCE ENDPOINTS
// ═══════════════════════════════════════════════════════════════

// Helper: check admin
const requireAdmin = async (c: any) => {
  const admin = await requireAdminRole(c, 'admin:read');
  return admin.userId;
};

async function runDeletionStatement(env: Env, sql: string, binds: any[] = []) {
  try {
    await env.DB.prepare(sql).bind(...binds).run();
  } catch (error: any) {
    const message = String(error?.message || '');
    if (/no such (table|column)/i.test(message)) return;
    console.warn(JSON.stringify({ event: 'account_deletion_statement_failed', code: getErrorCode(error).slice(0, 160) }));
  }
}

async function queryDeletionRows(env: Env, sql: string, binds: any[] = []): Promise<any[]> {
  try {
    const result = await env.DB.prepare(sql).bind(...binds).all();
    return result.results as any[] || [];
  } catch (error: any) {
    const message = String(error?.message || '');
    if (/no such (table|column)/i.test(message)) return [];
    console.warn(JSON.stringify({ event: 'account_deletion_query_failed', code: getErrorCode(error).slice(0, 160) }));
    return [];
  }
}

async function deleteCloudflareMediaAsset(env: Env, asset: any) {
  const provider = cleanText(asset?.storage_provider || asset?.provider, 40);
  const key = cleanText(asset?.storage_key || asset?.provider_id, 240);
  if (!provider || !key) return;
  const accountId = cloudflareAccountId(env);
  const token = provider === 'stream' ? cloudflareStreamToken(env) : provider === 'images' ? cloudflareImagesToken(env) : '';
  if (provider === 'r2') {
    await env.MEDIA_BACKUP?.delete(key).catch(() => {});
    return;
  }
  if (!accountId || !token) return;
  const url = provider === 'stream'
    ? `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountId)}/stream/${encodeURIComponent(key)}`
    : provider === 'images'
      ? `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountId)}/images/v1/${encodeURIComponent(key)}`
      : '';
  if (!url) return;
  const response = await fetch(url, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  }).catch(() => null);
  if (response && !response.ok && response.status !== 404) {
    console.warn(JSON.stringify({
      event: 'cloudflare_media_delete_failed',
      provider,
      status: response.status,
      media_id: publicId(asset?.id || '', 120),
    }));
  }
}

function chunkDeletionValues<T>(values: T[], size = 50): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < values.length; i += size) out.push(values.slice(i, i + size));
  return out;
}

function dueDeletionScheduledAt(value: unknown, cutoffMs = Date.now()): boolean {
  const text = cleanText(value, 80);
  if (!text) return false;
  const scheduledMs = Date.parse(text);
  return Number.isFinite(scheduledMs) && scheduledMs <= cutoffMs;
}

async function supabaseDeleteRowsByAnyField(c: any, table: string, fieldValues: Array<[string, string]>) {
  for (const [field, value] of fieldValues) {
    const cleanValue = cleanText(value, 240);
    if (!field || !cleanValue) continue;
    await supabaseAdminDeleteRowsIfShapeExists(c, table, { [field]: postgrestEqFilter(cleanValue) })
      .catch((error: any) => console.warn(JSON.stringify({
        event: 'supabase_account_deletion_table_cleanup_failed',
        table,
        field,
        code: getErrorCode(error).slice(0, 180),
      })));
  }
}

async function supabaseDeleteRowsForPostIds(c: any, table: string, field: string, postIds: string[]) {
  const cleanPostIds = Array.from(new Set(postIds.map((postId) => cleanText(postId, 120)).filter(Boolean)));
  for (const chunk of chunkDeletionValues(cleanPostIds)) {
    await supabaseAdminDeleteRowsIfShapeExists(c, table, { [field]: postgrestInFilter(chunk) })
      .catch((error: any) => console.warn(JSON.stringify({
        event: 'supabase_account_deletion_post_cleanup_failed',
        table,
        field,
        code: getErrorCode(error).slice(0, 180),
      })));
  }
}

async function permanentlyDeleteSupabaseAccount(env: Env, row: any) {
  const c: any = { env };
  const user = supabaseAppUserToLegacyUser(row);
  const userId = publicId(user?.id, 120);
  if (!userId || String(user?.status || '') === 'deleted') return;
  const deletedAt = now();
  const authUserId = isUuidText(row?.supabase_user_id || user?.supabase_user_id);

  const identities = await supabaseAdminQueryRows(c, 'app_account_identities', {
    select: 'provider,provider_user_id,email_hash',
    filters: { user_id: postgrestEqFilter(userId) },
    limit: 200,
  }).catch(() => []);
  const identityRows = identities.length ? identities : [{
    provider: cleanText(user.oauth_provider || (user.email ? 'email' : ''), 40),
    provider_user_id: cleanText(user.oauth_subject || authUserId || '', 240),
    email_hash: user.email ? await privacyHash(c, normalizeOptionalEmail(user.email) || '') : '',
  }];
  for (const identity of identityRows) {
    await supabaseAdminUpsertSafe(c, 'app_deleted_account_safety_records', [{
      id: uuid(),
      user_id: userId,
      email_hash: cleanText(identity.email_hash || '', 160) || null,
      provider: cleanText(identity.provider || '', 40) || null,
      provider_user_id_hash: identity.provider_user_id ? await privacyHash(c, identity.provider_user_id) : null,
      status_at_deletion: cleanText(user.status || 'deletion_pending', 40),
      reason: cleanText(user.ban_reason || 'account_deletion', 160),
      metadata: {
        source: 'supabase_primary_scheduled_cleanup',
        deleted_at: deletedAt,
      },
      created_at: deletedAt,
    }], 'id');
  }

  const assets = await supabaseAdminQueryRows(c, 'app_media_assets', {
    select: 'id,storage_provider,storage_key,media_type',
    filters: { user_id: postgrestEqFilter(userId) },
    limit: 10000,
  }).catch(() => []);
  for (const asset of assets) await deleteCloudflareMediaAsset(env, asset);

  const postRows = await supabaseAdminQueryRows(c, 'app_posts', {
    select: 'legacy_post_id',
    filters: { app_user_id: postgrestEqFilter(userId) },
    limit: 10000,
  }).catch(() => []);
  const postIds = postRows.map((post: any) => cleanText(post.legacy_post_id, 120)).filter(Boolean);
  for (const table of ['app_post_places', 'post_comments', 'app_post_interactions', 'app_media_assets']) {
    await supabaseDeleteRowsForPostIds(c, table, 'legacy_post_id', postIds);
  }

  await supabaseDeleteRowsByAnyField(c, 'app_moderation_results', assets.map((asset: any) => ['media_id', cleanText(asset.id, 120)]));
  await supabaseDeleteRowsByAnyField(c, 'app_moderation_jobs', assets.map((asset: any) => ['media_id', cleanText(asset.id, 120)]));
  await supabaseDeleteRowsByAnyField(c, 'app_moderation_events', assets.map((asset: any) => ['media_id', cleanText(asset.id, 120)]));

  const userScopedDeletes: Array<[string, Array<[string, string]>]> = [
    ['app_push_tokens', [['user_id', userId]]],
    ['app_notifications', [['user_id', userId], ['from_user_id', userId]]],
    ['app_post_interactions', [['app_user_id', userId], ['user_id', authUserId || userId]]],
    ['post_comment_likes', [['app_user_id', userId], ['user_id', authUserId || userId]]],
    ['post_comments', [['app_user_id', userId], ['user_id', authUserId || userId]]],
    ['app_follows', [['app_follower_id', userId], ['app_following_id', userId]]],
    ['app_blocks', [['blocker_id', userId], ['blocked_id', userId]]],
    ['app_friend_requests', [['from_user_id', userId], ['to_user_id', userId]]],
    ['app_friendships', [['user_id', userId], ['friend_id', userId]]],
    ['app_reports', [['reporter_id', userId], ['target_owner_user_id', userId], ['assigned_to', userId], ['reviewed_by', userId]]],
    ['app_messages', [['sender_id', userId], ['receiver_id', userId]]],
    ['app_group_messages', [['sender_id', userId]]],
    ['app_group_chat_members', [['user_id', userId]]],
    ['app_group_chats', [['created_by', userId]]],
    ['app_stories', [['user_id', userId]]],
    ['app_story_likes', [['user_id', userId]]],
    ['app_story_views', [['user_id', userId]]],
    ['app_story_thoughts', [['user_id', userId]]],
    ['app_favorite_sounds', [['user_id', userId]]],
    ['app_client_events', [['user_id', userId]]],
    ['app_account_identities', [['user_id', userId]]],
  ];
  for (const [table, filters] of userScopedDeletes) await supabaseDeleteRowsByAnyField(c, table, filters);
  await supabaseDeleteRowsForPostIds(c, 'app_posts', 'legacy_post_id', postIds);

  await supabaseAdminPatchRows(c, 'app_users', { id: postgrestEqFilter(userId) }, {
    supabase_user_id: null,
    email: null,
    username: `deleted_${userId.slice(0, 12)}`,
    full_name: 'Deleted user',
    avatar_url: null,
    cover_url: null,
    bio: '',
    city: '',
    is_private: true,
    is_verified: false,
    counts: { followers_count: 0, following_count: 0, posts_count: 0 },
    profile: {},
    metadata: {
      status: 'deleted',
      deleted_at: deletedAt,
      permanent_deletion_completed_at: deletedAt,
    },
    updated_at: deletedAt,
  });

  await writeSupabaseAuditLog(c, {
    actionType: 'account_deletion_permanent_completed',
    actorUserId: 'system',
    actorRole: 'system',
    targetType: 'user',
    targetId: userId,
    targetUserId: userId,
    metadata: {
      deleted_at: deletedAt,
      deleted_media_count: assets.length,
      deleted_post_count: postIds.length,
    },
  }).catch((error: any) => console.warn(JSON.stringify({
    event: 'supabase_account_deletion_audit_failed',
    code: getErrorCode(error).slice(0, 180),
  })));

  if (authUserId) {
    await deleteSupabaseAuthUser(c, authUserId).catch((error: any) => {
      console.warn(JSON.stringify({ event: 'supabase_auth_permanent_delete_failed', code: getErrorCode(error).slice(0, 160), user_id: publicId(userId, 120) }));
    });
  }
}

async function permanentlyDeleteAccount(env: Env, user: any) {
  const userId = publicId(user?.id, 120);
  if (!userId || String(user?.status || '') === 'deleted') return;
  await ensureAccountDeletionSchema(env.DB);
  await ensureGovernanceSchema(env.DB);
  await ensurePremiumSchema(env.DB);
  await ensureCommentSchema(env.DB);
  await ensureMediaBackupSchema(env.DB);
  await ensureMediaModerationSchema(env.DB);

  const deletedAt = now();
  const identities = await queryDeletionRows(env, 'SELECT provider, provider_user_id, email_hash FROM account_identities WHERE user_id = ?', [userId]);
  const identityRows = identities.length ? identities : [{
    provider: cleanText(user.oauth_provider || (user.email ? 'email' : ''), 40),
    provider_user_id: cleanText(user.oauth_subject || user.supabase_user_id || '', 240),
    email_hash: user.email ? await privacyHash({ env }, normalizeOptionalEmail(user.email) || '') : '',
  }];
  for (const identity of identityRows) {
    await runDeletionStatement(env,
      `INSERT OR IGNORE INTO deleted_account_safety_records
       (id, user_id, email_hash, provider, provider_user_id_hash, status_at_deletion, reason, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        uuid(),
        userId,
        cleanText(identity.email_hash || '', 160),
        cleanText(identity.provider || '', 40),
        await privacyHash({ env }, identity.provider_user_id || ''),
        cleanText(user.status || 'deletion_pending', 40),
        cleanText(user.ban_reason || 'account_deletion', 160),
        deletedAt,
      ],
    );
  }

  const assets = await queryDeletionRows(env, 'SELECT * FROM media_assets WHERE user_id = ?', [userId]);
  for (const asset of assets) await deleteCloudflareMediaAsset(env, asset);
  const backups = await queryDeletionRows(env, 'SELECT id, r2_key FROM media_backups WHERE user_id = ?', [userId]);
  for (const backup of backups) {
    const key = cleanText(backup.r2_key, 500);
    if (key) await env.MEDIA_BACKUP?.delete(key).catch(() => {});
  }

  const deletionStatements: Array<[string, any[]]> = [
    ['DELETE FROM push_tokens WHERE user_id = ?', [userId]],
    ['DELETE FROM saved_posts WHERE user_id = ?', [userId]],
    ['DELETE FROM bookmarks WHERE user_id = ?', [userId]],
    ['DELETE FROM likes WHERE user_id = ?', [userId]],
    ['DELETE FROM comment_likes WHERE user_id = ?', [userId]],
    ['DELETE FROM follows WHERE follower_id = ? OR following_id = ?', [userId, userId]],
    ['DELETE FROM friendships WHERE user_id = ? OR friend_id = ?', [userId, userId]],
    ['DELETE FROM friend_requests WHERE from_user_id = ? OR to_user_id = ?', [userId, userId]],
    ['DELETE FROM blocks WHERE blocker_id = ? OR blocked_id = ?', [userId, userId]],
    ['DELETE FROM notifications WHERE user_id = ? OR from_user_id = ?', [userId, userId]],
    ['DELETE FROM comments WHERE user_id = ?', [userId]],
    ['DELETE FROM note_comment_likes WHERE user_id = ?', [userId]],
    ['DELETE FROM note_comments WHERE user_id = ?', [userId]],
    ['DELETE FROM note_interactions WHERE user_id = ?', [userId]],
    ['DELETE FROM note_reports WHERE reporter_id = ?', [userId]],
    ['DELETE FROM notes WHERE user_id = ?', [userId]],
    ['DELETE FROM statuses WHERE user_id = ?', [userId]],
    ['DELETE FROM messages WHERE sender_id = ? OR receiver_id = ?', [userId, userId]],
    ['DELETE FROM message_typing WHERE user_id = ? OR peer_id = ?', [userId, userId]],
    ['DELETE FROM user_presence WHERE user_id = ?', [userId]],
    ['DELETE FROM group_messages WHERE sender_id = ?', [userId]],
    ['DELETE FROM group_chat_members WHERE user_id = ?', [userId]],
    ['DELETE FROM media_assets WHERE user_id = ?', [userId]],
    ['DELETE FROM media_backups WHERE user_id = ?', [userId]],
    ['DELETE FROM posts WHERE user_id = ?', [userId]],
    ['DELETE FROM account_identities WHERE user_id = ?', [userId]],
  ];
  for (const [sql, binds] of deletionStatements) await runDeletionStatement(env, sql, binds);

  const deletedPasswordHash = await hashPassword(`deleted:${userId}:${uuid()}`);
  await runDeletionStatement(env,
    `UPDATE users SET
       status = 'deleted',
       email = ?,
       username = ?,
       full_name = 'Deleted user',
       password_hash = ?,
       bio = '',
       profile_image = '',
       cover_image = '',
       city = '',
       followers_count = 0,
       following_count = 0,
       posts_count = 0,
       deleted_at = ?,
       updated_at = datetime('now')
     WHERE id = ?`,
    [`deleted_${userId}@deleted.flames-up.local`, `deleted_${userId.slice(0, 12)}`, deletedPasswordHash, deletedAt, userId],
  );
  await runDeletionStatement(env, "UPDATE users SET oauth_provider = '' WHERE id = ?", [userId]);
  await runDeletionStatement(env, "UPDATE users SET oauth_subject = '' WHERE id = ?", [userId]);
  await runDeletionStatement(env, 'UPDATE users SET supabase_user_id = NULL WHERE id = ?', [userId]);
  await runDeletionStatement(env, 'UPDATE users SET phone = NULL, phone_verified = 0 WHERE id = ?', [userId]);

  await runDeletionStatement(env,
    `INSERT INTO account_deletion_events (id, user_id, event_type, actor_user_id, reason, metadata, request_id, created_at)
     VALUES (?, ?, 'deletion_permanent_completed', '', 'scheduled_30_day_cleanup', ?, '', ?)`,
    [uuid(), userId, JSON.stringify({ deleted_at: deletedAt }), deletedAt],
  );
  if (user.supabase_user_id) {
    await deleteSupabaseAuthUser({ env }, user.supabase_user_id).catch((error: any) => {
      console.warn(JSON.stringify({ event: 'supabase_auth_permanent_delete_failed', code: getErrorCode(error).slice(0, 160), user_id: publicId(userId, 120) }));
    });
  }
}

async function processAccountDeletionQueue(env: Env, limit = 20) {
  const c: any = { env };
  if (supabasePrimaryConfigured(c)) {
    const rows = await supabaseAdminQueryRows(c, 'app_users', {
      select: SUPABASE_APP_USER_SELECT,
      filters: { 'metadata->>status': postgrestEqFilter('deletion_pending') },
      order: 'updated_at.asc',
      limit: Math.max(limit * 5, limit),
    }).catch((error: any) => {
      console.warn(JSON.stringify({ event: 'supabase_account_deletion_due_lookup_failed', code: getErrorCode(error).slice(0, 180) }));
      return [];
    });
    const due = rows
      .filter((account: any) => dueDeletionScheduledAt((parseJsonObject(account?.metadata) as any).deletion_scheduled_at))
      .slice(0, limit);
    for (const account of due) {
      try {
        await permanentlyDeleteSupabaseAccount(env, account);
      } catch (error: any) {
        console.warn(JSON.stringify({
          event: 'supabase_account_deletion_cleanup_failed',
          code: getErrorCode(error).slice(0, 180),
          user_id: publicId(account?.id || '', 120),
        }));
      }
    }
    return;
  }
  if (supabasePrimaryRequestedForEnv(env)) {
    console.warn(JSON.stringify({
      event: 'supabase_primary_required',
      feature: 'account_deletion_queue',
    }));
    return;
  }
  await ensureAccountDeletionSchema(env.DB);
  const due = await queryDeletionRows(env,
    `SELECT * FROM users
     WHERE status = 'deletion_pending'
       AND deletion_scheduled_at IS NOT NULL
       AND datetime(deletion_scheduled_at) <= datetime(?)
     ORDER BY deletion_scheduled_at ASC
     LIMIT ?`,
    [now(), limit],
  );
  for (const user of due) {
    try {
      await permanentlyDeleteAccount(env, user);
    } catch (error: any) {
      console.warn(JSON.stringify({
        event: 'account_deletion_cleanup_failed',
        code: getErrorCode(error).slice(0, 180),
        user_id: publicId(user?.id || '', 120),
      }));
    }
  }
}

api.route('/scan', createCaptroScanRoutes(authMiddleware, getUserId, enforceRateLimit));

// Mount API routes on app
app.route('/api', api);

async function handleMediaModerationQueue(batch: MessageBatch<MediaModerationJobMessage>, env: Env, _ctx: ExecutionContext) {
  for (const message of batch.messages) {
    try {
      await processMediaModerationJob(env, message.body, 'queue');
      message.ack();
    } catch (error: any) {
      console.warn(JSON.stringify({
        event: 'media_moderation_queue_failed',
        code: getErrorCode(error).slice(0, 180),
        media_id: publicId(message.body?.mediaId || '', 160),
      }));
      message.retry();
    }
  }
}

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext) {
    return app.fetch(request, env, ctx);
  },
  queue: handleMediaModerationQueue,
  scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(processAccountDeletionQueue(env));
  },
};
