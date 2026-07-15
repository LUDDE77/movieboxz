import express from 'express'
import { dbOperations, supabase } from '../config/database.js'
import { validateRequest } from '../middleware/validation.js'
import { movieQuerySchema, movieIdSchema } from '../schemas/movieSchemas.js'
import { logger } from '../utils/logger.js'
import { youtubeService } from '../services/youtubeService.js'
import { tmdbService } from '../services/tmdbService.js'

const router = express.Router()

// Maximum items per page allowed on public list endpoints
const MAX_LIMIT = 100

// Cache-Control for public read-only list endpoints
const PUBLIC_CACHE_CONTROL = 'public, max-age=300, stale-while-revalidate=600'

// Resolve the requesting user's country (ISO-3166-1 alpha-2) for per-country
// availability filtering. Prefer explicit ?country=, fall back to x-country
// header. getMovies/getMoviesByGenre sanitize/validate the value.
const userCountry = (req) => req.query.country || req.headers['x-country'] || null

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
            needs_verification,
            is_tv_series,
            is_kids_content,
            year_min,
            year_max,
            sort = 'popular',
            page = 1,
            limit = 20
        } = req.query

        const pageNum = parseInt(page) || 1
        const limitNum = Math.min(parseInt(limit) || 20, MAX_LIMIT)
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

        if (needs_verification === 'true') {
            filters.needsVerification = true
        }

        if (is_tv_series === 'true') {
            filters.isTvSeries = true
        } else {
            // Movie surfaces exclude TV episodes by default; pass is_tv_series=true
            // to fetch episodes explicitly (Browse's TV Series row does this)
            filters.excludeTvSeries = true
        }

        if (is_kids_content === 'true') {
            filters.isKidsContent = true
        }

        // Decade browse rows pass a release-year range
        if (year_min) filters.yearMin = year_min
        if (year_max) filters.yearMax = year_max

        // Map sort parameter to database fields
        const sortOptions = {
            popular: { sortBy: 'view_count', sortOrder: 'desc' },
            recent: { sortBy: 'published_at', sortOrder: 'desc' },
            rating: { sortBy: 'vote_average', sortOrder: 'desc' }
        }

        const sortConfig = sortOptions[sort] || sortOptions.popular
        filters.sortBy = sortConfig.sortBy
        filters.sortOrder = sortConfig.sortOrder
        filters.country = userCountry(req)

        // If genre filter is provided, use genre-specific query
        let result
        if (genre) {
            result = await dbOperations.getMoviesByGenre(
                genre,
                limitNum,
                offset,
                sortConfig.sortBy,
                sortConfig.sortOrder,
                userCountry(req)
            )
        } else {
            result = await dbOperations.getMovies(filters, limitNum, offset)
        }

        res.set('Cache-Control', PUBLIC_CACHE_CONTROL)
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

        // Use getMovies to get fully-shaped movie objects (with channel_title, genres, etc.)
        // sorted by featured_order so the admin-curated order is preserved
        const result = await dbOperations.getMovies(
            { featured: true, excludeTvSeries: true, sortBy: 'featured_order', sortOrder: 'asc', country: userCountry(req) },
            5,
            0
        )

        res.set('Cache-Control', PUBLIC_CACHE_CONTROL)
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
        const limit = Math.min(parseInt(req.query.limit) || 20, MAX_LIMIT)
        const offset = (page - 1) * limit

        logger.info(`Fetching trending movies - page ${page}`)

        let result = await dbOperations.getMovies({
            trending: true,
            excludeTvSeries: true,
            country: userCountry(req)
        }, limit, offset)

        // No movies are flagged trending — fall back to most viewed so the
        // apps' Trending row always has content
        let usedFallback = false
        if (result.total === 0) {
            usedFallback = true
            result = await dbOperations.getMovies({
                sortBy: 'view_count',
                sortOrder: 'desc',
                excludeTvSeries: true,
                country: userCountry(req)
            }, limit, offset)
        }

        res.set('Cache-Control', PUBLIC_CACHE_CONTROL)
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
            message: usedFallback
                ? `Retrieved ${result.movies.length} trending movies (most-viewed fallback)`
                : `Retrieved ${result.movies.length} trending movies`
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
        const limit = Math.min(parseInt(req.query.limit) || 20, MAX_LIMIT)
        const offset = (page - 1) * limit

        // Whitelist sort values — never pass raw client input into .order()
        const ALLOWED_SORTS = ['view_count', 'vote_average', 'published_at', 'created_at']
        const sortBy = ALLOWED_SORTS.includes(req.query.sort) ? req.query.sort : 'view_count'

        logger.info(`Fetching popular movies - page ${page}, sorted by ${sortBy}`)

        const result = await dbOperations.getMovies({
            sortBy,
            sortOrder: 'desc',
            excludeTvSeries: true,
            country: userCountry(req)
        }, limit, offset)

        res.set('Cache-Control', PUBLIC_CACHE_CONTROL)
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
// GET /api/movies/top-rated
// Get highest rated movies (filtered by minimum vote count)
// Query params:
//   - minVotes: Minimum number of votes required (default: 10)
//   - page: Page number (default: 1)
//   - limit: Items per page (default: 50)
// =============================================================================
router.get('/top-rated', async (req, res, next) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = Math.min(parseInt(req.query.limit) || 50, MAX_LIMIT)
        const offset = (page - 1) * limit
        // source=imdb ranks by the IMDB rating (numeric); default ranks by TMDB vote_average.
        const source = req.query.source === 'imdb' ? 'imdb' : 'tmdb'
        const ratingColumn = source === 'imdb' ? 'imdb_rating' : 'vote_average'
        const voteColumn = source === 'imdb' ? 'imdb_votes' : 'vote_count'
        const minVotes = parseInt(req.query.minVotes) || (source === 'imdb' ? 1000 : 10)

        logger.info(`Fetching top rated movies (${source}) - page ${page}, min ${minVotes} ${voteColumn}`)

        // Use raw Supabase query to filter NULL ratings and minimum votes
        let query = supabase
            .from('movies')
            .select(`
                *,
                channels(id, title, thumbnail_url),
                movie_genres(genres(id, name))
            `, { count: 'exact' })
            .eq('is_available', true)
            .not(ratingColumn, 'is', null)    // Filter out NULL ratings
            .gte(voteColumn, minVotes)        // Minimum vote threshold

        // The IMDB high-score row is a films-only list — keep TV episodes out
        // (is_tv_series is not true keeps both false and NULL).
        if (source === 'imdb') {
            query = query.not('is_tv_series', 'is', true)
        }

        // Per-country availability filter (same semantics as getMovies).
        // SHOW-IF-UNKNOWN: the `.is.null` branch lets movies with no region
        // data pass (worldwide). It is REQUIRED.
        const cc = String(req.query.country || req.headers['x-country'] || '').trim().toUpperCase()
        const validCC = /^[A-Z]{2}$/.test(cc) ? cc : null
        if (validCC) {
            query = query.or(`region_blocked.is.null,region_blocked.not.cs.{${validCC}}`)
            query = query.or(`region_allowed.is.null,region_allowed.cs.{${validCC}}`)
            if (process.env.REGION_FILTER_HIDE_IF_UNKNOWN === 'true') {
                query = query.not('region_checked_at', 'is', null)
            }
        }

        const { data, error, count } = await query
            .order(ratingColumn, { ascending: false })
            .range(offset, offset + limit - 1)

        if (error) {
            throw error
        }

        // Transform data to match standard format
        const transformedMovies = (data || []).map(movie => {
            const { channels, movie_genres, ...movieData } = movie
            return {
                ...movieData,
                channel_title: channels?.title || null,
                channel_thumbnail: channels?.thumbnail_url || null,
                genres: movie_genres?.map(mg => mg.genres) || []
            }
        })

        res.json({
            success: true,
            data: {
                movies: transformedMovies,
                pagination: {
                    page,
                    limit,
                    total: count,
                    pages: Math.ceil(count / limit)
                },
                filters: {
                    minVotes
                }
            },
            message: `Retrieved ${transformedMovies.length} top rated movies`
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
        const limit = Math.min(parseInt(req.query.limit) || 20, MAX_LIMIT)
        const offset = (page - 1) * limit

        logger.info(`Fetching recently added movies - page ${page}`)

        const result = await dbOperations.getMovies({
            sortBy: 'added_at',
            sortOrder: 'desc',
            excludeTvSeries: true,
            country: userCountry(req)
        }, limit, offset)

        res.set('Cache-Control', PUBLIC_CACHE_CONTROL)
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
        const { q, category, year, page = 1 } = req.query
        const limit = Math.min(parseInt(req.query.limit) || 20, MAX_LIMIT)
        const offset = (page - 1) * limit

        logger.info(`Searching movies: "${q}", category: ${category}, year: ${year}`)

        const filters = {
            search: q,
            country: userCountry(req)
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
        const limit = Math.min(parseInt(req.query.limit) || 20, MAX_LIMIT)
        const offset = (page - 1) * limit

        logger.info(`Fetching movies in category: ${category}`)

        const result = await dbOperations.getMovies({
            category,
            sortBy: 'vote_average',
            sortOrder: 'desc',
            country: userCountry(req)
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
        const limit = Math.min(parseInt(req.query.limit) || 20, MAX_LIMIT)
        const offset = (page - 1) * limit

        logger.info(`Fetching movies from channel: ${channelId}`)

        // Get channel info
        const channel = await dbOperations.getChannelById(channelId)

        // Get movies from channel
        const result = await dbOperations.getMovies({
            channelId,
            sortBy: 'published_at',
            sortOrder: 'desc',
            country: userCountry(req)
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

        // YouTube availability: only re-check if never validated or stale (> 24h),
        // and always fire-and-forget in the background — never block the response
        // or burn quota on every consumer detail view
        const lastValidated = movie.last_validated ? new Date(movie.last_validated) : null
        const validationStale = !lastValidated ||
            (Date.now() - lastValidated.getTime()) > 24 * 60 * 60 * 1000

        if (validationStale) {
            youtubeService.checkVideoAvailability(movie.youtube_video_id)
                .then(youtubeStatus => dbOperations.updateMovie(id, {
                    is_available: youtubeStatus.available,
                    is_embeddable: youtubeStatus.embeddable,
                    validation_error: youtubeStatus.error,
                    last_validated: new Date().toISOString()
                }))
                .catch(() => {})
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
        const limit = Math.min(parseInt(req.query.limit) || 12, MAX_LIMIT)

        logger.info(`Getting recommendations for movie: ${id}`)

        const movie = await dbOperations.getMovieById(id)

        if (!movie) {
            return res.status(404).json({
                success: false,
                error: 'Movie not found'
            })
        }

        // getMovieById flattens movie_genres into movie.genres ([{id, name}])
        const genreIds = (movie.genres || []).map(g => g?.id).filter(Boolean)

        if (genreIds.length === 0) {
            return res.json({
                success: true,
                data: {
                    recommendations: [],
                    basedOn: 'No genre data available'
                }
            })
        }

        // Find available movies sharing at least one genre with the source movie,
        // best-rated first. shared_genres!inner restricts to matching movies while
        // movie_genres(genres(...)) still returns each movie's full genre list.
        const { data, error } = await supabase
            .from('movies')
            .select(`
                *,
                channels(id, title, thumbnail_url),
                movie_genres(genres(id, name)),
                shared_genres:movie_genres!inner(genre_id)
            `)
            .in('shared_genres.genre_id', genreIds)
            .neq('id', id)
            .eq('is_available', true)
            .order('vote_average', { ascending: false, nullsFirst: false })
            .limit(limit)

        if (error) {
            throw error
        }

        // Flatten to the standard movie shape used by other endpoints
        const recommendations = (data || []).map(rec => {
            const { channels, movie_genres, shared_genres, ...movieData } = rec
            return {
                ...movieData,
                channel_title: channels?.title || null,
                channel_thumbnail: channels?.thumbnail_url || null,
                genres: movie_genres?.map(mg => mg.genres) || []
            }
        })

        res.json({
            success: true,
            data: {
                recommendations,
                basedOn: 'Shared genres',
                sourceMovie: {
                    id: movie.id,
                    title: movie.title
                }
            },
            message: `Generated ${recommendations.length} recommendations`
        })
    } catch (error) {
        next(error)
    }
})

export default router
