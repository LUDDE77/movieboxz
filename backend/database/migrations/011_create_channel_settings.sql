-- Migration 011: Create Channel Settings Table
-- Description: Store per-channel import and enrichment configuration
-- Date: 2026-02-08

-- =============================================================================
-- 1. Create channel_settings table
-- =============================================================================

CREATE TABLE IF NOT EXISTS channel_settings (
    channel_id VARCHAR(50) PRIMARY KEY REFERENCES channels(id) ON DELETE CASCADE,

    -- Import settings
    auto_import_enabled BOOLEAN DEFAULT FALSE,
    auto_import_schedule VARCHAR(20) DEFAULT 'manual', -- 'daily', 'weekly', 'manual'
    import_limit INTEGER, -- NULL = all videos, or specific number like 20, 50
    import_sort_order VARCHAR(20) DEFAULT 'latest', -- 'latest', 'oldest', 'alphabetical_az', 'alphabetical_za', 'views', 'rating'

    -- Default enrichment settings
    default_enrichment_priority VARCHAR(20) DEFAULT 'standard', -- 'poster', 'basic', 'standard', 'full'
    auto_enrich_on_import BOOLEAN DEFAULT FALSE,

    -- Default approval settings
    auto_approve_threshold NUMERIC(5,2), -- Auto-approve if confidence > threshold (e.g., 80.00)
    require_manual_review BOOLEAN DEFAULT TRUE,

    -- Filtering/tagging
    channel_tag VARCHAR(50), -- Custom tag for this channel (e.g., 'thriller-classics')
    is_featured BOOLEAN DEFAULT FALSE,
    quality_tier VARCHAR(20) DEFAULT 'standard', -- 'premium', 'standard', 'basic'

    -- Statistics
    last_import_at TIMESTAMPTZ,
    total_imported INTEGER DEFAULT 0,
    total_published INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- 2. Create indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_channel_settings_auto_import ON channel_settings(auto_import_enabled) WHERE auto_import_enabled = TRUE;
CREATE INDEX IF NOT EXISTS idx_channel_settings_featured ON channel_settings(is_featured) WHERE is_featured = TRUE;
CREATE INDEX IF NOT EXISTS idx_channel_settings_tag ON channel_settings(channel_tag) WHERE channel_tag IS NOT NULL;

-- =============================================================================
-- 3. Create trigger for updated_at
-- =============================================================================

CREATE OR REPLACE FUNCTION update_channel_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER channel_settings_updated_at
    BEFORE UPDATE ON channel_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_channel_settings_updated_at();

-- =============================================================================
-- 4. Add comments for documentation
-- =============================================================================

COMMENT ON TABLE channel_settings IS 'Per-channel configuration for imports, enrichment, and approval settings';
COMMENT ON COLUMN channel_settings.auto_import_enabled IS 'Enable automatic imports on schedule';
COMMENT ON COLUMN channel_settings.import_limit IS 'Max videos to import per run (NULL = all)';
COMMENT ON COLUMN channel_settings.import_sort_order IS 'Sort order for imports: latest, oldest, alphabetical_az, alphabetical_za, views, rating';
COMMENT ON COLUMN channel_settings.default_enrichment_priority IS 'Default enrichment level: poster, basic, standard, full';
COMMENT ON COLUMN channel_settings.auto_enrich_on_import IS 'Automatically enrich movies after import';
COMMENT ON COLUMN channel_settings.auto_approve_threshold IS 'Auto-approve movies if enrichment confidence exceeds this percentage';
COMMENT ON COLUMN channel_settings.channel_tag IS 'Custom tag for filtering and organization';
COMMENT ON COLUMN channel_settings.quality_tier IS 'Quality classification: premium, standard, basic';
