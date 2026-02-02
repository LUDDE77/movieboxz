import axios from 'axios'
import { logger } from '../utils/logger.js'

class OMDbService {
    constructor() {
        this.apiKey = process.env.OMDB_API_KEY
        this.baseUrl = 'http://www.omdbapi.com'

        if (!this.apiKey) {
            logger.warn('OMDb API key not configured. Set OMDB_API_KEY environment variable.')
        }
    }

    /**
     * Search by title
     * @param {string} title - Movie/TV show title
     * @param {string} year - Optional release year
     * @param {string} type - Optional: 'movie', 'series', or 'episode'
     * @returns {Object|null} OMDb data or null if not found
     */
    async searchByTitle(title, year = null, type = null) {
        if (!this.apiKey) {
            logger.warn('OMDb API key not configured, skipping enrichment')
            return null
        }

        try {
            const params = {
                apikey: this.apiKey,
                t: title,
                plot: 'full'
            }

            if (year) params.y = year
            if (type) params.type = type

            logger.debug(`OMDb: Searching for "${title}"${year ? ` (${year})` : ''}`)

            const response = await axios.get(this.baseUrl, { params })

            if (response.data.Response === 'False') {
                logger.debug(`OMDb: "${title}" not found (${response.data.Error})`)
                return null
            }

            logger.info(`✅ OMDb found: "${response.data.Title}" (${response.data.imdbID})`)
            return this.transformResponse(response.data)

        } catch (error) {
            logger.error(`OMDb API error for "${title}":`, error.message)
            return null
        }
    }

    /**
     * Get by IMDB ID
     * @param {string} imdbId - IMDB ID (e.g., 'tt1117667')
     * @returns {Object|null} OMDb data or null if not found
     */
    async getByImdbId(imdbId) {
        if (!this.apiKey) {
            logger.warn('OMDb API key not configured, skipping enrichment')
            return null
        }

        try {
            const response = await axios.get(this.baseUrl, {
                params: {
                    apikey: this.apiKey,
                    i: imdbId,
                    plot: 'full'
                }
            })

            if (response.data.Response === 'False') {
                return null
            }

            return this.transformResponse(response.data)

        } catch (error) {
            logger.error(`OMDb API error for IMDB ID "${imdbId}":`, error.message)
            return null
        }
    }

    /**
     * Transform OMDb response to our database format
     */
    transformResponse(omdbData) {
        return {
            // Core identifiers
            imdb_id: omdbData.imdbID,

            // Metadata
            title: omdbData.Title,
            release_date: this.parseReleaseDate(omdbData.Released),
            runtime_minutes: this.parseRuntime(omdbData.Runtime),

            // Content
            description: omdbData.Plot !== 'N/A' ? omdbData.Plot : null,
            poster_path: this.transformPosterUrl(omdbData.Poster),

            // Ratings
            imdb_rating: omdbData.imdbRating !== 'N/A' ? parseFloat(omdbData.imdbRating) : null,
            imdb_votes: omdbData.imdbVotes !== 'N/A' ? parseInt(omdbData.imdbVotes.replace(/,/g, '')) : null,

            // Additional info
            rated: omdbData.Rated !== 'N/A' ? omdbData.Rated : null,
            genre: omdbData.Genre !== 'N/A' ? omdbData.Genre : null,
            director: omdbData.Director !== 'N/A' ? omdbData.Director : null,
            actors: omdbData.Actors !== 'N/A' ? omdbData.Actors : null,
            language: omdbData.Language !== 'N/A' ? omdbData.Language : null,
            country: omdbData.Country !== 'N/A' ? omdbData.Country : null,

            // Type detection
            is_tv_show: omdbData.Type === 'series' || omdbData.Type === 'episode',

            // Source tracking
            enrichment_source: 'omdb',

            // Raw OMDb data for reference
            omdb_type: omdbData.Type,
            omdb_raw: omdbData
        }
    }

    /**
     * Transform OMDb poster URL
     * OMDb returns full IMDB URLs, we just use them as-is
     */
    transformPosterUrl(posterUrl) {
        if (!posterUrl || posterUrl === 'N/A') {
            return null
        }
        return posterUrl
    }

    /**
     * Parse runtime string like "178 min" to number
     */
    parseRuntime(runtime) {
        if (!runtime || runtime === 'N/A') return null
        const match = runtime.match(/(\d+)/)
        return match ? parseInt(match[1]) : null
    }

    /**
     * Parse release date string
     */
    parseReleaseDate(released) {
        if (!released || released === 'N/A') return null

        try {
            // OMDb returns dates like "08 Feb 2008"
            const date = new Date(released)
            if (isNaN(date.getTime())) return null
            return date.toISOString().split('T')[0] // Return YYYY-MM-DD
        } catch (error) {
            return null
        }
    }

    /**
     * Extract year from title like "Movie Title (2008)"
     */
    extractYearFromTitle(title) {
        const match = title.match(/\((\d{4})\)/)
        return match ? match[1] : null
    }

    /**
     * Search for multiple results (returns array)
     * @param {string} title - Movie title
     * @param {number} year - Optional year
     * @returns {Promise<Array>} Array of search results
     */
    async searchMultiple(title, year = null) {
        if (!this.apiKey) {
            logger.warn('OMDb API key not configured')
            return []
        }

        try {
            const params = {
                apikey: this.apiKey,
                s: title,  // 's' = search (returns multiple results)
                type: 'movie'
            }

            if (year) params.y = year

            logger.debug(`OMDb multi-search: "${title}"${year ? ` (${year})` : ''}`)

            const response = await axios.get(this.baseUrl, { params })

            if (response.data.Response === 'False') {
                logger.debug(`OMDb: No results for "${title}"`)
                return []
            }

            const results = response.data.Search || []
            logger.debug(`OMDb: Found ${results.length} results for "${title}"`)

            return results.map(movie => ({
                imdb_id: movie.imdbID,
                title: movie.Title,
                year: movie.Year,
                type: movie.Type,
                poster: movie.Poster !== 'N/A' ? movie.Poster : null
            }))

        } catch (error) {
            logger.error(`OMDb multi-search error:`, error.message)
            return []
        }
    }

    /**
     * Generate title variations for searching
     * @param {string} title - Original title
     * @returns {Array<string>} Title variations
     */
    generateTitleVariations(title) {
        const variations = [title]

        // Remove "The" from beginning
        if (title.startsWith('The ')) {
            variations.push(title.substring(4))
        }

        // Remove "A" from beginning
        if (title.startsWith('A ')) {
            variations.push(title.substring(2))
        }

        // Remove "An" from beginning
        if (title.startsWith('An ')) {
            variations.push(title.substring(3))
        }

        // Remove colons and special characters
        const noColons = title.replace(/[:]/g, '')
        if (noColons !== title) {
            variations.push(noColons)
        }

        // Remove hyphens
        const noHyphens = title.replace(/[-]/g, ' ')
        if (noHyphens !== title) {
            variations.push(noHyphens)
        }

        // Remove special characters completely
        const noSpecialChars = title.replace(/[^\w\s]/g, '')
        if (noSpecialChars !== title) {
            variations.push(noSpecialChars)
        }

        // Normalize spaces
        const normalized = title.replace(/\s+/g, ' ').trim()
        if (normalized !== title) {
            variations.push(normalized)
        }

        // Return unique variations
        return [...new Set(variations)]
    }

    /**
     * Validate if expected actors are in the movie cast
     * @param {string} movieActors - Comma-separated actor list from OMDb
     * @param {Array<string>} expectedActors - Actors to look for
     * @returns {boolean} True if at least one actor matches
     */
    validateActors(movieActors, expectedActors) {
        if (!movieActors || expectedActors.length === 0) {
            return false
        }

        const movieActorsList = movieActors.toLowerCase().split(',').map(a => a.trim())

        for (const expectedActor of expectedActors) {
            const expected = expectedActor.toLowerCase().trim()

            // Check for partial matches in both directions
            const match = movieActorsList.some(actor =>
                actor.includes(expected) || expected.includes(actor)
            )

            if (match) {
                logger.debug(`✓ Actor match: ${expectedActor} found in cast`)
                return true
            }
        }

        logger.debug(`✗ No actor matches found`)
        return false
    }

    /**
     * Smart search with title variations and actor validation
     * @param {string} title - Movie title
     * @param {Array<string>} actors - Expected actors for validation
     * @param {number} year - Optional year
     * @returns {Promise<Object|null>} Best matching movie or null
     */
    async searchWithValidation(title, actors = [], year = null) {
        try {
            const variations = this.generateTitleVariations(title)
            logger.info(`Trying ${variations.length} title variations for: "${title}"`)

            for (const variation of variations) {
                logger.debug(`→ Trying variation: "${variation}"`)

                const results = await this.searchMultiple(variation, year)

                if (results.length === 0) {
                    continue
                }

                // Single result - fetch details and validate
                if (results.length === 1) {
                    logger.debug(`Single result found, fetching details...`)
                    const details = await this.getByImdbId(results[0].imdb_id)

                    if (details) {
                        const actorMatch = actors.length > 0 ?
                            this.validateActors(details.actors, actors) : false

                        return {
                            ...details,
                            confidence: actorMatch ? 100 : 75,
                            actor_match: actorMatch,
                            matched_variation: variation,
                            enrichment_source: 'omdb'
                        }
                    }
                }

                // Multiple results - validate against actors
                if (results.length > 1) {
                    logger.debug(`Multiple results (${results.length}), validating...`)

                    // If we have actors, try to find exact match
                    if (actors.length > 0) {
                        for (const result of results) {
                            const details = await this.getByImdbId(result.imdb_id)

                            if (details && this.validateActors(details.actors, actors)) {
                                logger.info(`✓ Found match with actor validation: ${details.title}`)
                                return {
                                    ...details,
                                    confidence: 100,
                                    actor_match: true,
                                    matched_variation: variation,
                                    enrichment_source: 'omdb'
                                }
                            }
                        }
                    }

                    // No actor match, return first result with lower confidence
                    logger.debug(`No actor match, returning first result`)
                    const details = await this.getByImdbId(results[0].imdb_id)

                    if (details) {
                        return {
                            ...details,
                            confidence: 50,  // Lower confidence - no actor validation
                            actor_match: false,
                            matched_variation: variation,
                            enrichment_source: 'omdb'
                        }
                    }
                }
            }

            logger.warn(`No OMDb results for "${title}" after trying ${variations.length} variations`)
            return null

        } catch (error) {
            logger.error(`OMDb search with validation failed:`, error.message)
            return null
        }
    }
}

export const omdbService = new OMDbService()
export default omdbService
