-- Flames-Up D1 Database Schema v2
-- Adds: publisher_applications, admin fields, media in messages, discover_posts

-- Add missing columns to users
ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN is_publisher INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN location TEXT DEFAULT '';

-- Add media columns to messages
ALTER TABLE messages ADD COLUMN media_url TEXT;
ALTER TABLE messages ADD COLUMN media_type TEXT;

-- Publisher applications
CREATE TABLE IF NOT EXISTS publisher_applications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  user_username TEXT NOT NULL,
  user_full_name TEXT NOT NULL,
  user_profile_image TEXT DEFAULT '',
  business_name TEXT NOT NULL,
  category TEXT NOT NULL,
  about TEXT NOT NULL,
  phone TEXT NOT NULL,
  website TEXT DEFAULT '',
  social_instagram TEXT DEFAULT '',
  social_twitter TEXT DEFAULT '',
  social_tiktok TEXT DEFAULT '',
  address TEXT DEFAULT '',
  city TEXT DEFAULT '',
  why_publish TEXT NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TEXT DEFAULT (datetime('now'))
);

-- Discover posts (publisher content)
CREATE TABLE IF NOT EXISTS discover_posts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  content TEXT NOT NULL,
  image TEXT,
  images TEXT DEFAULT '[]',
  category TEXT DEFAULT 'local_news',
  location TEXT DEFAULT '',
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS discover_likes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE(user_id, post_id)
);

-- Places (user-created)
CREATE TABLE IF NOT EXISTS places (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  category TEXT DEFAULT '',
  lat REAL,
  lng REAL,
  address TEXT DEFAULT '',
  image TEXT,
  created_by TEXT NOT NULL,
  verified INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_publisher_apps_user ON publisher_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_discover_posts_user ON discover_posts(user_id);
CREATE INDEX IF NOT EXISTS idx_discover_posts_category ON discover_posts(category);
CREATE INDEX IF NOT EXISTS idx_places_created_by ON places(created_by);
