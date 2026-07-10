-- Migration 034: Validation runs — on-demand runs, progress tracking, resurrection
-- Description: Extend validation_runs so on-demand validation runs are trackable
--              (status/progress) and record resurrected movies (dead videos that
--              came back online). All statements are idempotent.
-- Date: 2026-07-10
-- NOTE: Apply manually via the Supabase dashboard SQL editor or CLI.

-- =============================================================================
-- 1. Extend validation_runs
-- =============================================================================

ALTER TABLE validation_runs ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ;
ALTER TABLE validation_runs ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
ALTER TABLE validation_runs ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'completed'; -- 'running', 'completed', 'failed'
ALTER TABLE validation_runs ADD COLUMN IF NOT EXISTS checked INTEGER DEFAULT 0;             -- total movies checked this run
ALTER TABLE validation_runs ADD COLUMN IF NOT EXISTS unavailable_found INTEGER DEFAULT 0;   -- newly-unavailable movies found
ALTER TABLE validation_runs ADD COLUMN IF NOT EXISTS resurrected INTEGER DEFAULT 0;         -- dead movies found alive again
ALTER TABLE validation_runs ADD COLUMN IF NOT EXISTS scope VARCHAR(20);                     -- 'all' or 'channel'
ALTER TABLE validation_runs ADD COLUMN IF NOT EXISTS channel_id VARCHAR(50);                -- set when scope = 'channel'
ALTER TABLE validation_runs ADD COLUMN IF NOT EXISTS triggered_by VARCHAR(20);              -- 'scheduled' or 'manual'
ALTER TABLE validation_runs ADD COLUMN IF NOT EXISTS error_message TEXT;

-- =============================================================================
-- 2. Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_validation_runs_started ON validation_runs(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_validation_runs_status ON validation_runs(status) WHERE status = 'running';

-- =============================================================================
-- 3. Comments
-- =============================================================================

COMMENT ON COLUMN validation_runs.status IS 'running, completed or failed — on-demand runs are trackable while in flight';
COMMENT ON COLUMN validation_runs.resurrected IS 'Movies with is_available=false whose YouTube video was found alive again and re-enabled';
COMMENT ON COLUMN validation_runs.scope IS 'all = whole catalog, channel = single channel (see channel_id)';
COMMENT ON COLUMN validation_runs.triggered_by IS 'scheduled (nightly cron) or manual (admin endpoint)';
