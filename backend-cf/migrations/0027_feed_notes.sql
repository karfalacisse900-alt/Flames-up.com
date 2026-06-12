ALTER TABLE posts ADD COLUMN note_font_style TEXT DEFAULT '';
ALTER TABLE posts ADD COLUMN note_background_style TEXT DEFAULT '';
ALTER TABLE posts ADD COLUMN note_text_color TEXT DEFAULT '';
ALTER TABLE posts ADD COLUMN note_alignment TEXT DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_posts_type_created ON posts(post_type, created_at DESC);
