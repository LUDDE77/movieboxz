import express from 'express'
import { supabase } from '../config/database.js'
import { youtubeService } from '../services/youtubeService.js'
import { movieCurator } from '../services/movieCurator.js'
import { selectiveEnrichment } from '../services/selectiveEnrichment.js'
import { logger } from '../utils/logger.js'
import { adminAuth } from '../middleware/adminAuth.js'
import { buildDurationFilter, VALID_IMPORT_SORTS } from '../utils/importHelpers.js'
import { proposeEpisodeMatch } from '../utils/episodeMatcher.js'
import { maybeAutoApprove, confidenceAsPercent } from './staging-simple.js'
import { normalizeAutoApproveThreshold, parsePositiveIntOrNull } from '../utils/syncValidationHelpers.js'

const router = express.Router()

// Apply admin auth to all channel management routes
router.use(adminAuth)

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

// buildDurationFilter and VALID_IMPORT_SORTS are pure helpers, imported from
// ../utils/importHelpers.js so they can be unit tested without a DB connection.

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

        // Keep channels classification flags in sync with the settings that
        // actually reach imported movies.
        // channel_settings.is_kids_content     -> channels.has_kids_content
        // channel_settings.is_tv_series_channel -> channels.has_series
        const channelsSync = {}
        if (cleanUpdates.is_kids_content !== undefined) {
            channelsSync.has_kids_content = cleanUpdates.is_kids_content
        }
        if (cleanUpdates.is_tv_series_channel !== undefined) {
            channelsSync.has_series = cleanUpdates.is_tv_series_channel
        }
        if (Object.keys(channelsSync).length > 0) {
            const { error: channelsError } = await supabase
                .from('channels')
                .update(channelsSync)
                .eq('id', channelId)
            if (channelsError) {
                logger.error(`[Channel Settings] Failed to sync channels flags for ${channelId}:`, channelsError)
            } else {
                logger.info(`[Channel Settings] Synced channels flags for ${channelId}:`, channelsSync)
            }
        }

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
 * Shared import starter used by import-all, import-latest, reimport and the
 * daily channel auto-sync job. Creates the import_history record and kicks off
 * processImport in the background (or awaits it when waitForCompletion is true,
 * so the auto-sync sweep can run channels sequentially).
 * Returns null if the channel does not exist.
 */
export async function startChannelImport(channelId, { limit = null, sortOrder = 'latest', applySettings = true, autoEnrich = false, waitForCompletion = false } = {}) {
    // Reject unsupported sort orders (e.g. the old fake 'rating') — fall back to 'latest'
    if (!VALID_IMPORT_SORTS.includes(sortOrder)) {
        logger.warn(`[Bulk Import] Unsupported sortOrder '${sortOrder}', falling back to 'latest'`)
        sortOrder = 'latest'
    }

    logger.info(`[Bulk Import] Starting import for ${channelId}, limit: ${limit || 'ALL'}, sort: ${sortOrder}, autoEnrich: ${autoEnrich}`)

    // Sweep any zombie imports left 'running' from a previous crash before starting a new one
    await sweepZombieImports().catch(err => logger.warn('[Bulk Import] Zombie sweep failed:', err.message))

    // Get channel info
    const { data: channel } = await supabase
        .from('channels')
        .select('title, pattern_source')
        .eq('id', channelId)
        .single()

    if (!channel) {
        return null
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

    // Start import process — asynchronously by default, awaited when the caller
    // (channel auto-sync) needs strictly sequential imports
    const importPromise = processImport(importRecord.id, channelId, channel.title, limit, sortOrder, channelSettings, autoEnrich, channel.pattern_source)
        .catch(error => {
            logger.error('[Bulk Import] Process error:', error)
        })

    if (waitForCompletion) {
        await importPromise
    }

    return {
        batchId: importRecord.id,
        channelTitle: channel.title
    }
}

/**
 * POST /api/admin/channel-management/sync-all
 * Body: { limit? }
 *
 * Trigger the daily channel auto-sync sweep on demand: for every channel with
 * channel_settings.auto_import_enabled = true, import the latest N videos
 * (default 25) with settings applied and auto-enrichment on. Fire-and-forget —
 * each channel writes its own import_history row (the summary handle), exactly
 * like manual imports.
 *
 * Response: { success, data: { started: true, channels: n } }
 */
router.post('/sync-all', async (req, res, next) => {
    try {
        // Dynamic import avoids a static circular dependency
        // (jobs/channelAutoSync.js imports startChannelImport from this module)
        const { runChannelAutoSync, getAutoSyncChannels } = await import('../jobs/channelAutoSync.js')

        const limit = parsePositiveIntOrNull(req.body?.limit)
        const channels = await getAutoSyncChannels()

        // Fire-and-forget: channels are processed sequentially in the background
        runChannelAutoSync(limit ? { limit } : {})
            .catch(error => {
                logger.error('[Auto-Sync] On-demand sweep failed:', error)
            })

        logger.info(`[Auto-Sync] On-demand sweep started for ${channels.length} channel(s)${limit ? ` (limit ${limit})` : ''}`)

        res.json({
            success: true,
            data: {
                started: true,
                channels: channels.length
            }
        })
    } catch (error) {
        logger.error('[Auto-Sync] sync-all error:', error)
        next(error)
    }
})

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

        const started = await startChannelImport(channelId, { limit, sortOrder, applySettings, autoEnrich })

        if (!started) {
            return res.status(404).json({
                success: false,
                error: 'Channel not found'
            })
        }

        res.json({
            success: true,
            data: {
                batchId: started.batchId,
                status: 'running',
                message: `Import started for ${started.channelTitle}`
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

        // Reuse import-all logic via the shared starter
        const started = await startChannelImport(channelId, { limit, sortOrder, applySettings })

        if (!started) {
            return res.status(404).json({
                success: false,
                error: 'Channel not found'
            })
        }

        res.json({
            success: true,
            data: {
                batchId: started.batchId,
                status: 'running',
                message: `Import started for ${started.channelTitle}`
            }
        })
    } catch (error) {
        logger.error('[Bulk Import] Start error:', error)
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
            imported_count: importRecord.videos_imported || 0,
            skipped: importRecord.videos_skipped || 0,
            failed: importRecord.videos_failed || 0,
            pattern_match_count: importRecord.pattern_match_count ?? null,
            truncated: importRecord.truncated || false,
            current: importRecord.current_video_title,
            currentIndex: importRecord.current_video_index,
            channelTitle: importRecord.channels?.title,
            errorDetails: importRecord.error_details || null
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

/**
 * POST /api/admin/channel-management/imports/:batchId/cancel
 * Request cancellation of a running import. The processImport loop re-reads the
 * status every ~10 videos and stops cleanly, finalizing counts.
 */
router.post('/imports/:batchId/cancel', async (req, res, next) => {
    try {
        const { batchId } = req.params

        const { data: importRecord, error: fetchError } = await supabase
            .from('import_history')
            .select('id, status')
            .eq('id', batchId)
            .single()

        if (fetchError || !importRecord) {
            return res.status(404).json({
                success: false,
                error: 'Import not found'
            })
        }

        if (importRecord.status !== 'running' && importRecord.status !== 'pending') {
            return res.status(409).json({
                success: false,
                error: `Cannot cancel an import with status '${importRecord.status}'`
            })
        }

        const { error: updateError } = await supabase
            .from('import_history')
            .update({ status: 'cancelled' })
            .eq('id', batchId)

        if (updateError) throw updateError

        logger.info(`[Import Cancel] Marked import ${batchId} as cancelled`)

        res.json({
            success: true,
            message: 'Import cancellation requested'
        })
    } catch (error) {
        logger.error('[Import Cancel] Error:', error)
        next(error)
    }
})

/**
 * Zombie sweeper: mark import_history rows stuck in 'running' for more than
 * 30 minutes as 'failed'. These are imports orphaned by a server restart mid-run.
 * Exported so server.js can call it once at boot, and startChannelImport calls it
 * before every new import.
 */
export async function sweepZombieImports() {
    const cutoff = new Date(Date.now() - 30 * 60 * 1000).toISOString()

    const { data, error } = await supabase
        .from('import_history')
        .update({
            status: 'failed',
            completed_at: new Date().toISOString(),
            error_message: 'server restarted mid-import'
        })
        .eq('status', 'running')
        .lt('started_at', cutoff)
        .select('id')

    if (error) {
        logger.error('[Zombie Sweep] Error:', error)
        return 0
    }

    const swept = data?.length || 0
    if (swept > 0) {
        logger.warn(`[Zombie Sweep] Marked ${swept} stale 'running' import(s) as failed`)
    }
    return swept
}

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
            // Fetch the movie ids first — Supabase JS has no real subquery support,
            // so .in() must receive a concrete array, not a query builder
            const { data: movies, error: moviesFetchError } = await supabase
                .from('movies')
                .select('id')
                .eq('channel_id', channelId)

            if (moviesFetchError) throw moviesFetchError

            if (movies && movies.length > 0) {
                const movieIds = movies.map(m => m.id)

                // First delete relationships
                const { error: genresError } = await supabase
                    .from('movie_genres')
                    .delete()
                    .in('movie_id', movieIds)

                if (genresError) throw genresError

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
            deleteExisting = false,
            applySettings = true,
            limit = null,
            force = false
        } = req.body

        // Delete existing if requested
        if (deleteExisting) {
            // Refuse to wipe production movies unless the caller explicitly forces it
            const { count: prodCount } = await supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .eq('channel_id', channelId)

            if ((prodCount || 0) > 0 && !force) {
                return res.status(409).json({
                    success: false,
                    error: `Reimport would delete ${prodCount} production movie(s) for this channel. Pass force:true to confirm.`,
                    details: { production: prodCount || 0 }
                })
            }

            await supabase
                .from('staged_movies')
                .delete()
                .eq('channel_id', channelId)

            if ((prodCount || 0) > 0 && force) {
                // Clean up genre relationships first (no real subquery support in Supabase JS)
                const { data: prodMovies } = await supabase
                    .from('movies')
                    .select('id')
                    .eq('channel_id', channelId)

                if (prodMovies && prodMovies.length > 0) {
                    await supabase
                        .from('movie_genres')
                        .delete()
                        .in('movie_id', prodMovies.map(m => m.id))
                }

                await supabase
                    .from('movies')
                    .delete()
                    .eq('channel_id', channelId)
            }

            logger.info(`[Reimport] Deleted existing movies from ${channelId} (production removed: ${(prodCount || 0) > 0 && force})`)
        }

        // Trigger new import via the shared starter
        const started = await startChannelImport(channelId, { limit, applySettings, sortOrder: 'latest' })

        if (!started) {
            return res.status(404).json({
                success: false,
                error: 'Channel not found'
            })
        }

        res.json({
            success: true,
            data: {
                batchId: started.batchId,
                status: 'running',
                message: `Import started for ${started.channelTitle}`
            }
        })
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

        // Get staging movies (exclude published — those are already in production)
        if (sources.includes('staging')) {
            const { data: stagedMovies, count } = await supabase
                .from('staged_movies')
                .select('*', { count: 'exact' })
                .eq('channel_id', channelId)
                .neq('approval_status', 'published')
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
                approval_status: 'published' // Production movies are published
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

async function processImport(importId, channelId, channelTitle, limit, sortOrder, channelSettings, autoEnrich, patternSource = 'title') {
    // Track per-video failures for import_history.error_details
    const errorDetails = []
    try {
        logger.info(`[Import Process] Starting ${importId} for ${channelTitle}`)

        // Update status to running
        await supabase
            .from('import_history')
            .update({ status: 'running' })
            .eq('id', importId)

        // Duration/shorts filter derived from channel settings
        const durationFilter = buildDurationFilter(channelSettings)

        // For latest/oldest we can page-and-filter (fetch-before-filter). For
        // sorts that need the full set (alphabetical, views) we fetch everything
        // within the safety cap, then sort, then slice to the limit.
        const needsFullSet = sortOrder === 'alphabetical_az' ||
            sortOrder === 'alphabetical_za' ||
            sortOrder === 'views'

        const fetchOptions = {
            maxResults: limit || 500,
            filter: durationFilter,
            order: sortOrder === 'oldest' ? 'oldest' : null
        }

        // Only early-stop on the limit for latest (chronological) imports; the
        // other orders need the full candidate set before the limit is applied
        if (limit && !needsFullSet && sortOrder !== 'oldest') {
            fetchOptions.postFilterLimit = limit
        }

        const videos = await youtubeService.getChannelVideos(channelId, fetchOptions)
        const truncated = !!videos.truncated

        // Apply sorts that require the full set
        if (sortOrder === 'alphabetical_az') {
            videos.sort((a, b) => a.title.localeCompare(b.title))
        } else if (sortOrder === 'alphabetical_za') {
            videos.sort((a, b) => b.title.localeCompare(a.title))
        } else if (sortOrder === 'views') {
            videos.sort((a, b) => (b.viewCount || 0) - (a.viewCount || 0))
        }

        // Videos are already duration-filtered inside getChannelVideos
        let filteredVideos = videos

        // Enforce the requested limit after ordering
        if (limit && filteredVideos.length > limit) {
            logger.info(`[Import Filter] 🎯 Limiting to ${limit} videos (had ${filteredVideos.length} after filtering)`)
            filteredVideos = filteredVideos.slice(0, limit)
        }

        // Update videos found (+ truncation flag)
        await supabase
            .from('import_history')
            .update({ videos_found: filteredVideos.length, truncated })
            .eq('id', importId)

        let imported = 0
        let skipped = 0
        let failed = 0
        let patternMatchCount = 0
        let cancelled = false

        // Import each video
        for (let i = 0; i < filteredVideos.length; i++) {
            const video = filteredVideos[i]

            // Re-read status every ~10 videos so a cancel request stops us cleanly
            if (i > 0 && i % 10 === 0) {
                const { data: statusRow } = await supabase
                    .from('import_history')
                    .select('status')
                    .eq('id', importId)
                    .single()

                if (statusRow?.status === 'cancelled') {
                    logger.info(`[Import Process] Import ${importId} cancelled at video ${i}/${filteredVideos.length}`)
                    cancelled = true
                    break
                }
            }

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

                // Extract metadata using channel pattern. When the channel's
                // pattern_source is 'description', run the pattern against the
                // video description text instead of the title.
                const patternInput = (patternSource === 'description' && video.description)
                    ? video.description
                    : video.title
                const parsed = await movieCurator.extractMetadata(patternInput, channelId)

                // Count pattern matches for the import's match-rate metric
                if (parsed.patternMatched) {
                    patternMatchCount++
                }

                // Log pattern extraction results
                logger.info(`[Import] Pattern extraction for "${video.title}":`, {
                    source: patternSource,
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
                    errorDetails.push({ videoId: video.id, title: video.title, error: insertError.message })
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

                                    // Apply the channel's auto-approve threshold, same as
                                    // the staging enrich endpoints do post-enrichment
                                    const autoApproveThreshold = normalizeAutoApproveThreshold(channelSettings?.auto_approve_threshold)
                                    if (autoApproveThreshold != null) {
                                        await maybeAutoApprove(
                                            { id: insertedMovie.id, title: movieData.title, approval_status: 'pending' },
                                            confidenceAsPercent(enrichResult.confidence),
                                            autoApproveThreshold
                                        )
                                    }

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
                        videos_failed: failed,
                        pattern_match_count: patternMatchCount
                    })
                    .eq('id', importId)

            } catch (videoError) {
                logger.error(`[Import] Error processing video ${video.id}:`, videoError)
                failed++
                errorDetails.push({ videoId: video.id, title: video.title, error: videoError.message })
            }
        }

        // Finalize — respect a cancellation requested mid-run
        await supabase
            .from('import_history')
            .update({
                status: cancelled ? 'cancelled' : 'completed',
                completed_at: new Date().toISOString(),
                videos_imported: imported,
                videos_skipped: skipped,
                videos_failed: failed,
                pattern_match_count: patternMatchCount,
                error_details: errorDetails.length > 0 ? errorDetails : null
            })
            .eq('id', importId)

        logger.info(`[Import Process] ${cancelled ? 'Cancelled' : 'Completed'} ${importId}: ${imported} imported, ${skipped} skipped, ${failed} failed, ${patternMatchCount} pattern-matched`)

    } catch (error) {
        logger.error(`[Import Process] Fatal error for ${importId}:`, error)

        await supabase
            .from('import_history')
            .update({
                status: 'failed',
                completed_at: new Date().toISOString(),
                error_message: error.message,
                error_details: errorDetails.length > 0 ? errorDetails : null
            })
            .eq('id', importId)
    }
}

// =============================================================================
// TV SERIES EPISODE MATCHING
// =============================================================================

/**
 * POST /api/admin/channel-management/:channelId/match-episodes
 * Body: { seriesIds: [uuid, ...] }
 *
 * Dry-run: for each of the channel's staged movies still awaiting approval,
 * detect which of the given series it belongs to and fuzzy-match its YouTube
 * title against that series' stored episode guide. Writes NOTHING.
 */
router.post('/:channelId/match-episodes', async (req, res, next) => {
    try {
        const { channelId } = req.params
        const { seriesIds } = req.body || {}

        if (!Array.isArray(seriesIds) || seriesIds.length === 0) {
            return res.status(400).json({
                success: false,
                error: 'seriesIds must be a non-empty array of tv_series uuids'
            })
        }

        const { data: seriesRows, error: seriesError } = await supabase
            .from('tv_series')
            .select('id, title')
            .in('id', seriesIds)

        if (seriesError) throw seriesError

        if (!seriesRows || seriesRows.length === 0) {
            return res.status(404).json({
                success: false,
                error: 'No tv_series found for the given seriesIds'
            })
        }

        const { data: guides, error: guidesError } = await supabase
            .from('episode_guides')
            .select('tv_series_id, episodes')
            .in('tv_series_id', seriesIds)

        if (guidesError) throw guidesError

        const guideBySeries = new Map((guides || []).map(g => [g.tv_series_id, g.episodes || []]))
        const seriesOptions = seriesRows.map(s => ({
            tvSeriesId: s.id,
            title: s.title,
            episodes: guideBySeries.get(s.id) || []
        }))

        // Fetch the channel's staged movies still awaiting approval.
        // Note: 'enriched' is not an approval_status value — enrichment keeps rows
        // in 'pending' (tracked via enriched_at), so 'pending' covers both.
        const stagedMovies = []
        const PAGE_SIZE = 1000
        for (let from = 0; ; from += PAGE_SIZE) {
            const { data, error } = await supabase
                .from('staged_movies')
                .select('id, title, youtube_video_title')
                .eq('channel_id', channelId)
                .eq('approval_status', 'pending')
                .order('created_at', { ascending: true })
                .range(from, from + PAGE_SIZE - 1)
            if (error) throw error
            stagedMovies.push(...(data || []))
            if (!data || data.length < PAGE_SIZE) break
        }

        const proposals = []
        const unmatched = []

        for (const movie of stagedMovies) {
            const youtubeTitle = movie.youtube_video_title || movie.title || ''
            const result = proposeEpisodeMatch(youtubeTitle, seriesOptions)

            if (result.matched) {
                proposals.push({
                    stagedMovieId: movie.id,
                    youtubeTitle,
                    tvSeriesId: result.tvSeriesId,
                    season: result.season,
                    episode: result.episode,
                    episodeName: result.episodeName,
                    confidence: result.confidence
                })
            } else {
                unmatched.push({
                    stagedMovieId: movie.id,
                    youtubeTitle,
                    reason: result.reason
                })
            }
        }

        logger.info(`[Episode Match] Channel ${channelId}: ${proposals.length} proposals, ${unmatched.length} unmatched (dry-run, ${seriesOptions.length} series)`)

        res.json({
            success: true,
            data: { proposals, unmatched }
        })
    } catch (error) {
        logger.error('[Episode Match] match-episodes error:', error)
        next(error)
    }
})

/**
 * POST /api/admin/channel-management/:channelId/confirm-episode-matches
 * Body: { matches: [{ stagedMovieId, tvSeriesId, season, episode, episodeName }] }
 *
 * Applies confirmed episode matches to staged_movies — only rows belonging to
 * this channel that are not already publishing/published.
 */
router.post('/:channelId/confirm-episode-matches', async (req, res, next) => {
    try {
        const { channelId } = req.params
        const { matches } = req.body || {}

        if (!Array.isArray(matches) || matches.length === 0) {
            return res.status(400).json({
                success: false,
                error: 'matches must be a non-empty array'
            })
        }

        const toInteger = (value) => {
            const n = parseInt(value)
            return Number.isInteger(n) ? n : null
        }

        let updated = 0
        const errors = []

        for (const match of matches) {
            const { stagedMovieId, tvSeriesId, season, episode, episodeName } = match || {}

            if (!stagedMovieId || !tvSeriesId) {
                errors.push({
                    stagedMovieId: stagedMovieId || null,
                    error: 'stagedMovieId and tvSeriesId are required'
                })
                continue
            }

            const { data, error } = await supabase
                .from('staged_movies')
                .update({
                    tv_series_id: tvSeriesId,
                    season_number: toInteger(season),
                    episode_number: toInteger(episode),
                    episode_name: episodeName || null,
                    is_tv_series: true,
                    series_type: 'tv_series',
                    updated_at: new Date().toISOString()
                })
                .eq('id', stagedMovieId)
                .eq('channel_id', channelId)
                .not('approval_status', 'in', '("publishing","published")')
                .select('id')

            if (error) {
                errors.push({ stagedMovieId, error: error.message })
                continue
            }

            if (data && data.length > 0) {
                updated++
            } else {
                errors.push({
                    stagedMovieId,
                    error: 'Not updated (wrong channel, already published, or not found)'
                })
            }
        }

        logger.info(`[Episode Match] Channel ${channelId}: confirmed ${updated}/${matches.length} episode matches`)

        res.json({
            success: true,
            data: {
                updated,
                errors: errors.length > 0 ? errors : undefined
            }
        })
    } catch (error) {
        logger.error('[Episode Match] confirm-episode-matches error:', error)
        next(error)
    }
})

export default router
