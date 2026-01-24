# Database Migrations

This directory contains SQL migration files for the MovieBoxZ database.

## Migration Files

- `001_add_tv_series_support.sql` - ✅ Applied - Adds TV series, seasons, episodes tables
- `002_add_youtube_compliance_fields.sql` - ⏳ **PENDING** - Adds YouTube TOS compliance fields

## How to Apply Migrations

### Option 1: Supabase SQL Editor (Recommended)

1. Go to your Supabase project: https://supabase.com/dashboard/project/qkzbhtzfnlhzyvhpcpyo
2. Navigate to **SQL Editor** (left sidebar)
3. Click **New Query**
4. Copy the contents of the migration file
5. Paste into the SQL editor
6. Click **Run** (or press Cmd/Ctrl + Enter)
7. Verify success message

### Option 2: CLI (If you have psql installed)

```bash
# Connect to Supabase database
psql "postgresql://postgres:[YOUR-PASSWORD]@db.qkzbhtzfnlhzyvhpcpyo.supabase.co:5432/postgres"

# Run migration
\i backend/database/migrations/002_add_youtube_compliance_fields.sql
```

### Option 3: Automated Script (Work in Progress)

```bash
cd backend
node scripts/apply-migrations.js 002
```

## Applying Migration 002 (YouTube TOS Compliance)

**⚠️ CRITICAL**: This migration is required for YouTube Terms of Service compliance.

### What it does:
- Adds `youtube_video_title` column (stores original YouTube API title)
- Adds `channel_thumbnail` column (channel profile image)
- Adds `last_refreshed` column (cache management timestamp)
- Creates index on `last_refreshed` for efficient queries
- Migrates existing data (copies `title` to `youtube_video_title`)

### Impact:
- ✅ Backward compatible (uses DEFAULT values)
- ✅ No downtime required
- ✅ Existing queries continue to work
- ⏱ Execution time: ~1-2 seconds

### To apply:

1. **Open Supabase SQL Editor**:
   - https://supabase.com/dashboard/project/qkzbhtzfnlhzyvhpcpyo/sql

2. **Copy migration SQL** from:
   - `backend/database/migrations/002_add_youtube_compliance_fields.sql`

3. **Run in SQL Editor**

4. **Verify**:
   ```sql
   -- Check new columns exist
   SELECT column_name, data_type, is_nullable
   FROM information_schema.columns
   WHERE table_name = 'movies'
   AND column_name IN ('youtube_video_title', 'channel_thumbnail', 'last_refreshed');

   -- Should return 3 rows
   ```

5. **Check data migration**:
   ```sql
   -- All movies should have youtube_video_title populated
   SELECT COUNT(*) as total,
          COUNT(youtube_video_title) FILTER (WHERE youtube_video_title != '') as populated
   FROM movies;
   ```

## Migration Best Practices

1. **Always backup** before running migrations (Supabase has automatic backups)
2. **Test locally** if possible (use a development project)
3. **Read the migration** before executing
4. **Run during low traffic** for large schema changes
5. **Verify after execution** using provided verification queries

## Rollback

If you need to rollback migration 002:

```sql
-- Remove columns
ALTER TABLE movies
    DROP COLUMN IF EXISTS youtube_video_title,
    DROP COLUMN IF EXISTS channel_thumbnail,
    DROP COLUMN IF EXISTS last_refreshed;

-- Drop index
DROP INDEX IF EXISTS idx_movies_last_refreshed;
```

⚠️ **Warning**: Rollback will delete all data in these columns.

## Support

For migration issues:
- Check Supabase logs in dashboard
- Review error messages carefully
- Consult `BACKEND_UPDATE.md` for context
