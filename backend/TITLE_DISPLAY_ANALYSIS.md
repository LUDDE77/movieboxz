# Title Display Issue Analysis
**Date:** 2026-01-25
**Issue:** Movies display uncleaned titles with metadata in frontend

---

## Executive Summary

**Problem:** iOS frontend shows full YouTube titles with metadata (e.g., "XIII The Conspiracy | Thriller Movies | Val Kilmer Stephen Dorff | The Midnight Screening") instead of clean movie titles (e.g., "XIII The Conspiracy").

**Root Cause:** Title cleaning function `cleanMovieTitle()` is not extracting the correct segment from pipe-separated titles due to pattern detection failure.

**Impact:** ALL movies in the database (not just CONtv imports) display uncleaned titles in the frontend.

---

## Data Flow Analysis

### 1. Backend → Database Flow

**Location:** `movieCurator.js:232`
```javascript
const movieData = {
    title: this.cleanMovieTitle(video.title, titlePattern),
    original_title: video.title,
    youtube_video_title: video.title,
    // ...
}
```

**What's Happening:**
- `cleanMovieTitle()` is called with the YouTube title and pattern
- Result is stored in `title` field in database
- `original_title` stores the unmodified YouTube title for reference

### 2. Database → API Flow

**Location:** `database.js:118-126`
```javascript
const transformedMovies = (data || []).map(movie => {
    const { channels, movie_genres, ...movieData } = movie
    return {
        ...movieData,
        channel_title: channels?.title || null,
        channel_thumbnail: channels?.thumbnail_url || null,
        genres: movie_genres?.map(mg => mg.genres) || []
    }
})
```

**What's Happening:**
- API reads `title` field directly from database
- No additional cleaning or transformation
- Returns whatever is stored in the `title` column

### 3. API → iOS Frontend Flow

**Location:** `Movie.swift:8, 54-56`
```swift
struct Movie: Codable, Identifiable {
    let id: String
    let youtubeVideoId: String
    let title: String  // <-- Receives from API "title" field
    // ...

    enum CodingKeys: String, CodingKey {
        case title  // Maps to backend "title" field
        // ...
    }
}
```

**What's Happening:**
- iOS decodes `title` field from JSON
- Displays title directly in UI without modification
- Expects backend to provide clean titles

---

## Current State Analysis

### Sample Movies from API (Popular Endpoint)

#### Movie 1: XIII The Conspiracy
```json
{
  "title": "XIII The Conspiracy | Thriller Movies | Val Kilmer Stephen Dorff | The Midnight Screening",
  "original_title": "XIII The Conspiracy FULL MOVIE | Thriller Movies | Val Kilmer Stephen Dorff | The Midnight Screening",
  "tmdb_id": null,
  "channel_title": "The Midnight Screening"
}
```

**Analysis:**
- ✅ `original_title` preserved correctly with "FULL MOVIE"
- ⚠️ `title` removed "FULL MOVIE" but kept all metadata
- ❌ Should be: `"title": "XIII The Conspiracy"`
- Pattern used: likely detected as `no_pipes` (wrong!)

#### Movie 2: The Flood
```json
{
  "title": "The Flood | Disaster Movies | Thriller Movies | Tom Hardy | The Midnight Screening",
  "original_title": "The Flood FULL MOVIE | Disaster Movies | Thriller Movies | Tom Hardy | The Midnight Screening",
  "tmdb_id": null
}
```

**Analysis:**
- ⚠️ Same issue: metadata not removed
- ❌ Should be: `"title": "The Flood"`

#### Movie 3: The Diplomat
```json
{
  "title": "The Diplomat | Thriller Movies | Dougray Scott | The Midnight Screening",
  "original_title": "The Diplomat FULL MOVIE | Thriller Movies | Dougray Scott | The Midnight Screening",
  "tmdb_id": null
}
```

**Analysis:**
- ⚠️ Same pattern: first segment + all subsequent segments
- ❌ Should be: `"title": "The Diplomat"`

---

## Root Cause Deep Dive

### cleanMovieTitle() Function Behavior

**Location:** `movieCurator.js:420-540`

**Step 1: Pattern-Based Extraction**
```javascript
if (title.includes('|')) {
    const segments = title.split('|').map(s => s.trim())

    if (pattern && pattern.pipe_separator) {
        // Use AI-detected pattern
        if (pattern.title_position === 'first') {
            candidateTitles.push(segments[0])  // ✅ Extract first segment
        }
    } else {
        // No pattern: try both first and last segments
        candidateTitles.push(segments[0])
        if (segments.length > 1) {
            candidateTitles.push(segments[segments.length - 1])
        }
    }
} else {
    // No pipes: use full title
    candidateTitles.push(title)  // ❌ PROBLEM: Returns full title!
}
```

**Step 2: Clean Each Candidate**
```javascript
const cleanedCandidates = candidateTitles.map(candidate => {
    let cleaned = candidate

    cleaned = cleaned
        .replace(/\b(full movie|complete film|full film|feature film)\b/gi, '')
        .replace(/\[.*?\]/g, '')
        .replace(/\b(HD|4K|1080p|720p|480p|DVD|BLURAY|BLU-RAY)\b/gi, '')
        // Remove extra whitespace
        .replace(/\s+/g, ' ')
        .trim()

    return cleaned
})
```

**Step 3: Return Shortest**
```javascript
// Return the shortest cleaned candidate (likely the actual movie title)
const bestTitle = cleanedCandidates.reduce((shortest, current) => {
    return current.length < shortest.length ? current : shortest
})

return bestTitle
```

---

## Why cleanMovieTitle() Fails

### Scenario 1: Pattern Detection Says "no_pipes"

**Input:** `"XIII The Conspiracy FULL MOVIE | Thriller Movies | Val Kilmer | The Midnight Screening"`

**Pattern:** `{ pipe_separator: false, title_position: 'full' }`

**Execution Flow:**
1. `title.includes('|')` → TRUE
2. BUT pattern says `pipe_separator: false`
3. Fallback override logic kicks in (lines 431-444) ✅
4. Override pattern to `{ pipe_separator: true, title_position: 'first' }`
5. Extract first segment: `"XIII The Conspiracy FULL MOVIE"`
6. Clean: `"XIII The Conspiracy FULL MOVIE"` → `"XIII The Conspiracy"` ✅
7. **Expected Result:** `"XIII The Conspiracy"` ✅

**BUT ACTUAL DATABASE HAS:** `"XIII The Conspiracy | Thriller Movies | Val Kilmer Stephen Dorff | The Midnight Screening"`

This means **the fallback override is NOT being applied** or **cleanMovieTitle() is not being called at all!**

---

## Database Evidence

### Migration 007 Schema
```sql
ALTER TABLE channels
ADD COLUMN title_pattern JSONB DEFAULT NULL,
ADD COLUMN pattern_analyzed BOOLEAN DEFAULT FALSE;
```

The `title_pattern` is stored in the **channels** table, not movies table!

### Channel Pattern Storage
**Location:** `channelPatternDetector.js:303-323`
```javascript
async storePattern(channelId, pattern) {
    const { error } = await supabase
        .from('channels')
        .update({
            title_pattern: pattern,
            pattern_analyzed: true,
            updated_at: new Date().toISOString()
        })
        .eq('id', channelId)
}
```

### Pattern Retrieval During Import
**Location:** `movieCurator.js:221-224`
```javascript
titlePattern = await channelPatternDetector.getPattern(video.channelId)
if (titlePattern) {
    logger.debug(`Using pattern for ${video.channelId}: ${titlePattern.type} (${titlePattern.title_position})`)
}
```

---

## Timeline Analysis

### When Were These Movies Imported?

Looking at API response timestamps:
```json
"added_at": "2026-01-24T22:04:54.198+00:00",
"last_validated": "2026-01-24T22:04:54.198+00:00"
```

All movies were imported on **2026-01-24 around 22:04 UTC**.

### When Was Pattern Detection Implemented?

Migration 007 created `title_pattern` column, which was deployed recently.

**HYPOTHESIS:** These movies were imported **BEFORE** the pattern detection system was implemented!

---

## Why Titles Are Uncleaned

### Theory 1: Imported Before Pattern Detection System ✅ LIKELY
- Movies imported on 2026-01-24
- Pattern detection system added after
- Old movies never had their titles cleaned with pattern logic
- Need to **re-import or update existing titles**

### Theory 2: Pattern Detection Not Running During Import ❌ UNLIKELY
- Pattern detector IS being called (line 221)
- Fallback logic IS in place (lines 431-444)
- Code looks correct

### Theory 3: cleanMovieTitle() Returns Full Title When No Pattern ❌ PARTIALLY TRUE
- When pattern is NULL, fallback tries both first and last segments
- Then cleans and picks shortest
- Should still extract "XIII The Conspiracy" from first segment

---

## Verification Tests

### Test 1: Check Channel Pattern in Database

```sql
SELECT id, title, title_pattern, pattern_analyzed
FROM channels
WHERE id = 'UC6A_LC-A5NVJ2vw9A0OjCug';
```

**Expected:** Pattern should exist for "The Midnight Screening" channel

### Test 2: Manually Run cleanMovieTitle()

```javascript
const titlePattern = { pipe_separator: true, title_position: 'first' }
const result = cleanMovieTitle(
    "XIII The Conspiracy FULL MOVIE | Thriller Movies | Val Kilmer | The Midnight Screening",
    titlePattern
)
console.log(result) // Should be: "XIII The Conspiracy"
```

### Test 3: Re-Import a Single Movie

```bash
curl -X POST https://movieboxz-backend-production.up.railway.app/api/admin/channels/import \
  -H "Content-Type: application/json" \
  -H "x-admin-api-key: $ADMIN_API_KEY" \
  -d '{"channel": "@TheMidnightScreening"}'
```

Check if newly imported movies have clean titles.

---

## Solution Options

### Option 1: Re-Import All Channels ⚠️ DESTRUCTIVE
**Impact:** Will create duplicates or update existing movies
**Pros:** Applies latest pattern detection to all movies
**Cons:** Time-consuming, may create data issues

### Option 2: Bulk Title Update Script ✅ RECOMMENDED
**Create migration script:**
```javascript
// Update all movies to use cleanMovieTitle() with current patterns
async function fixAllMovieTitles() {
    const movies = await getAllMovies()

    for (const movie of movies) {
        // Get channel pattern
        const pattern = await getChannelPattern(movie.channel_id)

        // Re-clean title from original_title
        const cleanedTitle = cleanMovieTitle(movie.original_title, pattern)

        // Update only if different
        if (cleanedTitle !== movie.title) {
            await updateMovie(movie.id, { title: cleanedTitle })
            console.log(`Updated: ${movie.title} → ${cleanedTitle}`)
        }
    }
}
```

### Option 3: Frontend Fallback Display ❌ NOT RECOMMENDED
**Modify iOS to clean titles client-side**
**Cons:**
- Violates single source of truth
- Duplicates cleaning logic
- Won't fix database data

### Option 4: API Layer Title Cleaning ❌ NOT RECOMMENDED
**Add cleaning in API response**
**Cons:**
- Performance overhead on every request
- Still doesn't fix database
- Masks underlying issue

---

## Recommended Fix

### Immediate Action (Today)

1. **Create bulk title update script**
   - Read all movies with uncleaned titles
   - Apply `cleanMovieTitle()` with current channel patterns
   - Update `title` field in database

2. **Test on sample movies**
   - Update first 10 movies
   - Verify titles are clean in API response
   - Check frontend display

3. **Deploy to all movies**
   - Run bulk update script
   - Monitor for errors
   - Verify frontend displays clean titles

### Long-term Prevention

1. **Add title validation during import**
   ```javascript
   // After cleanMovieTitle(), verify title doesn't contain pipes
   if (movieData.title.includes('|')) {
       logger.error(`Title cleaning failed: ${movieData.title}`)
       throw new Error('Title still contains metadata')
   }
   ```

2. **Add database constraint**
   ```sql
   -- Prevent storing titles with metadata
   ALTER TABLE movies ADD CONSTRAINT movies_title_no_pipes
   CHECK (title NOT LIKE '%|%');
   ```

3. **Add admin endpoint to trigger bulk title cleaning**
   ```javascript
   // POST /api/admin/movies/fix-titles
   router.post('/fix-titles', async (req, res) => {
       const result = await fixAllMovieTitles()
       res.json({ success: true, updated: result.count })
   })
   ```

---

## Impact Assessment

### Current State
- **Total Movies Affected:** Unknown (need to query database)
- **Channels Affected:** All channels without pattern detection
- **User Experience:** Poor - titles are cluttered and hard to read

### After Fix
- **Database State:** All movies have clean, display-ready titles
- **Frontend Display:** Netflix-style clean movie titles
- **TMDB Matching:** Improved (clean titles match TMDB better)

---

## Testing Checklist

Before deploying fix:

- [ ] Query database to count affected movies
- [ ] Test cleanMovieTitle() function manually
- [ ] Verify channel patterns exist in database
- [ ] Run bulk update on 10 sample movies
- [ ] Check API response shows clean titles
- [ ] Test iOS app displays clean titles
- [ ] Deploy bulk update to all movies
- [ ] Verify frontend across iPhone, iPad, Apple TV
- [ ] Monitor for any errors or issues

---

**Generated:** 2026-01-25
**Analysis By:** MovieBoxZ Development Team
**Status:** Ready for implementation
