-- Migration 015: Add Duration Filters to Channel Settings
-- Description: Allow filtering videos by duration during import
-- Date: 2026-02-08

-- =============================================================================
-- 1. Add duration filter columns to channel_settings
-- =============================================================================

ALTER TABLE channel_settings
ADD COLUMN IF NOT EXISTS min_duration_minutes INTEGER,
ADD COLUMN IF NOT EXISTS max_duration_minutes INTEGER,
ADD COLUMN IF NOT EXISTS filter_shorts BOOLEAN DEFAULT TRUE;

-- =============================================================================
-- 2. Add comments for clarity
-- =============================================================================

COMMENT ON COLUMN channel_settings.min_duration_minutes IS 'Minimum video duration in minutes (e.g., 60 for feature films)';
COMMENT ON COLUMN channel_settings.max_duration_minutes IS 'Maximum video duration in minutes (e.g., 180 to exclude very long videos)';
COMMENT ON COLUMN channel_settings.filter_shorts IS 'Automatically filter out YouTube Shorts (< 1 minute)';

-- =============================================================================
-- 3. Create index for performance
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_channel_settings_duration_filters
ON channel_settings(min_duration_minutes, max_duration_minutes)
WHERE min_duration_minutes IS NOT NULL OR max_duration_minutes IS NOT NULL;

-- =============================================================================
-- Example usage:
-- =============================================================================

-- Feature films only (60-180 minutes)
-- UPDATE channel_settings
-- SET min_duration_minutes = 60,
--     max_duration_minutes = 180,
--     filter_shorts = TRUE
-- WHERE channel_id = 'UC6A_LC-A5NVJ2vw9A0OjCug';

-- No shorts, but allow all feature lengths
-- UPDATE channel_settings
-- SET min_duration_minutes = 10,
--     filter_shorts = TRUE
-- WHERE channel_id = 'UC6A_LC-A5NVJ2vw9A0OjCug';
