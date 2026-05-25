-- Production hot-path indexes for feed, discover, profile grids, comments, chat, saves, and notifications.
-- These are safe to run multiple times.

CREATE INDEX IF NOT EXISTS idx_posts_created_desc
  ON posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_user_created
  ON posts(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_type_created
  ON posts(post_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_visibility_created
  ON posts(visibility, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_comments_post_created
  ON comments(post_id, created_at);

CREATE INDEX IF NOT EXISTS idx_likes_post_user
  ON likes(post_id, user_id);

CREATE INDEX IF NOT EXISTS idx_saved_posts_post_user
  ON saved_posts(post_id, user_id);
CREATE INDEX IF NOT EXISTS idx_saved_posts_user_created
  ON saved_posts(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_follows_following_follower
  ON follows(following_id, follower_id);

CREATE INDEX IF NOT EXISTS idx_messages_receiver_sender_created
  ON messages(receiver_id, sender_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_sender_created
  ON messages(sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_receiver_created
  ON messages(receiver_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread_created
  ON notifications(user_id, is_read, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_blocks_blocked_blocker
  ON blocks(blocked_id, blocker_id);

CREATE INDEX IF NOT EXISTS idx_discover_posts_category_created
  ON discover_posts(category, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_discover_posts_user_created
  ON discover_posts(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_discover_likes_post_user
  ON discover_likes(post_id, user_id);
