# Database Migrations

This directory contains SQL migration files for the MovieBoxZ database.

## How to Apply Migrations

### Option 1: Via Supabase Dashboard (Recommended)

1. Open your Supabase project dashboard: https://supabase.com/dashboard/project/yilqwcewkiyawtexmrfb
2. Navigate to **SQL Editor** in the left sidebar
3. Click **New query**
4. Copy the contents of each migration file (in order) and run them
5. Verify tables were created by checking **Table Editor**

### Option 2: Via psql Command Line

```bash
# Set your Supabase database URL
export DATABASE_URL="postgresql://postgres.[YOUR-PROJECT-REF]@aws-0-[REGION].pooler.supabase.com:5432/postgres"

# Run migrations in order
psql $DATABASE_URL < backend/database/migrations/007_create_channel_patterns.sql
psql $DATABASE_URL < backend/database/migrations/008_create_manual_enrichment_queue.sql
```

## Migration List

### 007_create_channel_patterns.sql
**Description:** Creates the `channel_patterns` table for storing configurable title extraction patterns for each YouTube channel.

**Tables Created:**
- `channel_patterns` - Stores pattern configurations with regex and parameter mappings

**Includes:**
- Indexes for performance
- Automatic `updated_at` trigger
- Example pattern for "The Midnight Screening" channel

### 008_create_manual_enrichment_queue.sql
**Description:** Creates the `manual_enrichment_queue` table for movies that fail automatic enrichment, allowing manual IMDB matching.

**Tables Created:**
- `manual_enrichment_queue` - Queue for manual enrichment with IMDB/TMDB IDs

**Features:**
- Stores extracted metadata from patterns
- Allows manual IMDB ID assignment
- Tracks enrichment status (pending, matched, skipped, in_progress)
- Includes automatic `updated_at` trigger

## Verify Migrations

After applying migrations, verify they were successful:

### Via Supabase Dashboard
1. Go to **Table Editor**
2. Confirm these tables exist:
   - `channel_patterns`
   - `manual_enrichment_queue`
3. Click on each table to see the schema

### Via SQL
```sql
-- Check if tables exist
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('channel_patterns', 'manual_enrichment_queue');

-- View example pattern for The Midnight Screening
SELECT * FROM channel_patterns WHERE channel_id = 'UC6A_LC-A5NVJ2vw9A0OjCug';
```

## Next Steps

After applying migrations:
1. Backend services will automatically use these tables
2. Channel patterns can be configured via API endpoints
3. Movies that fail auto-enrichment will be added to the manual queue
4. Use the admin API to manually match movies with IMDB IDs
