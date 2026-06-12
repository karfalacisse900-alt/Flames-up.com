-- Captro secure account deletion lifecycle.
-- ADD COLUMN statements are guarded at runtime by ensureAccountDeletionSchema()
-- because D1 replays migration files and portable ADD COLUMN IF NOT EXISTS is
-- not available everywhere.

CREATE TABLE IF NOT EXISTS account_identities (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  provider_user_id TEXT NOT NULL,
  email_hash TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(provider, provider_user_id)
);

CREATE TABLE IF NOT EXISTS account_deletion_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  actor_user_id TEXT DEFAULT '',
  reason TEXT DEFAULT '',
  metadata TEXT DEFAULT '{}',
  request_id TEXT DEFAULT '',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS deleted_account_safety_records (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  email_hash TEXT DEFAULT '',
  provider TEXT DEFAULT '',
  provider_user_id_hash TEXT DEFAULT '',
  status_at_deletion TEXT DEFAULT '',
  reason TEXT DEFAULT '',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_account_identities_user ON account_identities(user_id);
CREATE INDEX IF NOT EXISTS idx_account_identities_email_hash ON account_identities(email_hash);
CREATE INDEX IF NOT EXISTS idx_account_deletion_events_user ON account_deletion_events(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_deleted_account_safety_email ON deleted_account_safety_records(email_hash);
