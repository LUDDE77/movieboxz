-- Migration 029: Add year_start and year_end to tv_series table
-- These columns were defined in migration 025 but may not have been applied
-- if the table was created from an earlier version of that migration.

ALTER TABLE tv_series ADD COLUMN IF NOT EXISTS year_start INT;
ALTER TABLE tv_series ADD COLUMN IF NOT EXISTS year_end INT;
