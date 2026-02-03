-- Migration 010: Create Staged Movies Table
-- Description: Staging table for import review workflow before publishing to production
-- Date: 2026-02-03

-- =============================================================================
-- 1. Create approval status enum
-- =============================================================================

DO $$ BEGIN
    CREATE TYPE approval_status AS ENUM ('pending', 'approved', 'rejected');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- =============================================================================
-- 2. Create staged_movies table (mirrors movies table with staging fields)
-- =============================================================================

CREATE TABLE IF NOT EXISTS staged_movies (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Core movie fields (from movies table)
    youtube_video_id VARCHAR(20) NOT NULL,
    youtube_video_title TEXT NOT NULL DEFAULT '',
    title VARCHAR(500) NOT NULL,
    original_title VARCHAR(500),
    description TEXT,
    release_date DATE,
    runtime_minutes INTEGER,

    -- Channel reference
    channel_id VARCHAR(50) NOT NULL REFERENCES channels(id) ON DELETE CASCADE,

    -- YouTube metrics
    view_count BIGINT DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    published_at TIMESTAMPTZ,

    -- External IDs
    tmdb_id INTEGER,
    imdb_id VARCHAR(20),

    -- Enrichment data
    tmdb_data JSONB,
    poster_path VARCHAR(500),
    backdrop_path VARCHAR(500),

    -- Ratings
    vote_average NUMERIC,
    vote_count INTEGER DEFAULT 0,
    popularity NUMERIC,
    imdb_rating NUMERIC(3,1),
    imdb_votes INTEGER,

    -- Content metadata
    rated VARCHAR(10),
    director TEXT,
    actors TEXT,
    language VARCHAR(255),
    country VARCHAR(255),

    -- Flags
    is_tv_show BOOLEAN DEFAULT FALSE,
    is_embeddable BOOLEAN DEFAULT TRUE,
    is_available BOOLEAN DEFAULT TRUE,
    is_monetized BOOLEAN DEFAULT TRUE,

    -- Region restrictions
    region_allowed TEXT[],
    region_blocked TEXT[],

    -- Content classification
    category VARCHAR(50),
    quality VARCHAR(10) DEFAULT '720p',
    content_rating VARCHAR(10),

    -- Editorial flags
    featured BOOLEAN DEFAULT FALSE,
    trending BOOLEAN DEFAULT FALSE,
    staff_pick BOOLEAN DEFAULT FALSE,

    -- Validation
    validation_error TEXT,

    -- Search
    search_vector TSVECTOR,

    -- Duplicate detection
    movie_group_id UUID,
    is_primary BOOLEAN DEFAULT FALSE,
    backup_priority INTEGER DEFAULT 0,
    quality_score INTEGER DEFAULT 0,

    -- Enrichment tracking
    enrichment_source VARCHAR(20),
    enrichment_confidence NUMERIC,

    -- =============================================================================
    -- STAGING-SPECIFIC FIELDS
    -- =============================================================================

    -- Enrichment preview (test enrichment results before applying)
    enrichment_preview JSONB,
    COMMENT ON COLUMN staged_movies.enrichment_preview IS 'Preview of enrichment data from TMDB/OMDB before applying',

    -- Manual changes tracking
    manual_changes JSONB,
    COMMENT ON COLUMN staged_movies.manual_changes IS 'User manual edits: {"title": {"old": "X", "new": "Y", "timestamp": "..."}}',

    -- Approval workflow
    approval_status approval_status DEFAULT 'pending',
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    rejected_reason TEXT,

    -- Admin notes
    notes TEXT,
    COMMENT ON COLUMN staged_movies.notes IS 'Admin notes about this staged movie',

    -- Import source tracking
    import_batch_id UUID,
    COMMENT ON COLUMN staged_movies.import_batch_id IS 'Links to batch import job for tracking',

    -- Published movie reference (if approved and published)
    published_movie_id UUID REFERENCES movies(id) ON DELETE SET NULL,
    COMMENT ON COLUMN staged_movies.published_movie_id IS 'Reference to published movie in production table',

    -- Timestamps
    added_at TIMESTAMPTZ DEFAULT NOW(),
    last_refreshed TIMESTAMPTZ DEFAULT NOW(),
    last_validated TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- 3. Create indexes for performance
-- =============================================================================

-- Core lookups
CREATE INDEX IF NOT EXISTS idx_staged_movies_youtube_video_id ON staged_movies(youtube_video_id);
CREATE INDEX IF NOT EXISTS idx_staged_movies_channel_id ON staged_movies(channel_id);
CREATE INDEX IF NOT EXISTS idx_staged_movies_tmdb_id ON staged_movies(tmdb_id) WHERE tmdb_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_staged_movies_imdb_id ON staged_movies(imdb_id) WHERE imdb_id IS NOT NULL;

-- Workflow status
CREATE INDEX IF NOT EXISTS idx_staged_movies_approval_status ON staged_movies(approval_status);
CREATE INDEX IF NOT EXISTS idx_staged_movies_pending ON staged_movies(created_at) WHERE approval_status = 'pending';

-- Import tracking
CREATE INDEX IF NOT EXISTS idx_staged_movies_import_batch ON staged_movies(import_batch_id) WHERE import_batch_id IS NOT NULL;

-- Published reference
CREATE INDEX IF NOT EXISTS idx_staged_movies_published ON staged_movies(published_movie_id) WHERE published_movie_id IS NOT NULL;

-- Search
CREATE INDEX IF NOT EXISTS idx_staged_movies_search ON staged_movies USING GIN(search_vector);

-- Enrichment
CREATE INDEX IF NOT EXISTS idx_staged_movies_enrichment_source ON staged_movies(enrichment_source);
CREATE INDEX IF NOT EXISTS idx_staged_movies_unenriched ON staged_movies(id)
    WHERE tmdb_id IS NULL AND imdb_id IS NULL;

-- =============================================================================
-- 4. Create unique constraint (prevent duplicate imports)
-- =============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_staged_movies_unique_video
    ON staged_movies(youtube_video_id, channel_id)
    WHERE approval_status = 'pending';
COMMENT ON INDEX idx_staged_movies_unique_video IS 'Prevent duplicate pending imports of same video';

-- =============================================================================
-- 5. Create triggers
-- =============================================================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION update_staged_movies_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER staged_movies_updated_at
    BEFORE UPDATE ON staged_movies
    FOR EACH ROW
    EXECUTE FUNCTION update_staged_movies_updated_at();

-- Track manual changes trigger
CREATE OR REPLACE FUNCTION track_staged_movie_changes()
RETURNS TRIGGER AS $$
DECLARE
    change_record JSONB := '{}'::jsonb;
    field_name TEXT;
    field_changed BOOLEAN := FALSE;
BEGIN
    -- Track which fields were manually changed
    IF OLD.title IS DISTINCT FROM NEW.title THEN
        change_record := jsonb_set(change_record, '{title}',
            jsonb_build_object('old', OLD.title, 'new', NEW.title, 'timestamp', NOW()));
        field_changed := TRUE;
    END IF;

    IF OLD.description IS DISTINCT FROM NEW.description THEN
        change_record := jsonb_set(change_record, '{description}',
            jsonb_build_object('old', OLD.description, 'new', NEW.description, 'timestamp', NOW()));
        field_changed := TRUE;
    END IF;

    IF OLD.release_date IS DISTINCT FROM NEW.release_date THEN
        change_record := jsonb_set(change_record, '{release_date}',
            jsonb_build_object('old', OLD.release_date, 'new', NEW.release_date, 'timestamp', NOW()));
        field_changed := TRUE;
    END IF;

    IF OLD.poster_path IS DISTINCT FROM NEW.poster_path THEN
        change_record := jsonb_set(change_record, '{poster_path}',
            jsonb_build_object('old', OLD.poster_path, 'new', NEW.poster_path, 'timestamp', NOW()));
        field_changed := TRUE;
    END IF;

    -- Merge with existing manual_changes
    IF field_changed THEN
        NEW.manual_changes := COALESCE(NEW.manual_changes, '{}'::jsonb) || change_record;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER track_staged_movie_manual_changes
    BEFORE UPDATE ON staged_movies
    FOR EACH ROW
    WHEN (OLD.approval_status = 'pending' AND NEW.approval_status = 'pending')
    EXECUTE FUNCTION track_staged_movie_changes();

-- Update search vector trigger
CREATE OR REPLACE FUNCTION update_staged_movie_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.original_title, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.description, '')), 'C') ||
        setweight(to_tsvector('english', COALESCE(NEW.actors, '')), 'D');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_staged_movie_search_vector_trigger
    BEFORE INSERT OR UPDATE OF title, original_title, description, actors
    ON staged_movies
    FOR EACH ROW
    EXECUTE FUNCTION update_staged_movie_search_vector();

-- =============================================================================
-- 6. Create helper views
-- =============================================================================

-- View: Pending movies ready for review
CREATE OR REPLACE VIEW staged_movies_pending AS
SELECT
    sm.*,
    c.title AS channel_title
FROM staged_movies sm
JOIN channels c ON sm.channel_id = c.id
WHERE sm.approval_status = 'pending'
ORDER BY sm.created_at DESC;

-- View: Enriched staged movies (ready for approval)
CREATE OR REPLACE VIEW staged_movies_enriched AS
SELECT
    sm.*,
    c.title AS channel_title,
    CASE
        WHEN sm.tmdb_id IS NOT NULL THEN 'tmdb'
        WHEN sm.imdb_id IS NOT NULL THEN 'omdb'
        ELSE 'none'
    END AS enrichment_status
FROM staged_movies sm
JOIN channels c ON sm.channel_id = c.id
WHERE sm.approval_status = 'pending'
  AND (sm.tmdb_id IS NOT NULL OR sm.imdb_id IS NOT NULL)
ORDER BY sm.enrichment_confidence DESC NULLS LAST, sm.created_at DESC;

-- View: Unenriched staged movies (need enrichment)
CREATE OR REPLACE VIEW staged_movies_unenriched AS
SELECT
    sm.*,
    c.title AS channel_title
FROM staged_movies sm
JOIN channels c ON sm.channel_id = c.id
WHERE sm.approval_status = 'pending'
  AND sm.tmdb_id IS NULL
  AND sm.imdb_id IS NULL
ORDER BY sm.created_at DESC;

-- =============================================================================
-- 7. Add comments for documentation
-- =============================================================================

COMMENT ON TABLE staged_movies IS 'Staging table for movie import review workflow';
COMMENT ON COLUMN staged_movies.approval_status IS 'Workflow status: pending (needs review), approved (ready to publish), rejected (will not publish)';
COMMENT ON COLUMN staged_movies.enrichment_preview IS 'Test enrichment results from TMDB/OMDB for preview before applying';
COMMENT ON COLUMN staged_movies.manual_changes IS 'JSON tracking of all manual edits by admin before publishing';

-- =============================================================================
-- 8. Verification queries (commented out - run manually to verify)
-- =============================================================================

/*
-- Check pending staged movies
SELECT approval_status, COUNT(*)
FROM staged_movies
GROUP BY approval_status;

-- Check enrichment status
SELECT
    COUNT(*) as total,
    COUNT(tmdb_id) as tmdb_enriched,
    COUNT(imdb_id) as omdb_enriched,
    COUNT(*) - COUNT(tmdb_id) - COUNT(imdb_id) as unenriched
FROM staged_movies
WHERE approval_status = 'pending';

-- Test views
SELECT * FROM staged_movies_pending LIMIT 5;
SELECT * FROM staged_movies_enriched LIMIT 5;
SELECT * FROM staged_movies_unenriched LIMIT 5;
*/
