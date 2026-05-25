CREATE TABLE IF NOT EXISTS push_tokens (
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
);

CREATE TABLE IF NOT EXISTS client_events (
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
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON push_tokens(user_id, is_active, last_seen_at);
CREATE INDEX IF NOT EXISTS idx_client_events_name_created ON client_events(event_name, created_at);
CREATE INDEX IF NOT EXISTS idx_client_events_user_created ON client_events(user_id, created_at);
