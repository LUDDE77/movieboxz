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
    // TV SERIES OPERATIONS
    // =============================================================================

    async searchTVSeries(query, year = null) {
        try {
            logger.info(`Searching TMDB for TV series: "${query}"`)

            const params = {
                query: query,
                include_adult: false,
                page: 1
            }

            if (year) {
                params.first_air_date_year = year
            }

            const data = await this.makeRequest('/search/tv', params)

            if (!data.results || data.results.length === 0) {
                logger.debug(`No TMDB TV series results found for: "${query}"`)
                return []
            }

            return data.results.map(series => ({
                id: series.id,
                name: series.name,
                originalName: series.original_name,
                overview: series.overview,
                firstAirDate: series.first_air_date,
                posterPath: series.poster_path,
                backdropPath: series.backdrop_path,
                voteAverage: series.vote_average,
                voteCount: series.vote_count,
                popularity: series.popularity,
                genreIds: series.genre_ids,
                originCountry: series.origin_country
            }))

        } catch (error) {
            logger.error(`TMDB TV series search failed for "${query}":`, error.message)
            return []
        }
    }

    async getTVSeriesDetails(seriesId) {
        try {
            logger.debug(`Getting TMDB TV series details: ${seriesId}`)

            const params = {
                append_to_response: 'credits,videos,keywords,similar,content_ratings,aggregate_credits'
            }

            const data = await this.makeRequest(`/tv/${seriesId}`, params)

            // Get US content rating if available
            const usRating = data.content_ratings?.results?.find(r => r.iso_3166_1 === 'US')

            return {
                id: data.id,
                name: data.name,
                original_name: data.original_name,
                overview: data.overview,
                tagline: data.tagline,
                first_air_date: data.first_air_date,
                last_air_date: data.last_air_date,
                status: data.status,
                type: data.type,
                number_of_seasons: data.number_of_seasons,
                number_of_episodes: data.number_of_episodes,
                episode_run_time: data.episode_run_time,
                poster_path: data.poster_path,
                backdrop_path: data.backdrop_path,
                vote_average: data.vote_average,
                vote_count: data.vote_count,
                popularity: data.popularity,
                genres: data.genres,
                created_by: data.created_by,
                production_companies: data.production_companies,
                production_countries: data.production_countries,
                spoken_languages: data.spoken_languages,
                origin_country: data.origin_country,
                networks: data.networks,
                seasons: data.seasons,
                content_rating: usRating?.rating || null,
                credits: this.processTVCredits(data.aggregate_credits || data.credits),
                videos: this.processVideos(data.videos),
                keywords: data.keywords?.results || [],
                similar: data.similar?.results || []
            }

        } catch (error) {
            logger.error(`Failed to get TMDB TV series details for ID ${seriesId}:`, error.message)
            throw error
        }
    }

    async getSeasonDetails(seriesId, seasonNumber) {
        try {
            logger.debug(`Getting TMDB season details: ${seriesId} S${seasonNumber}`)

            const params = {
                append_to_response: 'credits,videos'
            }

            const data = await this.makeRequest(`/tv/${seriesId}/season/${seasonNumber}`, params)

            return {
                id: data.id,
                season_number: data.season_number,
                name: data.name,
                overview: data.overview,
                air_date: data.air_date,
                poster_path: data.poster_path,
                vote_average: data.vote_average,
                episodes: data.episodes?.map(ep => ({
                    id: ep.id,
                    episode_number: ep.episode_number,
                    season_number: ep.season_number,
                    name: ep.name,
                    overview: ep.overview,
                    air_date: ep.air_date,
                    runtime: ep.runtime,
                    still_path: ep.still_path,
                    vote_average: ep.vote_average,
                    vote_count: ep.vote_count,
                    crew: ep.crew,
                    guest_stars: ep.guest_stars
                })) || [],
                credits: this.processCredits(data.credits),
                videos: this.processVideos(data.videos)
            }

        } catch (error) {
            logger.error(`Failed to get season details for ${seriesId} S${seasonNumber}:`, error.message)
            throw error
        }
    }

    async getEpisodeDetails(seriesId, seasonNumber, episodeNumber) {
        try {
            logger.debug(`Getting TMDB episode details: ${seriesId} S${seasonNumber}E${episodeNumber}`)

            const params = {
                append_to_response: 'credits,videos'
            }

            const data = await this.makeRequest(
                `/tv/${seriesId}/season/${seasonNumber}/episode/${episodeNumber}`,
                params
            )

            return {
                id: data.id,
                episode_number: data.episode_number,
                season_number: data.season_number,
                name: data.name,
                overview: data.overview,
                air_date: data.air_date,
                runtime: data.runtime,
                still_path: data.still_path,
                vote_average: data.vote_average,
                vote_count: data.vote_count,
                crew: data.crew,
                guest_stars: data.guest_stars,
                credits: this.processCredits(data.credits),
                videos: this.processVideos(data.videos)
            }

        } catch (error) {
            logger.error(`Failed to get episode details for ${seriesId} S${seasonNumber}E${episodeNumber}:`, error.message)
            throw error
        }
    }

    async getTVGenres() {
        try {
            const data = await this.makeRequest('/genre/tv/list')
            return data.genres || []
        } catch (error) {
            logger.error('Failed to get TMDB TV genres:', error.message)
            return []
        }
    }

    async getPopularTVSeries(page = 1) {
        try {
            const data = await this.makeRequest('/tv/popular', { page })
            return data.results || []
        } catch (error) {
            logger.error('Failed to get popular TV series:', error.message)
            return []
        }
    }

    async getTopRatedTVSeries(page = 1) {
        try {
            const data = await this.makeRequest('/tv/top_rated', { page })
            return data.results || []
        } catch (error) {
            logger.error('Failed to get top rated TV series:', error.message)
            return []
        }
    }

    async getTVSeriesByGenre(genreId, page = 1) {
        try {
            const data = await this.makeRequest('/discover/tv', {
                with_genres: genreId,
                page: page,
                sort_by: 'vote_average.desc'
            })
            return data.results || []
        } catch (error) {
            logger.error(`Failed to get TV series for genre ${genreId}:`, error.message)
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

    processTVCredits(aggregateCredits) {
        if (!aggregateCredits) return { cast: [], crew: [] }

        // TV series use aggregate_credits which combines all seasons/episodes
        // Each person has a 'roles' array (for cast) or 'jobs' array (for crew)
        const cast = (aggregateCredits.cast || []).map(person => ({
            id: person.id,
            name: person.name,
            roles: person.roles?.map(role => ({
                character: role.character,
                episodeCount: role.episode_count
            })) || [],
            totalEpisodeCount: person.total_episode_count,
            order: person.order,
            profilePath: person.profile_path,
            gender: person.gender,
            knownForDepartment: person.known_for_department
        }))

        const crew = (aggregateCredits.crew || []).map(person => ({
            id: person.id,
            name: person.name,
            jobs: person.jobs?.map(job => ({
                job: job.job,
                episodeCount: job.episode_count
            })) || [],
            department: person.department,
            totalEpisodeCount: person.total_episode_count,
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

    cleanSeriesTitle(title) {
        // Remove episode identifiers and clean up title for better search
        return title
            .replace(/\s*[Ss]\d+[Ee]\d+.*$/, '') // Remove S01E01 patterns
            .replace(/\s*[Ee]pisode\s+\d+.*$/i, '') // Remove "Episode 123" patterns
            .replace(/\s*-\s*Episode\s+\d+.*$/i, '') // Remove "- Episode 123"
            .replace(/\s*\|\s*.*$/, '') // Remove everything after pipe (e.g., "Bonanza | Title")
            .replace(/\s*\(\d{4}\)$/, '') // Remove year in parentheses at end
            .replace(/[:\-–—]/g, ' ') // Replace colons and dashes with spaces
            .replace(/\s+/g, ' ') // Replace multiple spaces with single space
            .trim()
    }

    extractSeasonEpisode(title) {
        // Extract season and episode numbers from title
        // Matches patterns like: S01E01, S1E1, Season 1 Episode 1, etc.

        // Pattern: S01E01 or S1E1
        let match = title.match(/[Ss](\d+)[Ee](\d+)/)
        if (match) {
            return {
                season: parseInt(match[1]),
                episode: parseInt(match[2])
            }
        }

        // Pattern: Season 1 Episode 1
        match = title.match(/[Ss]eason\s+(\d+)\s+[Ee]pisode\s+(\d+)/i)
        if (match) {
            return {
                season: parseInt(match[1]),
                episode: parseInt(match[2])
            }
        }

        // Pattern: Episode 1 (assume season 1 if not specified)
        match = title.match(/[Ee]pisode\s+(\d+)/i)
        if (match) {
            return {
                season: 1,
                episode: parseInt(match[1])
            }
        }

        return null
    }

    async findBestSeriesMatch(seriesTitle, originalTitle = null, year = null) {
        // Try multiple search strategies to find the best TV series match

        const searchTitles = [
            seriesTitle,
            this.cleanSeriesTitle(seriesTitle),
            originalTitle
        ].filter(Boolean)

        for (const searchTitle of searchTitles) {
            const results = await this.searchTVSeries(searchTitle, year)

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
