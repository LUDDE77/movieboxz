# Staging Workflow - Implementation Plan

## Problem Analysis

### Current Issues
1. **Import skips all videos** (0 imported, 25 skipped)
   - Root cause: Videos already exist in production `movies` table
   - Import code only checks `staged_movies`, not `movies`
   - Insert fails silently due to unique constraint on `youtube_video_id`

2. **No enrichment UI visible**
   - Can't enrich because no movies in staging
   - Need to fix import first

3. **UX confusion**
   - Channel selection exists but workflow unclear
   - Need better visual hierarchy

---

## Solution: Two-Phase Approach

### Phase 1: Fix Backend Import Logic ✅ DO FIRST

**File:** `backend/src/routes/staging-simple.js`

**Changes needed:**

```javascript
// Add TWO duplicate checks:

// 1. Check if already in staging
const { data: inStaging } = await supabase
    .from('staged_movies')
    .select('id')
    .eq('youtube_video_id', video.id)
    .single()

if (inStaging) {
    skipped++
    continue
}

// 2. Check if already published to production
const { data: inProduction } = await supabase
    .from('movies')
    .select('id')
    .eq('youtube_video_id', video.id)
    .single()

if (inProduction) {
    skipped++
    logger.info(`Skipping ${video.title} - already in production`)
    continue
}
```

**Add import option:**
- `reimportPublished: boolean` - Allow re-importing movies that are already in production for re-enrichment

---

### Phase 2: Improve UX Workflow

## Complete Workflow Design

### 1️⃣ IMPORT TAB (Primary Action)

**Location:** Top of sidebar in Staging view

**UI Layout:**
```
┌─────────────────────────────────────┐
│ 📥 IMPORT FROM YOUTUBE              │
├─────────────────────────────────────┤
│ Channel: [Dropdown ▼]               │
│ • The Midnight Screening            │
│ • Cultmov Ent.                      │
│ • Public Domain Movies              │
│ • [All 8 channels]                  │
├─────────────────────────────────────┤
│ How many: [10  ] videos             │
│ ☐ Skip videos already published     │
│ ☐ Only import unenriched            │
├─────────────────────────────────────┤
│        [Import to Staging]          │
└─────────────────────────────────────┘
```

**What happens:**
- Fetches videos from selected channel
- Adds to `staged_movies` table with `approval_status: 'pending'`
- Shows: "Imported 10 movies, skipped 5"

---

### 2️⃣ MOVIE LIST (Review & Filter)

**Location:** Below import form

**Filter Tabs:**
```
[Pending: 25] [Enriched: 10] [Unenriched: 15]
```

**Movie Card:**
```
┌─────────────────────────────────────┐
│ [Poster]  The Conspiracy (2013)     │
│           ⚠️  Missing: poster, IMDB  │
│           ⏱️  84 min                  │
│           Status: Pending Review     │
└─────────────────────────────────────┘
```

**Click on movie** → Shows detail panel

---

### 3️⃣ DETAIL PANEL (Enrichment & Editing)

**Location:** Right side when movie selected

#### Section A: Movie Info (Top)
```
┌─────────────────────────────────────┐
│ [Large Poster]                      │
│ The Conspiracy                      │
│ YouTube: "The Conspiracy (2013)..." │
│ Duration: 84 min                    │
│ Views: 45M | Likes: 139K            │
└─────────────────────────────────────┘
```

#### Section B: Enrichment Controls
```
┌─────────────────────────────────────┐
│ 🎬 ENRICHMENT                        │
├─────────────────────────────────────┤
│ Priority: [Full Enrichment ▼]       │
│ • Poster Only                       │
│ • Basic (Poster + Genres)           │
│ • Standard (+ Plot & Date)          │
│ • Full (Everything)                 │
├─────────────────────────────────────┤
│ [Preview Enrichment] [Apply Now]    │
└─────────────────────────────────────┘
```

**Preview Mode:**
- Shows WHAT WILL BE ADDED without saving
- Displays confidence score
- Shows source (TMDB/OMDB)

**Apply Mode:**
- Actually saves enrichment to database
- Updates movie with metadata

#### Section C: Current Metadata
```
┌─────────────────────────────────────┐
│ 📝 METADATA                          │
├─────────────────────────────────────┤
│ TMDB ID: [    ] [Edit]              │
│ IMDB ID: [tt2330322] ✅             │
│ Poster:  [/path.jpg] ✅             │
│ Plot:    [A documentary about...] ✅│
│ Director: [Christopher MacBride]    │
│ Genre:   [Horror, Thriller]         │
├─────────────────────────────────────┤
│ Enrichment: 75% complete            │
│ Source: OMDB + Manual               │
└─────────────────────────────────────┘
```

**Click [Edit]** → Inline editing, auto-saves

#### Section D: Approval Actions (Bottom)
```
┌─────────────────────────────────────┐
│ [✅ Approve] [❌ Reject] [Delete]    │
└─────────────────────────────────────┘
```

---

### 4️⃣ PUBLISH TAB (Final Step)

**Location:** Bottom of sidebar

```
┌─────────────────────────────────────┐
│ 📤 PUBLISH TO PRODUCTION            │
├─────────────────────────────────────┤
│ ✅ 15 movies approved and ready     │
│                                     │
│ [Publish All Approved]              │
│ [Select Specific Movies...]         │
└─────────────────────────────────────┘
```

**What happens:**
- Moves approved movies from `staged_movies` → `movies`
- Marks as published with `published_movie_id`
- Can't be re-published (one-way operation)

---

## Complete User Journey

### Scenario: Import & Enrich 10 Movies

1. **Open Admin App** → Click "Staging" tab

2. **Import:**
   - Select "The Midnight Screening" channel
   - Enter "10" for limit
   - Click "Import to Staging"
   - See: "Imported 8 new, skipped 2 (already published)"

3. **Review List:**
   - See 8 new movies in "Unenriched" tab
   - Movies show ⚠️ Missing metadata

4. **Enrich First Movie:**
   - Click on "The Conspiracy"
   - Detail panel opens
   - Select "Full Enrichment"
   - Click "Preview Enrichment"
   - See: "Found match: The Conspiracy (2013) - IMDB: tt2330322 - Confidence: 85%"
   - Review poster, plot, director, genres
   - Click "Apply Now"
   - Movie updates with enrichment data
   - Movie moves to "Enriched" tab

5. **Manually Edit:**
   - Click [Edit] next to any field
   - Type new value
   - Press Enter → Auto-saves
   - Field marked as "manually changed"

6. **Approve:**
   - Review all metadata
   - Click "✅ Approve"
   - Movie status → "Approved"

7. **Repeat for other 7 movies**

8. **Publish:**
   - Scroll to bottom
   - See "8 movies approved and ready"
   - Click "Publish All Approved"
   - Movies move to production `movies` table
   - Appear in iOS app immediately

---

## Enrichment Priority Guide

### Poster Only (30 seconds)
- ✅ Just the poster image
- Use for: Quick visual improvement

### Basic (1 minute)
- ✅ Poster
- ✅ Genres (Horror, Thriller, etc.)
- Use for: Browsing by category

### Standard (2 minutes)
- ✅ Poster
- ✅ Genres
- ✅ Plot/description
- ✅ Release date
- Use for: Most movies (recommended)

### Full (3 minutes)
- ✅ Everything above
- ✅ Director, actors
- ✅ Runtime, ratings
- ✅ Country, language
- ✅ IMDB + TMDB IDs
- Use for: Featured/popular movies

---

## Keyboard Shortcuts (Future)

- `⌘ I` - Import form
- `⌘ E` - Enrich selected movie
- `⌘ ⏎` - Approve selected movie
- `⌘ ⌫` - Reject selected movie
- `↑ ↓` - Navigate movie list
- `⌘ P` - Publish all approved

---

## Backend Fixes Needed

### 1. Fix duplicate checking ✅ Priority 1
```javascript
// Check both staged_movies AND movies table
// Add option to reimport published movies
```

### 2. Add batch enrichment ✅ Priority 2
```javascript
POST /api/admin/staging/batch-enrich
{
  "movieIds": ["uuid1", "uuid2", ...],
  "priority": "standard"
}
// Enriches multiple movies at once
```

### 3. Add enrichment queue ✅ Priority 3
```javascript
POST /api/admin/staging/enrich-all-unenriched
{
  "priority": "standard",
  "limit": 50
}
// Background job to enrich all unenriched movies
```

### 4. Add progress tracking ✅ Priority 4
```javascript
GET /api/admin/staging/enrichment-progress
// Returns: { inProgress: 5, completed: 20, failed: 2 }
```

---

## Next Steps

1. ✅ **Fix import duplicate checking** (backend)
2. ✅ **Test import with new logic** (should import movies now)
3. ✅ **Test enrichment on one movie** (verify API works)
4. 🔄 **Add batch enrichment** (nice-to-have)
5. 🔄 **Add keyboard shortcuts** (UX improvement)
6. 🔄 **Add enrichment progress bar** (visual feedback)

---

## Questions to Answer

1. **Should we allow re-importing published movies?**
   - Yes, for re-enrichment with better data
   - Add checkbox: "☐ Reimport already published movies"

2. **What happens if enrichment finds multiple matches?**
   - Show all options with confidence scores
   - Let user pick correct one
   - Save choice to improve future matches

3. **Can we edit after publishing?**
   - No, staging is one-way
   - Need separate "Edit Production Movie" feature

4. **How to handle duplicate titles?**
   - Show year in title
   - Show thumbnail for visual confirmation
   - Mark duplicates with ⚠️ icon

---

## Summary

**The workflow is:**
Import → Review → Enrich → Edit → Approve → Publish

**Priority fixes:**
1. Fix duplicate check (backend) - 10 minutes
2. Test full workflow - 15 minutes
3. Add batch enrichment - 30 minutes

**Result:**
A smooth staging workflow where you can import YouTube videos, preview enrichment data, manually adjust, and publish only approved movies to production.
