import express from 'express'
import { dbOperations, supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'

// Curated public-domain films used ONLY for App Store screenshot capture
// (?demo=pd). Apple 4.1(a) flagged screenshots showing copyrighted posters/stars,
// so the screenshot build shows only these public-domain classics.
const DEMO_PD_MOVIE_IDS = [
    '3511e6ca-bfda-4f93-b5ca-cde146c810fd', 'd6becd9e-9b22-4c23-8d5e-41c0aa2f2170',
    '47c82ce6-a7d7-4265-b2aa-0d335d1f6c3d', '694a5fbe-12e3-407c-9635-347abe834759',
    'a6b865be-68b4-416f-8199-ea6989f6b284', '2209ca79-448d-43b2-93fb-8d451ea34d2f',
    'a4a2471a-06dc-45f0-9949-080b5eb95b47', 'b6c4a95c-d2d6-4fa6-ae19-257d3861535e',
    'f8e3eaf7-797c-4c91-b475-60207b73400d', '3f1274ec-495e-4793-bfc6-70c21b9088d8',
    '1a5b68f8-05da-4215-ae6e-2c7997bee830', '8b72de9d-36b3-42ec-839c-ef2b11b28ffd',
    'd8395484-1375-4e1b-86d9-59e808d1392a', 'e7cba85c-5875-4972-b83e-e9ef25870c2d',
    '3a7d539f-8384-40c0-bfd7-d6729f0a18c8', '2aa78008-2ed8-4df7-934b-5051198897ab',
    'fc43d885-0094-46c6-98e3-739e5f85ebb7', 'bed692ed-9575-49f7-96fb-6d02070d46c9',
    '67f27503-cb19-4af4-85a7-0203cad3e558', 'b1cd3bb9-d6ee-4598-8279-28b7ca9bb7b7'
]

// Build a full /browse/home payload from the curated public-domain set only.
async function buildDemoHome() {
    const { data: rows } = await supabase.from('movies').select('*').in('id', DEMO_PD_MOVIE_IDS)
    const byId = new Map((rows || []).map(m => [m.id, m]))
    const films = DEMO_PD_MOVIE_IDS.map(id => byId.get(id)).filter(Boolean)
    const rot = (n) => films.slice(n).concat(films.slice(0, n))
    return {
        featured: films.slice(0, 5),
        popular: rot(2),
        trending: rot(6).slice(0, 10),
        recent: rot(4),
        allMovies: films,
        uncategorized: [],
        topImdb: [...films].sort((a, b) => (b.imdb_rating || 0) - (a.imdb_rating || 0)).slice(0, 12),
        genres: [
            { genre: { id: 27, name: 'Horror' }, movies: rot(0).slice(0, 8) },
            { genre: { id: 80, name: 'Crime' }, movies: rot(7).slice(0, 8) },
            { genre: { id: 37, name: 'Western' }, movies: rot(10).slice(0, 6) }
        ],
        eras: { modern: [], eighties90s: [], sixties70s: rot(1).slice(0, 10), classic: rot(3) }
    }
}

const router = express.Router()

// Maximum items per page allowed on public list endpoints
const MAX_LIMIT = 100

// Cache-Control for public read-only endpoints
const PUBLIC_CACHE_CONTROL = 'public, max-age=300, stale-while-revalidate=600'

// =============================================================================
// GET /api/browse/genres
// List all genres with movie counts
// =============================================================================
router.get('/genres', async (req, res, next) => {
    try {
        logger.info('Fetching all genres with counts')

        const genres = await dbOperations.getGenresWithCounts()

        res.set('Cache-Control', PUBLIC_CACHE_CONTROL)
        res.json({
            success: true,
            data: {
                genres: genres.map(genre => ({
                    id: genre.id,
                    tmdb_id: genre.tmdb_id,
                    name: genre.name,
                    movie_count: parseInt(genre.movie_count) || 0
                })),
                pagination: {
                    page: 1,
                    limit: genres.length,
                    total: genres.length,
                    pages: 1
                }
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

        res.set('Cache-Control', PUBLIC_CACHE_CONTROL)
        res.json({
            success: true,
            data: {
                id: genre.id,
                tmdb_id: genre.tmdb_id,
                name: genre.name,
                movie_count: parseInt(genre.movie_count) || 0
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
        const limit = Math.min(parseInt(req.query.limit) || 20, MAX_LIMIT)
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

        // Get movies by genre (per-country availability filter)
        const result = await dbOperations.getMoviesByGenre(
            genreId,
            limit,
            offset,
            sortConfig.sortBy,
            sortConfig.sortOrder,
            req.query.country || req.headers['x-country'] || null
        )

        res.set('Cache-Control', PUBLIC_CACHE_CONTROL)
        res.json({
            success: true,
            data: {
                genre: {
                    id: genre.id,
                    tmdb_id: genre.tmdb_id,
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

// =============================================================================
// GET /api/browse/uncategorized
// Get movies without genre assignments (uncategorized)
// Query params: page, limit, sort (popular, recent, rating)
// =============================================================================
router.get('/uncategorized', async (req, res, next) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = Math.min(parseInt(req.query.limit) || 20, MAX_LIMIT)
        const offset = (page - 1) * limit
        const sort = req.query.sort || 'popular' // popular, recent, rating

        logger.info(`Fetching uncategorized movies - page ${page}, sort: ${sort}`)

        // Map sort param to database sort options
        const sortOptions = {
            popular: { sortBy: 'view_count', sortOrder: 'desc' },
            recent: { sortBy: 'published_at', sortOrder: 'desc' },
            rating: { sortBy: 'vote_average', sortOrder: 'desc' }
        }

        const sortConfig = sortOptions[sort] || sortOptions.popular

        // Get uncategorized movies
        const result = await dbOperations.getUncategorizedMovies(
            limit,
            offset,
            sortConfig.sortBy,
            sortConfig.sortOrder
        )

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
                },
                sort
            },
            message: `Retrieved ${result.movies.length} uncategorized movies`
        })
    } catch (error) {
        next(error)
    }
})

// GET /api/browse/home
// The ENTIRE Browse tab in a single response — featured, popular, trending,
// recent, all, uncategorized, High Score IMDb, every genre carousel, and the
// decade rails. This replaces ~20 separate requests the client used to fire on
// each Browse load, which is far friendlier to the API rate limit and faster.
router.get('/home', async (req, res, next) => {
    try {
        // Screenshot demo: return ONLY curated public-domain films (App Store 4.1(a)).
        if (req.query.demo === 'pd') {
            return res.json({ success: true, data: await buildDemoHome(), message: 'Browse home (demo)' })
        }
        const cc = String(req.query.country || req.headers['x-country'] || '').trim().toUpperCase()
        const country = /^[A-Z]{2}$/.test(cc) ? cc : null
        const base = { excludeTvSeries: true, country }
        const pop = { sortBy: 'view_count', sortOrder: 'desc' }

        logger.info(`Browse home (country=${country || 'all'})`)

        // Genres (with counts) first, so we know which carousels to build.
        const genresWithCounts = await dbOperations.getGenresWithCounts()
        const activeGenres = (genresWithCounts || []).filter(g => (g.movie_count || 0) > 0)

        // Everything else in parallel — one DB round trip's worth of work,
        // one HTTP response.
        const [
            featured, popular, recent, allMovies, uncategorized, topImdb,
            modern, eighties90s, sixties70s, classic, genreCarousels
        ] = await Promise.all([
            dbOperations.getMovies({ ...base, featured: true, sortBy: 'featured_order', sortOrder: 'asc' }, 10),
            dbOperations.getMovies({ ...base, ...pop }, 10),
            dbOperations.getMovies({ ...base, sortBy: 'added_at', sortOrder: 'desc' }, 50),
            dbOperations.getMovies({ ...base, ...pop }, 50),
            dbOperations.getUncategorizedMovies(10, 0, 'view_count', 'desc'),
            dbOperations.getMovies({ ...base, imdbRanked: true, sortBy: 'imdb_rating', sortOrder: 'desc' }, 20),
            dbOperations.getMovies({ ...base, ...pop, yearMin: 2000 }, 20),
            dbOperations.getMovies({ ...base, ...pop, yearMin: 1980, yearMax: 1999 }, 20),
            dbOperations.getMovies({ ...base, ...pop, yearMin: 1960, yearMax: 1979 }, 20),
            dbOperations.getMovies({ ...base, ...pop, yearMax: 1959 }, 20),
            Promise.all(activeGenres.map(async (g) => ({
                genre: { id: g.id, name: g.name },
                movies: (await dbOperations.getMoviesByGenre(g.id, 10, 0, 'view_count', 'desc', country)).movies
            })))
        ])

        res.set('Cache-Control', PUBLIC_CACHE_CONTROL)
        res.json({
            success: true,
            data: {
                featured: featured.movies,
                popular: popular.movies,
                trending: recent.movies.filter(m => m.trending),
                recent: recent.movies,
                allMovies: allMovies.movies,
                uncategorized: uncategorized.movies,
                topImdb: topImdb.movies,
                genres: genreCarousels.filter(g => g.movies.length > 0),
                eras: {
                    modern: modern.movies,
                    eighties90s: eighties90s.movies,
                    sixties70s: sixties70s.movies,
                    classic: classic.movies
                }
            },
            message: 'Browse home'
        })
    } catch (error) {
        next(error)
    }
})

export default router
