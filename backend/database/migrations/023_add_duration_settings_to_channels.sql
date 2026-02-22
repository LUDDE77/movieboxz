-- Migration 023: Add Duration Settings to Channel Settings
-- Description: Add min/max duration filtering per channel
-- Date: 2026-02-22

-- Add duration columns to channel_settings
ALTER TABLE channel_settings
ADD COLUMN IF NOT EXISTS min_duration_minutes INTEGER DEFAULT 35,
ADD COLUMN IF NOT EXISTS max_duration_minutes INTEGER DEFAULT 300;

-- Add comments
COMMENT ON COLUMN channel_settings.min_duration_minutes IS 'Minimum video duration to import (in minutes)';
COMMENT ON COLUMN channel_settings.max_duration_minutes IS 'Maximum video duration to import (in minutes)';

-- Update existing records to have the new default values
UPDATE channel_settings
SET min_duration_minutes = 35,
    max_duration_minutes = 300
WHERE min_duration_minutes IS NULL OR max_duration_minutes IS NULL;
