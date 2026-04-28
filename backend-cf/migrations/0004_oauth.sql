-- Flames-Up D1 schema v4
-- OAuth support for Google / Apple account linking

ALTER TABLE users ADD COLUMN oauth_provider TEXT;
ALTER TABLE users ADD COLUMN oauth_subject TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_oauth_identity
  ON users(oauth_provider, oauth_subject);

