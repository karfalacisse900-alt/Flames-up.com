-- Canonicalize engagement rows/counters.
-- One user can like a post/comment/story only once; denormalized counters are
-- repaired from the real interaction rows instead of preserving stale values.

CREATE TABLE IF NOT EXISTS likes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

DELETE FROM likes
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY user_id, post_id
             ORDER BY COALESCE(created_at, ''), id
           ) AS rn
    FROM likes
  )
  WHERE rn > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_likes_user_post_unique
  ON likes(user_id, post_id);

UPDATE posts
SET likes_count = (
  SELECT COUNT(*)
  FROM likes
  WHERE likes.post_id = posts.id
);

CREATE TABLE IF NOT EXISTS comment_likes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  comment_id TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

DELETE FROM comment_likes
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY user_id, comment_id
             ORDER BY COALESCE(created_at, ''), id
           ) AS rn
    FROM comment_likes
  )
  WHERE rn > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_comment_likes_user_comment_unique
  ON comment_likes(user_id, comment_id);

UPDATE comments
SET likes_count = (
  SELECT COUNT(*)
  FROM comment_likes
  WHERE comment_likes.comment_id = comments.id
);

CREATE TABLE IF NOT EXISTS discover_likes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

DELETE FROM discover_likes
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY user_id, post_id
             ORDER BY COALESCE(created_at, ''), id
           ) AS rn
    FROM discover_likes
  )
  WHERE rn > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_discover_likes_user_post_unique
  ON discover_likes(user_id, post_id);

UPDATE discover_posts
SET likes_count = (
  SELECT COUNT(*)
  FROM discover_likes
  WHERE discover_likes.post_id = discover_posts.id
);

CREATE TABLE IF NOT EXISTS status_likes (
  id TEXT PRIMARY KEY,
  status_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(status_id, user_id)
);

DELETE FROM status_likes
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY status_id, user_id
             ORDER BY COALESCE(created_at, ''), id
           ) AS rn
    FROM status_likes
  )
  WHERE rn > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_status_likes_status_user_unique
  ON status_likes(status_id, user_id);
