-- Migration 016: Add Pattern Extraction Fields
-- Description: Add fields to track pattern extraction results and import metadata
-- Date: 2026-02-14

-- =============================================================================
-- 1. Add pattern extraction tracking fields
-- =============================================================================

-- Pattern extraction results
ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS pattern_matched BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS pattern_confidence NUMERIC DEFAULT 0,
ADD COLUMN IF NOT EXISTS extracted_actor TEXT,
ADD COLUMN IF NOT EXISTS extracted_genre TEXT,
ADD COLUMN IF NOT EXISTS extracted_year INTEGER;

-- Import tracking fields
ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS import_sort_order VARCHAR(50),
ADD COLUMN IF NOT EXISTS import_index INTEGER,
ADD COLUMN IF NOT EXISTS channel_tag VARCHAR(100);

-- =============================================================================
-- 2. Add comments for documentation
-- =============================================================================

COMMENT ON COLUMN staged_movies.pattern_matched IS 'Whether pattern regex matched the YouTube title';
COMMENT ON COLUMN staged_movies.pattern_confidence IS 'Confidence score of pattern extraction (0.0-1.0)';
COMMENT ON COLUMN staged_movies.extracted_actor IS 'Actor name extracted from YouTube title using channel pattern';
COMMENT ON COLUMN staged_movies.extracted_genre IS 'Genre extracted from YouTube title using channel pattern';
COMMENT ON COLUMN staged_movies.extracted_year IS 'Release year extracted from YouTube title using channel pattern';
COMMENT ON COLUMN staged_movies.import_sort_order IS 'Sort order used during import (latest, alphabetical, etc)';
COMMENT ON COLUMN staged_movies.import_index IS 'Position in import batch (0-based)';
COMMENT ON COLUMN staged_movies.channel_tag IS 'Tag from channel settings applied during import';

-- =============================================================================
-- 3. Create indexes for pattern extraction queries
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_staged_movies_pattern_matched
    ON staged_movies(pattern_matched)
    WHERE pattern_matched = TRUE;

CREATE INDEX IF NOT EXISTS idx_staged_movies_extracted_year
    ON staged_movies(extracted_year)
    WHERE extracted_year IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_staged_movies_import_batch_index
    ON staged_movies(import_batch_id, import_index)
    WHERE import_batch_id IS NOT NULL;

-- =============================================================================
-- 4. Create view for pattern extraction analysis
-- =============================================================================

CREATE OR REPLACE VIEW staged_movies_pattern_extraction AS
SELECT
    sm.id,
    sm.youtube_video_title,
    sm.title AS extracted_title,
    sm.extracted_actor,
    sm.extracted_genre,
    sm.extracted_year,
    sm.pattern_matched,
    sm.pattern_confidence,
    sm.channel_id,
    c.title AS channel_title,
    sm.approval_status,
    sm.created_at
FROM staged_movies sm
JOIN channels c ON sm.channel_id = c.id
WHERE sm.pattern_matched = TRUE
ORDER BY sm.created_at DESC;

COMMENT ON VIEW staged_movies_pattern_extraction IS 'Movies where pattern successfully extracted metadata from YouTube title';

-- =============================================================================
-- 5. Verification queries (commented out - run manually to verify)
-- =============================================================================

/*
-- Check pattern extraction success rate
SELECT
    channel_id,
    COUNT(*) as total_imports,
    COUNT(CASE WHEN pattern_matched THEN 1 END) as pattern_matched_count,
    ROUND(COUNT(CASE WHEN pattern_matched THEN 1 END)::NUMERIC / COUNT(*) * 100, 2) as match_rate_percent
FROM staged_movies
GROUP BY channel_id
ORDER BY match_rate_percent DESC;

-- Check extracted metadata completeness
SELECT
    COUNT(*) as total,
    COUNT(extracted_actor) as has_actor,
    COUNT(extracted_genre) as has_genre,
    COUNT(extracted_year) as has_year,
    COUNT(CASE WHEN pattern_matched THEN 1 END) as pattern_matched
FROM staged_movies;

-- Test view
SELECT * FROM staged_movies_pattern_extraction LIMIT 10;
*/
