/**
 * Duplicate Groups — pure helpers for the production duplicate manager
 * (routes/duplicatesAdmin.js). Kept free of DB access so they can be unit tested.
 */

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function isUuid(value) {
    return typeof value === 'string' && UUID_RE.test(value)
}

/** Grouping key for imdb duplicates (null when the movie has no imdb_id). */
export function imdbKey(movie) {
    return movie?.imdb_id || null
}

/**
 * Grouping key for episode duplicates: same (tv_series_id, season, episode) triple.
 * Null when any part is missing.
 */
export function episodeKey(movie) {
    if (!movie) return null
    const { tv_series_id, season_number, episode_number } = movie
    if (!tv_series_id || season_number == null || episode_number == null) return null
    return `${tv_series_id}:S${season_number}:E${episode_number}`
}

/**
 * Given rows and a key function, return the keys that appear more than once.
 */
export function findDuplicateKeys(rows, keyFn) {
    const counts = new Map()
    for (const row of rows || []) {
        const key = keyFn(row)
        if (!key) continue
        counts.set(key, (counts.get(key) || 0) + 1)
    }
    return [...counts.entries()].filter(([, count]) => count > 1).map(([key]) => key)
}

/**
 * True when `other` belongs to the same duplicate group as `keepMovie`:
 * they share a non-null imdb_id, or the same complete episode triple.
 */
export function sameDuplicateGroup(keepMovie, other) {
    if (!keepMovie || !other) return false
    if (keepMovie.imdb_id && other.imdb_id === keepMovie.imdb_id) return true
    const keepKey = episodeKey(keepMovie)
    return !!keepKey && keepKey === episodeKey(other)
}

/**
 * Validate a resolve request payload. Returns an error message, or null when valid.
 */
export function validateResolveRequest(keepId, deleteIds) {
    if (!isUuid(keepId)) return 'keepId must be a valid uuid'
    if (!Array.isArray(deleteIds) || deleteIds.length === 0) return 'deleteIds must be a non-empty array'
    if (deleteIds.some(id => !isUuid(id))) return 'deleteIds must contain only valid uuids'
    if (new Set(deleteIds).size !== deleteIds.length) return 'deleteIds contains duplicate ids'
    if (deleteIds.includes(keepId)) return 'keepId must not be in deleteIds'
    return null
}
