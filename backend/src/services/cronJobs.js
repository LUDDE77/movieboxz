import cron from 'node-cron'
import { movieCurator } from './movieCurator.js'
import jobScheduler from '../jobs/scheduler.js'
import { logger } from '../utils/logger.js'

export function initializeCronJobs() {
    logger.info('🕒 Initializing cron jobs for MovieBoxZ')

    // Movie curation job - runs every 6 hours
    cron.schedule(process.env.CURATION_SCHEDULE || '0 */6 * * *', async () => {
        logger.info('🎬 Starting scheduled movie curation job')

        try {
            const results = await movieCurator.curateAllChannels()
            logger.info(`✅ Scheduled curation completed: ${results.moviesAdded} movies added`)
        } catch (error) {
            logger.error('❌ Scheduled curation failed:', error.message)
        }
    }, {
        timezone: 'UTC'
    })

    // Start new validation scheduler (Phase 7: Link validation with automatic failover)
    // Includes:
    // - Daily link validation at 3 AM UTC (9,000 movies/day)
    // - Weekly cleanup on Sundays at 2 AM UTC
    // - Monthly stats on 1st of month at 1 AM UTC
    jobScheduler.start()

    logger.info('✅ Cron jobs initialized successfully')
}
