# Database Architecture Review Report
**Date:** February 8, 2026
**Issue:** Admin tool showing different data than API endpoints

---

## Executive Summary

There is **NO table duplication**, but there **IS confusion** due to:
1. **Multiple API endpoints** accessing the same tables differently
2. **Different views using different endpoints**
3. **New channel management system** working alongside old admin system

The admin tool is reading from the **correct tables**, but it's using **different API endpoints** that may filter or present data differently.

---

## Table Structure

### Core Tables (Production)

| Table | Purpose | Used By |
|-------|---------|---------|
| `channels` | Master list of YouTube channels | All systems |
| `movies` | **Published/production movies** | `/api/movies`, `/api/channels` |
| `staged_movies` | **Pending review movies** | `/api/admin/staging`, new channel management |
| `channel_patterns` | Title extraction patterns | Pattern editor |
| `channel_settings` | Channel import configuration | **NEW - Channel Management only** |
| `import_history` | Bulk import tracking | **NEW - Channel Management only** |

### Key Observations

1. **`movies` table = PRODUCTION/PUBLISHED**
   - Only contains approved, published movies
   - Used by public API (`/api/movies`, `/api/channels`)
   - Admin tool's channel list shows counts from this table

2. **`staged_movies` table = STAGING/PENDING**
   - Contains movies awaiting approval
   - Used by staging system and new channel management
   - NOT counted in admin tool's main channel list

3. **Two separate workflows:**
   - **Old workflow:** Channels list → Movies (production only)
   - **New workflow:** Channel Management → Staging → Production

---

## API Endpoints Analysis

### Channels Endpoints

| Endpoint | Table(s) | What It Shows | Used By |
|----------|----------|---------------|---------|
| `GET /api/channels` | `channels` + `movies` | Channels with **production movie counts** | AdminView.swift, StagingView.swift |
| `GET /api/admin/channels` | `channels` + `channel_patterns` | Channels with patterns | ChannelManagementView.swift |
| `GET /api/admin/channel-management/:id/movies` | `staged_movies` + `movies` | **Both staging AND production** | **NEW** ChannelMoviesView.swift |

### Why You See Different Data

**When you call:**
```bash
curl .../api/admin/channels
```
You see: **All channels** (including @TheMidnightScreening)

**When admin tool loads:**
```swift
apiService.getChannels()  // Calls /api/channels
```
It sees: **Only channels with production movies**

**@TheMidnightScreening has:**
- 11 staged_movies (pending)
- 0 movies (production)

**Result:** The channel exists in the database but **doesn't show in the admin tool's main list** because it filters channels with `movies(count)`.

---

## The Root Cause

### Problem 1: Admin Tool Uses Wrong Endpoint

**File:** `macOS/MovieBoxZAdmin/Views/AdminView.swift:199`
```swift
let data = try await apiService.getChannels()  // ❌ Wrong!
```

This calls `/api/channels` which only shows channels with **production movies**.

**Should call:**
```swift
let data = try await apiService.getChannelsWithPatterns()  // ✅ Correct!
```

This calls `/api/admin/channels` which shows **all channels** regardless of movie count.

### Problem 2: Channel Management View Uses Correct Endpoint

**File:** `macOS/MovieBoxZAdmin/Views/ChannelManagementView.swift:145`
```swift
let data = try await apiService.getChannelsWithPatterns()  // ✅ Correct!
```

**Result:** Channel Management tab sees ALL channels (including @TheMidnightScreening).

---

## Current State Verification

### @TheMidnightScreening Status

| Aspect | Value | Table |
|--------|-------|-------|
| Channel ID | UC6A_LC-A5NVJ2vw9A0OjCug | `channels` |
| In database? | ✅ Yes | `channels` |
| Has settings? | ✅ Yes (auto-created) | `channel_settings` |
| Staging movies | 11 | `staged_movies` |
| Production movies | 0 | `movies` |
| Import history | 1 completed batch | `import_history` |

### Test Import Results

```
Batch ID: beaadb6a-8ee9-4620-b8ec-d738644949be
Status: ✅ Completed
Found: 10 videos
Imported: 1 new
Skipped: 9 duplicates
Failed: 0
```

**All systems working correctly** ✅

---

## Why Data Appears Different

### What I See via API:
```bash
curl /api/admin/channels
# Returns: All 9 channels including @TheMidnightScreening
```

### What Admin Tool Shows:
```swift
getChannels() → /api/channels?page=1&limit=50
# Returns: Only channels with production movies (filters out @TheMidnightScreening)
```

### What Channel Management Shows:
```swift
getChannelsWithPatterns() → /api/admin/channels
# Returns: All channels (includes @TheMidnightScreening)
```

---

## Recommendations

### 1. Fix AdminView to Show All Channels

**Change:** `macOS/MovieBoxZAdmin/Views/AdminView.swift:199`

```swift
// FROM:
let data = try await apiService.getChannels()

// TO:
let data = try await apiService.getChannelsWithPatterns()
```

### 2. OR Fix the Channels Endpoint

**Option A:** Modify `/api/channels` to return all channels, not just those with movies

**Option B:** Add a new query parameter `?include_empty=true`

### 3. Consolidate Channel Lists (Recommended)

**Current structure:**
- AdminView → Shows channels list (uses `/api/channels`)
- ChannelManagementView → Shows channels list with patterns (uses `/api/admin/channels`)

**These are duplicate views!**

**Recommendation:** Use ONE channels view that shows:
- Channel info
- Pattern status
- Movie counts (staging + production)
- Quick actions

---

## No Table Duplication Issues

✅ **No duplicate tables**
✅ **No conflicting data**
✅ **Clear separation:** staging → production workflow
✅ **New channel management system** works correctly

❌ **UI issue:** Different views use different endpoints
❌ **Filtering issue:** Main admin view filters out channels without production movies

---

## Summary

The system architecture is **correct**. The confusion stems from:

1. **AdminView** uses `/api/channels` (filters channels with movies)
2. **ChannelManagementView** uses `/api/admin/channels` (shows all channels)
3. **New channel management** adds movies to `staged_movies` first
4. **Channels without production movies** don't appear in main admin list

**Solution:** Update AdminView to use the same endpoint as ChannelManagementView, or modify the `/api/channels` endpoint to include all channels.

---

## Verification Commands

```bash
# List all channels
curl -s https://movieboxz-backend-production.up.railway.app/api/admin/channels \
  -H "x-admin-api-key: YOUR_KEY" | grep -o '"title":"[^"]*"'

# Check specific channel movies
curl -s "https://movieboxz-backend-production.up.railway.app/api/admin/channel-management/UC6A_LC-A5NVJ2vw9A0OjCug/movies?source=staging,production" \
  -H "x-admin-api-key: YOUR_KEY"

# Check channel settings
curl -s "https://movieboxz-backend-production.up.railway.app/api/admin/channel-management/UC6A_LC-A5NVJ2vw9A0OjCug/settings" \
  -H "x-admin-api-key: YOUR_KEY"
```
