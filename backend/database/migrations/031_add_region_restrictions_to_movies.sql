-- Migration 031: Add region_restrictions to movies
-- Date: 2026-07-09
-- Applied to production via Supabase MCP on 2026-07-09 (migration name: add_region_restrictions_to_movies).
--
-- Region restrictions were collected at import into staged_movies (migration 021)
-- but dropped at publish. This column lets publish carry them through so consumer
-- routes can filter or flag geo-blocked videos.

ALTER TABLE movies ADD COLUMN IF NOT EXISTS region_restrictions JSONB;
