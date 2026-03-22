-- Migration 026: Add atomic genre update RPC
-- Replaces the non-atomic DELETE + INSERT pattern in /api/admin/movies/:id/genres
-- This function runs in a single transaction so partial failures leave no orphaned rows.

CREATE OR REPLACE FUNCTION update_movie_genres(p_movie_id UUID, p_genre_ids INT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Delete existing associations
    DELETE FROM movie_genres WHERE movie_id = p_movie_id;

    -- Insert new associations (no-op if array is empty)
    IF array_length(p_genre_ids, 1) > 0 THEN
        INSERT INTO movie_genres (movie_id, genre_id)
        SELECT p_movie_id, unnest(p_genre_ids);
    END IF;
END;
$$;

COMMENT ON FUNCTION update_movie_genres IS
    'Atomically replace all genre associations for a movie in a single transaction.';
