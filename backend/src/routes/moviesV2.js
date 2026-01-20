import express from 'express'
import { dbOperations } from '../config/database.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// GET /api/movies/recent - Recently added movies
router.get('/recent', async (req, res, next) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 20
        const offset = (page - 1) * limit

        logger.info(`Fetching recently added movies - page ${page}`)

        const result = await dbOperations.getMovies({
            sortBy: 'added_at',
            sortOrder: 'desc'
        }, limit, offset)

        res.json({
            success: true,
            data: {
                movies: result.movies,
                pagination: {
                    page,
                    limit,
                    total: result.total,
                    pages: Math.ceil(result.total / limit)
                }
            },
            message: `Retrieved ${result.movies.length} recently added movies`
        })
    } catch (error) {
        next(error)
    }
})

// GET /api/movies/popular - Popular movies
router.get('/popular', async (req, res, next) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 20
        const offset = (page - 1) * limit
        const sortBy = req.query.sort || 'view_count'

        logger.info(`Fetching popular movies - page ${page}`)

        const result = await dbOperations.getMovies({
            sortBy,
            sortOrder: 'desc'
        }, limit, offset)

        res.json({
            success: true,
            data: {
                movies: result.movies,
                pagination: {
                    page,
                    limit,
                    total: result.total,
                    pages: Math.ceil(result.total / limit)
                }
            },
            message: `Retrieved ${result.movies.length} popular movies`
        })
    } catch (error) {
        next(error)
    }
})

// GET /api/movies/category/:category - Movies by category
router.get('/category/:category', async (req, res, next) => {
    try {
        const { category } = req.params
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 20
        const offset = (page - 1) * limit

        logger.info(`Fetching movies in category: ${category}`)

        const result = await dbOperations.getMovies({
            category,
            sortBy: 'vote_average',
            sortOrder: 'desc'
        }, limit, offset)

        res.json({
            success: true,
            data: {
                movies: result.movies,
                pagination: {
                    page,
                    limit,
                    total: result.total,
                    pages: Math.ceil(result.total / limit)
                },
                category
            },
            message: `Retrieved ${result.movies.length} ${category} movies`
        })
    } catch (error) {
        next(error)
    }
})

export default router
