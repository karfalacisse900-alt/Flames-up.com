-- Captro pre-publish media moderation.
-- Optional legacy posts columns are added by ensureMediaModerationSchema() at
-- runtime because this deploy workflow replays migration files and D1 does not
-- support portable ADD COLUMN IF NOT EXISTS.

CREATE TABLE IF NOT EXISTS media_assets (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  post_id TEXT,
  media_type TEXT NOT NULL CHECK (media_type IN ('image', 'video')),
  storage_provider TEXT NOT NULL CHECK (storage_provider IN ('r2', 'images', 'stream')),
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
);

CREATE TABLE IF NOT EXISTS moderation_jobs (
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
);

CREATE TABLE IF NOT EXISTS moderation_results (
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
);

CREATE TABLE IF NOT EXISTS moderation_events (
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
);

CREATE INDEX IF NOT EXISTS idx_media_assets_user_created ON media_assets(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_media_assets_status_created ON media_assets(moderation_status, created_at);
CREATE INDEX IF NOT EXISTS idx_media_assets_post ON media_assets(post_id);
CREATE INDEX IF NOT EXISTS idx_media_assets_storage ON media_assets(storage_provider, storage_key);
CREATE INDEX IF NOT EXISTS idx_media_assets_hash ON media_assets(sha256_hash);
CREATE INDEX IF NOT EXISTS idx_moderation_jobs_status ON moderation_jobs(status, queued_at);
CREATE INDEX IF NOT EXISTS idx_moderation_jobs_media ON moderation_jobs(media_id);
CREATE INDEX IF NOT EXISTS idx_moderation_results_media_created ON moderation_results(media_id, created_at);
CREATE INDEX IF NOT EXISTS idx_moderation_events_media_created ON moderation_events(media_id, created_at);
