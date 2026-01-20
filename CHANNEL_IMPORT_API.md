# YouTube Channel Import API

**Last Updated:** 2025-01-20
**Status:** ✅ Implemented

## Overview

The MovieBoxZ backend now supports dynamic YouTube channel import. You can provide a channel name, ID, or URL, and the backend will automatically:

1. Resolve the identifier to a YouTube channel ID
2. Fetch channel information
3. Scan all videos in the channel
4. Filter for full-length movies (60+ minutes)
5. Enrich with TMDB metadata
6. Automatically categorize by genre
7. Store in the database

All imports run as background jobs with progress tracking.

---

## API Endpoints

### 1. Import a Channel

**Endpoint:** `POST /api/admin/channels/import`

**Authentication:** Requires `X-Admin-API-Key` header

**Request Body:**
```json
{
  "channel": "timeless classic movies"
}
```

**Supported Channel Formats:**
- Channel ID: `UCf0O8RZF2enk6zy4YEUAKsA`
- Channel URL: `https://www.youtube.com/channel/UCf0O8RZF2enk6zy4YEUAKsA`
- Username URL: `https://www.youtube.com/@timelessclassicmovies`
- Channel name: `timeless classic movies`
- Username: `@timelessclassicmovies`

**Response (202 Accepted):**
```json
{
  "success": true,
  "data": {
    "job": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "status": "pending",
      "channelId": "UCf0O8RZF2enk6zy4YEUAKsA",
      "channelTitle": "Timeless Classic Movies",
      "channelUrl": "@timelessclassicmovies",
      "subscriberCount": 125000,
      "videoCount": 450,
      "createdAt": "2025-01-20T10:30:00.000Z"
    }
  },
  "message": "Channel import started: Timeless Classic Movies. Use GET /api/admin/jobs/550e8400-e29b-41d4-a716-446655440000 to check progress."
}
```

**Error Responses:**

*Channel Not Found (404):*
```json
{
  "success": false,
  "error": "Channel Not Found",
  "message": "Could not find YouTube channel: invalid-channel-name",
  "details": "No channel found matching: invalid-channel-name"
}
```

---

### 2. Check Job Status

**Endpoint:** `GET /api/admin/jobs/:jobId`

**Authentication:** Requires `X-Admin-API-Key` header

**Example:** `GET /api/admin/jobs/550e8400-e29b-41d4-a716-446655440000`

**Response:**
```json
{
  "success": true,
  "data": {
    "job": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "type": "channel_scan",
      "status": "running",
      "channelId": "UCf0O8RZF2enk6zy4YEUAKsA",
      "channelTitle": "Timeless Classic Movies",
      "progress": {
        "total": 50,
        "processed": 25,
        "successful": 12,
        "failed": 3,
        "percentage": 50
      },
      "timing": {
        "createdAt": "2025-01-20T10:30:00.000Z",
        "startedAt": "2025-01-20T10:30:05.000Z",
        "completedAt": null,
        "durationSeconds": null
      },
      "results": {
        "channelTitle": "Timeless Classic Movies",
        "channelUrl": "@timelessclassicmovies"
      },
      "errors": []
    }
  },
  "message": "Job status: running"
}
```

**Job Statuses:**
- `pending` - Job created, waiting to start
- `running` - Import in progress
- `completed` - Import finished successfully
- `failed` - Import failed with errors

---

### 3. List All Jobs

**Endpoint:** `GET /api/admin/jobs`

**Authentication:** Requires `X-Admin-API-Key` header

**Query Parameters:**
- `page` (optional) - Page number (default: 1)
- `limit` (optional) - Results per page (default: 20)
- `status` (optional) - Filter by status: `pending`, `running`, `completed`, `failed`
- `jobType` (optional) - Filter by type: `channel_scan`, `movie_validation`, `metadata_update`
- `channelId` (optional) - Filter by channel ID

**Example:** `GET /api/admin/jobs?status=completed&limit=10`

**Response:**
```json
{
  "success": true,
  "data": {
    "jobs": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "type": "channel_scan",
        "status": "completed",
        "channelId": "UCf0O8RZF2enk6zy4YEUAKsA",
        "channelTitle": "Timeless Classic Movies",
        "moviesAdded": 15,
        "moviesFound": 18,
        "createdAt": "2025-01-20T10:30:00.000Z",
        "completedAt": "2025-01-20T10:35:00.000Z"
      }
    ],
    "pagination": {
      "page": 1,
      "limit": 10,
      "total": 1
    }
  },
  "message": "Retrieved 1 jobs"
}
```

---

## Usage Examples

### Using curl

**1. Import a channel by name:**
```bash
curl -X POST https://movieboxz-backend.railway.app/api/admin/channels/import \
  -H "Content-Type: application/json" \
  -H "X-Admin-API-Key: your-admin-key" \
  -d '{"channel": "timeless classic movies"}'
```

**2. Import by YouTube URL:**
```bash
curl -X POST https://movieboxz-backend.railway.app/api/admin/channels/import \
  -H "Content-Type: application/json" \
  -H "X-Admin-API-Key: your-admin-key" \
  -d '{"channel": "https://www.youtube.com/@timelessclassicmovies"}'
```

**3. Check job status:**
```bash
curl https://movieboxz-backend.railway.app/api/admin/jobs/550e8400-e29b-41d4-a716-446655440000 \
  -H "X-Admin-API-Key: your-admin-key"
```

**4. List all completed jobs:**
```bash
curl "https://movieboxz-backend.railway.app/api/admin/jobs?status=completed" \
  -H "X-Admin-API-Key: your-admin-key"
```

---

## How It Works

### Import Process Flow

```
1. User provides channel identifier
   ↓
2. Backend resolves to channel ID
   - If direct ID (UC...) → use as-is
   - If URL → extract ID from URL
   - If name → search YouTube API
   ↓
3. Fetch channel information from YouTube
   ↓
4. Create curation job in database
   ↓
5. Start background import (async)
   ↓
6. For each video in channel:
   a. Check if it's a movie (60+ min duration)
   b. Check keywords ("full movie", etc.)
   c. Verify it's embeddable and public
   d. Skip if already in database
   e. Fetch TMDB metadata
   f. Auto-categorize by genre
   g. Save to database
   ↓
7. Update job progress every 5 videos
   ↓
8. Complete job with results
```

### Movie Filtering Criteria

Videos must meet ALL criteria to be imported:

**Duration:**
- Minimum: 60 minutes
- Maximum: 360 minutes (6 hours)

**Keywords (must have at least one):**
- "full movie"
- "complete film"
- "feature film"
- "classic movie"
- "movie"

**Exclusion Keywords (must have none):**
- "trailer"
- "clip"
- "scene"
- "making of"
- "interview"
- "review"
- "part 1" / "part 2"

**Technical Requirements:**
- Must be public
- Must be embeddable
- Must be fully processed
- Must have at least 1,000 views

### Automatic Categorization

Movies are automatically categorized based on keywords in title/description:

- **Action** - fight, war, battle, combat
- **Comedy** - funny, humor, laugh
- **Drama** - dramatic, emotional, tragedy
- **Horror** - scary, fear, ghost, monster
- **Romance** - love, romantic, heart
- **Thriller** - suspense, mystery, crime
- **Sci-Fi** - space, alien, future
- **Western** - cowboy, frontier
- **Documentary** - true story, real life
- **Animation** - animated, cartoon
- **Classic** - vintage, old, golden age

Default category if no match: **Drama**

### TMDB Enrichment

Each movie is enriched with TMDB data when available:
- Official poster and backdrop images
- Release date and runtime
- IMDb ID and TMDB ID
- Vote average and vote count
- Genre tags
- Cast and crew information

---

## Database Schema

### Curation Jobs Table

```sql
CREATE TABLE curation_jobs (
    id UUID PRIMARY KEY,
    job_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    channel_id VARCHAR(50) REFERENCES channels(id),

    -- Progress tracking
    total_items INTEGER DEFAULT 0,
    processed_items INTEGER DEFAULT 0,
    successful_items INTEGER DEFAULT 0,
    failed_items INTEGER DEFAULT 0,

    -- Timing
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Results
    result_summary JSONB,
    error_log TEXT[],

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

## Configuration

### Environment Variables

```bash
# YouTube API
YOUTUBE_API_KEY=your-youtube-api-key
YOUTUBE_QUOTA_PER_DAY=10000

# TMDB API (for movie metadata enrichment)
TMDB_API_KEY=your-tmdb-api-key

# Movie Filtering
MIN_MOVIE_DURATION_MINUTES=60
MAX_MOVIE_DURATION_MINUTES=360
MIN_VIEW_COUNT=1000

# Admin Authentication
ADMIN_API_KEY=your-secure-admin-key

# Supabase Database
SUPABASE_URL=your-supabase-url
SUPABASE_SERVICE_KEY=your-supabase-service-key
```

### Quota Management

**YouTube Data API v3 Costs:**
- `search.list` - 100 units per call
- `videos.list` - 1 unit per call
- `channels.list` - 1 unit per call

**Default Daily Quota:** 10,000 units

**Typical Channel Import:**
- Resolve channel name: 100 units (if not direct ID)
- Get channel info: 1 unit
- Get 50 videos: 101 units (search + details)
- **Total: ~202 units per channel**

With 10,000 units, you can import approximately **49 channels per day**.

---

## Best Practices

### 1. Channel Selection

✅ **Good Channels:**
- Public domain movie channels
- Classic film archives
- Licensed content distributors
- Official studio classic channels

❌ **Bad Channels:**
- Channels with copyrighted content
- Trailer/clip compilations
- Pirated content
- Non-embeddable videos

### 2. Import Strategy

**Start Small:**
```bash
# Import 1 test channel first
POST /api/admin/channels/import
{ "channel": "Public Domain Movies" }

# Check results
GET /api/admin/jobs/{jobId}

# Review imported movies
GET /api/movies?channelId={channelId}
```

**Scale Up:**
```bash
# Import multiple channels sequentially
# Wait for each job to complete before starting next
```

### 3. Monitoring

**Check job status regularly:**
```bash
# View all running jobs
GET /api/admin/jobs?status=running

# View all failed jobs
GET /api/admin/jobs?status=failed
```

**Review API quota usage:**
```bash
# Check quota from YouTube Service
# (Implementation would track this in api_usage table)
```

---

## Troubleshooting

### Problem: Channel Not Found

**Symptoms:**
```json
{
  "success": false,
  "error": "Channel Not Found",
  "message": "Could not find YouTube channel: ..."
}
```

**Solutions:**
1. Try using the direct channel URL from YouTube
2. Ensure the channel is public
3. Check for typos in channel name
4. Use channel ID if available (format: `UC...`)

### Problem: No Movies Found

**Symptoms:** Job completes but `moviesAdded: 0`

**Possible Causes:**
1. Channel has no videos meeting duration requirement (60+ min)
2. Videos don't have movie keywords in title/description
3. Videos are not embeddable
4. Videos are not public
5. All videos already imported

**Solutions:**
- Check `moviesFound` vs `moviesAdded` in job results
- Review `errors` array in job details
- Verify channel actually has full movies
- Check video durations on YouTube

### Problem: Import Stuck in "pending"

**Symptoms:** Job status remains "pending" for long time

**Solutions:**
1. Check backend logs for errors
2. Verify background job processing is working
3. Check YouTube API quota hasn't been exceeded
4. Restart backend server if needed

### Problem: High Failure Rate

**Symptoms:** Many videos in `failed_items`

**Possible Causes:**
1. TMDB enrichment failing (non-critical, movies still imported)
2. Database connection issues
3. Invalid video data

**Solutions:**
- Check `error_log` array in job details
- Review backend logs
- Consider reducing batch size

---

## Future Enhancements

### Planned Features

**1. Bulk Channel Import:**
```json
POST /api/admin/channels/import/bulk
{
  "channels": [
    "timeless classic movies",
    "classic cinema",
    "public domain movies"
  ]
}
```

**2. Scheduled Refreshes:**
- Automatically re-scan channels weekly
- Update movie statistics
- Find newly uploaded content

**3. Smart Recommendations:**
- Suggest similar channels
- Find channels based on imported movies
- Auto-discover public domain sources

**4. Import Presets:**
```json
POST /api/admin/channels/import
{
  "channel": "classic horror",
  "preset": "horror-only",
  "minYear": 1920,
  "maxYear": 1980
}
```

**5. Webhook Notifications:**
- Notify when imports complete
- Alert on errors
- Send daily summaries

---

## Support

For issues or questions:

1. Check backend logs: `/var/log/movieboxz/backend.log`
2. Review job details: `GET /api/admin/jobs/{jobId}`
3. Check Railway deployment logs
4. Open issue in MovieBoxZ repository

---

## Summary

**You can now:**
✅ Import YouTube channels by name, URL, or ID
✅ Automatically discover and import movies
✅ Track import progress with job system
✅ Filter for full-length movies only
✅ Enrich with TMDB metadata
✅ Auto-categorize by genre
✅ View import history and results

**Example Workflow:**
```bash
# 1. Import a channel
curl -X POST /api/admin/channels/import \
  -H "X-Admin-API-Key: $ADMIN_KEY" \
  -d '{"channel": "timeless classic movies"}'

# Response: { "data": { "job": { "id": "abc123" } } }

# 2. Check progress
curl /api/admin/jobs/abc123 \
  -H "X-Admin-API-Key: $ADMIN_KEY"

# 3. View imported movies
curl /api/movies?channelId=UCf0O8RZF2enk6zy4YEUAKsA

# Done! 🎬
```

---

*Last Updated: 2025-01-20*
*API Version: 1.0*
