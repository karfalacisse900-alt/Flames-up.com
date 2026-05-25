-- Captro admin/moderation MVP support tables.
-- Runtime schema guards add optional columns to legacy tables safely because D1
-- does not support ADD COLUMN IF NOT EXISTS across every deployment target.

CREATE TABLE IF NOT EXISTS admin_roles (
  user_id TEXT PRIMARY KEY,
  role TEXT NOT NULL,
  created_at TEXT NOT NULL,
  created_by TEXT DEFAULT '',
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS moderation_notes (
  id TEXT PRIMARY KEY,
  report_id TEXT DEFAULT '',
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  author_admin_user_id TEXT NOT NULL,
  note TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS moderation_actions (
  id TEXT PRIMARY KEY,
  actor_admin_user_id TEXT NOT NULL,
  actor_role TEXT NOT NULL,
  action_type TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  target_user_id TEXT DEFAULT '',
  reason TEXT DEFAULT '',
  note TEXT DEFAULT '',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY,
  actor_admin_user_id TEXT NOT NULL,
  actor_role TEXT NOT NULL,
  action_type TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  target_user_id TEXT DEFAULT '',
  reason TEXT DEFAULT '',
  internal_note TEXT DEFAULT '',
  before_state TEXT DEFAULT '{}',
  after_state TEXT DEFAULT '{}',
  ip_hash TEXT DEFAULT '',
  request_id TEXT DEFAULT '',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_restrictions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  restriction_type TEXT NOT NULL,
  reason TEXT DEFAULT '',
  starts_at TEXT NOT NULL,
  ends_at TEXT,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_admin_roles_role ON admin_roles(role);
CREATE INDEX IF NOT EXISTS idx_moderation_notes_report ON moderation_notes(report_id, created_at);
CREATE INDEX IF NOT EXISTS idx_moderation_notes_target ON moderation_notes(target_type, target_id, created_at);
CREATE INDEX IF NOT EXISTS idx_moderation_actions_target ON moderation_actions(target_type, target_id, created_at);
CREATE INDEX IF NOT EXISTS idx_moderation_actions_actor ON moderation_actions(actor_admin_user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs(actor_admin_user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_target ON audit_logs(target_type, target_id, created_at);
CREATE INDEX IF NOT EXISTS idx_user_restrictions_user_active ON user_restrictions(user_id, restriction_type, starts_at, ends_at);
