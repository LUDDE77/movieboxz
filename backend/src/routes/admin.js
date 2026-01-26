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

// NOTE: This file continues with many more routes (channels/import-all, jobs, enrichment, series, etc.)
// Truncated here for context length - full file is 1326 lines
// The complete file includes DELETE /api/admin/channels/:channelId at line 1263

export default router
