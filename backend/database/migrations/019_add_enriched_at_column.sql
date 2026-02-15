-- Migration 019: Add enriched_at column to staged_movies
-- Description: Track when a movie was enriched with OMDB/TMDB data
-- Date: 2026-02-15

-- Add enriched_at column if it doesn't exist
ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS enriched_at TIMESTAMP WITH TIME ZONE;

-- Add index for querying recently enriched movies
CREATE INDEX IF NOT EXISTS idx_staged_movies_enriched_at
    ON staged_movies(enriched_at)
    WHERE enriched_at IS NOT NULL;

-- Add comment
COMMENT ON COLUMN staged_movies.enriched_at IS 'Timestamp when movie was enriched with OMDB/TMDB data';
