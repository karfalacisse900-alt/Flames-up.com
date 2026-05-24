CREATE TABLE IF NOT EXISTS favorite_sounds (
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
);

CREATE INDEX IF NOT EXISTS idx_favorite_sounds_user ON favorite_sounds(user_id, provider, created_at);
