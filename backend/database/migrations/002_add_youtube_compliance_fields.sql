-- Migration: Add YouTube TOS Compliance Fields
-- Description: Add required YouTube metadata fields to movies table for TOS compliance
-- Date: 2026-01-24
-- Breaking: No (backward compatible with defaults)
-- Priority: CRITICAL - Required for YouTube TOS Section II.F

BEGIN;

-- =============================================================================
-- PHASE 0: YOUTUBE TOS COMPLIANCE (CRITICAL)
-- =============================================================================

-- Add required YouTube metadata columns to movies table
ALTER TABLE movies
    ADD COLUMN IF NOT EXISTS youtube_video_title TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS channel_thumbnail TEXT,
    ADD COLUMN IF NOT EXISTS last_refreshed TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Create index for cache management and refresh queries
CREATE INDEX IF NOT EXISTS idx_movies_last_refreshed ON movies(last_refreshed);

-- =============================================================================
-- DATA MIGRATION
-- =============================================================================

-- One-time update: Set youtube_video_title from current title for existing records
-- This ensures NOT NULL constraint is satisfied
UPDATE movies
SET youtube_video_title = title
WHERE youtube_video_title = '' OR youtube_video_title IS NULL;

-- Set last_refreshed for existing records (mark them as needing refresh)
-- Setting to 7 days ago ensures they'll be refreshed on next API call
UPDATE movies
SET last_refreshed = NOW() - INTERVAL '7 days'
WHERE last_refreshed IS NULL OR last_refreshed = created_at;

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON COLUMN movies.youtube_video_title IS 'Original YouTube video title (REQUIRED for TOS compliance - must display exact title from YouTube API)';
COMMENT ON COLUMN movies.channel_thumbnail IS 'Channel profile thumbnail URL from YouTube API';
COMMENT ON COLUMN movies.last_refreshed IS 'Last time YouTube metadata was refreshed (TOS requires max 30 day cache, recommend 24 hours)';

COMMIT;

-- =============================================================================
-- VERIFICATION QUERIES (Run after migration)
-- =============================================================================

-- Verify new columns exist
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_name = 'movies'
-- AND column_name IN ('youtube_video_title', 'channel_thumbnail', 'last_refreshed');

-- Verify all movies have youtube_video_title populated
-- SELECT COUNT(*) as total_movies,
--        COUNT(youtube_video_title) as with_yt_title,
--        COUNT(*) - COUNT(youtube_video_title) as missing_yt_title
-- FROM movies;

-- Check movies needing refresh (older than 24 hours)
-- SELECT COUNT(*) as movies_needing_refresh
-- FROM movies
-- WHERE last_refreshed < NOW() - INTERVAL '24 hours';
