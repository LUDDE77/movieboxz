import express from 'express'
import { supabase } from '../config/database.js'
import { selectiveEnrichment } from '../services/selectiveEnrichment.js'
import { movieCurator } from '../services/movieCurator.js'
import { youtubeService } from '../services/youtubeService.js'
import omdbService from '../services/omdbService.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// In-memory store for batch enrichment progress
const enrichmentProgress = new Map()

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
                        import_batch_id: batchId || null
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

// GET /api/admin/staging/stats - Get staging statistics
router.get('/stats', async (req, res, next) => {
    try {
        // Get all staged movies
        const { data: allMovies, error } = await supabase
            .from('staged_movies')
            .select('approval_status, tmdb_id, imdb_id')

        if (error) throw error

        const stats = {
            total_staged: allMovies.length,
            pending: allMovies.filter(m => m.approval_status === 'pending').length,
            approved: allMovies.filter(m => m.approval_status === 'approved').length,
            rejected: allMovies.filter(m => m.approval_status === 'rejected').length,
            enriched: allMovies.filter(m => m.tmdb_id || m.imdb_id).length,
            unenriched: allMovies.filter(m => !m.tmdb_id && !m.imdb_id).length
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
            const updateData = {
                ...enrichmentResult.preview,
                enrichment_source: enrichmentResult.source,
                enrichment_confidence: enrichmentResult.confidence,
                updated_at: new Date().toISOString()
            }

            const { data: updated, error: updateError } = await supabase
                .from('staged_movies')
                .update(updateData)
                .eq('id', id)
                .select()
                .single()

            if (updateError) throw updateError

            res.json({
                success: true,
                data: updated
            })
        } else {
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
    try {
        const { id } = req.params
        const { imdbId, verifiedBy = 'admin' } = req.body

        if (!imdbId || !imdbId.match(/^tt\d+$/)) {
            return res.status(400).json({
                success: false,
                error: 'Invalid IMDB ID format. Must be like tt1234567'
            })
        }

        logger.info(`[Staging] Manual IMDB enrichment: ${id} with IMDB ${imdbId}`)

        // Fetch movie data from OMDB using IMDB ID
        const omdbData = await omdbService.getByImdbId(imdbId)

        if (!omdbData) {
            return res.status(404).json({
                success: false,
                error: `No movie found with IMDB ID: ${imdbId}`
            })
        }

        // Update staged movie with OMDB data and mark as manually verified
        const updateData = {
            // Core metadata
            title: omdbData.title || null,
            description: omdbData.plot || null,
            release_year: omdbData.year || null,
            duration_minutes: omdbData.runtime || null,
            rating: omdbData.imdbRating || null,
            poster_url: omdbData.poster || null,

            // IMDB data
            imdb_id: omdbData.imdbID,
            manual_imdb_id: imdbId,

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

        const { data: updated, error: updateError } = await supabase
            .from('staged_movies')
            .update(updateData)
            .eq('id', id)
            .select()
            .single()

        if (updateError) {
            throw updateError
        }

        logger.info(`✅ [Staging] Movie manually verified: ${updated.title} (${imdbId})`)

        res.json({
            success: true,
            data: updated,
            message: `Movie enriched from IMDB ${imdbId} and marked as verified`
        })

    } catch (error) {
        logger.error('[Staging] Manual IMDB enrichment error:', error)
        next(error)
    }
})

// PATCH /api/admin/staging/movies/:id - Manual edit
router.patch('/movies/:id', async (req, res, next) => {
    try {
        const { id } = req.params
        const updates = {
            ...req.body,
            updated_at: new Date().toISOString()
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

// POST /api/admin/staging/publish - Publish approved movies
router.post('/publish', async (req, res, next) => {
    try {
        const { ids } = req.body
        let published = 0
        let failed = 0
        const movieIds = []

        // Get approved staged movies
        let query = supabase
            .from('staged_movies')
            .select('*')
            .eq('approval_status', 'approved')

        if (ids && ids.length > 0) {
            query = query.in('id', ids)
        }

        const { data: stagedMovies, error } = await query.order('created_at')

        if (error) throw error

        for (const stagedMovie of stagedMovies || []) {
            try {
                // Insert into movies table
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
                        category: stagedMovie.category,
                        enrichment_source: stagedMovie.enrichment_source,
                        enrichment_confidence: stagedMovie.enrichment_confidence,
                        is_available: true
                    })
                    .select('id')
                    .single()

                if (insertError) throw insertError

                const movieId = insertedMovie.id
                movieIds.push(movieId)

                // Update staged movie with published_movie_id
                await supabase
                    .from('staged_movies')
                    .update({
                        published_movie_id: movieId,
                        updated_at: new Date().toISOString()
                    })
                    .eq('id', stagedMovie.id)

                published++
            } catch (error) {
                logger.error(`[Staging] Failed to publish movie ${stagedMovie.id}:`, error)
                failed++
            }
        }

        res.json({
            success: true,
            data: {
                published,
                failed,
                movieIds
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
                    category: enrichResult.preview.category
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
                }
            } else {
                logger.warn(`⚠️ [Batch Enrich ${batchId}] No enrichment data for ${movie.title}: ${enrichResult.message}`)
                progress.skipped++
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

export default router
