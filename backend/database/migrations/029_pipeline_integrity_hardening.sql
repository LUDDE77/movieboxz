-- Migration 029: Pipeline integrity hardening
-- Date: 2026-07-09
-- Applied to production via Supabase MCP on 2026-07-09 (migration name: pipeline_integrity_hardening).
--
-- Duplicate protection, orphan backfill, hot-path indexes, episode integrity.

-- Document the enum values that were added by hand and never committed as a migration
ALTER TYPE approval_status ADD VALUE IF NOT EXISTS 'publishing';
ALTER TYPE approval_status ADD VALUE IF NOT EXISTS 'published';

-- One staged row per YouTube video across the whole lifecycle (rejected rows exempt).
-- Replaces the old pending-only partial index that let re-imports duplicate approved/published rows.
DROP INDEX IF EXISTS idx_staged_movies_unique_video;
CREATE UNIQUE INDEX idx_staged_movies_unique_video
  ON staged_movies(youtube_video_id)
  WHERE approval_status <> 'rejected';

-- Backfill provenance on published staged rows that lost their link to the production movie
UPDATE staged_movies sm
SET published_movie_id = m.id
FROM movies m
WHERE sm.approval_status = 'published'
  AND sm.published_movie_id IS NULL
  AND m.youtube_video_id = sm.youtube_video_id;

-- Indexes for the two default consumer sorts (popular = view_count, recent = published_at)
CREATE INDEX IF NOT EXISTS idx_movies_view_count
  ON movies(view_count DESC) WHERE is_available = true;
CREATE INDEX IF NOT EXISTS idx_movies_published_at
  ON movies(published_at DESC) WHERE is_available = true;

-- An episode row must belong to a series
ALTER TABLE movies ADD CONSTRAINT movies_episode_requires_series
  CHECK (season_number IS NULL OR tv_series_id IS NOT NULL);
