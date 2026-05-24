-- Flames-Up D1 schema v9
-- Comment replies, likes, and moderation reporting support.

ALTER TABLE comments ADD COLUMN parent_id TEXT;
ALTER TABLE comments ADD COLUMN likes_count INTEGER DEFAULT 0;

CREATE TABLE IF NOT EXISTS comment_likes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  comment_id TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE(user_id, comment_id)
);

CREATE INDEX IF NOT EXISTS idx_comments_parent
  ON comments(parent_id, created_at);

CREATE INDEX IF NOT EXISTS idx_comment_likes_comment
  ON comment_likes(comment_id);

CREATE INDEX IF NOT EXISTS idx_comment_likes_user
  ON comment_likes(user_id);
