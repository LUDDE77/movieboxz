import express from 'express'
import { dbOperations } from '../config/database.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// =============================================================================
// GET /api/browse/genres
// List all genres with movie counts
// =============================================================================
router.get('/genres', async (req, res, next) => {
    try {
        logger.info('Fetching all genres with counts')

        const genres = await dbOperations.getGenresWithCounts()

        res.json({
            success: true,
            data: {
                genres: genres.map(genre => ({
                    id: genre.id,
                    tmdbId: genre.tmdb_id,
                    name: genre.name,
                    movieCount: parseInt(genre.movie_count) || 0
                })),
                total: genres.length
            },
            message: `Retrieved ${genres.length} genres`
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/browse/genres/:genreId/info
// Get genre details with metadata
// =============================================================================
router.get('/genres/:genreId/info', async (req, res, next) => {
    try {
        const { genreId } = req.params

        logger.info(`Fetching genre info: ${genreId}`)

        const genre = await dbOperations.getGenreById(genreId)

        if (!genre) {
            return res.status(404).json({
                success: false,
                error: 'Genre not found',
                message: `No genre found with ID: ${genreId}`
            })
        }

        res.json({
            success: true,
            data: {
                id: genre.id,
                tmdbId: genre.tmdb_id,
                name: genre.name,
                movieCount: parseInt(genre.movie_count) || 0
            },
            message: 'Genre details retrieved successfully'
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/browse/genres/:genreId
// Get movies by genre with pagination and sorting
// Query params: page, limit, sort (popular, recent, rating)
// =============================================================================
router.get('/genres/:genreId', async (req, res, next) => {
    try {
        const { genreId } = req.params
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 20
        const offset = (page - 1) * limit
        const sort = req.query.sort || 'popular' // popular, recent, rating

        logger.info(`Fetching movies for genre ${genreId} - page ${page}, sort: ${sort}`)

        // Map sort param to database sort options
        const sortOptions = {
            popular: { sortBy: 'view_count', sortOrder: 'desc' },
            recent: { sortBy: 'published_at', sortOrder: 'desc' },
            rating: { sortBy: 'vote_average', sortOrder: 'desc' }
        }

        const sortConfig = sortOptions[sort] || sortOptions.popular

        // Get genre info
        const genre = await dbOperations.getGenreById(genreId)

        if (!genre) {
            return res.status(404).json({
                success: false,
                error: 'Genre not found',
                message: `No genre found with ID: ${genreId}`
            })
        }

        // Get movies by genre
        const result = await dbOperations.getMoviesByGenre(
            genreId,
            limit,
            offset,
            sortConfig.sortBy,
            sortConfig.sortOrder
        )

        res.json({
            success: true,
            data: {
                genre: {
                    id: genre.id,
                    tmdbId: genre.tmdb_id,
                    name: genre.name
                },
                movies: result.movies,
                pagination: {
                    page,
                    limit,
                    total: result.total,
                    pages: Math.ceil(result.total / limit)
                },
                sort
            },
            message: `Retrieved ${result.movies.length} ${genre.name} movies`
        })
    } catch (error) {
        next(error)
    }
})

export default router
