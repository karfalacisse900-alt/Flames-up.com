-- Prevent duplicate likes from stale clients or older schemas.
-- Keep the oldest like per user/post pair, then enforce uniqueness.

DELETE FROM likes
WHERE rowid NOT IN (
  SELECT MIN(rowid)
  FROM likes
  GROUP BY user_id, post_id
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_likes_user_post_unique
  ON likes(user_id, post_id);

UPDATE posts
SET likes_count = (
  SELECT COUNT(*)
  FROM likes
  WHERE likes.post_id = posts.id
);

DELETE FROM discover_likes
WHERE rowid NOT IN (
  SELECT MIN(rowid)
  FROM discover_likes
  GROUP BY user_id, post_id
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_discover_likes_user_post_unique
  ON discover_likes(user_id, post_id);

UPDATE discover_posts
SET likes_count = (
  SELECT COUNT(*)
  FROM discover_likes
  WHERE discover_likes.post_id = discover_posts.id
);
