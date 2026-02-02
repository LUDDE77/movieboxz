-- Migration 008: Create Manual Enrichment Queue Table
-- Description: Queue for movies that fail automatic enrichment, allowing manual IMDB matching
-- Date: 2026-02-02

-- Create manual_enrichment_queue table
CREATE TABLE IF NOT EXISTS manual_enrichment_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    youtube_video_id TEXT NOT NULL UNIQUE,
    youtube_video_title TEXT NOT NULL,
    channel_id TEXT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    channel_title TEXT NOT NULL,

    -- Extracted metadata (from pattern)
    extracted_title TEXT,
    extracted_actors TEXT[],
    extracted_genre TEXT,
    extracted_year INTEGER,

    -- Raw YouTube data for reference
    description TEXT,
    published_at TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER,
    thumbnail_url TEXT,

    -- Manual enrichment fields
    manual_imdb_id TEXT,           -- User provides this
    manual_tmdb_id INTEGER,         -- Can be looked up from IMDB
    manual_notes TEXT,              -- User can add notes
    enrichment_status TEXT DEFAULT 'pending' CHECK (enrichment_status IN ('pending', 'matched', 'skipped', 'in_progress')),

    -- Tracking
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    processed_at TIMESTAMP WITH TIME ZONE
);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_manual_enrichment_video_id ON manual_enrichment_queue(youtube_video_id);
CREATE INDEX IF NOT EXISTS idx_manual_enrichment_status ON manual_enrichment_queue(enrichment_status);
CREATE INDEX IF NOT EXISTS idx_manual_enrichment_channel ON manual_enrichment_queue(channel_id);
CREATE INDEX IF NOT EXISTS idx_manual_enrichment_created ON manual_enrichment_queue(created_at DESC);

-- Add comments for documentation
COMMENT ON TABLE manual_enrichment_queue IS 'Queue for movies that fail automatic enrichment, allowing manual IMDB/TMDB matching';
COMMENT ON COLUMN manual_enrichment_queue.youtube_video_id IS 'YouTube video ID (unique identifier)';
COMMENT ON COLUMN manual_enrichment_queue.extracted_title IS 'Movie title extracted from YouTube title using channel pattern';
COMMENT ON COLUMN manual_enrichment_queue.extracted_actors IS 'Actor names extracted from YouTube title';
COMMENT ON COLUMN manual_enrichment_queue.extracted_genre IS 'Genre extracted from YouTube title';
COMMENT ON COLUMN manual_enrichment_queue.extracted_year IS 'Release year extracted from YouTube title';
COMMENT ON COLUMN manual_enrichment_queue.manual_imdb_id IS 'IMDB ID manually provided by user (e.g., tt1090903)';
COMMENT ON COLUMN manual_enrichment_queue.manual_tmdb_id IS 'TMDB ID looked up from IMDB ID';
COMMENT ON COLUMN manual_enrichment_queue.enrichment_status IS 'Status: pending (awaiting manual match), matched (IMDB provided), skipped (won''t enrich), in_progress (being processed)';

-- Add trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_manual_enrichment_queue_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER manual_enrichment_queue_updated_at
    BEFORE UPDATE ON manual_enrichment_queue
    FOR EACH ROW
    EXECUTE FUNCTION update_manual_enrichment_queue_updated_at();

-- Grant permissions (adjust as needed for your setup)
-- GRANT SELECT, INSERT, UPDATE ON manual_enrichment_queue TO authenticated;
-- GRANT SELECT ON manual_enrichment_queue TO anon;
