import express from 'express'
import { supabase } from '../config/database.js'
import { selectiveEnrichment } from '../services/selectiveEnrichment.js'
import { movieCurator } from '../services/movieCurator.js'
import { youtubeService } from '../services/youtubeService.js'
import omdbService from '../services/omdbService.js'
import { tmdbService } from '../services/tmdbService.js'
import { logger } from '../utils/logger.js'
import { adminAuth } from '../middleware/adminAuth.js'
import { normalizeGenreEntries, mapGenreEntriesToIds } from '../utils/genreMapping.js'

const router = express.Router()

// Apply admin auth to all staging routes
router.use(adminAuth)

// In-memory store for batch enrichment progress
const enrichmentProgress = new Map()

// =============================================================================
// POST-ENRICHMENT PIPELINE HELPERS
// Auto-approve on high confidence + manual verification queue feeding
// =============================================================================

// Low-confidence bar used when the channel has no auto_approve_threshold
const DEFAULT_LOW_CONFIDENCE_THRESHOLD = 50

// enrichment confidence appears on both 0-1 and 0-100 scales — normalize to 0-100
// (exported for reuse by channelManagement's auto-enrich import path)
export function confidenceAsPercent(confidence) {
    const value = parseFloat(confidence)
    if (Number.isNaN(value)) return null
    return value <= 1 ? value * 100 : value
}

// Returns the channel's auto_approve_threshold (0-100) or null when unset/<= 0
async function getAutoApproveThreshold(channelId) {
    if (!channelId) return null
    const { data, error } = await supabase
        .from('channel_settings')
        .select('auto_approve_threshold')
        .eq('channel_id', channelId)
        .single()
    if (error || !data) return null
    const threshold = parseFloat(data.auto_approve_threshold)
    return threshold > 0 ? threshold : null
}

// Auto-approve a pending staged movie when its enrichment confidence clears the
// channel's auto_approve_threshold. Returns true when the row was approved.
// (exported for reuse by channelManagement's auto-enrich import path)
export async function maybeAutoApprove(movie, confidencePercent, threshold) {
    if (!movie?.id || threshold == null || confidencePercent == null) return false
    if (movie.approval_status !== 'pending') return false
    if (confidencePercent < threshold) return false

    const { data, error } = await supabase
        .from('staged_movies')
        .update({
            approval_status: 'approved',
            approved_at: new Date().toISOString(),
            approved_by: 'auto-approve',
            updated_at: new Date().toISOString()
        })
        .eq('id', movie.id)
        .eq('approval_status', 'pending') // never touch rows an admin already moved
        .select('id')

    if (error) {
        logger.error(`[Auto-Approve] Failed for staged movie ${movie.id}:`, error)
        return false
    }

    const approved = (data || []).length > 0
    if (approved) {
        logger.info(`[Auto-Approve] "${movie.title}" (${movie.id}) auto-approved: confidence ${confidencePercent} >= threshold ${threshold}`)
    }
    return approved
}

// Build candidate data (for the verification queue) from an enrichment result
function buildCandidateData(enrichmentResult) {
    const preview = enrichmentResult?.preview || {}
    const metadata = enrichmentResult?.metadata || {}
    const candidate = {
        source: enrichmentResult?.source || null,
        title: preview.title || metadata.title || null,
        release_date: preview.release_date || null,
        tmdb_id: metadata.tmdb_id ?? preview.tmdb_id ?? null,
        imdb_id: metadata.imdb_id ?? preview.imdb_id ?? null,
        poster_path: preview.poster_path || null
    }
    const hasData = Object.entries(candidate).some(([key, value]) => key !== 'source' && value != null)
    return hasData ? [candidate] : null
}

// Insert a staged movie into manual_enrichment_queue, deduping on open rows for
// the same video. Never throws — queue feeding must not break enrichment.
async function queueForManualEnrichment(movie, { reason, confidencePercent = null, candidates = null }) {
    try {
        if (!movie?.youtube_video_id) return false

        // Dedupe: skip when an open (pending/in_progress) entry already exists
        const { data: existing } = await supabase
            .from('manual_enrichment_queue')
            .select('id')
            .eq('youtube_video_id', movie.youtube_video_id)
            .in('enrichment_status', ['pending', 'in_progress'])
            .limit(1)

        if (existing && existing.length > 0) {
            logger.debug(`[Manual Queue] ${movie.youtube_video_id} already has an open queue entry`)
            return false
        }

        // channel_title is NOT NULL on the queue table
        let channelTitle = movie.channel_title || movie.channels?.title || null
        if (!channelTitle && movie.channel_id) {
            const { data: channel } = await supabase
                .from('channels')
                .select('title')
                .eq('id', movie.channel_id)
                .single()
            channelTitle = channel?.title || null
        }

        const { error } = await supabase
            .from('manual_enrichment_queue')
            .insert({
                youtube_video_id: movie.youtube_video_id,
                youtube_video_title: movie.youtube_video_title || movie.title,
                channel_id: movie.channel_id,
                channel_title: channelTitle || 'Unknown channel',
                extracted_title: movie.title || null,
                extracted_actors: movie.extracted_actor ? [movie.extracted_actor] : null,
                extracted_genre: movie.extracted_genre || null,
                extracted_year: movie.extracted_year || null,
                description: movie.description || null,
                published_at: movie.published_at || null,
                duration_minutes: movie.runtime_minutes || null,
                enrichment_status: 'pending',
                source_table: 'staged_movies',
                staged_movie_id: movie.id,
                reason,
                confidence: confidencePercent,
                candidates
            })

        if (error) {
            // 23505 = a concurrent request queued the same video — that's fine
            if (error.code !== '23505') {
                logger.error(`[Manual Queue] Failed to queue ${movie.youtube_video_id}:`, error)
            }
            return false
        }

        logger.info(`[Manual Queue] Queued "${movie.title}" (${movie.youtube_video_id}) for manual review: ${reason}`)
        return true
    } catch (err) {
        logger.error('[Manual Queue] Unexpected error:', err)
        return false
    }
}

// Shared hook run after every auto-enrichment attempt (single + batch paths):
//   - high confidence + channel threshold set  -> auto-approve
//   - low confidence (below threshold, or 50 if unset) or no match -> queue for manual review
async function handlePostEnrichment(movie, enrichmentResult) {
    const threshold = await getAutoApproveThreshold(movie?.channel_id)
    const confidencePercent = confidenceAsPercent(enrichmentResult?.confidence)

    if (enrichmentResult?.success) {
        const autoApproved = await maybeAutoApprove(movie, confidencePercent, threshold)
        if (autoApproved) return { autoApproved: true, queued: false }

        const lowBar = threshold ?? DEFAULT_LOW_CONFIDENCE_THRESHOLD
        if (confidencePercent == null || confidencePercent < lowBar) {
            const queued = await queueForManualEnrichment(movie, {
                reason: `Low enrichment confidence (${confidencePercent ?? 'unknown'} < ${lowBar})`,
                confidencePercent,
                candidates: buildCandidateData(enrichmentResult)
            })
            return { autoApproved: false, queued }
        }
        return { autoApproved: false, queued: false }
    }

    // Enrichment found no match at all
    const queued = await queueForManualEnrichment(movie, {
        reason: 'No enrichment match found',
        confidencePercent,
        candidates: null
    })
    return { autoApproved: false, queued }
}

// POST /api/admin/staging/import - Import movies to staging
router.post('/import', async (req, res, next) => {
    try {
        const { channelId, channelTitle, limit = 10, batchId } = req.body

        if (!channelId || !channelTitle) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: channelId and channelTitle'
            })
        }

        logger.info(`[Staging] Importing ${limit} videos from channel: ${channelTitle}`)

        // Fetch videos from YouTube using youtubeService
        const videos = await youtubeService.getChannelVideos(channelId, {
            maxResults: limit,
            fetchDetails: true
        })

        let imported = 0
        let skipped = 0
        const importedMovies = []

        for (const video of videos) {
            try {
                // Check if already in staging
                const { data: inStaging } = await supabase
                    .from('staged_movies')
                    .select('id')
                    .eq('youtube_video_id', video.id)
                    .single()

                if (inStaging) {
                    logger.info(`Skipping ${video.title} - already in staging`)
                    skipped++
                    continue
                }

                // Check if already published to production
                const { data: inProduction } = await supabase
                    .from('movies')
                    .select('id')
                    .eq('youtube_video_id', video.id)
                    .single()

                if (inProduction) {
                    logger.info(`Skipping ${video.title} - already published to production`)
                    skipped++
                    continue
                }

                // Extract metadata using channel pattern
                const parsed = await movieCurator.extractMetadata(video.title, channelId)

                // Calculate duration in minutes
                const durationMinutes = movieCurator.parseDuration(video.duration)

                // Determine if this is a TV series based on episode metadata
                const isTvSeries = !!(parsed.episode_name || parsed.season || parsed.episode)

                // Create staged movie record
                const { data: stagedMovie, error } = await supabase
                    .from('staged_movies')
                    .insert({
                        youtube_video_id: video.id,
                        youtube_video_title: video.title,
                        title: parsed.title || video.title,
                        description: video.description,
                        channel_id: channelId,
                        runtime_minutes: Math.round(durationMinutes),
                        view_count: parseInt(video.viewCount) || 0,
                        like_count: parseInt(video.likeCount) || 0,
                        comment_count: parseInt(video.commentCount) || 0,
                        published_at: video.publishedAt,
                        approval_status: 'pending',
                        import_batch_id: batchId || null,
                        region_restrictions: video.regionRestriction || null,
                        // Episode metadata
                        is_tv_series: isTvSeries,
                        episode_name: parsed.episode_name || null,
                        season_number: parsed.season || null,
                        episode_number: parsed.episode || null,
                        // Pattern metadata
                        pattern_matched: parsed.patternMatched || false,
                        pattern_confidence: parsed.confidence || 0,
                        extracted_actor: parsed.actors || null,
                        extracted_genre: parsed.genre || null,
                        extracted_year: parsed.year || null
                    })
                    .select()
                    .single()

                if (error) throw error

                importedMovies.push(stagedMovie)
                imported++
            } catch (error) {
                logger.error(`[Staging] Failed to import video ${video.id}:`, error)
                skipped++
            }
        }

        logger.info(`[Staging] Import complete: ${imported} imported, ${skipped} skipped`)

        res.json({
            success: true,
            data: {
                imported,
                skipped,
                batchId: batchId || null,
                movies: importedMovies
            }
        })
    } catch (error) {
        logger.error('[Staging] Import error:', error)
        next(error)
    }
})

// POST /api/admin/staging/import-playlist - Import movies from playlist to staging
router.post('/import-playlist', async (req, res, next) => {
    try {
        const { playlistId, channelId = null, limit = 50, batchId } = req.body

        if (!playlistId) {
            return res.status(400).json({
                success: false,
                error: 'Missing required field: playlistId'
            })
        }

        logger.info(`[Staging] Importing ${limit} videos from playlist: ${playlistId}`)

        // Fetch videos from YouTube playlist
        const videos = await youtubeService.getPlaylistItems(playlistId, {
            maxResults: limit
        })

        let imported = 0
        let skipped = 0
        const importedMovies = []

        for (const video of videos) {
            try {
                // Check if already in staging
                const { data: inStaging } = await supabase
                    .from('staged_movies')
                    .select('id')
                    .eq('youtube_video_id', video.id)
                    .single()

                if (inStaging) {
                    logger.info(`Skipping ${video.title} - already in staging`)
                    skipped++
                    continue
                }

                // Check if already published to production
                const { data: inProduction } = await supabase
                    .from('movies')
                    .select('id')
                    .eq('youtube_video_id', video.id)
                    .single()

                if (inProduction) {
                    logger.info(`Skipping ${video.title} - already published to production`)
                    skipped++
                    continue
                }

                // Use provided channelId or the one from the video
                const movieChannelId = channelId || video.channelId

                // Extract metadata using channel pattern
                const parsed = await movieCurator.extractMetadata(video.title, movieChannelId)

                // Calculate duration in minutes
                const durationMinutes = movieCurator.parseDuration(video.duration)

                // Determine if this is a TV series based on episode metadata
                const isTvSeries = !!(parsed.episode_name || parsed.season || parsed.episode)

                // Create staged movie record
                const { data: stagedMovie, error } = await supabase
                    .from('staged_movies')
                    .insert({
                        youtube_video_id: video.id,
                        youtube_video_title: video.title,
                        title: parsed.title || video.title,
                        description: video.description,
                        channel_id: movieChannelId,
                        runtime_minutes: Math.round(durationMinutes),
                        view_count: parseInt(video.viewCount) || 0,
                        like_count: parseInt(video.likeCount) || 0,
                        comment_count: parseInt(video.commentCount) || 0,
                        published_at: video.publishedAt,
                        approval_status: 'pending',
                        import_batch_id: batchId || null,
                        region_restrictions: video.regionRestriction || null,
                        // Episode metadata
                        is_tv_series: isTvSeries,
                        episode_name: parsed.episode_name || null,
                        season_number: parsed.season || null,
                        episode_number: parsed.episode || null,
                        // Pattern metadata
                        pattern_matched: parsed.patternMatched || false,
                        pattern_confidence: parsed.confidence || 0,
                        extracted_actor: parsed.actors || null,
                        extracted_genre: parsed.genre || null,
                        extracted_year: parsed.year || null
                    })
                    .select()
                    .single()

                if (error) throw error

                importedMovies.push(stagedMovie)
                imported++
            } catch (error) {
                logger.error(`[Staging] Failed to import video ${video.id}:`, error)
                skipped++
            }
        }

        logger.info(`[Staging] Playlist import complete: ${imported} imported, ${skipped} skipped`)

        res.json({
            success: true,
            data: {
                imported,
                skipped,
                batchId: batchId || null,
                movies: importedMovies
            }
        })
    } catch (error) {
        logger.error('[Staging] Playlist import error:', error)
        next(error)
    }
})

// GET /api/admin/staging/stats - Get staging statistics
// Uses per-status count queries — selecting all rows caps at 1,000 and undercounts
router.get('/stats', async (req, res, next) => {
    try {
        const countStaged = async (applyFilters) => {
            let query = supabase
                .from('staged_movies')
                .select('*', { count: 'exact', head: true })
            if (applyFilters) {
                query = applyFilters(query)
            }
            const { count, error } = await query
            if (error) throw error
            return count || 0
        }

        const [total, pending, approved, rejected, enriched, unenriched] = await Promise.all([
            countStaged(),
            countStaged(q => q.eq('approval_status', 'pending')),
            countStaged(q => q.eq('approval_status', 'approved')),
            countStaged(q => q.eq('approval_status', 'rejected')),
            countStaged(q => q.or('tmdb_id.not.is.null,imdb_id.not.is.null')),
            countStaged(q => q.is('tmdb_id', null).is('imdb_id', null))
        ])

        const stats = {
            total_staged: total,
            pending,
            approved,
            rejected,
            enriched,
            unenriched
        }

        res.json({
            success: true,
            data: stats
        })
    } catch (error) {
        logger.error('[Staging] Stats error:', error)
        next(error)
    }
})

// GET /api/admin/staging/movies - List staged movies
router.get('/movies', async (req, res, next) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 50
        const offset = (page - 1) * limit
        const status = req.query.status
        const filter = req.query.filter
        const channelId = req.query.channel_id
        const search = req.query.search

        let query = supabase
            .from('staged_movies')
            .select(`
                *,
                channels(title)
            `, { count: 'exact' })

        // Apply filters
        if (status) {
            query = query.eq('approval_status', status)
        }

        if (channelId) {
            query = query.eq('channel_id', channelId)
        }

        if (search) {
            // Case-insensitive match on either the cleaned title or the raw YouTube title
            const escaped = search.replace(/[%,]/g, ' ').trim()
            query = query.or(`title.ilike.%${escaped}%,youtube_video_title.ilike.%${escaped}%`)
        }

        if (filter === 'enriched') {
            query = query.or('tmdb_id.not.is.null,imdb_id.not.is.null')
        } else if (filter === 'unenriched') {
            query = query.is('tmdb_id', null).is('imdb_id', null)
        }

        const { data, error, count } = await query
            .order('created_at', { ascending: false })
            .range(offset, offset + limit - 1)

        if (error) throw error

        // Add channel_title to each movie
        const movies = (data || []).map(movie => ({
            ...movie,
            channel_title: movie.channels?.title || null
        }))

        res.json({
            success: true,
            data: {
                movies,
                pagination: {
                    page,
                    limit,
                    total: count || 0,
                    pages: Math.ceil((count || 0) / limit)
                }
            }
        })
    } catch (error) {
        logger.error('[Staging] List movies error:', error)
        next(error)
    }
})

// GET /api/admin/staging/movies/:id/tmdb-candidates?q=<title>
// Alternate TMDB matches for the review workflow's inline re-pick. Uses the
// provided query, or falls back to the movie's cleaned title / YouTube title.
router.get('/movies/:id/tmdb-candidates', async (req, res, next) => {
    try {
        const { id } = req.params
        let query = (req.query.q || '').trim()

        if (!query) {
            const { data: movie } = await supabase
                .from('staged_movies')
                .select('title, youtube_video_title')
                .eq('id', id)
                .maybeSingle()
            query = (movie?.title || movie?.youtube_video_title || '').trim()
        }

        if (!query) {
            return res.status(400).json({ success: false, error: 'No search query available' })
        }

        const results = await tmdbService.searchMovies(query)
        const candidates = (results || []).slice(0, 8).map(r => ({
            tmdb_id: r.id,
            title: r.title,
            year: r.release_date ? parseInt(String(r.release_date).slice(0, 4)) : null,
            poster_path: r.poster_path || null,
            overview: r.overview || null,
            vote_average: r.vote_average ?? null
        }))

        res.json({ success: true, data: { query, candidates } })
    } catch (error) {
        logger.error('[Staging] tmdb-candidates error:', error)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/set-match  { tmdbId }
// Re-point a staged movie's pick to a chosen TMDB match (used when the review
// UI operator corrects a wrong auto-pick). Writes the new pick but leaves the
// row pending so the operator confirms with Approve.
router.post('/movies/:id/set-match', async (req, res, next) => {
    try {
        const { id } = req.params
        const { tmdbId } = req.body || {}
        if (!tmdbId) {
            return res.status(400).json({ success: false, error: 'tmdbId is required' })
        }

        const details = await tmdbService.getMovieDetails(tmdbId)
        if (!details || !details.title) {
            return res.status(404).json({ success: false, error: `No TMDB movie found for id ${tmdbId}` })
        }

        const update = {
            title: details.title,
            description: details.overview || null,
            poster_path: details.poster_path || null,
            backdrop_path: details.backdrop_path || null,
            release_date: details.release_date || null,
            tmdb_id: details.id,
            imdb_id: details.imdb_id || null,
            vote_average: details.vote_average ?? null,
            enrichment_source: 'manual_review',
            enrichment_confidence: 100,
            manually_verified: true,
            enriched_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        }
        if (Array.isArray(details.genres) && details.genres.length > 0) {
            update.genre_data = details.genres
        }

        const { data, error } = await supabase
            .from('staged_movies')
            .update(update)
            .eq('id', id)
            .not('approval_status', 'in', '("publishing","published")')
            .select('*')
            .maybeSingle()

        if (error) throw error
        if (!data) {
            return res.status(404).json({ success: false, error: 'Movie not found or already published' })
        }

        res.json({ success: true, data })
    } catch (error) {
        logger.error('[Staging] set-match error:', error)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/preview-enrichment
router.post('/movies/:id/preview-enrichment', async (req, res, next) => {
    try {
        const { id } = req.params
        const { priority = 'full', fields = null, preferTmdb = true } = req.body

        const { data: movie, error } = await supabase
            .from('staged_movies')
            .select('*')
            .eq('id', id)
            .single()

        if (error) {
            return res.status(404).json({ success: false, error: 'Movie not found' })
        }

        const enrichmentResult = await selectiveEnrichment.enrichSelective(movie, {
            priority,
            fields,
            preferTmdb,
            previewOnly: true,
            respectManual: true,
            manualChanges: movie.manual_changes
        })

        // Save preview to database
        await supabase
            .from('staged_movies')
            .update({
                enrichment_preview: enrichmentResult.preview,
                updated_at: new Date().toISOString()
            })
            .eq('id', id)

        res.json({
            success: true,
            data: enrichmentResult
        })
    } catch (error) {
        logger.error('[Staging] Preview enrichment error:', error)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/enrich
router.post('/movies/:id/enrich', async (req, res, next) => {
    try {
        const { id } = req.params
        const { priority = 'full', fields = null, preferTmdb = true } = req.body

        const { data: movie, error } = await supabase
            .from('staged_movies')
            .select('*')
            .eq('id', id)
            .single()

        if (error) {
            return res.status(404).json({ success: false, error: 'Movie not found' })
        }

        const enrichmentResult = await selectiveEnrichment.enrichSelective(movie, {
            priority,
            fields,
            preferTmdb,
            previewOnly: false,
            respectManual: true,
            manualChanges: movie.manual_changes
        })

        if (enrichmentResult.success) {
            // genres is a relation (movie_genres), not a staged_movies column —
            // spreading it into the update makes Supabase 500. Capture it into
            // the genre_data JSONB column instead so publish can map it to
            // movie_genres (migration 035).
            const { genres: _genres, ...previewColumns } = enrichmentResult.preview || {}
            const updateData = {
                ...previewColumns,
                enrichment_source: enrichmentResult.source,
                enrichment_confidence: enrichmentResult.confidence,
                updated_at: new Date().toISOString()
            }

            const capturedGenres = normalizeGenreEntries(_genres)
            if (capturedGenres) {
                updateData.genre_data = capturedGenres
            }

            const { data: updated, error: updateError } = await supabase
                .from('staged_movies')
                .update(updateData)
                .eq('id', id)
                .select()
                .single()

            if (updateError) throw updateError

            // Auto-approve on high confidence / queue for manual review on low
            const postResult = await handlePostEnrichment(updated, enrichmentResult)
            if (postResult.autoApproved) {
                updated.approval_status = 'approved'
                updated.approved_at = new Date().toISOString()
                updated.approved_by = 'auto-approve'
            }

            res.json({
                success: true,
                data: postResult.autoApproved ? { ...updated, autoApproved: true } : updated
            })
        } else {
            // No match found — feed the manual verification queue
            await handlePostEnrichment(movie, enrichmentResult)

            res.status(400).json({
                success: false,
                error: 'Enrichment failed',
                message: enrichmentResult.message || 'Could not enrich movie'
            })
        }
    } catch (error) {
        logger.error('[Staging] Apply enrichment error:', error)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/enrich-manual-imdb
// Manually enrich from user-provided IMDB ID - system will trust this choice
router.post('/movies/:id/enrich-manual-imdb', async (req, res, next) => {
    const startTime = Date.now()
    logger.info(`\n${'='.repeat(80)}`)
    logger.info(`[Staging] 🎬 MANUAL IMDB ENRICHMENT REQUEST`)
    logger.info(`[Staging] Movie ID: ${req.params.id}`)
    logger.info(`[Staging] Request body:`, JSON.stringify(req.body, null, 2))
    logger.info(`${'='.repeat(80)}\n`)

    try {
        const { id } = req.params
        const { imdbId, verifiedBy = 'admin' } = req.body

        logger.info(`[Staging] Step 1: Validate IMDB ID format`)
        if (!imdbId || !imdbId.match(/^tt\d+$/)) {
            logger.error(`[Staging] ❌ Invalid IMDB ID format: ${imdbId}`)
            return res.status(400).json({
                success: false,
                error: 'Invalid IMDB ID format. Must be like tt1234567'
            })
        }
        logger.info(`[Staging] ✅ IMDB ID format valid: ${imdbId}`)

        logger.info(`[Staging] Step 2: Fetch data from OMDB API`)

        // Fetch movie data from OMDB using IMDB ID
        let omdbData
        try {
            logger.info(`[Staging]   → Calling omdbService.getByImdbId(${imdbId})`)
            omdbData = await omdbService.getByImdbId(imdbId)
            logger.info(`[Staging]   → OMDB API call completed`)
        } catch (error) {
            logger.error(`[Staging] ❌ OMDB API error:`, error)
            logger.error(`[Staging]   Error stack:`, error.stack)
            return res.status(500).json({
                success: false,
                error: 'Failed to fetch movie data from OMDB',
                details: error.message
            })
        }

        if (!omdbData) {
            logger.warn(`[Staging] ⚠️  No OMDB data found for IMDB ID: ${imdbId}`)
            return res.status(404).json({
                success: false,
                error: `No movie found with IMDB ID: ${imdbId}`
            })
        }

        logger.info(`[Staging] ✅ OMDB data retrieved successfully`)
        logger.info(`[Staging]   Title: ${omdbData.title}`)
        logger.info(`[Staging]   IMDB ID: ${omdbData.imdb_id}`)
        logger.info(`[Staging]   Full OMDB data:`, JSON.stringify(omdbData, null, 2))

        logger.info(`[Staging] Step 3: Validate OMDB data`)
        if (!omdbData.title) {
            logger.error(`[Staging] ❌ OMDB data missing required title field`)
            return res.status(500).json({
                success: false,
                error: 'OMDB data incomplete - missing title',
                details: 'The movie data from OMDB is missing the title field'
            })
        }
        logger.info(`[Staging] ✅ OMDB data validation passed`)

        logger.info(`[Staging] Step 4: Build update data object`)

        // Extract year from release_date (YYYY-MM-DD -> YYYY)
        let releaseYear = null
        if (omdbData.release_date) {
            releaseYear = parseInt(omdbData.release_date.split('-')[0])
        }

        // Update staged movie with OMDB data and mark as manually verified
        const updateData = {
            // Core metadata - title is required
            title: omdbData.title,
            description: omdbData.description || null,
            release_date: omdbData.release_date || null,
            runtime_minutes: omdbData.runtime_minutes || null,
            poster_path: omdbData.poster_path || null,

            // IMDB data
            imdb_id: omdbData.imdb_id,
            imdb_rating: omdbData.imdb_rating || null,
            imdb_votes: omdbData.imdb_votes || null,
            manual_imdb_id: imdbId,

            // Additional metadata
            rated: omdbData.rated || null,
            director: omdbData.director || null,
            actors: omdbData.actors || null,
            language: omdbData.language || null,
            country: omdbData.country || null,
            category: omdbData.genre || null,
            is_tv_show: omdbData.is_tv_show || false,

            // Manual verification tracking
            manually_verified: true,
            verified_by: verifiedBy,
            verified_at: new Date().toISOString(),

            // Enrichment metadata
            enrichment_source: 'manual_imdb',
            enrichment_confidence: 1.0,
            enriched_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        }

        logger.info(`[Staging] ✅ Update data object built`)
        logger.info(`[Staging]   Fields to update: ${Object.keys(updateData).join(', ')}`)
        logger.info(`[Staging]   Full update data:`, JSON.stringify(updateData, null, 2))

        logger.info(`[Staging] Step 5: Update database`)
        logger.info(`[Staging]   → Calling supabase.from('staged_movies').update()`)
        logger.info(`[Staging]   → WHERE id = ${id}`)

        const { data: updated, error: updateError } = await supabase
            .from('staged_movies')
            .update(updateData)
            .eq('id', id)
            .select()
            .single()

        if (updateError) {
            logger.error(`[Staging] ❌ Database update error:`)
            logger.error(`[Staging]   Error code: ${updateError.code}`)
            logger.error(`[Staging]   Error message: ${updateError.message}`)
            logger.error(`[Staging]   Error details:`, JSON.stringify(updateError, null, 2))
            throw updateError
        }

        if (!updated) {
            logger.error(`[Staging] ❌ No movie returned after update (movie not found?)`)
            throw new Error(`Movie with ID ${id} not found`)
        }

        logger.info(`[Staging] ✅ Database update successful`)
        logger.info(`[Staging]   Updated movie: ${updated.title}`)
        logger.info(`[Staging]   IMDB ID: ${updated.imdb_id}`)

        const duration = Date.now() - startTime
        logger.info(`\n${'='.repeat(80)}`)
        logger.info(`[Staging] ✅ MANUAL IMDB ENRICHMENT COMPLETED`)
        logger.info(`[Staging] Duration: ${duration}ms`)
        logger.info(`[Staging] Movie: ${updated.title} (${imdbId})`)
        logger.info(`${'='.repeat(80)}\n`)

        res.json({
            success: true,
            data: updated,
            message: `Movie enriched from IMDB ${imdbId} and marked as verified`
        })

    } catch (error) {
        const duration = Date.now() - startTime
        logger.error(`\n${'='.repeat(80)}`)
        logger.error(`[Staging] ❌ MANUAL IMDB ENRICHMENT FAILED`)
        logger.error(`[Staging] Duration: ${duration}ms`)
        logger.error(`[Staging] Error type: ${error.constructor.name}`)
        logger.error(`[Staging] Error message: ${error.message}`)
        logger.error(`[Staging] Error stack:`, error.stack)
        logger.error(`${'='.repeat(80)}\n`)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/clear-enrichment
// Clear all enrichment data (reset to unenriched state)
router.post('/movies/:id/clear-enrichment', async (req, res, next) => {
    try {
        const { id } = req.params

        logger.info(`[Staging] Clearing enrichment for movie: ${id}`)

        // Clear all enrichment fields but keep YouTube data
        const updateData = {
            // Clear TMDB/IMDB IDs
            tmdb_id: null,
            imdb_id: null,
            manual_imdb_id: null,

            // Clear enriched metadata (keep title as it might be from pattern extraction)
            description: null,
            release_date: null,
            runtime_minutes: null,
            poster_path: null,
            backdrop_path: null,
            vote_average: null,
            vote_count: null,
            popularity: null,
            imdb_rating: null,
            imdb_votes: null,
            rated: null,
            director: null,
            actors: null,
            language: null,
            country: null,
            is_tv_show: null,
            category: null,
            genre_data: null,

            // Clear enrichment metadata
            enrichment_source: null,
            enrichment_confidence: null,
            enriched_at: null,

            // Clear manual verification
            manually_verified: false,
            verified_by: null,
            verified_at: null,

            // Clear preview
            enrichment_preview: null,

            updated_at: new Date().toISOString()
        }

        const { data: updated, error: updateError } = await supabase
            .from('staged_movies')
            .update(updateData)
            .eq('id', id)
            .select()
            .single()

        if (updateError) {
            throw updateError
        }

        logger.info(`✅ [Staging] Enrichment cleared for: ${updated.title}`)

        res.json({
            success: true,
            data: updated,
            message: 'Enrichment data cleared - movie reset to unenriched state'
        })

    } catch (error) {
        logger.error('[Staging] Clear enrichment error:', error)
        next(error)
    }
})

// PATCH /api/admin/staging/movies/:id - Manual edit
// Only allow a safe allowlist of fields to prevent tampering with workflow state
const STAGING_PATCH_ALLOWED_FIELDS = [
    'title', 'description', 'release_date', 'runtime_minutes',
    'imdb_id', 'tmdb_id', 'poster_path', 'backdrop_path',
    'vote_average', 'vote_count', 'popularity',
    'imdb_rating', 'imdb_votes', 'rated',
    'director', 'actors', 'language', 'country',
    'category', 'is_tv_show', 'is_tv_series', 'is_kids_content',
    'notes', 'channel_tag', 'tv_series_id',
    'season_number', 'episode_number', 'episode_name'
]

router.patch('/movies/:id', async (req, res, next) => {
    try {
        const { id } = req.params

        // Build update object from allowlist only — never spread raw req.body
        const updates = { updated_at: new Date().toISOString() }
        for (const field of STAGING_PATCH_ALLOWED_FIELDS) {
            if (Object.prototype.hasOwnProperty.call(req.body, field)) {
                updates[field] = req.body[field]
            }
        }

        const { data, error } = await supabase
            .from('staged_movies')
            .update(updates)
            .eq('id', id)
            .select()
            .single()

        if (error) {
            return res.status(404).json({ success: false, error: 'Movie not found' })
        }

        res.json({
            success: true,
            data
        })
    } catch (error) {
        logger.error('[Staging] Update movie error:', error)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/approve
router.post('/movies/:id/approve', async (req, res, next) => {
    try {
        const { id } = req.params
        const { notes } = req.body

        const { data, error } = await supabase
            .from('staged_movies')
            .update({
                approval_status: 'approved',
                approved_at: new Date().toISOString(),
                notes: notes || null,
                updated_at: new Date().toISOString()
            })
            .eq('id', id)
            .select()
            .single()

        if (error) {
            return res.status(404).json({ success: false, error: 'Movie not found' })
        }

        res.json({
            success: true,
            data
        })
    } catch (error) {
        logger.error('[Staging] Approve movie error:', error)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/reject
router.post('/movies/:id/reject', async (req, res, next) => {
    try {
        const { id } = req.params
        const { reason } = req.body

        const { data, error } = await supabase
            .from('staged_movies')
            .update({
                approval_status: 'rejected',
                rejected_reason: reason,
                updated_at: new Date().toISOString()
            })
            .eq('id', id)
            .select()
            .single()

        if (error) {
            return res.status(404).json({ success: false, error: 'Movie not found' })
        }

        res.json({
            success: true,
            data
        })
    } catch (error) {
        logger.error('[Staging] Reject movie error:', error)
        next(error)
    }
})

// Maps a free-text category string (e.g. "Crime, Drama") to the first matching content_category enum value
const CATEGORY_MAP = {
    action: 'action', adventure: 'adventure', animation: 'animation', comedy: 'comedy',
    crime: 'crime', documentary: 'documentary', drama: 'drama', family: 'family',
    fantasy: 'fantasy', history: 'history', horror: 'horror', music: 'music',
    mystery: 'mystery', romance: 'romance', 'science fiction': 'science_fiction',
    'sci-fi': 'science_fiction', thriller: 'thriller', war: 'war', western: 'western', classic: 'classic'
}
function mapToContentCategory(category) {
    if (!category) return null
    const lower = String(category).toLowerCase()
    for (const [key, val] of Object.entries(CATEGORY_MAP)) {
        if (lower.includes(key)) return val
    }
    return null
}

// Reset rows stuck in 'publishing' for more than 15 minutes back to 'approved'.
// Prevents rows orphaned by a mid-publish crash/redeploy from vanishing forever.
export async function resetStuckPublishing() {
    const cutoff = new Date(Date.now() - 15 * 60 * 1000).toISOString()

    const { data, error } = await supabase
        .from('staged_movies')
        .update({ approval_status: 'approved', updated_at: new Date().toISOString() })
        .eq('approval_status', 'publishing')
        .lt('updated_at', cutoff)
        .select('id')

    if (error) throw error

    const resetCount = data?.length || 0
    if (resetCount > 0) {
        logger.warn(`[Staging] Reset ${resetCount} stuck 'publishing' row(s) back to 'approved'`)
    }
    return resetCount
}

// Map a staged row's captured genre_data onto the freshly published movie via
// the atomic update_movie_genres RPC. NEVER fatal — a genre mapping error must
// not fail a publish, so all failures are logged and swallowed.
async function applyStagedGenreData(movieId, stagedMovie, getGenreRows) {
    if (!stagedMovie.genre_data) return
    try {
        const genreRows = await getGenreRows()
        const { genreIds, matched, unmatched } = mapGenreEntriesToIds(stagedMovie.genre_data, genreRows)

        if (unmatched.length > 0) {
            logger.warn(`[Publish] Unmatched genre(s) for "${stagedMovie.title}": ${unmatched.join(', ')}`)
        }
        if (genreIds.length === 0) return

        const { error: rpcError } = await supabase.rpc('update_movie_genres', {
            p_movie_id: movieId,
            p_genre_ids: genreIds
        })
        if (rpcError) throw rpcError

        logger.info(`[Publish] Applied ${genreIds.length} genre(s) to "${stagedMovie.title}": ${matched.join(', ')}`)
    } catch (error) {
        logger.error(`[Publish] Genre mapping failed for movie ${movieId} ("${stagedMovie.title}") — publish unaffected:`, error)
    }
}

// POST /api/admin/staging/publish - Publish approved movies
router.post('/publish', async (req, res, next) => {
    try {
        const { ids } = req.body
        let published = 0
        let failed = 0
        const movieIds = []
        const errors = []

        // Genres table cache — loaded at most once per publish request
        let genreRowsCache = null
        const getGenreRows = async () => {
            if (genreRowsCache) return genreRowsCache
            const { data, error } = await supabase
                .from('genres')
                .select('id, name')
            if (error) throw error
            // genres.id doubles as the TMDB genre id in this schema
            genreRowsCache = (data || []).map(g => ({ ...g, tmdb_id: g.id }))
            return genreRowsCache
        }

        // Recover rows orphaned in 'publishing' by a previous crash/redeploy
        await resetStuckPublishing().catch(err => {
            logger.error('[Staging] Stuck-publishing reaper failed:', err)
        })

        // If specific IDs provided, approve them first.
        // Guard on current status so rejected/published rows are never force-approved.
        if (ids && ids.length > 0) {
            await supabase
                .from('staged_movies')
                .update({ approval_status: 'approved', updated_at: new Date().toISOString() })
                .in('id', ids)
                .in('approval_status', ['pending', 'approved'])
        }

        // Atomically claim movies for publishing: transition approved -> publishing.
        // This prevents concurrent Publish All requests from processing the same movies.
        let claimQuery = supabase
            .from('staged_movies')
            .update({ approval_status: 'publishing', updated_at: new Date().toISOString() })
            .eq('approval_status', 'approved')

        if (ids && ids.length > 0) {
            claimQuery = claimQuery.in('id', ids)
        }

        // Only process the rows THIS request claimed — a concurrent publish may
        // hold other rows in 'publishing' at the same time.
        const { data: claimedRows, error: claimError } = await claimQuery.select('id')

        if (claimError) throw claimError

        const claimedIds = (claimedRows || []).map(r => r.id)

        if (claimedIds.length === 0) {
            return res.json({
                success: true,
                data: {
                    published: 0,
                    failed: 0,
                    movieIds: [],
                    errors: undefined
                }
            })
        }

        const { data: stagedMovies, error } = await supabase
            .from('staged_movies')
            .select('*')
            .in('id', claimedIds)
            .order('created_at')

        if (error) throw error

        let skippedNoPoster = 0
        for (const stagedMovie of stagedMovies || []) {
            try {
                // Publish gate: movies (not episodes) must have a poster before
                // they reach the consumer apps. Episodes fall back to YouTube
                // thumbnails by design, so they are exempt.
                if (!stagedMovie.poster_path && !stagedMovie.is_tv_series) {
                    await supabase
                        .from('staged_movies')
                        .update({ approval_status: 'approved', updated_at: new Date().toISOString() })
                        .eq('id', stagedMovie.id)
                    skippedNoPoster++
                    logger.info(`[Publish] Skipped "${stagedMovie.title}" — no poster (stays approved)`)
                    continue
                }

                // Insert into movies table
                // Convert enrichment_confidence from 0-100 scale to 0-1 scale if needed
                let enrichmentConfidence = stagedMovie.enrichment_confidence
                if (enrichmentConfidence != null && enrichmentConfidence > 1) {
                    enrichmentConfidence = enrichmentConfidence / 100
                }

                const { data: insertedMovie, error: insertError } = await supabase
                    .from('movies')
                    .insert({
                        youtube_video_id: stagedMovie.youtube_video_id,
                        youtube_video_title: stagedMovie.youtube_video_title,
                        title: stagedMovie.title,
                        original_title: stagedMovie.original_title,
                        description: stagedMovie.description,
                        release_date: stagedMovie.release_date,
                        runtime_minutes: stagedMovie.runtime_minutes,
                        channel_id: stagedMovie.channel_id,
                        view_count: stagedMovie.view_count,
                        like_count: stagedMovie.like_count,
                        comment_count: stagedMovie.comment_count,
                        published_at: stagedMovie.published_at,
                        tmdb_id: stagedMovie.tmdb_id,
                        imdb_id: stagedMovie.imdb_id,
                        poster_path: stagedMovie.poster_path,
                        backdrop_path: stagedMovie.backdrop_path,
                        vote_average: stagedMovie.vote_average,
                        vote_count: stagedMovie.vote_count,
                        popularity: stagedMovie.popularity,
                        imdb_rating: stagedMovie.imdb_rating,
                        imdb_votes: stagedMovie.imdb_votes,
                        rated: stagedMovie.rated,
                        director: stagedMovie.director,
                        actors: stagedMovie.actors,
                        language: stagedMovie.language,
                        country: stagedMovie.country,
                        is_tv_show: stagedMovie.is_tv_show,
                        is_tv_series: stagedMovie.is_tv_series,
                        is_kids_content: stagedMovie.is_kids_content,
                        tv_series_id: stagedMovie.tv_series_id,
                        season_number: stagedMovie.season_number,
                        episode_number: stagedMovie.episode_number,
                        series_type: stagedMovie.series_type || null,
                        category: mapToContentCategory(stagedMovie.category),
                        region_restrictions: stagedMovie.region_restrictions || null,
                        // Project region_restrictions into queryable array columns so
                        // newly-published movies are immediately region-filter-ready.
                        region_blocked: stagedMovie.region_restrictions?.blocked ?? null,
                        region_allowed: stagedMovie.region_restrictions?.allowed ?? null,
                        region_checked_at: stagedMovie.region_restrictions ? new Date().toISOString() : null,
                        enrichment_source: stagedMovie.enrichment_source,
                        enrichment_confidence: enrichmentConfidence,
                        is_available: true
                    })
                    .select('id')
                    .single()

                if (insertError) {
                    // If duplicate youtube_video_id, find existing movie and mark as published
                    if (insertError.code === '23505' && insertError.message?.includes('youtube_video_id')) {
                        const { data: existing } = await supabase
                            .from('movies')
                            .select('id')
                            .eq('youtube_video_id', stagedMovie.youtube_video_id)
                            .single()
                        if (existing) {
                            await supabase
                                .from('staged_movies')
                                .update({
                                    approval_status: 'published',
                                    published_movie_id: existing.id,
                                    updated_at: new Date().toISOString()
                                })
                                .eq('id', stagedMovie.id)
                            movieIds.push(existing.id)
                            published++
                            continue
                        }
                    }
                    throw insertError
                }

                const movieId = insertedMovie.id
                movieIds.push(movieId)

                // Map captured enrichment genres to movie_genres (non-fatal)
                await applyStagedGenreData(movieId, stagedMovie, getGenreRows)

                // Update staged movie: mark as published and record production movie ID
                await supabase
                    .from('staged_movies')
                    .update({
                        approval_status: 'published',
                        published_movie_id: movieId,
                        updated_at: new Date().toISOString()
                    })
                    .eq('id', stagedMovie.id)

                published++
            } catch (error) {
                logger.error(`[Staging] Failed to publish movie ${stagedMovie.id}:`, error)
                errors.push({
                    movieId: stagedMovie.id,
                    movieTitle: stagedMovie.title,
                    error: error.message,
                    errorCode: error.code,
                    errorDetails: error.details || error.hint
                })
                // Roll back to 'approved' so the movie can be retried
                await supabase
                    .from('staged_movies')
                    .update({ approval_status: 'approved', updated_at: new Date().toISOString() })
                    .eq('id', stagedMovie.id)
                failed++
            }
        }

        res.json({
            success: true,
            data: {
                published,
                failed,
                skippedNoPoster: skippedNoPoster > 0 ? skippedNoPoster : undefined,
                movieIds,
                errors: errors.length > 0 ? errors : undefined
            }
        })
    } catch (error) {
        logger.error('[Staging] Publish error:', error)
        next(error)
    }
})

// POST /api/admin/staging/batch-enrich - Start batch enrichment (async)
router.post('/batch-enrich', async (req, res, next) => {
    try {
        const { movieIds, priority = 'full' } = req.body

        if (!movieIds || !Array.isArray(movieIds) || movieIds.length === 0) {
            return res.status(400).json({
                success: false,
                error: 'movieIds array is required'
            })
        }

        // Generate batch ID
        const batchId = `enrich_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`

        logger.info(`📦 [Batch Enrich] Starting batch enrichment for ${movieIds.length} movies (batch: ${batchId})`)

        // Initialize progress tracking
        enrichmentProgress.set(batchId, {
            status: 'running',
            total: movieIds.length,
            enriched: 0,
            failed: 0,
            skipped: 0,
            autoApproved: 0,
            current: null,
            currentIndex: 0,
            startedAt: new Date().toISOString()
        })

        // Return immediately with batch ID
        res.json({
            success: true,
            data: {
                batchId,
                status: 'running',
                total: movieIds.length
            }
        })

        // Process enrichment in background
        processEnrichmentBatch(batchId, movieIds, priority).catch(err => {
            logger.error(`[Batch Enrich] Background process error:`, err)
            const progress = enrichmentProgress.get(batchId)
            if (progress) {
                progress.status = 'failed'
                progress.error = err.message
            }
        })

    } catch (error) {
        logger.error('[Batch Enrich] Error:', error)
        next(error)
    }
})

// Background processing function
async function processEnrichmentBatch(batchId, movieIds, priority) {
    const progress = enrichmentProgress.get(batchId)
    if (!progress) return

    for (let i = 0; i < movieIds.length; i++) {
        const movieId = movieIds[i]

        try {
            // Fetch movie data
            const { data: movie, error: fetchError } = await supabase
                .from('staged_movies')
                .select('*')
                .eq('id', movieId)
                .single()

            if (fetchError || !movie) {
                logger.error(`❌ [Batch Enrich ${batchId}] Movie ${movieId} not found`)
                progress.failed++
                progress.currentIndex = i + 1
                continue
            }

            // Skip manually verified movies - they've been vetted by a human
            if (movie.manually_verified) {
                logger.info(`⏭️  [Batch Enrich ${batchId}] (${i + 1}/${movieIds.length}) Skipping "${movie.title}" - manually verified`)
                progress.skipped++
                progress.currentIndex = i + 1
                continue
            }

            // Update progress with current movie
            progress.current = movie.title
            progress.currentIndex = i + 1
            logger.info(`🔍 [Batch Enrich ${batchId}] (${i + 1}/${movieIds.length}) Enriching: "${movie.title}"`)

            // Call enrichment
            const enrichResult = await selectiveEnrichment.enrichSelective(
                {
                    title: movie.title,
                    actors: movie.extracted_actor,
                    year: movie.extracted_year,
                    youtube_video_title: movie.youtube_video_title,
                    channel_id: movie.channel_id,
                    channel_title: null,
                    published_at: movie.published_at
                },
                {
                    priority: priority,
                    previewOnly: false,
                    preferTmdb: true
                }
            )

            if (enrichResult.success && enrichResult.preview) {
                // Update movie with enrichment data
                const enrichmentUpdate = {
                    enrichment_source: enrichResult.source,
                    tmdb_id: enrichResult.metadata?.tmdb_id,
                    imdb_id: enrichResult.metadata?.imdb_id,
                    enrichment_confidence: enrichResult.confidence,
                    enriched_at: new Date().toISOString(),
                    poster_path: enrichResult.preview.poster_path,
                    backdrop_path: enrichResult.preview.backdrop_path,
                    description: enrichResult.preview.description,
                    release_date: enrichResult.preview.release_date,
                    runtime_minutes: enrichResult.preview.runtime_minutes,
                    vote_average: enrichResult.preview.vote_average,
                    vote_count: enrichResult.preview.vote_count,
                    imdb_rating: enrichResult.preview.imdb_rating,
                    imdb_votes: enrichResult.preview.imdb_votes,
                    popularity: enrichResult.preview.popularity,
                    rated: enrichResult.preview.rated,
                    director: enrichResult.preview.director,
                    actors: enrichResult.preview.actors,
                    language: enrichResult.preview.language,
                    country: enrichResult.preview.country,
                    category: enrichResult.preview.category,
                    // genres is not a staged_movies column — capture into the
                    // genre_data JSONB column for mapping at publish time.
                    // normalizeGenreEntries returns null for no data; `?? undefined`
                    // lets the undefined-cleanup below drop the key entirely.
                    genre_data: normalizeGenreEntries(enrichResult.preview.genres) ?? undefined
                }

                // Remove undefined values
                Object.keys(enrichmentUpdate).forEach(key =>
                    enrichmentUpdate[key] === undefined && delete enrichmentUpdate[key]
                )

                const { error: updateError } = await supabase
                    .from('staged_movies')
                    .update(enrichmentUpdate)
                    .eq('id', movieId)

                if (updateError) {
                    logger.error(`❌ [Batch Enrich ${batchId}] Update failed for ${movie.title}:`, updateError)
                    progress.failed++
                } else {
                    logger.info(`✅ [Batch Enrich ${batchId}] Enriched: ${movie.title} from ${enrichResult.source}`)
                    progress.enriched++

                    // Auto-approve on high confidence / queue for manual review on low
                    const postResult = await handlePostEnrichment({ ...movie, ...enrichmentUpdate }, enrichResult)
                    if (postResult.autoApproved) {
                        progress.autoApproved++
                    }
                }
            } else {
                logger.warn(`⚠️ [Batch Enrich ${batchId}] No enrichment data for ${movie.title}: ${enrichResult.message}`)
                progress.skipped++

                // Mark the attempt (same as the single-enrich path) so repeat
                // batch runs don't re-attempt the same unmatchable rows forever
                await supabase
                    .from('staged_movies')
                    .update({
                        enrichment_confidence: confidenceAsPercent(enrichResult.confidence) ?? 30,
                        enriched_at: new Date().toISOString()
                    })
                    .eq('id', movieId)

                // No match — feed the manual verification queue
                await handlePostEnrichment(movie, enrichResult)
            }

        } catch (movieError) {
            logger.error(`💥 [Batch Enrich ${batchId}] Error enriching ${movieId}:`, movieError)
            progress.failed++
        }
    }

    // Mark as completed
    progress.status = 'completed'
    progress.completedAt = new Date().toISOString()
    logger.info(`📦 [Batch Enrich ${batchId}] Complete: ${progress.enriched} enriched, ${progress.failed} failed, ${progress.skipped} skipped`)

    // Auto-cleanup after 5 minutes
    setTimeout(() => {
        enrichmentProgress.delete(batchId)
        logger.info(`🧹 [Batch Enrich] Cleaned up progress for batch ${batchId}`)
    }, 5 * 60 * 1000)
}

// GET /api/admin/staging/batch-enrich/:batchId/status - Get enrichment progress
router.get('/batch-enrich/:batchId/status', async (req, res, next) => {
    try {
        const { batchId } = req.params
        const progress = enrichmentProgress.get(batchId)

        if (!progress) {
            return res.status(404).json({
                success: false,
                error: 'Batch enrichment not found or expired'
            })
        }

        // Calculate percentage
        const processed = progress.enriched + progress.failed + progress.skipped
        const percentage = progress.total > 0
            ? Math.round((processed / progress.total) * 100)
            : 0

        res.json({
            success: true,
            data: {
                ...progress,
                percentage
            }
        })
    } catch (error) {
        logger.error('[Batch Enrich Status] Error:', error)
        next(error)
    }
})

/**
 * POST /api/admin/staging/movies/:id/enrich-from-data
 * Update a staged movie with pre-scraped enrichment data (e.g. from local Playwright).
 * Used as fallback when the OMDB/axios scraper is blocked.
 */
router.post('/movies/:id/enrich-from-data', async (req, res, next) => {
    try {
        const { id } = req.params
        const { imdbId, title, year, directors, actors, description, posterUrl, genres, imdbRating, type } = req.body

        if (!imdbId || !imdbId.match(/^tt\d+$/)) {
            return res.status(400).json({ success: false, error: 'Valid IMDB ID required (tt...)' })
        }

        const { data: movie, error: fetchError } = await supabase
            .from('staged_movies')
            .select('id, description, release_date')
            .eq('id', id)
            .single()

        if (fetchError) throw fetchError
        if (!movie) return res.status(404).json({ success: false, error: 'Staged movie not found' })

        const updateData = {
            imdb_id: imdbId,
            manual_imdb_id: imdbId,
            manually_verified: true,
            verified_by: 'imdb-verify-agent',
            verified_at: new Date().toISOString(),
            enrichment_source: 'playwright_local',
            enrichment_confidence: 1.0,
            updated_at: new Date().toISOString()
        }

        if (title) updateData.title = title
        if (posterUrl) updateData.poster_path = posterUrl
        if (imdbRating) updateData.imdb_rating = parseFloat(imdbRating)
        if (directors?.length) updateData.director = directors.join(', ')
        if (actors?.length) updateData.actors = actors.join(', ')
        if (description && !movie.description) updateData.description = description
        if (year && !movie.release_date) updateData.release_date = `${year}-01-01`
        if (type) updateData.is_tv_show = type === 'TVSeries'

        // Capture scraped genre names for mapping to movie_genres at publish
        const scrapedGenres = normalizeGenreEntries(genres)
        if (scrapedGenres) updateData.genre_data = scrapedGenres

        const { data: updated, error: updateError } = await supabase
            .from('staged_movies')
            .update(updateData)
            .eq('id', id)
            .select('*')
            .single()

        if (updateError) throw updateError

        logger.info(`[Staging] enrich-from-data done for staged movie ${id} → ${imdbId}`)
        res.json({ success: true, data: updated })
    } catch (error) {
        logger.error('[Staging] enrich-from-data error:', error)
        next(error)
    }
})

export default router
