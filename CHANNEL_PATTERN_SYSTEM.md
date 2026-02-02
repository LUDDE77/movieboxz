# Channel Pattern Detection System - Implementation Plan

## Goal

Create a flexible system where each YouTube channel has a **defined, manually-configured pattern** for extracting movie metadata from video titles.

## System Components

### 1. Channel Pattern Configuration

**Store channel patterns as structured configuration data:**

```javascript
{
  channelId: "UC6A_LC-A5NVJ2vw9A0OjCug",
  channelName: "The Midnight Screening",
  patterns: [
    {
      // Primary pattern
      regex: /^(.+?)\s*FULL MOVIE\s*\|\s*(.+?)\s*Movies?\s*\|\s*(.+?)\s*\|\s*The Midnight Screening$/i,
      parameters: {
        title: 1,        // Capture group 1
        genre: 2,        // Capture group 2
        actors: 3,       // Capture group 3
        channel: "The Midnight Screening"  // Static
      }
    },
    {
      // Alternative pattern with year
      regex: /^(.+?)\s*\((\d{4})\)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*The Midnight Screening$/i,
      parameters: {
        title: 1,
        year: 2,
        genre: 3,
        actors: 4,
        channel: "The Midnight Screening"
      }
    }
  ],
  fallbackPattern: {
    // If no pattern matches, use this
    type: "first_segment",
    divider: "|"
  }
}
```

### 2. Database Schema

**Add new table: `channel_patterns`**

```sql
CREATE TABLE channel_patterns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    channel_id TEXT NOT NULL UNIQUE REFERENCES channels(id),
    channel_name TEXT NOT NULL,
    patterns JSONB NOT NULL,  -- Array of pattern objects
    fallback_pattern JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

**Add new table: `manual_enrichment_queue`**

For movies that fail automatic enrichment:

```sql
CREATE TABLE manual_enrichment_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    youtube_video_id TEXT NOT NULL UNIQUE,
    youtube_video_title TEXT NOT NULL,
    channel_id TEXT NOT NULL,
    channel_title TEXT NOT NULL,

    -- Extracted metadata (from pattern)
    extracted_title TEXT,
    extracted_actors TEXT[],
    extracted_genre TEXT,
    extracted_year INTEGER,

    -- Raw YouTube data for reference
    description TEXT,
    published_at TIMESTAMP,
    duration_minutes INTEGER,
    thumbnail_url TEXT,

    -- Manual enrichment fields
    manual_imdb_id TEXT,              -- User provides this
    manual_tmdb_id INTEGER,            -- Can be looked up from IMDB
    manual_notes TEXT,                 -- User can add notes
    enrichment_status TEXT DEFAULT 'pending',  -- pending, matched, skipped

    -- Tracking
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    processed_at TIMESTAMP
);

CREATE INDEX idx_manual_enrichment_status ON manual_enrichment_queue(enrichment_status);
CREATE INDEX idx_manual_enrichment_channel ON manual_enrichment_queue(channel_id);
```

### 3. Pattern Matching Service

**New service: `channelPatternManager.js`**

```javascript
class ChannelPatternManager {
    constructor() {
        this.patterns = new Map() // Cache patterns in memory
    }

    // Load pattern from database
    async getPattern(channelId) {
        if (this.patterns.has(channelId)) {
            return this.patterns.get(channelId)
        }

        const { data } = await supabase
            .from('channel_patterns')
            .select('*')
            .eq('channel_id', channelId)
            .eq('is_active', true)
            .single()

        if (data) {
            this.patterns.set(channelId, data)
        }

        return data
    }

    // Extract metadata from title using pattern
    extractMetadata(youtubeTitle, pattern) {
        if (!pattern || !pattern.patterns) {
            return null
        }

        // Try each pattern in order
        for (const patternDef of pattern.patterns) {
            const match = youtubeTitle.match(patternDef.regex)
            if (match) {
                const metadata = {}

                // Extract each parameter
                for (const [param, captureGroup] of Object.entries(patternDef.parameters)) {
                    if (typeof captureGroup === 'number') {
                        metadata[param] = match[captureGroup]?.trim()
                    } else {
                        metadata[param] = captureGroup  // Static value
                    }
                }

                // Parse actors array if present
                if (metadata.actors) {
                    metadata.actorsArray = metadata.actors
                        .split(/[,&]|\\s+and\\s+/i)
                        .map(a => a.trim())
                        .filter(a => a.length > 0)
                }

                return {
                    ...metadata,
                    patternMatched: true,
                    confidence: 1.0
                }
            }
        }

        // No pattern matched - use fallback
        if (pattern.fallbackPattern) {
            return this.applyFallbackPattern(youtubeTitle, pattern.fallbackPattern)
        }

        return null
    }

    // Store pattern configuration
    async savePattern(channelId, channelName, patterns, fallbackPattern) {
        const { data, error } = await supabase
            .from('channel_patterns')
            .upsert({
                channel_id: channelId,
                channel_name: channelName,
                patterns: patterns,
                fallback_pattern: fallbackPattern,
                updated_at: new Date().toISOString()
            }, {
                onConflict: 'channel_id'
            })
            .select()
            .single()

        if (error) throw error

        // Update cache
        this.patterns.set(channelId, data)

        return data
    }
}
```

### 4. Manual Enrichment Queue Service

**New service: `manualEnrichmentQueue.js`**

```javascript
class ManualEnrichmentQueue {
    // Add movie to manual enrichment queue
    async addToQueue(movieData, extractedMetadata) {
        const { data, error } = await supabase
            .from('manual_enrichment_queue')
            .insert({
                youtube_video_id: movieData.youtube_video_id,
                youtube_video_title: movieData.youtube_video_title,
                channel_id: movieData.channel_id,
                channel_title: movieData.channel_title,
                extracted_title: extractedMetadata?.title,
                extracted_actors: extractedMetadata?.actorsArray,
                extracted_genre: extractedMetadata?.genre,
                extracted_year: extractedMetadata?.year,
                description: movieData.description,
                published_at: movieData.published_at,
                duration_minutes: movieData.duration_minutes,
                thumbnail_url: movieData.channel_thumbnail,
                enrichment_status: 'pending'
            })
            .select()
            .single()

        if (error) throw error
        return data
    }

    // Process manual IMDB match
    async processManualMatch(queueId, imdbId, notes) {
        // 1. Update queue record
        const { data: queueData } = await supabase
            .from('manual_enrichment_queue')
            .update({
                manual_imdb_id: imdbId,
                manual_notes: notes,
                enrichment_status: 'matched',
                processed_at: new Date().toISOString()
            })
            .eq('id', queueId)
            .select()
            .single()

        // 2. Fetch enrichment data using IMDB ID
        const enrichmentData = await this.enrichFromIMDB(imdbId)

        // 3. Update or create movie record
        // ... implement movie update logic

        return enrichmentData
    }

    // Get pending items
    async getPendingQueue(channelId = null, limit = 50) {
        let query = supabase
            .from('manual_enrichment_queue')
            .select('*')
            .eq('enrichment_status', 'pending')
            .order('created_at', { ascending: false })
            .limit(limit)

        if (channelId) {
            query = query.eq('channel_id', channelId)
        }

        const { data, error } = await query
        if (error) throw error
        return data
    }
}
```

### 5. API Endpoints

**Add new admin endpoints:**

```javascript
// GET /api/admin/channel-patterns/:channelId
// Get pattern configuration for a channel

// POST /api/admin/channel-patterns
// Create/update pattern configuration
// Body: { channelId, channelName, patterns, fallbackPattern }

// GET /api/admin/manual-enrichment-queue
// Get pending items in manual enrichment queue
// Query params: ?channelId=xxx&status=pending&limit=50

// POST /api/admin/manual-enrichment-queue/:id/match
// Manually match a movie with IMDB ID
// Body: { imdbId, notes }

// GET /api/admin/channel-patterns/analyze/:channelId
// Analyze a channel and suggest patterns based on sample titles
```

### 6. Integration with Movie Import Flow

**Updated flow in `movieCurator.js`:**

```javascript
async processMovie(video, options = {}) {
    try {
        // 1. Get channel pattern
        const pattern = await channelPatternManager.getPattern(video.channelId)

        // 2. Extract metadata using pattern
        const extractedMetadata = pattern
            ? channelPatternManager.extractMetadata(video.title, pattern)
            : { title: video.title }

        // 3. Prepare movie data
        const movieData = {
            youtube_video_id: video.id,
            title: extractedMetadata.title || video.title,
            youtube_video_title: video.title,
            // ... other fields
        }

        // 4. Try enrichment with extracted actor hints
        let enrichmentData = null
        if (extractedMetadata.actorsArray || extractedMetadata.year) {
            enrichmentData = await enhancedEnrichment.enrichMovie({
                ...movieData,
                actorHints: extractedMetadata.actorsArray,
                yearHint: extractedMetadata.year,
                genreHint: extractedMetadata.genre
            })
        }

        // 5. If enrichment fails or low confidence, add to manual queue
        if (!enrichmentData || enrichmentData.confidence < 70) {
            await manualEnrichmentQueue.addToQueue(movieData, extractedMetadata)
            logger.warn(`Low confidence match - added to manual queue: ${movieData.title}`)
        }

        // 6. Save movie (with or without enrichment)
        const savedMovie = await dbOperations.createMovie(movieData)

        return true
    } catch (error) {
        logger.error(`Failed to process movie: ${error.message}`)
        return false
    }
}
```

## Implementation Steps

### Phase 1: Database Setup
1. Create `channel_patterns` table
2. Create `manual_enrichment_queue` table
3. Add indexes

### Phase 2: Core Services
1. Implement `channelPatternManager.js`
2. Implement `manualEnrichmentQueue.js`
3. Add pattern analysis tool (suggest patterns from sample titles)

### Phase 3: API Layer
1. Add channel pattern management endpoints
2. Add manual enrichment queue endpoints
3. Add pattern analysis endpoint

### Phase 4: Integration
1. Update `movieCurator.js` to use pattern system
2. Update `enhancedEnrichment.js` to accept actor/year hints
3. Add fallback to manual queue on low confidence

### Phase 5: Admin Interface (Future)
1. Web UI for managing channel patterns
2. Web UI for processing manual enrichment queue
3. Pattern testing/preview tool

## Testing Plan

1. **Test Pattern Extraction**
   - Load sample titles from The Midnight Screening
   - Verify title, actor, genre, year extraction
   - Test fallback patterns

2. **Test Manual Queue**
   - Import movies with intentionally bad patterns
   - Verify they land in manual queue
   - Test manual IMDB matching

3. **Test End-to-End**
   - Import full channel with patterns configured
   - Verify correct enrichment
   - Check manual queue for failures

## Configuration Examples

### The Midnight Screening Pattern

```json
{
  "channelId": "UC6A_LC-A5NVJ2vw9A0OjCug",
  "channelName": "The Midnight Screening",
  "patterns": [
    {
      "regex": "^(.+?)\\s*FULL MOVIE\\s*\\|\\s*(.+?)\\s*Movies?\\s*\\|\\s*(.+?)\\s*\\|\\s*The Midnight Screening$",
      "parameters": {
        "title": 1,
        "genre": 2,
        "actors": 3,
        "channel": "The Midnight Screening"
      }
    },
    {
      "regex": "^(.+?)\\s*\\((\\d{4})\\)\\s*\\|\\s*(.+?)\\s*\\|\\s*(.+?)\\s*\\|\\s*The Midnight Screening$",
      "parameters": {
        "title": 1,
        "year": 2,
        "genre": 3,
        "actors": 4,
        "channel": "The Midnight Screening"
      }
    }
  ],
  "fallbackPattern": {
    "type": "first_segment",
    "divider": "|"
  }
}
```

## Success Criteria

✅ Patterns can be configured per-channel via API
✅ Title, actor, genre, year extracted correctly (>90% accuracy)
✅ Failed enrichments go to manual queue
✅ Manual IMDB matching works correctly
✅ System learns from manual matches (future enhancement)
