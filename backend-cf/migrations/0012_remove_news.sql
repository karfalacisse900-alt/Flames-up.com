-- Remove the retired Smart News system and its stored data.
DELETE FROM reports WHERE report_type = 'news' OR reported_type = 'news';

DROP TABLE IF EXISTS news_reading_history;
DROP TABLE IF EXISTS news_reports;
DROP TABLE IF EXISTS news_interactions;
DROP TABLE IF EXISTS blocked_news_sources;
DROP TABLE IF EXISTS news_cards;
