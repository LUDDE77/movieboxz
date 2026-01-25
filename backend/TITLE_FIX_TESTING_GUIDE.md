# Title Fix Testing Guide
**Date:** 2026-01-25

---

## Changes Made

### 1. Created Title Fixer Script
**File:** `backend/src/scripts/fixMovieTitles.js`

Bulk title cleaning script that:
- Re-runs `cleanMovieTitle()` on all movies using `original_title`
- Uses current channel patterns from database
- Updates `title` field in database with clean titles
- Supports dry-run mode for testing
- Can filter by channel or limit number of movies

### 2. Added Admin Endpoints
**File:** `backend/src/routes/admin.js`

**Bulk Fix Endpoint:**
```
POST /api/admin/movies/fix-titles
Body: {
  "dryRun": false,      // Preview changes without applying (default: false)
  "limit": 10,          // Limit number of movies to process (optional)
  "channelId": "UC..."  // Only fix specific channel (optional)
}
```

**Single Movie Fix Endpoint:**
```
POST /api/admin/movies/:movieId/fix-title
```

### 3. Created Analysis Documentation
- `TITLE_DISPLAY_ANALYSIS.md` - Comprehensive issue analysis
- `CONTV_IMPORT_ANALYSIS.md` - CONtv import analysis
- `FAILED_IMPORTS_MANUAL_REVIEW.md` - Manual review file with IMDB data

---

## Deployment Steps

### Step 1: Push to GitHub (Manual)
```bash
cd /Users/mrahl/movieboxz
git push origin main
```

Wait for Railway auto-deployment to complete (check Railway dashboard).

### Step 2: Test with Dry Run (10 Movies)
```bash
curl -X POST https://movieboxz-backend-production.up.railway.app/api/admin/movies/fix-titles \
  -H "Content-Type: application/json" \
  -H "x-admin-api-key: ec0b5a7e29843665384070f90a9b873f04c63b06b0b0a26269a166a05db7daa9" \
  -d '{
    "dryRun": true,
    "limit": 10
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "data": {
    "total": 10,
    "updated": 10,
    "unchanged": 0,
    "failed": 0,
    "changes": [
      {
        "id": "fdb65b8b-267b-4fbb-8f06-4d1aac3a25b8",
        "oldTitle": "XIII The Conspiracy | Thriller Movies | Val Kilmer Stephen Dorff | The Midnight Screening",
        "newTitle": "XIII The Conspiracy"
      },
      // ... more changes
    ]
  },
  "message": "Dry run completed: 10 titles would be updated"
}
```

### Step 3: Apply Fix to 10 Movies
```bash
curl -X POST https://movieboxz-backend-production.up.railway.app/api/admin/movies/fix-titles \
  -H "Content-Type: application/json" \
  -H "x-admin-api-key: ec0b5a7e29843665384070f90a9b873f04c63b06b0b0a26269a166a05db7daa9" \
  -d '{
    "dryRun": false,
    "limit": 10
  }'
```

### Step 4: Verify in API
```bash
curl -s "https://movieboxz-backend-production.up.railway.app/api/movies/popular?page=1&limit=5" | jq '.data.movies[] | {id, title, original_title}'
```

**Expected:** Clean titles without metadata
```json
{
  "id": "fdb65b8b-267b-4fbb-8f06-4d1aac3a25b8",
  "title": "XIII The Conspiracy",
  "original_title": "XIII The Conspiracy FULL MOVIE | Thriller Movies | Val Kilmer Stephen Dorff | The Midnight Screening"
}
```

### Step 5: Test in iOS App
1. Open MovieBoxZ app on iPhone/iPad/Apple TV
2. Browse to popular movies
3. **Verify:** Titles display clean without metadata
4. **Before:** "XIII The Conspiracy | Thriller Movies | Val Kilmer Stephen Dorff | The Midnight Screening"
5. **After:** "XIII The Conspiracy"

### Step 6: Apply to ALL Movies
```bash
curl -X POST https://movieboxz-backend-production.up.railway.app/api/admin/movies/fix-titles \
  -H "Content-Type: application/json" \
  -H "x-admin-api-key: ec0b5a7e29843665384070f90a9b873f04c63b06b0b0a26269a166a05db7daa9" \
  -d '{
    "dryRun": false
  }'
```

**This will process ALL movies** - may take several minutes depending on database size.

---

## Verification Checklist

- [ ] Pushed code to GitHub
- [ ] Railway deployment completed successfully
- [ ] Ran dry-run on 10 movies - verified changes look correct
- [ ] Applied fix to 10 movies - verified no errors
- [ ] Checked API response - titles are clean
- [ ] Tested iOS app - titles display correctly
- [ ] Applied fix to all movies
- [ ] Verified frontend across iPhone, iPad, Apple TV
- [ ] No errors in Railway logs

---

## Rollback Plan

If something goes wrong:

### Option 1: Restore from original_title
```bash
# Restore all titles from original_title field
curl -X POST https://movieboxz-backend-production.up.railway.app/api/admin/movies/restore-titles \
  -H "x-admin-api-key: $ADMIN_API_KEY"
```
(Note: This endpoint would need to be created if rollback is needed)

### Option 2: Database Rollback
```sql
-- Restore all titles from original_title
UPDATE movies
SET title = original_title,
    updated_at = NOW()
WHERE title != original_title;
```

---

## Expected Results

### Before Fix
**API Response:**
```json
{
  "title": "XIII The Conspiracy | Thriller Movies | Val Kilmer Stephen Dorff | The Midnight Screening"
}
```

**iOS Display:**
```
XIII The Conspiracy | Thriller Movies | Val Kilmer Stephen Dorff | The Midnight Screening
```

### After Fix
**API Response:**
```json
{
  "title": "XIII The Conspiracy"
}
```

**iOS Display:**
```
XIII The Conspiracy
```

---

## Troubleshooting

### Issue: No changes detected in dry-run
**Cause:** Titles may already be clean OR pattern detection is failing
**Solution:** Check a specific movie's title in database manually

### Issue: Some titles still have metadata
**Cause:** Pattern detection may be incorrect for that channel
**Solution:**
1. Manually fix specific channel's pattern
2. Re-run fix for that channel only:
```bash
curl -X POST ... -d '{
  "channelId": "UC6A_LC-A5NVJ2vw9A0OjCug"
}'
```

### Issue: Titles are blank after fix
**Cause:** `cleanMovieTitle()` may be removing too much
**Solution:** Restore from `original_title` and debug `cleanMovieTitle()` logic

---

## Monitoring

After applying fix to all movies, monitor:

1. **Railway Logs:**
   - Check for any errors during bulk update
   - Verify all movies processed successfully

2. **API Response Times:**
   - Should not be affected (fix only updates database once)

3. **User Feedback:**
   - Check if titles display correctly in app
   - Verify no broken layouts due to shorter titles

---

## Success Metrics

- ✅ All movies have clean titles without metadata
- ✅ Titles match format: "Movie Title" or "Movie Title (Year)"
- ✅ No pipes (|) in title field
- ✅ Frontend displays clean, professional titles
- ✅ No errors during bulk update process

---

**Created:** 2026-01-25
**Status:** Ready for deployment and testing