-- Migration 008: OMDb Enrichment Integration
-- Adds fields for OMDb (IMDB) enrichment as fallback when TMDB fails
-- Date: 2026-01-25

-- =============================================================================
-- 1. Add OMDb/IMDB-specific fields to movies table
-- =============================================================================

-- Track which service enriched each movie
ALTER TABLE movies ADD COLUMN IF NOT EXISTS enrichment_source VARCHAR(20);
COMMENT ON COLUMN movies.enrichment_source IS 'Source of metadata enrichment: tmdb, omdb, manual, or null';

-- IMDB ratings (OMDb provides these)
ALTER TABLE movies ADD COLUMN IF NOT EXISTS imdb_rating DECIMAL(3,1);
COMMENT ON COLUMN movies.imdb_rating IS 'IMDB rating from OMDb API (0.0-10.0)';

ALTER TABLE movies ADD COLUMN IF NOT EXISTS imdb_votes INTEGER;
COMMENT ON COLUMN movies.imdb_votes IS 'Number of IMDB votes from OMDb API';

-- Content rating (PG, PG-13, R, etc.)
ALTER TABLE movies ADD COLUMN IF NOT EXISTS rated VARCHAR(10);
COMMENT ON COLUMN movies.rated IS 'MPAA rating from OMDb API (G, PG, PG-13, R, NC-17, etc.)';

-- Director and actors
ALTER TABLE movies ADD COLUMN IF NOT EXISTS director TEXT;
COMMENT ON COLUMN movies.director IS 'Director name(s) from OMDb API';

ALTER TABLE movies ADD COLUMN IF NOT EXISTS actors TEXT;
COMMENT ON COLUMN movies.actors IS 'Comma-separated actor names from OMDb API';

-- Language and country
ALTER TABLE movies ADD COLUMN IF NOT EXISTS language VARCHAR(255);
COMMENT ON COLUMN movies.language IS 'Language(s) from OMDb API';

ALTER TABLE movies ADD COLUMN IF NOT EXISTS country VARCHAR(255);
COMMENT ON COLUMN movies.country IS 'Country/countries from OMDb API';

-- TV show flag (OMDb detects TV mini-series)
ALTER TABLE movies ADD COLUMN IF NOT EXISTS is_tv_show BOOLEAN DEFAULT FALSE;
COMMENT ON COLUMN movies.is_tv_show IS 'True if OMDb detected this as a TV series/mini-series';

-- =============================================================================
-- 2. Create index on enrichment_source for filtering
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_movies_enrichment_source ON movies(enrichment_source);
CREATE INDEX IF NOT EXISTS idx_movies_imdb_rating ON movies(imdb_rating) WHERE imdb_rating IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_movies_is_tv_show ON movies(is_tv_show);

-- =============================================================================
-- 3. Update existing movies with TMDB enrichment to mark source
-- =============================================================================

-- Mark existing TMDB-enriched movies
UPDATE movies
SET enrichment_source = 'tmdb'
WHERE tmdb_id IS NOT NULL
  AND enrichment_source IS NULL;

-- =============================================================================
-- 4. Add RLS policies for new fields (if RLS is enabled)
-- =============================================================================

-- No additional RLS policies needed - new fields inherit from movies table policies

-- =============================================================================
-- 5. Verification queries (run these to verify migration)
-- =============================================================================

-- Check movies by enrichment source
-- SELECT enrichment_source, COUNT(*) FROM movies GROUP BY enrichment_source;

-- Find movies ready for OMDb enrichment (no TMDB, no OMDb)
-- SELECT COUNT(*) FROM movies WHERE tmdb_id IS NULL AND imdb_id IS NULL;

-- Check IMDB ratings distribution
-- SELECT COUNT(*), AVG(imdb_rating), MIN(imdb_rating), MAX(imdb_rating)
-- FROM movies WHERE imdb_rating IS NOT NULL;
