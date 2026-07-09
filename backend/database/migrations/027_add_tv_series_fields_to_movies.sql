-- Migration 027: Add TV series episode fields to movies table
-- Adds season_number, episode_number, and series_type to production movies

ALTER TABLE movies ADD COLUMN IF NOT EXISTS season_number INTEGER;
ALTER TABLE movies ADD COLUMN IF NOT EXISTS episode_number INTEGER;
ALTER TABLE movies ADD COLUMN IF NOT EXISTS series_type TEXT CHECK (series_type IN ('tv_series', 'mini_series'));
