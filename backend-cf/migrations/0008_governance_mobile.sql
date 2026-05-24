-- Governance Mobile moderation fields and audit log
-- Run locally:
--   wrangler d1 execute flames-up-db --file=./migrations/0008_governance_mobile.sql
-- Run on Cloudflare:
--   wrangler d1 execute flames-up-db --file=./migrations/0008_governance_mobile.sql --remote

ALTER TABLE users ADD COLUMN status TEXT DEFAULT 'active';
ALTER TABLE users ADD COLUMN banned_at TEXT;
ALTER TABLE users ADD COLUMN ban_reason TEXT;

ALTER TABLE posts ADD COLUMN status TEXT DEFAULT 'active';
ALTER TABLE posts ADD COLUMN removed_at TEXT;
ALTER TABLE posts ADD COLUMN removed_reason TEXT;

ALTER TABLE reports ADD COLUMN reported_type TEXT DEFAULT '';
ALTER TABLE reports ADD COLUMN details TEXT DEFAULT '';
ALTER TABLE reports ADD COLUMN status TEXT DEFAULT 'pending';
ALTER TABLE reports ADD COLUMN admin_notes TEXT DEFAULT '';
ALTER TABLE reports ADD COLUMN reviewed_by TEXT;
ALTER TABLE reports ADD COLUMN action_taken TEXT DEFAULT '';
ALTER TABLE reports ADD COLUMN updated_at TEXT;

CREATE TABLE IF NOT EXISTS admin_actions (
  id TEXT PRIMARY KEY,
  admin_id TEXT NOT NULL,
  action_type TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  details TEXT DEFAULT '',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status);
CREATE INDEX IF NOT EXISTS idx_admin_actions_created ON admin_actions(created_at);
