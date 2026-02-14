import express from 'express'
import { pool, supabase } from '../config/database.js'
import { movieCurator } from '../services/movieCurator.js'
import { selectiveEnrichment } from '../services/selectiveEnrichment.js'
import { enhancedEnrichment } from '../services/enhancedEnrichment.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// =============================================================================
// 1. IMPORT TO STAGING
// =============================================================================

/**
 * Import channel movies to staging table
 * POST /api/staging/import
 * Body: { channelId, channelTitle, limit, batchId }
 */
router.post('/import', async (req, res, next) => {
    try {
        const { channelId, channelTitle, limit = 50, batchId = null } = req.body

        if (!channelId && !channelTitle) {
            return res.status(400).json({
                error: 'channelId or channelTitle required'
            })
        }

        logger.info(`Importing channel to staging: ${channelTitle || channelId}`)

        // Fetch movies from YouTube (use existing curator)
        const youtubeMovies = await movieCurator.fetchChannelMovies(channelId || channelTitle, limit)

        if (youtubeMovies.length === 0) {
            return res.json({
                success: true,
                imported: 0,
                skipped: 0,
                message: 'No movies found in channel'
            })
        }

        // Import to staging table
        const imported = []
        const skipped = []

        for (const movie of youtubeMovies) {
            // Check if already in staging (pending)
            const { data: existing } = await supabase
                .from('staged_movies')
                .select('id')
                .eq('youtube_video_id', movie.youtubeVideoId)
                .eq('approval_status', 'pending')
                .single()

            if (existing) {
                skipped.push(movie.youtubeVideoId)
                continue
            }

            // Insert to staging
            const { data, error } = await supabase
                .from('staged_movies')
                .insert({
                    youtube_video_id: movie.youtubeVideoId,
                    youtube_video_title: movie.title,
                    title: movie.cleanTitle || movie.title,
                    channel_id: movie.channelId,
                    description: movie.description,
                    published_at: movie.publishedAt,
                    view_count: movie.viewCount,
                    like_count: movie.likeCount,
                    comment_count: movie.commentCount,
                    approval_status: 'pending',
                    import_batch_id: batchId
                })
                .select()
                .single()

            if (error) {
                logger.error(`Failed to import ${movie.youtubeVideoId}:`, error)
                skipped.push(movie.youtubeVideoId)
            } else {
                imported.push(data)
            }
        }

        res.json({
            success: true,
            imported: imported.length,
            skipped: skipped.length,
            batchId,
            movies: imported
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// 2. LIST/FILTER STAGED MOVIES
// =============================================================================

/**
 * List staged movies with filters
 * GET /api/staging/movies?status=pending&enriched=false&limit=50&offset=0
 */
router.get('/movies', async (req, res, next) => {
    try {
        const {
            status = 'pending',
            enriched = null,
            channelId = null,
            batchId = null,
            limit = 50,
            offset = 0
        } = req.query

        let query = supabase
            .from('staged_movies')
            .select(`
                *,
                channels!inner(id, title)
            `)
            .order('created_at', { ascending: false })
            .range(offset, offset + limit - 1)

        // Filter by status
        if (status) {
            query = query.eq('approval_status', status)
        }

        // Filter by enrichment status
        if (enriched === 'true') {
            query = query.not('tmdb_id', 'is', null).or('imdb_id.not.is.null')
        } else if (enriched === 'false') {
            query = query.is('tmdb_id', null).is('imdb_id', null)
        }

        // Filter by channel
        if (channelId) {
            query = query.eq('channel_id', channelId)
        }

        // Filter by batch
        if (batchId) {
            query = query.eq('import_batch_id', batchId)
        }

        const { data, error, count } = await query

        if (error) throw error

        res.json({
            success: true,
            movies: data,
            count: data.length,
            offset: parseInt(offset),
            limit: parseInt(limit)
        })

    } catch (error) {
        next(error)
    }
})

/**
 * Get single staged movie
 * GET /api/staging/movies/:id
 */
router.get('/movies/:id', async (req, res, next) => {
    try {
        const { id } = req.params

        const { data, error } = await supabase
            .from('staged_movies')
            .select(`
                *,
                channels(id, title)
            `)
            .eq('id', id)
            .single()

        if (error) throw error
        if (!data) {
            return res.status(404).json({ error: 'Staged movie not found' })
        }

        res.json({
            success: true,
            movie: data
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// 3. PREVIEW ENRICHMENT (TEST MODE)
// =============================================================================

/**
 * Preview enrichment without saving
 * POST /api/staging/movies/:id/preview-enrichment
 * Body: { priority, fields, preferTmdb }
 */
router.post('/movies/:id/preview-enrichment', async (req, res, next) => {
    try {
        const { id } = req.params
        const {
            priority = 'full',
            fields = null,
            preferTmdb = true
        } = req.body

        // Get staged movie
        const { data: stagedMovie, error } = await supabase
            .from('staged_movies')
            .select('*, channels(title)')
            .eq('id', id)
            .single()

        if (error) throw error
        if (!stagedMovie) {
            return res.status(404).json({ error: 'Staged movie not found' })
        }

        // Extract title and actors from YouTube title using channel pattern
        const { cleanTitle, actors, year } = await enhancedEnrichment.extractTitleInfo(
            stagedMovie.youtube_video_title,
            stagedMovie.channels.title
        )

        // Preview enrichment (previewOnly: true)
        const result = await selectiveEnrichment.enrichSelective(
            {
                title: cleanTitle || stagedMovie.title,
                actors,
                year
            },
            {
                priority,
                fields,
                preferTmdb,
                previewOnly: true,
                respectManual: true,
                manualChanges: stagedMovie.manual_changes
            }
        )

        // Save preview to staged_movies.enrichment_preview
        if (result.success) {
            await supabase
                .from('staged_movies')
                .update({
                    enrichment_preview: {
                        ...result.preview,
                        confidence: result.confidence,
                        source: result.source,
                        timestamp: new Date().toISOString(),
                        fieldsEnriched: result.fieldsEnriched,
                        fieldsSkipped: result.fieldsSkipped
                    }
                })
                .eq('id', id)
        }

        res.json({
            success: true,
            preview: result
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// 4. APPLY ENRICHMENT
// =============================================================================

/**
 * Apply enrichment to staged movie
 * POST /api/staging/movies/:id/enrich
 * Body: { priority, fields, preferTmdb, applyFromPreview }
 */
router.post('/movies/:id/enrich', async (req, res, next) => {
    try {
        const { id } = req.params
        const {
            priority = 'full',
            fields = null,
            preferTmdb = true,
            applyFromPreview = false
        } = req.body

        // Get staged movie
        const { data: stagedMovie, error } = await supabase
            .from('staged_movies')
            .select('*, channels(title)')
            .eq('id', id)
            .single()

        if (error) throw error
        if (!stagedMovie) {
            return res.status(404).json({ error: 'Staged movie not found' })
        }

        let enrichmentData

        // Option 1: Apply from existing preview
        if (applyFromPreview && stagedMovie.enrichment_preview) {
            enrichmentData = stagedMovie.enrichment_preview
        }
        // Option 2: Run fresh enrichment
        else {
            const { cleanTitle, actors, year } = await enhancedEnrichment.extractTitleInfo(
                stagedMovie.youtube_video_title,
                stagedMovie.channels.title
            )

            const result = await selectiveEnrichment.enrichSelective(
                {
                    title: cleanTitle || stagedMovie.title,
                    actors,
                    year
                },
                {
                    priority,
                    fields,
                    preferTmdb,
                    previewOnly: false,
                    respectManual: true,
                    manualChanges: stagedMovie.manual_changes
                }
            )

            if (!result.success) {
                return res.status(400).json({
                    success: false,
                    message: result.message
                })
            }

            enrichmentData = result.preview
        }

        // Apply enrichment to staged movie
        const { data: updated, error: updateError } = await supabase
            .from('staged_movies')
            .update(enrichmentData)
            .eq('id', id)
            .select()
            .single()

        if (updateError) throw updateError

        res.json({
            success: true,
            movie: updated
        })

    } catch (error) {
        next(error)
    }
})

/**
 * Batch enrich staged movies
 * POST /api/staging/enrich-batch
 * Body: { ids, priority, fields }
 */
router.post('/enrich-batch', async (req, res, next) => {
    try {
        const { ids, priority = 'full', fields = null } = req.body

        if (!ids || !Array.isArray(ids)) {
            return res.status(400).json({ error: 'ids array required' })
        }

        const results = []

        for (const id of ids) {
            try {
                const { data: stagedMovie } = await supabase
                    .from('staged_movies')
                    .select('*, channels(title)')
                    .eq('id', id)
                    .single()

                if (!stagedMovie) continue

                const { cleanTitle, actors, year } = await enhancedEnrichment.extractTitleInfo(
                    stagedMovie.youtube_video_title,
                    stagedMovie.channels.title
                )

                const result = await selectiveEnrichment.enrichSelective(
                    { title: cleanTitle || stagedMovie.title, actors, year },
                    { priority, fields, respectManual: true, manualChanges: stagedMovie.manual_changes }
                )

                if (result.success) {
                    await supabase
                        .from('staged_movies')
                        .update(result.preview)
                        .eq('id', id)

                    results.push({ id, success: true, confidence: result.confidence })
                } else {
                    results.push({ id, success: false, message: result.message })
                }
            } catch (error) {
                results.push({ id, success: false, error: error.message })
            }
        }

        res.json({
            success: true,
            results,
            enriched: results.filter(r => r.success).length,
            failed: results.filter(r => !r.success).length
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// 5. MANUAL EDITING
// =============================================================================

/**
 * Update staged movie (manual edits)
 * PATCH /api/staging/movies/:id
 * Body: { title, description, poster_path, release_date, etc. }
 */
router.patch('/movies/:id', async (req, res, next) => {
    try {
        const { id } = req.params
        const updates = req.body

        // Update staged movie
        const { data, error } = await supabase
            .from('staged_movies')
            .update(updates)
            .eq('id', id)
            .select()
            .single()

        if (error) throw error

        res.json({
            success: true,
            movie: data
        })

    } catch (error) {
        next(error)
    }
})

/**
 * Add notes to staged movie
 * POST /api/staging/movies/:id/notes
 * Body: { notes }
 */
router.post('/movies/:id/notes', async (req, res, next) => {
    try {
        const { id } = req.params
        const { notes } = req.body

        const { data, error } = await supabase
            .from('staged_movies')
            .update({ notes })
            .eq('id', id)
            .select()
            .single()

        if (error) throw error

        res.json({
            success: true,
            movie: data
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// 6. APPROVAL WORKFLOW
// =============================================================================

/**
 * Approve staged movie
 * POST /api/staging/movies/:id/approve
 */
router.post('/movies/:id/approve', async (req, res, next) => {
    try {
        const { id } = req.params

        const { data, error } = await supabase
            .from('staged_movies')
            .update({
                approval_status: 'approved',
                approved_at: new Date().toISOString(),
                approved_by: 'admin' // TODO: Get from auth
            })
            .eq('id', id)
            .select()
            .single()

        if (error) throw error

        res.json({
            success: true,
            movie: data
        })

    } catch (error) {
        next(error)
    }
})

/**
 * Reject staged movie
 * POST /api/staging/movies/:id/reject
 * Body: { reason }
 */
router.post('/movies/:id/reject', async (req, res, next) => {
    try {
        const { id } = req.params
        const { reason } = req.body

        const { data, error } = await supabase
            .from('staged_movies')
            .update({
                approval_status: 'rejected',
                rejected_reason: reason
            })
            .eq('id', id)
            .select()
            .single()

        if (error) throw error

        res.json({
            success: true,
            movie: data
        })

    } catch (error) {
        next(error)
    }
})

/**
 * Bulk approve
 * POST /api/staging/approve-batch
 * Body: { ids }
 */
router.post('/approve-batch', async (req, res, next) => {
    try {
        const { ids } = req.body

        if (!ids || !Array.isArray(ids)) {
            return res.status(400).json({ error: 'ids array required' })
        }

        const { data, error } = await supabase
            .from('staged_movies')
            .update({
                approval_status: 'approved',
                approved_at: new Date().toISOString(),
                approved_by: 'admin'
            })
            .in('id', ids)
            .select()

        if (error) throw error

        res.json({
            success: true,
            approved: data.length,
            movies: data
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// 7. PUBLISH TO PRODUCTION
// =============================================================================

/**
 * Publish approved movies to production
 * POST /api/staging/publish
 * Body: { ids } - optional, publishes all approved if not provided
 */
router.post('/publish', async (req, res, next) => {
    try {
        const { ids = null } = req.body

        // Get approved movies
        let query = supabase
            .from('staged_movies')
            .select('*')
            .eq('approval_status', 'approved')

        if (ids && Array.isArray(ids)) {
            query = query.in('id', ids)
        }

        const { data: approvedMovies, error } = await query

        if (error) throw error

        if (approvedMovies.length === 0) {
            return res.json({
                success: true,
                published: 0,
                message: 'No approved movies to publish'
            })
        }

        const published = []
        const failed = []

        for (const stagedMovie of approvedMovies) {
            try {
                // Check if already exists in production
                const { data: existing } = await supabase
                    .from('movies')
                    .select('id')
                    .eq('youtube_video_id', stagedMovie.youtube_video_id)
                    .single()

                let productionMovie

                if (existing) {
                    // Update existing
                    const { data, error: updateError } = await supabase
                        .from('movies')
                        .update({
                            title: stagedMovie.title,
                            description: stagedMovie.description,
                            poster_path: stagedMovie.poster_path,
                            tmdb_id: stagedMovie.tmdb_id,
                            imdb_id: stagedMovie.imdb_id,
                            // ... copy all relevant fields
                        })
                        .eq('id', existing.id)
                        .select()
                        .single()

                    if (updateError) throw updateError
                    productionMovie = data
                } else {
                    // Insert new
                    const { data, error: insertError } = await supabase
                        .from('movies')
                        .insert({
                            youtube_video_id: stagedMovie.youtube_video_id,
                            youtube_video_title: stagedMovie.youtube_video_title,
                            title: stagedMovie.title,
                            description: stagedMovie.description,
                            channel_id: stagedMovie.channel_id,
                            poster_path: stagedMovie.poster_path,
                            backdrop_path: stagedMovie.backdrop_path,
                            release_date: stagedMovie.release_date,
                            runtime_minutes: stagedMovie.runtime_minutes,
                            tmdb_id: stagedMovie.tmdb_id,
                            imdb_id: stagedMovie.imdb_id,
                            enrichment_source: stagedMovie.enrichment_source,
                            enrichment_confidence: stagedMovie.enrichment_confidence,
                            vote_average: stagedMovie.vote_average,
                            vote_count: stagedMovie.vote_count,
                            imdb_rating: stagedMovie.imdb_rating,
                            imdb_votes: stagedMovie.imdb_votes,
                            director: stagedMovie.director,
                            actors: stagedMovie.actors,
                            language: stagedMovie.language,
                            country: stagedMovie.country,
                            rated: stagedMovie.rated,
                            is_tv_show: stagedMovie.is_tv_show,
                            view_count: stagedMovie.view_count,
                            like_count: stagedMovie.like_count,
                            comment_count: stagedMovie.comment_count,
                            published_at: stagedMovie.published_at
                        })
                        .select()
                        .single()

                    if (insertError) throw insertError
                    productionMovie = data
                }

                // Update staged movie with published reference
                await supabase
                    .from('staged_movies')
                    .update({ published_movie_id: productionMovie.id })
                    .eq('id', stagedMovie.id)

                published.push(productionMovie.id)

            } catch (error) {
                logger.error(`Failed to publish ${stagedMovie.id}:`, error)
                failed.push({ id: stagedMovie.id, error: error.message })
            }
        }

        res.json({
            success: true,
            published: published.length,
            failed: failed.length,
            publishedIds: published,
            errors: failed
        })

    } catch (error) {
        next(error)
    }
})

/**
 * Delete staged movie
 * DELETE /api/staging/movies/:id
 */
router.delete('/movies/:id', async (req, res, next) => {
    try {
        const { id } = req.params

        logger.info(`🗑️ [Delete Staged Movie] Attempting to delete movie: ${id}`)

        // First, check if the movie exists
        const { data: existingMovie, error: fetchError } = await supabase
            .from('staged_movies')
            .select('id, title, youtube_video_title, approval_status')
            .eq('id', id)
            .single()

        if (fetchError) {
            logger.error(`❌ [Delete Staged Movie] Error fetching movie ${id}:`, {
                error: fetchError.message,
                code: fetchError.code,
                details: fetchError.details,
                hint: fetchError.hint
            })
            throw fetchError
        }

        if (!existingMovie) {
            logger.warn(`⚠️ [Delete Staged Movie] Movie not found: ${id}`)
            return res.status(404).json({
                success: false,
                error: 'Movie not found'
            })
        }

        logger.info(`📋 [Delete Staged Movie] Found movie:`, {
            id: existingMovie.id,
            title: existingMovie.title,
            youtube_title: existingMovie.youtube_video_title,
            status: existingMovie.approval_status
        })

        // Attempt deletion
        const { error: deleteError } = await supabase
            .from('staged_movies')
            .delete()
            .eq('id', id)

        if (deleteError) {
            logger.error(`❌ [Delete Staged Movie] Deletion failed for ${id}:`, {
                error: deleteError.message,
                code: deleteError.code,
                details: deleteError.details,
                hint: deleteError.hint
            })
            throw deleteError
        }

        logger.info(`✅ [Delete Staged Movie] Successfully deleted: ${existingMovie.title}`)

        res.json({
            success: true,
            message: 'Staged movie deleted'
        })

    } catch (error) {
        logger.error(`💥 [Delete Staged Movie] Unexpected error:`, {
            message: error.message,
            stack: error.stack
        })
        next(error)
    }
})

/**
 * Get staging stats
 * GET /api/staging/stats
 */
router.get('/stats', async (req, res, next) => {
    try {
        // Count by status
        const { data: statusCounts } = await supabase
            .from('staged_movies')
            .select('approval_status')

        const stats = {
            pending: statusCounts.filter(m => m.approval_status === 'pending').length,
            approved: statusCounts.filter(m => m.approval_status === 'approved').length,
            rejected: statusCounts.filter(m => m.approval_status === 'rejected').length
        }

        // Count enriched vs unenriched
        const { data: enrichmentCounts } = await supabase
            .from('staged_movies')
            .select('tmdb_id, imdb_id')
            .eq('approval_status', 'pending')

        stats.enriched = enrichmentCounts.filter(m => m.tmdb_id || m.imdb_id).length
        stats.unenriched = enrichmentCounts.filter(m => !m.tmdb_id && !m.imdb_id).length

        res.json({
            success: true,
            stats
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// BATCH ENRICHMENT
// =============================================================================

/**
 * POST /api/staging/batch-enrich
 * Enrich multiple staged movies
 */
router.post('/batch-enrich', async (req, res, next) => {
    try {
        const { movieIds, priority = 'full' } = req.body

        if (!movieIds || !Array.isArray(movieIds) || movieIds.length === 0) {
            return res.status(400).json({
                success: false,
                error: 'movieIds array is required'
            })
        }

        logger.info(`📦 [Batch Enrich] Starting batch enrichment for ${movieIds.length} movies`)

        const results = {
            total: movieIds.length,
            enriched: 0,
            failed: 0,
            skipped: 0,
            details: []
        }

        for (const movieId of movieIds) {
            try {
                // Fetch movie data
                const { data: movie, error: fetchError } = await supabase
                    .from('staged_movies')
                    .select('*')
                    .eq('id', movieId)
                    .single()

                if (fetchError || !movie) {
                    logger.error(`❌ [Batch Enrich] Movie ${movieId} not found`)
                    results.failed++
                    results.details.push({
                        movieId,
                        success: false,
                        error: 'Movie not found'
                    })
                    continue
                }

                logger.info(`🔍 [Batch Enrich] Enriching: "${movie.title}" (${movieId})`)

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
                        last_enriched: new Date().toISOString(),
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
                        logger.error(`❌ [Batch Enrich] Update failed for ${movie.title}:`, updateError)
                        results.failed++
                        results.details.push({
                            movieId,
                            title: movie.title,
                            success: false,
                            error: updateError.message
                        })
                    } else {
                        logger.info(`✅ [Batch Enrich] Enriched: ${movie.title} (${enrichResult.fieldsEnriched?.length || 0} fields from ${enrichResult.source})`)
                        results.enriched++
                        results.details.push({
                            movieId,
                            title: movie.title,
                            success: true,
                            source: enrichResult.source,
                            confidence: enrichResult.confidence,
                            fieldsEnriched: enrichResult.fieldsEnriched?.length || 0
                        })
                    }
                } else {
                    logger.warn(`⚠️ [Batch Enrich] No enrichment data for ${movie.title}: ${enrichResult.message}`)
                    results.skipped++
                    results.details.push({
                        movieId,
                        title: movie.title,
                        success: false,
                        skipped: true,
                        reason: enrichResult.message
                    })
                }

            } catch (movieError) {
                logger.error(`💥 [Batch Enrich] Error enriching ${movieId}:`, movieError)
                results.failed++
                results.details.push({
                    movieId,
                    success: false,
                    error: movieError.message
                })
            }
        }

        logger.info(`📦 [Batch Enrich] Complete: ${results.enriched} enriched, ${results.failed} failed, ${results.skipped} skipped`)

        res.json({
            success: true,
            data: results,
            message: `Enriched ${results.enriched} of ${results.total} movies`
        })

    } catch (error) {
        logger.error('[Batch Enrich] Error:', error)
        next(error)
    }
})

export default router
