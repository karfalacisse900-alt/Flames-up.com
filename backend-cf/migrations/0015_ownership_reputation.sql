-- Ownership + Reputation Layer
-- App-level creator proof, credit chains, internal creator credits, and private trust signals.
-- This is not cryptocurrency and does not provide legal copyright registration.

CREATE TABLE IF NOT EXISTS ownership_records (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  post_id TEXT,
  media_id TEXT,
  title TEXT NOT NULL,
  description TEXT,
  content_type TEXT NOT NULL DEFAULT 'post' CHECK (content_type IN ('post', 'image', 'video', 'audio', 'text', 'idea', 'design', 'event', 'other')),
  content_hash TEXT NOT NULL,
  perceptual_hash TEXT,
  storage_url TEXT,
  ipfs_cid TEXT,
  original_filename TEXT,
  file_size INTEGER,
  mime_type TEXT,
  license_type TEXT NOT NULL DEFAULT 'share_with_credit' CHECK (license_type IN ('all_rights_reserved', 'share_with_credit', 'remix_with_credit', 'commercial_requires_permission', 'open_use')),
  visibility TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'followers', 'private')),
  status TEXT NOT NULL DEFAULT 'original' CHECK (status IN ('original', 'duplicate', 'possible_repost', 'credited_repost', 'possible_remix', 'credited_remix', 'under_review', 'idea_proof_only', 'active', 'disputed', 'removed', 'transferred')),
  chain_id TEXT,
  contract_address TEXT,
  token_id TEXT,
  transaction_hash TEXT,
  arweave_tx_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (post_id) REFERENCES posts(id)
);

CREATE TABLE IF NOT EXISTS credit_chains (
  id TEXT PRIMARY KEY,
  original_ownership_id TEXT NOT NULL,
  derived_ownership_id TEXT NOT NULL,
  original_user_id TEXT NOT NULL,
  derived_user_id TEXT NOT NULL,
  relationship_type TEXT NOT NULL CHECK (relationship_type IN ('repost', 'remix', 'quote', 'inspiration', 'collaboration', 'licensed_use')),
  permission_status TEXT NOT NULL DEFAULT 'pending' CHECK (permission_status IN ('allowed', 'pending', 'denied', 'disputed')),
  credit_required INTEGER NOT NULL DEFAULT 1,
  royalty_percent REAL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (original_ownership_id) REFERENCES ownership_records(id),
  FOREIGN KEY (derived_ownership_id) REFERENCES ownership_records(id)
);

CREATE TABLE IF NOT EXISTS remix_permission_requests (
  id TEXT PRIMARY KEY,
  original_ownership_id TEXT NOT NULL,
  requester_id TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'denied')),
  message TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (original_ownership_id) REFERENCES ownership_records(id)
);

CREATE TABLE IF NOT EXISTS reputation_profiles (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE,
  reputation_score INTEGER NOT NULL DEFAULT 100,
  originality_score INTEGER NOT NULL DEFAULT 0,
  trust_score INTEGER NOT NULL DEFAULT 50,
  community_score INTEGER NOT NULL DEFAULT 0,
  violation_score INTEGER NOT NULL DEFAULT 0,
  bot_risk_score INTEGER NOT NULL DEFAULT 0,
  verified_human_level TEXT NOT NULL DEFAULT 'none' CHECK (verified_human_level IN ('none', 'basic', 'strong')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS reputation_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN (
    'original_content_registered',
    'duplicate_content_detected',
    'valid_credit_given',
    'remix_permission_granted',
    'report_submitted',
    'report_confirmed',
    'stolen_content_confirmed',
    'spam_detected',
    'fake_engagement_detected',
    'abusive_behavior',
    'ban_evasion_signal',
    'trusted_activity',
    'admin_adjustment'
  )),
  score_delta INTEGER NOT NULL DEFAULT 0,
  reason TEXT NOT NULL DEFAULT '',
  related_post_id TEXT,
  related_ownership_id TEXT,
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS creator_credit_ledger (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  amount INTEGER NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('credit', 'debit')),
  reason TEXT NOT NULL CHECK (reason IN ('original_creation', 'trusted_report', 'remix_fee', 'community_reward', 'admin_adjustment', 'penalty')),
  related_post_id TEXT,
  related_ownership_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS ownership_disputes (
  id TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL,
  accused_user_id TEXT,
  original_ownership_id TEXT,
  disputed_post_id TEXT,
  reason TEXT NOT NULL CHECK (reason IN ('stolen_content', 'no_credit', 'impersonation', 'unauthorized_commercial_use', 'false_ownership_claim', 'other')),
  description TEXT NOT NULL DEFAULT '',
  evidence_urls TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'accepted', 'rejected', 'resolved')),
  admin_notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (reporter_id) REFERENCES users(id),
  FOREIGN KEY (original_ownership_id) REFERENCES ownership_records(id)
);

CREATE TABLE IF NOT EXISTS private_info_reports (
  id TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  reported_user_id TEXT NOT NULL,
  detected_types TEXT NOT NULL DEFAULT '[]',
  description TEXT,
  risk_level TEXT NOT NULL DEFAULT 'medium' CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'hidden_pending_review', 'accepted', 'rejected', 'resolved')),
  admin_notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (reporter_id) REFERENCES users(id),
  FOREIGN KEY (post_id) REFERENCES posts(id)
);

CREATE TABLE IF NOT EXISTS content_match_events (
  id TEXT PRIMARY KEY,
  uploaded_by_user_id TEXT NOT NULL,
  post_id TEXT,
  matched_ownership_id TEXT,
  match_type TEXT NOT NULL CHECK (match_type IN ('exact_hash', 'perceptual_hash', 'text_similarity', 'manual_report')),
  confidence_score REAL NOT NULL DEFAULT 0,
  action_taken TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (uploaded_by_user_id) REFERENCES users(id),
  FOREIGN KEY (matched_ownership_id) REFERENCES ownership_records(id)
);

CREATE TABLE IF NOT EXISTS anti_abuse_signals (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  signal_type TEXT NOT NULL CHECK (signal_type IN (
    'repeated_stolen_content',
    'suspicious_post_velocity',
    'duplicate_content_farming',
    'fake_ownership_claims',
    'fake_reports',
    'impersonation_pattern',
    'doxxing_pattern',
    'repeated_private_info_uploads'
  )),
  risk_level TEXT NOT NULL CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS anti_bot_signals (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  signal_type TEXT NOT NULL CHECK (signal_type IN (
    'repeated_device_pattern',
    'repeated_ip_pattern',
    'repeated_profile_details',
    'repeated_links',
    'suspicious_post_velocity',
    'fake_engagement_pattern',
    'duplicate_content_farming',
    'ban_evasion_pattern',
    'abuse_pattern'
  )),
  risk_level TEXT NOT NULL CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS impersonation_reports (
  id TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL,
  reported_user_id TEXT NOT NULL,
  target_name TEXT NOT NULL DEFAULT '',
  real_account_url TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  evidence_urls TEXT NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'accepted', 'rejected', 'resolved')),
  admin_notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (reporter_id) REFERENCES users(id),
  FOREIGN KEY (reported_user_id) REFERENCES users(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ownership_content_hash_unique ON ownership_records(content_hash);
CREATE INDEX IF NOT EXISTS idx_ownership_user_created ON ownership_records(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ownership_post ON ownership_records(post_id);
CREATE INDEX IF NOT EXISTS idx_ownership_status ON ownership_records(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_credit_chains_original ON credit_chains(original_ownership_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_credit_chains_derived ON credit_chains(derived_ownership_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_permission_requests_owner ON remix_permission_requests(owner_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reputation_events_user ON reputation_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_creator_credit_user ON creator_credit_ledger(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ownership_disputes_status ON ownership_disputes(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_private_info_reports_status ON private_info_reports(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_match_events_match ON content_match_events(match_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_anti_abuse_user ON anti_abuse_signals(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_impersonation_reports_status ON impersonation_reports(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_anti_bot_risk ON anti_bot_signals(risk_level, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_anti_bot_user ON anti_bot_signals(user_id, created_at DESC);

ALTER TABLE posts ADD COLUMN ownership_record_id TEXT;
ALTER TABLE posts ADD COLUMN ownership_status TEXT NOT NULL DEFAULT '';
ALTER TABLE posts ADD COLUMN ownership_duplicate_of TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN wallet_address TEXT;
