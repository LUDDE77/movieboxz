-- Migration: Add channel classification and pattern source fields
-- Description: Add flags for content type (movies/series/kids) and pattern extraction source

-- Add content type flags for filtering channels
ALTER TABLE channels
ADD COLUMN IF NOT EXISTS has_movies BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS has_series BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS has_kids_content BOOLEAN DEFAULT false;

COMMENT ON COLUMN channels.has_movies IS 'Channel contains movie content';
COMMENT ON COLUMN channels.has_series IS 'Channel contains TV series/show content';
COMMENT ON COLUMN channels.has_kids_content IS 'Channel contains kids/family content';

-- Add pattern source field to indicate where to extract metadata
ALTER TABLE channels
ADD COLUMN IF NOT EXISTS pattern_source VARCHAR(20) DEFAULT 'title' CHECK (pattern_source IN ('title', 'description'));

COMMENT ON COLUMN channels.pattern_source IS 'Where to apply parsing pattern: title (default) or description. Set to description when title lacks structure but description has metadata.';

-- Create index for filtering by content type
CREATE INDEX IF NOT EXISTS idx_channels_content_type
ON channels(has_movies, has_series, has_kids_content)
WHERE has_movies = true OR has_series = true OR has_kids_content = true;

-- Create index for pattern source
CREATE INDEX IF NOT EXISTS idx_channels_pattern_source
ON channels(pattern_source);
