-- Migration 025: Add TV Series support
-- Creates a tv_series table and links staged_movies and movies to it

CREATE TABLE tv_series (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    poster_path TEXT,
    year_start INT,
    year_end INT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE staged_movies ADD COLUMN IF NOT EXISTS tv_series_id UUID REFERENCES tv_series(id) ON DELETE SET NULL;
ALTER TABLE movies ADD COLUMN IF NOT EXISTS tv_series_id UUID REFERENCES tv_series(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_staged_movies_tv_series_id ON staged_movies(tv_series_id);
CREATE INDEX IF NOT EXISTS idx_movies_tv_series_id ON movies(tv_series_id);
