-- 038_create_usage_daily.sql
-- Privacy-safe, aggregate consumer usage analytics. No user ids, no device ids,
-- no personal data — only per-day counters of anonymous events (app opens, movie
-- and series detail views, searches), optionally bucketed by platform and country.
-- Populated by the usageTracker middleware, which batches in memory and flushes here.

CREATE TABLE IF NOT EXISTS usage_daily (
    day        date   NOT NULL,
    event      text   NOT NULL,                 -- app_open | movie_view | series_view | search
    platform   text   NOT NULL DEFAULT 'app',   -- ios | tvos | app
    country    text   NOT NULL DEFAULT '',       -- 2-letter, or '' if unknown
    ref_id     text   NOT NULL DEFAULT '',       -- movie/series id, or search term, or ''
    cnt        bigint NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (day, event, platform, country, ref_id)
);

CREATE INDEX IF NOT EXISTS idx_usage_daily_event_day ON usage_daily (event, day);

-- Atomic upsert-increment used by the flusher.
CREATE OR REPLACE FUNCTION increment_usage_daily(
    p_day date, p_event text, p_platform text, p_country text, p_ref_id text, p_delta bigint
) RETURNS void AS $$
    INSERT INTO usage_daily (day, event, platform, country, ref_id, cnt, updated_at)
    VALUES (p_day, p_event, COALESCE(p_platform, 'app'), COALESCE(p_country, ''), COALESCE(p_ref_id, ''), p_delta, now())
    ON CONFLICT (day, event, platform, country, ref_id)
    DO UPDATE SET cnt = usage_daily.cnt + EXCLUDED.cnt, updated_at = now();
$$ LANGUAGE sql;
