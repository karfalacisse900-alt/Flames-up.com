-- Retire the experimental Ownership / Protect this creation system.
-- This removes the feature data tables while keeping posts and media intact.
DROP TABLE IF EXISTS ownership_disputes;
DROP TABLE IF EXISTS remix_permission_requests;
DROP TABLE IF EXISTS credit_chains;
DROP TABLE IF EXISTS content_match_events;
DROP TABLE IF EXISTS private_info_reports;
DROP TABLE IF EXISTS anti_bot_signals;
DROP TABLE IF EXISTS anti_abuse_signals;
DROP TABLE IF EXISTS creator_credit_ledger;
DROP TABLE IF EXISTS reputation_events;
DROP TABLE IF EXISTS reputation_profiles;
DROP TABLE IF EXISTS ownership_records;
