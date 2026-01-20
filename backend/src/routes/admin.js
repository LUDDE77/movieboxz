import express from 'express'
import { movieCurator } from '../services/movieCurator.js'
import { youtubeService } from '../services/youtubeService.js'
import { dbOperations } from '../config/database.js'
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

        // Step 3: Create curation job
        const job = await dbOperations.createCurationJob({
            jobType: 'channel_scan',
            channelId: channelId,
            resultSummary: {
                channelTitle: channelInfo.title,
                channelUrl: channelInfo.customUrl
            }
        })

        logger.info(`Created curation job: ${job.id} for channel: ${channelInfo.title}`)

        // Step 4: Start import process asynchronously
        // (Run in background, don't wait for completion)
        movieCurator.curateChannelMovies(channelId, { jobId: job.id })
            .then(results => {
                logger.info(`Channel import completed for ${channelInfo.title}: ${results.moviesAdded} movies added`)
            })
            .catch(error => {
                logger.error(`Channel import failed for ${channelInfo.title}:`, error.message)
            })

        // Step 5: Return job info immediately
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

export default router
