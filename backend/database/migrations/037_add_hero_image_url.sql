-- 037_add_hero_image_url.sql
-- Hero Builder: let admins curate which image is shown for a movie in the
-- featured hero carousel. When hero_image_url is set, the iOS/tvOS hero uses
-- it directly (shown sharp/full-bleed); when NULL the app falls back to the
-- TMDB backdrop, then to a blurred ambient poster.

ALTER TABLE movies
    ADD COLUMN IF NOT EXISTS hero_image_url TEXT;

COMMENT ON COLUMN movies.hero_image_url IS
    'Admin-curated hero image (full URL) for the featured carousel. NULL = auto (backdrop, then blurred poster).';
