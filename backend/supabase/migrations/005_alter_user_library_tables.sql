-- Migration 005: Alter User Library Tables
-- Add missing columns to existing user_favorites and watch_history tables
-- Date: 2026-01-24

-- ============================================================================
-- Alter user_favorites table
-- ============================================================================

-- Add priority column for manual ordering (iOS drag-and-drop)
ALTER TABLE user_favorites
    ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 0;

-- Add created_at and updated_at if they don't exist
ALTER TABLE user_favorites
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE user_favorites
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Create index for priority ordering
CREATE INDEX IF NOT EXISTS idx_favorites_priority ON user_favorites(user_id, priority);

-- Update comment
COMMENT ON COLUMN user_favorites.priority IS 'Sort order for drag-and-drop reordering (lower number = higher priority)';

-- ============================================================================
-- Alter watch_history table
-- ============================================================================

-- Add watch_count column for tracking number of views
ALTER TABLE watch_history
    ADD COLUMN IF NOT EXISTS watch_count INTEGER DEFAULT 1;

-- Add first_watched_at (similar to started_at)
ALTER TABLE watch_history
    ADD COLUMN IF NOT EXISTS first_watched_at TIMESTAMP WITH TIME ZONE;

-- Add platform column (iOS, tvOS, web)
ALTER TABLE watch_history
    ADD COLUMN IF NOT EXISTS platform TEXT CHECK (platform IN ('iOS', 'tvOS', 'web'));

-- Backfill first_watched_at from started_at where null
UPDATE watch_history
SET first_watched_at = started_at
WHERE first_watched_at IS NULL;

-- Backfill platform from device_type where null
UPDATE watch_history
SET platform = CASE
    WHEN device_type ILIKE '%ios%' THEN 'iOS'
    WHEN device_type ILIKE '%tvos%' OR device_type ILIKE '%appletv%' THEN 'tvOS'
    ELSE 'web'
END
WHERE platform IS NULL AND device_type IS NOT NULL;

-- Create index for watch_count
CREATE INDEX IF NOT EXISTS idx_history_watch_count ON watch_history(user_id, watch_count DESC);

-- Update comments
COMMENT ON COLUMN watch_history.watch_count IS 'Number of times user has watched this movie';
COMMENT ON COLUMN watch_history.first_watched_at IS 'First time user watched this content';
COMMENT ON COLUMN watch_history.platform IS 'Platform where movie was watched (iOS, tvOS, web)';

-- ============================================================================
-- Update trigger for watch count increment (if not exists)
-- ============================================================================

-- Drop existing trigger if any
DROP TRIGGER IF EXISTS watch_history_increment_trigger ON watch_history;

-- Create or replace function
CREATE OR REPLACE FUNCTION increment_watch_count()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM watch_history
        WHERE user_id = NEW.user_id AND movie_id = NEW.movie_id
    ) THEN
        UPDATE watch_history
        SET
            watch_count = COALESCE(watch_count, 0) + 1,
            last_watched_at = NEW.last_watched_at,
            platform = COALESCE(NEW.platform, platform),
            updated_at = NOW()
        WHERE user_id = NEW.user_id AND movie_id = NEW.movie_id;
        RETURN NULL;
    ELSE
        NEW.watch_count = 1;
        NEW.first_watched_at = COALESCE(NEW.first_watched_at, NEW.started_at, NOW());
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER watch_history_increment_trigger
    BEFORE INSERT ON watch_history
    FOR EACH ROW
    EXECUTE FUNCTION increment_watch_count();

-- ============================================================================
-- Update trigger for updated_at timestamp (if not exists)
-- ============================================================================

-- Create or replace function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop and recreate triggers
DROP TRIGGER IF EXISTS update_favorites_updated_at ON user_favorites;
CREATE TRIGGER update_favorites_updated_at
    BEFORE UPDATE ON user_favorites
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_history_updated_at ON watch_history;
CREATE TRIGGER update_history_updated_at
    BEFORE UPDATE ON watch_history
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();