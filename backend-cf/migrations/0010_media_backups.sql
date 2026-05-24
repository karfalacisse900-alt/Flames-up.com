-- Track every user-uploaded post media file that is backed up to R2.

ALTER TABLE posts ADD COLUMN media_backup_ids TEXT DEFAULT '[]';

CREATE TABLE IF NOT EXISTS media_backups (
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
);

CREATE INDEX IF NOT EXISTS idx_media_backups_user ON media_backups(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_media_backups_post ON media_backups(post_id);
CREATE INDEX IF NOT EXISTS idx_media_backups_r2_key ON media_backups(r2_key);
