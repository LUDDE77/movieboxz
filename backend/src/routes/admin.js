import express from 'express'
import { movieCurator } from '../services/movieCurator.js'
import { seriesCurator } from '../services/seriesCurator.js'
import { youtubeService } from '../services/youtubeService.js'
import { channelPatternDetector } from '../services/channelPatternDetector.js'
import { titleFixer } from '../scripts/fixMovieTitles.js'
import { enhancedEnrichment } from '../services/enhancedEnrichment.js'
import { tmdbService } from '../services/tmdbService.js'
import { dbOperations, supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'
import manualEnrichmentQueue from '../services/manualEnrichmentQueue.js'
import { adminAuth } from '../middleware/adminAuth.js'
import { sumQuotaUnits, YOUTUBE_DAILY_BUDGET } from '../utils/importHelpers.js'

const router = express.Router()

// Apply admin auth to all routes
router.use(adminAuth)

// =============================================================================
// POST /api/admin/curate/all — DISABLED
// This endpoint called movieCurator.curateAllChannels(), which does not exist
// (it threw on every invocation). Do not repoint it at curateChannelMovies:
// that inserts directly into the movies table, bypassing the staging/approval
// pipeline. Use the staging import endpoints per channel instead.
// =============================================================================
router.post('/curate/all', (req, res) => {
    logger.warn('Admin called deprecated endpoint: POST /api/admin/curate/all')

    res.status(410).json({
        success: false,
        error: 'Endpoint Removed',
        message: 'Bulk curation across all channels has been removed. Import channels individually via the staging workflow (POST /api/admin/staging/import) instead.'
    })
})

// =============================================================================
// POST /api/admin/curate/channel/:channelId — DISABLED
// This inserted directly into the movies table, bypassing the staging/approval
// pipeline. Use the per-channel staging import endpoints instead
// (POST /api/admin/channel-management/channels/:channelId/import-all).
// =============================================================================
router.post('/curate/channel/:channelId', (req, res) => {
    logger.warn('Admin called deprecated endpoint: POST /api/admin/curate/channel/:channelId')

    res.status(410).json({
        success: false,
        error: 'Endpoint Removed',
        message: 'Direct channel curation has been removed because it bypassed the staging/approval pipeline. Import channels via the staging workflow (POST /api/admin/channel-management/channels/:channelId/import-all) instead.'
    })
})

// =============================================================================
// POST /api/admin/validate
// DISABLED: called movieCurator.validateExistingMovies(), which never existed —
// this endpoint has thrown a 500 on every invocation. Link validation runs
// nightly via linkValidatorService (jobs/scheduler.js).
// =============================================================================
router.post('/validate', (req, res) => {
    res.status(410).json({
        success: false,
        error: 'This endpoint has been removed. Movie availability is validated automatically by the nightly link validation job.'
    })
})

// =============================================================================
// GET /api/admin/stats
// Get curation and database statistics
// =============================================================================
router.get('/stats', async (req, res, next) => {
    try {
        logger.info('Admin requested statistics')

        const stats = await movieCurator.getStatistics()

        res.json({
            success: true,
            data: stats,
            message: 'Statistics retrieved successfully'
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/channels/import
// Import a YouTube channel by name, ID, or URL
// =============================================================================
router.post('/channels/import', async (req, res, next) => {
    try {
        const { channel, forceReenrich = false } = req.body

        if (!channel) {
            return res.status(400).json({
                success: false,
                error: 'Bad Request',
                message: 'Channel identifier is required (name, ID, or URL)'
            })
        }

        logger.info(`Admin requested channel import: ${channel}${forceReenrich ? ' [FORCE RE-ENRICH]' : ''}`)

        // Step 1: Resolve channel identifier to channel ID
        let channelId
        try {
            channelId = await youtubeService.resolveChannelIdentifier(channel)
            logger.info(`Resolved to channel ID: ${channelId}`)
        } catch (error) {
            return res.status(404).json({
                success: false,
                error: 'Channel Not Found',
                message: `Could not find YouTube channel: ${channel}`,
                details: error.message
            })
        }

        // Step 2: Get channel info
        let channelInfo
        try {
            channelInfo = await youtubeService.getChannelInfo(channelId)
        } catch (error) {
            return res.status(500).json({
                success: false,
                error: 'Channel Info Failed',
                message: 'Failed to fetch channel information',
                details: error.message
            })
        }

        // Step 3: Ensure channel exists in database
        try {
            const existingChannel = await dbOperations.getChannelById(channelId).catch(() => null)

            if (existingChannel) {
                // Update existing channel with latest info
                await dbOperations.updateChannel(channelId, {
                    title: channelInfo.title,
                    description: channelInfo.description,
                    thumbnail_url: channelInfo.thumbnailUrl,
                    banner_url: channelInfo.bannerUrl,
                    subscriber_count: channelInfo.subscriberCount,
                    view_count: channelInfo.viewCount,
                    video_count: channelInfo.videoCount,
                    is_verified: channelInfo.isVerified,
                    country: channelInfo.country
                })
            } else {
                // Create new channel
                await dbOperations.createChannel({
                    id: channelInfo.id,
                    title: channelInfo.title,
                    description: channelInfo.description,
                    thumbnail_url: channelInfo.thumbnailUrl,
                    banner_url: channelInfo.bannerUrl,
                    subscriber_count: channelInfo.subscriberCount,
                    view_count: channelInfo.viewCount,
                    video_count: channelInfo.videoCount,
                    is_verified: channelInfo.isVerified,
                    country: channelInfo.country,
                    is_curated: false
                })
            }

            logger.info(`Channel ready in database: ${channelInfo.title}`)
        } catch (error) {
            return res.status(500).json({
                success: false,
                error: 'Database Error',
                message: 'Failed to ensure channel exists in database',
                details: error.message
            })
        }

        // Step 4: Analyze channel title pattern
        let titlePattern = null
        try {
            logger.info(`🔍 Analyzing title pattern for channel: ${channelInfo.title}`)
            titlePattern = await channelPatternDetector.analyzeChannel(channelId, 25)
            logger.info(`✅ Pattern detected: ${titlePattern.type} (confidence: ${titlePattern.confidence})`)
        } catch (error) {
            logger.warn(`⚠️ Pattern analysis failed (will use fallback): ${error.message}`)
            // Continue with import even if pattern detection fails
        }

        // Step 5: Create curation job
        const job = await dbOperations.createCurationJob({
            jobType: 'channel_scan',
            channelId: channelId,
            resultSummary: {
                channelTitle: channelInfo.title,
                channelUrl: channelInfo.customUrl,
                titlePattern: titlePattern ? {
                    type: titlePattern.type,
                    confidence: titlePattern.confidence,
                    title_position: titlePattern.title_position
                } : null
            }
        })

        logger.info(`Created curation job: ${job.id} for channel: ${channelInfo.title}`)

        // Step 5: Start import process asynchronously
        // (Run in background, don't wait for completion)
        movieCurator.curateChannelMovies(channelId, { jobId: job.id, forceReenrich })
            .then(results => {
                const summary = forceReenrich
                    ? `${results.moviesAdded} added, ${results.moviesUpdated} updated`
                    : `${results.moviesAdded} movies added`
                logger.info(`Channel import completed for ${channelInfo.title}: ${summary}`)
            })
            .catch(error => {
                logger.error(`Channel import failed for ${channelInfo.title}:`, error.message)
            })

        // Step 6: Return job info immediately
        res.json({
            success: true,
            data: {
                job: {
                    id: job.id,
                    status: job.status,
                    channelId: channelId,
                    channelTitle: channelInfo.title,
                    channelUrl: channelInfo.customUrl,
                    subscriberCount: channelInfo.subscriberCount,
                    videoCount: channelInfo.videoCount,
                    createdAt: job.created_at
                }
            },
            message: `Channel import started: ${channelInfo.title}. Use GET /api/admin/jobs/${job.id} to check progress.`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/channels/import-all
// Import ALL movies from a YouTube channel (with pagination)
// =============================================================================
router.post('/channels/import-all', async (req, res, next) => {
    try {
        const { channel } = req.body

        if (!channel) {
            return res.status(400).json({
                success: false,
                error: 'Bad Request',
                message: 'Channel identifier is required (name, ID, or URL)'
            })
        }

        logger.info(`Admin requested FULL channel import: ${channel}`)

        // Step 1: Resolve channel identifier to channel ID
        let channelId
        try {
            channelId = await youtubeService.resolveChannelIdentifier(channel)
            logger.info(`Resolved to channel ID: ${channelId}`)
        } catch (error) {
            return res.status(404).json({
                success: false,
                error: 'Channel Not Found',
                message: `Could not find YouTube channel: ${channel}`,
                details: error.message
            })
        }

        // Step 2: Get channel info
        let channelInfo
        try {
            channelInfo = await youtubeService.getChannelInfo(channelId)
        } catch (error) {
            return res.status(500).json({
                success: false,
                error: 'Channel Info Failed',
                message: 'Failed to fetch channel information',
                details: error.message
            })
        }

        // Step 3: Ensure channel exists in database
        try {
            const existingChannel = await dbOperations.getChannelById(channelId).catch(() => null)

            if (existingChannel) {
                await dbOperations.updateChannel(channelId, {
                    title: channelInfo.title,
                    description: channelInfo.description,
                    thumbnail_url: channelInfo.thumbnailUrl,
                    banner_url: channelInfo.bannerUrl,
                    subscriber_count: channelInfo.subscriberCount,
                    view_count: channelInfo.viewCount,
                    video_count: channelInfo.videoCount,
                    is_verified: channelInfo.isVerified,
                    country: channelInfo.country
                })
            } else {
                await dbOperations.createChannel({
                    id: channelInfo.id,
                    title: channelInfo.title,
                    description: channelInfo.description,
                    thumbnail_url: channelInfo.thumbnailUrl,
                    banner_url: channelInfo.bannerUrl,
                    subscriber_count: channelInfo.subscriberCount,
                    view_count: channelInfo.viewCount,
                    video_count: channelInfo.videoCount,
                    is_verified: channelInfo.isVerified,
                    country: channelInfo.country,
                    is_curated: false
                })
            }
        } catch (error) {
            return res.status(500).json({
                success: false,
                error: 'Database Error',
                message: 'Failed to ensure channel exists in database',
                details: error.message
            })
        }

        // Step 4: Create curation job
        const job = await dbOperations.createCurationJob({
            jobType: 'channel_scan',
            channelId: channelId,
            resultSummary: {
                channelTitle: channelInfo.title,
                channelUrl: channelInfo.customUrl,
                fullImport: true
            }
        })

        logger.info(`Created FULL curation job: ${job.id} for channel: ${channelInfo.title}`);

        // Step 5: Start FULL import process (run in background)
        (async () => {
            try {
                await dbOperations.startCurationJob(job.id)

                const results = {
                    moviesFound: 0,
                    moviesAdded: 0,
                    moviesSkipped: 0,
                    errors: [],
                    channelInfo: channelInfo,
                    videosScanned: 0
                }

                // Fetch all channel videos via the uploads playlist
                // (~1 unit per page vs 100 units per page with search.list)
                const videos = await youtubeService.getChannelVideos(channelId, {
                    maxResults: 1000 // Safety limit, same cap as the old 20-page loop
                })

                results.videosScanned = videos.length

                for (let i = 0; i < videos.length; i++) {
                    const video = videos[i]

                    try {
                        if (movieCurator.isLikelyMovie(video)) {
                            results.moviesFound++

                            // Check if movie already exists
                            try {
                                await dbOperations.getMovieByYouTubeId(video.id)
                                results.moviesSkipped++
                                continue
                            } catch (error) {
                                // Movie doesn't exist, continue processing
                            }

                            // Process and add movie
                            const success = await movieCurator.processMovie(video)
                            if (success) {
                                results.moviesAdded++
                                logger.info(`✅ [${results.moviesAdded}] Added: ${video.title}`)
                            } else {
                                results.errors.push({
                                    videoId: video.id,
                                    title: video.title,
                                    error: 'Failed to process movie'
                                })
                            }
                        }
                    } catch (error) {
                        logger.error(`Error processing video ${video.id}:`, error.message)
                        results.errors.push({
                            videoId: video.id,
                            title: video.title,
                            error: error.message
                        })
                    }

                    // Update job progress every 50 videos
                    if ((i + 1) % 50 === 0 || i === videos.length - 1) {
                        await dbOperations.updateCurationJobProgress(job.id, {
                            processed: results.moviesFound,
                            successful: results.moviesAdded,
                            failed: results.errors.length
                        })
                    }
                }

                logger.info(`✅ FULL import completed for ${channelInfo.title}: ${results.moviesAdded} movies added from ${results.videosScanned} videos scanned`)

                await dbOperations.completeCurationJob(job.id, results)

            } catch (error) {
                logger.error(`FULL import failed for ${channelInfo.title}:`, error.message)
                try {
                    await dbOperations.failCurationJob(job.id, error.message)
                } catch (failError) {
                    // Never let the failure path itself become an unhandled rejection
                    logger.error(`Failed to mark curation job ${job.id} as failed:`, failError.message)
                }
            }
        })()

        // Step 6: Return job info immediately
        res.json({
            success: true,
            data: {
                job: {
                    id: job.id,
                    status: job.status,
                    channelId: channelId,
                    channelTitle: channelInfo.title,
                    channelUrl: channelInfo.customUrl,
                    subscriberCount: channelInfo.subscriberCount,
                    videoCount: channelInfo.videoCount,
                    createdAt: job.created_at,
                    fullImport: true
                }
            },
            message: `FULL channel import started: ${channelInfo.title}. This will fetch ALL videos using pagination. Use GET /api/admin/jobs/${job.id} to check progress.`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/admin/jobs/:jobId
// Get status of a curation job
// =============================================================================
router.get('/jobs/:jobId', async (req, res, next) => {
    try {
        const { jobId } = req.params

        logger.info(`Admin requested job status: ${jobId}`)

        const job = await dbOperations.getCurationJob(jobId)

        if (!job) {
            return res.status(404).json({
                success: false,
                error: 'Job Not Found',
                message: `No curation job found with ID: ${jobId}`
            })
        }

        // Calculate progress percentage
        const progressPercentage = job.total_items > 0
            ? Math.round((job.processed_items / job.total_items) * 100)
            : 0

        res.json({
            success: true,
            data: {
                job: {
                    id: job.id,
                    type: job.job_type,
                    status: job.status,
                    channelId: job.channel_id,
                    channelTitle: job.channels?.title,
                    progress: {
                        total: job.total_items,
                        processed: job.processed_items,
                        successful: job.successful_items,
                        failed: job.failed_items,
                        percentage: progressPercentage
                    },
                    timing: {
                        createdAt: job.created_at,
                        startedAt: job.started_at,
                        completedAt: job.completed_at,
                        durationSeconds: job.started_at && job.completed_at
                            ? Math.round((new Date(job.completed_at) - new Date(job.started_at)) / 1000)
                            : null
                    },
                    results: job.result_summary,
                    errors: job.error_log
                }
            },
            message: `Job status: ${job.status}`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/admin/jobs
// List all curation jobs
// =============================================================================
router.get('/jobs', async (req, res, next) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 20
        const offset = (page - 1) * limit

        const filters = {}
        if (req.query.status) filters.status = req.query.status
        if (req.query.jobType) filters.jobType = req.query.jobType
        if (req.query.channelId) filters.channelId = req.query.channelId

        logger.info('Admin requested jobs list')

        const jobs = await dbOperations.getCurationJobs(filters, limit, offset)

        res.json({
            success: true,
            data: {
                jobs: jobs.map(job => ({
                    id: job.id,
                    type: job.job_type,
                    status: job.status,
                    channelId: job.channel_id,
                    channelTitle: job.channels?.title,
                    moviesAdded: job.successful_items,
                    moviesFound: job.total_items,
                    createdAt: job.created_at,
                    completedAt: job.completed_at
                })),
                pagination: {
                    page,
                    limit,
                    total: jobs.length
                }
            },
            message: `Retrieved ${jobs.length} jobs`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/enrich-tmdb  /  POST /api/admin/enrich-omdb
// DISABLED: both called movieCurator.enrichWithTMDB / enrichWithOMDb, which
// never existed — every movie errored and the endpoints reported 100% failures.
// Use POST /api/admin/enrich-enhanced instead.
// =============================================================================
router.post('/enrich-tmdb', (req, res) => {
    res.status(410).json({
        success: false,
        error: 'This endpoint has been removed. Use POST /api/admin/enrich-enhanced instead.'
    })
})

router.post('/enrich-omdb', (req, res) => {
    res.status(410).json({
        success: false,
        error: 'This endpoint has been removed. Use POST /api/admin/enrich-enhanced instead.'
    })
})

// =============================================================================
// POST /api/admin/enrich-enhanced
// Re-enrich movies using enhanced actor-based matching and IMDB scraping
// Particularly useful for The Midnight Screening channel
// =============================================================================
router.post('/enrich-enhanced', async (req, res, next) => {
    try {
        const {
            channelId = null,
            channelTitle = null,
            limit = 100,
            onlyUnenriched = true
        } = req.body

        logger.info(`Admin triggered enhanced enrichment (limit: ${limit}, channel: ${channelTitle || channelId || 'all'})`)

        // Build query with channel JOIN
        let query = supabase
            .from('movies')
            .select(`
                id,
                youtube_video_id,
                title,
                youtube_video_title,
                channel_id,
                published_at,
                tmdb_id,
                imdb_id,
                channels!inner(id, title)
            `)

        // Filter by channel if specified
        if (channelId) {
            query = query.eq('channel_id', channelId)
        } else if (channelTitle) {
            query = query.ilike('channels.title', `%${channelTitle}%`)
        }

        // Filter to unenriched movies only
        if (onlyUnenriched) {
            query = query.is('tmdb_id', null)
        }

        query = query.order('published_at', { ascending: false }).limit(limit)

        const { data: movies, error } = await query

        if (error) {
            throw new Error(`Failed to fetch movies: ${error.message}`)
        }

        if (!movies || movies.length === 0) {
            return res.json({
                success: true,
                data: {
                    total: 0,
                    enriched: 0,
                    failed: 0,
                    results: []
                },
                message: 'No movies found to enrich'
            })
        }

        logger.info(`Found ${movies.length} movies for enhanced enrichment`)

        let enriched = 0
        let failed = 0
        const results = []

        for (const movie of movies) {
            try {
                logger.info(`\n🎬 Enriching: ${movie.youtube_video_title}`)

                // Transform movie object to include channel_title (from JOIN)
                const movieWithChannel = {
                    ...movie,
                    channel_title: movie.channels?.title || null
                }

                const enrichmentData = await enhancedEnrichment.enrichMovie(movieWithChannel)

                if (enrichmentData && enrichmentData.confidence >= 50) {
                    // Update movie with enrichment data
                    const updateData = {
                        tmdb_id: enrichmentData.tmdb_id,
                        imdb_id: enrichmentData.imdb_id,
                        title: enrichmentData.title || movie.title,
                        original_title: enrichmentData.original_title,
                        description: enrichmentData.description,
                        release_date: enrichmentData.release_date,
                        runtime_minutes: enrichmentData.runtime_minutes,
                        poster_path: enrichmentData.poster_path,
                        backdrop_path: enrichmentData.backdrop_path,
                        vote_average: enrichmentData.vote_average,
                        vote_count: enrichmentData.vote_count,
                        popularity: enrichmentData.popularity,
                        imdb_rating: enrichmentData.imdb_rating,
                        imdb_votes: enrichmentData.imdb_votes,
                        rated: enrichmentData.rated,
                        director: enrichmentData.director,
                        actors: enrichmentData.actors,
                        country: enrichmentData.country,
                        language: enrichmentData.language,
                        is_tv_show: enrichmentData.media_type === 'tv',
                        enrichment_source: enrichmentData.source,
                        updated_at: new Date().toISOString()
                    }

                    const { error: updateError } = await supabase
                        .from('movies')
                        .update(updateData)
                        .eq('id', movie.id)

                    if (updateError) {
                        throw new Error(`Database update failed: ${updateError.message}`)
                    }

                    // Add genres if present
                    if (enrichmentData.genres && enrichmentData.genres.length > 0) {
                        await movieCurator.addMovieGenres(movie.id, enrichmentData.genres)
                    }

                    enriched++
                    results.push({
                        id: movie.id,
                        youtube_title: movie.youtube_video_title,
                        status: 'enriched',
                        matched_title: enrichmentData.title,
                        tmdb_id: enrichmentData.tmdb_id,
                        imdb_id: enrichmentData.imdb_id,
                        media_type: enrichmentData.media_type,
                        confidence: enrichmentData.confidence,
                        actor_match: enrichmentData.actorMatch,
                        has_poster: !!enrichmentData.poster_path
                    })

                    logger.info(`✅ Enriched: ${enrichmentData.title} (${enrichmentData.media_type}) - Confidence: ${enrichmentData.confidence}%`)
                } else {
                    failed++
                    results.push({
                        id: movie.id,
                        youtube_title: movie.youtube_video_title,
                        status: 'not_found',
                        confidence: enrichmentData?.confidence || 0
                    })

                    logger.warn(`❌ Low confidence or no match: ${movie.youtube_video_title}`)
                }

                // Small delay to respect rate limits
                await new Promise(resolve => setTimeout(resolve, 500))

            } catch (error) {
                logger.error(`❌ Error enriching ${movie.youtube_video_title}:`, error.message)
                failed++
                results.push({
                    id: movie.id,
                    youtube_title: movie.youtube_video_title,
                    status: 'error',
                    error: error.message
                })
            }
        }

        res.json({
            success: true,
            data: {
                total: movies.length,
                enriched,
                failed,
                results
            },
            message: `Enhanced enrichment completed: ${enriched} enriched, ${failed} failed`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// TV SERIES ADMIN ROUTES
// =============================================================================

// =============================================================================
// POST /api/admin/series/create
// Create a simple TV series with just a title (no TMDB required)
// =============================================================================
router.post('/series/create', async (req, res, next) => {
    try {
        const { title, description } = req.body

        if (!title || !title.trim()) {
            return res.status(400).json({
                success: false,
                error: 'Bad Request',
                message: 'title is required'
            })
        }

        logger.info(`Admin creating simple TV series: ${title}`)

        const { data, error } = await supabase
            .from('tv_series')
            .insert({ title: title.trim(), description: description || null })
            .select()
            .single()

        if (error) {
            throw new Error(`Failed to create series: ${error.message}`)
        }

        res.json({
            success: true,
            data: { series: data },
            message: `TV series created: ${data.title}`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/series/import-tmdb
// Import a TV series from TMDB by ID or name
// =============================================================================
router.post('/series/import-tmdb', async (req, res, next) => {
    try {
        const { tmdbId, seriesName, channelId } = req.body

        if (!tmdbId && !seriesName) {
            return res.status(400).json({
                success: false,
                error: 'Bad Request',
                message: 'Either tmdbId or seriesName is required'
            })
        }

        logger.info(`Admin requested series import: ${tmdbId || seriesName}`)

        let result
        if (tmdbId) {
            result = await seriesCurator.importSeriesFromTMDB(parseInt(tmdbId), channelId)
        } else {
            result = await seriesCurator.importSeriesByName(seriesName, channelId)
        }

        res.json({
            success: true,
            data: result,
            message: `Series imported: ${result.series.title} (${result.seasonsCreated} seasons, ${result.episodesCreated} episodes)`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/admin/series
// List all TV series
// =============================================================================
router.get('/series', async (req, res, next) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 20
        const offset = (page - 1) * limit

        logger.info('Admin requested series list')

        const { data: series, error } = await supabase
            .from('tv_series')
            .select(`
                *,
                series_genres (
                    genres (id, name)
                )
            `)
            .order('created_at', { ascending: false })
            .range(offset, offset + limit - 1)

        if (error) {
            throw new Error(`Failed to fetch series: ${error.message}`)
        }

        // Get total count
        const { count } = await supabase
            .from('tv_series')
            .select('*', { count: 'exact', head: true })

        res.json({
            success: true,
            data: {
                series: series.map(s => ({
                    id: s.id,
                    tmdb_id: s.tmdb_id,
                    title: s.title,
                    status: s.status,
                    number_of_seasons: s.number_of_seasons,
                    number_of_episodes: s.number_of_episodes,
                    is_available: s.is_available,
                    featured: s.featured,
                    trending: s.trending,
                    vote_average: s.vote_average,
                    poster_path: s.poster_path,
                    created_at: s.created_at
                })),
                pagination: {
                    page,
                    limit,
                    total: count,
                    totalPages: Math.ceil(count / limit)
                }
            },
            message: `Retrieved ${series.length} series`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/admin/series/:seriesId
// Get detailed information about a specific series
// =============================================================================
router.get('/series/:seriesId', async (req, res, next) => {
    try {
        const { seriesId } = req.params

        logger.info(`Admin requested series details: ${seriesId}`)

        // Get series with related data
        const { data: series, error: seriesError } = await supabase
            .from('tv_series')
            .select(`
                *,
                series_genres (
                    genres (id, name)
                ),
                seasons (
                    id,
                    season_number,
                    title,
                    episode_count,
                    poster_path
                )
            `)
            .eq('id', seriesId)
            .single()

        if (seriesError) {
            throw new Error(`Failed to fetch series: ${seriesError.message}`)
        }

        // Get episode statistics
        const { data: episodeStats } = await supabase
            .from('episodes')
            .select('is_available')
            .eq('series_id', seriesId)

        const totalEpisodes = episodeStats?.length || 0
        const linkedEpisodes = episodeStats?.filter(e => e.is_available).length || 0
        const unlinkedEpisodes = totalEpisodes - linkedEpisodes

        res.json({
            success: true,
            data: {
                series: {
                    ...series,
                    statistics: {
                        totalEpisodes,
                        linkedEpisodes,
                        unlinkedEpisodes,
                        linkagePercentage: totalEpisodes > 0
                            ? Math.round((linkedEpisodes / totalEpisodes) * 100)
                            : 0
                    }
                }
            },
            message: 'Series details retrieved successfully'
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/admin/series/unlinked/:seriesId
// Get unlinked episodes for a series
// =============================================================================
router.get('/series/unlinked/:seriesId', async (req, res, next) => {
    try {
        const { seriesId } = req.params
        const limit = parseInt(req.query.limit) || 50

        logger.info(`Admin requested unlinked episodes for series: ${seriesId}`)

        const { data: episodes, error } = await supabase
            .from('episodes')
            .select('*')
            .eq('series_id', seriesId)
            .is('youtube_video_id', null)
            .order('season_number', { ascending: true })
            .order('episode_number', { ascending: true })
            .limit(limit)

        if (error) {
            throw new Error(`Failed to fetch unlinked episodes: ${error.message}`)
        }

        res.json({
            success: true,
            data: {
                episodes: episodes.map(e => ({
                    id: e.id,
                    season: e.season_number,
                    episode: e.episode_number,
                    title: e.title,
                    air_date: e.air_date,
                    runtime_minutes: e.runtime_minutes
                })),
                total: episodes.length
            },
            message: `Found ${episodes.length} unlinked episodes`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/series/link-youtube
// Link YouTube videos to episodes for a series
// =============================================================================
router.post('/series/link-youtube', async (req, res, next) => {
    try {
        const { seriesId, channelId, autoConfirm = false, dryRun = false } = req.body

        if (!seriesId || !channelId) {
            return res.status(400).json({
                success: false,
                error: 'Bad Request',
                message: 'seriesId and channelId are required'
            })
        }

        logger.info(`Admin requested YouTube linking for series ${seriesId} (dryRun: ${dryRun})`)

        const result = await seriesCurator.linkYouTubeEpisodes(seriesId, channelId, {
            autoConfirm,
            dryRun
        })

        res.json({
            success: true,
            data: result,
            message: dryRun
                ? `Found ${result.matchesFound} potential matches (dry run)`
                : `Linked ${result.episodesLinked} episodes to YouTube videos`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/series/confirm-link
// Manually confirm a specific episode-video link
// =============================================================================
router.post('/series/confirm-link', async (req, res, next) => {
    try {
        const { episodeId, videoId } = req.body

        if (!episodeId || !videoId) {
            return res.status(400).json({
                success: false,
                error: 'Bad Request',
                message: 'episodeId and videoId are required'
            })
        }

        logger.info(`Admin confirmed link: Episode ${episodeId} → Video ${videoId}`)

        // Get video info from YouTube
        const videoInfo = await youtubeService.getVideoDetails(videoId)

        if (!videoInfo) {
            return res.status(404).json({
                success: false,
                error: 'Video Not Found',
                message: `YouTube video ${videoId} not found`
            })
        }

        // Link episode to video
        await seriesCurator.linkEpisodeToYouTube(episodeId, videoInfo)

        res.json({
            success: true,
            data: {
                episodeId,
                videoId,
                videoTitle: videoInfo.title
            },
            message: 'Episode linked successfully'
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/series/:seriesId/toggle-availability
// Toggle series availability (featured, trending, staff_pick)
// =============================================================================
router.post('/series/:seriesId/toggle-availability', async (req, res, next) => {
    try {
        const { seriesId } = req.params
        const { field, value } = req.body

        if (!['featured', 'trending', 'staff_pick'].includes(field)) {
            return res.status(400).json({
                success: false,
                error: 'Bad Request',
                message: 'field must be one of: featured, trending, staff_pick'
            })
        }

        logger.info(`Admin toggled ${field} for series ${seriesId}: ${value}`)

        const { data, error } = await supabase
            .from('tv_series')
            .update({ [field]: value })
            .eq('id', seriesId)
            .select()
            .single()

        if (error) {
            throw new Error(`Failed to update series: ${error.message}`)
        }

        res.json({
            success: true,
            data: {
                series: data
            },
            message: `Series ${field} set to ${value}`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/movies/fix-titles
// Bulk fix movie titles by re-cleaning with current channel patterns
// Query params:
//   - dryRun: boolean (default: false) - Preview changes without applying
//   - limit: number (optional) - Limit number of movies to process
//   - channelId: string (optional) - Only fix titles for specific channel
// =============================================================================
router.post('/movies/fix-titles', async (req, res, next) => {
    try {
        const {
            dryRun = false,
            limit = null,
            channelId = null
        } = req.body

        logger.info('Admin triggered title fix:', { dryRun, limit, channelId })

        const results = await titleFixer.fixAllTitles({
            dryRun,
            limit: limit ? parseInt(limit) : null,
            channelId
        })

        res.json({
            success: true,
            data: results,
            message: dryRun
                ? `Dry run completed: ${results.updated} titles would be updated`
                : `Title fix completed: ${results.updated} titles updated`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/movies/:movieId/fix-title
// Fix title for a single movie
// =============================================================================
router.post('/movies/:movieId/fix-title', async (req, res, next) => {
    try {
        const { movieId } = req.params

        logger.info(`Admin triggered title fix for movie: ${movieId}`)

        const result = await titleFixer.fixSingleMovie(movieId)

        res.json({
            success: true,
            data: result,
            message: result.newTitle
                ? `Title updated: ${result.oldTitle} → ${result.newTitle}`
                : result.message
        })

    } catch (error) {
        next(error)
    }
})

// NOTE: DELETE /api/admin/channels/:channelId lives in channelsAdmin.js.
// A broken duplicate here (querying a nonexistent youtube_channels table)
// was removed.

// =============================================================================
// CHANNEL PATTERN MANAGEMENT ROUTES — DISABLED (410 Gone)
// The canonical pattern API lives in channelsAdmin.js and is mounted at
// /api/admin/channels/:id/pattern (GET/PUT/DELETE) plus /:id/test-pattern.
// This duplicate /channel-patterns block is retired to avoid two divergent
// pattern APIs. Verified no macOS/iOS client references /channel-patterns.
// =============================================================================
function channelPatternsGone(req, res) {
    logger.warn(`Admin called retired endpoint: ${req.method} ${req.originalUrl}`)
    res.status(410).json({
        success: false,
        error: 'Endpoint Removed',
        message: 'Use the canonical channel pattern API at /api/admin/channels/:id/pattern (GET/PUT/DELETE) and /api/admin/channels/:id/test-pattern instead.'
    })
}

router.get('/channel-patterns', channelPatternsGone)
router.get('/channel-patterns/:channelId', channelPatternsGone)
router.post('/channel-patterns', channelPatternsGone)
router.delete('/channel-patterns/:channelId', channelPatternsGone)

// =============================================================================
// MANUAL ENRICHMENT QUEUE ROUTES
// =============================================================================

// =============================================================================
// GET /api/admin/manual-enrichment-queue
// Get pending items in manual enrichment queue
// Query params:
//   - channelId: Filter by channel (optional)
//   - status: Filter by status (default: 'pending')
//   - limit: Max results (default: 50)
//   - offset: Pagination offset (default: 0)
// =============================================================================
router.get('/manual-enrichment-queue', async (req, res, next) => {
    try {
        const options = {
            channelId: req.query.channelId || null,
            status: req.query.status || 'pending',
            limit: parseInt(req.query.limit) || 50,
            offset: parseInt(req.query.offset) || 0
        }

        logger.info('Admin requested manual enrichment queue', options)

        const result = await manualEnrichmentQueue.getQueue(options)

        res.json({
            success: true,
            data: result,
            message: `Retrieved ${result.items.length} queue items`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/admin/manual-enrichment-queue/stats
// Get queue statistics
// Query params:
//   - channelId: Filter by channel (optional)
// =============================================================================
router.get('/manual-enrichment-queue/stats', async (req, res, next) => {
    try {
        const channelId = req.query.channelId || null

        logger.info('Admin requested queue statistics', { channelId })

        const stats = await manualEnrichmentQueue.getStats(channelId)

        res.json({
            success: true,
            data: { stats },
            message: 'Queue statistics retrieved successfully'
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/admin/manual-enrichment-queue/:queueId
// Get a specific queue entry
// =============================================================================
router.get('/manual-enrichment-queue/:queueId', async (req, res, next) => {
    try {
        const { queueId } = req.params

        logger.info(`Admin requested queue entry: ${queueId}`)

        const item = await manualEnrichmentQueue.getQueueItem(queueId)

        if (!item) {
            return res.status(404).json({
                success: false,
                error: 'Queue Entry Not Found',
                message: `No queue entry found with ID: ${queueId}`
            })
        }

        res.json({
            success: true,
            data: { item },
            message: 'Queue entry retrieved successfully'
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/manual-enrichment-queue/:queueId/match
// Manually match a movie with an IMDB ID
// Body: { imdbId, notes }
// =============================================================================
router.post('/manual-enrichment-queue/:queueId/match', async (req, res, next) => {
    try {
        const { queueId } = req.params
        const { imdbId, notes } = req.body

        if (!imdbId) {
            return res.status(400).json({
                success: false,
                error: 'Bad Request',
                message: 'imdbId is required'
            })
        }

        logger.info(`Admin processing manual match for queue ${queueId}:`, { imdbId })

        const result = await manualEnrichmentQueue.processManualMatch(queueId, imdbId, notes)

        res.json({
            success: true,
            data: result,
            message: `Movie matched successfully: ${result.enrichment.title}`
        })

    } catch (error) {
        // Lookup failures are a data problem, not a server fault — tell the
        // admin what happened instead of a blank 500
        if (String(error.message).startsWith('Failed to enrich movie with IMDB ID')) {
            return res.status(422).json({
                success: false,
                error: `No data found for that IMDB id on OMDB or TMDB. Check the id (tt...) is correct — episode-level ids often work better than series-level ones.`
            })
        }
        next(error)
    }
})

// =============================================================================
// POST /api/admin/manual-enrichment-queue/:queueId/skip
// Skip a queue entry (won't be enriched)
// Body: { reason }
// =============================================================================
router.post('/manual-enrichment-queue/:queueId/skip', async (req, res, next) => {
    try {
        const { queueId } = req.params
        const { reason } = req.body

        logger.info(`Admin skipping queue entry: ${queueId}`)

        await manualEnrichmentQueue.skipEntry(queueId, reason)

        res.json({
            success: true,
            message: 'Queue entry skipped successfully'
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// DELETE /api/admin/manual-enrichment-queue/:queueId
// Delete a queue entry
// =============================================================================
router.delete('/manual-enrichment-queue/:queueId', async (req, res, next) => {
    try {
        const { queueId} = req.params

        logger.info(`Admin deleting queue entry: ${queueId}`)

        await manualEnrichmentQueue.deleteEntry(queueId)

        res.json({
            success: true,
            message: 'Queue entry deleted successfully'
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// QUOTA
// =============================================================================

// sumQuotaUnits and YOUTUBE_DAILY_BUDGET are pure helpers imported from
// ../utils/importHelpers.js (unit tested without a DB connection).

/**
 * GET /api/admin/quota
 * Summarize today's YouTube API quota usage from the api_usage table.
 */
router.get('/quota', async (req, res, next) => {
    try {
        // Start of the current UTC day
        const now = new Date()
        const dayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))
        const date = dayStart.toISOString().slice(0, 10) // YYYY-MM-DD

        const { data, error } = await supabase
            .from('api_usage')
            .select('quota_cost')
            .eq('service', 'youtube')
            .gte('created_at', dayStart.toISOString())

        if (error) throw error

        const used = sumQuotaUnits(data)

        res.json({
            success: true,
            data: {
                date,
                used,
                budget: YOUTUBE_DAILY_BUDGET,
                remaining: Math.max(0, YOUTUBE_DAILY_BUDGET - used)
            }
        })
    } catch (error) {
        logger.error('[Quota] Error:', error)
        next(error)
    }
})

// =============================================================================
// PRODUCTION MOVIE MANAGEMENT
// =============================================================================

// Admin movie list sort whitelist -> DB columns
const ADMIN_MOVIE_SORTS = {
    view_count: 'view_count',
    vote_average: 'vote_average',
    published_at: 'published_at',
    created_at: 'created_at',
    title: 'title'
}

/**
 * GET /api/admin/movies
 * Admin-grade movie list. Same flattened shape as public GET /api/movies but
 * supports include_unavailable=true and a wider sort whitelist.
 * Query params: page, limit, sort, order (asc|desc), search, channel, include_unavailable
 */
router.get('/movies', async (req, res, next) => {
    try {
        const {
            page = 1,
            limit = 20,
            sort = 'created_at',
            order = 'desc',
            search,
            channel,
            include_unavailable
        } = req.query

        const pageNum = parseInt(page) || 1
        const limitNum = Math.min(parseInt(limit) || 20, 100)
        const offset = (pageNum - 1) * limitNum

        const sortBy = ADMIN_MOVIE_SORTS[sort] || 'created_at'
        const sortOrder = order === 'asc' ? 'asc' : 'desc'

        const filters = {
            sortBy,
            sortOrder,
            includeUnavailable: include_unavailable === 'true'
        }
        if (channel) filters.channelId = channel
        if (search) filters.search = search

        const result = await dbOperations.getMovies(filters, limitNum, offset)

        res.json({
            success: true,
            data: {
                movies: result.movies,
                pagination: {
                    page: pageNum,
                    limit: limitNum,
                    total: result.total,
                    pages: Math.ceil((result.total || 0) / limitNum)
                }
            }
        })
    } catch (error) {
        logger.error('[Admin Movies] List error:', error)
        next(error)
    }
})

/**
 * PATCH /api/admin/movies/:id
 * Update production movie metadata
 */
router.patch('/movies/:id', async (req, res, next) => {
    try {
        const { id } = req.params
        const updates = req.body

        logger.info(`[Production Movies] Updating movie ${id}`)

        // Allowed fields for update
        const allowedFields = [
            'title', 'description', 'release_date', 'director', 'actors',
            'is_tv_series', 'is_kids_content', 'is_available', 'needs_verification',
            'runtime_minutes', 'imdb_rating', 'imdb_votes',
            'backdrop_path', // detail-page hero/background image (TMDB path or full URL)
            'hero_image_url' // Hero Builder: admin-curated carousel image (nullable)
        ]

        const cleanUpdates = {}
        allowedFields.forEach(field => {
            if (updates[field] !== undefined) {
                cleanUpdates[field] = updates[field]
            }
        })

        if (Object.keys(cleanUpdates).length === 0) {
            return res.status(400).json({
                success: false,
                error: 'No valid fields to update'
            })
        }

        cleanUpdates.updated_at = new Date().toISOString()

        const { data: movie, error } = await supabase
            .from('movies')
            .update(cleanUpdates)
            .eq('id', id)
            .select(`
                *,
                genres:movie_genres(
                    genre:genres(*)
                )
            `)
            .single()

        if (error) throw error

        if (!movie) {
            return res.status(404).json({
                success: false,
                error: 'Movie not found'
            })
        }

        // Transform genres to match expected format
        const transformedMovie = {
            ...movie,
            genres: movie.genres?.map(mg => mg.genre) || []
        }

        res.json({
            success: true,
            data: transformedMovie
        })

    } catch (error) {
        logger.error('[Production Movies] Update error:', error)
        next(error)
    }
})

/**
 * POST /api/admin/movies/:id/enrich
 * Manually enrich a production movie
 */
router.post('/movies/:id/enrich', async (req, res, next) => {
    try {
        const { id } = req.params
        const { priority = 'full' } = req.body

        logger.info(`[Production Movies] Enriching movie ${id} with priority: ${priority}`)

        // Get the movie
        const { data: movie, error: fetchError } = await supabase
            .from('movies')
            .select('*')
            .eq('id', id)
            .single()

        if (fetchError) throw fetchError

        if (!movie) {
            return res.status(404).json({
                success: false,
                error: 'Movie not found'
            })
        }

        // Enrich using enhanced enrichment service
        const enriched = await enhancedEnrichment.enrichMovie({
            title: movie.title,
            youtube_video_title: movie.youtube_video_title,
            releaseDate: movie.release_date
        }, priority)

        // Update movie with enrichment data
        const updateData = {
            tmdb_id: enriched.tmdb_id,
            imdb_id: enriched.imdb_id,
            poster_path: enriched.poster_path,
            backdrop_path: enriched.backdrop_path,
            vote_average: enriched.vote_average,
            vote_count: enriched.vote_count,
            popularity: enriched.popularity,
            imdb_rating: enriched.imdb_rating,
            imdb_votes: enriched.imdb_votes,
            rated: enriched.rated,
            director: enriched.director,
            actors: enriched.actors,
            language: enriched.language,
            country: enriched.country,
            is_tv_show: enriched.is_tv_show,
            category: enriched.category,
            enrichment_source: enriched.enrichment_source,
            enrichment_confidence: enriched.enrichment_confidence,
            updated_at: new Date().toISOString()
        }

        // Only update description if we got one and the movie doesn't have one
        if (enriched.description && !movie.description) {
            updateData.description = enriched.description
        }

        // Only update release_date if we got one and the movie doesn't have one
        if (enriched.release_date && !movie.release_date) {
            updateData.release_date = enriched.release_date
        }

        // Only update runtime if we got one and the movie doesn't have one
        if (enriched.runtime_minutes && !movie.runtime_minutes) {
            updateData.runtime_minutes = enriched.runtime_minutes
        }

        const { data: updatedMovie, error: updateError } = await supabase
            .from('movies')
            .update(updateData)
            .eq('id', id)
            .select(`
                *,
                genres:movie_genres(
                    genre:genres(*)
                )
            `)
            .single()

        if (updateError) throw updateError

        // Transform genres to match expected format
        const transformedMovie = {
            ...updatedMovie,
            genres: updatedMovie.genres?.map(mg => mg.genre) || []
        }

        logger.info(`[Production Movies] Successfully enriched movie ${id}`)

        res.json({
            success: true,
            data: transformedMovie
        })

    } catch (error) {
        logger.error('[Production Movies] Enrichment error:', error)
        next(error)
    }
})

/**
 * POST /api/admin/movies/:id/genres
 * Update genres for a production movie
 */
router.post('/movies/:id/genres', async (req, res, next) => {
    try {
        const { id } = req.params
        const { genreIds } = req.body

        logger.info(`[Production Movies] Updating genres for movie ${id}`)

        if (!Array.isArray(genreIds)) {
            return res.status(400).json({
                success: false,
                error: 'genreIds must be an array'
            })
        }

        // Atomically replace genre associations via a stored procedure
        // (avoids the race window between DELETE and INSERT)
        const { error: rpcError } = await supabase
            .rpc('update_movie_genres', {
                p_movie_id: id,
                p_genre_ids: genreIds
            })

        if (rpcError) throw rpcError

        // Fetch updated movie with genres
        const { data: movie, error: fetchError } = await supabase
            .from('movies')
            .select(`
                *,
                genres:movie_genres(
                    genre:genres(*)
                )
            `)
            .eq('id', id)
            .single()

        if (fetchError) throw fetchError

        if (!movie) {
            return res.status(404).json({
                success: false,
                error: 'Movie not found'
            })
        }

        // Transform genres to match expected format
        const transformedMovie = {
            ...movie,
            genres: movie.genres?.map(mg => mg.genre) || []
        }

        logger.info(`[Production Movies] Successfully updated genres for movie ${id}`)

        res.json({
            success: true,
            data: transformedMovie
        })

    } catch (error) {
        logger.error('[Production Movies] Genre update error:', error)
        next(error)
    }
})

/**
 * POST /api/admin/movies/:id/enrich-manual-imdb
 * Manually enrich a production movie from a specific IMDB ID
 */
router.post('/movies/:id/enrich-manual-imdb', async (req, res, next) => {
    try {
        const { id } = req.params
        const { imdbId } = req.body

        logger.info(`[Production Movies] Manual IMDB enrichment for movie ${id} with IMDB ${imdbId}`)

        if (!imdbId || !imdbId.startsWith('tt')) {
            return res.status(400).json({
                success: false,
                error: 'Valid IMDB ID required (must start with "tt")'
            })
        }

        // Get the movie
        const { data: movie, error: fetchError } = await supabase
            .from('movies')
            .select('*')
            .eq('id', id)
            .single()

        if (fetchError) throw fetchError

        if (!movie) {
            return res.status(404).json({
                success: false,
                error: 'Movie not found'
            })
        }

        // Enrich using the specific IMDB ID
        logger.info(`[Production Movies] Enriching with IMDB ID: ${imdbId}`)
        const enriched = await enhancedEnrichment.enrichMovie({
            title: movie.title,
            youtube_video_title: movie.youtube_video_title,
            releaseDate: movie.release_date,
            imdbId: imdbId  // Force this specific IMDB ID
        }, 'full')

        if (!enriched) {
            logger.warn(`[Production Movies] Enrichment returned null for ${imdbId} — saving IMDB ID only`)
        } else {
            logger.info(`[Production Movies] Enrichment result:`)
            logger.info(`  - Title: ${enriched.title || 'N/A'}`)
            logger.info(`  - TMDB ID: ${enriched.tmdb_id || 'N/A'}`)
            logger.info(`  - IMDB Rating: ${enriched.imdb_rating || 'N/A'}`)
            logger.info(`  - Genres: ${enriched.genres ? enriched.genres.length : 0} genres`)
        }

        // Update movie with enrichment data (fall back to IMDB-ID-only if enrichment failed)
        const updateData = {
            imdb_id: imdbId,  // Always save the user-specified IMDB ID
            tmdb_id: enriched?.tmdb_id,
            poster_path: enriched?.poster_path,
            backdrop_path: enriched?.backdrop_path,
            vote_average: enriched?.vote_average,
            vote_count: enriched?.vote_count,
            popularity: enriched?.popularity,
            imdb_rating: enriched?.imdb_rating,
            imdb_votes: enriched?.imdb_votes,
            rated: enriched?.rated,
            director: enriched?.director,
            actors: enriched?.actors,
            language: enriched?.language,
            country: enriched?.country,
            is_tv_show: enriched?.is_tv_show,
            category: enriched?.category,
            enrichment_source: 'manual_imdb',
            enrichment_confidence: 1.0,  // User verified
            updated_at: new Date().toISOString()
        }

        // Update description if we got one and movie doesn't have one
        if (enriched?.description && !movie.description) {
            updateData.description = enriched.description
        }

        // Update release_date if we got one and movie doesn't have one
        if (enriched?.release_date && !movie.release_date) {
            updateData.release_date = enriched.release_date
        }

        // Update runtime if we got one and movie doesn't have one
        if (enriched?.runtime_minutes && !movie.runtime_minutes) {
            updateData.runtime_minutes = enriched.runtime_minutes
        }

        const { data: updatedMovie, error: updateError } = await supabase
            .from('movies')
            .update(updateData)
            .eq('id', id)
            .select(`
                *,
                genres:movie_genres(
                    genre:genres(*)
                )
            `)
            .single()

        if (updateError) throw updateError

        // Update genres if enrichment returned any
        if (enriched?.genres && enriched.genres.length > 0) {
            logger.info(`[Production Movies] Received ${enriched.genres.length} genre names from enrichment:`)
            logger.info(`[Production Movies] Genre names: ${JSON.stringify(enriched.genres)}`)

            // Fetch all genres from database to map names to IDs
            const { data: allGenres, error: genresError } = await supabase
                .from('genres')
                .select('id, name')

            if (genresError) {
                logger.error('[Production Movies] Error fetching genres:', genresError)
            } else {
                logger.info(`[Production Movies] Fetched ${allGenres.length} genres from database`)

                // Create case-insensitive name-to-ID mapping
                const genreNameToId = {}
                allGenres.forEach(genre => {
                    genreNameToId[genre.name.toLowerCase()] = genre.id
                })

                // Map enrichment genre names to database genre IDs
                const genreIds = []
                const unmappedGenres = []

                enriched.genres.forEach(genreName => {
                    const normalizedName = genreName.toLowerCase().trim()
                    const genreId = genreNameToId[normalizedName]

                    if (genreId) {
                        genreIds.push(genreId)
                        logger.info(`[Production Movies] Mapped genre "${genreName}" -> ID ${genreId}`)
                    } else {
                        unmappedGenres.push(genreName)
                        logger.warn(`[Production Movies] Could not map genre "${genreName}" to database ID`)
                    }
                })

                if (unmappedGenres.length > 0) {
                    logger.warn(`[Production Movies] ${unmappedGenres.length} genres could not be mapped: ${JSON.stringify(unmappedGenres)}`)
                }

                logger.info(`[Production Movies] Successfully mapped ${genreIds.length} of ${enriched.genres.length} genres`)

                if (genreIds.length > 0) {
                    // Delete existing genre associations
                    const { error: deleteError } = await supabase
                        .from('movie_genres')
                        .delete()
                        .eq('movie_id', id)

                    if (deleteError) {
                        logger.error('[Production Movies] Error deleting existing genres:', deleteError)
                    }

                    // Insert new genre associations with mapped IDs
                    const genreAssociations = genreIds.map(genreId => ({
                        movie_id: id,
                        genre_id: genreId
                    }))

                    logger.info(`[Production Movies] Inserting ${genreAssociations.length} genre associations`)

                    const { error: insertError } = await supabase
                        .from('movie_genres')
                        .insert(genreAssociations)

                    if (insertError) {
                        logger.error('[Production Movies] Error inserting new genres:', insertError)
                    } else {
                        logger.info(`[Production Movies] Successfully updated ${genreIds.length} genres for movie ${id}`)
                    }

                    // Fetch movie again with updated genres
                    const { data: movieWithGenres, error: fetchGenresError } = await supabase
                        .from('movies')
                        .select(`
                            *,
                            genres:movie_genres(
                                genre:genres(*)
                            )
                        `)
                        .eq('id', id)
                        .single()

                    if (!fetchGenresError && movieWithGenres) {
                        updatedMovie.genres = movieWithGenres.genres
                        logger.info(`[Production Movies] Refetched movie with ${movieWithGenres.genres?.length || 0} genres`)
                    }
                } else {
                    logger.warn(`[Production Movies] No valid genre IDs to insert`)
                }
            }
        }

        // Transform genres to match expected format
        const transformedMovie = {
            ...updatedMovie,
            genres: updatedMovie.genres?.map(mg => mg.genre) || []
        }

        logger.info(`[Production Movies] Successfully enriched movie ${id} with manual IMDB ${imdbId}`)
        logger.info(`[Production Movies] Final movie has ${transformedMovie.genres.length} genres`)

        res.json({
            success: true,
            data: transformedMovie
        })

    } catch (error) {
        logger.error('[Production Movies] Manual IMDB enrichment error:', error)
        next(error)
    }
})

/**
 * POST /api/admin/movies/:id/enrich-from-data
 * Update a production movie with pre-scraped enrichment data (e.g. from local Playwright).
 * Used as a fallback when the server-side IMDB scraper is blocked.
 * Accepts: { imdbId, title, year, directors, actors, description, posterUrl, genres, imdbRating, type }
 */
router.post('/movies/:id/enrich-from-data', async (req, res, next) => {
    try {
        const { id } = req.params
        const {
            imdbId,
            title,
            year,
            directors,
            actors,
            description,
            posterUrl,
            genres,
            imdbRating,
            type
        } = req.body

        if (!imdbId || !imdbId.startsWith('tt')) {
            return res.status(400).json({
                success: false,
                error: 'Valid IMDB ID required (must start with "tt")'
            })
        }

        logger.info(`[Production Movies] enrich-from-data for movie ${id} with IMDB ${imdbId}`)

        // Check movie exists
        const { data: movie, error: fetchError } = await supabase
            .from('movies')
            .select('id, description, release_date, runtime_minutes')
            .eq('id', id)
            .single()

        if (fetchError) throw fetchError
        if (!movie) return res.status(404).json({ success: false, error: 'Movie not found' })

        const updateData = {
            imdb_id: imdbId,
            enrichment_source: 'playwright_local',
            enrichment_confidence: 1.0,
            updated_at: new Date().toISOString()
        }

        if (title) updateData.title = title
        if (posterUrl) updateData.poster_path = posterUrl
        if (imdbRating) updateData.imdb_rating = parseFloat(imdbRating)
        if (directors && directors.length) updateData.director = directors.join(', ')
        if (actors && actors.length) updateData.actors = actors.join(', ')
        if (description && !movie.description) updateData.description = description
        if (year && !movie.release_date) updateData.release_date = `${year}-01-01`
        if (type) updateData.is_tv_show = type === 'TVSeries'

        const { data: updatedMovie, error: updateError } = await supabase
            .from('movies')
            .update(updateData)
            .eq('id', id)
            .select('*, genres:movie_genres(genre:genres(*))')
            .single()

        if (updateError) throw updateError

        // Update genres if provided
        if (genres && genres.length > 0) {
            const { data: allGenres } = await supabase.from('genres').select('id, name')
            if (allGenres) {
                const nameToId = {}
                allGenres.forEach(g => { nameToId[g.name.toLowerCase()] = g.id })
                const genreIds = genres
                    .map(name => nameToId[name.toLowerCase().trim()])
                    .filter(Boolean)

                if (genreIds.length > 0) {
                    await supabase.from('movie_genres').delete().eq('movie_id', id)
                    await supabase.from('movie_genres').insert(
                        genreIds.map(genre_id => ({ movie_id: id, genre_id }))
                    )
                    logger.info(`[Production Movies] enrich-from-data: set ${genreIds.length} genres for movie ${id}`)
                }
            }
        }

        logger.info(`[Production Movies] enrich-from-data done for movie ${id}`)
        res.json({
            success: true,
            data: {
                ...updatedMovie,
                genres: updatedMovie.genres?.map(mg => mg.genre) || []
            }
        })

    } catch (error) {
        logger.error('[Production Movies] enrich-from-data error:', error)
        next(error)
    }
})

// =============================================================================
// FEATURED MOVIES MANAGEMENT (max 5, admin-controlled carousel)
// =============================================================================

// GET /api/admin/featured — list current featured movies in order
router.get('/featured', async (req, res, next) => {
    try {
        const { data, error } = await supabase
            .from('movies')
            .select('id, title, poster_path, backdrop_path, hero_image_url, release_date, imdb_rating, vote_average, featured_order')
            .eq('featured', true)
            .not('featured_order', 'is', null)
            .order('featured_order', { ascending: true })

        if (error) throw error

        res.json({
            success: true,
            data: { movies: data || [], count: (data || []).length },
            message: `${(data || []).length} featured movies`
        })
    } catch (error) {
        next(error)
    }
})

// GET /api/admin/movies/:id/hero-candidates — image options for the Hero Builder.
// Returns TMDB alternates (multiple backdrops + posters) plus the movie's current
// backdrop/poster and YouTube thumbnails, so an admin can pick the best hero image.
router.get('/movies/:id/hero-candidates', async (req, res, next) => {
    try {
        const { id } = req.params
        const { data: movie, error } = await supabase
            .from('movies')
            .select('id, title, tmdb_id, poster_path, backdrop_path, hero_image_url, youtube_video_id')
            .eq('id', id)
            .single()
        if (error) throw error
        if (!movie) return res.status(404).json({ success: false, error: 'Movie not found' })

        const TMDB = 'https://image.tmdb.org/t/p'
        const toFull = (path, size) => {
            if (!path) return null
            if (path.startsWith('http')) return path
            return `${TMDB}/${size}${path}`
        }

        const candidates = []
        const seen = new Set()
        const add = (url, type, source) => {
            if (!url || seen.has(url)) return
            seen.add(url)
            candidates.push({ url, type, source })
        }

        // TMDB alternates first (usually several backdrops to choose from)
        if (movie.tmdb_id) {
            const imgs = await tmdbService.getMovieImages(movie.tmdb_id)
            imgs.backdrops.forEach(u => add(u, 'backdrop', 'tmdb'))
            imgs.posters.forEach(u => add(u, 'poster', 'tmdb'))
        }
        // The movie's current images
        add(toFull(movie.backdrop_path, 'w1280'), 'backdrop', 'current')
        add(toFull(movie.poster_path, 'w780'), 'poster', 'current')
        // YouTube thumbnails (last resort)
        if (movie.youtube_video_id) {
            add(`https://img.youtube.com/vi/${movie.youtube_video_id}/maxresdefault.jpg`, 'thumbnail', 'youtube')
            add(`https://img.youtube.com/vi/${movie.youtube_video_id}/hqdefault.jpg`, 'thumbnail', 'youtube')
        }

        res.json({
            success: true,
            data: {
                movieId: movie.id,
                title: movie.title,
                current: movie.hero_image_url || null,
                candidates
            },
            message: `${candidates.length} hero image candidates`
        })
    } catch (error) {
        next(error)
    }
})

// POST /api/admin/featured/:movieId — feature a movie (max 5)
router.post('/featured/:movieId', async (req, res, next) => {
    try {
        const { movieId } = req.params

        // Count current featured movies
        const { data: current, error: countError } = await supabase
            .from('movies')
            .select('id, featured_order')
            .eq('featured', true)
            .not('featured_order', 'is', null)
            .order('featured_order', { ascending: true })

        if (countError) throw countError

        if (current.length >= 5) {
            return res.status(400).json({
                success: false,
                error: 'Max 5 featured movies allowed. Remove one first.'
            })
        }

        const alreadyFeatured = current.find(m => m.id === movieId)
        if (alreadyFeatured) {
            return res.status(400).json({
                success: false,
                error: 'Movie is already featured'
            })
        }

        // Assign next available slot (1–5)
        const usedOrders = current.map(m => m.featured_order)
        let nextOrder = 1
        while (usedOrders.includes(nextOrder)) nextOrder++

        const { data: updated, error: updateError } = await supabase
            .from('movies')
            .update({ featured: true, featured_order: nextOrder, updated_at: new Date().toISOString() })
            .eq('id', movieId)
            .select('id, title, featured_order')
            .single()

        if (updateError) throw updateError

        res.json({
            success: true,
            data: updated,
            message: `Movie featured at position ${nextOrder}`
        })
    } catch (error) {
        next(error)
    }
})

// DELETE /api/admin/featured/:movieId — unfeature a movie
router.delete('/featured/:movieId', async (req, res, next) => {
    try {
        const { movieId } = req.params

        const { error } = await supabase
            .from('movies')
            .update({ featured: false, featured_order: null, updated_at: new Date().toISOString() })
            .eq('id', movieId)

        if (error) throw error

        res.json({ success: true, message: 'Movie removed from featured' })
    } catch (error) {
        next(error)
    }
})

// PATCH /api/admin/featured/reorder — reorder featured movies
// Body: { movieIds: ["id1","id2",...] } — array in desired order, position = index + 1
router.patch('/featured/reorder', async (req, res, next) => {
    try {
        const { movieIds } = req.body

        if (!Array.isArray(movieIds) || movieIds.length === 0 || movieIds.length > 5) {
            return res.status(400).json({
                success: false,
                error: 'movieIds must be an array of 1–5 movie IDs'
            })
        }

        await Promise.all(
            movieIds.map((id, index) =>
                supabase
                    .from('movies')
                    .update({ featured_order: index + 1, updated_at: new Date().toISOString() })
                    .eq('id', id)
            )
        )

        res.json({ success: true, message: 'Featured movies reordered' })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// MAINTENANCE / DATA-QUALITY TOOLS
// =============================================================================

// Fetch every production row matching a Supabase filter, paging past the 1000-row cap.
async function fetchAllMovies(selectCols, applyFilters) {
    const all = []
    const pageSize = 1000
    let from = 0
    while (true) {
        let query = supabase.from('movies').select(selectCols).range(from, from + pageSize - 1)
        query = applyFilters(query)
        const { data, error } = await query
        if (error) throw error
        if (!data || data.length === 0) break
        all.push(...data)
        if (data.length < pageSize) break
        from += pageSize
    }
    return all
}

// GET /api/admin/maintenance/short-clips?maxMinutes=20
// READ-ONLY. Scans real movies (not kids, not TV) and returns those whose ACTUAL
// YouTube video length is under maxMinutes — i.e. clips/trailers mis-imported as
// movies. Uses live YouTube durations because movies.runtime_minutes holds the
// film's metadata runtime, not the video length. ~1 quota unit per 50 movies.
router.get('/maintenance/short-clips', async (req, res, next) => {
    try {
        const maxMinutes = parseInt(req.query.maxMinutes) || 20

        const movies = await fetchAllMovies(
            'id, title, youtube_video_id, runtime_minutes',
            (q) => q
                .not('is_kids_content', 'is', true)
                .not('is_tv_series', 'is', true)
                .not('is_tv_show', 'is', true)
        )

        const ids = movies.map(m => m.youtube_video_id).filter(Boolean)
        const durations = await youtubeService.getVideoDurations(ids)

        const clips = []
        const unavailable = []
        for (const m of movies) {
            const mins = durations.get(m.youtube_video_id)
            if (mins === undefined) {
                unavailable.push({ id: m.id, title: m.title, youtube_video_id: m.youtube_video_id })
                continue
            }
            if (mins < maxMinutes) {
                clips.push({ id: m.id, title: m.title, youtube_video_id: m.youtube_video_id, minutes: mins })
            }
        }
        clips.sort((a, b) => a.minutes - b.minutes)

        res.json({
            success: true,
            data: {
                scanned: movies.length,
                maxMinutes,
                clipCount: clips.length,
                clips,
                unavailableCount: unavailable.length,
                unavailable
            }
        })
    } catch (error) {
        next(error)
    }
})

// POST /api/admin/maintenance/delete-movies  { ids: [...] }
// Permanently removes the given production movies (and their movie_genres rows).
router.post('/maintenance/delete-movies', async (req, res, next) => {
    try {
        const { ids } = req.body || {}
        if (!Array.isArray(ids) || ids.length === 0) {
            return res.status(400).json({ success: false, error: 'ids must be a non-empty array' })
        }
        if (ids.length > 5000) {
            return res.status(400).json({ success: false, error: 'Too many ids in one request (max 5000)' })
        }

        // Chunk to keep each PostgREST request URL a sane length.
        const chunk = (arr, n) => arr.reduce((acc, _, i) => (i % n ? acc : [...acc, arr.slice(i, i + n)]), [])
        let deleted = 0
        for (const batch of chunk(ids, 200)) {
            await supabase.from('movie_genres').delete().in('movie_id', batch)
            const { data, error } = await supabase.from('movies').delete().in('id', batch).select('id')
            if (error) throw error
            deleted += data?.length || 0
        }

        logger.info(`[Maintenance] Deleted ${deleted}/${ids.length} production movies`)
        res.json({ success: true, data: { requested: ids.length, deleted } })
    } catch (error) {
        next(error)
    }
})

// POST /api/admin/maintenance/backfill-backdrops?dryRun=true&limit=500
// Repairs the detail-page hero for movies enriched via the manual-IMDB path, which
// used OMDB (no backdrop) and so left backdrop_path stale/blank. Re-fetches the
// correct backdrop from TMDB by imdb_id. dryRun (default true) reports proposed
// changes without writing.
router.post('/maintenance/backfill-backdrops', async (req, res, next) => {
    try {
        const dryRun = req.query.dryRun !== 'false'
        // Each row costs a rate-limited TMDB call, so keep batches small and page
        // through with offset to stay under the request timeout.
        const limit = Math.min(parseInt(req.query.limit) || 100, 300)
        const offset = parseInt(req.query.offset) || 0

        const { count: total } = await supabase
            .from('movies')
            .select('id', { count: 'exact', head: true })
            .eq('enrichment_source', 'manual_imdb')
            .not('imdb_id', 'is', null)

        const { data: movies, error } = await supabase
            .from('movies')
            .select('id, title, imdb_id, backdrop_path')
            .eq('enrichment_source', 'manual_imdb')
            .not('imdb_id', 'is', null)
            .order('id', { ascending: true })
            .range(offset, offset + limit - 1)
        if (error) throw error

        const updated = []
        const skipped = []
        for (const m of movies) {
            try {
                const find = await tmdbService.findByImdbId(m.imdb_id)
                const tm = find?.movie_results?.[0]
                if (!tm?.backdrop_path) { skipped.push({ id: m.id, title: m.title, reason: 'no TMDB backdrop' }); continue }
                if (m.backdrop_path === tm.backdrop_path) { skipped.push({ id: m.id, title: m.title, reason: 'already correct' }); continue }
                if (!dryRun) {
                    const { error: uErr } = await supabase
                        .from('movies')
                        .update({ backdrop_path: tm.backdrop_path, updated_at: new Date().toISOString() })
                        .eq('id', m.id)
                    if (uErr) throw uErr
                }
                updated.push({ id: m.id, title: m.title, from: m.backdrop_path, to: tm.backdrop_path })
            } catch (e) {
                skipped.push({ id: m.id, title: m.title, reason: e.message })
            }
        }

        res.json({
            success: true,
            data: {
                dryRun,
                total,
                offset,
                limit,
                batchSize: movies.length,
                nextOffset: offset + movies.length,
                done: offset + movies.length >= (total || 0),
                updatedCount: updated.length,
                updated: updated.slice(0, 100),
                skippedCount: skipped.length,
                skipped: skipped.slice(0, 50)
            }
        })
    } catch (error) {
        next(error)
    }
})

// POST /api/admin/maintenance/enrich-tv-series?dryRun=true   Body: { channelId }
// TV-aware enrichment. The standard batch-enrich searches TMDB *movies*, so a
// series that shares its name with a film (e.g. "Rules of Engagement") gets the
// film's poster/description. This groups a channel's staged episodes by show
// name and matches each show against TMDB's TV database once, applying the show's
// artwork/overview to every episode. dryRun (default) previews the per-show match.
router.post('/maintenance/enrich-tv-series', async (req, res, next) => {
    try {
        const dryRun = req.query.dryRun !== 'false'
        const { channelId } = req.body || {}
        if (!channelId) {
            return res.status(400).json({ success: false, error: 'channelId is required' })
        }

        // Gather episodes needing a series from BOTH staged (unpublished) and
        // production orphans (already published but with no tv_series_id — e.g.
        // number-less episodes that published before the series existed).
        const { data: staged, error: stErr } = await supabase
            .from('staged_movies')
            .select('id, title')
            .eq('channel_id', channelId)
            .eq('is_tv_series', true)
            .not('approval_status', 'in', '("published","publishing")')
        if (stErr) throw stErr

        const { data: prodOrphans, error: poErr } = await supabase
            .from('movies')
            .select('id, title')
            .eq('channel_id', channelId)
            .eq('is_tv_series', true)
            .is('tv_series_id', null)
        if (poErr) throw poErr

        const norm = (s) => (s || '').toLowerCase().replace(/[^a-z0-9]/g, '')

        // Group by show name -> { staged:[ids], prod:[ids] }
        const byShow = new Map()
        const bucket = (title) => {
            const key = (title || '').trim()
            if (!key) return null
            if (!byShow.has(key)) byShow.set(key, { staged: [], prod: [] })
            return byShow.get(key)
        }
        for (const m of (staged || [])) { const b = bucket(m.title); if (b) b.staged.push(m.id) }
        for (const m of (prodOrphans || [])) { const b = bucket(m.title); if (b) b.prod.push(m.id) }

        const shows = []
        for (const [showName, grp] of byShow) {
            const results = await tmdbService.searchTVSeries(showName)
            const best = results.find(r => norm(r.name) === norm(showName)) || results[0] || null
            const nameMatch = best ? norm(best.name) === norm(showName) : false
            shows.push({ showName, staged: grp.staged, prod: grp.prod, best, nameMatch })
        }

        let episodesUpdated = 0
        let seriesCreated = 0
        let productionLinked = 0
        if (!dryRun) {
            for (const s of shows) {
                if (!s.best || !s.best.posterPath) continue // skip non-matches (promos/awards)

                // Find or create the tv_series row (keyed by tmdb_id). Episodes with a
                // season number can't publish without a tv_series_id (check constraint
                // movies_episode_requires_series), and the app groups episodes by series.
                let seriesId
                const { data: existingSeries } = await supabase
                    .from('tv_series').select('id').eq('tmdb_id', s.best.id).maybeSingle()
                if (existingSeries) {
                    seriesId = existingSeries.id
                } else {
                    const yr = s.best.firstAirDate ? parseInt(s.best.firstAirDate.slice(0, 4)) : null
                    const { data: created, error: cErr } = await supabase
                        .from('tv_series')
                        .insert({
                            tmdb_id: s.best.id,
                            title: s.best.name,
                            description: s.best.overview || null,
                            first_air_date: s.best.firstAirDate || null,
                            poster_path: s.best.posterPath,
                            backdrop_path: s.best.backdropPath || null,
                            vote_average: s.best.voteAverage ?? null,
                            year_start: yr,
                            updated_at: new Date().toISOString()
                        })
                        .select('id').single()
                    if (cErr) throw cErr
                    seriesId = created.id
                    seriesCreated++
                }

                if (s.staged.length) {
                    const upd = {
                        tmdb_id: s.best.id,
                        tv_series_id: seriesId,
                        poster_path: s.best.posterPath,
                        backdrop_path: s.best.backdropPath || null,
                        description: s.best.overview || null,
                        release_date: s.best.firstAirDate || null,
                        vote_average: s.best.voteAverage ?? null,
                        is_tv_show: true,
                        enrichment_source: 'tmdb_tv',
                        enrichment_confidence: s.nameMatch ? 90 : 60,
                        enriched_at: new Date().toISOString(),
                        updated_at: new Date().toISOString()
                    }
                    const { error: uErr } = await supabase.from('staged_movies').update(upd).in('id', s.staged)
                    if (uErr) throw uErr
                    episodesUpdated += s.staged.length
                }

                // Link + re-art already-published orphan episodes of this show.
                if (s.prod.length) {
                    const { data: linked } = await supabase
                        .from('movies')
                        .update({
                            tv_series_id: seriesId,
                            tmdb_id: s.best.id,
                            poster_path: s.best.posterPath,
                            backdrop_path: s.best.backdropPath || null,
                            updated_at: new Date().toISOString()
                        })
                        .in('id', s.prod)
                        .select('id')
                    productionLinked += (linked?.length || 0)
                }
            }
        }

        res.json({
            success: true,
            data: {
                dryRun,
                distinctShows: shows.length,
                episodesUpdated,
                seriesCreated,
                productionLinked,
                shows: shows.map(s => ({
                    show: s.showName,
                    staged: s.staged.length,
                    published: s.prod.length,
                    matched: s.best ? `${s.best.name} (${(s.best.firstAirDate || '').slice(0, 4)}) [tv:${s.best.id}]` : null,
                    nameMatch: s.nameMatch,
                    hasPoster: !!(s.best && s.best.posterPath)
                }))
            }
        })
    } catch (error) {
        next(error)
    }
})

// POST /api/admin/maintenance/enrich-from-description?dryRun=true&limit=50&minConfidence=70
// Body: { channelId }
// For movie channels (e.g. FilmRise) whose enrichment is weak because the title
// carries junk ("- Full Movie", "- Starring X") and the real signal — cast + year —
// lives in the YouTube title/description. Cleans the title, pulls the year from the
// title, extracts cast names from the description, searches TMDB, and scores each
// candidate by cast overlap + title + year to pick the right film. dryRun previews.
router.post('/maintenance/enrich-from-description', async (req, res, next) => {
    try {
        const dryRun = req.query.dryRun !== 'false'
        const { channelId } = req.body || {}
        if (!channelId) return res.status(400).json({ success: false, error: 'channelId is required' })
        const minConfidence = parseInt(req.query.minConfidence) || 70
        // Each row can fire several rate-limited TMDB calls, so keep batches small
        // and page with offset — a whole-channel pass in one request times out (502).
        const limit = Math.min(parseInt(req.query.limit) || 20, 40)
        const offset = parseInt(req.query.offset) || 0

        const norm = (s) => (s || '').toLowerCase().replace(/[^a-z0-9]/g, '')

        // Stable, offset-paged set: all this channel's non-TV, unpublished rows.
        const { count: total } = await supabase
            .from('staged_movies')
            .select('id', { count: 'exact', head: true })
            .eq('channel_id', channelId)
            .not('is_tv_series', 'is', true)
            .not('approval_status', 'in', '("published","publishing")')

        const { data: movies, error } = await supabase
            .from('staged_movies')
            .select('id, title, youtube_video_title, description, enrichment_source, enrichment_confidence, manually_verified')
            .eq('channel_id', channelId)
            .not('is_tv_series', 'is', true)
            .not('approval_status', 'in', '("published","publishing")')
            .order('id', { ascending: true })
            .range(offset, offset + limit - 1)
        if (error) throw error

        const results = []
        let applied = 0
        for (const m of movies) {
            // Skip rows already handled or human-vetted.
            if (m.manually_verified) continue
            if (m.enrichment_source === 'tmdb_desc') continue
            if (m.enrichment_confidence != null && m.enrichment_confidence >= minConfidence) continue
            const raw = m.youtube_video_title || m.title || ''

            // Year from the raw title first, then the description.
            const ym = raw.match(/\((19|20)(\d{2})\)/) || (m.description || '').match(/\b(19|20)\d{2}\b/)
            const year = ym ? parseInt(ym[0].replace(/[()]/g, ''), 10) : null

            // Cast signal: names in the description (parenthesised / after "starring")
            // plus actor-name segments FilmRise embeds in the title
            // ("NICOLAS CAGE | Grand Isle | FULL MOVIE").
            const desc = m.description || ''
            const castSet = new Set()
            const isName = (n) => /^[A-Z][a-z]+(\s+[A-Z][a-z.'’-]+){1,2}$/.test(n)
            for (const mm of desc.matchAll(/\(([A-Z][a-z]+(?:\s+[A-Z][a-z.'-]+){1,2})\)/g)) castSet.add(mm[1])
            for (const mm of desc.matchAll(/\b(?:starring|stars?|featuring|with)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z.'-]+){1,2})/g)) castSet.add(mm[1])
            // Parse the comma-separated cast list after "Starring:"/"Stars:" (Popcornflix
            // descriptions read "... | 1992 | Starring Brigitte Nielsen (Red Sonja), Jeff Wincott").
            const starList = desc.match(/\b(?:starring|stars?)\s*:?\s*([^.|\n]+)/i)
            if (starList) {
                for (const raw2 of starList[1].split(/,|\band\b|&/)) {
                    const n = raw2.replace(/\([^)]*\)/g, '').trim()
                    if (isName(n)) castSet.add(n)
                }
            }

            const GENRE = /^(crime|thriller|horror|drama|comedy|action|sci-?fi|science fiction|romance|romantic|mystery|documentary|western|fantasy|adventure|psychological|historical|zombie|slasher|cult(\s+horror)?|inspiring.*|creature feature|unexplained ufos|.*adaptation|ghost story|murder mystery|all-new.*|based on.*|a heartwarming.*|sweet second.*|new movie|q&a.*|update of a classic)$/i
            const stripJunk = (s) => s
                .replace(/\s*\/\/.*$/, '')
                .replace(/^[A-Z][A-Z0-9 '’.]*[!?]\s+/, '')                    // leading shout "EPIC TRUE CRIME DOC! ", "AMAZING CAST! "
                .replace(/\((?:free\s+)?(?:full|complete)[^)]*\)/ig, '')     // "(Full Movie)" / "(Free Full Movie)" tag
                .replace(/\b(free\s+)?(full|complete)\s+(\w+\s+)?(movie|film|episode|documentary|special)\b.*$/i, '')
                .replace(/\s{2,}.*$/, '')                                    // cut trailing genres/cast after the gap the tag left
                .replace(/\bstarring\b.*$/i, '')
                .replace(/\((?:19|20)\d{2}\)/g, '')
                .replace(/\b(hd|4k|official|uncut|filmrise(\s+movies)?)\b/ig, '')
                .replace(/\ba\.k\.a\.?.*$/i, '')
                .replace(/\s+(g|pg|pg-13|r|nc-17|nr|unrated|tv-(?:y7?|g|pg|14|ma))\s*$/i, '') // trailing rating
                .replace(/[|\-–—:]+\s*$/, '')
                .trim()

            // Candidate title strings. For pipe-delimited titles, each non-junk,
            // non-genre segment is a candidate (the film title may be any of them);
            // 2–3 word ALL-CAPS segments are person names → cast signal, not title.
            const cand = []
            for (const seg0 of (raw.includes('|') ? raw.split('|') : [raw])) {
                const seg = seg0.trim().replace(/,\s*$/, '')
                const words = seg.split(/\s+/)
                // ALL-CAPS person name segment -> cast ("NICOLAS CAGE")
                if (/^[A-Z][A-Z .'’-]+$/.test(seg) && words.length >= 2 && words.length <= 3) {
                    castSet.add(words.map(w => w[0] + w.slice(1).toLowerCase()).join(' '))
                    continue
                }
                // comma-separated list of proper names -> cast ("David Carradine, Wes Studi")
                const parts = seg.split(',').map(s => s.trim()).filter(Boolean)
                if (parts.length >= 2 && parts.every(isName)) { parts.forEach(p => castSet.add(p)); continue }
                // pure genre descriptor segment ("Western, Family")
                if (parts.length >= 1 && parts.every(p => GENRE.test(p))) continue
                const c = stripJunk(seg)
                if (c && !GENRE.test(c)) cand.push(c)
            }
            const candTitles = [...new Set(cand.filter(Boolean))].slice(0, 3)
            const castNames = [...castSet].slice(0, 8)
            const castNorm = castNames.map(norm)

            let best = null
            let bestScore = -1
            let title = candTitles[0] || ''
            for (const ct of candTitles) {
                const candidates = await tmdbService.searchMovies(ct, year)
                for (const c of candidates.slice(0, 3)) {
                    const det = await tmdbService.getMovieDetails(c.id).catch(() => null)
                    if (!det) continue
                    const tmdbCast = new Set((det.credits?.cast || []).slice(0, 12).map(p => norm(p.name)))
                    const overlap = castNorm.filter(n => tmdbCast.has(n)).length
                    const titleMatch = norm(det.title) === norm(ct) ? 1 : 0
                    const yearMatch = (year && det.release_date && det.release_date.slice(0, 4) === String(year)) ? 1 : 0
                    const score = overlap * 3 + titleMatch * 2 + yearMatch
                    if (score > bestScore) { bestScore = score; best = { det, overlap, titleMatch, yearMatch }; title = ct }
                }
            }

            let confidence = 0
            if (best) {
                confidence = Math.min(50 + best.overlap * 15 + best.titleMatch * 20 + best.yearMatch * 10, 99)
            }

            // Require a real title or cast match (not just a coincidental year) so the
            // wider multi-segment candidate search can't apply a spurious match.
            const willApply = !dryRun && best && best.det.poster_path && confidence >= 60 &&
                (best.titleMatch === 1 || best.overlap >= 1)
            if (willApply) {
                const castStr = (best.det.credits?.cast || []).slice(0, 6).map(p => p.name).join(', ') || (castNames.join(', ') || null)
                const { error: uErr } = await supabase.from('staged_movies').update({
                    title: best.det.title,
                    tmdb_id: best.det.id,
                    imdb_id: best.det.imdb_id || null,
                    poster_path: best.det.poster_path,
                    backdrop_path: best.det.backdrop_path || null,
                    description: best.det.overview || m.description,
                    release_date: best.det.release_date || null,
                    vote_average: best.det.vote_average ?? null,
                    actors: castStr,
                    enrichment_source: 'tmdb_desc',
                    enrichment_confidence: confidence,
                    enriched_at: new Date().toISOString(),
                    updated_at: new Date().toISOString()
                }).eq('id', m.id)
                if (uErr) throw uErr
                applied++
            }

            results.push({
                cleanTitle: title,
                year,
                cast: castNames,
                matched: best ? `${best.det.title} (${(best.det.release_date || '').slice(0, 4)}) [tmdb:${best.det.id}]` : null,
                castOverlap: best ? best.overlap : 0,
                confidence,
                applied: willApply
            })
        }

        results.sort((a, b) => b.confidence - a.confidence)
        res.json({
            success: true,
            data: {
                dryRun,
                total,
                offset,
                limit,
                batchSize: movies.length,
                nextOffset: offset + movies.length,
                done: offset + movies.length >= (total || 0),
                processed: results.length,
                applied,
                confident: results.filter(r => r.confidence >= 60).length,
                weak: results.filter(r => r.confidence < 60).length,
                results
            }
        })
    } catch (error) {
        next(error)
    }
})

// POST /api/admin/maintenance/make-series?dryRun=true
// Convert a set of PRODUCTION movies into a TV series: create/find the tv_series
// (art from TMDB TV search, else the first member's art) and set is_tv_series +
// tv_series_id + season/episode on each member so they group under one series
// instead of cluttering Browse as separate movies.
// Body: {
//   seriesTitle, tmdbTvQuery?, tmdbTvId?,
//   select: { imdbId?, titleExact?, titleContains?: [..], channelId? },
//   episodeMode?: 'sequence' | 'part'   // 'part' reads "Part N" from the title
// }
router.post('/maintenance/make-series', async (req, res, next) => {
    try {
        const dryRun = req.query.dryRun !== 'false'
        const { seriesTitle, tmdbTvQuery, tmdbTvId, select = {}, episodeMode = 'sequence' } = req.body || {}
        if (!seriesTitle && !tmdbTvQuery) {
            return res.status(400).json({ success: false, error: 'seriesTitle or tmdbTvQuery is required' })
        }

        // --- select member movies ---
        let q = supabase.from('movies')
            .select('id, title, youtube_video_title, imdb_id, channel_id, created_at, poster_path, backdrop_path, description, is_tv_series, tv_series_id')
        if (select.imdbId) q = q.eq('imdb_id', select.imdbId)
        if (select.titleExact) q = q.eq('title', select.titleExact)
        if (select.channelId) q = q.eq('channel_id', select.channelId)
        if (Array.isArray(select.titleContains) && select.titleContains.length) {
            q = q.or(select.titleContains.map(t => `title.ilike.%${t}%`).join(','))
        }
        const { data: members, error } = await q
        if (error) throw error
        if (!members || members.length === 0) {
            return res.json({ success: true, data: { dryRun, members: 0, note: 'no members matched selection' } })
        }

        // --- artwork: TMDB TV, else first member with a poster ---
        let art = null
        if (tmdbTvId) {
            const d = await tmdbService.getTVSeriesDetails(tmdbTvId).catch(() => null)
            if (d) art = { tmdb_id: d.id, name: d.name, poster: d.poster_path, backdrop: d.backdrop_path, overview: d.overview, first_air_date: d.first_air_date }
        } else if (tmdbTvQuery) {
            const r = await tmdbService.searchTVSeries(tmdbTvQuery)
            const b = r[0]
            if (b) art = { tmdb_id: b.id, name: b.name, poster: b.posterPath, backdrop: b.backdropPath, overview: b.overview, first_air_date: b.firstAirDate }
        }
        const memberWithArt = members.find(m => m.poster_path)
        if (!art || !art.poster) {
            art = {
                tmdb_id: art?.tmdb_id || null,
                name: art?.name || seriesTitle,
                poster: art?.poster || memberWithArt?.poster_path || null,
                backdrop: art?.backdrop || memberWithArt?.backdrop_path || null,
                overview: art?.overview || memberWithArt?.description || null,
                first_air_date: art?.first_air_date || null
            }
        }
        const finalTitle = seriesTitle || art.name

        // --- find / create tv_series ---
        let seriesId = null
        let seriesCreated = false
        const { data: existing } = art.tmdb_id
            ? await supabase.from('tv_series').select('id').eq('tmdb_id', art.tmdb_id).maybeSingle()
            : await supabase.from('tv_series').select('id').eq('title', finalTitle).maybeSingle()
        if (!dryRun) {
            if (existing) {
                seriesId = existing.id
            } else {
                const yr = art.first_air_date ? parseInt(art.first_air_date.slice(0, 4), 10) : null
                const { data: created, error: cErr } = await supabase.from('tv_series').insert({
                    title: finalTitle,
                    tmdb_id: art.tmdb_id,
                    description: art.overview || null,
                    poster_path: art.poster || null,
                    backdrop_path: art.backdrop || null,
                    first_air_date: art.first_air_date || null,
                    year_start: yr,
                    updated_at: new Date().toISOString()
                }).select('id').single()
                if (cErr) throw cErr
                seriesId = created.id
                seriesCreated = true
            }
        }

        // --- assign episode numbers ---
        members.sort((a, b) => (a.created_at || '').localeCompare(b.created_at || ''))
        const assign = members.map((m, i) => {
            let ep = i + 1
            if (episodeMode === 'part') {
                const mm = (m.title || m.youtube_video_title || '').match(/part\s*(\d+)/i)
                if (mm) ep = parseInt(mm[1], 10)
            }
            const epName = (m.youtube_video_title || m.title || '').replace(/\s*\|.*$/, '').trim() || null
            return { id: m.id, title: m.title, episode: ep, episode_name: epName }
        })

        let updated = 0
        if (!dryRun && seriesId) {
            for (const a of assign) {
                const { error: uErr } = await supabase.from('movies').update({
                    is_tv_series: true,
                    is_tv_show: true,
                    tv_series_id: seriesId,
                    season_number: 1,
                    episode_number: a.episode,
                    episode_name: a.episode_name,
                    updated_at: new Date().toISOString()
                }).eq('id', a.id)
                if (uErr) throw uErr
                updated++
            }
        }

        res.json({
            success: true,
            data: {
                dryRun,
                seriesTitle: finalTitle,
                tmdbMatch: art.tmdb_id ? `${art.name} [tv:${art.tmdb_id}]` : '(no TMDB TV match — using member art)',
                hasPoster: !!art.poster,
                members: members.length,
                seriesCreated,
                updated,
                sampleEpisodes: assign.slice(0, 8).map(a => `E${a.episode}: ${(a.episode_name || '').slice(0, 45)}`)
            }
        })
    } catch (error) {
        next(error)
    }
})

export default router
