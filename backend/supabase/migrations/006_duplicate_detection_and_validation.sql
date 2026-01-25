-- Migration 006: Duplicate Detection and Link Validation System
-- Purpose: Track movie duplicates, enable automatic failover to backups
-- Date: 2026-01-25

-- ============================================================================
-- Enable Extensions
-- ============================================================================

-- pg_trgm: Fuzzy text matching for duplicate detection
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ============================================================================
-- Movie Groups Table
-- Groups duplicate movies from different YouTube channels
-- ============================================================================

CREATE TABLE IF NOT EXISTS movie_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tmdb_id INTEGER UNIQUE,  -- TMDB movie ID (most reliable duplicate detector)
    canonical_title TEXT NOT NULL,  -- Official movie title
    normalized_title TEXT NOT NULL,  -- Lowercase, no punctuation (for fuzzy matching)
    release_year INTEGER,  -- Helps distinguish remakes
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Fuzzy text search index for finding similar titles
CREATE INDEX idx_movie_groups_normalized_title ON movie_groups USING gin(normalized_title gin_trgm_ops);

-- Fast lookup by TMDB ID
CREATE INDEX idx_movie_groups_tmdb_id ON movie_groups(tmdb_id) WHERE tmdb_id IS NOT NULL;

-- Comments
COMMENT ON TABLE movie_groups IS 'Groups duplicate movies from different YouTube channels';
COMMENT ON COLUMN movie_groups.tmdb_id IS 'TMDB movie ID - most reliable duplicate detector';
COMMENT ON COLUMN movie_groups.normalized_title IS 'Lowercase title without punctuation for fuzzy matching';

-- ============================================================================
-- Add Columns to Movies Table
-- ============================================================================

-- Link movies to their group
ALTER TABLE movies ADD COLUMN IF NOT EXISTS movie_group_id UUID REFERENCES movie_groups(id) ON DELETE SET NULL;

-- Primary/backup tracking
ALTER TABLE movies ADD COLUMN IF NOT EXISTS is_primary BOOLEAN DEFAULT false;
ALTER TABLE movies ADD COLUMN IF NOT EXISTS backup_priority INTEGER DEFAULT 0;

-- Quality scoring for ranking backups
ALTER TABLE movies ADD COLUMN IF NOT EXISTS quality_score INTEGER DEFAULT 0;

-- YouTube metadata for quality calculation
ALTER TABLE movies ADD COLUMN IF NOT EXISTS view_count BIGINT;
ALTER TABLE movies ADD COLUMN IF NOT EXISTS published_at TIMESTAMP WITH TIME ZONE;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_movies_group_primary ON movies(movie_group_id, is_primary);
CREATE INDEX IF NOT EXISTS idx_movies_quality ON movies(quality_score DESC);
CREATE INDEX IF NOT EXISTS idx_movies_validation ON movies(last_validated ASC NULLS FIRST) WHERE is_available = true;

-- Comments
COMMENT ON COLUMN movies.movie_group_id IS 'Links to movie_groups for duplicate tracking';
COMMENT ON COLUMN movies.is_primary IS 'Only one primary per group (shown in app)';
COMMENT ON COLUMN movies.backup_priority IS 'Manual override for backup ranking (higher = better)';
COMMENT ON COLUMN movies.quality_score IS 'Calculated score (0-100) based on views, channel rep, etc.';
COMMENT ON COLUMN movies.view_count IS 'YouTube view count for quality scoring';

-- ============================================================================
-- Validation Runs Table
-- Track daily validation job statistics
-- ============================================================================

CREATE TABLE IF NOT EXISTS validation_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_date TIMESTAMP WITH TIME ZONE NOT NULL,
    validated_count INTEGER NOT NULL DEFAULT 0,
    failed_count INTEGER NOT NULL DEFAULT 0,
    failover_count INTEGER NOT NULL DEFAULT 0,
    quota_used INTEGER NOT NULL DEFAULT 0,  -- YouTube API units consumed
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_validation_runs_date ON validation_runs(run_date DESC);

COMMENT ON TABLE validation_runs IS 'Daily validation job statistics';
COMMENT ON COLUMN validation_runs.quota_used IS 'YouTube API quota units consumed during this run';

-- ============================================================================
-- Validation Failures Table
-- Track individual video failures for analysis
-- ============================================================================

CREATE TABLE IF NOT EXISTS validation_failures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    movie_id UUID REFERENCES movies(id) ON DELETE CASCADE,
    youtube_video_id TEXT NOT NULL,
    failure_reason TEXT,  -- 'not_found', 'private', 'deleted', etc.
    detected_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_primary BOOLEAN NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_validation_failures_movie ON validation_failures(movie_id);
CREATE INDEX idx_validation_failures_date ON validation_failures(detected_at DESC);
CREATE INDEX idx_validation_failures_youtube ON validation_failures(youtube_video_id);

COMMENT ON TABLE validation_failures IS 'Track individual video validation failures';
COMMENT ON COLUMN validation_failures.failure_reason IS 'not_found, private, deleted, not_processed, etc.';

-- ============================================================================
-- Failover Events Table
-- Log automatic backup promotions
-- ============================================================================

CREATE TABLE IF NOT EXISTS failover_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    movie_group_id UUID REFERENCES movie_groups(id) ON DELETE CASCADE,
    old_primary_id UUID REFERENCES movies(id) ON DELETE SET NULL,
    new_primary_id UUID REFERENCES movies(id) ON DELETE CASCADE,
    triggered_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_failover_events_group ON failover_events(movie_group_id);
CREATE INDEX idx_failover_events_triggered ON failover_events(triggered_at DESC);

COMMENT ON TABLE failover_events IS 'Log automatic backup promotions when primary videos fail';

-- ============================================================================
-- Admin Alerts Table
-- Notify admins when all backups fail
-- ============================================================================

CREATE TABLE IF NOT EXISTS admin_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type TEXT NOT NULL,  -- 'all_backups_failed', 'quota_exceeded', etc.
    movie_group_id UUID REFERENCES movie_groups(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    severity TEXT DEFAULT 'warning',  -- 'info', 'warning', 'critical'
    resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_admin_alerts_unresolved ON admin_alerts(resolved, created_at DESC);
CREATE INDEX idx_admin_alerts_type ON admin_alerts(type);

COMMENT ON TABLE admin_alerts IS 'Admin notifications for critical failures';
COMMENT ON COLUMN admin_alerts.type IS 'all_backups_failed, quota_exceeded, validation_failed, etc.';

-- ============================================================================
-- API Quota Usage Table
-- Track YouTube API quota consumption
-- ============================================================================

CREATE TABLE IF NOT EXISTS api_quota_usage (
    date DATE NOT NULL,
    operation TEXT NOT NULL,  -- 'videos.list', 'search.list', etc.
    units INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (date, operation)
);

CREATE INDEX idx_api_quota_date ON api_quota_usage(date DESC);

COMMENT ON TABLE api_quota_usage IS 'Track YouTube API quota consumption';
COMMENT ON COLUMN api_quota_usage.units IS 'API quota units consumed (videos.list=1, search.list=100)';

-- ============================================================================
-- Trigger: Update movie_groups.updated_at
-- ============================================================================

CREATE OR REPLACE FUNCTION update_movie_groups_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_movie_groups_updated_at ON movie_groups;
CREATE TRIGGER update_movie_groups_updated_at
    BEFORE UPDATE ON movie_groups
    FOR EACH ROW
    EXECUTE FUNCTION update_movie_groups_updated_at();

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Calculate string similarity using pg_trgm
CREATE OR REPLACE FUNCTION calculate_title_similarity(title1 TEXT, title2 TEXT)
RETURNS FLOAT AS $$
BEGIN
    RETURN similarity(
        lower(regexp_replace(title1, '[^\w\s]', '', 'g')),
        lower(regexp_replace(title2, '[^\w\s]', '', 'g'))
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_title_similarity IS 'Calculate similarity between two movie titles (0-1)';

-- Find similar movie groups using fuzzy matching
CREATE OR REPLACE FUNCTION find_similar_movie_groups(
    search_title TEXT,
    search_year INTEGER DEFAULT NULL,
    year_tolerance INTEGER DEFAULT 1,
    similarity_threshold FLOAT DEFAULT 0.7
)
RETURNS TABLE (
    id UUID,
    tmdb_id INTEGER,
    canonical_title TEXT,
    normalized_title TEXT,
    release_year INTEGER,
    similarity FLOAT,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        mg.id,
        mg.tmdb_id,
        mg.canonical_title,
        mg.normalized_title,
        mg.release_year,
        similarity(mg.normalized_title, search_title) as similarity,
        mg.created_at,
        mg.updated_at
    FROM movie_groups mg
    WHERE
        -- Fuzzy title match using pg_trgm
        mg.normalized_title % search_title
        AND similarity(mg.normalized_title, search_title) >= similarity_threshold
        AND (
            -- If year provided, match within tolerance
            search_year IS NULL
            OR mg.release_year IS NULL
            OR ABS(mg.release_year - search_year) <= year_tolerance
        )
    ORDER BY similarity DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION find_similar_movie_groups IS 'Find similar movie groups using fuzzy title matching and optional year filter';

-- ============================================================================
-- Views for Easy Querying
-- ============================================================================

-- View: Movies with backup count
CREATE OR REPLACE VIEW movies_with_backup_info AS
SELECT
    m.*,
    mg.canonical_title as group_canonical_title,
    mg.tmdb_id as group_tmdb_id,
    (
        SELECT COUNT(*)
        FROM movies backup
        WHERE backup.movie_group_id = m.movie_group_id
          AND backup.is_available = true
          AND backup.id != m.id
    ) as backup_count,
    (
        SELECT COUNT(*)
        FROM movies total
        WHERE total.movie_group_id = m.movie_group_id
    ) as total_versions
FROM movies m
LEFT JOIN movie_groups mg ON m.movie_group_id = mg.id;

COMMENT ON VIEW movies_with_backup_info IS 'Movies with backup count and group info';

-- View: Movies ready for validation (oldest first)
CREATE OR REPLACE VIEW movies_pending_validation AS
SELECT
    id,
    youtube_video_id,
    title,
    movie_group_id,
    is_primary,
    last_validated,
    COALESCE(EXTRACT(EPOCH FROM (NOW() - last_validated)) / 86400, 999999) as days_since_validation
FROM movies
WHERE is_available = true
ORDER BY last_validated ASC NULLS FIRST;

COMMENT ON VIEW movies_pending_validation IS 'Movies ordered by validation priority (oldest first)';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

-- Grant access to authenticated users (for RLS policies later)
ALTER TABLE movie_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE validation_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE validation_failures ENABLE ROW LEVEL SECURITY;
ALTER TABLE failover_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_quota_usage ENABLE ROW LEVEL SECURITY;

-- Allow service role full access (backend operations)
CREATE POLICY "Service role full access on movie_groups" ON movie_groups FOR ALL USING (true);
CREATE POLICY "Service role full access on validation_runs" ON validation_runs FOR ALL USING (true);
CREATE POLICY "Service role full access on validation_failures" ON validation_failures FOR ALL USING (true);
CREATE POLICY "Service role full access on failover_events" ON failover_events FOR ALL USING (true);
CREATE POLICY "Service role full access on admin_alerts" ON admin_alerts FOR ALL USING (true);
CREATE POLICY "Service role full access on api_quota_usage" ON api_quota_usage FOR ALL USING (true);

-- Allow anonymous read access to movie_groups (for public API)
CREATE POLICY "Public read access on movie_groups" ON movie_groups FOR SELECT USING (true);
