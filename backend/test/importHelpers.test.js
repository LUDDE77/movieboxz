import { describe, it, expect } from 'vitest'
import {
    parseIsoDurationMinutes,
    buildDurationFilter,
    sumQuotaUnits,
    validateRegex,
    selectVideos,
    VALID_IMPORT_SORTS,
    YOUTUBE_DAILY_BUDGET
} from '../src/utils/importHelpers.js'

describe('parseIsoDurationMinutes', () => {
    it('parses hours, minutes and seconds', () => {
        expect(parseIsoDurationMinutes('PT2H30M15S')).toBe(150)
    })

    it('parses minutes only', () => {
        expect(parseIsoDurationMinutes('PT45M')).toBe(45)
    })

    it('returns 0 for missing / invalid input', () => {
        expect(parseIsoDurationMinutes(null)).toBe(0)
        expect(parseIsoDurationMinutes('')).toBe(0)
        expect(parseIsoDurationMinutes('garbage')).toBe(0)
    })
})

describe('buildDurationFilter', () => {
    it('keeps everything when no settings', () => {
        const f = buildDurationFilter(null)
        expect(f({ duration: 'PT5S' })).toBe(true)
    })

    it('filters shorts under a minute', () => {
        const f = buildDurationFilter({ filter_shorts: true })
        expect(f({ duration: 'PT30S' })).toBe(false)
        expect(f({ duration: 'PT2M' })).toBe(true)
    })

    it('enforces min and max duration', () => {
        const f = buildDurationFilter({ min_duration_minutes: 60, max_duration_minutes: 180 })
        expect(f({ duration: 'PT40M' })).toBe(false)   // below min
        expect(f({ duration: 'PT90M' })).toBe(true)    // in range
        expect(f({ duration: 'PT200M' })).toBe(false)  // above max
    })
})

describe('sumQuotaUnits', () => {
    it('sums quota_cost across rows', () => {
        expect(sumQuotaUnits([{ quota_cost: 1 }, { quota_cost: 100 }, { quota_cost: 2 }])).toBe(103)
    })

    it('tolerates missing / non-numeric values and non-arrays', () => {
        expect(sumQuotaUnits([{ quota_cost: null }, {}, { quota_cost: '5' }])).toBe(5)
        expect(sumQuotaUnits(null)).toBe(0)
        expect(sumQuotaUnits([])).toBe(0)
    })

    it('budget constant is 10000', () => {
        expect(YOUTUBE_DAILY_BUDGET).toBe(10000)
    })
})

describe('validateRegex', () => {
    it('accepts a valid regex', () => {
        expect(validateRegex('^(.+?) \\| Full Movie$')).toEqual({ valid: true, error: null })
    })

    it('rejects an invalid regex with the compile error', () => {
        const result = validateRegex('([unclosed')
        expect(result.valid).toBe(false)
        expect(typeof result.error).toBe('string')
        expect(result.error.length).toBeGreaterThan(0)
    })
})

describe('selectVideos', () => {
    const videos = [
        { id: 'a', duration: 'PT90M' },   // newest
        { id: 'b', duration: 'PT30S' },   // short
        { id: 'c', duration: 'PT120M' },
        { id: 'd', duration: 'PT80M' }    // oldest
    ]

    it('applies the filter before the limit so limited imports do not under-deliver', () => {
        const filter = buildDurationFilter({ filter_shorts: true, min_duration_minutes: 60 })
        // Without fetch-before-filter, taking the first 2 then filtering would yield 1.
        // selectVideos filters first, then limits — so we get the full 2 requested.
        const result = selectVideos(videos, { filter, limit: 2 })
        expect(result.map(v => v.id)).toEqual(['a', 'c'])
    })

    it('reverses for oldest ordering', () => {
        const result = selectVideos(videos, { order: 'oldest' })
        expect(result.map(v => v.id)).toEqual(['d', 'c', 'b', 'a'])
    })

    it('applies oldest then limit', () => {
        const result = selectVideos(videos, { order: 'oldest', limit: 2 })
        expect(result.map(v => v.id)).toEqual(['d', 'c'])
    })
})

describe('VALID_IMPORT_SORTS', () => {
    it('includes the real sorts and excludes the fake "rating" option', () => {
        expect(VALID_IMPORT_SORTS).toContain('latest')
        expect(VALID_IMPORT_SORTS).toContain('oldest')
        expect(VALID_IMPORT_SORTS).toContain('views')
        expect(VALID_IMPORT_SORTS).not.toContain('rating')
    })
})
