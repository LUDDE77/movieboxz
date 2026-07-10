-- Migration 032: Admin Pipeline Hardening
-- Description: Fix live-DB drift on channel_settings classification flags and add
--              import_history metrics columns used by the hardened import pipeline.
-- Date: 2026-07-10
--
-- IMPORTANT: This migration MUST be applied (Supabase SQL editor or CLI) BEFORE
-- deploying the backend changes that write pattern_match_count / truncated.

-- =============================================================================
-- 1. channel_settings classification flags (fixes live-DB drift)
--    These are the flags that actually reach imported movies; the app now keeps
--    them in sync with channels.has_kids_content / channels.has_series.
-- =============================================================================

ALTER TABLE channel_settings
    ADD COLUMN IF NOT EXISTS is_kids_content BOOLEAN DEFAULT false;

ALTER TABLE channel_settings
    ADD COLUMN IF NOT EXISTS is_tv_series_channel BOOLEAN DEFAULT false;

-- =============================================================================
-- 2. import_history metrics
--    pattern_match_count: number of imported rows whose pattern extraction matched
--    truncated: the fetch stopped at the safety cap before exhausting the channel
-- =============================================================================

ALTER TABLE import_history
    ADD COLUMN IF NOT EXISTS pattern_match_count INTEGER;

ALTER TABLE import_history
    ADD COLUMN IF NOT EXISTS truncated BOOLEAN DEFAULT false;

-- =============================================================================
-- 3. import_history.status
--    No schema change needed. status uses the import_status enum from migration
--    012, which already includes 'cancelled' (see migration 012, ENUM definition:
--    'pending', 'running', 'completed', 'failed', 'cancelled'). The real-cancel
--    flow writes status='cancelled', which the existing enum already permits.
-- =============================================================================

COMMENT ON COLUMN import_history.pattern_match_count IS 'Count of imported staged rows where channel-pattern extraction matched (pattern_matched=true)';
COMMENT ON COLUMN import_history.truncated IS 'TRUE when the YouTube fetch stopped at the safety cap (~2000 videos) before exhausting the channel';
COMMENT ON COLUMN channel_settings.is_kids_content IS 'Kept in sync with channels.has_kids_content; this flag reaches imported movies';
COMMENT ON COLUMN channel_settings.is_tv_series_channel IS 'Kept in sync with channels.has_series; this flag reaches imported movies';
