import { tmdbService } from './tmdbService.js'
import { logger } from '../utils/logger.js'
import axios from 'axios'

class EnhancedEnrichment {
    constructor() {
        // Channel-specific title patterns
        this.channelPatterns = {
            'The Midnight Screening': {
                pattern: /^(.+?)\s*FULL MOVIE\s*\|\s*(?:[\w\s]+Movies?)\s*\|\s*(.+?)\s*\|\s*The Midnight Screening$/i,
                titleGroup: 1,
                actorGroup: 2
            },
            'UC6A_LC-A5NVJ2vw9A0OjCug': {
                pattern: /^(.+?)\s*FULL MOVIE\s*\|\s*(?:[\w\s]+Movies?)\s*\|\s*(.+?)\s*\|\s*The Midnight Screening$/i,
                titleGroup: 1,
                actorGroup: 2
            }
        }

        this.confidenceThresholds = {
            autoAccept: 70,
            manualReview: 50,
            reject: 50
        }
    }

    /**
     * Extract actor hints from YouTube title
     * @param {string} youtubeTitle - Full YouTube video title
     * @param {string} channelTitle - Channel name
     * @param {string} channelId - Channel ID
     * @returns {Object} { title, actors: [...], mediaHint }
     */
    extractActorHints(youtubeTitle, channelTitle, channelId) {
        const result = {
            title: youtubeTitle,
            actors: [],
            mediaHint: null
        }

        // Try channel-specific patterns
        const pattern = this.channelPatterns[channelTitle] || this.channelPatterns[channelId]

        if (pattern) {
            const match = youtubeTitle.match(pattern.pattern)
            if (match) {
                result.title = match[pattern.titleGroup].trim()
                const actorText = match[pattern.actorGroup].trim()

                // Split actor names by common separators
                result.actors = actorText
                    .split(/[,&]|\s+and\s+/i)
                    .map(name => name.trim())
                    .filter(name => name.length > 0)

                logger.debug(`Extracted title: "${result.title}" with actors: [${result.actors.join(', ')}]`)
            }
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

            const actorResults = await tmdbService.searchMulti(actorQuery)
            results.push(...actorResults)
        }

        // Strategy 2: Fallback to title-only search
        if (results.length === 0) {
            logger.debug(`Strategy 2: Fallback to title-only: "${title}"`)
            const titleResults = await tmdbService.searchMulti(title)
            results.push(...titleResults)
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
     * Main enrichment method
     * @param {Object} movie - Movie from database
     * @returns {Object|null} Enrichment data with confidence score
     */
    async enrichMovie(movie) {
        try {
            // Extract actor hints
            const actorHints = this.extractActorHints(
                movie.youtube_video_title,
                movie.channel_title,
                movie.channel_id
            )

            logger.info(`Actor hints: title="${actorHints.title}", actors=[${actorHints.actors.join(', ')}], mediaHint=${actorHints.mediaHint}`)

            // Search TMDB with actor context
            const publishYear = new Date(movie.published_at).getFullYear()
            const tmdbResults = await this.searchTMDBWithActors(
                actorHints.title,
                actorHints.actors,
                publishYear,
                actorHints.mediaHint
            )

            if (!tmdbResults || tmdbResults.length === 0) {
                logger.warn(`No TMDB results for: ${actorHints.title}`)
                return null
            }

            // Calculate confidence for top result
            const topResult = tmdbResults[0]
            const confidence = await this.calculateConfidence(movie, topResult, actorHints)

            logger.info(`Top match: ${topResult.media_type === 'movie' ? topResult.title : topResult.name} (${topResult.media_type}) - Confidence: ${confidence}%`)

            // Get full details from TMDB
            let tmdbDetails
            if (topResult.media_type === 'movie') {
                tmdbDetails = await tmdbService.getMovieDetails(topResult.id)
            } else {
                tmdbDetails = await tmdbService.getTVSeriesDetails(topResult.id)
            }

            // Scrape IMDB if available
            let imdbData = null
            if (tmdbDetails.imdb_id) {
                imdbData = await this.scrapeIMDBData(tmdbDetails.imdb_id)
            }

            // Merge data sources
            const enrichmentData = {
                tmdb_id: tmdbDetails.id,
                imdb_id: tmdbDetails.imdb_id || imdbData?.imdb_id,
                title: tmdbDetails.title || tmdbDetails.name,
                original_title: tmdbDetails.original_title || tmdbDetails.original_name,
                description: tmdbDetails.overview || imdbData?.description,
                release_date: tmdbDetails.release_date || tmdbDetails.first_air_date || imdbData?.release_date,
                runtime_minutes: tmdbDetails.runtime || (Array.isArray(tmdbDetails.episode_run_time) ? tmdbDetails.episode_run_time[0] : null) || imdbData?.runtime_minutes,
                poster_path: tmdbDetails.poster_path,
                backdrop_path: tmdbDetails.backdrop_path,
                vote_average: tmdbDetails.vote_average,
                vote_count: tmdbDetails.vote_count,
                popularity: tmdbDetails.popularity,
                genres: tmdbDetails.genres,
                imdb_rating: imdbData?.imdb_rating,
                imdb_votes: imdbData?.imdb_votes,
                rated: imdbData?.rated,
                director: imdbData?.director,
                actors: imdbData?.actors,
                country: imdbData?.country,
                language: imdbData?.language,
                media_type: topResult.media_type,
                confidence: confidence,
                actorMatch: actorHints.actors.length > 0,
                source: 'enhanced_enrichment'
            }

            return enrichmentData

        } catch (error) {
            logger.error(`Enhanced enrichment failed:`, error.message)
            return null
        }
    }
}

export const enhancedEnrichment = new EnhancedEnrichment()
