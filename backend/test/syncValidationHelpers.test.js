import { describe, it, expect } from 'vitest'
import {
    hasQuotaForSync,
    staleCutoffIso,
    normalizeAutoApproveThreshold,
    parsePositiveIntOrNull,
    mapValidationRunRow,
    SYNC_MIN_QUOTA_REMAINING,
    DEFAULT_SYNC_IMPORT_LIMIT,
    RESURRECTION_BATCH_LIMIT
} from '../src/utils/syncValidationHelpers.js'

describe('hasQuotaForSync (auto-sync quota guard)', () => {
    it('allows a sweep when total remaining quota is at or above the floor', () => {
        expect(hasQuotaForSync({ totalRemaining: 500 })).toBe(true)
        expect(hasQuotaForSync({ totalRemaining: 9500 })).toBe(true)
    })

    it('stops the sweep when total remaining quota is below the floor', () => {
        expect(hasQuotaForSync({ totalRemaining: 499 })).toBe(false)
        expect(hasQuotaForSync({ totalRemaining: 0 })).toBe(false)
    })

    it('falls back to the current key remaining when totalRemaining is missing', () => {
        expect(hasQuotaForSync({ remaining: 600 })).toBe(true)
        expect(hasQuotaForSync({ remaining: 100 })).toBe(false)
    })

    it('is conservative on missing/garbage input', () => {
        expect(hasQuotaForSync(null)).toBe(false)
        expect(hasQuotaForSync({})).toBe(false)
        expect(hasQuotaForSync({ totalRemaining: 'lots' })).toBe(false)
    })

    it('respects a custom floor', () => {
        expect(hasQuotaForSync({ totalRemaining: 300 }, 200)).toBe(true)
        expect(hasQuotaForSync({ totalRemaining: 300 }, 400)).toBe(false)
    })

    it('exports sensible defaults', () => {
        expect(SYNC_MIN_QUOTA_REMAINING).toBe(500)
        expect(DEFAULT_SYNC_IMPORT_LIMIT).toBe(25)
        expect(RESURRECTION_BATCH_LIMIT).toBe(200)
    })
})

describe('staleCutoffIso', () => {
    it('returns an ISO timestamp exactly N days before now', () => {
        const now = Date.parse('2026-07-10T12:00:00.000Z')
        expect(staleCutoffIso(7, now)).toBe('2026-07-03T12:00:00.000Z')
        expect(staleCutoffIso(1, now)).toBe('2026-07-09T12:00:00.000Z')
    })

    it('defaults to 7 days', () => {
        const now = Date.parse('2026-07-10T00:00:00.000Z')
        expect(staleCutoffIso(undefined, now)).toBe('2026-07-03T00:00:00.000Z')
    })
})

describe('normalizeAutoApproveThreshold', () => {
    it('returns positive numeric thresholds', () => {
        expect(normalizeAutoApproveThreshold(80)).toBe(80)
        expect(normalizeAutoApproveThreshold('75.5')).toBe(75.5)
    })

    it('returns null for unset, zero, negative or garbage values', () => {
        expect(normalizeAutoApproveThreshold(null)).toBe(null)
        expect(normalizeAutoApproveThreshold(undefined)).toBe(null)
        expect(normalizeAutoApproveThreshold(0)).toBe(null)
        expect(normalizeAutoApproveThreshold(-10)).toBe(null)
        expect(normalizeAutoApproveThreshold('nope')).toBe(null)
    })
})

describe('parsePositiveIntOrNull', () => {
    it('parses positive integers', () => {
        expect(parsePositiveIntOrNull(25)).toBe(25)
        expect(parsePositiveIntOrNull('10')).toBe(10)
    })

    it('returns null for missing, zero, negative or garbage values', () => {
        expect(parsePositiveIntOrNull(undefined)).toBe(null)
        expect(parsePositiveIntOrNull(null)).toBe(null)
        expect(parsePositiveIntOrNull(0)).toBe(null)
        expect(parsePositiveIntOrNull(-5)).toBe(null)
        expect(parsePositiveIntOrNull('abc')).toBe(null)
    })
})

describe('mapValidationRunRow (GET /validation/status contract)', () => {
    it('returns null for a missing row', () => {
        expect(mapValidationRunRow(null)).toBe(null)
        expect(mapValidationRunRow(undefined)).toBe(null)
    })

    it('maps a post-migration-034 row directly', () => {
        const row = {
            id: 'run-1',
            started_at: '2026-07-10T05:00:00Z',
            completed_at: '2026-07-10T05:20:00Z',
            status: 'completed',
            checked: 9000,
            unavailable_found: 12,
            resurrected: 3,
            validated_count: 8985,
            failed_count: 12
        }
        expect(mapValidationRunRow(row)).toEqual({
            id: 'run-1',
            started_at: '2026-07-10T05:00:00Z',
            completed_at: '2026-07-10T05:20:00Z',
            status: 'completed',
            checked: 9000,
            unavailable_found: 12,
            resurrected: 3
        })
    })

    it('falls back to legacy columns for pre-migration rows', () => {
        const legacy = {
            id: 'run-legacy',
            run_date: '2026-07-01T03:00:00Z',
            validated_count: 100,
            failed_count: 5,
            failover_count: 1,
            quota_used: 3
        }
        expect(mapValidationRunRow(legacy)).toEqual({
            id: 'run-legacy',
            started_at: '2026-07-01T03:00:00Z',
            completed_at: null,
            status: 'completed',
            checked: 105,
            unavailable_found: 5,
            resurrected: 0
        })
    })

    it('keeps an in-flight run visible as running', () => {
        const running = {
            id: 'run-2',
            started_at: '2026-07-10T09:00:00Z',
            status: 'running',
            checked: 0,
            unavailable_found: 0,
            resurrected: 0
        }
        const mapped = mapValidationRunRow(running)
        expect(mapped.status).toBe('running')
        expect(mapped.completed_at).toBe(null)
    })
})
