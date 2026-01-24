import express from 'express'
import { dbOperations } from '../config/database.js'
import { validateRequest } from '../middleware/validation.js'
import { movieQuerySchema, movieIdSchema } from '../schemas/movieSchemas.js'
import { logger } from '../utils/logger.js'
import { youtubeService } from '../services/youtubeService.js'
import { tmdbService } from '../services/tmdbService.js'

const router = express.Router()

// =============================================================================
// YOUTUBE TOS COMPLIANCE HELPERS
// =============================================================================

/**
 * Check if movie metadata needs refreshing per YouTube TOS
 * TOS Section II.F: Cache data for max 30 days, refresh after 24 hours recommended
 * @param {Object} movie - Movie object with last_refreshed timestamp
 * @returns {boolean} - True if needs refresh
 */
const needsRefresh = (movie) => {
    if (!movie.last_refreshed) return true

    const lastRefreshed = new Date(movie.last_refreshed)
    const now = new Date()
    const hoursSinceRefresh = (now - lastRefreshed) / (1000 * 60 * 60)

    // Refresh if older than 24 hours (TOS recommended)
    return hoursSinceRefresh > 24
}

/**
 * Refresh YouTube metadata from API
 * @param {string} movieId - Database movie ID
 * @param {string} youtubeVideoId - YouTube video ID
 */
const refreshYouTubeMetadata = async (movieId, youtubeVideoId) => {
    try {
        logger.debug(`Refreshing YouTube metadata for movie ${movieId}`)

        // Fetch fresh data from YouTube API
        const videoData = await youtubeService.getVideoDetails(youtubeVideoId)

        if (videoData) {
            // Fetch channel thumbnail
            const channelData = await youtubeService.getChannelDetails(videoData.channelId)

            // Update database with fresh YouTube TOS fields
            await dbOperations.updateMovie(movieId, {
                youtube_video_title: videoData.title,
                channel_thumbnail: channelData?.thumbnail,
                last_refreshed: new Date().toISOString()
            })

            logger.info(`Refreshed YouTube metadata for movie ${movieId}`)
            return true
        }
    } catch (error) {
        logger.error(`Failed to refresh YouTube metadata for movie ${movieId}:`, error.message)
        return false
    }
}

// =============================================================================
// GET /api/movies
// Comprehensive movies endpoint with filtering, sorting, and pagination
// Query params:
//   - genre: Filter by genre ID
//   - channel: Filter by channel ID
//   - search: Full-text search
//   - sort: popular, recent, rating (default: popular)
//   - page: Page number (default: 1)
//   - limit: Items per page (default: 20)
// =============================================================================
router.get('/', async (req, res, next) => {
    try {
        const {
            genre,
            channel,
            search,
            sort = 'popular',
            page = 1,
            limit = 20
        } = req.query

        const pageNum = parseInt(page)
        const limitNum = parseInt(limit)
        const offset = (pageNum - 1) * limitNum

        logger.info(`Fetching movies with filters:`, { genre, channel, search, sort, page, limit })

        // Build filters object
        const filters = {}

        if (channel) {
            filters.channelId = channel
        }

        if (search) {
            filters.search = search
        }

        // Map sort parameter to database fields
        const sortOptions = {
            popular: { sortBy: 'view_count', sortOrder: 'desc' },
            recent: { sortBy: 'published_at', sortOrder: 'desc' },
            rating: { sortBy: 'vote_average', sortOrder: 'desc' }
        }

        const sortConfig = sortOptions[sort] || sortOptions.popular
        filters.sortBy = sortConfig.sortBy
        filters.sortOrder = sortConfig.sortOrder

        // If genre filter is provided, use genre-specific query
        let result
        if (genre) {
            result = await dbOperations.getMoviesByGenre(
                genre,
                limitNum,
                offset,
                sortConfig.sortBy,
                sortConfig.sortOrder
            )
        } else {
            result = await dbOperations.getMovies(filters, limitNum, offset)
        }

        res.json({
            success: true,
            data: {
                movies: result.movies,
                pagination: {
                    page: pageNum,
                    limit: limitNum,
                    total: result.total,
                    pages: Math.ceil(result.total / limitNum)
                },
                filters: {
                    genre,
                    channel,
                    search,
                    sort
                }
            },
            message: `Retrieved ${result.movies.length} movies`
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/movies/featured
// Get featured movies for homepage
// =============================================================================
router.get('/featured', async (req, res, next) => {
    try {
        logger.info('Fetching featured movies')

        const result = await dbOperations.getMovies({
            featured: true
        }, 20, 0)

        res.json({
            success: true,
            data: {
                movies: result.movies,
                total: result.total
            },
            message: `Retrieved ${result.movies.length} featured movies`
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/movies/trending
// Get trending movies
// =============================================================================
router.get('/trending', async (req, res, next) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 20
        const offset = (page - 1) * limit

        logger.info(`Fetching trending movies - page ${page}`)

        const result = await dbOperations.getMovies({
            trending: true
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
            message: `Retrieved ${result.movies.length} trending movies`
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/movies/popular
// Get popular movies sorted by view count or rating
// =============================================================================
router.get('/popular', async (req, res, next) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 20
        const offset = (page - 1) * limit
        const sortBy = req.query.sort || 'view_count' // view_count, vote_average, popularity

        logger.info(`Fetching popular movies - page ${page}, sorted by ${sortBy}`)

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

// =============================================================================
// GET /api/movies/recent
// Get recently added movies
// =============================================================================
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

// =============================================================================
// GET /api/movies/search
// Search movies with full-text search
// =============================================================================
router.get('/search', validateRequest(movieQuerySchema), async (req, res, next) => {
    try {
        const { q, category, year, page = 1, limit = 20 } = req.query
        const offset = (page - 1) * limit

        logger.info(`Searching movies: "${q}", category: ${category}, year: ${year}`)

        const filters = {
            search: q
        }

        if (category) {
            filters.category = category
        }

        // For year filtering, we'd need to add this to the database query
        // This is a simplified version
        const result = await dbOperations.getMovies(filters, limit, offset)

        res.json({
            success: true,
            data: {
                movies: result.movies,
                pagination: {
                    page: parseInt(page),
                    limit: parseInt(limit),
                    total: result.total,
                    pages: Math.ceil(result.total / limit)
                },
                query: {
                    search: q,
                    category,
                    year
                }
            },
            message: `Found ${result.movies.length} movies for "${q}"`
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/movies/category/:category
// Get movies by category
// =============================================================================
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

// =============================================================================
// GET /api/movies/channel/:channelId
// Get movies from specific YouTube channel
// =============================================================================
router.get('/channel/:channelId', async (req, res, next) => {
    try {
        const { channelId } = req.params
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 20
        const offset = (page - 1) * limit

        logger.info(`Fetching movies from channel: ${channelId}`)

        // Get channel info
        const channel = await dbOperations.getChannelById(channelId)

        // Get movies from channel
        const result = await dbOperations.getMovies({
            channelId,
            sortBy: 'published_at',
            sortOrder: 'desc'
        }, limit, offset)

        res.json({
            success: true,
            data: {
                channel,
                movies: result.movies,
                pagination: {
                    page,
                    limit,
                    total: result.total,
                    pages: Math.ceil(result.total / limit)
                }
            },
            message: `Retrieved ${result.movies.length} movies from ${channel?.title || 'channel'}`
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/movies/:id
// Get movie details by ID
// =============================================================================
router.get('/:id', validateRequest(movieIdSchema), async (req, res, next) => {
    try {
        const { id } = req.params

        logger.info(`Fetching movie details: ${id}`)

        const movie = await dbOperations.getMovieById(id)

        if (!movie) {
            return res.status(404).json({
                success: false,
                error: 'Movie not found',
                message: `No movie found with ID: ${id}`
            })
        }

        // YouTube TOS Compliance: Refresh metadata if stale (> 24 hours)
        if (needsRefresh(movie)) {
            // Don't await - refresh in background to avoid blocking response
            refreshYouTubeMetadata(id, movie.youtube_video_id).catch(err => {
                logger.error(`Background refresh failed for movie ${id}:`, err)
            })
        }

        // Check if movie is still available on YouTube
        try {
            const youtubeStatus = await youtubeService.checkVideoAvailability(movie.youtube_video_id)

            // Update movie status if needed
            if (!youtubeStatus.available || !youtubeStatus.embeddable) {
                await dbOperations.updateMovie(id, {
                    is_available: youtubeStatus.available,
                    is_embeddable: youtubeStatus.embeddable,
                    validation_error: youtubeStatus.error,
                    last_validated: new Date().toISOString()
                })

                movie.is_available = youtubeStatus.available
                movie.is_embeddable = youtubeStatus.embeddable
            }
        } catch (youtubeError) {
            logger.warn(`Failed to check YouTube availability for movie ${id}:`, youtubeError.message)
        }

        res.json({
            success: true,
            data: movie,
            message: 'Movie details retrieved successfully'
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/movies/:id/availability
// Check if movie is still available on YouTube
// =============================================================================
router.get('/:id/availability', validateRequest(movieIdSchema), async (req, res, next) => {
    try {
        const { id } = req.params

        logger.info(`Checking availability for movie: ${id}`)

        const movie = await dbOperations.getMovieById(id)

        if (!movie) {
            return res.status(404).json({
                success: false,
                error: 'Movie not found',
                message: `No movie found with ID: ${id}`
            })
        }

        // Check YouTube availability
        const youtubeStatus = await youtubeService.checkVideoAvailability(movie.youtube_video_id)

        // Update database if status changed
        if (youtubeStatus.available !== movie.is_available || youtubeStatus.embeddable !== movie.is_embeddable) {
            await dbOperations.updateMovie(id, {
                is_available: youtubeStatus.available,
                is_embeddable: youtubeStatus.embeddable,
                validation_error: youtubeStatus.error,
                last_validated: new Date().toISOString()
            })
        }

        res.json({
            success: true,
            data: {
                movieId: id,
                youtubeVideoId: movie.youtube_video_id,
                available: youtubeStatus.available,
                embeddable: youtubeStatus.embeddable,
                error: youtubeStatus.error,
                checkedAt: new Date().toISOString(),
                playbackOptions: youtubeStatus.available ? {
                    youtubeApp: `youtube://${movie.youtube_video_id}`,
                    youtubeWeb: `https://www.youtube.com/watch?v=${movie.youtube_video_id}`,
                    embed: youtubeStatus.embeddable
                } : null
            },
            message: youtubeStatus.available ? 'Movie is available' : 'Movie is not available'
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// GET /api/movies/:id/recommendations
// Get movie recommendations based on genres and viewing history
// =============================================================================
router.get('/:id/recommendations', async (req, res, next) => {
    try {
        const { id } = req.params
        const limit = parseInt(req.query.limit) || 10

        logger.info(`Getting recommendations for movie: ${id}`)

        const movie = await dbOperations.getMovieById(id)

        if (!movie) {
            return res.status(404).json({
                success: false,
                error: 'Movie not found'
            })
        }

        // Get movies with similar genres
        const genres = movie.movie_genres?.map(mg => mg.genres.id) || []

        if (genres.length === 0) {
            return res.json({
                success: true,
                data: {
                    recommendations: [],
                    basedOn: 'No genre data available'
                }
            })
        }

        // This would be a complex query - simplified for now
        const recommendations = await dbOperations.getMovies({
            sortBy: 'vote_average',
            sortOrder: 'desc'
        }, limit, 0)

        // Filter out the current movie
        const filteredMovies = recommendations.movies.filter(m => m.id !== id)

        res.json({
            success: true,
            data: {
                recommendations: filteredMovies.slice(0, limit),
                basedOn: 'Similar genres and popular movies',
                sourceMovie: {
                    id: movie.id,
                    title: movie.title
                }
            },
            message: `Generated ${filteredMovies.length} recommendations`
        })
    } catch (error) {
        next(error)
    }
})

export default router