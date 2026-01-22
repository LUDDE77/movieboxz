import express from 'express'
import { movieCurator } from '../services/movieCurator.js'
import { youtubeService } from '../services/youtubeService.js'
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
        const { channel } = req.body

        if (!channel) {
            return res.status(400).json({
                success: false,
                error: 'Bad Request',
                message: 'Channel identifier is required (name, ID, or URL)'
            })
        }

        logger.info(`Admin requested channel import: ${channel}`)

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

        // Step 4: Create curation job
        const job = await dbOperations.createCurationJob({
            jobType: 'channel_scan',
            channelId: channelId,
            resultSummary: {
                channelTitle: channelInfo.title,
                channelUrl: channelInfo.customUrl
            }
        })

        logger.info(`Created curation job: ${job.id} for channel: ${channelInfo.title}`)

        // Step 5: Start import process asynchronously
        // (Run in background, don't wait for completion)
        movieCurator.curateChannelMovies(channelId, { jobId: job.id })
            .then(results => {
                logger.info(`Channel import completed for ${channelInfo.title}: ${results.moviesAdded} movies added`)
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
        });

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

export default router