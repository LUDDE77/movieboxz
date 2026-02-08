# Channel Management Workflow - Improvement Plan

## 📋 User Requirements Summary

### 1. Bulk Channel Import
- Import **entire channel** at once (all videos)
- Apply **generic/default settings** per channel
- One-click import instead of manual batching

### 2. Channel-Level Configuration
- Set default enrichment priority per channel (poster-only, standard, full)
- Set default approval settings per channel
- Automatic application of channel settings to all imports

### 3. Enhanced Movie Management
- **Filter movies by channel** in movie table
- **Mark/tag entire channel** in one operation
- **Batch edit** all movies from a channel
- **Delete entire channel's movies** at once
- **Re-import entire channel** (reset and reimport)

### 4. Smart Import Options
When doing manual import, specify:
- **Import limit**: "Last 20 videos"
- **Sort order**:
  - Latest uploaded (by publish date - newest first)
  - Oldest uploaded (by publish date - oldest first)
  - Alphabetical A-Z
  - Alphabetical Z-A
  - Most viewed
  - Highest rated

---

## 🎯 Proposed Solution

### Phase 1: Database Schema Updates

#### A. Add Channel Settings Table
```sql
CREATE TABLE channel_settings (
    channel_id VARCHAR(50) PRIMARY KEY REFERENCES channels(id),

    -- Import settings
    auto_import_enabled BOOLEAN DEFAULT FALSE,
    auto_import_schedule VARCHAR(20), -- 'daily', 'weekly', 'manual'
    import_limit INTEGER, -- NULL = all, or specific number
    import_sort_order VARCHAR(20) DEFAULT 'latest', -- 'latest', 'oldest', 'alphabetical', 'views'

    -- Default enrichment settings
    default_enrichment_priority VARCHAR(20) DEFAULT 'standard', -- 'poster', 'basic', 'standard', 'full'
    auto_enrich_on_import BOOLEAN DEFAULT FALSE,

    -- Default approval settings
    auto_approve_threshold NUMERIC, -- Auto-approve if confidence > threshold
    require_manual_review BOOLEAN DEFAULT TRUE,

    -- Filtering/tagging
    channel_tag VARCHAR(50), -- Custom tag for this channel
    is_featured BOOLEAN DEFAULT FALSE,
    quality_tier VARCHAR(20), -- 'premium', 'standard', 'basic'

    -- Metadata
    last_import_at TIMESTAMPTZ,
    total_imported INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### B. Add Import History Table
```sql
CREATE TABLE import_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id VARCHAR(50) REFERENCES channels(id),
    batch_id UUID,

    -- Import details
    import_type VARCHAR(20), -- 'full', 'partial', 'latest'
    videos_found INTEGER,
    videos_imported INTEGER,
    videos_skipped INTEGER,
    videos_failed INTEGER,

    -- Import parameters
    import_limit INTEGER,
    sort_order VARCHAR(20),

    -- Results
    status VARCHAR(20), -- 'pending', 'running', 'completed', 'failed'
    error_message TEXT,

    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    duration_seconds INTEGER
);
```

#### C. Update Movies Table
Add channel reference tracking:
```sql
ALTER TABLE movies
ADD COLUMN IF NOT EXISTS import_batch_id UUID REFERENCES import_history(id),
ADD COLUMN IF NOT EXISTS channel_tag VARCHAR(50);

CREATE INDEX idx_movies_channel_id ON movies(channel_id);
CREATE INDEX idx_movies_channel_tag ON movies(channel_tag);
CREATE INDEX idx_movies_import_batch ON movies(import_batch_id);
```

---

### Phase 2: Backend API Endpoints

#### Channel Settings Management

**1. Get Channel Settings**
```
GET /api/admin/channels/:channelId/settings
Response: {
  channelId,
  autoImportEnabled,
  defaultEnrichmentPriority,
  autoEnrichOnImport,
  importLimit,
  importSortOrder,
  ...
}
```

**2. Update Channel Settings**
```
PUT /api/admin/channels/:channelId/settings
Body: {
  autoImportEnabled: true,
  defaultEnrichmentPriority: 'standard',
  autoEnrichOnImport: true,
  importLimit: null, // null = all
  importSortOrder: 'latest'
}
```

#### Bulk Import Operations

**3. Import Entire Channel**
```
POST /api/admin/channels/:channelId/import-all
Body: {
  applySettings: true, // Use channel default settings
  sortOrder: 'latest', // Override default
  limit: null // null = all videos
}
Response: {
  batchId,
  videosFound: 450,
  status: 'running'
}
```

**4. Import Latest N Videos**
```
POST /api/admin/channels/:channelId/import-latest
Body: {
  limit: 20,
  sortOrder: 'latest', // 'latest', 'oldest', 'alphabetical', 'views'
  applySettings: true
}
```

**5. Get Import Status**
```
GET /api/admin/imports/:batchId/status
Response: {
  status: 'running',
  progress: {
    found: 450,
    imported: 120,
    skipped: 5,
    failed: 0,
    current: 125
  }
}
```

#### Batch Operations

**6. Delete All Channel Movies**
```
DELETE /api/admin/channels/:channelId/movies
Query: ?deleteFrom=staging,production
Response: {
  deletedFromStaging: 10,
  deletedFromProduction: 440
}
```

**7. Re-import Channel**
```
POST /api/admin/channels/:channelId/reimport
Body: {
  deleteExisting: true,
  applySettings: true,
  limit: null
}
```

**8. Get Channel Movies**
```
GET /api/admin/channels/:channelId/movies
Query: ?source=staging,production&page=1&limit=50
Response: {
  staging: { movies: [...], total: 10 },
  production: { movies: [...], total: 440 }
}
```

#### Import History

**9. Get Import History**
```
GET /api/admin/channels/:channelId/import-history
Response: {
  imports: [
    {
      id,
      importType: 'full',
      videosImported: 450,
      status: 'completed',
      startedAt,
      duration: 320
    }
  ]
}
```

---

### Phase 3: macOS UI Components

#### 1. Channel Settings Panel

**Location**: Channel Setup → Channel Detail → Settings Tab

**UI Structure**:
```
┌─────────────────────────────────────────┐
│ Channel Settings - The Midnight Screening│
├─────────────────────────────────────────┤
│                                         │
│ Import Settings                         │
│ ☐ Auto-import enabled                  │
│ Import schedule: [Manual ▼]            │
│ Import limit: [All videos ▼]           │
│ Sort order: [Latest first ▼]           │
│                                         │
│ Enrichment Settings                     │
│ Default priority: [Standard ▼]         │
│ ☑ Auto-enrich on import                │
│                                         │
│ Approval Settings                       │
│ Auto-approve threshold: [80% ▼]        │
│ ☑ Require manual review                │
│                                         │
│ Channel Tagging                         │
│ Tag: [thriller-classics    ]           │
│ Quality tier: [Premium ▼]              │
│ ☐ Featured channel                     │
│                                         │
│ [Save Settings]  [Reset to Defaults]   │
└─────────────────────────────────────────┘
```

#### 2. Bulk Import Panel

**Location**: Channel Setup → Channel Detail → Import Tab

**UI Structure**:
```
┌─────────────────────────────────────────┐
│ Import from The Midnight Screening      │
├─────────────────────────────────────────┤
│                                         │
│ Import Mode:                            │
│ ○ Import entire channel (all videos)   │
│ ● Import latest N videos               │
│                                         │
│ How many: [20        ] videos           │
│                                         │
│ Sort by:                                │
│ ● Latest uploaded (newest first)       │
│ ○ Oldest uploaded (oldest first)       │
│ ○ Alphabetical (A-Z)                   │
│ ○ Most viewed                           │
│                                         │
│ ☑ Apply channel default settings       │
│ ☑ Auto-enrich after import             │
│                                         │
│ [Start Import]                          │
│                                         │
│ ──────────────────────────────────────  │
│                                         │
│ Quick Actions:                          │
│ [Import Last 10] [Import Last 50]      │
│ [Import All New]                        │
└─────────────────────────────────────────┘
```

#### 3. Import Progress View

**Real-time progress during bulk import**:
```
┌─────────────────────────────────────────┐
│ Importing from The Midnight Screening... │
├─────────────────────────────────────────┤
│                                         │
│ Status: Running                         │
│ ████████████████░░░░░░░░ 65%          │
│                                         │
│ Found: 450 videos                       │
│ Imported: 120                           │
│ Skipped: 5 (already exist)              │
│ Failed: 0                               │
│                                         │
│ Current: "The Conspiracy (2013)..."     │
│ Estimated time: 4 minutes remaining     │
│                                         │
│ [Cancel Import]                         │
└─────────────────────────────────────────┘
```

#### 4. Channel Movies View

**Location**: Channel Setup → Channel Detail → Movies Tab

**UI Structure**:
```
┌─────────────────────────────────────────┐
│ Movies from The Midnight Screening      │
├─────────────────────────────────────────┤
│ Filter: [All ▼] Search: [           ]  │
│                                         │
│ Staging: 10 movies | Production: 440   │
│                                         │
│ Batch Actions:                          │
│ [Enrich All] [Approve All] [Delete All]│
│ [Re-import Channel]                     │
│                                         │
│ ──────────────────────────────────────  │
│                                         │
│ ☐ The Stick Up             | Staging    │
│ ☐ Driven To Kill           | Staging    │
│ ☑ High Voltage             | Production │
│ ☑ The Conspiracy           | Production │
│                                         │
│ Selected: 2 | [Enrich] [Delete]        │
└─────────────────────────────────────────┘
```

#### 5. Import History View

**Location**: Channel Setup → Channel Detail → History Tab

**UI Structure**:
```
┌─────────────────────────────────────────┐
│ Import History                          │
├─────────────────────────────────────────┤
│                                         │
│ 2026-02-07 12:45 | Full Import         │
│ ✅ Completed | 450 videos | 5m 20s      │
│ [View Details] [Re-run]                 │
│                                         │
│ 2026-02-03 09:30 | Latest 20           │
│ ✅ Completed | 20 videos | 45s          │
│ [View Details] [Re-run]                 │
│                                         │
│ 2026-02-01 14:15 | Full Import         │
│ ⚠️ Failed | Error: Rate limit exceeded  │
│ [View Details] [Retry]                  │
└─────────────────────────────────────────┘
```

---

### Phase 4: Implementation Order

#### Sprint 1: Database & Basic Settings (3-4 days)
1. ✅ Create channel_settings table migration
2. ✅ Create import_history table migration
3. ✅ Update movies table with channel tracking
4. ✅ Create backend API for channel settings CRUD
5. ✅ Test database operations

#### Sprint 2: Bulk Import Backend (4-5 days)
1. ✅ Implement bulk import service
2. ✅ Add import queue/job system (or use sequential)
3. ✅ Add import progress tracking
4. ✅ Implement sort order logic (latest, oldest, alphabetical, views)
5. ✅ Add import limit support
6. ✅ Create import history logging
7. ✅ Test bulk imports with real channels

#### Sprint 3: Batch Operations Backend (2-3 days)
1. ✅ Implement delete all channel movies
2. ✅ Implement re-import channel
3. ✅ Add channel movies listing endpoint
4. ✅ Add batch enrichment support
5. ✅ Test batch operations

#### Sprint 4: macOS UI - Settings (3-4 days)
1. ✅ Create ChannelSettingsView.swift
2. ✅ Add settings form with all options
3. ✅ Connect to backend API
4. ✅ Add validation and error handling
5. ✅ Test settings save/load

#### Sprint 5: macOS UI - Bulk Import (4-5 days)
1. ✅ Create BulkImportView.swift
2. ✅ Add import mode selection
3. ✅ Add sort order picker
4. ✅ Create progress view with real-time updates
5. ✅ Add cancel import functionality
6. ✅ Test import flows

#### Sprint 6: macOS UI - Channel Movies (3-4 days)
1. ✅ Create ChannelMoviesView.swift
2. ✅ Add staging/production filter
3. ✅ Add batch action buttons
4. ✅ Add movie selection/multi-select
5. ✅ Connect batch operations to backend
6. ✅ Test batch operations

#### Sprint 7: macOS UI - Import History (2-3 days)
1. ✅ Create ImportHistoryView.swift
2. ✅ Display import logs with details
3. ✅ Add re-run/retry functionality
4. ✅ Test history tracking

#### Sprint 8: Integration & Polish (2-3 days)
1. ✅ Integrate all views into ChannelManagementView
2. ✅ Add tab navigation (Pattern, Settings, Import, Movies, History)
3. ✅ Add loading states and error handling
4. ✅ Add user feedback (toasts, alerts)
5. ✅ Final testing and bug fixes

---

## 🎨 Key UX Improvements

### Before (Current Workflow):
1. Add channel
2. Configure pattern
3. Import 10-20 movies manually
4. Go to Staging view
5. Enrich movies one by one
6. Approve movies one by one
7. Publish individually
8. Repeat steps 3-7 for more movies

**Time per channel: 30-60 minutes** ⏱️

### After (Improved Workflow):
1. Add channel
2. Configure pattern
3. Configure channel settings (one-time)
4. Click "Import All" or "Import Last 50"
5. System auto-enriches with channel defaults
6. Batch review in channel view
7. Batch approve/publish
8. Done! ✅

**Time per channel: 5-10 minutes** ⚡

---

## 🔧 Technical Considerations

### Backend Performance
- **Large imports**: Use background jobs for 100+ videos
- **Rate limiting**: Respect YouTube API limits
- **Progress tracking**: WebSocket or polling for real-time updates
- **Cancellation**: Support mid-import cancellation

### Data Consistency
- **Idempotent imports**: Skip duplicates automatically
- **Transactional operations**: Batch deletes in transactions
- **Rollback support**: Keep import history for recovery

### UI/UX Polish
- **Real-time feedback**: Show import progress live
- **Error recovery**: Clear error messages and retry options
- **Bulk confirmations**: Warn before destructive operations
- **Keyboard shortcuts**: Speed up power users

---

## 📊 Success Metrics

After implementation, we should see:
- ✅ **90% reduction** in time to import full channel
- ✅ **75% reduction** in manual steps per channel
- ✅ **Zero duplicate imports** (automatic skip)
- ✅ **Batch operations** working on 100+ movies
- ✅ **Import history** tracking all operations

---

## 🚀 Next Steps

Would you like me to:
1. **Start with Phase 1** (Database schema) and create the migrations?
2. **Create a specific feature first** (e.g., bulk import or channel settings)?
3. **Adjust the plan** based on your priorities?

Let me know which direction you'd like to take! 🎯
