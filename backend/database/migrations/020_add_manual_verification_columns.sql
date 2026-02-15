-- Migration 020: Add manual verification columns to staged_movies
-- Description: Track manual IMDB ID and verification status
-- Date: 2026-02-15

-- Add manual_imdb_id column
ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS manual_imdb_id VARCHAR(20);

-- Add manually_verified column
ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS manually_verified BOOLEAN DEFAULT FALSE;

-- Add verified_by column
ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS verified_by VARCHAR(100);

-- Add verified_at column
ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP WITH TIME ZONE;

-- Add index for querying manually verified movies
CREATE INDEX IF NOT EXISTS idx_staged_movies_manually_verified
    ON staged_movies(manually_verified)
    WHERE manually_verified = TRUE;

-- Add comments
COMMENT ON COLUMN staged_movies.manual_imdb_id IS 'IMDB ID manually entered by admin for enrichment';
COMMENT ON COLUMN staged_movies.manually_verified IS 'Whether this movie has been manually verified by admin';
COMMENT ON COLUMN staged_movies.verified_by IS 'Username/ID of admin who verified this movie';
COMMENT ON COLUMN staged_movies.verified_at IS 'Timestamp when movie was manually verified';
