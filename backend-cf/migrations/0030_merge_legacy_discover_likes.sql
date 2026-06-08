-- Merge legacy Discover likes into canonical post likes.
-- This prevents one user from liking the same real post again through a
-- different route/cache after refresh.

CREATE TABLE IF NOT EXISTS likes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS discover_likes (
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

INSERT OR IGNORE INTO likes (id, user_id, post_id, created_at)
SELECT 'discover:' || user_id || ':' || post_id,
       user_id,
       post_id,
       COALESCE(created_at, datetime('now'))
FROM discover_likes
WHERE EXISTS (SELECT 1 FROM posts WHERE posts.id = discover_likes.post_id);

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

UPDATE posts
SET likes_count = (
  SELECT COUNT(*)
  FROM likes
  WHERE likes.post_id = posts.id
);

UPDATE discover_posts
SET likes_count = CASE
  WHEN EXISTS (SELECT 1 FROM posts WHERE posts.id = discover_posts.id) THEN (
    SELECT COUNT(*)
    FROM likes
    WHERE likes.post_id = discover_posts.id
  )
  ELSE (
    SELECT COUNT(*)
    FROM discover_likes
    WHERE discover_likes.post_id = discover_posts.id
  )
END;
