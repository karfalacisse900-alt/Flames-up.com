-- Content safety upgrade for app-level ownership proof.
-- Adds exact/similar-match metadata, private-info reports, impersonation reports, and private anti-abuse signals.
-- Non-destructive: old ownership records and posts remain readable.

ALTER TABLE ownership_records ADD COLUMN exact_hash TEXT;
ALTER TABLE ownership_records ADD COLUMN text_similarity_key TEXT;
ALTER TABLE ownership_records ADD COLUMN object_labels TEXT DEFAULT '[]';
ALTER TABLE ownership_records ADD COLUMN location_labels TEXT DEFAULT '[]';
ALTER TABLE ownership_records ADD COLUMN original_ownership_id TEXT;

CREATE TABLE IF NOT EXISTS private_info_reports (
  id TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  reported_user_id TEXT NOT NULL,
  detected_types TEXT NOT NULL DEFAULT '[]',
  description TEXT,
  risk_level TEXT NOT NULL DEFAULT 'medium',
  status TEXT NOT NULL DEFAULT 'pending',
  admin_notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS content_match_events (
  id TEXT PRIMARY KEY,
  uploaded_by_user_id TEXT NOT NULL,
  post_id TEXT,
  matched_ownership_id TEXT,
  match_type TEXT NOT NULL,
  confidence_score REAL NOT NULL DEFAULT 0,
  action_taken TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS anti_abuse_signals (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  signal_type TEXT NOT NULL,
  risk_level TEXT NOT NULL,
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS impersonation_reports (
  id TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL,
  reported_user_id TEXT NOT NULL,
  target_name TEXT NOT NULL DEFAULT '',
  real_account_url TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  evidence_urls TEXT NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'pending',
  admin_notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ownership_exact_hash ON ownership_records(exact_hash);
CREATE INDEX IF NOT EXISTS idx_ownership_similarity_key ON ownership_records(text_similarity_key);
CREATE INDEX IF NOT EXISTS idx_ownership_original ON ownership_records(original_ownership_id);
CREATE INDEX IF NOT EXISTS idx_private_info_reports_status ON private_info_reports(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_match_events_match ON content_match_events(match_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_anti_abuse_user ON anti_abuse_signals(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_impersonation_reports_status ON impersonation_reports(status, created_at DESC);
