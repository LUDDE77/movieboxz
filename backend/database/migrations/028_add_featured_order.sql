-- Migration 028: Add featured_order to movies table
-- Allows admin to control which movies appear in the featured carousel (max 5)
-- and in what order they appear.

ALTER TABLE movies ADD COLUMN IF NOT EXISTS featured_order INTEGER;

-- Partial index for fast lookup of ordered featured movies
CREATE INDEX IF NOT EXISTS idx_movies_featured_order
ON movies(featured_order ASC)
WHERE featured = TRUE AND featured_order IS NOT NULL;
