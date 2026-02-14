import { tmdbService } from './tmdbService.js'
import { omdbService } from './omdbService.js'
import { logger } from '../utils/logger.js'
import axios from 'axios'
import channelPatternManager from './channelPatternManager.js'

class EnhancedEnrichment {
    constructor() {
        this.confidenceThresholds = {
            autoAccept: 70,
            manualReview: 50,
            reject: 50
        }
    }

    /**
     * Extract actor hints from YouTube title using ChannelPatternManager
     * @param {string} youtubeTitle - Full YouTube video title
     * @param {string} channelTitle - Channel name
     * @param {string} channelId - Channel ID
     * @returns {Promise<Object>} { title, actors: [...], mediaHint, genre, year }
     */
    async extractActorHints(youtubeTitle, channelTitle, channelId) {
        const result = {
            title: youtubeTitle,
            actors: [],
            mediaHint: null,
            genre: null,
            year: null
        }

        // Try to get pattern from database
        const pattern = await channelPatternManager.getPattern(channelId)

        if (pattern) {
            // Use ChannelPatternManager to extract metadata
            const metadata = channelPatternManager.extractMetadata(youtubeTitle, pattern)

            if (metadata) {
                result.title = metadata.title || youtubeTitle
                result.actors = metadata.actorsArray || []
                result.genre = metadata.genre || null
                result.year = metadata.year || null

                logger.info(`✓ Pattern extracted: title="${result.title}", actors=[${result.actors.join(', ')}], genre="${result.genre}", year=${result.year}`)
            } else {
                logger.debug(`No pattern match for: ${youtubeTitle}`)
            }
        } else {
            logger.debug(`No pattern configured for channel: ${channelId}`)
        }

        // Detect media type hints
        if (/FULL MOVIE/i.test(youtubeTitle)) {
            result.mediaHint = 'movie'
        } else if (/TV SERIES|SEASON|EPISODE/i.test(youtubeTitle)) {
            result.mediaHint = 'tv'
        }

        return result
    }

    /**
     * Search TMDB with actor context
     * @param {string} title - Cleaned movie/show title
     * @param {Array<string>} actorHints - Actor names from title
     * @param {number} publishYear - Year from YouTube publish date
     * @param {string} mediaHint - 'movie' or 'tv' hint
     * @returns {Array} TMDB search results
     */
    async searchTMDBWithActors(title, actorHints, publishYear, mediaHint) {
        const results = []

        // Strategy 1: Search with actor name (if available)
        if (actorHints && actorHints.length > 0) {
            const actorQuery = `${title} ${actorHints[0]}`
            logger.debug(`Strategy 1: Searching with actor context: "${actorQuery}"`)

            // Search both movies and TV series
            const movieResults = await tmdbService.searchMovies(actorQuery, publishYear)
            const tvResults = await tmdbService.searchTVSeries(actorQuery, publishYear)

            // Add media_type to each result
            movieResults.forEach(r => r.media_type = 'movie')
            tvResults.forEach(r => r.media_type = 'tv')

            results.push(...movieResults, ...tvResults)
        }

        // Strategy 2: Fallback to title-only search
        if (results.length === 0) {
            logger.debug(`Strategy 2: Fallback to title-only: "${title}"`)

            // Search both movies and TV series
            const movieResults = await tmdbService.searchMovies(title, publishYear)
            const tvResults = await tmdbService.searchTVSeries(title, publishYear)

            // Add media_type to each result
            movieResults.forEach(r => r.media_type = 'movie')
            tvResults.forEach(r => r.media_type = 'tv')

            results.push(...movieResults, ...tvResults)
        }

        // Prioritize based on media hint
        if (mediaHint && results.length > 0) {
            results.sort((a, b) => {
                const aMatch = a.media_type === mediaHint ? 1 : 0
                const bMatch = b.media_type === mediaHint ? 1 : 0
                return bMatch - aMatch
            })
        }

        return results
    }

    /**
     * Calculate confidence score for a match
     * @param {Object} youtubeMovie - YouTube movie data
     * @param {Object} tmdbCandidate - TMDB result
     * @param {Object} actorHints - Actor extraction result
     * @returns {number} Confidence score 0-100
     */
    async calculateConfidence(youtubeMovie, tmdbCandidate, actorHints) {
        let score = 0

        // Title similarity (30 points)
        const tmdbTitle = tmdbCandidate.media_type === 'movie'
            ? tmdbCandidate.title
            : tmdbCandidate.name

        const titleSimilarity = this.levenshteinSimilarity(actorHints.title.toLowerCase(), tmdbTitle.toLowerCase())
        score += titleSimilarity * 30

        // Actor validation (40 points)
        if (actorHints.actors.length > 0) {
            const actorMatch = await this.validateActorMatch(tmdbCandidate.id, tmdbCandidate.media_type, actorHints)
            if (actorMatch) {
                score += 40
            }
        }

        // Media type match (20 points)
        if (actorHints.mediaHint === tmdbCandidate.media_type) {
            score += 20
        }

        // Year proximity (10 points)
        const publishYear = new Date(youtubeMovie.published_at).getFullYear()
        const tmdbYear = tmdbCandidate.media_type === 'movie'
            ? new Date(tmdbCandidate.releaseDate).getFullYear()
            : new Date(tmdbCandidate.firstAirDate).getFullYear()

        if (!isNaN(tmdbYear) && !isNaN(publishYear)) {
            const yearDiff = Math.abs(tmdbYear - publishYear)
            score += Math.max(0, 10 - yearDiff)
        }

        return Math.round(score)
    }

    /**
     * Validate actor hints against TMDB cast
     * @param {number} tmdbId - TMDB movie/tv ID
     * @param {string} mediaType - 'movie' or 'tv'
     * @param {Object} actorHints - Actor extraction result
     * @returns {boolean} True if actor match found
     */
    async validateActorMatch(tmdbId, mediaType, actorHints) {
        try {
            let credits
            if (mediaType === 'movie') {
                credits = await tmdbService.getMovieCredits(tmdbId)
            } else {
                credits = await tmdbService.getTVCredits(tmdbId)
            }

            if (!credits || !credits.cast) return false

            // Check top 10 cast members
            const topCast = credits.cast.slice(0, 10).map(c => c.name.toLowerCase())

            for (const actorHint of actorHints.actors) {
                const hintLower = actorHint.toLowerCase()
                for (const castMember of topCast) {
                    const similarity = this.levenshteinSimilarity(hintLower, castMember)
                    if (similarity > 0.8) {
                        logger.debug(`✓ Actor match: "${actorHint}" ≈ "${castMember}" (${Math.round(similarity * 100)}%)`)
                        return true
                    }
                }
            }

            return false
        } catch (error) {
            logger.error(`Failed to validate actor match:`, error.message)
            return false
        }
    }

    /**
     * Scrape IMDB page for additional data
     * @param {string} imdbId - IMDB ID (e.g., "tt0490086")
     * @returns {Object|null} IMDB data
     */
    async scrapeIMDBData(imdbId) {
        try {
            const url = `https://www.imdb.com/title/${imdbId}/`
            logger.debug(`Scraping IMDB: ${url}`)

            const response = await axios.get(url, {
                headers: {
                    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
                },
                timeout: 10000
            })

            const html = response.data

            // Extract JSON-LD structured data
            const jsonLdMatch = html.match(/<script type="application\/ld\+json">(.*?)<\/script>/s)
            if (!jsonLdMatch) {
                logger.warn(`No JSON-LD data found on IMDB page: ${imdbId}`)
                return null
            }

            const jsonData = JSON.parse(jsonLdMatch[1])

            // Parse IMDB data
            const imdbData = {
                imdb_id: imdbId,
                title: jsonData.name,
                description: jsonData.description,
                release_date: jsonData.datePublished,
                runtime_minutes: this.parseISO8601Duration(jsonData.duration),
                imdb_rating: jsonData.aggregateRating?.ratingValue,
                imdb_votes: jsonData.aggregateRating?.ratingCount,
                rated: jsonData.contentRating,
                director: Array.isArray(jsonData.director)
                    ? jsonData.director.map(d => d.name).join(', ')
                    : jsonData.director?.name,
                actors: Array.isArray(jsonData.actor)
                    ? jsonData.actor.slice(0, 5).map(a => a.name).join(', ')
                    : null,
                genres: Array.isArray(jsonData.genre) ? jsonData.genre : [jsonData.genre],
                country: jsonData.countryOfOrigin?.name,
                language: jsonData.inLanguage,
                type: jsonData['@type'] // Movie, TVSeries, TVMiniSeries
            }

            logger.debug(`✓ IMDB data scraped: ${imdbData.title} (${imdbData.type})`)
            return imdbData

        } catch (error) {
            logger.error(`Failed to scrape IMDB ${imdbId}:`, error.message)
            return null
        }
    }

    /**
     * Parse ISO 8601 duration to minutes
     * @param {string} duration - e.g., "PT1H45M"
     * @returns {number|null}
     */
    parseISO8601Duration(duration) {
        if (!duration) return null

        const match = duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?/)
        if (!match) return null

        const hours = parseInt(match[1]) || 0
        const minutes = parseInt(match[2]) || 0
        return hours * 60 + minutes
    }

    /**
     * Levenshtein distance similarity (0-1)
     */
    levenshteinSimilarity(str1, str2) {
        const longer = str1.length > str2.length ? str1 : str2
        const shorter = str1.length > str2.length ? str2 : str1

        if (longer.length === 0) return 1.0

        const editDistance = this.levenshteinDistance(longer, shorter)
        return (longer.length - editDistance) / longer.length
    }

    /**
     * Levenshtein distance calculation
     */
    levenshteinDistance(str1, str2) {
        const matrix = []

        for (let i = 0; i <= str2.length; i++) {
            matrix[i] = [i]
        }

        for (let j = 0; j <= str1.length; j++) {
            matrix[0][j] = j
        }

        for (let i = 1; i <= str2.length; i++) {
            for (let j = 1; j <= str1.length; j++) {
                if (str2.charAt(i - 1) === str1.charAt(j - 1)) {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = Math.min(
                        matrix[i - 1][j - 1] + 1,
                        matrix[i][j - 1] + 1,
                        matrix[i - 1][j] + 1
                    )
                }
            }
        }

        return matrix[str2.length][str1.length]
    }

    /**
     * Search IMDB by title to find IMDB ID
     * @param {string} title - Movie title
     * @param {number} year - Optional release year
     * @returns {string|null} IMDB ID (e.g., "tt27036391") or null
     */
    async searchIMDBByTitle(title, year = null) {
        try {
            // URL encode the title for search
            const searchQuery = encodeURIComponent(title)
            const searchUrl = `https://www.imdb.com/find/?q=${searchQuery}&s=tt&ttype=ft&ref_=fn_ft`

            logger.debug(`Searching IMDB: ${searchUrl}`)

            const response = await axios.get(searchUrl, {
                headers: {
                    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
                },
                timeout: 10000
            })

            const html = response.data

            // Extract IMDB IDs from search results
            // Look for pattern: /title/tt1234567/
            const imdbIdMatches = html.match(/\/title\/(tt\d+)\//g)

            if (!imdbIdMatches || imdbIdMatches.length === 0) {
                logger.warn(`No IMDB results found for: ${title}`)
                return null
            }

            // Extract first IMDB ID (most relevant result)
            const firstMatch = imdbIdMatches[0].match(/tt\d+/)
            const imdbId = firstMatch ? firstMatch[0] : null

            if (imdbId) {
                logger.info(`✓ Found IMDB ID: ${imdbId} for "${title}"`)
            }

            return imdbId

        } catch (error) {
            logger.error(`Failed to search IMDB for "${title}":`, error.message)
            return null
        }
    }

    /**
     * Enrich movie directly from IMDB ID
     * @param {string} imdbId - IMDB ID (e.g., "tt27036391")
     * @returns {Object|null} Enrichment data
     */
    async enrichByIMDBId(imdbId) {
        try {
            logger.info(`Enriching by IMDB ID: ${imdbId}`)

            // Scrape IMDB data
            const imdbData = await this.scrapeIMDBData(imdbId)

            if (!imdbData) {
                logger.warn(`Failed to scrape IMDB data for: ${imdbId}`)
                return null
            }

            // Try to get TMDB data if possible (for posters/backdrops)
            let tmdbDetails = null
            try {
                const tmdbResults = await tmdbService.findByIMDBId(imdbId)
                if (tmdbResults) {
                    tmdbDetails = tmdbResults
                }
            } catch (error) {
                logger.debug(`TMDB lookup failed for ${imdbId}, using IMDB-only data`)
            }

            // Build enrichment data
            const enrichmentData = {
                imdb_id: imdbId,
                tmdb_id: tmdbDetails?.id || null,
                title: imdbData.title,
                original_title: imdbData.title,
                description: imdbData.description,
                release_date: imdbData.release_date,
                runtime_minutes: imdbData.runtime_minutes,
                poster_path: tmdbDetails?.poster_path || null,
                backdrop_path: tmdbDetails?.backdrop_path || null,
                vote_average: tmdbDetails?.vote_average || null,
                vote_count: tmdbDetails?.vote_count || null,
                popularity: tmdbDetails?.popularity || null,
                genres: imdbData.genres || [],
                imdb_rating: imdbData.imdb_rating,
                imdb_votes: imdbData.imdb_votes,
                rated: imdbData.rated,
                director: imdbData.director,
                actors: imdbData.actors,
                country: imdbData.country,
                language: imdbData.language,
                media_type: imdbData.type === 'Movie' ? 'movie' : 'tv',
                confidence: 100, // Manual IMDB ID = 100% confidence
                actorMatch: false,
                source: 'imdb_direct'
            }

            logger.info(`✓ Enriched from IMDB: ${enrichmentData.title}`)
            return enrichmentData

        } catch (error) {
            logger.error(`Failed to enrich by IMDB ID ${imdbId}:`, error.message)
            return null
        }
    }

    /**
     * Main enrichment method
     * @param {Object} movie - Movie from database
     * @returns {Object|null} Enrichment data with confidence score
     */
    async enrichMovie(movie) {
        try {
            // Extract actor hints from channel pattern (now async)
            const actorHints = await this.extractActorHints(
                movie.youtube_video_title,
                movie.channel_title,
                movie.channel_id
            )

            logger.info(`Actor hints: title="${actorHints.title}", actors=[${actorHints.actors.join(', ')}], genre="${actorHints.genre}", year=${actorHints.year}, mediaHint=${actorHints.mediaHint}`)

            const publishYear = new Date(movie.published_at).getFullYear()

            // STEP 1: Try TMDB first
            const tmdbResults = await this.searchTMDBWithActors(
                actorHints.title,
                actorHints.actors,
                publishYear,
                actorHints.mediaHint
            )

            if (tmdbResults && tmdbResults.length > 0) {
                // Found in TMDB - use as primary source
                const topResult = tmdbResults[0]
                const confidence = await this.calculateConfidence(movie, topResult, actorHints)

                logger.info(`✓ TMDB match: ${topResult.media_type === 'movie' ? topResult.title : topResult.name} (confidence: ${confidence}%)`)

                // Get full TMDB details
                let tmdbDetails
                if (topResult.media_type === 'movie') {
                    tmdbDetails = await tmdbService.getMovieDetails(topResult.id)
                } else {
                    tmdbDetails = await tmdbService.getTVSeriesDetails(topResult.id)
                }

                // Supplement with IMDB data ONLY for missing fields
                let imdbData = null
                if (tmdbDetails.imdb_id) {
                    imdbData = await this.scrapeIMDBData(tmdbDetails.imdb_id)
                }

                // Merge: TMDB first, IMDB supplements missing fields
                const enrichmentData = {
                    tmdb_id: tmdbDetails.id,
                    imdb_id: tmdbDetails.imdb_id || imdbData?.imdb_id,
                    title: tmdbDetails.title || tmdbDetails.name,
                    original_title: tmdbDetails.original_title || tmdbDetails.original_name,
                    description: tmdbDetails.overview || imdbData?.description, // IMDB supplements if TMDB missing
                    release_date: tmdbDetails.release_date || tmdbDetails.first_air_date || imdbData?.release_date,
                    runtime_minutes: tmdbDetails.runtime || (Array.isArray(tmdbDetails.episode_run_time) ? tmdbDetails.episode_run_time[0] : null) || imdbData?.runtime_minutes,
                    poster_path: tmdbDetails.poster_path, // TMDB only
                    backdrop_path: tmdbDetails.backdrop_path, // TMDB only
                    vote_average: tmdbDetails.vote_average,
                    vote_count: tmdbDetails.vote_count,
                    popularity: tmdbDetails.popularity,
                    genres: tmdbDetails.genres || imdbData?.genres, // IMDB supplements if TMDB missing
                    imdb_rating: imdbData?.imdb_rating, // IMDB only field
                    imdb_votes: imdbData?.imdb_votes, // IMDB only field
                    rated: imdbData?.rated, // IMDB only field
                    director: imdbData?.director, // IMDB only field
                    actors: imdbData?.actors, // IMDB only field
                    country: imdbData?.country, // IMDB only field
                    language: imdbData?.language, // IMDB only field
                    media_type: topResult.media_type,
                    confidence: confidence,
                    actorMatch: actorHints.actors.length > 0,
                    source: 'tmdb_with_imdb'
                }

                return enrichmentData
            }

            // STEP 2: Not in TMDB, try OMDB with smart search + actor validation
            logger.warn(`No TMDB results for: ${actorHints.title}, trying OMDB with smart search...`)

            const omdbResult = await omdbService.searchWithValidation(
                actorHints.title,
                actorHints.actors,
                publishYear
            )

            if (omdbResult) {
                logger.info(`✓ Found in OMDB: "${omdbResult.title}" (${omdbResult.imdb_id}) - confidence: ${omdbResult.confidence}%`)

                // Try to get TMDB data for poster/backdrop if IMDB ID exists
                let tmdbDetails = null
                if (omdbResult.imdb_id) {
                    try {
                        tmdbDetails = await tmdbService.findByIMDBId(omdbResult.imdb_id)
                    } catch (error) {
                        logger.debug(`TMDB lookup failed for ${omdbResult.imdb_id}, using OMDB-only data`)
                    }
                }

                // Build enrichment data (OMDB primary, TMDB supplements posters)
                const enrichmentData = {
                    imdb_id: omdbResult.imdb_id,
                    tmdb_id: tmdbDetails?.id || null,
                    title: omdbResult.title,
                    original_title: omdbResult.title,
                    description: omdbResult.description,
                    release_date: omdbResult.release_date,
                    runtime_minutes: omdbResult.runtime_minutes,
                    poster_path: tmdbDetails?.poster_path || omdbResult.poster_path, // TMDB poster preferred
                    backdrop_path: tmdbDetails?.backdrop_path || null,
                    vote_average: tmdbDetails?.vote_average || null,
                    vote_count: tmdbDetails?.vote_count || null,
                    popularity: tmdbDetails?.popularity || null,
                    genres: omdbResult.genre ? omdbResult.genre.split(', ') : [],
                    imdb_rating: omdbResult.imdb_rating,
                    imdb_votes: omdbResult.imdb_votes,
                    rated: omdbResult.rated,
                    director: omdbResult.director,
                    actors: omdbResult.actors,
                    country: omdbResult.country,
                    language: omdbResult.language,
                    media_type: omdbResult.is_tv_show ? 'tv' : 'movie',
                    confidence: omdbResult.confidence,
                    actorMatch: omdbResult.actor_match,
                    source: 'omdb'
                }

                return enrichmentData
            }

            // STEP 3: Not in IMDB either, use cleaned YouTube data
            logger.warn(`No IMDB results either, using cleaned YouTube data for: ${actorHints.title}`)

            const enrichmentData = {
                tmdb_id: null,
                imdb_id: null,
                title: actorHints.title, // Use pattern-extracted clean title
                original_title: actorHints.title,
                description: movie.description,
                release_date: movie.published_at,
                runtime_minutes: movie.duration_minutes,
                poster_path: null,
                backdrop_path: null,
                vote_average: null,
                vote_count: null,
                popularity: null,
                genres: [], // Could extract from channel patterns in future
                imdb_rating: null,
                imdb_votes: null,
                rated: null,
                director: null,
                actors: actorHints.actors.join(', ') || null, // Use pattern-extracted actors
                country: null,
                language: null,
                media_type: actorHints.mediaHint || 'movie',
                confidence: 30, // Low confidence - no external validation
                actorMatch: actorHints.actors.length > 0,
                source: 'youtube_patterns'
            }

            return enrichmentData

        } catch (error) {
            logger.error(`Enhanced enrichment failed:`, error.message)
            return null
        }
    }
}

export const enhancedEnrichment = new EnhancedEnrichment()
