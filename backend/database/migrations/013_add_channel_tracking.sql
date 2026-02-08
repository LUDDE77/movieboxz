-- Migration 013: Add Channel Tracking to Movies Tables
-- Description: Add import tracking and channel tagging to movies and staged_movies
-- Date: 2026-02-08

-- =============================================================================
-- 1. Add columns to movies table
-- =============================================================================

ALTER TABLE movies
ADD COLUMN IF NOT EXISTS import_batch_id UUID REFERENCES import_history(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS channel_tag VARCHAR(50),
ADD COLUMN IF NOT EXISTS import_sort_order VARCHAR(20),
ADD COLUMN IF NOT EXISTS import_index INTEGER; -- Position in import batch

-- =============================================================================
-- 2. Add columns to staged_movies table (already has import_batch_id)
-- =============================================================================

ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS channel_tag VARCHAR(50),
ADD COLUMN IF NOT EXISTS import_sort_order VARCHAR(20),
ADD COLUMN IF NOT EXISTS import_index INTEGER;

-- Note: staged_movies already has import_batch_id from migration 010

-- =============================================================================
-- 3. Create indexes for performance
-- =============================================================================

-- Movies table indexes
CREATE INDEX IF NOT EXISTS idx_movies_import_batch ON movies(import_batch_id) WHERE import_batch_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_movies_channel_tag ON movies(channel_tag) WHERE channel_tag IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_movies_channel_id_tag ON movies(channel_id, channel_tag);

-- Staged movies table indexes
CREATE INDEX IF NOT EXISTS idx_staged_movies_channel_tag ON staged_movies(channel_tag) WHERE channel_tag IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_staged_movies_channel_id_tag ON staged_movies(channel_id, channel_tag);

-- =============================================================================
-- 4. Create function to sync channel tags
-- =============================================================================

-- Automatically apply channel_tag from channel_settings when movie is inserted
CREATE OR REPLACE FUNCTION apply_channel_tag_to_movies()
RETURNS TRIGGER AS $$
BEGIN
    -- Get channel_tag from channel_settings if not already set
    IF NEW.channel_tag IS NULL THEN
        SELECT channel_tag INTO NEW.channel_tag
        FROM channel_settings
        WHERE channel_id = NEW.channel_id
          AND channel_tag IS NOT NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to movies table
CREATE TRIGGER apply_channel_tag_to_movies_trigger
    BEFORE INSERT ON movies
    FOR EACH ROW
    EXECUTE FUNCTION apply_channel_tag_to_movies();

-- Apply to staged_movies table
CREATE TRIGGER apply_channel_tag_to_staged_movies_trigger
    BEFORE INSERT ON staged_movies
    FOR EACH ROW
    EXECUTE FUNCTION apply_channel_tag_to_movies();

-- =============================================================================
-- 5. Create helper views for channel movie listings
-- =============================================================================

-- View: All movies by channel (staging + production)
CREATE OR REPLACE VIEW channel_movies_overview AS
SELECT
    c.id AS channel_id,
    c.title AS channel_title,
    COUNT(DISTINCT m.id) AS production_count,
    COUNT(DISTINCT sm.id) AS staging_count,
    COUNT(DISTINCT m.id) + COUNT(DISTINCT sm.id) AS total_count,
    MAX(GREATEST(m.created_at, sm.created_at)) AS last_added,
    cs.channel_tag
FROM channels c
LEFT JOIN movies m ON c.id = m.channel_id
LEFT JOIN staged_movies sm ON c.id = sm.channel_id
LEFT JOIN channel_settings cs ON c.id = cs.channel_id
GROUP BY c.id, c.title, cs.channel_tag;

-- View: Movies with import details
CREATE OR REPLACE VIEW movies_with_import_info AS
SELECT
    m.*,
    ih.import_type,
    ih.started_at AS import_started_at,
    ih.sort_order AS import_sort_order_used,
    c.title AS channel_title,
    cs.channel_tag
FROM movies m
LEFT JOIN import_history ih ON m.import_batch_id = ih.id
LEFT JOIN channels c ON m.channel_id = c.id
LEFT JOIN channel_settings cs ON c.id = cs.channel_id;

-- View: Staged movies with import details
CREATE OR REPLACE VIEW staged_movies_with_import_info AS
SELECT
    sm.*,
    ih.import_type,
    ih.started_at AS import_started_at,
    ih.sort_order AS import_sort_order_used,
    c.title AS channel_title,
    cs.channel_tag
FROM staged_movies sm
LEFT JOIN import_history ih ON sm.import_batch_id = ih.id
LEFT JOIN channels c ON sm.channel_id = c.id
LEFT JOIN channel_settings cs ON c.id = cs.channel_id;

-- =============================================================================
-- 6. Add comments for documentation
-- =============================================================================

COMMENT ON COLUMN movies.import_batch_id IS 'Links to the import operation that added this movie';
COMMENT ON COLUMN movies.channel_tag IS 'Inherited from channel_settings for filtering and organization';
COMMENT ON COLUMN movies.import_sort_order IS 'Sort order used during import (latest, alphabetical, etc.)';
COMMENT ON COLUMN movies.import_index IS 'Position in import batch (for maintaining sort order)';

COMMENT ON COLUMN staged_movies.channel_tag IS 'Inherited from channel_settings for filtering and organization';
COMMENT ON COLUMN staged_movies.import_sort_order IS 'Sort order used during import';
COMMENT ON COLUMN staged_movies.import_index IS 'Position in import batch';

-- =============================================================================
-- 7. Verification queries (commented out - run manually to test)
-- =============================================================================

/*
-- Test: Check movies by channel with tags
SELECT channel_id, channel_tag, COUNT(*)
FROM movies
GROUP BY channel_id, channel_tag;

-- Test: Check import history integration
SELECT
    c.title AS channel,
    ih.import_type,
    COUNT(m.id) AS movies_from_import
FROM import_history ih
JOIN channels c ON ih.channel_id = c.id
LEFT JOIN movies m ON ih.id = m.import_batch_id
GROUP BY c.title, ih.import_type;

-- Test: Channel movies overview
SELECT * FROM channel_movies_overview;
*/
