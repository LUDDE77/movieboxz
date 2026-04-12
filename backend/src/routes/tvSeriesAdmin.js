import express from 'express'
import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'
import { adminAuth } from '../middleware/adminAuth.js'

const router = express.Router()

// Apply admin auth to all TV series admin routes
router.use(adminAuth)

// =============================================================================
// GET /api/admin/tv-content
// Returns all movies where is_tv_show = true OR is_tv_series = true
// =============================================================================
router.get('/tv-content', async (req, res, next) => {
    try {
        const { data: movies, error } = await supabase
            .from('movies')
            .select(`
                id,
                title,
                youtube_video_id,
                youtube_video_title,
                is_tv_show,
                is_tv_series,
                tv_series_id,
                season_number,
                episode_number,
                series_type,
                imdb_id,
                channel_id,
                is_available,
                created_at,
                updated_at,
                channels(id, title, thumbnail_url),
                movie_genres(genres(id, name, tmdb_id))
            `)
            .or('is_tv_show.eq.true,is_tv_series.eq.true')
            .order('title', { ascending: true })

        if (error) throw error

        logger.info(`TV content fetch: ${movies.length} movies`)

        const flatMovies = movies.map(({ channels, movie_genres, ...m }) => ({
            ...m,
            channel_title: channels?.title || null,
            channel_thumbnail: channels?.thumbnail_url || null,
            genres: (movie_genres || []).map(mg => mg.genres).filter(Boolean)
        }))

        res.json({
            success: true,
            data: {
                movies: flatMovies,
                total: flatMovies.length
            }
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/admin/tv-series
// Returns all records from tv_series table
// =============================================================================
router.get('/tv-series', async (req, res, next) => {
    try {
        const { data: series, error } = await supabase
            .from('tv_series')
            .select('*')
            .order('title', { ascending: true })

        if (error) throw error

        logger.info(`TV series fetch: ${series.length} series`)

        res.json({
            success: true,
            data: {
                series,
                total: series.length
            }
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// POST /api/admin/tv-series
// Create a new tv_series record
// =============================================================================
router.post('/tv-series', async (req, res, next) => {
    try {
        const { title, imdb_id, description, series_type } = req.body

        if (!title || !title.trim()) {
            return res.status(400).json({
                success: false,
                error: 'title is required'
            })
        }

        const insertData = {
            title: title.trim(),
            updated_at: new Date().toISOString()
        }

        if (imdb_id) insertData.imdb_id = imdb_id.trim()
        if (description) insertData.description = description.trim()

        const { data: series, error } = await supabase
            .from('tv_series')
            .insert(insertData)
            .select()
            .single()

        if (error) throw error

        logger.info(`Created TV series: ${series.title} (${series.id})`)

        res.status(201).json({
            success: true,
            data: series
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// PATCH /api/admin/movies/:id/tv-info
// Update a movie's TV series info
// =============================================================================
router.patch('/movies/:id/tv-info', async (req, res, next) => {
    try {
        const { id } = req.params
        const ALLOWED_FIELDS = [
            'season_number',
            'episode_number',
            'series_type',
            'tv_series_id',
            'is_tv_show',
            'is_tv_series'
        ]

        const updates = {}
        for (const field of ALLOWED_FIELDS) {
            if (Object.prototype.hasOwnProperty.call(req.body, field)) {
                updates[field] = req.body[field]
            }
        }

        if (Object.keys(updates).length === 0) {
            return res.status(400).json({
                success: false,
                error: 'No valid fields provided'
            })
        }

        updates.updated_at = new Date().toISOString()

        const { data: movie, error } = await supabase
            .from('movies')
            .update(updates)
            .eq('id', id)
            .select(`
                id,
                title,
                youtube_video_id,
                youtube_video_title,
                is_tv_show,
                is_tv_series,
                tv_series_id,
                season_number,
                episode_number,
                series_type,
                imdb_id,
                channel_id,
                is_available,
                created_at,
                updated_at,
                channels(id, title, thumbnail_url)
            `)
            .single()

        if (error) throw error

        if (!movie) {
            return res.status(404).json({
                success: false,
                error: 'Movie not found'
            })
        }

        logger.info(`Updated TV info for movie ${id}: ${JSON.stringify(updates)}`)

        const { channels, ...movieData } = movie
        res.json({
            success: true,
            data: {
                ...movieData,
                channel_title: channels?.title || null,
                channel_thumbnail: channels?.thumbnail_url || null
            }
        })
    } catch (error) {
        next(error)
    }
})

export { router as tvSeriesAdminRouter }
