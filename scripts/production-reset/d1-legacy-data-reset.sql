-- Captro protected legacy Cloudflare D1 data reset.
--
-- This file is NOT a migration and must not be wired into automatic deploys.
-- It exists only to clear legacy compatibility/cache data after Supabase has
-- been backed up and reset.
--
-- Run only with:
--   wrangler d1 execute DB --env production --remote --yes --file=../scripts/production-reset/d1-legacy-data-reset.sql
--
-- Keep schemas. Delete user/test/generated rows only.

PRAGMA foreign_keys = OFF;

DELETE FROM status_likes;
DELETE FROM discover_likes;
DELETE FROM comment_likes;
DELETE FROM likes;
DELETE FROM saved_posts;
DELETE FROM saved_places;
DELETE FROM comments;
DELETE FROM reports;
DELETE FROM private_info_reports;
DELETE FROM impersonation_reports;
DELETE FROM content_match_events;
DELETE FROM blocks;
DELETE FROM notifications;
DELETE FROM push_tokens;
DELETE FROM message_typing;
DELETE FROM messages;
DELETE FROM group_messages;
DELETE FROM group_chat_members;
DELETE FROM group_chats;
DELETE FROM user_presence;
DELETE FROM media_assets;
DELETE FROM media_backups;
DELETE FROM moderation_results;
DELETE FROM moderation_jobs;
DELETE FROM moderation_events;
DELETE FROM moderation_notes;
DELETE FROM moderation_actions;
DELETE FROM admin_actions;
DELETE FROM audit_logs;
DELETE FROM user_restrictions;
DELETE FROM anti_abuse_signals;
DELETE FROM anti_bot_signals;
DELETE FROM client_events;
DELETE FROM ownership_disputes;
DELETE FROM remix_permission_requests;
DELETE FROM publisher_applications;
DELETE FROM creator_credit_ledger;
DELETE FROM creator_portfolio_items;
DELETE FROM credit_chains;
DELETE FROM creators;
DELETE FROM ownership_records;
DELETE FROM reputation_events;
DELETE FROM reputation_profiles;
DELETE FROM posts;
DELETE FROM discover_posts;
DELETE FROM statuses;
DELETE FROM favorite_sounds;
DELETE FROM phone_login_codes;
DELETE FROM follows;
DELETE FROM friendships;
DELETE FROM friend_requests;
DELETE FROM places;
DELETE FROM account_deletion_events;
DELETE FROM deleted_account_safety_records;
DELETE FROM account_identities;
DELETE FROM users;

PRAGMA foreign_keys = ON;
