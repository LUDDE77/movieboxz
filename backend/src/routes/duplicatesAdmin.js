import express from 'express'
import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'
import { adminAuth } from '../middleware/adminAuth.js'
import {
    imdbKey,
    episodeKey,
    findDuplicateKeys,
    sameDuplicateGroup,
    validateResolveRequest
} from '../utils/duplicateGroups.js'

const router = express.Router()

// Apply admin auth to all duplicate-manager routes
router.use(adminAuth)

const PAGE_SIZE = 1000
const IN_CHUNK_SIZE = 100

// Fields returned for each movie in a duplicate group (channel title comes via join)
const GROUP_MOVIE_SELECT = `
    id, title, youtube_video_id, is_available, view_count, poster_path,
    imdb_id, tv_series_id, season_number, episode_number, created_at,
    channels(title)
`

function flattenMovie(movie) {
    const { channels, ...rest } = movie
    return { ...rest, channel_title: channels?.title || null }
}

function chunk(array, size) {
    const chunks = []
    for (let i = 0; i < array.length; i += size) chunks.push(array.slice(i, i + size))
    return chunks
}

// Page through a narrow column projection of the movies table (keys only, never
// full rows) so duplicate keys can be found without loading the whole table.
async function scanMovieKeys(select, applyFilters) {
    const rows = []
    for (let from = 0; ; from += PAGE_SIZE) {
        let query = supabase
            .from('movies')
            .select(select)
            .order('id', { ascending: true })
            .range(from, from + PAGE_SIZE - 1)
        query = applyFilters(query)
        const { data, error } = await query
        if (error) throw error
        rows.push(...(data || []))
        if (!data || data.length < PAGE_SIZE) break
    }
    return rows
}

/**
 * GET /api/admin/duplicates
 * Groups of production duplicates:
 *   - type 'imdb':    movies sharing the same non-null imdb_id
 *   - type 'episode': movies sharing the same (tv_series_id, season_number, episode_number)
 */
router.get('/', async (req, res, next) => {
    try {
        // --- Pass 1: find duplicate keys from narrow column scans -----------------
        const imdbRows = await scanMovieKeys(
            'id, imdb_id',
            q => q.not('imdb_id', 'is', null)
        )
        const duplicateImdbIds = findDuplicateKeys(imdbRows, imdbKey)

        const episodeRows = await scanMovieKeys(
            'id, tv_series_id, season_number, episode_number',
            q => q
                .not('tv_series_id', 'is', null)
                .not('season_number', 'is', null)
                .not('episode_number', 'is', null)
        )
        const duplicateEpisodeKeys = new Set(findDuplicateKeys(episodeRows, episodeKey))

        // --- Pass 2: fetch full member rows for the duplicate keys only -----------
        const groups = []

        if (duplicateImdbIds.length > 0) {
            const byImdb = new Map()
            for (const ids of chunk(duplicateImdbIds, IN_CHUNK_SIZE)) {
                const { data, error } = await supabase
                    .from('movies')
                    .select(GROUP_MOVIE_SELECT)
                    .in('imdb_id', ids)
                    .order('created_at', { ascending: true })
                if (error) throw error
                for (const movie of data || []) {
                    if (!byImdb.has(movie.imdb_id)) byImdb.set(movie.imdb_id, [])
                    byImdb.get(movie.imdb_id).push(flattenMovie(movie))
                }
            }
            for (const [key, movies] of byImdb) {
                if (movies.length > 1) groups.push({ key, type: 'imdb', movies })
            }
        }

        if (duplicateEpisodeKeys.size > 0) {
            const seriesIds = [...new Set(
                [...duplicateEpisodeKeys].map(key => key.split(':')[0])
            )]
            const byEpisode = new Map()
            for (const ids of chunk(seriesIds, IN_CHUNK_SIZE)) {
                const { data, error } = await supabase
                    .from('movies')
                    .select(GROUP_MOVIE_SELECT)
                    .in('tv_series_id', ids)
                    .not('season_number', 'is', null)
                    .not('episode_number', 'is', null)
                    .order('created_at', { ascending: true })
                if (error) throw error
                for (const movie of data || []) {
                    const key = episodeKey(movie)
                    if (!key || !duplicateEpisodeKeys.has(key)) continue
                    if (!byEpisode.has(key)) byEpisode.set(key, [])
                    byEpisode.get(key).push(flattenMovie(movie))
                }
            }
            for (const [key, movies] of byEpisode) {
                if (movies.length > 1) groups.push({ key, type: 'episode', movies })
            }
        }

        groups.sort((a, b) => a.type.localeCompare(b.type) || a.key.localeCompare(b.key))

        logger.info(`[Duplicates] Found ${groups.length} duplicate groups (${duplicateImdbIds.length} imdb keys, ${duplicateEpisodeKeys.size} episode keys)`)

        res.json({
            success: true,
            data: {
                groups,
                total: groups.length
            }
        })
    } catch (error) {
        logger.error('[Duplicates] List error:', error)
        next(error)
    }
})

/**
 * POST /api/admin/duplicates/resolve
 * Body: { keepId: uuid, deleteIds: [uuid, ...] }
 *
 * Verifies server-side that every deleteId is in the same duplicate group as keepId
 * (same non-null imdb_id or same episode triple), repoints staged_movies rows whose
 * published_movie_id targets a deleted movie to keepId, then deletes the duplicates
 * (movie_genres rows cascade).
 */
router.post('/resolve', async (req, res, next) => {
    try {
        const { keepId, deleteIds } = req.body || {}

        const validationError = validateResolveRequest(keepId, deleteIds)
        if (validationError) {
            return res.status(400).json({ success: false, error: validationError })
        }

        const { data: keepMovie, error: keepError } = await supabase
            .from('movies')
            .select('id, title, imdb_id, tv_series_id, season_number, episode_number')
            .eq('id', keepId)
            .single()

        if (keepError || !keepMovie) {
            return res.status(404).json({ success: false, error: 'keepId movie not found' })
        }

        const { data: deleteMovies, error: deleteFetchError } = await supabase
            .from('movies')
            .select('id, title, imdb_id, tv_series_id, season_number, episode_number')
            .in('id', deleteIds)

        if (deleteFetchError) throw deleteFetchError

        if ((deleteMovies || []).length !== deleteIds.length) {
            return res.status(404).json({ success: false, error: 'One or more deleteIds not found' })
        }

        const outsider = deleteMovies.find(movie => !sameDuplicateGroup(keepMovie, movie))
        if (outsider) {
            return res.status(400).json({
                success: false,
                error: `Movie ${outsider.id} ("${outsider.title}") is not in the same duplicate group as keepId`
            })
        }

        // Repoint staging references before deleting, so no staged_movies row is left
        // pointing at a removed production movie
        const { error: repointError } = await supabase
            .from('staged_movies')
            .update({ published_movie_id: keepId, updated_at: new Date().toISOString() })
            .in('published_movie_id', deleteIds)

        if (repointError) throw repointError

        const { data: deletedRows, error: deleteError } = await supabase
            .from('movies')
            .delete()
            .in('id', deleteIds)
            .select('id')

        if (deleteError) throw deleteError

        const deleted = (deletedRows || []).length
        logger.info(`[Duplicates] Resolved group: kept ${keepId} ("${keepMovie.title}"), deleted ${deleted} duplicate(s)`)

        res.json({
            success: true,
            data: { deleted },
            message: `Kept "${keepMovie.title}" and deleted ${deleted} duplicate(s)`
        })
    } catch (error) {
        logger.error('[Duplicates] Resolve error:', error)
        next(error)
    }
})

export default router
