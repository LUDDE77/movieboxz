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
     * Search TMDB by title, then rank by actors and year
     * @param {string} title - Cleaned movie/show title
     * @param {Array<string>} actorHints - Actor names from title
     * @param {number} publishYear - Year from YouTube publish date
     * @param {string} mediaHint - 'movie' or 'tv' hint
     * @param {number} extractedYear - Year extracted from title pattern (if any)
     * @returns {Array} TMDB search results ranked by relevance
     */
    async searchTMDBWithActors(title, actorHints, publishYear, mediaHint, extractedYear = null) {
        logger.debug(`🔍 Searching TMDB by title: "${title}"`)

        // Step 1: Search by TITLE ONLY (no year filter to get all matches)
        const movieResults = await tmdbService.searchMovies(title, null)
        const tvResults = await tmdbService.searchTVSeries(title, null)

        // Add media_type to each result
        movieResults.forEach(r => r.media_type = 'movie')
        tvResults.forEach(r => r.media_type = 'tv')

        const allResults = [...movieResults, ...tvResults]

        if (allResults.length === 0) {
            logger.debug(`No TMDB results found for: "${title}"`)
            return []
        }

        logger.debug(`Found ${allResults.length} TMDB results, now ranking by actors/year...`)

        // Step 2: Score each result based on actors and year
        const scoredResults = []
        for (const result of allResults) {
            const score = await this.scoreResult(result, actorHints, publishYear, extractedYear, mediaHint)
            scoredResults.push({ ...result, relevanceScore: score })
        }

        // Step 3: Sort by relevance score (highest first)
        scoredResults.sort((a, b) => b.relevanceScore - a.relevanceScore)

        logger.debug(`Top 3 results:`, scoredResults.slice(0, 3).map(r => ({
            title: r.title || r.name,
            year: r.release_date || r.first_air_date,
            score: r.relevanceScore,
            media_type: r.media_type
        })))

        return scoredResults
    }

    /**
     * Score a TMDB result based on actors, year, and media type
     * @param {Object} result - TMDB search result
     * @param {Array<string>} actorHints - Extracted actor names
     * @param {number} publishYear - YouTube publish year
     * @param {number} extractedYear - Year extracted from title pattern
     * @param {string} mediaHint - 'movie' or 'tv' hint
     * @returns {number} Score 0-100
     */
    async scoreResult(result, actorHints, publishYear, extractedYear, mediaHint) {
        let score = 0

        // 1. Actor match (40 points)
        if (actorHints && actorHints.length > 0) {
            const actorMatch = await this.validateActorMatch(result.id, result.media_type, { actors: actorHints })
            if (actorMatch) {
                score += 40
                logger.debug(`  ✓ Actor match found (+40 points)`)
            }
        }

        // 2. Year match (30 points)
        const resultYear = result.media_type === 'movie'
            ? new Date(result.release_date).getFullYear()
            : new Date(result.first_air_date).getFullYear()

        // Prefer extracted year over publish year (pattern year is more reliable)
        const targetYear = extractedYear || publishYear

        if (!isNaN(resultYear) && !isNaN(targetYear)) {
            const yearDiff = Math.abs(resultYear - targetYear)
            if (yearDiff === 0) {
                score += 30
                logger.debug(`  ✓ Exact year match: ${resultYear} (+30 points)`)
            } else if (yearDiff <= 1) {
                score += 20
                logger.debug(`  ≈ Close year match: ${resultYear} vs ${targetYear} (+20 points)`)
            } else if (yearDiff <= 3) {
                score += 10
                logger.debug(`  ~ Approximate year: ${resultYear} vs ${targetYear} (+10 points)`)
            }
        }

        // 3. Media type match (20 points)
        if (mediaHint === result.media_type) {
            score += 20
            logger.debug(`  ✓ Media type match: ${result.media_type} (+20 points)`)
        }

        // 4. Popularity bonus (10 points) - prefer popular results when ambiguous
        const popularity = result.popularity || 0
        if (popularity > 50) {
            score += 10
        } else if (popularity > 20) {
            score += 5
        }

        return score
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

            // Try OMDB first (reliable API, works on Railway)
            let omdbData = null
            try {
                omdbData = await omdbService.getByImdbId(imdbId)
                if (omdbData) {
                    logger.info(`✓ Got OMDB data for ${imdbId}: ${omdbData.title}`)
                }
            } catch (error) {
                logger.debug(`OMDB lookup failed for ${imdbId}: ${error.message}`)
            }

            // Fall back to scraping IMDB directly (works locally, may fail on Railway)
            let imdbData = null
            if (!omdbData) {
                imdbData = await this.scrapeIMDBData(imdbId)
                if (!imdbData) {
                    logger.warn(`Failed to get data for ${imdbId} from OMDB or IMDB scrape`)
                    return null
                }
            }

            // Try to get TMDB data for posters/backdrops
            let tmdbDetails = null
            try {
                const tmdbResults = await tmdbService.findByIMDBId(imdbId)
                if (tmdbResults) {
                    tmdbDetails = tmdbResults
                }
            } catch (error) {
                logger.debug(`TMDB lookup failed for ${imdbId}, using OMDB/IMDB-only data`)
            }

            // Parse genres: OMDB returns comma-separated string, IMDB scrape returns array
            let genres = []
            if (omdbData?.genre) {
                genres = omdbData.genre.split(',').map(g => g.trim()).filter(Boolean)
            } else if (imdbData?.genres) {
                genres = Array.isArray(imdbData.genres) ? imdbData.genres : [imdbData.genres]
            }

            const source = omdbData ? 'omdb_direct' : 'imdb_scrape'
            const title = omdbData?.title || imdbData?.title
            const enrichmentData = {
                imdb_id: imdbId,
                tmdb_id: tmdbDetails?.id || null,
                title,
                original_title: title,
                description: omdbData?.description || imdbData?.description,
                release_date: omdbData?.release_date || imdbData?.release_date,
                runtime_minutes: omdbData?.runtime_minutes || imdbData?.runtime_minutes,
                poster_path: tmdbDetails?.poster_path || omdbData?.poster_path || null,
                backdrop_path: tmdbDetails?.backdrop_path || null,
                vote_average: tmdbDetails?.vote_average || null,
                vote_count: tmdbDetails?.vote_count || null,
                popularity: tmdbDetails?.popularity || null,
                genres,
                imdb_rating: omdbData?.imdb_rating || imdbData?.imdb_rating,
                imdb_votes: omdbData?.imdb_votes || imdbData?.imdb_votes,
                rated: omdbData?.rated || imdbData?.rated,
                director: omdbData?.director || imdbData?.director,
                actors: omdbData?.actors || imdbData?.actors,
                country: omdbData?.country || imdbData?.country,
                language: omdbData?.language || imdbData?.language,
                media_type: (omdbData?.is_tv_show || imdbData?.type !== 'Movie') ? 'tv' : 'movie',
                confidence: 100, // Manual IMDB ID = 100% confidence
                actorMatch: false,
                source
            }

            logger.info(`✓ Enriched from ${source}: ${enrichmentData.title}`)
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
            logger.info(`🎬 [EnhancedEnrichment] ========== STARTING ENRICHMENT ==========`)
            logger.info(`🎬 [EnhancedEnrichment] Input movie:`, {
                youtube_video_title: movie.youtube_video_title,
                channel_title: movie.channel_title,
                channel_id: movie.channel_id,
                published_at: movie.published_at
            })

            // If a specific IMDB ID is forced, use it directly
            if (movie.imdbId) {
                logger.info(`🎬 [EnhancedEnrichment] Forced IMDB ID provided: ${movie.imdbId} — using enrichByIMDBId()`)
                return await this.enrichByIMDBId(movie.imdbId)
            }

            // Extract actor hints from channel pattern (now async)
            logger.info(`🎬 [EnhancedEnrichment] Step 1: Extracting actor hints from pattern...`)
            const actorHints = await this.extractActorHints(
                movie.youtube_video_title,
                movie.channel_title,
                movie.channel_id
            )

            logger.info(`🎬 [EnhancedEnrichment] Pattern extraction result:`, {
                title: actorHints.title,
                actors: actorHints.actors,
                genre: actorHints.genre,
                year: actorHints.year,
                mediaHint: actorHints.mediaHint
            })

            const publishYear = new Date(movie.published_at).getFullYear()
            logger.info(`🎬 [EnhancedEnrichment] Publish year: ${publishYear}`)

            // STEP 1: Try TMDB first
            logger.info(`🎬 [EnhancedEnrichment] Step 2: Searching TMDB...`)
            const tmdbResults = await this.searchTMDBWithActors(
                actorHints.title,
                actorHints.actors,
                publishYear,
                actorHints.mediaHint,
                actorHints.year  // Pass extracted year for better matching
            )

            logger.info(`🎬 [EnhancedEnrichment] TMDB search results:`, {
                resultCount: tmdbResults?.length || 0,
                topResult: tmdbResults?.[0] ? {
                    id: tmdbResults[0].id,
                    title: tmdbResults[0].title || tmdbResults[0].name,
                    media_type: tmdbResults[0].media_type
                } : null
            })

            if (tmdbResults && tmdbResults.length > 0) {
                // Found in TMDB - use as primary source
                const topResult = tmdbResults[0]
                logger.info(`🎬 [EnhancedEnrichment] Calculating confidence for TMDB match...`)
                const confidence = await this.calculateConfidence(movie, topResult, actorHints)

                logger.info(`✅ [EnhancedEnrichment] TMDB match: ${topResult.media_type === 'movie' ? topResult.title : topResult.name} (confidence: ${confidence}%)`)

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
            logger.warn(`⚠️ [EnhancedEnrichment] No TMDB results for: ${actorHints.title}`)
            logger.info(`🎬 [EnhancedEnrichment] Step 3: Trying OMDB with smart search + actor validation...`)

            const omdbResult = await omdbService.searchWithValidation(
                actorHints.title,
                actorHints.actors,
                publishYear
            )

            logger.info(`🎬 [EnhancedEnrichment] OMDB search result:`, {
                hasResult: !!omdbResult,
                title: omdbResult?.title,
                imdb_id: omdbResult?.imdb_id,
                confidence: omdbResult?.confidence,
                actor_match: omdbResult?.actor_match
            })

            if (omdbResult) {
                logger.info(`✅ [EnhancedEnrichment] Found in OMDB: "${omdbResult.title}" (${omdbResult.imdb_id}) - confidence: ${omdbResult.confidence}%`)

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
            logger.warn(`⚠️ [EnhancedEnrichment] No IMDB results either`)
            logger.info(`🎬 [EnhancedEnrichment] Step 4: Using cleaned YouTube data (pattern-extracted) as fallback...`)

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

            logger.info(`🎬 [EnhancedEnrichment] Returning YouTube patterns fallback:`, {
                title: enrichmentData.title,
                actors: enrichmentData.actors,
                confidence: enrichmentData.confidence,
                source: enrichmentData.source
            })
            logger.info(`🎬 [EnhancedEnrichment] ========== ENRICHMENT COMPLETE ==========`)

            return enrichmentData

        } catch (error) {
            logger.error(`❌ [EnhancedEnrichment] Enhanced enrichment failed:`, {
                error: error.message,
                stack: error.stack
            })
            logger.info(`🎬 [EnhancedEnrichment] ========== ENRICHMENT FAILED ==========`)
            return null
        }
    }
}

export const enhancedEnrichment = new EnhancedEnrichment()
