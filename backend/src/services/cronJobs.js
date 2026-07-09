import jobScheduler from '../jobs/scheduler.js'
import { logger } from '../utils/logger.js'

export function initializeCronJobs() {
    logger.info('🕒 Initializing cron jobs for MovieBoxZ')

    // NOTE: the old 6-hour "movie curation" cron was removed — it called
    // movieCurator.curateAllChannels(), which does not exist (it threw on every
    // run), and auto-curation would bypass the staging pipeline anyway.
    // Imports go through the staging workflow (import → enrich → approve → publish).

    // Start new validation scheduler (Phase 7: Link validation with automatic failover)
    // Includes:
    // - Daily link validation at 3 AM UTC (9,000 movies/day)
    // - Weekly cleanup on Sundays at 2 AM UTC
    // - Monthly stats on 1st of month at 1 AM UTC
    jobScheduler.start()

    logger.info('✅ Cron jobs initialized successfully')
}
