-- 039_smart_search.sql
-- Best-in-class search: relevance ranking (Phase 1), director + genre matching
-- (Phase 2), typo/fuzzy tolerance via trigrams (Phase 3), and a minimum-relevance
-- threshold so weak matches return nothing instead of junk (Phase 4).

-- Phase 3: fuzzy matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_movies_title_trgm ON movies USING gin (lower(title) gin_trgm_ops);

-- search_movies(query, country, limit, offset) -> ranked movie rows.
CREATE OR REPLACE FUNCTION search_movies(
    p_query   text,
    p_country text DEFAULT NULL,
    p_limit   int  DEFAULT 20,
    p_offset  int  DEFAULT 0
)
RETURNS SETOF movies
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_raw    text := trim(coalesce(p_query, ''));
    v_words  text[];
    v_prefix text;
    v_tsq    tsquery := NULL;
    v_cc     text := CASE WHEN p_query IS NOT NULL AND p_country ~ '^[A-Za-z]{2}$' THEN upper(p_country) ELSE NULL END;
BEGIN
    IF v_raw = '' THEN RETURN; END IF;

    -- Normalise to words and build a prefix tsquery: "spider man" -> 'spider:* & man:*'
    v_words := regexp_split_to_array(lower(regexp_replace(v_raw, '[^a-z0-9 ]', ' ', 'gi')), '\s+');
    SELECT string_agg(w || ':*', ' & ') INTO v_prefix FROM unnest(v_words) w WHERE length(w) > 0;
    IF v_prefix IS NOT NULL AND v_prefix <> '' THEN
        BEGIN
            v_tsq := to_tsquery('english', v_prefix);
        EXCEPTION WHEN others THEN
            v_tsq := NULL;
        END;
    END IF;

    RETURN QUERY
    WITH ranked AS (
        SELECT m.id,
            (
                -- Phase 1: full-text relevance (title>orig>description>actors via search_vector)
                COALESCE(CASE WHEN v_tsq IS NOT NULL THEN ts_rank(m.search_vector, v_tsq) END, 0) * 4
                -- Phase 2: director + genre
                + CASE WHEN m.director ILIKE '%' || v_raw || '%' THEN 0.6 ELSE 0 END
                + CASE WHEN EXISTS (
                        SELECT 1 FROM movie_genres mg JOIN genres g ON g.id = mg.genre_id
                        WHERE mg.movie_id = m.id AND g.name ILIKE '%' || v_raw || '%'
                    ) THEN 0.5 ELSE 0 END
                -- Phase 3: fuzzy title similarity (typos, hyphen variants)
                + similarity(lower(m.title), lower(v_raw)) * 2
            ) AS score
        FROM movies m
        WHERE (m.is_available IS NULL OR m.is_available = true)
          AND (
                (v_tsq IS NOT NULL AND m.search_vector @@ v_tsq)
                OR m.director ILIKE '%' || v_raw || '%'
                OR EXISTS (SELECT 1 FROM movie_genres mg JOIN genres g ON g.id = mg.genre_id
                           WHERE mg.movie_id = m.id AND g.name ILIKE '%' || v_raw || '%')
                OR lower(m.title) % lower(v_raw)
          )
          AND (
                v_cc IS NULL OR (
                    (m.region_blocked IS NULL OR NOT (m.region_blocked @> ARRAY[v_cc]))
                    AND (m.region_allowed IS NULL OR m.region_allowed @> ARRAY[v_cc])
                )
          )
    )
    SELECT m.*
    FROM ranked r
    JOIN movies m ON m.id = r.id
    WHERE r.score > 0.12   -- Phase 4: below this = not a real match -> empty, not junk
    ORDER BY r.score DESC, m.view_count DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset;
END;
$$;
