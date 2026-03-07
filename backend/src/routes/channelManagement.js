import express from 'express'
import { supabase } from '../config/database.js'
import { youtubeService } from '../services/youtubeService.js'
import { movieCurator } from '../services/movieCurator.js'
import { selectiveEnrichment } from '../services/selectiveEnrichment.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// Strip emojis from text fields on import
function stripEmojis(text) {
    if (!text) return text
    return text
        .replace(/[\u{1F600}-\u{1F64F}]/gu, '')
        .replace(/[\u{1F300}-\u{1F5FF}]/gu, '')
        .replace(/[\u{1F680}-\u{1F6FF}]/gu, '')
        .replace(/[\u{1F1E0}-\u{1F1FF}]/gu, '')
        .replace(/[\u{2600}-\u{26FF}]/gu, '')
        .replace(/[\u{2700}-\u{27BF}]/gu, '')
        .replace(/[\u{1F900}-\u{1F9FF}]/gu, '')
        .replace(/[\u{1FA00}-\u{1FA6F}]/gu, '')
        .replace(/[\u{1FA70}-\u{1FAFF}]/gu, '')
        .replace(/[\u{FE00}-\u{FE0F}]/gu, '')   // Variation selectors
        .replace(/[\u{1F004}]/gu, '')
        .replace(/\s{2,}/g, ' ')
        .trim()
}

// =============================================================================
// CHANNEL SETTINGS CRUD
// =============================================================================

/**
 * GET /api/admin/channels/:channelId/settings
 * Get channel settings (creates default if not exists)
 */
router.get('/:channelId/settings', async (req, res, next) => {
    try {
        const { channelId } = req.params

        // Get or create default settings
        let { data: settings, error } = await supabase
            .from('channel_settings')
            .select('*')
            .eq('channel_id', channelId)
            .single()

        if (error && error.code === 'PGRST116') {
            // Settings don't exist, create defaults
            const { data: newSettings, error: insertError } = await supabase
                .from('channel_settings')
                .insert({
                    channel_id: channelId,
                    auto_import_enabled: false,
                    import_limit: 50,
                    import_sort_order: 'latest',
                    default_enrichment_priority: 'standard',
                    auto_enrich_on_import: false,
                    require_manual_review: true,
                    quality_tier: 'standard'
                })
                .select()
                .single()

            if (insertError) throw insertError
            settings = newSettings
        } else if (error) {
            throw error
        }

        res.json({
            success: true,
            data: settings
        })
    } catch (error) {
        logger.error('[Channel Settings] Get error:', error)
        next(error)
    }
})

/**
 * PUT /api/admin/channels/:channelId/settings
 * Update channel settings
 */
router.put('/:channelId/settings', async (req, res, next) => {
    try {
        const { channelId } = req.params
        const updates = req.body

        // Validate allowed fields
        const allowedFields = [
            'auto_import_enabled', 'auto_import_schedule', 'import_limit', 'import_sort_order',
            'default_enrichment_priority', 'auto_enrich_on_import',
            'auto_approve_threshold', 'require_manual_review',
            'channel_tag', 'is_featured', 'quality_tier',
            'min_duration_minutes', 'max_duration_minutes', 'filter_shorts',
            'is_kids_content', 'is_tv_series_channel'
        ]

        const cleanUpdates = {}
        allowedFields.forEach(field => {
            if (updates[field] !== undefined) {
                cleanUpdates[field] = updates[field]
            }
        })

        const { data: settings, error } = await supabase
            .from('channel_settings')
            .upsert({
                channel_id: channelId,
                ...cleanUpdates
            })
            .select()
            .single()

        if (error) throw error

        logger.info(`[Channel Settings] Updated settings for ${channelId}`)

        res.json({
            success: true,
            data: settings,
            message: 'Channel settings updated successfully'
        })
    } catch (error) {
        logger.error('[Channel Settings] Update error:', error)
        next(error)
    }
})

// =============================================================================
// BULK IMPORT OPERATIONS
// =============================================================================

/**
 * POST /api/admin/channels/:channelId/import-all
 * Import all or limited videos from channel
 */
router.post('/:channelId/import-all', async (req, res, next) => {
    try {
        const { channelId } = req.params

        logger.info(`🚀 [Bulk Import] ========== IMPORT REQUEST RECEIVED ==========`)
        logger.info(`🚀 [Bulk Import] Channel ID: ${channelId}`)
        logger.info(`🚀 [Bulk Import] Raw request body:`, req.body)

        const {
            limit = null,
            sortOrder = 'latest',
            applySettings = true,
            autoEnrich = false
        } = req.body

        logger.info(`🚀 [Bulk Import] Parsed parameters:`, {
            limit,
            sortOrder,
            applySettings,
            autoEnrich,
            autoEnrichType: typeof autoEnrich,
            autoEnrichRaw: req.body.autoEnrich
        })

        logger.info(`[Bulk Import] Starting import for ${channelId}, limit: ${limit || 'ALL'}, sort: ${sortOrder}, autoEnrich: ${autoEnrich}`)

        // Get channel info
        const { data: channel } = await supabase
            .from('channels')
            .select('title')
            .eq('id', channelId)
            .single()

        if (!channel) {
            return res.status(404).json({
                success: false,
                error: 'Channel not found'
            })
        }

        // Get channel settings if applying
        let channelSettings = null
        if (applySettings) {
            const { data: settings } = await supabase
                .from('channel_settings')
                .select('*')
                .eq('channel_id', channelId)
                .single()
            channelSettings = settings
        }

        // Create import history record
        const { data: importRecord, error: importError } = await supabase
            .from('import_history')
            .insert({
                channel_id: channelId,
                import_type: limit ? 'partial' : 'full',
                import_limit: limit,
                sort_order: sortOrder,
                status: 'running',
                applied_settings: channelSettings,
                auto_enriched: autoEnrich
            })
            .select()
            .single()

        if (importError) throw importError

        // Start import process asynchronously
        processImport(importRecord.id, channelId, channel.title, limit, sortOrder, channelSettings, autoEnrich)
            .catch(error => {
                logger.error('[Bulk Import] Process error:', error)
            })

        res.json({
            success: true,
            data: {
                batchId: importRecord.id,
                status: 'running',
                message: `Import started for ${channel.title}`
            }
        })
    } catch (error) {
        logger.error('[Bulk Import] Start error:', error)
        next(error)
    }
})

/**
 * POST /api/admin/channels/:channelId/import-latest
 * Import latest N videos from channel
 */
router.post('/:channelId/import-latest', async (req, res, next) => {
    try {
        const { channelId } = req.params
        const {
            limit = 20,
            sortOrder = 'latest',
            applySettings = true
        } = req.body

        // Reuse import-all logic
        req.body.limit = limit
        req.body.sortOrder = sortOrder
        req.body.applySettings = applySettings

        return router.handle({ ...req, url: `/${channelId}/import-all`, method: 'POST' }, res, next)
    } catch (error) {
        next(error)
    }
})

/**
 * GET /api/admin/imports/:batchId/status
 * Get import progress status
 */
router.get('/imports/:batchId/status', async (req, res, next) => {
    try {
        const { batchId } = req.params

        const { data: importRecord, error } = await supabase
            .from('import_history')
            .select('*, channels(title)')
            .eq('id', batchId)
            .single()

        if (error) throw error

        if (!importRecord) {
            return res.status(404).json({
                success: false,
                error: 'Import not found'
            })
        }

        const progress = {
            status: importRecord.status,
            found: importRecord.videos_found || 0,
            imported: importRecord.videos_imported || 0,
            skipped: importRecord.videos_skipped || 0,
            failed: importRecord.videos_failed || 0,
            current: importRecord.current_video_title,
            currentIndex: importRecord.current_video_index,
            channelTitle: importRecord.channels?.title
        }

        // Calculate percentage
        if (progress.found > 0) {
            progress.percentage = Math.round(
                ((progress.imported + progress.skipped + progress.failed) / progress.found) * 100
            )
        }

        res.json({
            success: true,
            data: progress
        })
    } catch (error) {
        logger.error('[Import Status] Error:', error)
        next(error)
    }
})

// =============================================================================
// BATCH OPERATIONS
// =============================================================================

/**
 * DELETE /api/admin/channels/:channelId/movies
 * Delete all movies from a channel
 */
router.delete('/:channelId/movies', async (req, res, next) => {
    try {
        const { channelId } = req.params
        const { deleteFrom = 'staging,production' } = req.query

        logger.info(`🗑️ [Bulk Delete] Starting bulk delete for channel: ${channelId}`, {
            deleteFrom,
            sources: deleteFrom.split(',').map(s => s.trim())
        })

        const sources = deleteFrom.split(',').map(s => s.trim())
        const results = {}

        // Delete from staging
        if (sources.includes('staging')) {
            logger.info(`📋 [Bulk Delete] Checking staged movies for channel: ${channelId}`)

            const { data: stagedMovies, error: fetchError } = await supabase
                .from('staged_movies')
                .select('id')
                .eq('channel_id', channelId)

            if (fetchError) {
                logger.error(`❌ [Bulk Delete] Error fetching staged movies:`, {
                    error: fetchError.message,
                    code: fetchError.code,
                    details: fetchError.details
                })
                throw fetchError
            }

            if (stagedMovies && stagedMovies.length > 0) {
                logger.info(`🗑️ [Bulk Delete] Deleting ${stagedMovies.length} staged movies`)

                const { error: deleteError } = await supabase
                    .from('staged_movies')
                    .delete()
                    .eq('channel_id', channelId)

                if (deleteError) {
                    logger.error(`❌ [Bulk Delete] Error deleting staged movies:`, {
                        error: deleteError.message,
                        code: deleteError.code,
                        details: deleteError.details
                    })
                    throw deleteError
                }

                logger.info(`✅ [Bulk Delete] Deleted ${stagedMovies.length} staged movies`)
                results.deletedFromStaging = stagedMovies.length
            } else {
                logger.info(`ℹ️ [Bulk Delete] No staged movies found for channel`)
                results.deletedFromStaging = 0
            }
        }

        // Delete from production
        if (sources.includes('production')) {
            // First delete relationships
            await supabase
                .from('movie_genres')
                .delete()
                .in('movie_id', supabase
                    .from('movies')
                    .select('id')
                    .eq('channel_id', channelId)
                )

            const { data: movies } = await supabase
                .from('movies')
                .select('id')
                .eq('channel_id', channelId)

            if (movies && movies.length > 0) {
                const { error } = await supabase
                    .from('movies')
                    .delete()
                    .eq('channel_id', channelId)

                if (error) throw error
                results.deletedFromProduction = movies.length
            } else {
                results.deletedFromProduction = 0
            }
        }

        logger.info(`[Batch Delete] Deleted movies from ${channelId}:`, results)

        res.json({
            success: true,
            data: results,
            message: `Deleted ${(results.deletedFromStaging || 0) + (results.deletedFromProduction || 0)} movies`
        })
    } catch (error) {
        logger.error('[Batch Delete] Error:', error)
        next(error)
    }
})

/**
 * POST /api/admin/channels/:channelId/reimport
 * Delete and re-import all movies from channel
 */
router.post('/:channelId/reimport', async (req, res, next) => {
    try {
        const { channelId } = req.params
        const {
            deleteExisting = true,
            applySettings = true,
            limit = null
        } = req.body

        // Delete existing if requested
        if (deleteExisting) {
            await supabase
                .from('staged_movies')
                .delete()
                .eq('channel_id', channelId)

            await supabase
                .from('movies')
                .delete()
                .eq('channel_id', channelId)

            logger.info(`[Reimport] Deleted existing movies from ${channelId}`)
        }

        // Trigger new import
        req.body = { limit, applySettings, sortOrder: 'latest' }
        return router.handle({ ...req, url: `/${channelId}/import-all`, method: 'POST' }, res, next)
    } catch (error) {
        logger.error('[Reimport] Error:', error)
        next(error)
    }
})

/**
 * GET /api/admin/channels/:channelId/movies
 * List all movies from channel (staging + production)
 */
router.get('/:channelId/movies', async (req, res, next) => {
    try {
        const { channelId } = req.params
        const { source = 'staging,production', page = 1, limit = 50 } = req.query

        const sources = source.split(',').map(s => s.trim())
        const offset = (page - 1) * limit
        const results = {}

        // Get staging movies
        if (sources.includes('staging')) {
            const { data: stagedMovies, count } = await supabase
                .from('staged_movies')
                .select('*', { count: 'exact' })
                .eq('channel_id', channelId)
                .order('created_at', { ascending: false })
                .range(offset, offset + limit - 1)

            results.staging = {
                movies: stagedMovies || [],
                total: count || 0
            }
        }

        // Get production movies
        if (sources.includes('production')) {
            const { data: movies, count } = await supabase
                .from('movies')
                .select('*', { count: 'exact' })
                .eq('channel_id', channelId)
                .order('created_at', { ascending: false })
                .range(offset, offset + limit - 1)

            // Add approval_status field for Swift compatibility
            const moviesWithStatus = (movies || []).map(movie => ({
                ...movie,
                approval_status: 'approved' // Production movies are always approved
            }))

            results.production = {
                movies: moviesWithStatus,
                total: count || 0
            }
        }

        res.json({
            success: true,
            data: results,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit)
            }
        })
    } catch (error) {
        logger.error('[Channel Movies] Error:', error)
        next(error)
    }
})

// =============================================================================
// IMPORT HISTORY
// =============================================================================

/**
 * GET /api/admin/channels/:channelId/import-history
 * Get import history for channel
 */
router.get('/:channelId/import-history', async (req, res, next) => {
    try {
        const { channelId } = req.params
        const { limit = 20 } = req.query

        const { data: imports, error } = await supabase
            .from('import_history')
            .select('*')
            .eq('channel_id', channelId)
            .order('started_at', { ascending: false })
            .limit(limit)

        if (error) throw error

        res.json({
            success: true,
            data: {
                imports: imports || [],
                total: imports?.length || 0
            }
        })
    } catch (error) {
        logger.error('[Import History] Error:', error)
        next(error)
    }
})

// =============================================================================
// IMPORT PROCESSING (Background)
// =============================================================================

async function processImport(importId, channelId, channelTitle, limit, sortOrder, channelSettings, autoEnrich) {
    try {
        logger.info(`[Import Process] Starting ${importId} for ${channelTitle}`)

        // Update status to running
        await supabase
            .from('import_history')
            .update({ status: 'running' })
            .eq('id', importId)

        // Fetch videos from YouTube with sort order
        const fetchOptions = {
            maxResults: limit || 500,
            fetchDetails: true
        }

        // Apply sort order
        if (sortOrder === 'latest' || sortOrder === 'oldest') {
            fetchOptions.order = sortOrder === 'latest' ? 'date' : 'date_asc'
        }

        const videos = await youtubeService.getChannelVideos(channelId, fetchOptions)

        // Apply additional sorting if needed
        if (sortOrder === 'alphabetical_az') {
            videos.sort((a, b) => a.title.localeCompare(b.title))
        } else if (sortOrder === 'alphabetical_za') {
            videos.sort((a, b) => b.title.localeCompare(a.title))
        } else if (sortOrder === 'views') {
            videos.sort((a, b) => (b.viewCount || 0) - (a.viewCount || 0))
        }

        // Apply duration filters if set
        let filteredVideos = videos
        if (channelSettings) {
            const { min_duration_minutes, max_duration_minutes, filter_shorts } = channelSettings

            filteredVideos = videos.filter(video => {
                // Parse duration to minutes
                const durationMinutes = movieCurator.parseDuration(video.duration)

                // Filter shorts (< 1 minute)
                if (filter_shorts && durationMinutes < 1) {
                    logger.debug(`[Import Filter] Filtering short: ${video.title} (${durationMinutes} min)`)
                    return false
                }

                // Filter by minimum duration
                if (min_duration_minutes && durationMinutes < min_duration_minutes) {
                    logger.debug(`[Import Filter] Below minimum: ${video.title} (${durationMinutes} < ${min_duration_minutes} min)`)
                    return false
                }

                // Filter by maximum duration
                if (max_duration_minutes && durationMinutes > max_duration_minutes) {
                    logger.debug(`[Import Filter] Above maximum: ${video.title} (${durationMinutes} > ${max_duration_minutes} min)`)
                    return false
                }

                return true
            })

            const filtered = videos.length - filteredVideos.length
            if (filtered > 0) {
                logger.info(`[Import Filter] Filtered ${filtered} videos by duration (${filteredVideos.length} remaining)`)
            }
        }

        // Enforce the requested limit after filtering
        if (limit && filteredVideos.length > limit) {
            logger.info(`[Import Filter] 🎯 Limiting to ${limit} videos (had ${filteredVideos.length} after filtering)`)
            filteredVideos = filteredVideos.slice(0, limit)
        }

        // Update videos found
        await supabase
            .from('import_history')
            .update({ videos_found: filteredVideos.length })
            .eq('id', importId)

        let imported = 0
        let skipped = 0
        let failed = 0

        // Import each video
        for (let i = 0; i < filteredVideos.length; i++) {
            const video = filteredVideos[i]

            try {
                // Update current progress
                await supabase
                    .from('import_history')
                    .update({
                        current_video_title: video.title,
                        current_video_index: i + 1
                    })
                    .eq('id', importId)

                // Check if already exists
                const { data: existing } = await supabase
                    .from('staged_movies')
                    .select('id')
                    .eq('youtube_video_id', video.id)
                    .single()

                if (existing) {
                    skipped++
                    continue
                }

                const { data: inProduction } = await supabase
                    .from('movies')
                    .select('id')
                    .eq('youtube_video_id', video.id)
                    .single()

                if (inProduction) {
                    skipped++
                    continue
                }

                // Extract metadata using channel pattern
                const parsed = await movieCurator.extractMetadata(video.title, channelId)

                // Log pattern extraction results
                logger.info(`[Import] Pattern extraction for "${video.title}":`, {
                    matched: parsed.patternMatched || false,
                    extractedTitle: parsed.title,
                    actor: parsed.actors || parsed.actor || null,
                    genre: parsed.genre || null,
                    year: parsed.year || null,
                    confidence: parsed.confidence || 0
                })

                // Calculate duration
                const durationMinutes = movieCurator.parseDuration(video.duration)

                // Prepare movie data with extracted metadata
                const movieData = {
                    youtube_video_id: video.id,
                    youtube_video_title: stripEmojis(video.title),
                    title: parsed.title || video.title,
                    description: video.description ? stripEmojis(video.description) : video.description,
                    channel_id: channelId,
                    runtime_minutes: Math.round(durationMinutes),
                    view_count: parseInt(video.viewCount) || 0,
                    like_count: parseInt(video.likeCount) || 0,
                    comment_count: parseInt(video.commentCount) || 0,
                    published_at: video.publishedAt,
                    approval_status: 'pending',
                    import_batch_id: importId,
                    import_sort_order: sortOrder,
                    import_index: i,
                    channel_tag: channelSettings?.channel_tag,
                    // Propagate channel-level flags
                    is_tv_series: channelSettings?.is_tv_series_channel || false,
                    is_kids_content: channelSettings?.is_kids_content || false,
                    // Save extracted metadata from pattern
                    pattern_matched: parsed.patternMatched || false,
                    pattern_confidence: parsed.confidence || 0
                }

                // Add extracted actor if present
                if (parsed.actors || parsed.actor) {
                    movieData.extracted_actor = parsed.actors || parsed.actor
                }

                // Add extracted genre if present
                if (parsed.genre) {
                    movieData.extracted_genre = parsed.genre
                }

                // Add extracted year if present
                if (parsed.year) {
                    movieData.extracted_year = parseInt(parsed.year)
                }

                logger.info(`[Import] Saving movie with extracted data:`, {
                    title: movieData.title,
                    actor: movieData.extracted_actor,
                    genre: movieData.extracted_genre,
                    year: movieData.extracted_year,
                    patternMatched: movieData.pattern_matched
                })

                // Create staged movie
                const { data: insertedMovie, error: insertError } = await supabase
                    .from('staged_movies')
                    .insert(movieData)
                    .select()
                    .single()

                if (insertError) {
                    logger.error(`[Import] Failed to insert ${video.id}:`, insertError)
                    failed++
                } else {
                    imported++

                    // Auto-enrich if enabled
                    logger.info(`🔍 [Import] ========== AUTO-ENRICH CHECK ==========`)
                    logger.info(`🔍 [Import] Auto-enrich enabled: ${autoEnrich}`)
                    logger.info(`🔍 [Import] Movie inserted: ${!!insertedMovie}`)

                    if (autoEnrich && insertedMovie) {
                        try {
                            logger.info(`🔍 [Import] ========== STARTING AUTO-ENRICHMENT ==========`)
                            logger.info(`🔍 [Import] Movie: "${movieData.title}"`)
                            logger.info(`🔍 [Import] Extracted data:`, {
                                title: movieData.title,
                                actor: movieData.extracted_actor,
                                genre: movieData.extracted_genre,
                                year: movieData.extracted_year
                            })
                            logger.info(`🔍 [Import] Full context:`, {
                                youtube_video_title: video.title,
                                channel_id: channelId,
                                channel_title: channelTitle,
                                published_at: video.publishedAt
                            })

                            logger.info(`🔍 [Import] Calling selectiveEnrichment.enrichSelective...`)
                            const enrichResult = await selectiveEnrichment.enrichSelective(
                                {
                                    title: movieData.title,
                                    actors: movieData.extracted_actor,
                                    year: movieData.extracted_year,
                                    // Pass full context for enhanced enrichment
                                    youtube_video_title: video.title,
                                    channel_id: channelId,
                                    channel_title: channelTitle,
                                    published_at: video.publishedAt
                                },
                                {
                                    priority: 'full',
                                    previewOnly: false,
                                    preferTmdb: true
                                }
                            )

                            logger.info(`🔍 [Import] Enrichment completed with result:`, {
                                success: enrichResult.success,
                                source: enrichResult.source,
                                confidence: enrichResult.confidence,
                                hasPreview: !!enrichResult.preview,
                                fieldsEnriched: enrichResult.fieldsEnriched?.length || 0,
                                message: enrichResult.message,
                                metadata: enrichResult.metadata
                            })

                            if (enrichResult.success && enrichResult.preview) {
                                // IMPORTANT: Keep pattern extraction fields separate, only add enrichment data
                                const enrichmentUpdate = {
                                    // Enrichment metadata
                                    enrichment_source: enrichResult.source,
                                    tmdb_id: enrichResult.metadata?.tmdb_id,
                                    imdb_id: enrichResult.metadata?.imdb_id,
                                    enrichment_confidence: enrichResult.confidence,
                                    last_enriched: new Date().toISOString(),

                                    // Enriched fields (poster, plot, ratings, etc.) - NOT title or actors
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
                                    // Use enriched actors only if we don't have extracted_actor from pattern
                                    actors: enrichResult.preview.actors,
                                    language: enrichResult.preview.language,
                                    country: enrichResult.preview.country,
                                    category: enrichResult.preview.category
                                }

                                // Remove undefined values
                                Object.keys(enrichmentUpdate).forEach(key =>
                                    enrichmentUpdate[key] === undefined && delete enrichmentUpdate[key]
                                )

                                logger.info(`🔍 [Import] 💾 Preparing to save enrichment data...`)
                                logger.info(`🔍 [Import] 💾 Fields to update:`, Object.keys(enrichmentUpdate))
                                logger.info(`🔍 [Import] 💾 Key values:`, {
                                    enrichment_source: enrichmentUpdate.enrichment_source,
                                    tmdb_id: enrichmentUpdate.tmdb_id,
                                    imdb_id: enrichmentUpdate.imdb_id,
                                    enrichment_confidence: enrichmentUpdate.enrichment_confidence,
                                    has_poster: !!enrichmentUpdate.poster_path,
                                    has_backdrop: !!enrichmentUpdate.backdrop_path,
                                    has_description: !!enrichmentUpdate.description,
                                    has_director: !!enrichmentUpdate.director,
                                    has_actors: !!enrichmentUpdate.actors
                                })

                                logger.info(`🔍 [Import] 💾 Updating staged_movies table for movie ID: ${insertedMovie.id}`)
                                const { error: enrichError } = await supabase
                                    .from('staged_movies')
                                    .update(enrichmentUpdate)
                                    .eq('id', insertedMovie.id)

                                if (enrichError) {
                                    logger.error(`❌ [Import] Database update FAILED for ${movieData.title}:`, {
                                        error: enrichError.message,
                                        code: enrichError.code,
                                        details: enrichError.details
                                    })
                                } else {
                                    logger.info(`✅ [Import] Database update SUCCESS!`)
                                    logger.info(`✅ [Import] Auto-enriched: ${movieData.title}`)
                                    logger.info(`✅ [Import] Enriched ${enrichResult.fieldsEnriched?.length || 0} fields from ${enrichResult.source}`)
                                    logger.info(`🔍 [Import] ========== AUTO-ENRICHMENT COMPLETE ==========`)
                                }
                            } else {
                                logger.warn(`⚠️ [Import] Auto-enrichment did not return valid data`)
                                logger.warn(`⚠️ [Import] Reason: ${enrichResult.message}`)
                                logger.warn(`⚠️ [Import] Success: ${enrichResult.success}, HasPreview: ${!!enrichResult.preview}`)
                                logger.info(`🔍 [Import] ========== AUTO-ENRICHMENT SKIPPED ==========`)
                            }
                        } catch (enrichError) {
                            logger.error(`💥 [Import] Auto-enrichment EXCEPTION for ${movieData.title}:`, {
                                error: enrichError.message,
                                stack: enrichError.stack
                            })
                            logger.info(`🔍 [Import] ========== AUTO-ENRICHMENT FAILED ==========`)
                        }
                    } else if (!autoEnrich) {
                        logger.info(`⏭️ [Import] Auto-enrichment disabled, skipping`)
                        logger.info(`🔍 [Import] ========== AUTO-ENRICHMENT DISABLED ==========`)
                    } else {
                        logger.warn(`⚠️ [Import] Auto-enrich check failed: enabled=${autoEnrich}, hasMovie=${!!insertedMovie}`)
                    }
                }

                // Update progress
                await supabase
                    .from('import_history')
                    .update({
                        videos_imported: imported,
                        videos_skipped: skipped,
                        videos_failed: failed
                    })
                    .eq('id', importId)

            } catch (videoError) {
                logger.error(`[Import] Error processing video ${video.id}:`, videoError)
                failed++
            }
        }

        // Mark as completed
        await supabase
            .from('import_history')
            .update({
                status: 'completed',
                completed_at: new Date().toISOString(),
                videos_imported: imported,
                videos_skipped: skipped,
                videos_failed: failed
            })
            .eq('id', importId)

        logger.info(`[Import Process] Completed ${importId}: ${imported} imported, ${skipped} skipped, ${failed} failed`)

    } catch (error) {
        logger.error(`[Import Process] Fatal error for ${importId}:`, error)

        await supabase
            .from('import_history')
            .update({
                status: 'failed',
                completed_at: new Date().toISOString(),
                error_message: error.message
            })
            .eq('id', importId)
    }
}

export default router
