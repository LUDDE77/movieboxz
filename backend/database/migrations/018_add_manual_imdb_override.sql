-- Migration 018: Add Manual IMDB Override Fields
-- Description: Allow users to manually set IMDB ID and mark movies as verified
-- Date: 2026-02-15
--
-- Use Case: When auto-enrichment finds wrong match, user can manually set correct IMDB ID
-- and system will trust their choice (won't override on future enrichments)

-- =============================================================================
-- 1. Add manual override fields to staged_movies
-- =============================================================================

ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS manual_imdb_id TEXT,
ADD COLUMN IF NOT EXISTS manually_verified BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS verified_by TEXT,
ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP WITH TIME ZONE;

-- =============================================================================
-- 2. Add comments for documentation
-- =============================================================================

COMMENT ON COLUMN staged_movies.manual_imdb_id IS 'IMDB ID manually set by user (e.g., tt1234567). When set, system trusts this over auto-enrichment.';
COMMENT ON COLUMN staged_movies.manually_verified IS 'TRUE if movie was manually verified by user. Auto-enrichment will not override these movies.';
COMMENT ON COLUMN staged_movies.verified_by IS 'Username/ID of user who manually verified this movie';
COMMENT ON COLUMN staged_movies.verified_at IS 'Timestamp when movie was manually verified';

-- =============================================================================
-- 3. Create index for manually verified movies
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_staged_movies_manually_verified
    ON staged_movies(manually_verified)
    WHERE manually_verified = TRUE;

CREATE INDEX IF NOT EXISTS idx_staged_movies_manual_imdb_id
    ON staged_movies(manual_imdb_id)
    WHERE manual_imdb_id IS NOT NULL;

-- =============================================================================
-- 4. Create view for manually verified movies
-- =============================================================================

CREATE OR REPLACE VIEW staged_movies_manually_verified AS
SELECT
    sm.id,
    sm.youtube_video_title,
    sm.title,
    sm.manual_imdb_id,
    sm.imdb_id AS auto_imdb_id,
    sm.manually_verified,
    sm.verified_by,
    sm.verified_at,
    sm.channel_id,
    c.title AS channel_title,
    sm.approval_status,
    sm.created_at
FROM staged_movies sm
JOIN channels c ON sm.channel_id = c.id
WHERE sm.manually_verified = TRUE
ORDER BY sm.verified_at DESC;

COMMENT ON VIEW staged_movies_manually_verified IS 'Movies that have been manually verified by users with correct IMDB IDs';

-- =============================================================================
-- 5. Verification queries (commented out - run manually to verify)
-- =============================================================================

/*
-- Check manual verification stats
SELECT
    COUNT(*) as total_staged,
    COUNT(CASE WHEN manually_verified THEN 1 END) as manually_verified_count,
    COUNT(CASE WHEN manual_imdb_id IS NOT NULL THEN 1 END) as has_manual_imdb
FROM staged_movies;

-- Test view
SELECT * FROM staged_movies_manually_verified LIMIT 10;
*/
