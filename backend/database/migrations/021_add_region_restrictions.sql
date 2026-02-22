-- Migration: Add region restrictions tracking
-- Description: Adds JSONB column to track YouTube video regional availability
-- Created: 2026-02-22

-- Add region_restrictions column to staged_movies
ALTER TABLE staged_movies
ADD COLUMN IF NOT EXISTS region_restrictions JSONB DEFAULT NULL;

-- Add comment explaining the structure
COMMENT ON COLUMN staged_movies.region_restrictions IS 'YouTube regional restrictions: {allowed: [country codes], blocked: [country codes]}. NULL = worldwide, allowed = only these countries, blocked = all except these countries';

-- Create index for querying videos available in specific countries
CREATE INDEX IF NOT EXISTS idx_staged_movies_region_restrictions
ON staged_movies USING GIN (region_restrictions);

-- Example data structure:
-- NULL or {} = available worldwide
-- {"allowed": ["US", "CA", "GB"]} = only available in these countries
-- {"blocked": ["CN", "RU"]} = blocked in these countries, available everywhere else
