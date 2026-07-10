/**
 * Pure helpers for channel auto-sync and on-demand link validation.
 * No DB or network access — unit testable (see test/syncValidationHelpers.test.js).
 */

// Auto-sync stops sweeping channels when remaining YouTube quota drops below this
export const SYNC_MIN_QUOTA_REMAINING = 500

// Latest-N videos fetched per channel during an auto-sync sweep
export const DEFAULT_SYNC_IMPORT_LIMIT = 25

// Movies whose last_validated is older than this are considered stale
export const STALE_VALIDATION_DAYS = 7

// Max dead (is_available = false) movies re-checked per validation run
export const RESURRECTION_BATCH_LIMIT = 200

/**
 * Quota-guard decision for the auto-sync sweep.
 * Takes the object returned by youtubeService.quotaCheck() and answers:
 * "is there enough quota left to safely import another channel?"
 *
 * Uses totalRemaining (across all API keys) when present, falling back to the
 * current key's remaining.
 */
export function hasQuotaForSync(quotaStatus, minRemaining = SYNC_MIN_QUOTA_REMAINING) {
    if (!quotaStatus) return false
    const remaining = Number(quotaStatus.totalRemaining ?? quotaStatus.remaining)
    return Number.isFinite(remaining) && remaining >= minRemaining
}

/**
 * ISO timestamp for the stale-validation cutoff (now - days).
 */
export function staleCutoffIso(days = STALE_VALIDATION_DAYS, now = Date.now()) {
    return new Date(now - days * 24 * 60 * 60 * 1000).toISOString()
}

/**
 * Normalize a channel's auto_approve_threshold to a number (0-100) or null when
 * unset / invalid / <= 0. Mirrors staging-simple's getAutoApproveThreshold but
 * works on an already-loaded settings value.
 */
export function normalizeAutoApproveThreshold(value) {
    const threshold = parseFloat(value)
    if (Number.isNaN(threshold)) return null
    return threshold > 0 ? threshold : null
}

/**
 * Parse a user-supplied positive integer limit; returns null (no limit) when
 * missing or invalid.
 */
export function parsePositiveIntOrNull(value) {
    const n = Number.parseInt(value, 10)
    return Number.isInteger(n) && n > 0 ? n : null
}

/**
 * Map a validation_runs row to the API contract shape for GET /validation/status.
 * Tolerates rows written before migration 034 (extended columns missing) by
 * falling back to the legacy columns.
 *
 * Contract: { id, started_at, completed_at, status, checked, unavailable_found, resurrected }
 */
export function mapValidationRunRow(row) {
    if (!row) return null
    return {
        id: row.id,
        started_at: row.started_at ?? row.run_date ?? row.created_at ?? null,
        completed_at: row.completed_at ?? null,
        status: row.status ?? 'completed',
        checked: row.checked ?? ((row.validated_count || 0) + (row.failed_count || 0)),
        unavailable_found: row.unavailable_found ?? row.failed_count ?? 0,
        resurrected: row.resurrected ?? 0
    }
}
