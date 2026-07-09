-- Migration 028: Enable RLS and revoke anon/authenticated write access
-- Date: 2026-07-09
-- Applied to production via Supabase MCP on 2026-07-09 (migration name: enable_rls_lockdown).
--
-- Catalog tables stay publicly readable; pipeline/admin tables become invisible to clients.
-- The backend API uses the service role key, which bypasses RLS, so it is unaffected.

-- 1. Enable RLS on all tables that lacked it
ALTER TABLE api_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE collection_movies ENABLE ROW LEVEL SECURITY;
ALTER TABLE curation_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE genres ENABLE ROW LEVEL SECURITY;
ALTER TABLE import_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE manual_enrichment_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE movie_collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE movie_genres ENABLE ROW LEVEL SECURITY;
ALTER TABLE movie_people ENABLE ROW LEVEL SECURITY;
ALTER TABLE movies ENABLE ROW LEVEL SECURITY;
ALTER TABLE staged_movies ENABLE ROW LEVEL SECURITY;

-- 2. Ensure public read policies exist on consumer catalog tables
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['movies','channels','genres','movie_genres','movie_people','movie_collections','collection_movies'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = t AND cmd = 'SELECT'
    ) THEN
      EXECUTE format('CREATE POLICY "Public read access" ON %I FOR SELECT USING (true)', t);
    END IF;
  END LOOP;
END $$;

-- 3. Revoke write access from client roles (user-owned tables keep their RLS-scoped access)
DO $$
DECLARE t text;
BEGIN
  FOR t IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename NOT IN ('user_profiles','user_favorites','user_watchlist','watch_history')
  LOOP
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON %I FROM anon, authenticated', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['user_profiles','user_favorites','user_watchlist','watch_history'] LOOP
    EXECUTE format('REVOKE TRUNCATE ON %I FROM anon, authenticated', t);
  END LOOP;
END $$;

-- 4. Pipeline/admin tables: no client reads either (defense in depth on top of RLS)
REVOKE SELECT ON staged_movies, channel_patterns, channel_settings, import_history,
  manual_enrichment_queue, curation_jobs, api_usage FROM anon, authenticated;

-- 5. Lock down the genre RPC (backend calls it with the service role)
DO $$
DECLARE sig text;
BEGIN
  FOR sig IN
    SELECT p.oid::regprocedure::text FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'update_movie_genres'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon, authenticated', sig);
  END LOOP;
END $$;

-- 6. Views must run with the caller's permissions, not the owner's
ALTER VIEW channel_import_stats SET (security_invoker = true);
ALTER VIEW channel_movies_overview SET (security_invoker = true);
ALTER VIEW import_history_with_channel SET (security_invoker = true);
ALTER VIEW movies_pending_validation SET (security_invoker = true);
ALTER VIEW movies_with_backup_info SET (security_invoker = true);
ALTER VIEW movies_with_import_info SET (security_invoker = true);
ALTER VIEW staged_movies_enriched SET (security_invoker = true);
ALTER VIEW staged_movies_pattern_extraction SET (security_invoker = true);
ALTER VIEW staged_movies_pending SET (security_invoker = true);
ALTER VIEW staged_movies_unenriched SET (security_invoker = true);
ALTER VIEW staged_movies_with_import_info SET (security_invoker = true);
