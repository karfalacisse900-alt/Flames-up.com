-- Structured Captro Notes documents and editorial Wall support.
CREATE TABLE IF NOT EXISTS notes (
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
);

ALTER TABLE notes ADD COLUMN schema_version INTEGER DEFAULT 1;
ALTER TABLE notes ADD COLUMN artwork_mode TEXT DEFAULT 'editable_canvas';
ALTER TABLE notes ADD COLUMN content_kind TEXT DEFAULT '';
ALTER TABLE notes ADD COLUMN canvas_width REAL DEFAULT 1080;
ALTER TABLE notes ADD COLUMN canvas_height REAL DEFAULT 1350;
ALTER TABLE notes ADD COLUMN document TEXT DEFAULT '';
ALTER TABLE notes ADD COLUMN detail_blocks TEXT DEFAULT '[]';
ALTER TABLE notes ADD COLUMN visibility TEXT DEFAULT 'everyone';
ALTER TABLE notes ADD COLUMN thumbnail_reference TEXT DEFAULT '';
ALTER TABLE notes ADD COLUMN alt_text TEXT DEFAULT '';

CREATE TABLE IF NOT EXISTS note_interactions (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  value TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  UNIQUE(note_id, user_id, kind)
);

CREATE TABLE IF NOT EXISTS note_comments (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  parent_id TEXT DEFAULT '',
  body TEXT NOT NULL,
  likes_count INTEGER DEFAULT 0,
  status TEXT DEFAULT 'active',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS note_comment_likes (
  id TEXT PRIMARY KEY,
  comment_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(comment_id, user_id)
);

CREATE TABLE IF NOT EXISTS note_reports (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,
  reporter_id TEXT NOT NULL,
  reason TEXT DEFAULT '',
  details TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  UNIQUE(note_id, reporter_id)
);

CREATE TABLE IF NOT EXISTS note_assets (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  asset_type TEXT NOT NULL,
  source_url TEXT NOT NULL,
  original_url TEXT DEFAULT '',
  thumbnail_url TEXT DEFAULT '',
  width REAL,
  height REAL,
  status TEXT DEFAULT 'active',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS note_signatures (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  body TEXT NOT NULL,
  doodle_url TEXT DEFAULT '',
  status TEXT DEFAULT 'active',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_notes_kind_created ON notes(content_kind, created_at);
CREATE INDEX IF NOT EXISTS idx_notes_visibility_created ON notes(visibility, created_at);
CREATE INDEX IF NOT EXISTS idx_note_interactions_user ON note_interactions(user_id, kind, created_at);
CREATE INDEX IF NOT EXISTS idx_note_comments_note ON note_comments(note_id, created_at);
CREATE INDEX IF NOT EXISTS idx_note_comment_likes_comment ON note_comment_likes(comment_id, created_at);
CREATE INDEX IF NOT EXISTS idx_note_reports_note ON note_reports(note_id, created_at);
CREATE INDEX IF NOT EXISTS idx_note_assets_note ON note_assets(note_id, created_at);
CREATE INDEX IF NOT EXISTS idx_note_signatures_note ON note_signatures(note_id, created_at);
