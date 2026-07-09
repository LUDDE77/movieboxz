-- Migration 030: Function hardening
-- Date: 2026-07-09
-- Applied to production via Supabase MCP on 2026-07-09 (migration name: function_hardening).
--
-- Removes PUBLIC execute on the genre RPC (role-specific revokes in 028 did not cover the
-- PUBLIC pseudo-role grant) and pins search_path on all functions flagged by the advisor.

DO $$
DECLARE sig text;
BEGIN
  FOR sig IN
    SELECT p.oid::regprocedure::text FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'update_movie_genres'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', sig);
  END LOOP;

  FOR sig IN
    SELECT p.oid::regprocedure::text FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN (
      'update_updated_at_column','update_movie_search_vector','auto_complete_watch_history',
      'update_series_search_vector','update_series_episode_counts','increment_watch_count',
      'update_movie_groups_updated_at','calculate_title_similarity','find_similar_movie_groups',
      'get_channel_title_pattern','update_channel_patterns_updated_at',
      'update_manual_enrichment_queue_updated_at','update_staged_movies_updated_at',
      'track_staged_movie_changes','update_staged_movie_search_vector',
      'update_channel_settings_updated_at','calculate_import_duration',
      'update_channel_import_stats','apply_channel_tag_to_movies','update_movie_genres'
    )
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public', sig);
  END LOOP;
END $$;
