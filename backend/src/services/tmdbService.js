import { logger } from '../utils/logger.js'
import { dbOperations } from '../config/database.js'

class TMDBService {
    constructor() {
        this.apiKey = process.env.TMDB_API_KEY
        this.readAccessToken = process.env.TMDB_READ_ACCESS_TOKEN
        this.baseURL = 'https://api.themoviedb.org/3'
        this.imageBaseURL = 'https://image.tmdb.org/t/p'

        // Rate limiting (40 requests per 10 seconds)
        this.requestQueue = []
        this.requestsPerWindow = 40
        this.windowSizeMs = 10000
        this.lastWindowStart = Date.now()
    }

    // =============================================================================
    // RATE LIMITING
    // =============================================================================

    async waitForRateLimit() {
        const now = Date.now()

        // Reset window if enough time has passed
        if (now - this.lastWindowStart >= this.windowSizeMs) {
            this.requestQueue = []
            this.lastWindowStart = now
            return
        }

        // Remove old requests from queue
        this.requestQueue = this.requestQueue.filter(
            requestTime => now - requestTime < this.windowSizeMs
        )

        // Wait if we've hit the limit
        if (this.requestQueue.length >= this.requestsPerWindow) {
            const oldestRequest = Math.min(...this.requestQueue)
            const waitTime = this.windowSizeMs - (now - oldestRequest) + 100

            logger.debug(`TMDB rate limit reached, waiting ${waitTime}ms`)
            await new Promise(resolve => setTimeout(resolve, waitTime))

            // Recursively check again
            return this.waitForRateLimit()
        }

        // Add current request to queue
        this.requestQueue.push(now)
    }

    async makeRequest(endpoint, params = {}) {
        await this.waitForRateLimit()

        const url = new URL(`${this.baseURL}${endpoint}`)
        url.searchParams.append('api_key', this.apiKey)

        Object.keys(params).forEach(key => {
            if (params[key] !== undefined && params[key] !== null) {
                url.searchParams.append(key, params[key])
            }
        })

        const startTime = Date.now()

        try {
            logger.debug(`TMDB API request: ${endpoint}`)

            const response = await fetch(url.toString())
            const responseTime = Date.now() - startTime

            if (!response.ok) {
                throw new Error(`TMDB API error: ${response.status} ${response.statusText}`)
            }

            const data = await response.json()

            // Log successful API usage
            await dbOperations.logApiUsage(
                'tmdb',
                endpoint,
                'GET',
                1,
                response.status,
                responseTime
            )

            return data

        } catch (error) {
            const responseTime = Date.now() - startTime

            logger.error(`TMDB API error for ${endpoint}:`, error.message)

            // Log failed API usage
            await dbOperations.logApiUsage(
                'tmdb',
                endpoint,
                'GET',
                1,
                500,
                responseTime,
                error.message
            )

            throw error
        }
    }

    // =============================================================================
    // HEALTH AND QUOTA CHECKS
    // =============================================================================

    async healthCheck() {
        try {
            // Simple API call to test connection
            await this.makeRequest('/configuration')
            return true
        } catch (error) {
            logger.error('TMDB API health check failed:', error.message)
            return false
        }
    }

    async quotaCheck() {
        // TMDB has rate limiting but no daily quota
        const now = Date.now()
        const recentRequests = this.requestQueue.filter(
            requestTime => now - requestTime < this.windowSizeMs
        )

        return {
            windowSize: this.windowSizeMs,
            windowLimit: this.requestsPerWindow,
            currentRequests: recentRequests.length,
            remaining: this.requestsPerWindow - recentRequests.length,
            resetsIn: this.windowSizeMs - (now - this.lastWindowStart)
        }
    }

    // =============================================================================
    // MOVIE OPERATIONS
    // =============================================================================

    async searchMovies(query, year = null) {
        try {
            logger.info(`Searching TMDB for: "${query}"`)

            const params = {
                query: query,
                include_adult: false,
                page: 1
            }

            if (year) {
                params.year = year
            }

            const data = await this.makeRequest('/search/movie', params)

            if (!data.results || data.results.length === 0) {
                logger.debug(`No TMDB results found for: "${query}"`)
                return []
            }

            return data.results.map(movie => ({
                id: movie.id,
                title: movie.title,
                originalTitle: movie.original_title,
                overview: movie.overview,
                releaseDate: movie.release_date,
                posterPath: movie.poster_path,
                backdropPath: movie.backdrop_path,
                voteAverage: movie.vote_average,
                voteCount: movie.vote_count,
                popularity: movie.popularity,
                genreIds: movie.genre_ids
            }))

        } catch (error) {
            logger.error(`TMDB search failed for "${query}":`, error.message)
            return []
        }
    }

    async getMovieDetails(movieId) {
        try {
            logger.debug(`Getting TMDB movie details: ${movieId}`)

            const params = {
                append_to_response: 'credits,videos,keywords,similar'
            }

            const data = await this.makeRequest(`/movie/${movieId}`, params)

            return {
                id: data.id,
                imdb_id: data.imdb_id,
                title: data.title,
                original_title: data.original_title,
                overview: data.overview,
                tagline: data.tagline,
                release_date: data.release_date,
                runtime: data.runtime,
                poster_path: data.poster_path,
                backdrop_path: data.backdrop_path,
                vote_average: data.vote_average,
                vote_count: data.vote_count,
                popularity: data.popularity,
                budget: data.budget,
                revenue: data.revenue,
                status: data.status,
                genres: data.genres,
                production_companies: data.production_companies,
                production_countries: data.production_countries,
                spoken_languages: data.spoken_languages,
                credits: this.processCredits(data.credits),
                videos: this.processVideos(data.videos),
                keywords: data.keywords?.keywords || [],
                similar: data.similar?.results || []
            }

        } catch (error) {
            logger.error(`Failed to get TMDB movie details for ID ${movieId}:`, error.message)
            throw error
        }
    }

    async getMovieCredits(movieId) {
        try {
            const data = await this.makeRequest(`/movie/${movieId}/credits`)
            return this.processCredits(data)
        } catch (error) {
            logger.error(`Failed to get movie credits for ID ${movieId}:`, error.message)
            return { cast: [], crew: [] }
        }
    }

    async getMovieVideos(movieId) {
        try {
            const data = await this.makeRequest(`/movie/${movieId}/videos`)
            return this.processVideos(data)
        } catch (error) {
            logger.error(`Failed to get movie videos for ID ${movieId}:`, error.message)
            return []
        }
    }

    async getGenres() {
        try {
            const data = await this.makeRequest('/genre/movie/list')
            return data.genres || []
        } catch (error) {
            logger.error('Failed to get TMDB genres:', error.message)
            return []
        }
    }

    // =============================================================================
    // DATA PROCESSING HELPERS
    // =============================================================================

    processCredits(credits) {
        if (!credits) return { cast: [], crew: [] }

        const cast = (credits.cast || []).map(person => ({
            id: person.id,
            name: person.name,
            character: person.character,
            order: person.order,
            profilePath: person.profile_path,
            gender: person.gender,
            knownForDepartment: person.known_for_department
        }))

        const crew = (credits.crew || []).map(person => ({
            id: person.id,
            name: person.name,
            job: person.job,
            department: person.department,
            profilePath: person.profile_path,
            gender: person.gender,
            knownForDepartment: person.known_for_department
        }))

        return { cast, crew }
    }

    processVideos(videos) {
        if (!videos || !videos.results) return []

        return videos.results
            .filter(video => video.site === 'YouTube' && video.type === 'Trailer')
            .map(video => ({
                id: video.id,
                key: video.key,
                name: video.name,
                site: video.site,
                type: video.type,
                size: video.size,
                official: video.official
            }))
    }

    // =============================================================================
    // IMAGE HELPERS
    // =============================================================================

    getImageURL(path, size = 'w500') {
        if (!path) return null
        return `${this.imageBaseURL}/${size}${path}`
    }

    getPosterURL(posterPath, size = 'w500') {
        return this.getImageURL(posterPath, size)
    }

    getBackdropURL(backdropPath, size = 'w1280') {
        return this.getImageURL(backdropPath, size)
    }

    getProfileURL(profilePath, size = 'w185') {
        return this.getImageURL(profilePath, size)
    }

    // =============================================================================
    // DISCOVERY HELPERS
    // =============================================================================

    async getPopularMovies(page = 1) {
        try {
            const data = await this.makeRequest('/movie/popular', { page })
            return data.results || []
        } catch (error) {
            logger.error('Failed to get popular movies:', error.message)
            return []
        }
    }

    async getTopRatedMovies(page = 1) {
        try {
            const data = await this.makeRequest('/movie/top_rated', { page })
            return data.results || []
        } catch (error) {
            logger.error('Failed to get top rated movies:', error.message)
            return []
        }
    }

    async getUpcomingMovies(page = 1) {
        try {
            const data = await this.makeRequest('/movie/upcoming', { page })
            return data.results || []
        } catch (error) {
            logger.error('Failed to get upcoming movies:', error.message)
            return []
        }
    }

    async getNowPlayingMovies(page = 1) {
        try {
            const data = await this.makeRequest('/movie/now_playing', { page })
            return data.results || []
        } catch (error) {
            logger.error('Failed to get now playing movies:', error.message)
            return []
        }
    }

    async getMoviesByGenre(genreId, page = 1) {
        try {
            const data = await this.makeRequest('/discover/movie', {
                with_genres: genreId,
                page: page,
                sort_by: 'vote_average.desc'
            })
            return data.results || []
        } catch (error) {
            logger.error(`Failed to get movies for genre ${genreId}:`, error.message)
            return []
        }
    }

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    cleanMovieTitle(title) {
        // Remove common suffixes and clean up title for better search results
        return title
            .replace(/\s*\(\d{4}\)$/, '') // Remove year in parentheses at end
            .replace(/\s*-\s*.*$/, '') // Remove everything after dash
            .replace(/[:\-–—]/g, ' ') // Replace colons and dashes with spaces
            .replace(/\s+/g, ' ') // Replace multiple spaces with single space
            .trim()
    }

    extractYearFromTitle(title) {
        const yearMatch = title.match(/\((\d{4})\)/)
        return yearMatch ? parseInt(yearMatch[1]) : null
    }

    async findBestMatch(movieTitle, originalTitle = null, year = null) {
        // Try multiple search strategies to find the best match

        const searchTitles = [
            movieTitle,
            this.cleanMovieTitle(movieTitle),
            originalTitle
        ].filter(Boolean)

        for (const searchTitle of searchTitles) {
            const results = await this.searchMovies(searchTitle, year)

            if (results.length > 0) {
                // Return the best match (first result is usually most relevant)
                return results[0]
            }
        }

        return null
    }
}

export const tmdbService = new TMDBService()
export default tmdbService