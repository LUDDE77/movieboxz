-- Migration 012: Create Import History Table
-- Description: Track all import operations with detailed metrics
-- Date: 2026-02-08

-- =============================================================================
-- 1. Create import status enum
-- =============================================================================

DO $$ BEGIN
    CREATE TYPE import_status AS ENUM ('pending', 'running', 'completed', 'failed', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- =============================================================================
-- 2. Create import_history table
-- =============================================================================

CREATE TABLE IF NOT EXISTS import_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id VARCHAR(50) REFERENCES channels(id) ON DELETE CASCADE,
    batch_id UUID, -- Links related imports together

    -- Import configuration
    import_type VARCHAR(20) NOT NULL, -- 'full', 'partial', 'latest', 'manual'
    import_limit INTEGER, -- NULL = all, or specific number
    sort_order VARCHAR(20), -- 'latest', 'oldest', 'alphabetical_az', 'alphabetical_za', 'views'

    -- Import results
    videos_found INTEGER DEFAULT 0,
    videos_imported INTEGER DEFAULT 0,
    videos_skipped INTEGER DEFAULT 0,
    videos_failed INTEGER DEFAULT 0,

    -- Processing details
    status import_status DEFAULT 'pending',
    error_message TEXT,
    error_details JSONB,

    -- Applied settings
    applied_settings JSONB, -- Snapshot of channel_settings at import time
    auto_enriched BOOLEAN DEFAULT FALSE,

    -- Performance metrics
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    duration_seconds INTEGER,

    -- Progress tracking (for real-time updates)
    current_video_title TEXT,
    current_video_index INTEGER,

    -- Metadata
    created_by VARCHAR(100), -- User or 'system'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- 3. Create indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_import_history_channel_id ON import_history(channel_id);
CREATE INDEX IF NOT EXISTS idx_import_history_batch_id ON import_history(batch_id) WHERE batch_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_import_history_status ON import_history(status);
CREATE INDEX IF NOT EXISTS idx_import_history_started_at ON import_history(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_import_history_running ON import_history(id) WHERE status = 'running';

-- =============================================================================
-- 4. Add helper functions
-- =============================================================================

-- Function to calculate duration automatically
CREATE OR REPLACE FUNCTION calculate_import_duration()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IN ('completed', 'failed', 'cancelled') AND NEW.completed_at IS NOT NULL THEN
        NEW.duration_seconds = EXTRACT(EPOCH FROM (NEW.completed_at - NEW.started_at))::INTEGER;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_import_duration_trigger
    BEFORE UPDATE ON import_history
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION calculate_import_duration();

-- Function to update channel_settings statistics
CREATE OR REPLACE FUNCTION update_channel_import_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' THEN
        UPDATE channel_settings
        SET
            last_import_at = NEW.completed_at,
            total_imported = total_imported + NEW.videos_imported
        WHERE channel_id = NEW.channel_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_channel_import_stats_trigger
    AFTER UPDATE ON import_history
    FOR EACH ROW
    WHEN (OLD.status != 'completed' AND NEW.status = 'completed')
    EXECUTE FUNCTION update_channel_import_stats();

-- =============================================================================
-- 5. Create helper views
-- =============================================================================

-- View: Recent imports with channel info
CREATE OR REPLACE VIEW import_history_with_channel AS
SELECT
    ih.*,
    c.title AS channel_title,
    c.thumbnail_url AS channel_thumbnail,
    CASE
        WHEN ih.status = 'completed' THEN '✅'
        WHEN ih.status = 'failed' THEN '❌'
        WHEN ih.status = 'running' THEN '⏳'
        WHEN ih.status = 'cancelled' THEN '🚫'
        ELSE '⏸️'
    END AS status_emoji,
    CASE
        WHEN ih.videos_found > 0 THEN
            ROUND((ih.videos_imported::NUMERIC / ih.videos_found::NUMERIC) * 100, 1)
        ELSE 0
    END AS success_rate
FROM import_history ih
LEFT JOIN channels c ON ih.channel_id = c.id
ORDER BY ih.started_at DESC;

-- View: Import statistics by channel
CREATE OR REPLACE VIEW channel_import_stats AS
SELECT
    c.id AS channel_id,
    c.title AS channel_title,
    COUNT(ih.id) AS total_imports,
    SUM(ih.videos_imported) AS total_videos_imported,
    SUM(ih.videos_failed) AS total_videos_failed,
    MAX(ih.started_at) AS last_import_at,
    AVG(ih.duration_seconds) AS avg_duration_seconds,
    COUNT(*) FILTER (WHERE ih.status = 'completed') AS successful_imports,
    COUNT(*) FILTER (WHERE ih.status = 'failed') AS failed_imports
FROM channels c
LEFT JOIN import_history ih ON c.id = ih.channel_id
GROUP BY c.id, c.title;

-- =============================================================================
-- 6. Add comments for documentation
-- =============================================================================

COMMENT ON TABLE import_history IS 'Detailed history of all import operations per channel';
COMMENT ON COLUMN import_history.import_type IS 'Type of import: full (all videos), partial (limited), latest (newest N), manual (user-triggered)';
COMMENT ON COLUMN import_history.import_limit IS 'Maximum number of videos to import (NULL = unlimited)';
COMMENT ON COLUMN import_history.sort_order IS 'Video sort order for import: latest, oldest, alphabetical, views';
COMMENT ON COLUMN import_history.applied_settings IS 'Snapshot of channel_settings at time of import';
COMMENT ON COLUMN import_history.batch_id IS 'Groups related imports together (e.g., multi-channel bulk import)';
COMMENT ON COLUMN import_history.duration_seconds IS 'Total time taken for import in seconds';
