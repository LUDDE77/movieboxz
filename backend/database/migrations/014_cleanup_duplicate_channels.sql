-- Migration 014: Cleanup Duplicate Channel Entries
-- Description: Remove duplicate channel entries with @handle as ID
-- Date: 2026-02-08

-- Delete channel with @handle as ID (duplicate of proper UC ID)
DELETE FROM channel_settings WHERE channel_id = '@TheMidnightScreening';
DELETE FROM channels WHERE id = '@TheMidnightScreening';

-- Verify: Should only have proper UC channel IDs after this
-- SELECT id, title FROM channels WHERE title = 'The Midnight Screening';
