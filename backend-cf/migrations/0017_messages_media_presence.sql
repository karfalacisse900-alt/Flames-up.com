-- Message reliability upgrade.
-- Safe to run more than once through Wrangler; duplicate columns can be ignored by runtime schema repair.

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  sender_id TEXT NOT NULL,
  receiver_id TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  media_url TEXT,
  media_type TEXT,
  is_read INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (sender_id) REFERENCES users(id),
  FOREIGN KEY (receiver_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_messages_sender_receiver_created
  ON messages(sender_id, receiver_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_receiver_read
  ON messages(receiver_id, is_read);

CREATE TABLE IF NOT EXISTS user_presence (
  user_id TEXT PRIMARY KEY,
  last_seen_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS message_typing (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  is_typing INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_message_typing_pair
  ON message_typing(user_id, peer_id);
CREATE INDEX IF NOT EXISTS idx_message_typing_peer_updated
  ON message_typing(peer_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_user_presence_last_seen
  ON user_presence(last_seen_at);
