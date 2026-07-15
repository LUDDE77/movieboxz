import express from 'express'
import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// =============================================================================
// GET /api/series
// List all TV series that have at least 1 episode in the movies table.
// Query params:
//   - limit: Items per page (default: 50)
//   - page:  Page number (default: 1)
// Response includes episode_count and season_count derived from linked movies.
// =============================================================================
router.get('/', async (req, res, next) => {
    try {
        const limit = Math.min(parseInt(req.query.limit) || 50, 100)
        const page = parseInt(req.query.page) || 1
        const offset = (page - 1) * limit
        const kidsOnly = req.query.kids === 'true'

        logger.info(`Fetching series list - page ${page}, limit ${limit}`)

        // Fetch one page of tv_series rows joined with their episodes.
        // movies!inner restricts to series with at least one non-unavailable
        // episode, pagination happens in the database via .range(), and
        // count: 'exact' returns the total matching series without loading them.
        let seriesQuery = supabase
            .from('tv_series')
            .select(`
                id,
                title,
                description,
                poster_path,
                year_start,
                year_end,
                movies!inner(
                    id,
                    season_number,
                    is_tv_series,
                    is_available,
                    is_kids_content
                )
            `, { count: 'exact' })
            .not('movies.is_available', 'is', false)

        if (kidsOnly) {
            // Kids surface: only series whose episodes are kids content
            seriesQuery = seriesQuery.eq('movies.is_kids_content', true)
        }

        const { data: seriesRows, error: seriesError, count } = await seriesQuery
            .order('title', { ascending: true })
            .range(offset, offset + limit - 1)

        if (seriesError) {
            logger.error(`Series list query failed: ${JSON.stringify(seriesError)}`)
            throw seriesError
        }

        // Build series objects with derived counts.
        const paginated = (seriesRows || []).map(series => {
            const episodes = (series.movies || []).filter(m => m.is_available !== false)
            const distinctSeasons = new Set(
                episodes
                    .map(e => e.season_number)
                    .filter(n => n !== null && n !== undefined)
            )

            return {
                id: series.id,
                title: series.title,
                description: series.description,
                poster_path: series.poster_path,
                year_start: series.year_start,
                year_end: series.year_end,
                episode_count: episodes.length,
                season_count: distinctSeasons.size
            }
        })

        const total = count || 0

        res.json({
            success: true,
            data: {
                series: paginated,
                pagination: {
                    page,
                    limit,
                    total,
                    pages: Math.ceil(total / limit)
                }
            },
            message: `Retrieved ${paginated.length} series`
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/series/:seriesId/episodes
// Return series metadata and all episodes grouped by season.
// Episodes are movies where tv_series_id = :seriesId and is_tv_series = true,
// ordered by season_number ASC, episode_number ASC.
// =============================================================================
router.get('/:seriesId/episodes', async (req, res, next) => {
    try {
        const { seriesId } = req.params

        logger.info(`Fetching episodes for series: ${seriesId}`)

        // Fetch series metadata
        const { data: series, error: seriesError } = await supabase
            .from('tv_series')
            .select(`
                id,
                title,
                description,
                poster_path,
                year_start,
                year_end
            `)
            .eq('id', seriesId)
            .single()

        if (seriesError) {
            if (seriesError.code === 'PGRST116') {
                return res.status(404).json({
                    success: false,
                    error: 'Series not found',
                    message: `No series found with ID: ${seriesId}`
                })
            }
            throw seriesError
        }

        // Fetch all episodes belonging to this series, hiding any the viewer's
        // country can't play (same per-country rule as the movie surfaces;
        // NULL region columns pass = "no restriction = worldwide").
        const cc = String(req.query.country || req.headers['x-country'] || '').trim().toUpperCase()
        const validCC = /^[A-Z]{2}$/.test(cc) ? cc : null

        let episodesQuery = supabase
            .from('movies')
            .select('*, channels(id, title, thumbnail_url)')
            .eq('tv_series_id', seriesId)
            .eq('is_tv_series', true)
            .eq('is_available', true)

        if (validCC) {
            episodesQuery = episodesQuery
                .or(`region_blocked.is.null,region_blocked.not.cs.{${validCC}}`)
                .or(`region_allowed.is.null,region_allowed.cs.{${validCC}}`)
            if (process.env.REGION_FILTER_HIDE_IF_UNKNOWN === 'true') {
                episodesQuery = episodesQuery.not('region_checked_at', 'is', null)
            }
        }

        const { data: episodeRows, error: episodesError } = await episodesQuery
            .order('season_number', { ascending: true })
            .order('episode_number', { ascending: true })

        if (episodesError) throw episodesError

        // Flatten channel fields to match the standard movies API shape
        const episodes = (episodeRows || []).map(ep => {
            const { channels, ...rest } = ep
            return {
                ...rest,
                channel_title: channels?.title || null,
                channel_thumbnail: channels?.thumbnail_url || null
            }
        })

        // Group episodes by season_number. Episodes we couldn't map to a
        // specific season (null) list under Season 1 rather than a bare
        // "Season 0" — real TMDB specials carry an explicit 0 and are unaffected.
        const seasonMap = new Map()
        for (const episode of episodes) {
            const seasonNum = episode.season_number ?? 1
            if (!seasonMap.has(seasonNum)) {
                seasonMap.set(seasonNum, [])
            }
            seasonMap.get(seasonNum).push(episode)
        }

        // Convert to sorted array of season objects
        const seasons = Array.from(seasonMap.entries())
            .sort(([a], [b]) => a - b)
            .map(([seasonNumber, episodes]) => ({
                seasonNumber,
                episodes
            }))

        res.json({
            success: true,
            data: {
                series,
                seasons
            },
            message: `Retrieved ${episodeRows.length} episodes across ${seasons.length} season(s)`
        })
    } catch (error) {
        next(error)
    }
})

export default router
