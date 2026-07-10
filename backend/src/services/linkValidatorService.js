import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'
import duplicateDetector from './duplicateDetector.js'
import { RESURRECTION_BATCH_LIMIT } from '../utils/syncValidationHelpers.js'

/**
 * LinkValidatorService
 *
 * Daily validation service that:
 * 1. Checks ~9,000 movies per day (uses 9,000/10,000 YouTube API quota)
 * 2. Detects unavailable videos (deleted, private, etc.)
 * 3. Automatically promotes backups when primary videos fail
 * 4. Alerts admins when all backups fail
 *
 * Runs once daily at 3 AM UTC via cron job
 */
class LinkValidatorService {
    constructor() {
        // YouTube API quota limits
        this.DAILY_QUOTA = 10000  // Total daily quota
        this.COST_PER_VIDEO_CHECK = 1  // videos.list costs 1 unit
        this.MAX_DAILY_CHECKS = 9000  // Leave 1000 units for other operations

        // Batch processing
        this.BATCH_SIZE = 50  // YouTube API allows 50 video IDs per request
        this.RATE_LIMIT_DELAY_MS = 1000  // Pause 1 second between batches

        // API endpoint
        this.YOUTUBE_API_KEY = process.env.YOUTUBE_API_KEY
        this.YOUTUBE_VIDEOS_ENDPOINT = 'https://www.googleapis.com/youtube/v3/videos'
    }

    /**
     * Run daily validation job
     *
     * Main entry point called by cron scheduler. Creates a trackable
     * validation_runs row and validates the whole catalog, including the
     * resurrection pass for currently-unavailable movies.
     */
    async runDailyValidation() {
        const runId = await this.createRun({ scope: 'all', trigger: 'scheduled' })
        return await this.runValidation({ runId })
    }

    /**
     * Create a validation_runs row in 'running' state and return its id.
     *
     * Falls back to a legacy (pre-migration-034) insert if the extended
     * columns don't exist yet, so validation keeps working either way.
     *
     * @param {Object} options
     * @param {string} options.scope - 'all' or 'channel'
     * @param {string|null} options.channelId - channel id when scope is 'channel'
     * @param {string} options.trigger - 'scheduled' or 'manual'
     * @returns {Promise<string|null>} run id (null only if even the legacy insert fails)
     */
    async createRun({ scope = 'all', channelId = null, trigger = 'scheduled' } = {}) {
        const now = new Date().toISOString()

        let { data, error } = await supabase
            .from('validation_runs')
            .insert({
                run_date: now,
                started_at: now,
                status: 'running',
                scope,
                channel_id: channelId,
                triggered_by: trigger
            })
            .select('id')
            .single()

        if (error) {
            logger.warn(`validation_runs extended insert failed (migration 034 applied?): ${error.message} — falling back to legacy columns`)
            ;({ data, error } = await supabase
                .from('validation_runs')
                .insert({ run_date: now })
                .select('id')
                .single())

            if (error) {
                logger.error('Failed to create validation run row:', error)
                return null
            }
        }

        return data.id
    }

    /**
     * Core validation pass. Checks:
     * 1. Available movies (oldest-validated first) — marks dead ones unavailable
     *    and attempts failover for primaries.
     * 2. RESURRECTION PASS: currently-unavailable movies (capped at
     *    RESURRECTION_BATCH_LIMIT per run) — when a dead video is alive again,
     *    flips is_available back to true.
     *
     * Updates the validation_runs row (if runId given) on completion/failure.
     *
     * @param {Object} options
     * @param {string|null} options.runId - validation_runs row to update
     * @param {string|null} options.channelId - limit the run to one channel
     * @param {number|null} options.limit - max available movies to check (defaults to MAX_DAILY_CHECKS)
     */
    async runValidation({ runId = null, channelId = null, limit = null } = {}) {
        const startTime = Date.now()
        const maxChecks = limit || this.MAX_DAILY_CHECKS
        logger.info(`🔍 Starting link validation run${runId ? ` ${runId}` : ''}${channelId ? ` (channel ${channelId})` : ' (all channels)'}, limit ${maxChecks}`)

        try {
            // 1. Available movies that need validation (oldest first)
            let activeQuery = supabase
                .from('movies')
                .select('id, youtube_video_id, title, movie_group_id, is_primary, last_validated, is_available')
                .eq('is_available', true)
                .order('last_validated', { ascending: true, nullsFirst: true })
                .limit(maxChecks)
            if (channelId) activeQuery = activeQuery.eq('channel_id', channelId)

            const { data: activeMovies, error } = await activeQuery
            if (error) throw error

            // 2. Resurrection candidates: dead movies, oldest-checked first, capped
            const resurrectionCap = Math.min(RESURRECTION_BATCH_LIMIT, maxChecks)
            let deadQuery = supabase
                .from('movies')
                .select('id, youtube_video_id, title, movie_group_id, is_primary, last_validated, is_available')
                .eq('is_available', false)
                .order('last_validated', { ascending: true, nullsFirst: true })
                .limit(resurrectionCap)
            if (channelId) deadQuery = deadQuery.eq('channel_id', channelId)

            const { data: deadMovies, error: deadError } = await deadQuery
            if (deadError) {
                logger.error('Failed to fetch resurrection candidates (continuing without):', deadError)
            }

            const movies = [...(activeMovies || []), ...(deadMovies || [])]

            if (movies.length === 0) {
                logger.info('No movies to validate')
                const emptyStats = { checked: 0, validatedCount: 0, failedCount: 0, failoverCount: 0, resurrected: 0, quotaUsed: 0, durationSeconds: 0 }
                await this.finalizeRun(runId, emptyStats)
                return emptyStats
            }

            logger.info(`Found ${movies.length} movies to validate (${(activeMovies || []).length} active, ${(deadMovies || []).length} resurrection candidates)`)

            let validatedCount = 0
            let failedCount = 0
            let failoverCount = 0
            let resurrected = 0
            let quotaUsed = 0
            let checked = 0

            // Process in batches of 50
            for (let i = 0; i < movies.length; i += this.BATCH_SIZE) {
                const batch = movies.slice(i, i + this.BATCH_SIZE)
                const videoIds = batch.map(m => m.youtube_video_id).join(',')

                try {
                    // Check video availability (batch request)
                    const results = await this.checkVideosAvailability(videoIds)
                    quotaUsed += 1  // videos.list costs 1 unit regardless of batch size

                    // Process each movie in the batch
                    for (const movie of batch) {
                        const videoData = results[movie.youtube_video_id]
                        const isAlive = videoData && videoData.status !== 'unavailable'
                        checked++

                        if (isAlive && movie.is_available === false) {
                            // RESURRECTION: dead video is alive again
                            await this.resurrectMovie(movie)
                            resurrected++
                        } else if (isAlive) {
                            // Video is available - update last_validated
                            await this.updateValidationTimestamp(movie.id)
                            validatedCount++
                        } else if (movie.is_available === false) {
                            // Still dead — just bump last_validated so the
                            // resurrection batch rotates (no duplicate failure logs)
                            await this.updateValidationTimestamp(movie.id)
                        } else {
                            // Newly unavailable video
                            await this.handleUnavailableVideo(movie, videoData?.reason || 'unknown')
                            failedCount++

                            // If this was primary, attempt failover
                            if (movie.is_primary) {
                                const failedOver = await this.attemptFailover(movie.movie_group_id, movie.id)
                                if (failedOver) {
                                    failoverCount++
                                }
                            }
                        }
                    }

                } catch (batchError) {
                    logger.error('Batch validation error:', batchError)
                    // Continue with next batch even if this one fails
                }

                // Rate limiting: pause between batches
                if (i + this.BATCH_SIZE < movies.length) {
                    await this.sleep(this.RATE_LIMIT_DELAY_MS)
                }

                // Progress logging every 500 movies
                if ((i + this.BATCH_SIZE) % 500 === 0) {
                    logger.info(`Progress: ${i + this.BATCH_SIZE}/${movies.length} movies checked`)
                }
            }

            const duration = Math.round((Date.now() - startTime) / 1000)
            logger.info(`✅ Validation complete in ${duration}s: ${validatedCount} valid, ${failedCount} failed, ${failoverCount} failovers, ${resurrected} resurrected`)

            const stats = {
                checked,
                validatedCount,
                failedCount,
                failoverCount,
                resurrected,
                quotaUsed,
                durationSeconds: duration
            }

            // Update the validation_runs row
            await this.finalizeRun(runId, stats)

            return stats

        } catch (error) {
            logger.error('❌ Validation run failed:', error)
            await this.markRunFailed(runId, error)
            throw error
        }
    }

    /**
     * Re-enable a movie whose YouTube video came back online.
     *
     * @param {Object} movie - Movie row (was is_available = false)
     */
    async resurrectMovie(movie) {
        try {
            const { error } = await supabase
                .from('movies')
                .update({
                    is_available: true,
                    validation_error: null,
                    last_validated: new Date().toISOString()
                })
                .eq('id', movie.id)

            if (error) throw error

            logger.info(`🪄 Resurrected: "${movie.title}" — video is available again`, {
                movie_id: movie.id,
                youtube_video_id: movie.youtube_video_id
            })
        } catch (error) {
            logger.error(`Error resurrecting movie ${movie.id}:`, error)
        }
    }

    /**
     * Mark a validation_runs row completed with final stats.
     * Falls back to legacy columns if migration 034 isn't applied yet.
     */
    async finalizeRun(runId, stats) {
        if (!runId) {
            // No trackable row (legacy insert also failed) — keep the old behavior
            await this.logValidationRun(stats)
            return
        }

        const legacyFields = {
            validated_count: stats.validatedCount,
            failed_count: stats.failedCount,
            failover_count: stats.failoverCount,
            quota_used: stats.quotaUsed
        }

        const { error } = await supabase
            .from('validation_runs')
            .update({
                ...legacyFields,
                status: 'completed',
                completed_at: new Date().toISOString(),
                checked: stats.checked,
                unavailable_found: stats.failedCount,
                resurrected: stats.resurrected
            })
            .eq('id', runId)

        if (error) {
            logger.warn(`validation_runs extended update failed (migration 034 applied?): ${error.message} — falling back to legacy columns`)
            const { error: legacyError } = await supabase
                .from('validation_runs')
                .update(legacyFields)
                .eq('id', runId)
            if (legacyError) {
                logger.error('Error finalizing validation run:', legacyError)
            }
        }
    }

    /**
     * Mark a validation_runs row failed. Best-effort — never throws.
     */
    async markRunFailed(runId, error) {
        if (!runId) return
        try {
            const { error: updateError } = await supabase
                .from('validation_runs')
                .update({
                    status: 'failed',
                    completed_at: new Date().toISOString(),
                    error_message: error?.message || 'unknown error'
                })
                .eq('id', runId)
            if (updateError) {
                logger.error('Error marking validation run failed:', updateError)
            }
        } catch (e) {
            logger.error('Error marking validation run failed:', e)
        }
    }

    /**
     * Check multiple videos in a single API call (batch request)
     *
     * @param {string} videoIds - Comma-separated video IDs (max 50)
     * @returns {Promise<Object>} Map of video ID → status
     */
    async checkVideosAvailability(videoIds) {
        try {
            const url = `${this.YOUTUBE_VIDEOS_ENDPOINT}?` +
                `part=status&id=${videoIds}&key=${this.YOUTUBE_API_KEY}`

            const response = await fetch(url, { signal: AbortSignal.timeout(10000) })
            const data = await response.json()

            if (!response.ok) {
                throw new Error(`YouTube API error: ${data.error?.message || 'Unknown error'}`)
            }

            // Build result map
            const results = {}
            const requestedIds = videoIds.split(',')

            for (const id of requestedIds) {
                const videoData = data.items?.find(item => item.id === id)

                if (!videoData) {
                    // Video not found = deleted or made private
                    results[id] = { status: 'unavailable', reason: 'not_found' }
                } else if (videoData.status.privacyStatus === 'private') {
                    results[id] = { status: 'unavailable', reason: 'private' }
                } else if (videoData.status.uploadStatus !== 'processed') {
                    results[id] = { status: 'unavailable', reason: 'not_processed' }
                } else {
                    results[id] = {
                        status: 'available',
                        embeddable: videoData.status.embeddable,
                        privacyStatus: videoData.status.privacyStatus
                    }
                }
            }

            return results

        } catch (error) {
            logger.error('YouTube API error:', error)
            throw error
        }
    }

    /**
     * Mark video as unavailable and record reason
     *
     * @param {Object} movie - Movie object
     * @param {string} reason - Failure reason (not_found, private, etc.)
     */
    async handleUnavailableVideo(movie, reason) {
        try {
            // Update movie status
            const { error: updateError } = await supabase
                .from('movies')
                .update({
                    is_available: false,
                    last_validated: new Date().toISOString(),
                    validation_error: reason
                })
                .eq('id', movie.id)

            if (updateError) {
                throw updateError
            }

            // Log the failure
            const { error: logError } = await supabase
                .from('validation_failures')
                .insert({
                    movie_id: movie.id,
                    youtube_video_id: movie.youtube_video_id,
                    failure_reason: reason,
                    detected_at: new Date().toISOString(),
                    is_primary: movie.is_primary
                })

            if (logError) {
                logger.error('Failed to log validation failure:', logError)
            }

            logger.warn(`Video unavailable: ${movie.title} (${reason})`, {
                movie_id: movie.id,
                youtube_video_id: movie.youtube_video_id,
                is_primary: movie.is_primary
            })

        } catch (error) {
            logger.error('Error handling unavailable video:', error)
            throw error
        }
    }

    /**
     * Update validation timestamp for available video
     *
     * @param {string} movieId - Movie ID
     */
    async updateValidationTimestamp(movieId) {
        try {
            const { error } = await supabase
                .from('movies')
                .update({ last_validated: new Date().toISOString() })
                .eq('id', movieId)

            if (error) {
                throw error
            }

        } catch (error) {
            logger.error('Error updating validation timestamp:', error)
            // Non-critical error, don't throw
        }
    }

    /**
     * Attempt to failover to a backup version
     *
     * @param {string} movieGroupId - Movie group ID
     * @param {string} failedPrimaryId - ID of failed primary
     * @returns {Promise<boolean>} True if failover succeeded
     */
    async attemptFailover(movieGroupId, failedPrimaryId) {
        try {
            logger.info(`Attempting failover for group ${movieGroupId}`)

            // Find best available backup
            const { data: backups, error } = await supabase
                .from('movies')
                .select('id, youtube_video_id, quality_score, title')
                .eq('movie_group_id', movieGroupId)
                .eq('is_available', true)
                .eq('is_primary', false)
                .order('quality_score', { ascending: false })
                .limit(3)  // Get top 3 backups

            if (error) {
                throw error
            }

            if (!backups || backups.length === 0) {
                logger.error(`No backups available for group ${movieGroupId}`)
                await this.notifyAdminAllBackupsFailed(movieGroupId)
                return false
            }

            // Validate backups before promoting (prevent cascade failures)
            for (const backup of backups) {
                const isValid = await this.validateSingleVideo(backup.youtube_video_id)

                if (isValid) {
                    // Promote this backup to primary
                    await this.promoteBackupToPrimary(backup.id, movieGroupId, failedPrimaryId)
                    logger.info(`✅ Failover successful: promoted ${backup.title}`, {
                        new_primary_id: backup.id,
                        old_primary_id: failedPrimaryId,
                        quality_score: backup.quality_score
                    })
                    return true
                } else {
                    // Backup also failed - mark it as unavailable
                    logger.warn(`Backup ${backup.title} also unavailable`)
                    await this.handleUnavailableVideo(backup, 'validation_failed')
                }
            }

            // All backups failed
            logger.error(`All backups failed for group ${movieGroupId}`)
            await this.notifyAdminAllBackupsFailed(movieGroupId)
            return false

        } catch (error) {
            logger.error('Failover error:', error)
            return false
        }
    }

    /**
     * Validate a single video (used for backup verification)
     *
     * @param {string} videoId - YouTube video ID
     * @returns {Promise<boolean>} True if available
     */
    async validateSingleVideo(videoId) {
        try {
            const results = await this.checkVideosAvailability(videoId)
            return results[videoId]?.status === 'available'
        } catch (error) {
            logger.error('Error validating single video:', error)
            return false
        }
    }

    /**
     * Promote backup to primary
     *
     * @param {string} backupId - Backup movie ID
     * @param {string} movieGroupId - Movie group ID
     * @param {string} oldPrimaryId - Old primary ID
     */
    async promoteBackupToPrimary(backupId, movieGroupId, oldPrimaryId) {
        try {
            // Update backup to primary
            const { error: promoteError } = await supabase
                .from('movies')
                .update({
                    is_primary: true,
                    last_validated: new Date().toISOString()
                })
                .eq('id', backupId)

            if (promoteError) {
                throw promoteError
            }

            // Log failover event
            const { error: logError } = await supabase
                .from('failover_events')
                .insert({
                    movie_group_id: movieGroupId,
                    old_primary_id: oldPrimaryId,
                    new_primary_id: backupId,
                    triggered_at: new Date().toISOString()
                })

            if (logError) {
                logger.error('Failed to log failover event:', logError)
            }

        } catch (error) {
            logger.error('Error promoting backup:', error)
            throw error
        }
    }

    /**
     * Notify admin when all versions of a movie are unavailable
     *
     * @param {string} movieGroupId - Movie group ID
     */
    async notifyAdminAllBackupsFailed(movieGroupId) {
        try {
            // Get movie group info
            const { data: group, error: groupError } = await supabase
                .from('movie_groups')
                .select('canonical_title, tmdb_id')
                .eq('id', movieGroupId)
                .single()

            if (groupError) {
                logger.error('Error fetching movie group:', groupError)
            }

            const message = `All versions of "${group?.canonical_title || 'Unknown'}" (Group ${movieGroupId}) are unavailable`

            // Create admin alert
            const { error } = await supabase
                .from('admin_alerts')
                .insert({
                    type: 'all_backups_failed',
                    movie_group_id: movieGroupId,
                    message,
                    severity: 'critical'
                })

            if (error) {
                logger.error('Failed to create admin alert:', error)
            }

            logger.error(`🚨 ALERT: ${message}`)

            // TODO: Send email/Slack notification to admin
            // await emailService.sendAlert(message)
            // await slackService.sendAlert(message)

        } catch (error) {
            logger.error('Error notifying admin:', error)
        }
    }

    /**
     * Log validation run statistics
     *
     * @param {Object} stats - Validation statistics
     */
    async logValidationRun(stats) {
        try {
            const { error } = await supabase
                .from('validation_runs')
                .insert({
                    run_date: new Date().toISOString(),
                    validated_count: stats.validatedCount,
                    failed_count: stats.failedCount,
                    failover_count: stats.failoverCount,
                    quota_used: stats.quotaUsed
                })

            if (error) {
                throw error
            }

        } catch (error) {
            logger.error('Error logging validation run:', error)
            // Non-critical error, don't throw
        }
    }

    /**
     * Get validation statistics
     *
     * @returns {Promise<Object>} Recent validation stats
     */
    async getValidationStats() {
        try {
            const { data: runs, error } = await supabase
                .from('validation_runs')
                .select('*')
                .order('run_date', { ascending: false })
                .limit(30)  // Last 30 days

            if (error) {
                throw error
            }

            // Calculate totals
            const totals = (runs || []).reduce((acc, run) => ({
                totalValidated: acc.totalValidated + run.validated_count,
                totalFailed: acc.totalFailed + run.failed_count,
                totalFailovers: acc.totalFailovers + run.failover_count,
                totalQuotaUsed: acc.totalQuotaUsed + run.quota_used
            }), {
                totalValidated: 0,
                totalFailed: 0,
                totalFailovers: 0,
                totalQuotaUsed: 0
            })

            return {
                recent_runs: runs,
                totals,
                average_daily_quota: totals.totalQuotaUsed / Math.max(runs.length, 1)
            }

        } catch (error) {
            logger.error('Error getting validation stats:', error)
            throw error
        }
    }

    /**
     * Sleep helper for rate limiting
     *
     * @param {number} ms - Milliseconds to sleep
     */
    sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms))
    }
}

// Export singleton instance
export default new LinkValidatorService()
