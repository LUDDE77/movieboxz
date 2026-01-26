-- Migration 009: Fix Language and Country Field Sizes
-- The movies table has language VARCHAR(5) and country VARCHAR(5) from base schema
-- Migration 008 tried to ADD these columns, but they already existed
-- This migration expands them to accommodate OMDb full language/country names
-- Date: 2026-01-26

-- =============================================================================
-- 1. Expand existing language and country fields to VARCHAR(255)
-- =============================================================================

-- The movies table currently has:
--   language VARCHAR(5) DEFAULT 'en'  -- Was for ISO codes like 'en', 'es'
--   (no country field in base schema)
--
-- OMDb returns full names like:
--   language: "English, Spanish"
--   country: "United States, United Kingdom"
--
-- We need to expand these to handle full names

ALTER TABLE movies
    ALTER COLUMN language TYPE VARCHAR(255);

-- Remove the default 'en' since OMDb will populate full language names
ALTER TABLE movies
    ALTER COLUMN language DROP DEFAULT;

-- Add country column if it doesn't exist (it wasn't in base schema)
-- This will succeed now since we're not trying to add language
ALTER TABLE movies
    ADD COLUMN IF NOT EXISTS country VARCHAR(255);

COMMENT ON COLUMN movies.language IS 'Full language name(s) from OMDb or TMDB (e.g., "English, Spanish")';
COMMENT ON COLUMN movies.country IS 'Country/countries from OMDb or TMDB (e.g., "United States")';

-- =============================================================================
-- 2. Verification
-- =============================================================================

-- Check that language field is now expanded
-- SELECT column_name, data_type, character_maximum_length
-- FROM information_schema.columns
-- WHERE table_name = 'movies' AND column_name IN ('language', 'country');
