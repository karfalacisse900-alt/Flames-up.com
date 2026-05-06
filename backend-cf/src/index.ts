// Flames-Up Cloudflare Workers API — Hono + D1 + CF Images + CF Stream
// Deploy: wrangler deploy
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import bcrypt from 'bcryptjs';
import { RtcRole, RtcTokenBuilder } from 'agora-token';

// ─── Types ───────────────────────────────────────────────────────────────────
type WorkersAiBinding = {
  run: (model: string, input: unknown, options?: unknown) => Promise<unknown>;
};

interface Env {
  DB: D1Database;
  KV?: KVNamespace;
  MEDIA_BACKUP?: R2Bucket;
  AI?: WorkersAiBinding;
  JWT_SECRET: string;
  CLOUDFLARE_ACCOUNT_ID: string;
  CLOUDFLARE_IMAGES_ACCOUNT_HASH?: string;
  CLOUDFLARE_IMAGES_TOKEN: string;
  CLOUDFLARE_STREAM_TOKEN: string;
  MAPBOX_ACCESS_TOKEN?: string;
  EVENTBRITE_API_TOKEN?: string;
  EVENTS_PREVIEW?: string;
  FRONTEND_URL: string;
  OWNER_USERNAMES?: string;
  GOOGLE_OAUTH_CLIENT_ID?: string;
  GOOGLE_OAUTH_CLIENT_IDS?: string;
  APPLE_OAUTH_AUDIENCE?: string;
  APPLE_OAUTH_AUDIENCES?: string;
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_AUTH_TOKEN?: string;
  TWILIO_VERIFY_SERVICE_SID?: string;
  TWILIO_SERVICE_SID?: string;
  TWILIO_FROM_PHONE?: string;
  AGORA_APP_ID?: string;
  AGORA_APP_CERTIFICATE?: string;
  AGORA_TOKEN_TTL_SECONDS?: string;
  MEDIA_AI_ENHANCEMENT?: string;
  MEDIA_AI_MODEL?: string;
  MEDIA_BACKUP_MAX_VIDEO_BYTES?: string;
  ELEVENLABS_API_KEY?: string;
  MUSIC_DAILY_GENERATION_LIMIT?: string;
  MUSIC_GENERATION_COOLDOWN_SECONDS?: string;
}

type HonoApp = { Bindings: Env; Variables: { userId: string } };

const app = new Hono<HonoApp>();

// Root handler
app.get('/', (c) => c.json({ name: 'Flames-Up API', version: '2.0', status: 'live', docs: '/api/health' }));

const api = new Hono<HonoApp>();

// ─── CORS ────────────────────────────────────────────────────────────────────
const ALLOWED_ORIGINS = [
  'https://flames-up.com',
  'https://www.flames-up.com',
  'https://flames-up-preview.preview.emergentagent.com',
  'http://localhost:3000',
  'http://localhost:8081',
  'http://localhost:8083',
  'http://localhost:8084',
  'http://localhost:8085',
  'exp://localhost:8081',
];
const corsOpts = {
  origin: (o: string) => ALLOWED_ORIGINS.includes(o) ? o : ALLOWED_ORIGINS[0],
  allowMethods: ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowHeaders: ['Authorization', 'Content-Type', 'Range'],
  exposeHeaders: ['Accept-Ranges', 'Content-Length', 'Content-Range', 'Content-Type', 'ETag'],
};
app.use('*', cors(corsOpts));
api.use('*', cors(corsOpts));

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

  try {
    const { jwtVerify } = await import('jose');
    const verified = await jwtVerify(token, new TextEncoder().encode(getJwtSecret(c)));
    payload = verified.payload;
    c.set('jwtPayload', payload);
  } catch (error: any) {
    if (getErrorCode(error).includes('JWT_SECRET_MISSING')) {
      return c.json({ detail: 'Auth service is not configured.', code: 'JWT_SECRET_MISSING' }, 503);
    }
    return c.json({ detail: 'Invalid token', code: 'INVALID_TOKEN' }, 401);
  }

  const userId = String(payload?.sub || payload?.userId || '');
  if (!userId) return c.json({ detail: 'Invalid token', code: 'INVALID_TOKEN' }, 401);

  try {
    let user: any;
    try {
      user = await c.env.DB.prepare('SELECT id, status FROM users WHERE id = ?').bind(userId).first();
    } catch (error: any) {
      const message = String(error?.message || '');
      if (!message.includes('no such column: status')) throw error;
      user = await c.env.DB.prepare("SELECT id, 'active' AS status FROM users WHERE id = ?").bind(userId).first();
    }

    if (!user) return c.json({ detail: 'Session user was not found.', code: 'USER_NOT_FOUND' }, 401);

    if (String(user?.status || 'active') === 'banned') {
      return c.json({ detail: 'This account has been banned.' }, 403);
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

  try {
    const token = authHeader.slice(7);
    const { jwtVerify } = await import('jose');
    const verified = await jwtVerify(token, new TextEncoder().encode(getJwtSecret(c)));
    const payload: any = verified.payload;
    const userId = String(payload?.sub || payload?.userId || '');
    if (!userId) return '';

    let user: any;
    try {
      user = await c.env.DB.prepare('SELECT id, status FROM users WHERE id = ?').bind(userId).first();
    } catch (error: any) {
      const message = String(error?.message || '');
      if (!message.includes('no such column: status')) throw error;
      user = await c.env.DB.prepare("SELECT id, 'active' AS status FROM users WHERE id = ?").bind(userId).first();
    }

    if (!user || String(user?.status || 'active') === 'banned') return '';
    c.set('jwtPayload', payload);
    return userId;
  } catch {
    return '';
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
    .replace(/[^a-z0-9_]/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '');
  return base || `user_${Math.floor(Math.random() * 100000)}`;
}

async function ensureUniqueUsername(db: D1Database, desired: string): Promise<string> {
  const base = usernameSlug(desired).slice(0, 24);
  let candidate = base;
  let attempt = 0;

  while (attempt < 100) {
    const existing = await db.prepare('SELECT id FROM users WHERE LOWER(username) = ?').bind(candidate.toLowerCase()).first();
    if (!existing) return candidate;
    attempt += 1;
    candidate = `${base}_${Math.floor(Math.random() * 9999)}`.slice(0, 30);
  }

  return `${base}_${Date.now().toString().slice(-6)}`.slice(0, 30);
}

let phoneAuthSchemaReady = false;
let oauthSchemaReady = false;
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

async function ensurePrivacySchema(db: D1Database) {
  if (privacySchemaReady) return;

  const statements = [
    'ALTER TABLE users ADD COLUMN is_private INTEGER DEFAULT 0',
    "ALTER TABLE users ADD COLUMN language TEXT DEFAULT 'en'",
    "ALTER TABLE posts ADD COLUMN visibility TEXT DEFAULT 'public'",
    "ALTER TABLE statuses ADD COLUMN visibility TEXT DEFAULT 'public'",
    'CREATE INDEX IF NOT EXISTS idx_users_private ON users(is_private)',
    'CREATE INDEX IF NOT EXISTS idx_posts_visibility ON posts(visibility)',
    'CREATE INDEX IF NOT EXISTS idx_statuses_visibility ON statuses(visibility)',
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
    "ALTER TABLE posts ADD COLUMN editor_overlays TEXT DEFAULT '[]'",
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
    `CREATE TABLE IF NOT EXISTS note_reports (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      reporter_id TEXT NOT NULL,
      reason TEXT DEFAULT '',
      details TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      UNIQUE(note_id, reporter_id)
    )`,
    'CREATE INDEX IF NOT EXISTS idx_notes_status_created ON notes(status, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_notes_user_created ON notes(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_note_interactions_user ON note_interactions(user_id, kind, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_note_comments_note ON note_comments(note_id, created_at)',
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
    "ALTER TABLE reports ADD COLUMN reported_type TEXT DEFAULT ''",
    "ALTER TABLE reports ADD COLUMN details TEXT DEFAULT ''",
    "ALTER TABLE reports ADD COLUMN status TEXT DEFAULT 'pending'",
    "ALTER TABLE reports ADD COLUMN admin_notes TEXT DEFAULT ''",
    'ALTER TABLE reports ADD COLUMN reviewed_by TEXT',
    "ALTER TABLE reports ADD COLUMN action_taken TEXT DEFAULT ''",
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
    'CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status)',
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

async function ensureMediaBackupSchema(db: D1Database) {
  if (mediaBackupSchemaReady) return;

  const statements = [
    "ALTER TABLE posts ADD COLUMN media_backup_ids TEXT DEFAULT '[]'",
    `CREATE TABLE IF NOT EXISTS media_backups (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      post_id TEXT,
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
    'CREATE INDEX IF NOT EXISTS idx_media_backups_user ON media_backups(user_id, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_media_backups_post ON media_backups(post_id)',
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
    'CREATE INDEX IF NOT EXISTS idx_posts_audio_track ON posts(audio_provider, audio_track_id)',
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
  return `(${alias}.id = ? OR COALESCE(${alias}.is_private, 0) = 0 OR EXISTS (SELECT 1 FROM friendships f WHERE f.user_id = ? AND f.friend_id = ${alias}.id))`;
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
  return [userId, userId, userId, userId, userId, userId];
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

function cleanText(value: unknown, max = 500): string {
  return String(value || '').trim().slice(0, max);
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
  try {
    const url = new URL(raw.startsWith('http://') || raw.startsWith('https://') ? raw : `https://${raw}`);
    if (!['http:', 'https:'].includes(url.protocol)) return '';
    return url.toString();
  } catch {
    return '';
  }
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
    } else if (host.includes('youtube.com')) {
      const id = url.searchParams.get('v') || url.pathname.match(/\/(?:shorts|embed)\/([^/?#]+)/)?.[1] || '';
      if (id) {
        result.provider = 'youtube';
        result.external_id = id;
        result.embed_url = `https://www.youtube.com/embed/${encodeURIComponent(id)}`;
        result.thumbnail_url ||= `https://img.youtube.com/vi/${encodeURIComponent(id)}/hqdefault.jpg`;
      }
    } else if (host.includes('vimeo.com')) {
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
    } else if (host.includes('goodreads.com')) {
      result.provider = 'book';
    } else if (host.includes('letterboxd.com') || host.includes('imdb.com')) {
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

const AUDIUS_APP_NAME = 'Flames Up';
const AUDIUS_BASE_URL = 'https://discoveryprovider.audius.co/v1';

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
  const id = String(track?.id || track?.track_id || '');
  return {
    id,
    track_id: id,
    numeric_track_id: track?.track_id || null,
    title: cleanText(track?.title || 'Untitled track', 180),
    artist: cleanText(user?.name || user?.handle || 'Audius artist', 120),
    artwork_url: artwork?.['480x480'] || artwork?.['1000x1000'] || artwork?.['150x150'] || '',
    duration: clampNumber(track?.duration, 0, 60 * 60 * 6, 0),
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
    'image/gif': 'gif',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
  };
  return map[normalized] || fallback;
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

async function sha256BinaryHex(input: ArrayBuffer | Uint8Array): Promise<string> {
  const buffer = input instanceof Uint8Array ? bytesToArrayBuffer(input) : input;
  const hash = await crypto.subtle.digest('SHA-256', buffer);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function maxBackupVideoBytes(c: any): number {
  const raw = Number(c.env.MEDIA_BACKUP_MAX_VIDEO_BYTES || 95_000_000);
  return Number.isFinite(raw) && raw > 0 ? raw : 95_000_000;
}

function mediaDeliveryUrl(c: any, backupId: string): string {
  const origin = new URL(c.req.url).origin;
  return `${origin}/api/media/${encodeURIComponent(backupId)}`;
}

async function maybeEnhanceImage(c: any, bytes: Uint8Array, contentType: string) {
  const mode = String(c.env.MEDIA_AI_ENHANCEMENT || 'off').toLowerCase();
  if (mode !== 'on' && mode !== 'flux2') {
    return { bytes, contentType, status: 'disabled' };
  }
  if (!c.env.AI) {
    return { bytes, contentType, status: 'missing_ai_binding' };
  }

  try {
    const form = new FormData();
    const ext = contentTypeExtension(contentType, 'jpg');
    form.append('prompt', 'Enhance this user-uploaded social media photo. Preserve the original subject, composition, people, identity, and text. Improve clarity, exposure, and detail naturally.');
    form.append('input_image_0', new Blob([bytesToArrayBuffer(bytes)], { type: contentType }), `source.${ext}`);
    form.append('width', '1024');
    form.append('height', '1024');

    const formResponse = new Response(form);
    const model = String(c.env.MEDIA_AI_MODEL || '@cf/black-forest-labs/flux-2-klein-9b');
    const result = await c.env.AI.run(model, {
      multipart: {
        body: formResponse.body,
        contentType: formResponse.headers.get('content-type') || 'multipart/form-data',
      },
    }) as { image?: string };

    if (!result?.image) {
      return { bytes, contentType, status: 'no_ai_output' };
    }

    const enhanced = dataUriToBytes(result.image, 'image/png');
    return { bytes: enhanced.bytes, contentType: enhanced.contentType, status: 'enhanced' };
  } catch (error: any) {
    console.log('Workers AI enhancement failed:', error?.message || error);
    return { bytes, contentType, status: 'failed' };
  }
}

async function storeMediaBackup(c: any, opts: {
  userId: string;
  postId?: string | null;
  mediaKind: 'image' | 'video';
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
  const ext = contentTypeExtension(opts.contentType, opts.mediaKind === 'image' ? 'jpg' : 'mp4');
  const filename = sanitizeMediaName(opts.originalFilename || opts.providerId || id, opts.mediaKind);
  const key = `users/${opts.userId}/${date}/${id}-${filename}.${ext}`;
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

function postPayload(post: any, likedBy: string[] = []) {
  const audioHidden = Number(post.audio_hidden || 0) === 1;
  const payload = {
    ...post,
    images: parseJsonArray(post.images),
    media_types: parseJsonArray(post.media_types),
    media_backup_ids: parseJsonArray(post.media_backup_ids),
    editor_overlays: parseJsonArray(post.editor_overlays),
    liked_by: likedBy,
    is_verified_checkin: !!post.is_verified_checkin,
  };
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

async function isFriend(db: D1Database, userId: string, targetId: string): Promise<boolean> {
  const friendship = await db.prepare('SELECT id FROM friendships WHERE user_id = ? AND friend_id = ?').bind(userId, targetId).first();
  return !!friendship;
}

async function canViewUserContent(db: D1Database, viewerId: string, owner: any): Promise<boolean> {
  if (!owner) return false;
  if (viewerId === owner.id) return true;
  if (!owner.is_private) return true;
  return isFriend(db, viewerId, owner.id);
}

function safeUserPayload(user: any) {
  const { password_hash, ...safe } = user;
  return {
    ...safe,
    is_private: !!safe.is_private,
    language: normalizeLanguage(safe.language),
  };
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
  return email.includes('@') ? email : '';
}

function normalizeOptionalName(value: unknown): string {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function internalOAuthEmail(provider: 'google' | 'apple', subject: string): string {
  const safeSubject = subject.replace(/[^a-z0-9]/gi, '').toLowerCase().slice(0, 48) || 'user';
  return `${provider}_${safeSubject}@oauth.flames-up.local`;
}

function isInternalOAuthEmail(email: unknown): boolean {
  return String(email || '').toLowerCase().endsWith('@oauth.flames-up.local');
}

function publicUserEmail(email: unknown): string {
  return isInternalOAuthEmail(email) ? '' : String(email || '');
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

const EVENTBRITE_API_BASE = 'https://www.eventbriteapi.com/v3';
const NYC_OPEN_DATA_EVENTS_URL = 'https://data.cityofnewyork.us/resource/tvpp-9vvx.json';
const MAPBOX_SEARCH_BOX_API_BASE = 'https://api.mapbox.com/search/searchbox/v1';
const EVENT_LOOKAHEAD_DAYS = 45;
const EVENTBRITE_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const EVENTBRITE_WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

const EVENT_INTEREST_MAP: Record<string, { queries: string[]; categories?: string[] }> = {
  fashion: { queries: ['fashion show', 'style', 'beauty'], categories: ['106'] },
  beauty: { queries: ['beauty', 'makeup', 'fashion'], categories: ['106'] },
  sport: { queries: ['sports', 'fitness', 'basketball'], categories: ['108'] },
  sports: { queries: ['sports', 'fitness', 'basketball'], categories: ['108'] },
  fitness: { queries: ['fitness', 'workout', 'wellness'], categories: ['108', '107'] },
  club: { queries: ['club', 'nightlife', 'party', 'dance'] },
  nightlife: { queries: ['nightlife', 'club', 'party', 'dance'] },
  party: { queries: ['party', 'club', 'nightlife'] },
  movie: { queries: ['movie', 'film screening', 'cinema'], categories: ['104'] },
  film: { queries: ['film screening', 'movie', 'cinema'], categories: ['104'] },
  music: { queries: ['live music', 'concert', 'dj'], categories: ['103'] },
  food: { queries: ['food festival', 'tasting', 'farmers market'], categories: ['110'] },
  art: { queries: ['art', 'gallery', 'creative'], categories: ['105'] },
  culture: { queries: ['culture', 'community', 'festival'], categories: ['113'] },
  tech: { queries: ['technology', 'startup', 'tech meetup'], categories: ['102'] },
  business: { queries: ['business', 'networking', 'entrepreneur'], categories: ['101'] },
  wellness: { queries: ['wellness', 'yoga', 'health'], categories: ['107'] },
};

const MAPBOX_EVENT_PLANS = [
  {
    id: 'tonight-clubs',
    title: 'Night events tonight',
    host: 'Flames nightlife guide',
    keyword: 'club party nightlife',
    weekday: null as number | null,
    startHour: 20,
    endHour: 2,
    description: 'A nightlife pick shaped by your event preferences. Check the venue page for the exact lineup before you go.',
  },
  {
    id: 'live-music',
    title: 'Live music tonight',
    host: 'Flames music guide',
    keyword: 'live music',
    weekday: null as number | null,
    startHour: 19,
    endHour: 23,
    description: 'A live night plan picked from your music and going-out signals.',
  },
  {
    id: 'movie-night',
    title: 'Movie night',
    host: 'Flames movie guide',
    keyword: 'movie film cinema',
    weekday: null as number | null,
    startHour: 19,
    endHour: 22,
    description: 'A movie plan picked from your entertainment and culture signals.',
  },
  {
    id: 'weekend-parks',
    title: 'Park happenings',
    host: 'Flames park guide',
    keyword: 'events',
    weekday: 6 as number | null,
    startHour: 11,
    endHour: 19,
    description: 'A park-based plan for public programming, markets, or seasonal pop-ups.',
  },
  {
    id: 'sports-weekend',
    title: 'Sports nearby',
    host: 'Flames sports guide',
    keyword: 'sports game',
    weekday: 6 as number | null,
    startHour: 15,
    endHour: 18,
    description: 'A nearby sports venue pick shaped by your activity and fan interests.',
  },
];

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

function buildEventPreference(user: any, explicitQuery?: string) {
  const rawTerms = uniq([
    ...parsePreferenceList(user?.interests),
    ...parsePreferenceList(user?.looking_for),
    ...(explicitQuery ? [explicitQuery.toLowerCase()] : []),
  ]);
  const queries: string[] = [];
  const categories: string[] = [];

  for (const term of rawTerms) {
    const normalized = term.replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
    if (!normalized) continue;
    let mapped = false;

    for (const [key, config] of Object.entries(EVENT_INTEREST_MAP)) {
      if (normalized.includes(key)) {
        queries.push(...config.queries);
        if (config.categories) categories.push(...config.categories);
        mapped = true;
      }
    }

    if (!mapped) queries.push(normalized);
  }

  const fallbackQueries = ['events tonight', 'live music', 'food festival', 'art', 'fitness'];

  return {
    terms: rawTerms,
    queries: uniq(queries.length > 0 ? queries : fallbackQueries).slice(0, 6),
    categories: uniq(categories).slice(0, 4),
  };
}

function stripHtml(value: unknown): string {
  return String(value || '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function eventbriteClock(date: Date): string {
  let hour = date.getHours();
  const minute = `${date.getMinutes()}`.padStart(2, '0');
  const suffix = hour >= 12 ? 'PM' : 'AM';
  hour = hour % 12 || 12;
  return `${`${hour}`.padStart(2, '0')}:${minute}${suffix}`;
}

function eventbriteDateParts(startLocal: string, endLocal?: string) {
  const start = startLocal ? new Date(startLocal) : new Date();
  const end = endLocal ? new Date(endLocal) : null;
  const weekday = EVENTBRITE_WEEKDAYS[start.getDay()];
  const month = EVENTBRITE_MONTHS[start.getMonth()];
  const day = `${start.getDate()}`.padStart(2, '0');
  const dateLabel = `${weekday}, ${month} ${start.getDate()} at ${eventbriteClock(start)}`;
  const schedule = end ? `${dateLabel} - ${eventbriteClock(end)}` : dateLabel;
  const today = new Date();
  const isToday =
    start.getFullYear() === today.getFullYear() &&
    start.getMonth() === today.getMonth() &&
    start.getDate() === today.getDate();
  const isWeekend = start.getDay() === 0 || start.getDay() === 6;

  return {
    weekday,
    month,
    day,
    schedule,
    shortTime: isToday ? 'Tonight' : isWeekend ? 'This weekend' : weekday,
  };
}

function eventbriteAddress(venue: any): string {
  const address = venue?.address || {};
  return address.localized_address_display || address.address_1 || address.city || venue?.name || 'Eventbrite venue';
}

function eventbriteEventToCard(event: any, reason: string, rank: number) {
  const date = eventbriteDateParts(event?.start?.local, event?.end?.local);
  const venue = event?.venue || {};
  const image = event?.logo?.original?.url || event?.logo?.url || '';
  const description = stripHtml(event?.summary || event?.description?.text);
  const category = event?.category?.short_name || event?.category?.name || reason;

  return {
    event: true,
    event_source: 'eventbrite',
    event_id: `eventbrite-${event.id}`,
    place_id: `eventbrite-${event.id}`,
    eventbrite_id: event.id,
    event_url: event.url || '',
    name: event?.name?.text || 'Eventbrite event',
    event_title: event?.name?.text || 'Eventbrite event',
    event_host: 'Eventbrite',
    event_venue: venue?.name || (event?.online_event ? 'Online event' : 'Eventbrite venue'),
    event_address: event?.online_event ? 'Online event' : eventbriteAddress(venue),
    event_description: description || `A ${category.toLowerCase()} event picked from your Flames preferences.`,
    event_time_label: date.shortTime,
    event_schedule: date.schedule,
    event_start: event?.start?.utc || event?.start?.local || '',
    event_weekday: date.weekday,
    event_month: date.month,
    event_day: date.day,
    attendees: 3 + ((Number(event?.id || rank) || rank) % 8),
    category,
    preference_reason: reason,
    photo_url: image,
    lat: venue?.latitude ? Number(venue.latitude) : null,
    lng: venue?.longitude ? Number(venue.longitude) : null,
    source_rank: rank,
  };
}

function nycBoroughFromLocation(location: { address: string; lat?: string; lng?: string }): string | null {
  const address = String(location.address || '').toLowerCase();
  if (address.includes('brooklyn')) return 'Brooklyn';
  if (address.includes('queens')) return 'Queens';
  if (address.includes('bronx')) return 'Bronx';
  if (address.includes('staten island')) return 'Staten Island';
  if (address.includes('manhattan') || address.includes('new york') || address.includes('nyc')) return 'Manhattan';

  const lat = Number(location.lat);
  const lng = Number(location.lng);
  if (Number.isFinite(lat) && Number.isFinite(lng) && lat > 40.45 && lat < 40.95 && lng > -74.3 && lng < -73.65) {
    return 'Manhattan';
  }

  return null;
}

function nycOpenDataEventToCard(event: any, rank: number) {
  const start = String(event.start_date_time || '');
  const end = String(event.end_date_time || '');
  const validEnd = Date.parse(end) > Date.parse(start) ? end : undefined;
  const date = eventbriteDateParts(start, validEnd);
  const eventType = event.event_type || 'City event';
  const venue = event.event_location || `${event.event_borough || 'NYC'} event`;

  return {
    event: true,
    event_source: 'nyc_open_data',
    event_id: `nyc-${event.event_id || rank}`,
    place_id: `nyc-${event.event_id || rank}`,
    eventbrite_id: '',
    event_url: '',
    name: event.event_name || eventType,
    event_title: event.event_name || eventType,
    event_host: event.event_agency || 'City of New York',
    event_venue: venue,
    event_address: venue,
    event_description: `${eventType} from NYC Open Data, matched to your local event preferences.`,
    event_time_label: date.shortTime,
    event_schedule: date.schedule,
    event_start: start,
    event_weekday: date.weekday,
    event_month: date.month,
    event_day: date.day,
    attendees: 3 + ((Number(event.event_id || rank) || rank) % 8),
    category: eventType,
    source_rank: rank,
  };
}

async function fetchNycOpenDataEvents(location: { address: string; lat?: string; lng?: string }) {
  const borough = nycBoroughFromLocation(location);
  if (!borough) return [];

  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + EVENT_LOOKAHEAD_DAYS);

  const where = [
    `start_date_time >= '${start.toISOString().slice(0, 19)}'`,
    `start_date_time <= '${end.toISOString().slice(0, 19)}'`,
    `event_borough = '${borough.replace(/'/g, "''")}'`,
  ].join(' AND ');
  const params = new URLSearchParams({
    '$select': 'event_id,event_name,start_date_time,end_date_time,event_agency,event_type,event_borough,event_location',
    '$where': where,
    '$order': 'start_date_time ASC',
    '$limit': '80',
  });

  const response = await fetch(`${NYC_OPEN_DATA_EVENTS_URL}?${params.toString()}`);
  if (!response.ok) throw new Error(`NYC_OPEN_DATA_FAILED:${response.status}`);

  const data: any = await response.json();
  return Array.isArray(data) ? data : [];
}

async function fetchEventbriteEvents(c: any, query: string, category: string | undefined, location: { address: string; lat?: string; lng?: string }) {
  const token = String(c.env.EVENTBRITE_API_TOKEN || '').trim();
  if (!token) throw new Error('EVENTBRITE_TOKEN_MISSING');

  const start = new Date();
  const end = new Date(start);
  end.setDate(end.getDate() + EVENT_LOOKAHEAD_DAYS);

  const params = new URLSearchParams({
    q: query,
    sort_by: 'date',
    expand: 'venue,logo,category',
    page_size: '12',
    'start_date.range_start': start.toISOString(),
    'start_date.range_end': end.toISOString(),
  });

  if (category) params.set('categories', category);
  if (location.lat && location.lng) {
    params.set('location.latitude', location.lat);
    params.set('location.longitude', location.lng);
  } else {
    params.set('location.address', location.address);
  }
  params.set('location.within', '25mi');

  const response = await fetch(`${EVENTBRITE_API_BASE}/events/search/?${params.toString()}`, {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (!response.ok) {
    if (response.status === 404) throw new Error('EVENTBRITE_PUBLIC_SEARCH_UNAVAILABLE');
    throw new Error(`EVENTBRITE_SEARCH_FAILED:${response.status}`);
  }

  const data: any = await response.json();
  return Array.isArray(data.events) ? data.events : [];
}

async function fetchOwnedEventbriteEvents(c: any) {
  const token = String(c.env.EVENTBRITE_API_TOKEN || '').trim();
  if (!token) throw new Error('EVENTBRITE_TOKEN_MISSING');

  const headers = { Authorization: `Bearer ${token}` };
  const orgResponse = await fetch(`${EVENTBRITE_API_BASE}/users/me/organizations/`, { headers });
  if (!orgResponse.ok) throw new Error(`EVENTBRITE_ORGS_FAILED:${orgResponse.status}`);

  const orgData: any = await orgResponse.json();
  const organizations = Array.isArray(orgData.organizations) ? orgData.organizations : [];
  const events: any[] = [];

  for (const org of organizations.slice(0, 5)) {
    const params = new URLSearchParams({
      status: 'live,started',
      expand: 'venue,logo,category',
      page_size: '25',
    });
    const response = await fetch(`${EVENTBRITE_API_BASE}/organizations/${org.id}/events/?${params.toString()}`, { headers });
    if (!response.ok) continue;

    const data: any = await response.json();
    if (Array.isArray(data.events)) events.push(...data.events);
  }

  return events;
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

function mapboxEventWindow(plan: typeof MAPBOX_EVENT_PLANS[number]) {
  const start = new Date();
  if (plan.weekday !== null) {
    const today = start.getDay();
    const delta = (plan.weekday - today + 7) % 7 || 7;
    start.setDate(start.getDate() + delta);
  }
  start.setHours(plan.startHour, 0, 0, 0);
  const end = new Date(start);
  end.setHours(plan.endHour, 0, 0, 0);
  if (plan.endHour <= plan.startHour) end.setDate(end.getDate() + 1);
  return eventbriteDateParts(start.toISOString(), end.toISOString());
}

function mapboxPlaceToEventCard(place: any, plan: typeof MAPBOX_EVENT_PLANS[number], rank: number) {
  const date = mapboxEventWindow(plan);
  const venue = place?.name || plan.title;
  const address = place?.vicinity || place?.formatted_address || venue;

  return {
    event: true,
    event_source: 'mapbox_search',
    event_id: `mapbox-${plan.id}-${place?.place_id || rank}`.replace(/[^a-zA-Z0-9_-]/g, '-'),
    place_id: place?.place_id || `mapbox-${plan.id}-${rank}`,
    eventbrite_id: '',
    event_url: place?.mapbox_url || '',
    name: plan.title,
    event_title: plan.title,
    event_host: plan.host,
    event_venue: venue,
    event_address: address,
    event_description: plan.description,
    event_time_label: date.shortTime,
    event_schedule: date.schedule,
    event_start: '',
    event_weekday: date.weekday,
    event_month: date.month,
    event_day: date.day,
    attendees: 3 + (rank % 8),
    category: plan.keyword,
    rating: place?.rating,
    user_ratings_total: place?.user_ratings_total,
    open_now: place?.open_now,
    lat: place?.lat,
    lng: place?.lng,
    types: place?.types || [],
    photo_url: place?.photo_url || null,
    source_rank: rank,
  };
}

async function fetchMapboxEventPlaces(c: any, location: { address: string; lat?: string; lng?: string }) {
  const token = getMapboxAccessToken(c);
  const cards: any[] = [];
  const seen = new Set<string>();
  const proximity = mapboxProximity(location);

  for (const plan of MAPBOX_EVENT_PLANS) {
    const params = new URLSearchParams({
      q: `${plan.keyword} ${location.address || 'New York, NY'}`,
      language: 'en',
      limit: '5',
      country: 'US',
      types: 'poi',
      proximity,
      access_token: token,
    });
    const response = await fetch(`${MAPBOX_SEARCH_BOX_API_BASE}/forward?${params.toString()}`);
    if (!response.ok) throw new Error(`MAPBOX_SEARCH_FAILED:${response.status}`);
    const data: any = await response.json();

    const places = Array.isArray(data.features)
      ? data.features.map((feature: any, index: number) => mapboxFeatureToPlace(feature, `mapbox-${plan.id}-${index}`))
      : [];
    for (const place of places.slice(0, 2)) {
      const placeId = place?.place_id || place?.mapbox_id || `${plan.id}-${cards.length}`;
      if (seen.has(placeId)) continue;
      seen.add(placeId);
      cards.push(mapboxPlaceToEventCard(place, plan, cards.length));
    }
  }

  return cards;
}

function eventCardScore(card: any, preferenceTerms: string[], query: string): number {
  const corpus = `${card.event_title || ''} ${card.event_description || ''} ${card.category || ''}`.toLowerCase();
  let score = 0;

  for (const term of preferenceTerms) {
    const normalized = term.toLowerCase().trim();
    if (normalized && corpus.includes(normalized)) score += 8;
  }

  for (const part of query.toLowerCase().split(/\s+/)) {
    if (part.length > 2 && corpus.includes(part)) score += 2;
  }

  if (card.photo_url) score += 2;
  if (card.event_venue && card.event_venue !== 'Eventbrite venue') score += 1;

  const startMs = Date.parse(card.event_start || '');
  if (Number.isFinite(startMs)) {
    const hoursAway = Math.max(0, (startMs - Date.now()) / (1000 * 60 * 60));
    score += Math.max(0, 8 - hoursAway / 24);
  }

  return score;
}

function eventbriteEmptyDetail(errors: string[]): string {
  if (errors.includes('EVENTBRITE_TOKEN_MISSING')) return 'Eventbrite API token is not configured.';
  if (errors.includes('EVENTBRITE_PUBLIC_SEARCH_UNAVAILABLE') && errors.includes('owned_events_empty')) {
    return 'Eventbrite public event search is unavailable for this token, and the connected Eventbrite organizer has no live events yet.';
  }
  if (errors.includes('owned_events_empty')) return 'The connected Eventbrite organizer has no live events yet.';
  if (errors.includes('EVENTBRITE_PUBLIC_SEARCH_UNAVAILABLE')) return 'Eventbrite public event search is unavailable for this token.';
  return 'Eventbrite did not return live events for these preferences.';
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
    `CREATE TABLE IF NOT EXISTS comment_likes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      comment_id TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(user_id, comment_id)
    )`,
    'CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments(parent_id, created_at)',
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
    const username = await ensureUniqueUsername(c.env.DB, `phone_${digits.slice(-6)}`);
    const safeName = String(fullName || '').trim() || 'Flames User';
    const email = `${digits}@phone.flames-up.local`;
    const generatedPasswordHash = await hashPassword(`phone_${phone}_${uuid()}`);

    await c.env.DB.prepare(
      'INSERT INTO users (id, email, username, full_name, password_hash, phone, phone_verified) VALUES (?, ?, ?, ?, ?, ?, 1)'
    ).bind(id, email, username, safeName, generatedPasswordHash, phone).run();
    user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
  } else if (!user.phone_verified) {
    await c.env.DB.prepare('UPDATE users SET phone_verified = 1, updated_at = datetime(\'now\') WHERE id = ?').bind(user.id).run();
    user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(user.id).first();
  }

  return user;
}

function authUserPayload(user: any) {
  return {
    id: user.id,
    email: publicUserEmail(user.email),
    phone: user.phone,
    phone_verified: !!user.phone_verified,
    username: user.username,
    full_name: user.full_name,
    profile_image: user.profile_image,
    cover_image: user.cover_image,
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
    language: normalizeLanguage(user.language),
  };
}

async function requirePhoneVerified(c: any, action = 'continue') {
  const userId = getUserId(c);
  await ensurePhoneAuthSchema(c.env.DB);
  const user: any = await c.env.DB.prepare('SELECT username, phone_verified FROM users WHERE id = ?').bind(userId).first();
  if (!user) return c.json({ detail: 'User not found' }, 404);
  if (isOwnerUsername(c, user.username)) return null;
  if (!user.phone_verified) {
    return c.json({
      detail: `Verify your phone number to ${action}.`,
      code: 'PHONE_VERIFICATION_REQUIRED',
    }, 403);
  }
  return null;
}

function ownerUsernames(c: any): string[] {
  return String(c.env.OWNER_USERNAMES || 'dxhfqhsd5c')
    .split(',')
    .map((value) => value.replace(/^@/, '').trim().toLowerCase())
    .filter(Boolean);
}

function isOwnerUsername(c: any, username: unknown): boolean {
  const clean = String(username || '').replace(/^@/, '').trim().toLowerCase();
  return !!clean && ownerUsernames(c).includes(clean);
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
    fullName: email ? email.split('@')[0] : '',
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
  const usernameSeed = providedEmail ? providedEmail.split('@')[0] : `${provider}_${normalizedSubject.replace(/[^a-z0-9]/gi, '').slice(-8) || 'user'}`;
  const username = await ensureUniqueUsername(c.env.DB, usernameSeed);
  const generatedPasswordHash = await hashPassword(`${provider}_${normalizedSubject}_${uuid()}`);
  const safeName = safeFullName || (providedEmail ? providedEmail.split('@')[0] : 'Apple User');

  await c.env.DB.prepare(
    'INSERT INTO users (id, email, username, full_name, password_hash, profile_image, oauth_provider, oauth_subject) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
  ).bind(id, normalizedEmail, username, safeName, generatedPasswordHash, profileImage || '', provider, normalizedSubject).run();

  return c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTH
// ═══════════════════════════════════════════════════════════════════════════════
api.post('/auth/register', async (c) => {
  try {
    const jwtSecret = getJwtSecret(c);
    const body: any = await c.req.json().catch(() => ({}));
    const email = normalizeOptionalEmail(body.email);
    const password = String(body.password || '');
    const username = normalizeOptionalName(body.username);
    const fullName = normalizeOptionalName(body.full_name);
    if (!email || !password || !username || !fullName)
      return c.json({ detail: 'All fields required' }, 400);
    const existing = await c.env.DB.prepare('SELECT id FROM users WHERE LOWER(email) = ? OR LOWER(username) = ?')
      .bind(email, username.toLowerCase()).first();
    if (existing) return c.json({ detail: 'Email or username already exists' }, 400);
    const id = uuid();
    const hash = await hashPassword(password);
    await c.env.DB.prepare(
      'INSERT INTO users (id, email, username, full_name, password_hash) VALUES (?, ?, ?, ?, ?)'
    ).bind(id, email, username, fullName, hash).run();
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
    const body: any = await c.req.json().catch(() => ({}));
    const email = String(body.email || '').trim().toLowerCase();
    const password = String(body.password || '');
    if (!email || !password) return c.json({ detail: 'Email and password are required' }, 400);

    const jwtSecret = getJwtSecret(c);
    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).first();
    if (!user || !(await verifyPassword(password, user.password_hash)))
      return c.json({ detail: 'Invalid credentials' }, 401);
    if (String(user.status || 'active') === 'banned') {
      return c.json({ detail: 'This account has been banned.' }, 403);
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
    const body: any = await c.req.json().catch(() => ({}));
    const normalizedPhone = normalizePhone(body.phone);
    if (!normalizedPhone) return c.json({ detail: 'Enter a valid phone number with country code.' }, 400);
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
    const body: any = await c.req.json().catch(() => ({}));
    const normalizedPhone = normalizePhone(body.phone);
    if (!normalizedPhone) return c.json({ detail: 'Enter a valid phone number with country code.' }, 400);
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
    await ensureOAuthSchema(c.env.DB);
    const { id_token } = await c.req.json();
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
    await ensureOAuthSchema(c.env.DB);
    const body: any = await c.req.json().catch(() => ({}));
    const idToken = String(body.id_token || '');
    if (!idToken) return c.json({ detail: 'id_token is required' }, 400);

    const appleProfile = await verifyAppleIdToken(c, idToken);
    const clientEmail = normalizeOptionalEmail(body.email);
    const clientFullName = normalizeOptionalName(body.full_name);
    const appleSubject = String(appleProfile.subject || body.apple_user || '').trim();
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
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  if (!user) return c.json({ detail: 'User not found' }, 404);
  return c.json(authUserPayload(user));
});

// ═══════════════════════════════════════════════════════════════════════════════
// USERS
// ═══════════════════════════════════════════════════════════════════════════════
api.put('/users/me', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const body = await c.req.json();
  const fields = ['full_name', 'bio', 'profile_image', 'cover_image', 'city', 'username', 'age', 'looking_for', 'interests', 'social_website', 'social_tiktok', 'social_instagram', 'is_private', 'language'];
  const updates: string[] = []; const values: any[] = [];
  for (const f of fields) {
    if (body[f] !== undefined) {
      updates.push(`${f} = ?`);
      if (f === 'is_private') values.push(normalizeSqlBoolean(body[f]));
      else if (f === 'language') values.push(normalizeLanguage(body[f]));
      else values.push(body[f]);
    }
  }
  if (updates.length === 0) return c.json({ detail: 'Nothing to update' }, 400);
  values.push(userId);
  await c.env.DB.prepare(`UPDATE users SET ${updates.join(', ')}, updated_at = datetime('now') WHERE id = ?`).bind(...values).run();
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
  return c.json(safeUserPayload(user));
});

api.put('/users/me/email', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const body: any = await c.req.json().catch(() => ({}));
    const email = normalizeOptionalEmail(body.email || body.new_email);
    const password = String(body.password || body.current_password || '');

    if (!email) return c.json({ detail: 'Enter a valid email address.' }, 400);
    if (!password) return c.json({ detail: 'Enter your current password to change email.' }, 400);

    const currentUser: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
    if (!currentUser) return c.json({ detail: 'User not found' }, 404);
    if (!(await verifyPassword(password, currentUser.password_hash))) {
      return c.json({ detail: 'Current password is incorrect.' }, 401);
    }

    const owner: any = await c.env.DB.prepare('SELECT id FROM users WHERE LOWER(email) = ? AND id != ?')
      .bind(email, userId)
      .first();
    if (owner) return c.json({ detail: 'That email is already used by another account.' }, 409);

    await c.env.DB.prepare('UPDATE users SET email = ?, updated_at = datetime(\'now\') WHERE id = ?')
      .bind(email, userId)
      .run();
    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
    return c.json(authUserPayload(user));
  } catch {
    return c.json({ detail: 'Could not update email.' }, 500);
  }
});

api.put('/users/me/password', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const body: any = await c.req.json().catch(() => ({}));
    const currentPassword = String(body.old_password || body.current_password || '');
    const newPassword = String(body.new_password || '');

    if (!currentPassword || !newPassword) return c.json({ detail: 'Current password and new password are required.' }, 400);
    if (newPassword.length < 8) return c.json({ detail: 'New password must be at least 8 characters.' }, 400);

    const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first();
    if (!user) return c.json({ detail: 'User not found' }, 404);
    if (!(await verifyPassword(currentPassword, user.password_hash))) {
      return c.json({ detail: 'Current password is incorrect.' }, 401);
    }

    const newHash = await hashPassword(newPassword);
    await c.env.DB.prepare('UPDATE users SET password_hash = ?, updated_at = datetime(\'now\') WHERE id = ?')
      .bind(newHash, userId)
      .run();
    return c.json({ detail: 'Password updated.' });
  } catch {
    return c.json({ detail: 'Could not update password.' }, 500);
  }
});

api.post('/users/me/phone/start', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
    const body: any = await c.req.json().catch(() => ({}));
    const normalizedPhone = normalizePhone(body.phone);
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
    const body: any = await c.req.json().catch(() => ({}));
    const normalizedPhone = normalizePhone(body.phone);
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

api.get('/users/search/:query', authMiddleware, async (c) => {
  const q = c.req.param('query');
  const r = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio FROM users WHERE username LIKE ? OR full_name LIKE ? LIMIT 20').bind(`%${q}%`, `%${q}%`).all();
  return c.json(r.results);
});

// Exact username check (no auth required for registration flow)
api.get('/users/check-username/:username', async (c) => {
  const username = c.req.param('username').toLowerCase();
  const user: any = await c.env.DB.prepare('SELECT id FROM users WHERE LOWER(username) = ?').bind(username).first();
  return c.json({ available: !user, username });
});

api.get('/users/:userId', authMiddleware, async (c) => {
  const viewerId = getUserId(c);
  const user: any = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(c.req.param('userId')).first();
  if (!user) return c.json({ detail: 'User not found' }, 404);
  const safe = safeUserPayload(user);
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
      is_private: true,
      privacy_locked: true,
    });
  }
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
  // Create notification for followed user
  try {
    const me: any = await c.env.DB.prepare('SELECT full_name FROM users WHERE id = ?').bind(userId).first();
    await c.env.DB.prepare('INSERT INTO notifications (id, user_id, type, title, body, data, is_read, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, datetime(\'now\'))')
      .bind(uuid(), targetId, 'follow', 'New Follower', `${me?.full_name || 'Someone'} started following you`, JSON.stringify({ from_user_id: userId })).run();
  } catch {}
  return c.json({ following: true });
});

// ═══════════════════════════════════════════════════════════════════════════════
// POSTS (with Check-In support)
// ═══════════════════════════════════════════════════════════════════════════════
// Music proxy: Audius powers the post creation sound picker without exposing provider internals.
api.get('/music/audius/trending', async (c) => {
  try {
    await ensureAudioSchema(c.env.DB);
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

api.get('/music/audius/stream/:trackId', async (c) => {
  try {
    await ensureAudioSchema(c.env.DB);
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
      `SELECT fs.track_id, fs.title, fs.artist, fs.artwork_url, fs.duration
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
      artwork_url: String(row.artwork_url || ''),
      duration: Number(row.duration || 0),
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
    const artworkUrl = cleanText(body.artwork_url || body.audio_artwork_url || '', 1000);
    const duration = clampNumber(body.duration || body.audio_duration, 0, 60 * 60 * 6, 0);
    const ts = now();

    await c.env.DB.prepare(
      `INSERT INTO favorite_sounds (id, user_id, provider, track_id, title, artist, artwork_url, duration, created_at, updated_at)
       VALUES (?, ?, 'audius', ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, provider, track_id) DO UPDATE SET
         title = excluded.title,
         artist = excluded.artist,
         artwork_url = excluded.artwork_url,
         duration = excluded.duration,
         updated_at = excluded.updated_at`
    ).bind(uuid(), userId, trackId, title, artist, artworkUrl, duration, ts, ts).run();

    return c.json({
      favorite: true,
      track: { id: trackId, track_id: trackId, title, artist, artwork_url: artworkUrl, duration },
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
    await ensureAiMusicSchema(c.env.DB);
    const userId = getUserId(c);
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
      await c.env.DB.prepare(`UPDATE ai_music_posts SET ${column} = MAX(0, COALESCE(${column}, 0) + ?), updated_at = ? WHERE id = ?`)
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
    const musicId = cleanText(c.req.param('musicId'), 80);
    const body: any = await c.req.json().catch(() => ({}));
    const music: any = await c.env.DB.prepare('SELECT * FROM ai_music_posts WHERE id = ?').bind(musicId).first();
    if (!music) return c.json({ detail: 'Music post not found.' }, 404);
    if (music.user_id === userId) return c.json({ detail: 'You cannot report your own music post.' }, 400);
    const reason = cleanText(body.reason || 'AI music report', 240);
    const ts = now();
    await c.env.DB.prepare('INSERT OR IGNORE INTO ai_music_reports (id, music_id, reporter_id, reason, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(uuid(), musicId, userId, reason, ts)
      .run();
    await c.env.DB.prepare('UPDATE ai_music_posts SET reports_count = COALESCE(reports_count, 0) + 1, updated_at = ? WHERE id = ?')
      .bind(ts, musicId)
      .run();
    await c.env.DB.prepare(
      `INSERT INTO reports
       (id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, created_at, updated_at)
       VALUES (?, ?, ?, 'sound', 'ai_music', ?, ?, ?, 'pending', ?, ?)`
    ).bind(uuid(), userId, music.user_id, reason, cleanText(body.details || music.prompt_text || '', 1000), musicId, ts, ts).run();
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
    await ensureAiMusicSchema(c.env.DB);
    const userId = getUserId(c);
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
  await ensureMediaBackupSchema(c.env.DB);
  await ensureAudioSchema(c.env.DB);
  await ensurePostEditorSchema(c.env.DB);
  const userId = getUserId(c);
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image FROM users WHERE id = ?').bind(userId).first();
  const b = await c.req.json();
  const id = uuid(); const postType = b.post_type || 'lifestyle';
  const isCheckin = postType === 'check_in' && b.place_id ? 1 : 0;
  const location = b.location || b.place_name || null;
  const visibility = normalizeVisibility(b.visibility);
  const backupIds = parseJsonArray(b.media_backup_ids).map(String).filter(Boolean);
  const editorOverlays = parseJsonArray(b.editor_overlays).slice(0, 8);
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
    `INSERT INTO posts (
       id, user_id, content, image, images, media_types, media_backup_ids, location, post_type,
       place_id, place_name, place_lat, place_lng, is_verified_checkin, visibility,
       editor_overlays,
       audio_provider, audio_track_id, audio_title, audio_artist, audio_artwork_url, audio_stream_url,
       audio_start_time, audio_duration
     )
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(id, userId, b.content || '', b.image || null, JSON.stringify(b.images || []), JSON.stringify(b.media_types || []),
    JSON.stringify(backupIds), location, postType, b.place_id || null, b.place_name || null, b.place_lat || null, b.place_lng || null, isCheckin, visibility,
    JSON.stringify(editorOverlays),
    audioProvider, audioTrackId, audioTitle, audioArtist, audioArtworkUrl, audioStreamUrl, audioStartTime, audioDuration).run();
  await attachMediaBackupsToPost(c.env.DB, userId, id, backupIds);
  await c.env.DB.prepare('UPDATE users SET posts_count = posts_count + 1 WHERE id = ?').bind(userId).run();
  return c.json({ id, user_id: userId, user_username: user?.username, user_full_name: user?.full_name,
    user_profile_image: user?.profile_image, content: b.content, image: b.image, images: b.images || [],
    media_types: b.media_types || [], media_backup_ids: backupIds, editor_overlays: editorOverlays, location, post_type: postType, place_id: b.place_id, place_name: b.place_name,
    place_lat: b.place_lat, place_lng: b.place_lng, is_verified_checkin: !!isCheckin,
    audio_provider: audioProvider, audio_track_id: audioTrackId, audio_title: audioTitle, audio_artist: audioArtist,
    audio_artwork_url: audioArtworkUrl, audio_stream_url: audioStreamUrl, audio_start_time: audioStartTime, audio_duration: audioDuration,
    visibility, likes_count: 0, comments_count: 0, liked_by: [], created_at: now() });
});

api.get('/posts/feed', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const skip = parseInt(c.req.query('skip') || '0'); const limit = parseInt(c.req.query('limit') || '20');
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id
     WHERE ${visiblePostWhere('u', 'p')}
     ORDER BY p.created_at DESC LIMIT ? OFFSET ?`
  ).bind(...visiblePostBindValues(userId), limit, skip).all();
  const results = [];
  for (const p of posts.results as any[]) {
    const likes = await c.env.DB.prepare('SELECT user_id FROM likes WHERE post_id = ?').bind(p.id).all();
    results.push(postPayload(p, likes.results.map((l: any) => l.user_id)));
  }
  return c.json(results);
});

api.get('/posts/world-board', async (c) => {
  try {
    await ensurePrivacySchema(c.env.DB);
    const skip = Math.max(0, parseInt(c.req.query('skip') || '0', 10) || 0);
    const limit = Math.min(80, Math.max(1, parseInt(c.req.query('limit') || '40', 10) || 40));
    const posts = await c.env.DB.prepare(
      `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
       FROM posts p JOIN users u ON p.user_id = u.id
       WHERE ${publicPostWhere('u', 'p')}
       ORDER BY p.created_at DESC LIMIT ? OFFSET ?`
    ).bind(limit, skip).all();
    return c.json((posts.results as any[]).map((p) => postPayload(p)));
  } catch {
    return c.json({ detail: 'Could not load world board.' }, 500);
  }
});

api.get('/posts/nearby-feed', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id
     WHERE ${visiblePostWhere('u', 'p')}
     ORDER BY p.created_at DESC LIMIT 50`
  ).bind(...visiblePostBindValues(userId)).all();
  return c.json((posts.results as any[]).map((p) => postPayload(p)));
});

api.get('/posts/:postId', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const postId = c.req.param('postId');
  const p: any = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id
     WHERE p.id = ? AND ${visiblePostWhere('u', 'p')}`).bind(postId, ...visiblePostBindValues(userId)).first();
  if (!p) return c.json({ detail: 'Post not found' }, 404);
  const likes = await c.env.DB.prepare('SELECT user_id FROM likes WHERE post_id = ?').bind(postId).all();
  return c.json(postPayload(p, likes.results.map((l: any) => l.user_id)));
});

api.post('/posts/:postId/like', authMiddleware, async (c) => {
  const userId = getUserId(c); const postId = c.req.param('postId');
  const visiblePost = await c.env.DB.prepare(
    `SELECT p.id FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ? AND ${visiblePostWhere('u', 'p')}`
  ).bind(postId, ...visiblePostBindValues(userId)).first();
  if (!visiblePost) return c.json({ detail: 'Post not found' }, 404);
  const ex = await c.env.DB.prepare('SELECT id FROM likes WHERE user_id = ? AND post_id = ?').bind(userId, postId).first();
  if (ex) {
    await c.env.DB.prepare('DELETE FROM likes WHERE user_id = ? AND post_id = ?').bind(userId, postId).run();
    await c.env.DB.prepare('UPDATE posts SET likes_count = MAX(0, likes_count - 1) WHERE id = ?').bind(postId).run();
    return c.json({ liked: false });
  }
  await c.env.DB.prepare('INSERT INTO likes (id, user_id, post_id) VALUES (?, ?, ?)').bind(uuid(), userId, postId).run();
  await c.env.DB.prepare('UPDATE posts SET likes_count = likes_count + 1 WHERE id = ?').bind(postId).run();
  // Create notification for post owner
  try {
    const post: any = await c.env.DB.prepare('SELECT user_id FROM posts WHERE id = ?').bind(postId).first();
    if (post && post.user_id !== userId) {
      const me: any = await c.env.DB.prepare('SELECT full_name FROM users WHERE id = ?').bind(userId).first();
      await c.env.DB.prepare('INSERT INTO notifications (id, user_id, type, title, body, data, is_read, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, datetime(\'now\'))')
        .bind(uuid(), post.user_id, 'like', 'New Like', `${me?.full_name || 'Someone'} liked your post`, JSON.stringify({ post_id: postId, from_user_id: userId })).run();
    }
  } catch {}
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
  const viewerId = getUserId(c);
  const targetId = c.req.param('userId');
  const owner: any = await c.env.DB.prepare('SELECT id, is_private FROM users WHERE id = ?').bind(targetId).first();
  if (!owner) return c.json({ detail: 'User not found' }, 404);
  if (!(await canViewUserContent(c.env.DB, viewerId, owner))) return c.json([]);
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
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
     ORDER BY p.created_at DESC`
  ).bind(targetId, viewerId, viewerId, viewerId, viewerId).all();
  return c.json((posts.results as any[]).map((p) => postPayload(p)));
});

// Comments
api.post('/posts/:postId/comments', authMiddleware, async (c) => {
  try {
    await ensurePrivacySchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    await ensureCommentSchema(c.env.DB);
    const userId = getUserId(c);
    const postId = c.req.param('postId');
    const body: any = await c.req.json().catch(() => ({}));
    const content = String(body.content || '').trim();
    const parentId = body.parent_id ? String(body.parent_id) : null;
    if (!content) return c.json({ detail: 'Comment cannot be empty.' }, 400);
    if (content.length > 1200) return c.json({ detail: 'Comment is too long.' }, 400);

    const visiblePost: any = await c.env.DB.prepare(
      `SELECT p.id, p.user_id FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ? AND ${visiblePostWhere('u', 'p')}`
    ).bind(postId, ...visiblePostBindValues(userId)).first();
    if (!visiblePost) return c.json({ detail: 'Post not found' }, 404);

    let parent: any = null;
    if (parentId) {
      parent = await c.env.DB.prepare('SELECT id, user_id FROM comments WHERE id = ? AND post_id = ?')
        .bind(parentId, postId)
        .first();
      if (!parent) return c.json({ detail: 'Comment to reply to was not found.' }, 404);
    }

    const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image FROM users WHERE id = ?').bind(userId).first();
    const id = uuid();
    const createdAt = now();
    await c.env.DB.prepare('INSERT INTO comments (id, user_id, post_id, parent_id, content) VALUES (?, ?, ?, ?, ?)')
      .bind(id, userId, postId, parentId, content)
      .run();
    await c.env.DB.prepare('UPDATE posts SET comments_count = comments_count + 1 WHERE id = ?').bind(postId).run();

    try {
      const notifyUserId = parent?.user_id && parent.user_id !== userId ? parent.user_id : visiblePost.user_id;
      if (notifyUserId && notifyUserId !== userId) {
        await c.env.DB.prepare('INSERT INTO notifications (id, user_id, type, title, body, data, is_read, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, datetime(\'now\'))')
          .bind(
            uuid(),
            notifyUserId,
            parentId ? 'comment_reply' : 'comment',
            parentId ? 'New Reply' : 'New Comment',
            `${user?.full_name || 'Someone'} ${parentId ? 'replied to your comment' : 'commented on your post'}`,
            JSON.stringify({ post_id: postId, comment_id: id, parent_id: parentId, from_user_id: userId })
          ).run();
      }
    } catch {}

    return c.json({
      id,
      user_id: userId,
      post_id: postId,
      parent_id: parentId,
      content,
      likes_count: 0,
      liked_by_me: false,
      user_username: user?.username,
      user_full_name: user?.full_name,
      user_profile_image: user?.profile_image,
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
    const r = await c.env.DB.prepare(
      `SELECT c.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
              CASE WHEN cl.id IS NULL THEN 0 ELSE 1 END AS liked_by_me
       FROM comments c
       JOIN posts p ON c.post_id = p.id
       JOIN users owner ON p.user_id = owner.id
       JOIN users u ON c.user_id = u.id
       LEFT JOIN comment_likes cl ON cl.comment_id = c.id AND cl.user_id = ?
       WHERE c.post_id = ? AND ${visiblePostWhere('owner', 'p')}
       ORDER BY COALESCE(c.parent_id, c.id), c.parent_id IS NOT NULL, c.created_at ASC`
    ).bind(userId, c.req.param('postId'), ...visiblePostBindValues(userId)).all();

    return c.json((r.results as any[]).map((comment) => ({
      ...comment,
      likes_count: Number(comment.likes_count || 0),
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
    const commentId = c.req.param('commentId');
    const comment: any = await c.env.DB.prepare(
      `SELECT c.id, c.likes_count
       FROM comments c
       JOIN posts p ON c.post_id = p.id
       JOIN users owner ON p.user_id = owner.id
       WHERE c.id = ? AND ${visiblePostWhere('owner', 'p')}`
    ).bind(commentId, ...visiblePostBindValues(userId)).first();
    if (!comment) return c.json({ detail: 'Comment not found' }, 404);

    const existing: any = await c.env.DB.prepare('SELECT id FROM comment_likes WHERE user_id = ? AND comment_id = ?')
      .bind(userId, commentId)
      .first();

    if (existing) {
      await c.env.DB.prepare('DELETE FROM comment_likes WHERE id = ?').bind(existing.id).run();
      await c.env.DB.prepare('UPDATE comments SET likes_count = MAX(0, COALESCE(likes_count, 0) - 1) WHERE id = ?').bind(commentId).run();
    } else {
      await c.env.DB.prepare('INSERT INTO comment_likes (id, user_id, comment_id) VALUES (?, ?, ?)')
        .bind(uuid(), userId, commentId)
        .run();
      await c.env.DB.prepare('UPDATE comments SET likes_count = COALESCE(likes_count, 0) + 1 WHERE id = ?').bind(commentId).run();
    }

    const updated: any = await c.env.DB.prepare('SELECT likes_count FROM comments WHERE id = ?').bind(commentId).first();
    return c.json({ liked: !existing, likes_count: Number(updated?.likes_count || 0) });
  } catch (error: any) {
    console.error('Comment like failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not update comment like.' }, 500);
  }
});

// Statuses
api.post('/statuses', authMiddleware, async (c) => {
  const phoneGate = await requirePhoneVerified(c, 'share stories');
  if (phoneGate) return phoneGate;
  const userId = getUserId(c); const b = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image FROM users WHERE id = ?').bind(userId).first();
  const id = uuid(); const expiresAt = new Date(Date.now() + 86400000).toISOString();
  const visibility = normalizeVisibility(b.visibility);
  await c.env.DB.prepare('INSERT INTO statuses (id, user_id, content, image, background_color, text_color, visibility, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
    .bind(id, userId, b.content || '', b.image || null, b.background_color || '#1B4332', b.text_color || '#FFFFFF', visibility, expiresAt).run();
  return c.json({ id, user_id: userId, content: b.content, image: b.image, background_color: b.background_color, text_color: b.text_color, visibility, user_username: user?.username, user_full_name: user?.full_name, user_profile_image: user?.profile_image, viewed_by: [], created_at: now(), expires_at: expiresAt });
});

api.get('/statuses', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const r = await c.env.DB.prepare(
    `SELECT s.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM statuses s JOIN users u ON s.user_id = u.id
     WHERE s.expires_at > datetime('now') AND ${visibleStatusWhere('u', 's')}
     ORDER BY s.created_at DESC`
  ).bind(userId, userId).all();
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
  const s: any = await c.env.DB.prepare(
    `SELECT s.viewed_by FROM statuses s JOIN users u ON s.user_id = u.id
     WHERE s.id = ? AND ${visibleStatusWhere('u', 's')}`
  ).bind(statusId, userId, userId).first();
  if (!s) return c.json({ detail: 'Not found' }, 404);
  const vb: string[] = JSON.parse(s.viewed_by || '[]');
  if (!vb.includes(userId)) { vb.push(userId); await c.env.DB.prepare('UPDATE statuses SET viewed_by = ? WHERE id = ?').bind(JSON.stringify(vb), statusId).run(); }
  return c.json({ viewed: true });
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
    `).bind(userId).all();

    groupConversations = (groups.results as any[]).map((g) => ({
      id: `group-${g.id}`,
      type: 'group',
      group_id: g.id,
      group_name: g.name,
      member_count: Number(g.member_count || 0),
      last_message: g.last_message
        ? `${g.last_sender_username || 'Someone'}: ${g.last_message}`
        : 'Group created',
      last_message_time: g.last_message_time || g.created_at,
      unread_count: 0,
    }));
  } catch {
    groupConversations = [];
  }

  return c.json([...directConversations, ...groupConversations].sort((a, b) => Date.parse(b.last_message_time || '') - Date.parse(a.last_message_time || '')));
});

api.post('/messages', authMiddleware, async (c) => {
  const phoneGate = await requirePhoneVerified(c, 'send messages');
  if (phoneGate) return phoneGate;
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

api.post('/group-chats', authMiddleware, async (c) => {
  const phoneGate = await requirePhoneVerified(c, 'create group chats');
  if (phoneGate) return phoneGate;
  const userId = getUserId(c);
  const body: any = await c.req.json().catch(() => ({}));
  const memberIds = Array.isArray(body.member_ids)
    ? body.member_ids.map((id: any) => String(id)).filter((id: string) => id && id !== userId)
    : [];
  const uniqueMemberIds = Array.from(new Set(memberIds)).slice(0, 50);
  if (uniqueMemberIds.length < 2) return c.json({ detail: 'Select at least two people for a group chat.' }, 400);

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
  const groupId = c.req.param('groupId');
  if (!await requireGroupMember(c, groupId, userId)) return c.json({ detail: 'Group not found' }, 404);

  const group: any = await c.env.DB.prepare(`
    SELECT g.*, COUNT(m.user_id) AS member_count
    FROM group_chats g
    LEFT JOIN group_chat_members m ON m.group_id = g.id
    WHERE g.id = ?
    GROUP BY g.id
  `).bind(groupId).first();
  const messages = await c.env.DB.prepare(`
    SELECT gm.*, u.username, u.full_name, u.profile_image
    FROM group_messages gm
    JOIN users u ON u.id = gm.sender_id
    WHERE gm.group_id = ?
    ORDER BY gm.created_at ASC
  `).bind(groupId).all();

  return c.json({ group, messages: messages.results });
});

api.post('/group-chats/:groupId/messages', authMiddleware, async (c) => {
  const phoneGate = await requirePhoneVerified(c, 'send group messages');
  if (phoneGate) return phoneGate;
  const userId = getUserId(c);
  const groupId = c.req.param('groupId');
  if (!await requireGroupMember(c, groupId, userId)) return c.json({ detail: 'Group not found' }, 404);
  const body: any = await c.req.json().catch(() => ({}));
  const content = String(body.content || '').trim();
  if (!content) return c.json({ detail: 'Message is empty' }, 400);

  const id = uuid();
  await c.env.DB.prepare('INSERT INTO group_messages (id, group_id, sender_id, content, media_url, media_type) VALUES (?, ?, ?, ?, ?, ?)')
    .bind(id, groupId, userId, content, body.media_url || null, body.media_type || null)
    .run();
  await c.env.DB.prepare('UPDATE group_chats SET updated_at = datetime(\'now\') WHERE id = ?').bind(groupId).run();
  return c.json({ id, group_id: groupId, sender_id: userId, content, media_url: body.media_url, media_type: body.media_type, created_at: now() });
});

// Calls
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
      mode: body.mode === 'live' ? 'live' : 'call',
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
    const r = await c.env.DB.prepare('SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 50').bind(getUserId(c)).all();
    return c.json(r.results);
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

    const rows = await c.env.DB.prepare(`
      SELECT r.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM recommendations r
      LEFT JOIN users u ON u.id = r.user_id
      ${where}
      ORDER BY r.created_at DESC
      LIMIT ?
    `).bind(...binds).all();
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
    await ensureRecommendationSchema(c.env.DB);
    const userId = getUserId(c);
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
    const recommendationId = c.req.param('recommendationId');
    const body: any = await c.req.json().catch(() => ({}));
    const recommendation: any = await c.env.DB.prepare('SELECT * FROM recommendations WHERE id = ?').bind(recommendationId).first();
    if (!recommendation) return c.json({ detail: 'Recommendation not found.' }, 404);
    if (recommendation.user_id === userId) return c.json({ detail: 'You cannot report your own recommendation.' }, 400);
    const ts = now();
    await c.env.DB.prepare(
      'INSERT OR IGNORE INTO recommendation_reports (id, recommendation_id, reporter_id, reason, created_at) VALUES (?, ?, ?, ?, ?)'
    ).bind(uuid(), recommendationId, userId, cleanText(body.reason || 'Recommendation report', 240), ts).run();
    await c.env.DB.prepare('UPDATE recommendations SET reports_count = COALESCE(reports_count, 0) + 1, updated_at = ? WHERE id = ?').bind(ts, recommendationId).run();
    await c.env.DB.prepare(
      `INSERT INTO reports
       (id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, created_at, updated_at)
       VALUES (?, ?, ?, 'recommendation', 'recommendation', ?, ?, ?, 'pending', ?, ?)`
    ).bind(uuid(), userId, recommendation.user_id, cleanText(body.reason || 'Recommendation report', 240), cleanText(body.details || '', 1000), recommendationId, ts, ts).run();
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
    const rows = await c.env.DB.prepare(`
      SELECT n.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image,
        EXISTS(SELECT 1 FROM note_interactions i WHERE i.note_id = n.id AND i.user_id = ? AND i.kind = 'reaction') AS reacted,
        EXISTS(SELECT 1 FROM note_interactions i WHERE i.note_id = n.id AND i.user_id = ? AND i.kind = 'save') AS saved
      FROM notes n
      LEFT JOIN users u ON u.id = n.user_id
      ${where}
      ORDER BY n.created_at DESC
      LIMIT ?
    `).bind(...binds).all();
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
    await ensureNotesSchema(c.env.DB);
    const userId = getUserId(c);
    const body: any = await c.req.json().catch(() => ({}));
    const noteBody = cleanText(body.body || body.text || body.content, 420);
    const moderation = moderateCommunityText(noteBody);
    if (!moderation.ok) return c.json({ detail: moderation.detail || 'That note cannot be posted.' }, 400);
    if (noteBody.length < 2) return c.json({ detail: 'Write a little more first.' }, 400);
    const noteType = normalizeNoteType(body.note_type || body.type);
    const mood = normalizeNoteMood(body.mood || body.color);
    const color = /^#[0-9a-f]{6}$/i.test(String(body.color || '')) ? String(body.color) : mood.color;
    const anonymous = normalizeSqlBoolean(body.anonymous);
    const ts = now();
    const id = uuid();
    await c.env.DB.prepare(
      `INSERT INTO notes
       (id, user_id, body, note_type, mood, color, anonymous, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)`
    ).bind(id, userId, noteBody, noteType, mood.mood, color, anonymous, ts, ts).run();
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
      await c.env.DB.prepare(`UPDATE notes SET ${column} = MAX(0, COALESCE(${column}, 0) - 1), updated_at = ? WHERE id = ?`).bind(now(), noteId).run();
      return c.json({ active: false, kind });
    }
    if (!existing || kind === 'share') {
      await c.env.DB.prepare('INSERT OR IGNORE INTO note_interactions (id, note_id, user_id, kind, value, created_at) VALUES (?, ?, ?, ?, ?, ?)')
        .bind(uuid(), noteId, userId, kind, value, now())
        .run();
      const column = kind === 'save' ? 'saves_count' : kind === 'share' ? 'shares_count' : 'reactions_count';
      await c.env.DB.prepare(`UPDATE notes SET ${column} = COALESCE(${column}, 0) + 1, updated_at = ? WHERE id = ?`).bind(now(), noteId).run();
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
      SELECT nc.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
      FROM note_comments nc
      LEFT JOIN users u ON u.id = nc.user_id
      WHERE nc.note_id = ? AND COALESCE(nc.status, 'active') = 'active'
      ORDER BY nc.created_at ASC
      LIMIT 80
    `).bind(noteId).all();
    return c.json((rows.results as any[]).map((comment) => ({
      id: comment.id,
      body: comment.body,
      parent_id: comment.parent_id || '',
      likes_count: Number(comment.likes_count || 0),
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
    await ensureNotesSchema(c.env.DB);
    const userId = getUserId(c);
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

api.post('/notes/:noteId/report', authMiddleware, async (c) => {
  try {
    await ensureNotesSchema(c.env.DB);
    await ensureGovernanceSchema(c.env.DB);
    const userId = getUserId(c);
    const noteId = cleanText(c.req.param('noteId'), 80);
    const body: any = await c.req.json().catch(() => ({}));
    const note: any = await c.env.DB.prepare('SELECT id, user_id FROM notes WHERE id = ?').bind(noteId).first();
    if (!note) return c.json({ detail: 'Note not found.' }, 404);
    if (note.user_id === userId) return c.json({ detail: 'You cannot report your own note.' }, 400);
    const ts = now();
    await c.env.DB.prepare('INSERT OR IGNORE INTO note_reports (id, note_id, reporter_id, reason, details, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(uuid(), noteId, userId, cleanText(body.reason || 'Note report', 240), cleanText(body.details || '', 1000), ts)
      .run();
    await c.env.DB.prepare('UPDATE notes SET reports_count = COALESCE(reports_count, 0) + 1, updated_at = ? WHERE id = ?').bind(ts, noteId).run();
    await c.env.DB.prepare(
      `INSERT INTO reports
       (id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, created_at, updated_at)
       VALUES (?, ?, ?, 'note', 'note', ?, ?, ?, 'pending', ?, ?)`
    ).bind(uuid(), userId, note.user_id, cleanText(body.reason || 'Note report', 240), cleanText(body.details || '', 1000), noteId, ts, ts).run();
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
    const profileId = cleanText(c.req.param('profileId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const kind = String(body.kind) === 'save' ? 'save' : 'follow';
    if (profileId.startsWith('user:') && kind === 'follow') {
      const targetId = profileId.slice(5);
      if (targetId === userId) return c.json({ detail: 'Cannot follow yourself.' }, 400);
      const existing: any = await c.env.DB.prepare('SELECT id FROM follows WHERE follower_id = ? AND following_id = ?').bind(userId, targetId).first();
      if (existing) {
        await c.env.DB.prepare('DELETE FROM follows WHERE follower_id = ? AND following_id = ?').bind(userId, targetId).run();
        await c.env.DB.prepare('UPDATE users SET following_count = MAX(0, following_count - 1) WHERE id = ?').bind(userId).run();
        await c.env.DB.prepare('UPDATE users SET followers_count = MAX(0, followers_count - 1) WHERE id = ?').bind(targetId).run();
        return c.json({ active: false, kind });
      }
      await c.env.DB.prepare('INSERT INTO follows (id, follower_id, following_id) VALUES (?, ?, ?)').bind(uuid(), userId, targetId).run();
      await c.env.DB.prepare('UPDATE users SET following_count = COALESCE(following_count, 0) + 1 WHERE id = ?').bind(userId).run();
      await c.env.DB.prepare('UPDATE users SET followers_count = COALESCE(followers_count, 0) + 1 WHERE id = ?').bind(targetId).run();
      return c.json({ active: true, kind });
    }
    const existing: any = await c.env.DB.prepare('SELECT id FROM people_interactions WHERE profile_id = ? AND user_id = ? AND kind = ?')
      .bind(profileId, userId, kind)
      .first();
    if (existing) {
      await c.env.DB.prepare('DELETE FROM people_interactions WHERE id = ?').bind(existing.id).run();
      const column = kind === 'save' ? 'saves_count' : 'followers_count';
      await c.env.DB.prepare(`UPDATE people_profiles SET ${column} = MAX(0, COALESCE(${column}, 0) - 1), updated_at = ? WHERE id = ?`).bind(now(), profileId).run();
      return c.json({ active: false, kind });
    }
    await c.env.DB.prepare('INSERT INTO people_interactions (id, profile_id, user_id, kind, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(uuid(), profileId, userId, kind, now()).run();
    const column = kind === 'save' ? 'saves_count' : 'followers_count';
    await c.env.DB.prepare(`UPDATE people_profiles SET ${column} = COALESCE(${column}, 0) + 1, updated_at = ? WHERE id = ?`).bind(now(), profileId).run();
    return c.json({ active: true, kind });
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
    const profileId = cleanText(c.req.param('profileId'), 120);
    const body: any = await c.req.json().catch(() => ({}));
    const ts = now();
    await c.env.DB.prepare('INSERT OR IGNORE INTO people_reports (id, profile_id, reporter_id, reason, details, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(uuid(), profileId, userId, cleanText(body.reason || 'Wrong info', 240), cleanText(body.details || '', 1000), ts).run();
    await c.env.DB.prepare('UPDATE people_profiles SET reports_count = COALESCE(reports_count, 0) + 1, updated_at = ? WHERE id = ?').bind(ts, profileId).run();
    await c.env.DB.prepare(
      `INSERT INTO reports
       (id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, created_at, updated_at)
       VALUES (?, ?, ?, 'people', 'people', ?, ?, ?, 'pending', ?, ?)`
    ).bind(uuid(), userId, profileId, cleanText(body.reason || 'Wrong People profile info', 240), cleanText(body.details || '', 1000), profileId, ts, ts).run();
    return c.json({ reported: true });
  } catch (error: any) {
    const message = String(error?.message || '').toLowerCase();
    if (message.includes('unique constraint')) return c.json({ reported: true });
    console.error('People report failed:', getErrorCode(error), error?.message || error);
    return c.json({ detail: 'Could not report People profile.' }, 500);
  }
});

// Discover
api.get('/discover/trending', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const r = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id
     WHERE ${visiblePostWhere('u', 'p')}
     ORDER BY p.likes_count DESC, p.created_at DESC LIMIT 20`
  ).bind(...visiblePostBindValues(userId)).all();
  return c.json((r.results as any[]).map((p) => postPayload(p)));
});
api.get('/discover/search', authMiddleware, async (c) => {
  const userId = getUserId(c);
  const q = c.req.query('q') || '';
  const posts = await c.env.DB.prepare(
    `SELECT p.*, u.username AS user_username, u.full_name AS user_full_name, u.profile_image AS user_profile_image
     FROM posts p JOIN users u ON p.user_id = u.id
     WHERE p.content LIKE ? AND ${visiblePostWhere('u', 'p')}
     LIMIT 20`
  ).bind(`%${q}%`, ...visiblePostBindValues(userId)).all();
  const users = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio, is_private FROM users WHERE username LIKE ? OR full_name LIKE ? LIMIT 10').bind(`%${q}%`, `%${q}%`).all();
  return c.json({ posts: (posts.results as any[]).map((p) => postPayload(p)), users: users.results });
});
api.get('/discover/suggested-users', authMiddleware, async (c) => { const r = await c.env.DB.prepare('SELECT id, username, full_name, profile_image, bio, followers_count FROM users WHERE id != ? ORDER BY followers_count DESC LIMIT 10').bind(getUserId(c)).all(); return c.json(r.results); });

api.get('/events/personalized', async (c) => {
  const previewMode = String(c.env.EVENTS_PREVIEW || '') === '1';
  let user: any = {
    city: c.req.query('city') || c.req.query('location') || '',
    looking_for: c.req.query('looking_for') || '',
    interests: c.req.query('interests') || '',
  };

  if (!previewMode) {
    const authHeader = c.req.header('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return c.json({ detail: 'Not authenticated' }, 401);

    try {
      const token = authHeader.slice(7);
      const { jwtVerify } = await import('jose');
      const { payload } = await jwtVerify(token, new TextEncoder().encode(getJwtSecret(c)));
      const userId = String(payload?.sub || payload?.userId || '');
      const dbUser: any = await c.env.DB.prepare('SELECT id, city, looking_for, interests FROM users WHERE id = ?').bind(userId).first();
      if (!dbUser) return c.json({ detail: 'User not found' }, 404);
      user = {
        ...dbUser,
        city: user.city || dbUser.city,
        looking_for: user.looking_for || dbUser.looking_for,
        interests: user.interests || dbUser.interests,
      };
    } catch {
      return c.json({ detail: 'Invalid token' }, 401);
    }
  }

  const token = String(c.env.EVENTBRITE_API_TOKEN || '').trim();
  if (!token) {
    return c.json({ detail: 'Eventbrite API token is not configured', events: [] }, 503);
  }

  const limit = Math.min(Number(c.req.query('limit') || 12), 24);
  const explicitQuery = c.req.query('q') || '';
  const preference = buildEventPreference(user, explicitQuery);
  const location = {
    address: c.req.query('location') || user.city || 'New York, NY',
    lat: c.req.query('lat') || undefined,
    lng: c.req.query('lng') || undefined,
  };

  const searchPlans = preference.queries.slice(0, 6).map((query, index) => ({
    query,
    category: preference.categories.length > 0 ? preference.categories[index % preference.categories.length] : undefined,
  }));

  const scored = new Map<string, { card: any; score: number }>();
  const errors: string[] = [];

  for (const plan of searchPlans) {
    try {
      const events = await fetchEventbriteEvents(c, plan.query, plan.category, location);
      events.forEach((event: any, index: number) => {
        const card = eventbriteEventToCard(event, plan.query, scored.size + index);
        const score = eventCardScore(card, preference.terms, plan.query);
        const existing = scored.get(card.event_id);
        if (!existing || score > existing.score) scored.set(card.event_id, { card, score });
      });
    } catch (error: any) {
      const message = String(error?.message || error || '');
      const code = message.startsWith('EVENTBRITE_SEARCH_FAILED') ? 'search_failed' : message;
      if (!errors.includes(code)) errors.push(code);
      if (code === 'EVENTBRITE_PUBLIC_SEARCH_UNAVAILABLE') break;
    }
  }

  if (scored.size === 0) {
    try {
      const ownedEvents = await fetchOwnedEventbriteEvents(c);
      ownedEvents.forEach((event: any, index: number) => {
        const card = eventbriteEventToCard(event, 'your Eventbrite organization', index);
        scored.set(card.event_id, { card, score: eventCardScore(card, preference.terms, 'your Eventbrite organization') });
      });
      if (ownedEvents.length === 0) errors.push('owned_events_empty');
    } catch (error: any) {
      errors.push(String(error?.message || error || 'owned_events_failed'));
    }
  }

  if (scored.size === 0) {
    try {
      const mapboxEvents = await fetchMapboxEventPlaces(c, location);
      mapboxEvents.forEach((card: any) => {
        scored.set(card.event_id, { card, score: eventCardScore(card, preference.terms, 'mapbox places') + 4 });
      });
      if (mapboxEvents.length === 0) errors.push('mapbox_places_empty');
    } catch (error: any) {
      errors.push(String(error?.message || error || 'mapbox_places_failed'));
    }
  }

  if (scored.size === 0) {
    try {
      const nycEvents = await fetchNycOpenDataEvents(location);
      nycEvents.forEach((event: any, index: number) => {
        const card = nycOpenDataEventToCard(event, index);
        scored.set(card.event_id, { card, score: eventCardScore(card, preference.terms, 'nyc open data') + 2 });
      });
      if (nycEvents.length === 0) errors.push('nyc_events_empty');
    } catch (error: any) {
      errors.push(String(error?.message || error || 'nyc_events_failed'));
    }
  }

  const events = [...scored.values()]
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map(({ card, score }) => ({ ...card, preference_score: Number(score.toFixed(2)) }));

  return c.json({
    source: 'eventbrite',
    location,
    preferences: preference.terms,
    queries: preference.queries,
    events,
    detail: events.length === 0 ? eventbriteEmptyDetail(errors) : '',
    errors: errors.length > 0 && events.length === 0 ? errors.slice(0, 5) : [],
  });
});

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
api.post('/reports', authMiddleware, async (c) => {
  try {
    await ensureGovernanceSchema(c.env.DB);
    const body: any = await c.req.json().catch(() => ({}));
    const reportedType = body.reported_type || body.report_type || 'other';
    const reportedId = body.reported_id || body.post_id || body.user_id || '';
    const contentId = body.content_id || (reportedType === 'post' ? reportedId : null);
    const reason = body.reason || 'Reported from app';
    const details = body.details || body.description || '';
    const ts = now();
    const id = uuid();

    await c.env.DB.prepare(
      `INSERT INTO reports (
        id, reporter_id, reported_id, report_type, reported_type, reason, details, content_id, status, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`
    ).bind(id, getUserId(c), reportedId, reportedType, reportedType, reason, details, contentId, ts, ts).run();

    return c.json({ id, reported: true });
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
  const userId = getUserId(c); const b = await c.req.json();
  const user: any = await c.env.DB.prepare('SELECT username, full_name, profile_image, is_publisher FROM users WHERE id = ?').bind(userId).first();
  if (!user?.is_publisher) return c.json({ detail: 'Publishers only' }, 403);
  const id = uuid();
  await c.env.DB.prepare('INSERT INTO discover_posts (id, user_id, content, image, images, category, location) VALUES (?, ?, ?, ?, ?, ?, ?)').bind(id, userId, b.content || '', b.image || null, JSON.stringify(b.images || []), b.category || 'culture', b.location || '').run();
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

async function requireGovernanceAdmin(c: any): Promise<string> {
  await ensureGovernanceSchema(c.env.DB);
  const userId = getUserId(c);
  const user: any = await c.env.DB.prepare('SELECT is_admin, status FROM users WHERE id = ?').bind(userId).first();
  if (!user?.is_admin) throw new Error('FORBIDDEN');
  if (String(user.status || 'active') === 'banned') throw new Error('FORBIDDEN');
  return userId;
}

function governanceError(c: any, error: any) {
  const message = String(error?.message || error || 'Governance request failed');
  return c.json({ detail: message === 'FORBIDDEN' ? 'Admin access required' : message }, message === 'FORBIDDEN' ? 403 : 500);
}

async function logGovernanceAction(c: any, adminId: string, actionType: string, targetType: string, targetId: string, details: any = {}) {
  await c.env.DB.prepare(
    'INSERT INTO admin_actions (id, admin_id, action_type, target_type, target_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
  ).bind(uuid(), adminId, actionType, targetType, targetId, JSON.stringify(details || {}), now()).run();
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
    await c.env.DB.prepare(`UPDATE people_profiles SET ${updates.join(', ')} WHERE id = ?`).bind(...values).run();
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
        r.reviewed_by,
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
      ORDER BY r.created_at DESC
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
    await c.env.DB.prepare(
      "UPDATE reports SET status = 'resolved', admin_notes = ?, action_taken = ?, reviewed_by = ?, updated_at = ? WHERE id = ?"
    ).bind(body.admin_notes || '', body.action_taken || 'resolved', adminId, now(), reportId).run();
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
      "UPDATE reports SET status = 'dismissed', admin_notes = ?, action_taken = 'dismissed', reviewed_by = ?, updated_at = ? WHERE id = ?"
    ).bind(body.admin_notes || '', adminId, now(), reportId).run();
    await logGovernanceAction(c, adminId, 'dismiss_report', 'report', reportId, body);
    return c.json({ dismissed: true });
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
    await c.env.DB.prepare("UPDATE users SET status = 'banned', banned_at = ?, ban_reason = ?, updated_at = datetime('now') WHERE id = ?")
      .bind(now(), body.reason || 'Banned by governance', targetUserId)
      .run();
    await logGovernanceAction(c, adminId, 'ban_user', 'user', targetUserId, body);
    return c.json({ banned: true });
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

// Admin: List all users
api.get('/admin/users', authMiddleware, adminGuard, async (c) => {
  const search = c.req.query('search') || '';
  const role = c.req.query('role') || '';
  let sql = 'SELECT id, email, username, full_name, profile_image, bio, city, is_admin, is_creator, is_publisher, is_verified, followers_count, posts_count, created_at FROM users';
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
  await c.env.DB.prepare(`UPDATE users SET ${fields.join(', ')}, updated_at = datetime('now') WHERE id = ?`).bind(...vals).run();
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
  const { banned } = await c.req.json();
  await c.env.DB.prepare('UPDATE users SET is_banned = ? WHERE id = ?').bind(banned ? 1 : 0, userId).run();
  return c.json({ success: true, banned: !!banned });
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
    const body = await c.req.json();
    const base64Data = body.image || body.base64;
    if (!base64Data) return c.json({ detail: 'No image data provided' }, 400);

    const userId = getUserId(c);
    const decoded = dataUriToBytes(base64Data, 'image/jpeg');
    const processed = await maybeEnhanceImage(c, decoded.bytes, decoded.contentType);

    const blob = new Blob([bytesToArrayBuffer(processed.bytes)], { type: processed.contentType });
    const formData = new FormData();
    const fileExt = contentTypeExtension(processed.contentType, 'jpg');
    formData.append('file', blob, `upload-${Date.now()}.${fileExt}`);
    formData.append('metadata', JSON.stringify({ userId, backup: true, enhancement: processed.status }));

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
          r2_backup_key: backup?.r2_key || null,
          size_bytes: backup?.size_bytes || processed.bytes.byteLength,
          checksum_sha256: backup?.checksum_sha256 || null,
          enhancement_status: processed.status,
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
    if (!backup) return c.json({ url: base64Data, source: 'base64_fallback' });
    return c.json({
      url: backup.delivery_url,
      id: backup.id,
      source: 'r2_image',
      backup_id: backup.id,
      r2_backup_key: backup.r2_key,
      size_bytes: backup.size_bytes,
      checksum_sha256: backup.checksum_sha256,
      enhancement_status: processed.status,
    });
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
    return c.json({ detail: 'Video upload setup failed: ' + e.message }, 500);
  }
});

api.post('/upload/video-with-backup', authMiddleware, async (c) => {
  try {
    const userId = getUserId(c);
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
    const fileType = file.type || 'video/mp4';
    const fileSize = Number(file.size || 0);
    if (!fileType.startsWith('video/')) return c.json({ detail: 'Only video uploads are supported' }, 400);
    if (fileSize > maxBackupVideoBytes(c)) {
      return c.json({
        detail: 'Video is too large for Worker backup upload. Use direct Stream upload for this file.',
        max_bytes: maxBackupVideoBytes(c),
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
          streamForm.append('file', new Blob([videoBytes], { type: fileType }), file.name || 'upload.mp4');
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
              r2_backup_key: backup?.r2_key || null,
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
      r2_backup_key: backup.r2_key,
      size_bytes: backup.size_bytes,
      checksum_sha256: backup.checksum_sha256,
    });
  } catch (e: any) {
    return c.json({ detail: 'Video upload failed: ' + e.message }, 500);
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

// Mapbox Places proxy.
async function mapboxPlacesNearbyHandler(c: any) {
  try {
    const token = getMapboxAccessToken(c);
    const lat = c.req.query('lat') || '40.7128';
    const lng = c.req.query('lng') || '-74.006';
    const type = c.req.query('type') || 'restaurant';
    const keyword = c.req.query('keyword') || '';
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
    name: c.req.query('name') || 'Mapbox place',
    address: c.req.query('address') || '',
    vicinity: c.req.query('address') || '',
    phone: '',
    rating: null,
    user_ratings_total: null,
    website: '',
    price_level: null,
    types: [],
    url: '',
    mapbox_url: lat && lng ? `https://www.mapbox.com/search?query=${encodeURIComponent(pid)}&center=${lng},${lat}` : '',
    lat: lat ? Number(lat) : null,
    lng: lng ? Number(lng) : null,
    opening_hours: null,
    reviews: [],
    photos: [],
  });
}

api.get('/mapbox-places/nearby', mapboxPlacesNearbyHandler);
api.get('/mapbox-places/:placeId', mapboxPlaceDetailHandler);

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
  } catch (e: any) { return c.json({ detail: e?.message }, e?.message === 'FORBIDDEN' ? 403 : 500); }
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
