import { supabase } from '../config/database.js'
import { youtubeService } from '../services/youtubeService.js'
import { logger } from '../utils/logger.js'
import { startChannelImport } from '../routes/channelManagement.js'
import {
    hasQuotaForSync,
    SYNC_MIN_QUOTA_REMAINING,
    DEFAULT_SYNC_IMPORT_LIMIT
} from '../utils/syncValidationHelpers.js'

/**
 * Channel Auto-Sync
 *
 * Daily sweep (05:00 UTC, after the 03:00 link validation) that pulls the
 * latest videos from every channel with channel_settings.auto_import_enabled.
 * Each channel runs through the exact same code path as a manual
 * "import latest" (startChannelImport → processImport), so:
 * - import_history rows are written exactly like manual imports
 * - channel settings (duration filters, tags, flags) apply
 * - new imports auto-enrich immediately and the channel's
 *   auto_approve_threshold logic applies
 *
 * Channels are processed strictly sequentially. Per-channel failures are
 * logged and skipped. Before each channel the remaining YouTube quota is
 * checked and the sweep stops early when it drops below
 * SYNC_MIN_QUOTA_REMAINING (500 units).
 */

/**
 * Channels eligible for auto-sync: channel_settings.auto_import_enabled = true.
 * (channel_settings has no is_active column — verified against migration 011.)
 */
export async function getAutoSyncChannels() {
    const { data, error } = await supabase
        .from('channel_settings')
        .select('channel_id, import_limit, auto_import_schedule')
        .eq('auto_import_enabled', true)

    if (error) throw error
    return data || []
}

/**
 * Run the auto-sync sweep. Returns a summary object.
 *
 * @param {Object} options
 * @param {number} options.limit - latest-N videos to import per channel
 */
export async function runChannelAutoSync({ limit = DEFAULT_SYNC_IMPORT_LIMIT } = {}) {
    const startTime = Date.now()
    logger.info(`🔄 [Auto-Sync] Starting channel auto-sync sweep (limit ${limit} per channel)`)

    const summary = {
        channelsEligible: 0,
        channelsProcessed: 0,
        imported: 0,
        skipped: 0,
        failed: 0,
        failures: [],
        stoppedForQuota: false,
        durationSeconds: 0
    }

    let channels
    try {
        channels = await getAutoSyncChannels()
    } catch (error) {
        logger.error('[Auto-Sync] Failed to load auto-import channels:', error)
        throw error
    }

    summary.channelsEligible = channels.length

    if (channels.length === 0) {
        logger.info('[Auto-Sync] No channels with auto_import_enabled — nothing to do')
        return summary
    }

    for (const channel of channels) {
        const channelId = channel.channel_id

        // Quota guard: stop the sweep when remaining quota gets too low
        const quota = await youtubeService.quotaCheck()
        if (!hasQuotaForSync(quota)) {
            logger.warn(`[Auto-Sync] Stopping sweep: remaining YouTube quota ${quota?.totalRemaining ?? 'unknown'} < ${SYNC_MIN_QUOTA_REMAINING} units (${summary.channelsProcessed}/${channels.length} channels processed)`)
            summary.stoppedForQuota = true
            break
        }

        try {
            // Same code path as a manual import-latest, awaited so channels run
            // sequentially. Writes an import_history row like manual imports.
            const started = await startChannelImport(channelId, {
                limit,
                sortOrder: 'latest',
                applySettings: true,
                autoEnrich: true,
                waitForCompletion: true
            })

            if (!started) {
                logger.warn(`[Auto-Sync] Channel ${channelId} not found — skipping`)
                summary.failures.push({ channelId, error: 'channel not found' })
                continue
            }

            // Read the finished import_history row for per-channel counts
            const { data: importRow } = await supabase
                .from('import_history')
                .select('status, videos_imported, videos_skipped, videos_failed')
                .eq('id', started.batchId)
                .single()

            summary.channelsProcessed++
            summary.imported += importRow?.videos_imported || 0
            summary.skipped += importRow?.videos_skipped || 0
            summary.failed += importRow?.videos_failed || 0

            if (importRow?.status === 'failed') {
                summary.failures.push({ channelId, error: 'import ended with status failed' })
            }

            logger.info(`[Auto-Sync] ${started.channelTitle} (${channelId}): ${importRow?.videos_imported || 0} imported, ${importRow?.videos_skipped || 0} skipped, ${importRow?.videos_failed || 0} failed`)

        } catch (error) {
            // Continue past per-channel failures
            logger.error(`[Auto-Sync] Channel ${channelId} failed:`, error)
            summary.failures.push({ channelId, error: error.message })
        }
    }

    summary.durationSeconds = Math.round((Date.now() - startTime) / 1000)

    logger.info(`✅ [Auto-Sync] Sweep complete in ${summary.durationSeconds}s:`, {
        channels_eligible: summary.channelsEligible,
        channels_processed: summary.channelsProcessed,
        imported: summary.imported,
        skipped: summary.skipped,
        failed: summary.failed,
        failures: summary.failures.length,
        stopped_for_quota: summary.stoppedForQuota
    })

    return summary
}
