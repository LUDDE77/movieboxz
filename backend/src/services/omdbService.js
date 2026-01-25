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
}

export const omdbService = new OMDbService()
export default omdbService
