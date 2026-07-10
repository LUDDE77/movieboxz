import express from 'express'
import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'
import { adminAuth } from '../middleware/adminAuth.js'
import { tmdbService } from '../services/tmdbService.js'
import { normalizeGenreEntries, mapGenreEntriesToIds } from '../utils/genreMapping.js'

const router = express.Router()

// Apply admin auth to all genre admin routes
router.use(adminAuth)

const VALID_SCOPES = ['tmdb', 'imdb', 'episodes', 'all']
const DEFAULT_LIMIT = 500
const MAX_LIMIT = 2000
const DRY_RUN_SAMPLE_SIZE = 20
const PROGRESS_LOG_INTERVAL = 25
const CANDIDATE_PAGE_SIZE = 1000

// =============================================================================
// Candidate collection
// =============================================================================

/**
 * Load all production movies that have zero movie_genres rows, with the
 * fields the backfill needs. Pages through the whole table (a few thousand
 * rows) and filters the "zero genres" condition client-side via the
 * embedded movie_genres relation.
 */
async function loadMoviesMissingGenres() {
    const rows = []
    for (let from = 0; ; from += CANDIDATE_PAGE_SIZE) {
        const { data, error } = await supabase
            .from('movies')
            .select('id, title, tmdb_id, imdb_id, is_tv_series, is_kids_content, tv_series_id, channel_id, movie_genres(genre_id)')
            .order('created_at', { ascending: true })
            .range(from, from + CANDIDATE_PAGE_SIZE - 1)

        if (error) throw error
        if (!data || data.length === 0) break

        for (const movie of data) {
            if (!movie.movie_genres || movie.movie_genres.length === 0) {
                rows.push(movie)
            }
        }
        if (data.length < CANDIDATE_PAGE_SIZE) break
    }
    return rows
}

/**
 * Split zero-genre movies into scope buckets.
 * - tmdb:     non-episode movies with a tmdb_id
 * - imdb:     non-episode movies with an imdb_id but no tmdb_id
 * - episodes: is_tv_series = true rows (genres come from their TV series)
 */
function bucketCandidates(missing) {
    return {
        tmdb: missing.filter(m => !m.is_tv_series && m.tmdb_id),
        imdb: missing.filter(m => !m.is_tv_series && !m.tmdb_id && m.imdb_id),
        episodes: missing.filter(m => m.is_tv_series === true)
    }
}

function candidatesForScope(scope, buckets) {
    if (scope === 'all') {
        // Concatenate with a per-candidate kind; buckets are disjoint by construction
        return [
            ...buckets.tmdb.map(movie => ({ movie, kind: 'tmdb' })),
            ...buckets.imdb.map(movie => ({ movie, kind: 'imdb' })),
            ...buckets.episodes.map(movie => ({ movie, kind: 'episodes' }))
        ]
    }
    return buckets[scope].map(movie => ({ movie, kind: scope }))
}

// =============================================================================
// Per-scope genre proposal
// =============================================================================

/**
 * Build the shared context for a backfill run: genres table rows, episode
 * guides for the involved series, and the set of kids channels.
 */
async function buildRunContext(candidates) {
    const { data: genreRows, error: genresError } = await supabase
        .from('genres')
        .select('id, name')
    if (genresError) throw genresError

    const episodeCandidates = candidates.filter(c => c.kind === 'episodes')

    // Episode guides: tv_series_id -> TMDB TV id (source_id)
    const guideBySeries = new Map()
    const seriesIds = [...new Set(episodeCandidates.map(c => c.movie.tv_series_id).filter(Boolean))]
    for (let i = 0; i < seriesIds.length; i += 200) {
        const chunk = seriesIds.slice(i, i + 200)
        const { data: guides, error: guidesError } = await supabase
            .from('episode_guides')
            .select('tv_series_id, source, source_id')
            .in('tv_series_id', chunk)
        if (guidesError) throw guidesError
        for (const guide of guides || []) {
            if (guide.source === 'tmdb' && guide.source_id) {
                guideBySeries.set(guide.tv_series_id, guide.source_id)
            }
        }
    }

    // Kids channels (channels.has_kids_content) for the episode candidates
    const kidsChannelIds = new Set()
    const channelIds = [...new Set(episodeCandidates.map(c => c.movie.channel_id).filter(Boolean))]
    for (let i = 0; i < channelIds.length; i += 200) {
        const chunk = channelIds.slice(i, i + 200)
        const { data: channels, error: channelsError } = await supabase
            .from('channels')
            .select('id, has_kids_content')
            .in('id', chunk)
        if (channelsError) throw channelsError
        for (const channel of channels || []) {
            if (channel.has_kids_content) kidsChannelIds.add(channel.id)
        }
    }

    return {
        // genres.id doubles as the TMDB genre id in this schema
        genreRows: (genreRows || []).map(g => ({ ...g, tmdb_id: g.id })),
        guideBySeries,
        kidsChannelIds,
        seriesGenreCache: new Map() // tv_series_id -> normalized entries (per run)
    }
}

/**
 * Propose genre entries for one candidate. Returns:
 *   { entries: [{tmdb_id, name}]|null, setTmdbId?: number, skipReason?: string }
 * Throws on TMDB request failure (caller counts it as failed).
 */
async function proposeGenres(candidate, ctx) {
    const { movie, kind } = candidate

    if (kind === 'tmdb') {
        const tmdbGenres = await tmdbService.getMovieGenres(movie.tmdb_id)
        return { entries: normalizeGenreEntries(tmdbGenres) }
    }

    if (kind === 'imdb') {
        const found = await tmdbService.findByImdbId(movie.imdb_id)
        const match = found?.movie_results?.[0]
        if (!match) return { entries: null, skipReason: 'no TMDB match for imdb_id' }
        const tmdbGenres = await tmdbService.getMovieGenres(match.id)
        return { entries: normalizeGenreEntries(tmdbGenres), setTmdbId: match.id }
    }

    // kind === 'episodes'
    let entries = null
    if (movie.tv_series_id) {
        if (ctx.seriesGenreCache.has(movie.tv_series_id)) {
            entries = ctx.seriesGenreCache.get(movie.tv_series_id)
        } else {
            const tmdbTvId = ctx.guideBySeries.get(movie.tv_series_id)
            if (tmdbTvId) {
                const tvGenres = await tmdbService.getTVShowGenres(tmdbTvId)
                entries = normalizeGenreEntries(tvGenres)
            }
            // Cache even null so each series is fetched at most once per run
            ctx.seriesGenreCache.set(movie.tv_series_id, entries)
        }
    }

    // Kids content always gets Animation + Family on top of the series genres
    const isKids = movie.is_kids_content === true || ctx.kidsChannelIds.has(movie.channel_id)
    if (isKids) {
        entries = normalizeGenreEntries([...(entries || []), 'Animation', 'Family'])
    }

    if (!entries) {
        return { entries: null, skipReason: movie.tv_series_id ? 'no episode guide / TV genres' : 'no tv_series_id' }
    }
    return { entries }
}

// =============================================================================
// POST /api/admin/genres/backfill
// Body: { dryRun = true, scope = 'tmdb'|'imdb'|'episodes'|'all', limit = 500 }
//
// Backfills movie_genres for production movies that currently have none.
// dryRun (default) computes proposals for a small sample without writing.
// Response: { success, data: { dryRun, scope, processed, updated|proposed,
//             failed, remaining, sample } }
// =============================================================================
router.post('/backfill', async (req, res, next) => {
    try {
        const { dryRun = true, scope = 'tmdb', limit } = req.body || {}

        if (!VALID_SCOPES.includes(scope)) {
            return res.status(400).json({
                success: false,
                error: `Invalid scope '${scope}'. Must be one of: ${VALID_SCOPES.join(', ')}`
            })
        }

        let parsedLimit = Number.parseInt(limit, 10)
        if (!Number.isInteger(parsedLimit) || parsedLimit < 1) parsedLimit = DEFAULT_LIMIT
        parsedLimit = Math.min(parsedLimit, MAX_LIMIT)

        logger.info(`[GenreBackfill] Starting (scope: ${scope}, dryRun: ${dryRun}, limit: ${parsedLimit})`)

        const missing = await loadMoviesMissingGenres()
        const buckets = bucketCandidates(missing)
        const candidates = candidatesForScope(scope, buckets)

        logger.info(`[GenreBackfill] ${candidates.length} candidate(s) with zero genres ` +
            `(tmdb: ${buckets.tmdb.length}, imdb: ${buckets.imdb.length}, episodes: ${buckets.episodes.length})`)

        const ctx = await buildRunContext(candidates)

        // Dry run only inspects a sample — keeps TMDB traffic near zero
        const budget = dryRun
            ? Math.min(DRY_RUN_SAMPLE_SIZE, parsedLimit, candidates.length)
            : Math.min(parsedLimit, candidates.length)

        let processed = 0
        let updated = 0
        let failed = 0
        const sample = []

        for (const candidate of candidates.slice(0, budget)) {
            const { movie } = candidate
            processed++
            try {
                const proposal = await proposeGenres(candidate, ctx)
                const { genreIds, matched, unmatched } = mapGenreEntriesToIds(proposal.entries, ctx.genreRows)

                if (unmatched.length > 0) {
                    logger.warn(`[GenreBackfill] Unmatched genre(s) for "${movie.title}": ${unmatched.join(', ')}`)
                }

                if (genreIds.length === 0) {
                    failed++
                    logger.warn(`[GenreBackfill] No mappable genres for "${movie.title}" (${movie.id})` +
                        `${proposal.skipReason ? ` — ${proposal.skipReason}` : ''}`)
                    continue
                }

                if (!dryRun) {
                    const { error: rpcError } = await supabase.rpc('update_movie_genres', {
                        p_movie_id: movie.id,
                        p_genre_ids: genreIds
                    })
                    if (rpcError) throw rpcError

                    // IMDB scope: we just resolved the tmdb_id — persist it
                    if (proposal.setTmdbId) {
                        const { error: tmdbIdError } = await supabase
                            .from('movies')
                            .update({ tmdb_id: proposal.setTmdbId, updated_at: new Date().toISOString() })
                            .eq('id', movie.id)
                        if (tmdbIdError) {
                            logger.warn(`[GenreBackfill] Failed to set tmdb_id for "${movie.title}": ${tmdbIdError.message}`)
                        }
                    }
                }

                updated++
                if (sample.length < DRY_RUN_SAMPLE_SIZE) {
                    sample.push({ movieId: movie.id, title: movie.title, genres: matched })
                }
            } catch (error) {
                failed++
                logger.error(`[GenreBackfill] Failed for "${movie.title}" (${movie.id}):`, error.message)
            }

            if (!dryRun && processed % PROGRESS_LOG_INTERVAL === 0) {
                logger.info(`[GenreBackfill] Progress: ${processed}/${budget} processed, ${updated} updated, ${failed} failed`)
            }
        }

        const remaining = dryRun ? candidates.length : candidates.length - updated
        logger.info(`[GenreBackfill] Done (scope: ${scope}, dryRun: ${dryRun}): ` +
            `${processed} processed, ${updated} ${dryRun ? 'proposed' : 'updated'}, ${failed} failed, ${remaining} remaining`)

        const data = {
            dryRun: !!dryRun,
            scope,
            processed,
            failed,
            remaining,
            sample
        }
        if (dryRun) {
            data.proposed = updated
        } else {
            data.updated = updated
        }

        res.json({ success: true, data })
    } catch (error) {
        logger.error('[GenreBackfill] Error:', error)
        next(error)
    }
})

export default router
