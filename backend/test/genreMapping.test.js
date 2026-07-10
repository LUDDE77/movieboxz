import { describe, it, expect } from 'vitest'
import { normalizeGenreEntries, mapGenreEntriesToIds } from '../src/utils/genreMapping.js'

// Mimics the genres table (id = our PK, tmdb_id = TMDB's genre id)
const GENRE_ROWS = [
    { id: 1, name: 'Action', tmdb_id: 28 },
    { id: 2, name: 'Comedy', tmdb_id: 35 },
    { id: 3, name: 'Animation', tmdb_id: 16 },
    { id: 4, name: 'Family', tmdb_id: 10751 },
    { id: 5, name: 'Science Fiction', tmdb_id: 878 },
    { id: 6, name: 'Local Genre', tmdb_id: null }
]

describe('normalizeGenreEntries', () => {
    it('normalizes TMDB {id, name} objects', () => {
        expect(normalizeGenreEntries([{ id: 28, name: 'Action' }])).toEqual([
            { tmdb_id: 28, name: 'Action' }
        ])
    })

    it('normalizes plain strings (OMDB/IMDB shape)', () => {
        expect(normalizeGenreEntries(['Action', ' Comedy '])).toEqual([
            { tmdb_id: null, name: 'Action' },
            { tmdb_id: null, name: 'Comedy' }
        ])
    })

    it('passes through already-normalized {tmdb_id, name} entries', () => {
        expect(normalizeGenreEntries([{ tmdb_id: 35, name: 'Comedy' }])).toEqual([
            { tmdb_id: 35, name: 'Comedy' }
        ])
    })

    it('handles mixed shapes and dedupes', () => {
        const result = normalizeGenreEntries([
            { id: 28, name: 'Action' },
            'action',            // duplicate by name (case-insensitive)
            { tmdb_id: 28 },     // duplicate by tmdb_id
            'Comedy'
        ])
        expect(result).toEqual([
            { tmdb_id: 28, name: 'Action' },
            { tmdb_id: null, name: 'Comedy' }
        ])
    })

    it('drops unusable entries and returns null when nothing remains', () => {
        expect(normalizeGenreEntries([])).toBeNull()
        expect(normalizeGenreEntries(['', '  ', {}, null, { id: 'abc' }])).toBeNull()
        expect(normalizeGenreEntries(null)).toBeNull()
        expect(normalizeGenreEntries(undefined)).toBeNull()
        expect(normalizeGenreEntries('Action')).toBeNull() // not an array
    })
})

describe('mapGenreEntriesToIds', () => {
    it('matches by tmdb_id first', () => {
        const { genreIds, matched, unmatched } = mapGenreEntriesToIds(
            [{ tmdb_id: 28, name: 'Totally Wrong Name' }],
            GENRE_ROWS
        )
        expect(genreIds).toEqual([1])
        expect(matched).toEqual(['Action'])
        expect(unmatched).toEqual([])
    })

    it('falls back to case-insensitive name match', () => {
        const { genreIds, matched } = mapGenreEntriesToIds(
            ['comedy', 'SCIENCE FICTION', { tmdb_id: null, name: 'local genre' }],
            GENRE_ROWS
        )
        expect(genreIds).toEqual([2, 5, 6])
        expect(matched).toEqual(['Comedy', 'Science Fiction', 'Local Genre'])
    })

    it('uses name fallback when tmdb_id is unknown to the genres table', () => {
        const { genreIds } = mapGenreEntriesToIds(
            [{ tmdb_id: 99999, name: 'Family' }],
            GENRE_ROWS
        )
        expect(genreIds).toEqual([4])
    })

    it('skips unmatchable entries without failing', () => {
        const { genreIds, matched, unmatched } = mapGenreEntriesToIds(
            [{ id: 28, name: 'Action' }, 'Telenovela', { tmdb_id: 424242 }],
            GENRE_ROWS
        )
        expect(genreIds).toEqual([1])
        expect(matched).toEqual(['Action'])
        expect(unmatched).toEqual(['Telenovela', 'tmdb:424242'])
    })

    it('dedupes entries that resolve to the same genre row', () => {
        const { genreIds } = mapGenreEntriesToIds(
            [{ tmdb_id: 28, name: 'Action' }, { tmdb_id: 28, name: 'Aktion' }],
            GENRE_ROWS
        )
        expect(genreIds).toEqual([1])
    })

    it('returns empty result for null/empty inputs', () => {
        expect(mapGenreEntriesToIds(null, GENRE_ROWS).genreIds).toEqual([])
        expect(mapGenreEntriesToIds([], GENRE_ROWS).genreIds).toEqual([])
        expect(mapGenreEntriesToIds(['Action'], []).genreIds).toEqual([])
        expect(mapGenreEntriesToIds(['Action'], null).genreIds).toEqual([])
    })

    it('reports all entries as unmatched when the genres table is empty', () => {
        const { unmatched } = mapGenreEntriesToIds(['Action', { tmdb_id: 35 }], [])
        expect(unmatched).toEqual(['Action', 'tmdb:35'])
    })
})
