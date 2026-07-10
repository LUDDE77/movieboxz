import express from 'express'
import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'
import { adminAuth } from '../middleware/adminAuth.js'
import linkValidatorService from '../services/linkValidatorService.js'
import {
    mapValidationRunRow,
    parsePositiveIntOrNull,
    staleCutoffIso
} from '../utils/syncValidationHelpers.js'

const router = express.Router()

// Apply admin auth to all validation routes
router.use(adminAuth)

/**
 * POST /api/admin/validation/run
 * Body: { channelId?, limit? }
 *
 * Kicks off a link-validation run NOW (fire-and-forget) for the whole catalog
 * or a single channel. Includes the resurrection pass (re-checks currently
 * unavailable movies). Progress is trackable via the returned runId and
 * GET /api/admin/validation/status.
 *
 * Response: { success, data: { runId, scope: 'all'|'channel', started: true } }
 */
router.post('/run', async (req, res, next) => {
    try {
        const { channelId = null, limit = null } = req.body || {}
        const parsedLimit = parsePositiveIntOrNull(limit)
        const scope = channelId ? 'channel' : 'all'

        // Refuse to stack runs: reject if a run is already in flight (recent).
        // Best-effort — the status column only exists after migration 034.
        try {
            const threeHoursAgo = new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString()
            const { data: running, error: runningError } = await supabase
                .from('validation_runs')
                .select('id')
                .eq('status', 'running')
                .gte('run_date', threeHoursAgo)
                .limit(1)

            if (!runningError && running && running.length > 0) {
                return res.status(409).json({
                    success: false,
                    error: `A validation run is already in progress (run ${running[0].id})`
                })
            }
        } catch (guardError) {
            logger.warn('[Validation] Concurrent-run guard failed (continuing):', guardError.message)
        }

        const runId = await linkValidatorService.createRun({
            scope,
            channelId,
            trigger: 'manual'
        })

        // Fire-and-forget — the run updates its validation_runs row on completion
        linkValidatorService
            .runValidation({ runId, channelId, limit: parsedLimit })
            .catch(error => {
                logger.error(`[Validation] On-demand run ${runId} failed:`, error)
            })

        logger.info(`[Validation] On-demand run ${runId} started (scope: ${scope}${channelId ? `, channel: ${channelId}` : ''}${parsedLimit ? `, limit: ${parsedLimit}` : ''})`)

        res.json({
            success: true,
            data: {
                runId,
                scope,
                started: true
            }
        })
    } catch (error) {
        logger.error('[Validation] Run start error:', error)
        next(error)
    }
})

/**
 * GET /api/admin/validation/status
 *
 * Latest validation run + catalog health counts.
 *
 * Response: {
 *   success,
 *   data: {
 *     lastRun: { id, started_at, completed_at, status, checked, unavailable_found, resurrected } | null,
 *     unavailableTotal,
 *     staleTotal
 *   }
 * }
 */
router.get('/status', async (req, res, next) => {
    try {
        // Latest run (created_at exists both pre- and post-migration 034)
        const { data: runs, error: runsError } = await supabase
            .from('validation_runs')
            .select('*')
            .order('created_at', { ascending: false })
            .limit(1)

        if (runsError) throw runsError

        const lastRun = mapValidationRunRow(runs?.[0] || null)

        // Currently unavailable movies
        const { count: unavailableTotal, error: unavailableError } = await supabase
            .from('movies')
            .select('*', { count: 'exact', head: true })
            .eq('is_available', false)

        if (unavailableError) throw unavailableError

        // Stale: available movies not validated within the last 7 days (or never)
        const cutoff = staleCutoffIso()
        const { count: staleTotal, error: staleError } = await supabase
            .from('movies')
            .select('*', { count: 'exact', head: true })
            .eq('is_available', true)
            .or(`last_validated.lt.${cutoff},last_validated.is.null`)

        if (staleError) throw staleError

        res.json({
            success: true,
            data: {
                lastRun,
                unavailableTotal: unavailableTotal || 0,
                staleTotal: staleTotal || 0
            }
        })
    } catch (error) {
        logger.error('[Validation] Status error:', error)
        next(error)
    }
})

export default router
