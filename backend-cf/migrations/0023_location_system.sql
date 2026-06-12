-- Captro two-layer location metadata.
-- Optional legacy-table columns and indexes are added by ensureLocationSchema()
-- at runtime because this deploy workflow replays migration files and D1 does
-- not provide portable ADD COLUMN IF NOT EXISTS for repeated executes.

SELECT 1;
