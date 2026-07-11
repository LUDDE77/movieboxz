import { tmdbService } from './tmdbService.js'
import { omdbService } from './omdbService.js'
import { enhancedEnrichment } from './enhancedEnrichment.js'
import { logger } from '../utils/logger.js'

/**
 * Selective Enrichment Service
 * Allows field-level control over enrichment
 *
 * Features:
 * - Field-level selection (poster, genres, plot, cast, ratings, release_date)
 * - Priority modes: poster-only, basic, full
 * - Preview mode (test without saving)
 * - Respects manual changes
 */
class SelectiveEnrichment {
    constructor() {
        // Field groups for priority modes
        this.fieldGroups = {
            'poster-only': ['poster_path'],
            'basic': ['poster_path', 'genres'],
            'standard': ['poster_path', 'genres', 'description', 'release_date'],
            'full': ['poster_path', 'genres', 'description', 'release_date', 'director', 'actors', 'ratings']
        }

        // Map of enrichment fields to database columns
        this.fieldMapping = {
            'poster': ['poster_path', 'backdrop_path'],
            'genres': ['category'], // genres stored in movie_genres table
            'plot': ['description'],
            'cast': ['director', 'actors'],
            'release_date': ['release_date', 'runtime_minutes'],
            'ratings': ['vote_average', 'vote_count', 'imdb_rating', 'imdb_votes', 'popularity', 'rated'],
            'metadata': ['original_title', 'language', 'country', 'is_tv_show']
        }
    }

    /**
     * Enrich movie with selective field control
     * @param {Object} movie - Movie object with title, actors, year
     * @param {Object} options - Enrichment options
     * @returns {Object} Enrichment result
     */
    async enrichSelective(movie, options = {}) {
        const {
            fields = null,              // Array of fields to enrich, or null for all
            priority = 'full',          // Priority mode: poster-only, basic, standard, full
            previewOnly = false,        // True to test enrichment without saving
            respectManual = true,       // Don't overwrite manual changes
            manualChanges = null,       // JSONB of manual edits
            preferTmdb = true           // Try TMDB first, then OMDB
        } = options

        logger.info(`Selective enrichment for "${movie.title}" (mode: ${priority}, preview: ${previewOnly})`)

        try {
            // Determine which fields to enrich
            const fieldsToEnrich = this._resolveFields(fields, priority)
            logger.debug(`Fields to enrich: ${fieldsToEnrich.join(', ')}`)

            // Get enrichment data from TMDB/OMDB
            const enrichmentData = await this._fetchEnrichmentData(movie, preferTmdb)

            if (!enrichmentData) {
                return {
                    success: false,
                    confidence: 30,
                    message: 'No enrichment data found',
                    preview: null
                }
            }

            // Build selective update (only requested fields)
            const update = this._buildSelectiveUpdate(enrichmentData, fieldsToEnrich, manualChanges, respectManual)

            // Return result
            return {
                success: Object.keys(update.data).length > 0,
                confidence: enrichmentData.confidence,
                source: enrichmentData.enrichment_source,
                preview: update.data,
                fieldsEnriched: update.fieldsEnriched,
                fieldsSkipped: update.fieldsSkipped,
                message: `Enriched ${update.fieldsEnriched.length} fields from ${enrichmentData.enrichment_source}`,
                metadata: {
                    tmdb_id: enrichmentData.tmdb_id,
                    imdb_id: enrichmentData.imdb_id,
                    title: enrichmentData.title,
                    actor_match: enrichmentData.actor_match,
                    matched_variation: enrichmentData.matched_variation
                }
            }

        } catch (error) {
            logger.error(`Selective enrichment failed for "${movie.title}":`, error.message)
            return {
                success: false,
                confidence: 0,
                message: `Enrichment error: ${error.message}`,
                preview: null
            }
        }
    }

    /**
     * Fetch enrichment data using enhanced enrichment service
     * This now uses pattern extraction and actor validation
     * @private
     */
    async _fetchEnrichmentData(movie, preferTmdb = true) {
        const enrichmentData = await this._fetchEnrichmentDataUnchecked(movie, preferTmdb)
        return this._applySanityChecks(enrichmentData, movie)
    }

    /**
     * Reality checks on a candidate match, using signals the matcher can't fake:
     * 1. TIMELINE VETO: a full movie cannot be uploaded to YouTube before the
     *    film exists — candidate release_date after the video upload (+30d
     *    slack) means the match is impossible (e.g. "Five (1951)" matched to
     *    Toy Story 5 because TMDB ranks upcoming franchise titles highly).
     * 2. YEAR GUARD: when the YouTube title itself states a year that is not
     *    part of the matched film's own title and disagrees with the match by
     *    more than a year, cap confidence below every auto-approve/low bar so
     *    the row goes to manual verification instead.
     */
    _applySanityChecks(enrichmentData, movie) {
        if (!enrichmentData || !enrichmentData.release_date) return enrichmentData

        const releaseTime = Date.parse(enrichmentData.release_date)
        if (Number.isNaN(releaseTime)) return enrichmentData

        const uploadTime = Date.parse(movie.published_at)
        if (!Number.isNaN(uploadTime) && releaseTime > uploadTime + 30 * 24 * 3600 * 1000) {
            logger.warn(`⛔ [SelectiveEnrichment] Timeline veto: "${enrichmentData.title}" (${enrichmentData.release_date}) released after the video upload (${movie.published_at}) — discarding match`)
            return null
        }

        const ytTitle = movie.youtube_video_title || ''
        const matchedTitle = (enrichmentData.title || '').toLowerCase()
        const releaseYear = new Date(releaseTime).getFullYear()
        const statedYears = [...ytTitle.matchAll(/\b(19[2-9][0-9]|20[0-2][0-9])\b/g)]
            .map(m => parseInt(m[1]))
            .filter(y => !matchedTitle.includes(String(y))) // years that are part of the film's own title don't count
        if (statedYears.length > 0 && !statedYears.some(y => Math.abs(y - releaseYear) <= 1)) {
            const capped = Math.min(enrichmentData.confidence ?? 0, 40)
            logger.warn(`⚠️ [SelectiveEnrichment] Year guard: video states ${statedYears.join('/')} but match "${enrichmentData.title}" is ${releaseYear} — capping confidence ${enrichmentData.confidence} -> ${capped}`)
            enrichmentData.confidence = capped
        }

        return enrichmentData
    }

    async _fetchEnrichmentDataUnchecked(movie, preferTmdb = true) {
        const { title, actors = [], year, youtube_video_title, channel_id, channel_title, published_at } = movie

        logger.info(`🔍 [SelectiveEnrichment] _fetchEnrichmentData called with:`, {
            title,
            actors,
            year,
            youtube_video_title,
            channel_id,
            channel_title,
            published_at,
            hasFullContext: !!(youtube_video_title && channel_id && published_at)
        })

        // If we have full movie context, use enhancedEnrichment for smart matching
        if (youtube_video_title && channel_id && published_at) {
            logger.info(`🎯 [SelectiveEnrichment] Using enhanced enrichment with full context...`)
            logger.info(`🎯 [SelectiveEnrichment] Calling enhancedEnrichment.enrichMovie with:`, {
                youtube_video_title,
                channel_id,
                channel_title: channel_title || 'Unknown',
                published_at
            })

            const enrichmentData = await enhancedEnrichment.enrichMovie({
                youtube_video_title,
                channel_id,
                channel_title: channel_title || 'Unknown',
                published_at: published_at || new Date().toISOString(),
                // Pass the staged title so a manually cleaned title (from title
                // repair) beats pattern extraction of the raw YouTube title
                title
            })

            logger.info(`🎯 [SelectiveEnrichment] Enhanced enrichment returned:`, {
                hasData: !!enrichmentData,
                title: enrichmentData?.title,
                confidence: enrichmentData?.confidence,
                source: enrichmentData?.source,
                tmdb_id: enrichmentData?.tmdb_id,
                imdb_id: enrichmentData?.imdb_id
            })

            if (enrichmentData) {
                logger.info(`✅ [SelectiveEnrichment] Enhanced enrichment SUCCESS: "${enrichmentData.title}" (confidence: ${enrichmentData.confidence}, source: ${enrichmentData.source})`)
                return enrichmentData
            } else {
                logger.warn(`❌ [SelectiveEnrichment] Enhanced enrichment returned NULL`)
            }
        } else {
            logger.warn(`⚠️ [SelectiveEnrichment] Missing full context - cannot use enhanced enrichment`, {
                hasYoutubeTitle: !!youtube_video_title,
                hasChannelId: !!channel_id,
                hasPublishedAt: !!published_at
            })
        }

        // Fallback to basic search if no full context or enhanced failed
        logger.debug('Falling back to basic TMDB/OMDB search...')

        // Try TMDB first (if preferred)
        if (preferTmdb) {
            logger.debug('Trying TMDB enrichment...')
            const tmdbData = await this._enrichWithTmdb(title, actors, year)
            if (tmdbData && tmdbData.confidence >= 70) {
                logger.info(`✅ TMDB enriched: "${tmdbData.title}" (confidence: ${tmdbData.confidence})`)
                return tmdbData
            }
        }

        // Fallback to OMDB
        logger.debug('Trying OMDB enrichment...')
        const omdbData = await this._enrichWithOmdb(title, actors, year)
        if (omdbData && omdbData.confidence >= 50) {
            logger.info(`✅ OMDB enriched: "${omdbData.title}" (confidence: ${omdbData.confidence})`)
            return omdbData
        }

        // Try TMDB if we haven't yet
        if (!preferTmdb) {
            logger.debug('Trying TMDB enrichment as fallback...')
            const tmdbData = await this._enrichWithTmdb(title, actors, year)
            if (tmdbData && tmdbData.confidence >= 50) {
                logger.info(`✅ TMDB enriched: "${tmdbData.title}" (confidence: ${tmdbData.confidence})`)
                return tmdbData
            }
        }

        logger.warn(`No enrichment data found for "${title}"`)
        return null
    }

    /**
     * Enrich with TMDB
     * @private
     */
    async _enrichWithTmdb(title, actors, year) {
        try {
            const results = await tmdbService.searchMovies(title, year)
            if (results.length === 0) return null

            // Get details for best match
            const movieDetails = await tmdbService.getMovieDetails(results[0].id)
            if (!movieDetails) return null

            // Calculate confidence
            const confidence = results.length === 1 ? 75 : 50

            return {
                ...movieDetails,
                confidence,
                actor_match: false,
                matched_variation: title,
                enrichment_source: 'tmdb'
            }
        } catch (error) {
            logger.error('TMDB enrichment error:', error.message)
            return null
        }
    }

    /**
     * Enrich with OMDB (with actor validation)
     * @private
     */
    async _enrichWithOmdb(title, actors, year) {
        try {
            const omdbData = await omdbService.searchWithValidation(title, actors, year)
            return omdbData
        } catch (error) {
            logger.error('OMDB enrichment error:', error.message)
            return null
        }
    }

    /**
     * Resolve which fields to enrich based on options
     * @private
     */
    _resolveFields(fields, priority) {
        // If specific fields provided, use them
        if (fields && Array.isArray(fields)) {
            return fields
        }

        // Otherwise use priority mode
        return this.fieldGroups[priority] || this.fieldGroups.full
    }

    /**
     * Build selective update object (only requested fields, respect manual changes)
     * @private
     */
    _buildSelectiveUpdate(enrichmentData, fieldsToEnrich, manualChanges, respectManual) {
        const update = {}
        const fieldsEnriched = []
        const fieldsSkipped = []

        // Check if field was manually changed
        const wasManuallyChanged = (field) => {
            if (!respectManual || !manualChanges) return false
            return manualChanges[field] !== undefined
        }

        // Poster fields
        if (fieldsToEnrich.includes('poster_path') || fieldsToEnrich.includes('poster')) {
            if (!wasManuallyChanged('poster_path') && enrichmentData.poster_path) {
                update.poster_path = enrichmentData.poster_path
                fieldsEnriched.push('poster_path')
            } else if (wasManuallyChanged('poster_path')) {
                fieldsSkipped.push('poster_path (manual)')
            }

            if (!wasManuallyChanged('backdrop_path') && enrichmentData.backdrop_path) {
                update.backdrop_path = enrichmentData.backdrop_path
                fieldsEnriched.push('backdrop_path')
            }
        }

        // Genres (note: genres stored in separate table, return for separate handling)
        if (fieldsToEnrich.includes('genres') && enrichmentData.genres) {
            update.genres = enrichmentData.genres
            fieldsEnriched.push('genres')
        }

        // Plot/Description
        if (fieldsToEnrich.includes('description') || fieldsToEnrich.includes('plot')) {
            if (!wasManuallyChanged('description') && enrichmentData.description) {
                update.description = enrichmentData.description
                fieldsEnriched.push('description')
            } else if (wasManuallyChanged('description')) {
                fieldsSkipped.push('description (manual)')
            }
        }

        // Release date & runtime
        if (fieldsToEnrich.includes('release_date')) {
            if (!wasManuallyChanged('release_date') && enrichmentData.release_date) {
                update.release_date = enrichmentData.release_date
                fieldsEnriched.push('release_date')
            } else if (wasManuallyChanged('release_date')) {
                fieldsSkipped.push('release_date (manual)')
            }

            if (!wasManuallyChanged('runtime_minutes') && enrichmentData.runtime_minutes) {
                update.runtime_minutes = enrichmentData.runtime_minutes
                fieldsEnriched.push('runtime_minutes')
            }
        }

        // Cast & Director
        if (fieldsToEnrich.includes('director') || fieldsToEnrich.includes('cast')) {
            if (!wasManuallyChanged('director') && enrichmentData.director) {
                update.director = enrichmentData.director
                fieldsEnriched.push('director')
            } else if (wasManuallyChanged('director')) {
                fieldsSkipped.push('director (manual)')
            }

            if (!wasManuallyChanged('actors') && enrichmentData.actors) {
                update.actors = enrichmentData.actors
                fieldsEnriched.push('actors')
            } else if (wasManuallyChanged('actors')) {
                fieldsSkipped.push('actors (manual)')
            }
        }

        // Ratings
        if (fieldsToEnrich.includes('ratings')) {
            if (enrichmentData.vote_average) {
                update.vote_average = enrichmentData.vote_average
                fieldsEnriched.push('vote_average')
            }
            if (enrichmentData.vote_count) {
                update.vote_count = enrichmentData.vote_count
                fieldsEnriched.push('vote_count')
            }
            if (enrichmentData.imdb_rating) {
                update.imdb_rating = enrichmentData.imdb_rating
                fieldsEnriched.push('imdb_rating')
            }
            if (enrichmentData.imdb_votes) {
                update.imdb_votes = enrichmentData.imdb_votes
                fieldsEnriched.push('imdb_votes')
            }
            if (enrichmentData.popularity) {
                update.popularity = enrichmentData.popularity
                fieldsEnriched.push('popularity')
            }
            if (enrichmentData.rated) {
                update.rated = enrichmentData.rated
                fieldsEnriched.push('rated')
            }
        }

        // Metadata
        if (fieldsToEnrich.includes('metadata')) {
            if (enrichmentData.original_title) {
                update.original_title = enrichmentData.original_title
                fieldsEnriched.push('original_title')
            }
            if (enrichmentData.language) {
                update.language = enrichmentData.language
                fieldsEnriched.push('language')
            }
            if (enrichmentData.country) {
                update.country = enrichmentData.country
                fieldsEnriched.push('country')
            }
            if (enrichmentData.is_tv_show !== undefined) {
                update.is_tv_show = enrichmentData.is_tv_show
                fieldsEnriched.push('is_tv_show')
            }
        }

        // Always include enrichment tracking
        update.enrichment_source = enrichmentData.enrichment_source
        update.enrichment_confidence = enrichmentData.confidence
        update.tmdb_id = enrichmentData.tmdb_id || null
        update.imdb_id = enrichmentData.imdb_id || null

        return {
            data: update,
            fieldsEnriched,
            fieldsSkipped
        }
    }

    /**
     * Quick enrichment modes (shortcuts)
     */
    async enrichPosterOnly(movie, options = {}) {
        return this.enrichSelective(movie, { ...options, priority: 'poster-only' })
    }

    async enrichBasic(movie, options = {}) {
        return this.enrichSelective(movie, { ...options, priority: 'basic' })
    }

    async enrichStandard(movie, options = {}) {
        return this.enrichSelective(movie, { ...options, priority: 'standard' })
    }

    async enrichFull(movie, options = {}) {
        return this.enrichSelective(movie, { ...options, priority: 'full' })
    }
}

export const selectiveEnrichment = new SelectiveEnrichment()
export default selectiveEnrichment
