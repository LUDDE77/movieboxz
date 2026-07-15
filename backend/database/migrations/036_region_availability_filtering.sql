-- 036 — Per-country availability filtering
--
-- YouTube videos carry regionRestriction (allowed/blocked ISO-3166-1 alpha-2
-- country lists). region_restrictions (jsonb) already captured the raw shape;
-- this projects it into two indexable text[] columns the consumer query path
-- can filter on, and adds a bookkeeping timestamp for resumable backfill /
-- nightly freshness.
--
-- Semantics: NULL/empty region_allowed AND region_blocked = worldwide.
-- Visible in country CC iff:
--   (region_blocked IS NULL OR NOT region_blocked @> ARRAY[CC])
--   AND (region_allowed IS NULL OR region_allowed @> ARRAY[CC])
-- Policy is SHOW-IF-UNKNOWN (a movie with no region data still shows), because
-- YouTube enforces the real block at playback; env REGION_FILTER_HIDE_IF_UNKNOWN
-- flips to hide-if-unknown.

ALTER TABLE movies ADD COLUMN IF NOT EXISTS region_allowed  text[];
ALTER TABLE movies ADD COLUMN IF NOT EXISTS region_blocked  text[];
ALTER TABLE movies ADD COLUMN IF NOT EXISTS region_checked_at timestamptz;

COMMENT ON COLUMN movies.region_blocked IS 'ISO 3166-1 alpha-2 codes where YouTube playback is blocked. NULL/empty = not blocked anywhere.';
COMMENT ON COLUMN movies.region_allowed IS 'ISO 3166-1 alpha-2 codes where playback is allowed (allow-list). NULL/empty = allowed everywhere.';
COMMENT ON COLUMN movies.region_checked_at IS 'When region availability was last fetched from the YouTube API (resumable backfill / freshness).';

-- Project rows already captured in region_restrictions jsonb.
UPDATE movies SET
  region_allowed = CASE WHEN jsonb_typeof(region_restrictions->'allowed') = 'array'
        THEN ARRAY(SELECT jsonb_array_elements_text(region_restrictions->'allowed')) END,
  region_blocked = CASE WHEN jsonb_typeof(region_restrictions->'blocked') = 'array'
        THEN ARRAY(SELECT jsonb_array_elements_text(region_restrictions->'blocked')) END,
  region_checked_at = now()
WHERE region_restrictions IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_movies_region_blocked ON movies USING GIN (region_blocked);
CREATE INDEX IF NOT EXISTS idx_movies_region_allowed ON movies USING GIN (region_allowed);
