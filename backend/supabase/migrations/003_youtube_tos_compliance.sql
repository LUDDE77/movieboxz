-- Migration 003: YouTube TOS Compliance
-- Add required fields for YouTube Terms of Service compliance
-- Date: 2026-01-24

-- ============================================================================
-- Add YouTube metadata columns to movies table
-- ============================================================================

-- Add youtube_video_title (original YouTube video title - TOS requirement)
ALTER TABLE movies
    ADD COLUMN IF NOT EXISTS youtube_video_title TEXT;

-- Add channel_thumbnail (channel avatar URL)
ALTER TABLE movies
    ADD COLUMN IF NOT EXISTS channel_thumbnail TEXT;

-- Add last_refreshed (cache management timestamp - max 30 days per TOS)
ALTER TABLE movies
    ADD COLUMN IF NOT EXISTS last_refreshed TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Create index for cache management queries
CREATE INDEX IF NOT EXISTS idx_movies_last_refreshed ON movies(last_refreshed);

-- ============================================================================
-- Backfill existing data
-- ============================================================================

-- Update existing rows: set youtube_video_title from original_title
UPDATE movies
SET youtube_video_title = COALESCE(original_title, title)
WHERE youtube_video_title IS NULL;

-- Set NOT NULL constraint after backfill
ALTER TABLE movies
    ALTER COLUMN youtube_video_title SET NOT NULL;

-- Set default value for youtube_video_title
ALTER TABLE movies
    ALTER COLUMN youtube_video_title SET DEFAULT '';

-- ============================================================================
-- Comments for documentation
-- ============================================================================

COMMENT ON COLUMN movies.youtube_video_title IS 'Original YouTube video title (required for TOS Section III.D.8)';
COMMENT ON COLUMN movies.channel_thumbnail IS 'YouTube channel thumbnail/avatar URL';
COMMENT ON COLUMN movies.last_refreshed IS 'Last time metadata was refreshed from YouTube API (TOS: max 30 days cache)';