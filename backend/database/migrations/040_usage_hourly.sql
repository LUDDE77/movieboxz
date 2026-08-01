-- 040_usage_hourly.sql
-- Hour-of-day usage counts (UTC), so we can see when each market is active.
-- Coarser than usage_daily: only day + hour + event + country (no platform/ref).
-- Still fully anonymous — no user/device id.

CREATE TABLE IF NOT EXISTS usage_hourly (
    day        date     NOT NULL,
    hour       smallint NOT NULL,        -- 0-23, UTC
    event      text     NOT NULL,        -- app_open | movie_view | series_view | search
    country    text     NOT NULL DEFAULT '',
    cnt        bigint   NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (day, hour, event, country)
);
CREATE INDEX IF NOT EXISTS idx_usage_hourly_day ON usage_hourly (day, hour);

CREATE OR REPLACE FUNCTION increment_usage_hourly(
    p_day date, p_hour smallint, p_event text, p_country text, p_delta bigint
) RETURNS void AS $$
    INSERT INTO usage_hourly (day, hour, event, country, cnt, updated_at)
    VALUES (p_day, p_hour, p_event, COALESCE(p_country, ''), p_delta, now())
    ON CONFLICT (day, hour, event, country)
    DO UPDATE SET cnt = usage_hourly.cnt + EXCLUDED.cnt, updated_at = now();
$$ LANGUAGE sql;
