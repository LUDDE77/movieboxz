-- Migration 024: Add Episode Metadata to Staged Movies
-- Description: Add columns to support TV series episodes with season/episode numbers and episode names
-- Date: 2026-02-22

-- Add episode-specific columns
ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS episode_name TEXT,
ADD COLUMN IF NOT EXISTS season_number INTEGER,
ADD COLUMN IF NOT EXISTS episode_number INTEGER,
ADD COLUMN IF NOT EXISTS is_tv_series BOOLEAN DEFAULT false;

-- Add indexes for series filtering
CREATE INDEX IF NOT EXISTS idx_staged_movies_series
ON staged_movies(is_tv_series)
WHERE is_tv_series = true;

CREATE INDEX IF NOT EXISTS idx_staged_movies_series_season
ON staged_movies(channel_id, season_number, episode_number)
WHERE is_tv_series = true;

-- Add comments
COMMENT ON COLUMN staged_movies.episode_name IS 'Name/title of the specific episode (for TV series)';
COMMENT ON COLUMN staged_movies.season_number IS 'Season number (for TV series episodes)';
COMMENT ON COLUMN staged_movies.episode_number IS 'Episode number within the season (for TV series)';
