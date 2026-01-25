import cron from 'node-cron'
import linkValidatorService from '../services/linkValidatorService.js'
import { logger } from '../utils/logger.js'

/**
 * Job Scheduler
 *
 * Manages all scheduled background jobs:
 * - Daily link validation (3 AM UTC)
 * - Weekly cleanup tasks (Sunday 2 AM UTC)
 * - Monthly analytics (1st of month, 1 AM UTC)
 */
class JobScheduler {
    constructor() {
        this.jobs = {}
    }

    /**
     * Start all scheduled jobs
     */
    start() {
        logger.info('📅 Starting job scheduler')

        // Daily link validation at 3 AM UTC
        this.jobs.dailyValidation = cron.schedule('0 3 * * *', async () => {
            logger.info('🔄 Running scheduled daily link validation')

            try {
                const result = await linkValidatorService.runDailyValidation()

                logger.info('✅ Daily validation completed:', {
                    validated: result.validatedCount,
                    failed: result.failedCount,
                    failovers: result.failoverCount,
                    quota_used: result.quotaUsed,
                    duration_seconds: result.durationSeconds
                })

            } catch (error) {
                logger.error('❌ Daily validation failed:', error)
            }
        }, {
            scheduled: true,
            timezone: 'UTC'
        })

        // Weekly cleanup: Remove old validation failures (Sunday 2 AM UTC)
        this.jobs.weeklyCleanup = cron.schedule('0 2 * * 0', async () => {
            logger.info('🧹 Running weekly cleanup')

            try {
                await this.cleanupOldData()
                logger.info('✅ Weekly cleanup completed')
            } catch (error) {
                logger.error('❌ Weekly cleanup failed:', error)
            }
        }, {
            scheduled: true,
            timezone: 'UTC'
        })

        // Monthly stats: Generate monthly report (1st of month, 1 AM UTC)
        this.jobs.monthlyStats = cron.schedule('0 1 1 * *', async () => {
            logger.info('📊 Generating monthly statistics')

            try {
                const stats = await linkValidatorService.getValidationStats()
                logger.info('Monthly validation stats:', stats.totals)
                // TODO: Send monthly report email to admin
            } catch (error) {
                logger.error('❌ Monthly stats generation failed:', error)
            }
        }, {
            scheduled: true,
            timezone: 'UTC'
        })

        logger.info('✅ Scheduler started:', {
            daily_validation: '3:00 AM UTC',
            weekly_cleanup: 'Sunday 2:00 AM UTC',
            monthly_stats: '1st of month 1:00 AM UTC'
        })
    }

    /**
     * Stop all scheduled jobs
     */
    stop() {
        logger.info('⏹️  Stopping job scheduler')

        Object.keys(this.jobs).forEach(jobName => {
            if (this.jobs[jobName]) {
                this.jobs[jobName].stop()
                logger.info(`Stopped job: ${jobName}`)
            }
        })

        this.jobs = {}
        logger.info('✅ All jobs stopped')
    }

    /**
     * Run a job immediately (for testing)
     *
     * @param {string} jobName - Job name (dailyValidation, weeklyCleanup, etc.)
     */
    async runNow(jobName) {
        logger.info(`▶️  Running job immediately: ${jobName}`)

        switch (jobName) {
            case 'dailyValidation':
                return await linkValidatorService.runDailyValidation()

            case 'weeklyCleanup':
                return await this.cleanupOldData()

            case 'monthlyStats':
                return await linkValidatorService.getValidationStats()

            default:
                throw new Error(`Unknown job: ${jobName}`)
        }
    }

    /**
     * Cleanup old data to save database space
     *
     * Removes:
     * - Validation failures older than 90 days
     * - Validation runs older than 90 days
     * - Resolved admin alerts older than 30 days
     */
    async cleanupOldData() {
        const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString()
        const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()

        try {
            // Import supabase from database config
            const { supabase } = await import('../config/database.js')

            // Delete old validation failures
            const { error: failuresError, count: failuresDeleted } = await supabase
                .from('validation_failures')
                .delete({ count: 'exact' })
                .lt('created_at', ninetyDaysAgo)

            if (failuresError) {
                logger.error('Error deleting old validation failures:', failuresError)
            } else {
                logger.info(`Deleted ${failuresDeleted || 0} old validation failures`)
            }

            // Delete old validation runs
            const { error: runsError, count: runsDeleted } = await supabase
                .from('validation_runs')
                .delete({ count: 'exact' })
                .lt('created_at', ninetyDaysAgo)

            if (runsError) {
                logger.error('Error deleting old validation runs:', runsError)
            } else {
                logger.info(`Deleted ${runsDeleted || 0} old validation runs`)
            }

            // Delete resolved admin alerts older than 30 days
            const { error: alertsError, count: alertsDeleted } = await supabase
                .from('admin_alerts')
                .delete({ count: 'exact' })
                .eq('resolved', true)
                .lt('resolved_at', thirtyDaysAgo)

            if (alertsError) {
                logger.error('Error deleting old admin alerts:', alertsError)
            } else {
                logger.info(`Deleted ${alertsDeleted || 0} old admin alerts`)
            }

            return {
                failuresDeleted: failuresDeleted || 0,
                runsDeleted: runsDeleted || 0,
                alertsDeleted: alertsDeleted || 0
            }

        } catch (error) {
            logger.error('Error during cleanup:', error)
            throw error
        }
    }

    /**
     * Get scheduler status
     *
     * @returns {Object} Status of all jobs
     */
    getStatus() {
        const status = {}

        Object.keys(this.jobs).forEach(jobName => {
            const job = this.jobs[jobName]
            status[jobName] = {
                running: job ? true : false,
                nextRun: job ? 'Scheduled' : 'Stopped'
            }
        })

        return status
    }
}

// Export singleton instance
export default new JobScheduler()
