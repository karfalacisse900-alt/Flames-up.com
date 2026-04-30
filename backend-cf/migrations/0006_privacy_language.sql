-- Privacy, story visibility, and language preferences
-- Run locally:
--   wrangler d1 execute flames-up-db --file=./migrations/0006_privacy_language.sql
-- Run on Cloudflare:
--   wrangler d1 execute flames-up-db --file=./migrations/0006_privacy_language.sql --remote

ALTER TABLE users ADD COLUMN is_private INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN language TEXT DEFAULT 'en';
ALTER TABLE posts ADD COLUMN visibility TEXT DEFAULT 'public';
ALTER TABLE statuses ADD COLUMN visibility TEXT DEFAULT 'public';

CREATE INDEX IF NOT EXISTS idx_users_private ON users(is_private);
CREATE INDEX IF NOT EXISTS idx_posts_visibility ON posts(visibility);
CREATE INDEX IF NOT EXISTS idx_statuses_visibility ON statuses(visibility);
