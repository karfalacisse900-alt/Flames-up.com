-- Flames-Up D1 Database Schema v3
-- Creator Hub system - badges, applications, profiles, portfolio

-- Creator profiles
CREATE TABLE IF NOT EXISTS creators (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE,
  category TEXT NOT NULL,
  skills TEXT DEFAULT '[]',
  portfolio_links TEXT DEFAULT '[]',
  short_bio TEXT DEFAULT '',
  city TEXT DEFAULT '',
  borough TEXT DEFAULT '',
  availability_status TEXT DEFAULT 'available',
  pricing_range TEXT DEFAULT '',
  contact_link TEXT DEFAULT '',
  example_work TEXT DEFAULT '[]',
  status TEXT DEFAULT 'pending',
  is_verified INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Creator portfolio items (pinned posts)
CREATE TABLE IF NOT EXISTS creator_portfolio_items (
  id TEXT PRIMARY KEY,
  creator_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  display_order INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE(creator_id, post_id),
  FOREIGN KEY (creator_id) REFERENCES creators(id),
  FOREIGN KEY (post_id) REFERENCES posts(id)
);

-- Add is_creator column to users
ALTER TABLE users ADD COLUMN is_creator INTEGER DEFAULT 0;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_creators_user ON creators(user_id);
CREATE INDEX IF NOT EXISTS idx_creators_status ON creators(status);
CREATE INDEX IF NOT EXISTS idx_creators_category ON creators(category);
CREATE INDEX IF NOT EXISTS idx_creators_city ON creators(city);
CREATE INDEX IF NOT EXISTS idx_creators_availability ON creators(availability_status);
CREATE INDEX IF NOT EXISTS idx_portfolio_creator ON creator_portfolio_items(creator_id);
