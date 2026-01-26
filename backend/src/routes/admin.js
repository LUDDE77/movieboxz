import express from 'express'
import { movieCurator } from '../services/movieCurator.js'
import { seriesCurator } from '../services/seriesCurator.js'
import { youtubeService } from '../services/youtubeService.js'
import { channelPatternDetector } from '../services/channelPatternDetector.js'
import { titleFixer } from '../scripts/fixMovieTitles.js'
import { dbOperations, supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// Simple admin authentication middleware (enhance for production)
const adminAuth = (req, res, next) => {
    const apiKey = req.headers['x-admin-api-key']

    if (!apiKey || apiKey !== process.env.ADMIN_API_KEY) {
        return res.status(401).json({
            success: false,
            error: 'Unauthorized',
            message: 'Valid admin API key required'
        })
    }

    next()
}

// Apply admin auth to all routes
router.use(adminAuth)

// =============================================================================
// POST /api/admin/curate/all
// Curate movies from all configured channels
// =============================================================================
router.post('/curate/all', async (req, res, next) => {
    try {
        logger.info('Admin triggered full channel curation')

        const results = await movieCurator.curateAllChannels()

        res.json({
            success: true,
            data: results,
            message: `Curation completed: ${results.moviesAdded} movies added from ${results.channelsProcessed} channels`
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/curate/channel/:channelId
// Curate movies from specific channel
// =============================================================================
router.post('/curate/channel/:channelId', async (req, res, next) => {
    try {
        const { channelId } = req.params

        logger.info(`Admin triggered curation for channel: ${channelId}`)

        const results = await movieCurator.curateChannelMovies(channelId)

        res.json({
            success: true,
            data: results,
            message: `Channel curation completed: ${results.moviesAdded}/${results.moviesFound} movies added`
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/validate
// Validate existing movies are still available
// =============================================================================
router.post('/validate', async (req, res, next) => {
    try {
        const limit = parseInt(req.query.limit) || 100

        logger.info(`Admin triggered movie validation (limit: ${limit})`)

        const results = await movieCurator.validateExistingMovies(limit)

        res.json({
            success: true,
            data: results,
            message: `Validation completed: ${results.stillAvailable} available, ${results.nowUnavailable} unavailable`
        })
    } catch (error) {
        next(error)
    }
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

        // Step 5: Start FULL import process with pagination (run in background)
        (async () => {
            try {
                await dbOperations.startCurationJob(job.id)

                const results = {
                    moviesFound: 0,
                    moviesAdded: 0,
                    moviesSkipped: 0,
                    errors: [],
                    channelInfo: channelInfo,
                    pagesFetched: 0
                }

                let pageToken = null
                const maxPages = 20 // Safety limit: 20 pages × 50 results = 1000 videos max

                do {
                    try {
                        logger.info(`Fetching page ${results.pagesFetched + 1} for channel ${channelInfo.title}`)

                        // Fetch videos with pagination
                        const searchParams = {
                            part: ['snippet'],
                            channelId: channelId,
                            type: 'video',
                            order: 'date',
                            maxResults: 50
                        }

                        if (pageToken) {
                            searchParams.pageToken = pageToken
                        }

                        const searchResponse = await youtubeService.youtube.search.list(searchParams)
                        youtubeService.updateQuotaUsage(100)

                        if (!searchResponse.data.items || searchResponse.data.items.length === 0) {
                            break
                        }

                        // Get video IDs for detailed info
                        const videoIds = searchResponse.data.items.map(item => item.id.videoId)

                        // Get detailed video information
                        const videosResponse = await youtubeService.youtube.videos.list({
                            part: ['snippet', 'contentDetails', 'status', 'statistics'],
                            id: videoIds
                        })
                        youtubeService.updateQuotaUsage(1)

                        const videos = videosResponse.data.items.map(video => ({
                            id: video.id,
                            title: video.snippet.title,
                            description: video.snippet.description,
                            channelId: video.snippet.channelId,
                            channelTitle: video.snippet.channelTitle,
                            publishedAt: video.snippet.publishedAt,
                            thumbnails: video.snippet.thumbnails,
                            duration: video.contentDetails.duration,
                            embeddable: video.status.embeddable,
                            uploadStatus: video.status.uploadStatus,
                            privacyStatus: video.status.privacyStatus,
                            viewCount: parseInt(video.statistics.viewCount) || 0,
                            likeCount: parseInt(video.statistics.likeCount) || 0,
                            commentCount: parseInt(video.statistics.commentCount) || 0
                        }))

                        // Process each video
                        for (const video of videos) {
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
                        }

                        // Update job progress
                        await dbOperations.updateCurationJobProgress(job.id, {
                            processed: results.moviesFound,
                            successful: results.moviesAdded,
                            failed: results.errors.length
                        })

                        results.pagesFetched++
                        pageToken = searchResponse.data.nextPageToken

                        // Small delay to respect rate limits
                        await new Promise(resolve => setTimeout(resolve, 1000))

                    } catch (error) {
                        logger.error(`Error fetching page for channel ${channelInfo.title}:`, error.message)
                        results.errors.push({
                            page: results.pagesFetched + 1,
                            error: error.message
                        })
                        break
                    }

                } while (pageToken && results.pagesFetched < maxPages)

                logger.info(`✅ FULL import completed for ${channelInfo.title}: ${results.moviesAdded} movies added from ${results.pagesFetched} pages`)

                await dbOperations.completeCurationJob(job.id, results)

            } catch (error) {
                logger.error(`FULL import failed for ${channelInfo.title}:`, error.message)
                await dbOperations.failCurationJob(job.id, error.message)
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
// POST /api/admin/enrich-tmdb
// Enrich existing movies with TMDB metadata (posters, ratings, etc.)
// =============================================================================
router.post('/enrich-tmdb', async (req, res, next) => {
    try {
        const limit = parseInt(req.query.limit) || 50

        logger.info(`Admin triggered TMDB enrichment (limit: ${limit})`)

        // Get movies without TMDB data
        const { data: movies, error } = await supabase
            .from('movies')
            .select('id, title, original_title, tmdb_id')
            .is('tmdb_id', null)
            .limit(limit)

        if (error) {
            throw new Error(`Failed to fetch movies: ${error.message}`)
        }

        logger.info(`Found ${movies.length} movies without TMDB data`)

        let enriched = 0
        let failed = 0
        const results = []

        for (const movie of movies) {
            try {
                // Try to enrich with TMDB
                const tmdbData = await movieCurator.enrichWithTMDB(movie.title || movie.original_title)

                if (tmdbData) {
                    // Extract genres before updating movie (genres go in separate table)
                    const { genres, ...movieUpdateData } = tmdbData

                    // Update movie with TMDB data (without genres)
                    await dbOperations.updateMovie(movie.id, movieUpdateData)

                    // Add genres if present
                    if (genres && genres.length > 0) {
                        await movieCurator.addMovieGenres(movie.id, genres)
                    }

                    enriched++
                    results.push({
                        id: movie.id,
                        title: movie.title,
                        status: 'enriched',
                        tmdb_id: tmdbData.tmdb_id,
                        has_poster: !!tmdbData.poster_path
                    })

                    logger.info(`✅ Enriched: ${movie.title} (TMDB ID: ${tmdbData.tmdb_id})`)
                } else {
                    failed++
                    results.push({
                        id: movie.id,
                        title: movie.title,
                        status: 'not_found'
                    })

                    logger.warn(`❌ No TMDB match: ${movie.title}`)
                }

                // Small delay to respect rate limits
                await new Promise(resolve => setTimeout(resolve, 300))

            } catch (error) {
                failed++
                results.push({
                    id: movie.id,
                    title: movie.title,
                    status: 'error',
                    error: error.message
                })

                logger.error(`❌ Error enriching ${movie.title}:`, error.message)
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
            message: `TMDB enrichment completed: ${enriched} enriched, ${failed} failed`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/enrich-omdb
// Re-enrich movies that failed TMDB using OMDb (IMDB database)
// =============================================================================
router.post('/enrich-omdb', async (req, res, next) => {
    try {
        const { limit = 100 } = req.body

        logger.info(`Admin triggered OMDb enrichment (limit: ${limit})`)

        // Find movies without TMDB or OMDb data
        // Order by updated_at DESC to prioritize recently cleaned titles
        const { data: movies, error: queryError } = await supabase
            .from('movies')
            .select('id, title, original_title, tmdb_id, imdb_id, updated_at')
            .is('tmdb_id', null)
            .is('imdb_id', null)
            .order('updated_at', { ascending: false })
            .limit(limit)

        if (queryError) {
            throw new Error(`Database query failed: ${queryError.message}`)
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

        let enriched = 0
        let failed = 0
        const results = []

        for (const movie of movies) {
            try {
                // Try OMDb enrichment
                const omdbData = await movieCurator.enrichWithOMDb(
                    movie.title || movie.original_title
                )

                if (omdbData) {
                    // Update movie with OMDb data
                    const { error: updateError } = await supabase
                        .from('movies')
                        .update({
                            imdb_id: omdbData.imdb_id,
                            poster_path: omdbData.poster_path,
                            description: omdbData.description,
                            release_date: omdbData.release_date,
                            runtime_minutes: omdbData.runtime_minutes,
                            imdb_rating: omdbData.imdb_rating,
                            imdb_votes: omdbData.imdb_votes,
                            rated: omdbData.rated,
                            director: omdbData.director,
                            actors: omdbData.actors,
                            language: omdbData.language,
                            country: omdbData.country,
                            is_tv_show: omdbData.is_tv_show,
                            enrichment_source: 'omdb',
                            updated_at: new Date().toISOString()
                        })
                        .eq('id', movie.id)

                    if (updateError) {
                        throw new Error(`Database update failed: ${updateError.message}`)
                    }

                    enriched++
                    results.push({
                        id: movie.id,
                        title: movie.title,
                        status: 'enriched',
                        imdb_id: omdbData.imdb_id,
                        has_poster: !!omdbData.poster_path
                    })

                    logger.info(`✅ OMDb enriched: ${movie.title} (IMDB: ${omdbData.imdb_id})`)
                } else {
                    failed++
                    results.push({
                        id: movie.id,
                        title: movie.title,
                        status: 'not_found'
                    })
                }

            } catch (error) {
                logger.error(`❌ Error enriching ${movie.title}:`, error.message)
                failed++
                results.push({
                    id: movie.id,
                    title: movie.title,
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
            message: `OMDb enrichment completed: ${enriched} enriched, ${failed} failed`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// TV SERIES ADMIN ROUTES
// =============================================================================

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

export default router
