-- Migration 035: Genre pipeline — carry enrichment genres through staging to publish
-- Date: 2026-07-10
--
-- Problem: TMDB/OMDB enrichment fetches genres, but staged_movies had nowhere
-- to store them, so the publish step could never populate movie_genres.
-- This adds a JSONB column that captures genres at enrichment time; the
-- publish loop maps entries to genres-table ids (tmdb_id first, then
-- case-insensitive name) and applies them via the update_movie_genres RPC.

ALTER TABLE staged_movies
    ADD COLUMN IF NOT EXISTS genre_data JSONB;

COMMENT ON COLUMN staged_movies.genre_data IS
    'Genres captured at enrichment time: [{"tmdb_id": <int|null>, "name": "<string>"}]. '
    'Mapped to movie_genres rows (via the genres table + update_movie_genres RPC) when the movie is published. '
    'Not a foreign key — unmatchable entries are ignored at publish.';
