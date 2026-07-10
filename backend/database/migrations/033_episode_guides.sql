-- Migration 033: Episode guides + episode-matching pipeline support
-- Date: 2026-07-10
--
-- 1. episode_guides: cached season/episode lists per tv_series (fetched from TMDB)
-- 2. staged_movies.series_type: so confirmed episode matches carry series_type
--    through the staging pipeline (movies already has it from migration 027)
-- 3. manual_enrichment_queue: columns used by the verification-queue feeding
--    (low-confidence / no-match enrichments reference their staged_movies row)

-- =============================================================================
-- 1. Episode guides
-- =============================================================================
CREATE TABLE IF NOT EXISTS episode_guides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tv_series_id UUID NOT NULL UNIQUE REFERENCES tv_series(id) ON DELETE CASCADE,
    source VARCHAR(20) NOT NULL,          -- e.g. 'tmdb'
    source_id VARCHAR(40),                -- e.g. TMDB TV show id
    episodes JSONB NOT NULL,              -- [{ "season": 1, "episode": 1, "name": "...", "air_date": "1983-09-05" }, ...]
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE episode_guides IS 'Cached episode guide per TV series, used to fuzzy-match staged YouTube episodes';
COMMENT ON COLUMN episode_guides.episodes IS 'Array of { season, episode, name, air_date } objects';

-- Service-role only: enable RLS with no policies and revoke client access,
-- consistent with migration 028''s lockdown approach (backend uses the service
-- role key, which bypasses RLS).
ALTER TABLE episode_guides ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON episode_guides FROM anon, authenticated;

-- =============================================================================
-- 2. staged_movies.series_type (movies got this in migration 027)
-- =============================================================================
ALTER TABLE staged_movies
    ADD COLUMN IF NOT EXISTS series_type TEXT CHECK (series_type IN ('tv_series', 'mini_series'));

COMMENT ON COLUMN staged_movies.series_type IS 'Type of series when is_tv_series = true; copied to movies on publish';

-- =============================================================================
-- 3. manual_enrichment_queue: verification-queue feeding fields
-- =============================================================================
ALTER TABLE manual_enrichment_queue
    ADD COLUMN IF NOT EXISTS source_table VARCHAR(20) DEFAULT 'staged_movies',
    ADD COLUMN IF NOT EXISTS staged_movie_id UUID REFERENCES staged_movies(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS reason TEXT,
    ADD COLUMN IF NOT EXISTS confidence NUMERIC(5,2),
    ADD COLUMN IF NOT EXISTS candidates JSONB;

COMMENT ON COLUMN manual_enrichment_queue.source_table IS 'Which table the queued movie lives in (currently always staged_movies)';
COMMENT ON COLUMN manual_enrichment_queue.staged_movie_id IS 'FK to the staged_movies row that failed/low-confidence enrichment';
COMMENT ON COLUMN manual_enrichment_queue.reason IS 'Why this row was queued (no match, low confidence, ...)';
COMMENT ON COLUMN manual_enrichment_queue.confidence IS 'Enrichment confidence (0-100) at queue time, if any';
COMMENT ON COLUMN manual_enrichment_queue.candidates IS 'Proposed candidate matches: [{ source, title, release_date, tmdb_id, imdb_id, poster_path }]';

CREATE INDEX IF NOT EXISTS idx_manual_enrichment_staged_movie ON manual_enrichment_queue(staged_movie_id);
