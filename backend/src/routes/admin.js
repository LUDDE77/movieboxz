import express from 'express'
import { movieCurator } from '../services/movieCurator.js'
import { seriesCurator } from '../services/seriesCurator.js'
import { youtubeService } from '../services/youtubeService.js'
import { channelPatternDetector } from '../services/channelPatternDetector.js'
import { titleFixer } from '../scripts/fixMovieTitles.js'
import { enhancedEnrichment } from '../services/enhancedEnrichment.js'
import { dbOperations, supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'
import channelPatternManager from '../services/channelPatternManager.js'
import manualEnrichmentQueue from '../services/manualEnrichmentQueue.js'
import { adminAuth } from '../middleware/adminAuth.js'

const router = express.Router()

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

// =============================================================================
// DELETE /api/admin/channels/:channelId
// Delete a channel and all its movies
// =============================================================================
router.delete('/channels/:channelId', async (req, res, next) => {
    try {
        const { channelId } = req.params

        logger.info(`Admin triggered deletion for channel: ${channelId}`)

        // Get channel info first
        const { data: channel, error: channelError } = await supabase
            .from('youtube_channels')
            .select('channel_title, video_count')
            .eq('id', channelId)
            .single()

        if (channelError || !channel) {
            return res.status(404).json({
                success: false,
                error: 'Channel Not Found',
                message: `Channel not found: ${channelId}`
            })
        }

        // Count movies for this channel
        const { count: movieCount } = await supabase
            .from('movies')
            .select('*', { count: 'exact', head: true })
            .eq('channel_id', channelId)

        // Delete all movies from this channel
        const { error: moviesError } = await supabase
            .from('movies')
            .delete()
            .eq('channel_id', channelId)

        if (moviesError) {
            throw new Error(`Failed to delete movies: ${moviesError.message}`)
        }

        // Delete the channel
        const { error: deleteError } = await supabase
            .from('youtube_channels')
            .delete()
            .eq('id', channelId)

        if (deleteError) {
            throw new Error(`Failed to delete channel: ${deleteError.message}`)
        }

        logger.info(`✅ Deleted channel ${channel.channel_title} and ${movieCount} movies`)

        res.json({
            success: true,
            data: {
                channelId,
                channelTitle: channel.channel_title,
                moviesDeleted: movieCount
            },
            message: `Deleted channel "${channel.channel_title}" and ${movieCount} associated movies`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// CHANNEL PATTERN MANAGEMENT ROUTES
// =============================================================================

// =============================================================================
// GET /api/admin/channel-patterns
// Get all channel patterns
// =============================================================================
router.get('/channel-patterns', async (req, res, next) => {
    try {
        logger.info('Admin requested all channel patterns')

        const patterns = await channelPatternManager.getAllPatterns()

        res.json({
            success: true,
            data: {
                patterns: patterns.map(p => ({
                    id: p.id,
                    channelId: p.channel_id,
                    channelName: p.channel_name,
                    patternCount: p.patterns.length,
                    hasFallback: !!p.fallback_pattern,
                    isActive: p.is_active,
                    createdAt: p.created_at,
                    updatedAt: p.updated_at
                }))
            },
            message: `Retrieved ${patterns.length} channel patterns`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/admin/channel-patterns/:channelId
// Get pattern configuration for a specific channel
// =============================================================================
router.get('/channel-patterns/:channelId', async (req, res, next) => {
    try {
        const { channelId } = req.params

        logger.info(`Admin requested pattern for channel: ${channelId}`)

        const pattern = await channelPatternManager.getPattern(channelId)

        if (!pattern) {
            return res.status(404).json({
                success: false,
                error: 'Pattern Not Found',
                message: `No pattern configured for channel: ${channelId}`
            })
        }

        res.json({
            success: true,
            data: { pattern },
            message: 'Channel pattern retrieved successfully'
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/channel-patterns
// Create or update channel pattern configuration
// =============================================================================
router.post('/channel-patterns', async (req, res, next) => {
    try {
        const { channelId, channelName, patterns, fallbackPattern } = req.body

        if (!channelId || !channelName || !patterns) {
            return res.status(400).json({
                success: false,
                error: 'Bad Request',
                message: 'channelId, channelName, and patterns are required'
            })
        }

        logger.info(`Admin saving pattern for channel: ${channelName}`)

        const result = await channelPatternManager.savePattern(
            channelId,
            channelName,
            patterns,
            fallbackPattern
        )

        res.json({
            success: true,
            data: { pattern: result },
            message: `Channel pattern saved for: ${channelName}`
        })

    } catch (error) {
        next(error)
    }
})

// =============================================================================
// DELETE /api/admin/channel-patterns/:channelId
// Delete channel pattern configuration
// =============================================================================
router.delete('/channel-patterns/:channelId', async (req, res, next) => {
    try {
        const { channelId } = req.params

        logger.info(`Admin deleting pattern for channel: ${channelId}`)

        await channelPatternManager.deletePattern(channelId)

        res.json({
            success: true,
            message: `Channel pattern deleted for: ${channelId}`
        })

    } catch (error) {
        next(error)
    }
})

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
// PRODUCTION MOVIE MANAGEMENT
// =============================================================================

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
            'is_tv_series', 'is_kids_content', 'is_available', 'needs_verification'
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

export default router
