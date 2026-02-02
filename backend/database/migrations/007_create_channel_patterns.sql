-- Migration 007: Create Channel Patterns Table
-- Description: Stores configurable title extraction patterns for each YouTube channel
-- Date: 2026-02-02

-- Create channel_patterns table
CREATE TABLE IF NOT EXISTS channel_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id TEXT NOT NULL UNIQUE REFERENCES channels(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    patterns JSONB NOT NULL DEFAULT '[]'::jsonb,
    fallback_pattern JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_channel_patterns_channel_id ON channel_patterns(channel_id);
CREATE INDEX IF NOT EXISTS idx_channel_patterns_active ON channel_patterns(is_active) WHERE is_active = true;

-- Add comments for documentation
COMMENT ON TABLE channel_patterns IS 'Configurable title extraction patterns for YouTube channels';
COMMENT ON COLUMN channel_patterns.channel_id IS 'YouTube channel ID (references channels table)';
COMMENT ON COLUMN channel_patterns.channel_name IS 'Human-readable channel name';
COMMENT ON COLUMN channel_patterns.patterns IS 'Array of pattern objects with regex and parameter mappings. Example: [{"regex": "^(.+?)\\s*FULL MOVIE", "parameters": {"title": 1, "actors": 2}}]';
COMMENT ON COLUMN channel_patterns.fallback_pattern IS 'Fallback pattern to use when no regex pattern matches';
COMMENT ON COLUMN channel_patterns.is_active IS 'Whether this pattern configuration is currently active';

-- Add trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_channel_patterns_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER channel_patterns_updated_at
    BEFORE UPDATE ON channel_patterns
    FOR EACH ROW
    EXECUTE FUNCTION update_channel_patterns_updated_at();

-- Insert example pattern for The Midnight Screening using dollar-quoting to avoid escaping issues
INSERT INTO channel_patterns (channel_id, channel_name, patterns, fallback_pattern, is_active)
VALUES (
    'UC6A_LC-A5NVJ2vw9A0OjCug',
    'The Midnight Screening',
    $$[
        {
            "regex": "^(.+?)\\s*FULL MOVIE\\s*\\|\\s*(.+?)\\s*Movies?\\s*\\|\\s*(.+?)\\s*\\|\\s*The Midnight Screening$",
            "parameters": {
                "title": 1,
                "genre": 2,
                "actors": 3,
                "channel": "The Midnight Screening"
            }
        },
        {
            "regex": "^(.+?)\\s*\\((\\d{4})\\)\\s*\\|\\s*(.+?)\\s*\\|\\s*(.+?)\\s*\\|\\s*The Midnight Screening$",
            "parameters": {
                "title": 1,
                "year": 2,
                "genre": 3,
                "actors": 4,
                "channel": "The Midnight Screening"
            }
        }
    ]$$::jsonb,
    $${"type": "first_segment", "divider": "|"}$$::jsonb,
    true
)
ON CONFLICT (channel_id) DO UPDATE
SET
    patterns = EXCLUDED.patterns,
    fallback_pattern = EXCLUDED.fallback_pattern,
    updated_at = NOW();

-- Grant permissions (adjust as needed for your setup)
-- GRANT SELECT, INSERT, UPDATE ON channel_patterns TO authenticated;
-- GRANT SELECT ON channel_patterns TO anon;
