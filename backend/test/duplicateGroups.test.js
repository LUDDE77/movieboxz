import { describe, it, expect } from 'vitest'
import {
    isUuid,
    imdbKey,
    episodeKey,
    findDuplicateKeys,
    sameDuplicateGroup,
    validateResolveRequest
} from '../src/utils/duplicateGroups.js'

const UUID_A = '11111111-1111-4111-8111-111111111111'
const UUID_B = '22222222-2222-4222-8222-222222222222'
const UUID_C = '33333333-3333-4333-8333-333333333333'
const SERIES = '6c783b97-5cd1-4e12-a5b2-742b54fb2784'

describe('isUuid', () => {
    it('accepts valid uuids and rejects everything else', () => {
        expect(isUuid(UUID_A)).toBe(true)
        expect(isUuid('not-a-uuid')).toBe(false)
        expect(isUuid('')).toBe(false)
        expect(isUuid(null)).toBe(false)
        expect(isUuid(42)).toBe(false)
    })
})

describe('imdbKey / episodeKey', () => {
    it('imdbKey returns the imdb_id or null', () => {
        expect(imdbKey({ imdb_id: 'tt0126158' })).toBe('tt0126158')
        expect(imdbKey({ imdb_id: null })).toBeNull()
        expect(imdbKey(null)).toBeNull()
    })

    it('episodeKey requires the complete triple', () => {
        expect(episodeKey({ tv_series_id: SERIES, season_number: 1, episode_number: 2 }))
            .toBe(`${SERIES}:S1:E2`)
        expect(episodeKey({ tv_series_id: SERIES, season_number: null, episode_number: 2 })).toBeNull()
        expect(episodeKey({ tv_series_id: SERIES, season_number: 1, episode_number: null })).toBeNull()
        expect(episodeKey({ tv_series_id: null, season_number: 1, episode_number: 2 })).toBeNull()
        expect(episodeKey(null)).toBeNull()
    })

    it('episodeKey allows season/episode 0 semantics via == null check', () => {
        expect(episodeKey({ tv_series_id: SERIES, season_number: 0, episode_number: 0 }))
            .toBe(`${SERIES}:S0:E0`)
    })
})

describe('findDuplicateKeys', () => {
    it('returns only keys appearing more than once', () => {
        const rows = [
            { imdb_id: 'tt1' }, { imdb_id: 'tt1' },
            { imdb_id: 'tt2' },
            { imdb_id: 'tt3' }, { imdb_id: 'tt3' }, { imdb_id: 'tt3' },
            { imdb_id: null }
        ]
        expect(findDuplicateKeys(rows, imdbKey).sort()).toEqual(['tt1', 'tt3'])
    })

    it('ignores rows with null keys and handles empty input', () => {
        expect(findDuplicateKeys([{ imdb_id: null }, { imdb_id: null }], imdbKey)).toEqual([])
        expect(findDuplicateKeys([], imdbKey)).toEqual([])
        expect(findDuplicateKeys(null, imdbKey)).toEqual([])
    })

    it('works with episode keys', () => {
        const rows = [
            { tv_series_id: SERIES, season_number: 1, episode_number: 1 },
            { tv_series_id: SERIES, season_number: 1, episode_number: 1 },
            { tv_series_id: SERIES, season_number: 1, episode_number: 2 }
        ]
        expect(findDuplicateKeys(rows, episodeKey)).toEqual([`${SERIES}:S1:E1`])
    })
})

describe('sameDuplicateGroup', () => {
    it('matches on shared non-null imdb_id', () => {
        expect(sameDuplicateGroup({ imdb_id: 'tt1' }, { imdb_id: 'tt1' })).toBe(true)
        expect(sameDuplicateGroup({ imdb_id: 'tt1' }, { imdb_id: 'tt2' })).toBe(false)
    })

    it('never matches on null imdb_id alone', () => {
        expect(sameDuplicateGroup({ imdb_id: null }, { imdb_id: null })).toBe(false)
    })

    it('matches on the same episode triple even without imdb ids', () => {
        const keep = { imdb_id: null, tv_series_id: SERIES, season_number: 1, episode_number: 3 }
        const dupe = { imdb_id: null, tv_series_id: SERIES, season_number: 1, episode_number: 3 }
        const other = { imdb_id: null, tv_series_id: SERIES, season_number: 1, episode_number: 4 }
        expect(sameDuplicateGroup(keep, dupe)).toBe(true)
        expect(sameDuplicateGroup(keep, other)).toBe(false)
    })

    it('rejects incomplete episode triples', () => {
        const keep = { tv_series_id: SERIES, season_number: null, episode_number: 3 }
        const other = { tv_series_id: SERIES, season_number: null, episode_number: 3 }
        expect(sameDuplicateGroup(keep, other)).toBe(false)
    })
})

describe('validateResolveRequest', () => {
    it('accepts a valid payload', () => {
        expect(validateResolveRequest(UUID_A, [UUID_B, UUID_C])).toBeNull()
    })

    it('rejects a missing or malformed keepId', () => {
        expect(validateResolveRequest(null, [UUID_B])).toMatch(/keepId/)
        expect(validateResolveRequest('nope', [UUID_B])).toMatch(/keepId/)
    })

    it('rejects an empty or non-array deleteIds', () => {
        expect(validateResolveRequest(UUID_A, [])).toMatch(/deleteIds/)
        expect(validateResolveRequest(UUID_A, null)).toMatch(/deleteIds/)
        expect(validateResolveRequest(UUID_A, 'nope')).toMatch(/deleteIds/)
    })

    it('rejects malformed ids inside deleteIds', () => {
        expect(validateResolveRequest(UUID_A, [UUID_B, 'garbage'])).toMatch(/uuid/)
    })

    it('rejects duplicate deleteIds', () => {
        expect(validateResolveRequest(UUID_A, [UUID_B, UUID_B])).toMatch(/duplicate/)
    })

    it('rejects keepId contained in deleteIds', () => {
        expect(validateResolveRequest(UUID_A, [UUID_A, UUID_B])).toMatch(/keepId must not be in deleteIds/)
    })
})
