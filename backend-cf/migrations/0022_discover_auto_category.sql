-- Captro Discover auto-categorization metadata.
-- Optional legacy-table columns are added by ensureAutoCategorySchema() at runtime
-- because this deploy workflow replays migration files and D1 does not provide
-- portable ADD COLUMN IF NOT EXISTS for repeated executes.

SELECT 1;
