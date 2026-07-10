/**
 * Genre mapping helpers — pure logic, no network/DB.
 *
 * Enrichment sources return genres in mixed shapes:
 *   - TMDB details:        [{ id: 28, name: 'Action' }, ...]
 *   - OMDB / IMDB scrape:  ['Action', 'Comedy'] (or a comma string upstream)
 *   - staged genre_data:   [{ tmdb_id: 28, name: 'Action' }, ...]
 *
 * normalizeGenreEntries() flattens all of these to [{ tmdb_id, name }],
 * mapGenreEntriesToIds() resolves them against the genres table
 * (id, name, tmdb_id) — tmdb_id match first, then case-insensitive name;
 * unmatchable entries are skipped, never fatal.
 */

/**
 * Normalize a genres payload into [{ tmdb_id: number|null, name: string|null }].
 * Accepts strings, TMDB objects ({ id, name }), or already-normalized objects
 * ({ tmdb_id, name }). Entries with neither a usable id nor name are dropped;
 * duplicates (same tmdb_id or same case-insensitive name) are removed.
 *
 * @param {Array|null|undefined} genres
 * @returns {Array<{tmdb_id: number|null, name: string|null}>|null} null when nothing usable
 */
export function normalizeGenreEntries(genres) {
    if (!Array.isArray(genres)) return null

    const entries = []
    const seenIds = new Set()
    const seenNames = new Set()

    for (const genre of genres) {
        let tmdbId = null
        let name = null

        if (typeof genre === 'string') {
            name = genre.trim()
        } else if (genre && typeof genre === 'object') {
            // TMDB uses `id`; our stored shape uses `tmdb_id`
            const rawId = genre.tmdb_id ?? genre.id
            const parsed = Number.parseInt(rawId, 10)
            if (Number.isInteger(parsed) && parsed > 0) tmdbId = parsed
            if (typeof genre.name === 'string') name = genre.name.trim()
        }

        if (!name && tmdbId === null) continue
        if (name === '') name = null
        if (!name && tmdbId === null) continue

        const nameKey = name ? name.toLowerCase() : null
        if (tmdbId !== null && seenIds.has(tmdbId)) continue
        if (tmdbId === null && nameKey && seenNames.has(nameKey)) continue

        if (tmdbId !== null) seenIds.add(tmdbId)
        if (nameKey) seenNames.add(nameKey)

        entries.push({ tmdb_id: tmdbId, name })
    }

    return entries.length > 0 ? entries : null
}

/**
 * Map normalized (or raw) genre entries to genres-table primary keys.
 *
 * Matching order per entry:
 *   1. genres.tmdb_id === entry.tmdb_id
 *   2. genres.name matches entry.name case-insensitively
 *   3. no match → entry is skipped (reported in `unmatched`)
 *
 * @param {Array} entries - output of normalizeGenreEntries (raw shapes also accepted)
 * @param {Array<{id: number, name: string, tmdb_id: number|null}>} genreRows - rows from the genres table
 * @returns {{genreIds: number[], matched: string[], unmatched: string[]}}
 */
export function mapGenreEntriesToIds(entries, genreRows) {
    const result = { genreIds: [], matched: [], unmatched: [] }

    const normalized = normalizeGenreEntries(entries)
    if (!normalized || !Array.isArray(genreRows) || genreRows.length === 0) {
        if (normalized) {
            result.unmatched = normalized.map(e => e.name || `tmdb:${e.tmdb_id}`)
        }
        return result
    }

    const byTmdbId = new Map()
    const byName = new Map()
    for (const row of genreRows) {
        if (row == null || row.id == null) continue
        if (row.tmdb_id != null) byTmdbId.set(Number(row.tmdb_id), row)
        if (typeof row.name === 'string') byName.set(row.name.trim().toLowerCase(), row)
    }

    const seen = new Set()
    for (const entry of normalized) {
        let row = null
        if (entry.tmdb_id !== null) row = byTmdbId.get(entry.tmdb_id) || null
        if (!row && entry.name) row = byName.get(entry.name.toLowerCase()) || null

        if (!row) {
            result.unmatched.push(entry.name || `tmdb:${entry.tmdb_id}`)
            continue
        }
        if (seen.has(row.id)) continue
        seen.add(row.id)
        result.genreIds.push(row.id)
        result.matched.push(row.name)
    }

    return result
}
