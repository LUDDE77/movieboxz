import { youtubeService } from './youtubeService.js'
import { tmdbService } from './tmdbService.js'
import { omdbService } from './omdbService.js'
import { dbOperations } from '../config/database.js'
import { logger } from '../utils/logger.js'
import { channelPatternDetector } from './channelPatternDetector.js'
import duplicateDetector from './duplicateDetector.js'

class MovieCurator {
    constructor() {
        // Curated channels known for hosting classic/public domain movies
        this.curatedChannels = [
            {
                id: 'UCf0O8RZF2enk6zy4YEUAKsA',
                name: 'Public Domain Movies',
                description: 'Classic public domain movies'
            },
            {
                id: 'UCEbaXJqQU5Cug9SHXF3gzqQ',
                name: 'Classic Cinema',
                description: 'Restored classic films'
            },
            {
                id: 'UChBnVdgIeJWG_mQWOQydPdQ',
                name: 'Free Movies Cinema',
                description: 'Free classic movies'
            }
        ]

        // Keywords that indicate full movies
        this.movieKeywords = [
            'full movie',
            'complete film',
            'full film',
            'feature film',
            'classic movie',
            'vintage movie',
            'public domain movie',
            'cinema classic',
            'movie',
            'film'
        ]

        // Keywords that exclude content
        this.excludeKeywords = [
            'trailer',
            'clip',
            'scene',
            'making of',
            'behind the scenes',
            'interview',
            'review',
            'analysis',
            'reaction',
            'part 1',
            'part 2',
            'episode',
            'preview',
            'teaser',
            'deleted scene'
        ]

        // Minimum requirements for movies
        this.requirements = {
            minDurationMinutes: parseInt(process.env.MIN_MOVIE_DURATION_MINUTES) || 60,
            maxDurationMinutes: parseInt(process.env.MAX_MOVIE_DURATION_MINUTES) || 360,
            minViewCount: parseInt(process.env.MIN_VIEW_COUNT) || 0  // No view count requirement
        }
    }

    // =============================================================================
    // MAIN CURATION FUNCTIONS
    // =============================================================================

    async curateAllChannels() {
        logger.info('🎬 Starting full channel curation process')

        const results = {
            channelsProcessed: 0,
            moviesFound: 0,
            moviesAdded: 0,
            errors: []
        }

        for (const channelInfo of this.curatedChannels) {
            try {
                logger.info(`Processing channel: ${channelInfo.name} (${channelInfo.id})`)

                const channelResults = await this.curateChannelMovies(channelInfo.id)

                results.channelsProcessed++
                results.moviesFound += channelResults.moviesFound
                results.moviesAdded += channelResults.moviesAdded

                logger.info(`Channel ${channelInfo.name} completed: ${channelResults.moviesAdded}/${channelResults.moviesFound} movies added`)

            } catch (error) {
                logger.error(`Error processing channel ${channelInfo.name}:`, error.message)
                results.errors.push({
                    channel: channelInfo.name,
                    error: error.message
                })
            }
        }

        logger.info(`🎉 Curation completed: ${results.moviesAdded} movies added from ${results.channelsProcessed} channels`)
        return results
    }

    async curateChannelMovies(channelId, options = {}) {
        const { jobId = null, forceReenrich = false } = options

        logger.info(`🔍 Curating movies from channel: ${channelId}${jobId ? ` (Job: ${jobId})` : ''}${forceReenrich ? ' [FORCE RE-ENRICH MODE]' : ''}`)

        const results = {
            moviesFound: 0,
            moviesAdded: 0,
            moviesSkipped: 0,
            moviesUpdated: 0,
            errors: [],
            channelInfo: null
        }

        try {
            // Start job if provided
            if (jobId) {
                await dbOperations.startCurationJob(jobId)
            }

            // Ensure channel exists in database
            const channel = await this.ensureChannelExists(channelId)
            results.channelInfo = channel

            // Get videos from channel (with pagination support)
            const videos = await youtubeService.getChannelVideos(channelId, {
                maxResults: 500,  // Increased from 50 to 500 to fetch all channel videos
                order: 'date'
            })

            logger.info(`Found ${videos.length} videos in channel ${channelId}`)

            for (let i = 0; i < videos.length; i++) {
                const video = videos[i]

                try {
                    // Check if video is likely a full movie
                    if (this.isLikelyMovie(video)) {
                        results.moviesFound++

                        // Check if movie already exists
                        try {
                            const existingMovie = await dbOperations.getMovieByYouTubeId(video.id)
                            logger.debug(`Movie already exists: ${video.title}`)

                            // If force re-enrich is enabled, update TMDB metadata
                            if (forceReenrich) {
                                logger.info(`[RE-ENRICH] Updating metadata for: ${video.title}`)
                                const updated = await this.updateExistingMovie(existingMovie, video)
                                if (updated) {
                                    results.moviesUpdated++
                                    logger.info(`✅ Updated movie: ${video.title}`)
                                } else {
                                    results.moviesSkipped++
                                }
                            } else {
                                results.moviesSkipped++
                            }
                            continue
                        } catch (error) {
                            // Movie doesn't exist, continue processing
                        }

                        // Process and add movie
                        const success = await this.processMovie(video)
                        if (success) {
                            results.moviesAdded++
                            logger.info(`✅ Added movie: ${video.title}`)
                        } else {
                            results.errors.push({
                                videoId: video.id,
                                title: video.title,
                                error: 'Failed to process movie'
                            })
                        }

                        // Update job progress periodically (every 5 videos)
                        if (jobId && i % 5 === 0) {
                            await dbOperations.updateCurationJobProgress(jobId, {
                                processed: i + 1,
                                successful: results.moviesAdded + results.moviesUpdated,
                                failed: results.errors.length
                            })
                        }
                    }
                } catch (error) {
                    logger.error(`Error processing video ${video.id}:`, error.message)
                    results.errors.push({
                        videoId: video.id,
                        title: video.title,
                        error: error.message
                    })
                }
            }

            // Complete job if provided
            if (jobId) {
                await dbOperations.completeCurationJob(jobId, results)
            }

        } catch (error) {
            logger.error(`Error curating channel ${channelId}:`, error.message)

            // Fail job if provided
            if (jobId) {
                await dbOperations.failCurationJob(jobId, error.message)
            }

            throw error
        }

        return results
    }

    async processMovie(video) {
        try {
            logger.debug(`Processing potential movie: ${video.title}`)

            // Get channel thumbnail from database
            let channelThumbnail = null
            try {
                const channel = await dbOperations.getChannelById(video.channelId)
                channelThumbnail = channel?.thumbnail_url || null
            } catch (error) {
                logger.debug(`Channel ${video.channelId} not in database, will be created`)
            }

            // Enhanced movie data with YouTube info
            // APPROACH 1: Store original YouTube title, clean later via bulk cleanup job
            // This allows flexible iteration on cleaning logic without re-importing
            const movieData = {
                youtube_video_id: video.id,
                title: video.title,  // Store original YouTube title (clean later with POST /api/admin/movies/fix-titles)
                original_title: video.title,
                // YouTube TOS Compliance fields (Phase 0)
                youtube_video_title: video.title,  // REQUIRED: Original YouTube video title (TOS Section III.D.8)
                channel_thumbnail: channelThumbnail,  // Channel avatar/thumbnail URL
                last_refreshed: new Date().toISOString(),  // Cache timestamp (TOS: max 30 days)
                // Regular YouTube metadata
                description: video.description,
                channel_id: video.channelId,
                view_count: video.viewCount,
                like_count: video.likeCount,
                comment_count: video.commentCount,
                published_at: video.publishedAt,
                runtime_minutes: youtubeService.parseDuration(video.duration),
                is_embeddable: video.embeddable,
                is_available: video.uploadStatus === 'processed' && video.privacyStatus === 'public',
                quality: this.determineVideoQuality(video),
                added_at: new Date().toISOString(),
                last_validated: new Date().toISOString()
            }

            // Try to enhance with TMDB data
            // Quick clean for TMDB search only (don't store this cleaned version)
            try {
                const titleForTMDB = this.quickCleanForTMDB(video.title)
                const tmdbData = await this.enrichWithTMDB(titleForTMDB)
                if (tmdbData) {
                    Object.assign(movieData, tmdbData)
                    movieData.enrichment_source = 'tmdb'
                    logger.debug(`Enhanced with TMDB data: ${tmdbData.title}`)
                } else {
                    // FALLBACK TO OMDB when TMDB fails
                    logger.info(`TMDB not found, trying OMDb for: ${video.title}`)
                    const omdbData = await this.enrichWithOMDb(video.title)
                    if (omdbData) {
                        Object.assign(movieData, omdbData)
                        logger.info(`✅ Enhanced with OMDb data: ${omdbData.title} (${omdbData.imdb_id})`)
                    }
                }
            } catch (tmdbError) {
                logger.warn(`TMDB enrichment failed for "${video.title}":`, tmdbError.message)
                // Try OMDb as fallback even on error
                try {
                    const omdbData = await this.enrichWithOMDb(video.title)
                    if (omdbData) {
                        Object.assign(movieData, omdbData)
                        logger.info(`✅ Enhanced with OMDb data: ${omdbData.title} (${omdbData.imdb_id})`)
                    }
                } catch (omdbError) {
                    logger.warn(`OMDb enrichment also failed for "${video.title}":`, omdbError.message)
                }
            }

            // Determine category
            movieData.category = this.categorizeMovie(movieData)

            // =============================================================================
            // DUPLICATE DETECTION (Phase 2)
            // =============================================================================

            // Step 1: Find or create movie group (detects duplicates)
            const { group, matchType, confidence } = await duplicateDetector.findOrCreateMovieGroup({
                tmdb_id: movieData.tmdb_id,
                title: movieData.title,
                release_year: movieData.release_date ? new Date(movieData.release_date).getFullYear() : null,
                youtube_video_id: video.id
            })

            // Log duplicate detection result
            if (matchType === 'new_group') {
                logger.info(`New movie: ${movieData.title}`, { group_id: group.id })
            } else {
                logger.info(`Duplicate detected: ${movieData.title} (${matchType}, ${(confidence * 100).toFixed(0)}% match)`, {
                    group_id: group.id,
                    canonical_title: group.canonical_title
                })
            }

            // Step 2: Calculate quality score for this version
            const qualityScore = duplicateDetector.calculateQualityScore(movieData)
            logger.debug(`Quality score: ${qualityScore}/100`, {
                views: movieData.view_count,
                embeddable: movieData.is_embeddable
            })

            // Step 3: Check if this should be the primary version
            const { isPrimary, existingPrimaryId } = await duplicateDetector.shouldBePrimary(
                group.id,
                qualityScore
            )

            // Add duplicate detection fields to movieData
            movieData.movie_group_id = group.id
            movieData.is_primary = isPrimary
            movieData.quality_score = qualityScore

            // =============================================================================
            // CREATE MOVIE IN DATABASE
            // =============================================================================

            // Check if this specific YouTube video is already in the database
            let existingMovie = null
            try {
                existingMovie = await dbOperations.getMovieByYouTubeId(video.id)
            } catch (error) {
                // Video doesn't exist, which is fine - we'll create it
            }

            let movie
            if (existingMovie) {
                // This specific YouTube video is already imported
                logger.info(`YouTube video already exists in database: ${video.title}`, {
                    existing_movie_id: existingMovie.id,
                    group_id: existingMovie.movie_group_id
                })

                // Update the existing movie's stats instead of inserting a duplicate
                await dbOperations.updateMovieStats(video.id, {
                    viewCount: movieData.view_count,
                    likeCount: movieData.like_count,
                    commentCount: movieData.comment_count
                })

                logger.info(`Updated stats for existing video`, {
                    movie_id: existingMovie.id,
                    views: movieData.view_count
                })

                return true
            } else {
                // New YouTube video - create it
                movie = await dbOperations.createMovie(movieData)
            }

            // Step 4: If this is now primary, demote the old primary
            if (isPrimary && existingPrimaryId) {
                await duplicateDetector.demotePrimary(existingPrimaryId)
                logger.info(`Promoted to primary (better quality score), demoted previous primary`, {
                    new_primary: movie.id,
                    old_primary: existingPrimaryId,
                    new_score: qualityScore
                })
            } else if (isPrimary) {
                logger.info(`Set as primary (first version in group)`, {
                    primary: movie.id,
                    group_id: group.id
                })
            } else {
                logger.info(`Added as backup version`, {
                    backup: movie.id,
                    group_id: group.id,
                    quality_score: qualityScore
                })
            }

            // Add genres if available
            if (movieData.genres && movie.id) {
                await this.addMovieGenres(movie.id, movieData.genres)
            }

            return true

        } catch (error) {
            logger.error(`Failed to process movie ${video.title}:`, error.message)
            return false
        }
    }

    async updateExistingMovie(existingMovie, video) {
        try {
            logger.debug(`Re-enriching existing movie: ${video.title}`)

            // Clean title for TMDB search (same as in processMovie)
            const titleForTMDB = this.quickCleanForTMDB(video.title)
            logger.debug(`Cleaned title for TMDB: "${titleForTMDB}"`)

            // Re-run TMDB enrichment with year-based matching
            const tmdbData = await this.enrichWithTMDB(titleForTMDB)

            if (tmdbData) {
                // Prepare update data
                const updateData = {
                    // Update TMDB fields
                    title: tmdbData.title,
                    description: tmdbData.description,
                    tmdb_id: tmdbData.tmdb_id,
                    imdb_id: tmdbData.imdb_id,
                    poster_path: tmdbData.poster_path,
                    backdrop_path: tmdbData.backdrop_path,
                    vote_average: tmdbData.vote_average,
                    vote_count: tmdbData.vote_count,
                    popularity: tmdbData.popularity,
                    release_date: tmdbData.release_date,
                    runtime_minutes: tmdbData.runtime_minutes,
                    enrichment_source: 'tmdb',
                    updated_at: new Date().toISOString()
                }

                // Update movie in database
                await dbOperations.updateMovie(existingMovie.id, updateData)

                // Update genres if available
                if (tmdbData.genres && existingMovie.id) {
                    await this.addMovieGenres(existingMovie.id, tmdbData.genres)
                }

                const matchYear = tmdbData.release_date ? new Date(tmdbData.release_date).getFullYear() : 'N/A'
                logger.info(`[RE-ENRICH] Updated TMDB data: ${tmdbData.title} (${matchYear}) - TMDB ID: ${tmdbData.tmdb_id}`)
                return true
            } else {
                // TMDB failed, try OMDb fallback
                logger.debug(`[RE-ENRICH] TMDB failed, trying OMDb fallback`)
                const omdbData = await this.enrichWithOMDb(titleForTMDB)

                if (omdbData) {
                    const updateData = {
                        title: omdbData.title,
                        description: omdbData.description,
                        imdb_id: omdbData.imdb_id,
                        poster_path: omdbData.poster_path,
                        backdrop_path: omdbData.backdrop_path,
                        imdb_rating: omdbData.imdb_rating,
                        imdb_votes: omdbData.imdb_votes,
                        rated: omdbData.rated,
                        release_date: omdbData.release_date,
                        runtime_minutes: omdbData.runtime_minutes,
                        director: omdbData.director,
                        actors: omdbData.actors,
                        country: omdbData.country,
                        is_tv_show: omdbData.is_tv_show,
                        enrichment_source: 'omdb',
                        updated_at: new Date().toISOString()
                    }

                    await dbOperations.updateMovie(existingMovie.id, updateData)
                    logger.info(`[RE-ENRICH] Updated OMDb data: ${omdbData.title}`)
                    return true
                }

                logger.warn(`[RE-ENRICH] Failed to enrich: ${video.title}`)
                return false
            }

        } catch (error) {
            logger.error(`Failed to update existing movie ${video.title}:`, error.message)
            return false
        }
    }

    // =============================================================================
    // MOVIE VALIDATION AND PROCESSING
    // =============================================================================

    isLikelyMovie(video) {
        const title = video.title.toLowerCase()
        const description = (video.description || '').toLowerCase()

        // Duration check
        const durationMinutes = youtubeService.parseDuration(video.duration)
        if (durationMinutes < this.requirements.minDurationMinutes ||
            durationMinutes > this.requirements.maxDurationMinutes) {
            return false
        }

        // View count check
        if (video.viewCount < this.requirements.minViewCount) {
            return false
        }

        // NOTE: We do NOT check embeddable status!
        // The embeddable flag only affects web IFrame embedding.
        // Since MovieBoxZ uses deep linking (youtube:// URL scheme) to open videos
        // in the native YouTube app, embeddable status is irrelevant.
        // This allows us to access ALL full-length movies on the channel.

        // Must be public and processed
        if (video.uploadStatus !== 'processed' || video.privacyStatus !== 'public') {
            return false
        }

        // Check for exclusion keywords only (no longer require movie keywords)
        // For dedicated movie channels, any 60+ minute video without negative keywords
        // is likely a full movie (even if title is just "Casablanca (1942)")
        const hasExcludeKeyword = this.excludeKeywords.some(keyword =>
            title.includes(keyword) || description.includes(keyword)
        )

        return !hasExcludeKeyword
    }

    quickCleanForTMDB(title) {
        /**
         * Quick title cleaning for TMDB search only
         * Used during import to find TMDB matches without storing cleaned title
         * Simple extraction: first segment before pipe, remove common keywords
         */
        let cleaned = title

        // Extract first segment before pipe (most common pattern)
        if (cleaned.includes('|')) {
            cleaned = cleaned.split('|')[0].trim()
        }

        // Remove common YouTube indicators
        cleaned = cleaned
            .replace(/\b(full movie|complete film|full film|feature film)\b/gi, '')
            .replace(/\[.*?\]/g, '')
            .replace(/\b(HD|4K|1080p|720p|480p)\b/gi, '')
            .replace(/\s+/g, ' ')
            .trim()

        return cleaned
    }

    cleanMovieTitle(title, pattern = null) {
        /**
         * Intelligent title cleaning with pattern-aware extraction
         *
         * Uses AI-detected channel patterns to extract correct title segment:
         * - Pattern A: "Movie Title | Genre | Actor | Channel" → Extract FIRST
         * - Pattern B: "Clickbait | Actual Movie Title" → Extract LAST
         * - Mixed/Unknown: Try both and pick shortest cleaned result
         */

        // SAFETY CHECK: Override pattern if it contradicts actual title structure
        if (pattern && !pattern.pipe_separator && title.includes('|')) {
            logger.warn(`Pattern mismatch detected: pattern says no pipes but title has pipes`, {
                title: title,
                detected_pattern: pattern.type
            })
            // Override pattern to use pipe-based extraction
            pattern = {
                pipe_separator: true,
                title_position: 'first',
                type: 'first_segment_override',
                confidence: 0.6
            }
            logger.info(`Applied fallback pattern: first_segment with 60% confidence`)
        }

        let candidateTitles = []

        // Step 1: Extract title segment(s) based on detected pattern
        if (title.includes('|')) {
            const segments = title.split('|').map(s => s.trim())

            if (pattern && pattern.pipe_separator) {
                // Use AI-detected pattern
                logger.debug(`Using detected pattern: ${pattern.type} (position: ${pattern.title_position})`)

                if (pattern.title_position === 'first') {
                    // Title is in FIRST segment (e.g., "Movie | Genre | Actor | Channel")
                    candidateTitles.push(segments[0])
                } else if (pattern.title_position === 'last') {
                    // Title is in LAST segment (e.g., "Clickbait | Actual Title")
                    candidateTitles.push(segments[segments.length - 1])
                } else if (pattern.title_position === 'both' || pattern.confidence < 0.7) {
                    // Low confidence or mixed patterns: try both
                    candidateTitles.push(segments[0])
                    if (segments.length > 1) {
                        candidateTitles.push(segments[segments.length - 1])
                    }
                    logger.debug(`Low confidence pattern, trying both segments`)
                }
            } else {
                // No pattern: try both first and last segments (fallback)
                candidateTitles.push(segments[0])
                if (segments.length > 1) {
                    candidateTitles.push(segments[segments.length - 1])
                }
                logger.debug(`No pattern available, trying both first and last segments`)
            }
        } else {
            // No pipes: use full title
            candidateTitles.push(title)
        }

        // Step 2: Clean all candidate titles
        const cleanedCandidates = candidateTitles.map(candidate => {
            let cleaned = candidate

            // Remove common YouTube video indicators
            cleaned = cleaned
                // Remove "FULL MOVIE", "Full Movie", "full movie", etc.
                .replace(/\b(full movie|complete film|full film|feature film)\b/gi, '')

                // Remove brackets and their content like "[HD]" or "[Restored]"
                .replace(/\[.*?\]/g, '')

                // Remove quality indicators like "HD", "4K", "1080p"
                .replace(/\b(HD|4K|1080p|720p|480p|DVD|BLURAY|BLU-RAY)\b/gi, '')

                // Remove "Official", "Original", etc.
                .replace(/\b(official|original|remastered|restored)\b/gi, '')

                // Remove dashes at the end (often used before channel names)
                .replace(/\s*-\s*$/, '')

                // Remove extra whitespace (multiple spaces become single space)
                .replace(/\s+/g, ' ')

                // Trim leading/trailing whitespace
                .trim()

            // NOTE: We keep years in parentheses like "(1975)" because they help with TMDB matching!
            return cleaned
        })

        // Step 3: Pick best candidate (shortest is usually best for TMDB matching)
        const bestTitle = cleanedCandidates.reduce((shortest, current) => {
            return current.length < shortest.length ? current : shortest
        })

        logger.debug(`Extracted title: "${bestTitle}" (from ${candidateTitles.length} candidates)`)

        return bestTitle
    }

    determineVideoQuality(video) {
        const title = video.title.toLowerCase()

        if (title.includes('4k')) return '4k'
        if (title.includes('1080p') || title.includes('hd')) return '1080p'
        if (title.includes('720p')) return '720p'

        return '720p' // Default assumption
    }

    categorizeMovie(movieData) {
        const title = movieData.title.toLowerCase()
        const description = (movieData.description || '').toLowerCase()
        const text = `${title} ${description}`

        // Genre detection based on keywords
        const genreKeywords = {
            'action': ['action', 'fight', 'war', 'battle', 'combat', 'martial arts'],
            'comedy': ['comedy', 'funny', 'humor', 'laugh', 'comic'],
            'drama': ['drama', 'dramatic', 'emotional', 'tragedy'],
            'horror': ['horror', 'scary', 'fear', 'ghost', 'monster', 'zombie'],
            'romance': ['romance', 'love', 'romantic', 'wedding', 'heart'],
            'thriller': ['thriller', 'suspense', 'mystery', 'crime', 'detective'],
            'science_fiction': ['sci-fi', 'science fiction', 'space', 'alien', 'future'],
            'western': ['western', 'cowboy', 'frontier', 'gunfight'],
            'documentary': ['documentary', 'true story', 'real life', 'biography'],
            'animation': ['animation', 'animated', 'cartoon'],
            'classic': ['classic', 'vintage', 'old', 'golden age', 'legendary']
        }

        // Check for genre keywords
        for (const [category, keywords] of Object.entries(genreKeywords)) {
            if (keywords.some(keyword => text.includes(keyword))) {
                return category
            }
        }

        // Default to classic for older content
        if (movieData.published_at && new Date(movieData.published_at).getFullYear() < 2000) {
            return 'classic'
        }

        return 'drama' // Default category
    }

    // =============================================================================
    // TMDB INTEGRATION
    // =============================================================================

    async enrichWithTMDB(movieTitle) {
        try {
            if (!tmdbService) {
                return null
            }

            // PHASE 1: Year-Based Matching
            // Extract year from title like "Nosferatu (1922)" or "Casablanca (1942)"
            const yearMatch = movieTitle.match(/\((\d{4})\)/)
            const year = yearMatch ? parseInt(yearMatch[1]) : null

            // Clean title by removing year for search
            const cleanTitle = movieTitle.replace(/\s*\((\d{4})\)\s*/, '').trim()

            if (year) {
                logger.info(`[YEAR-MATCH] Searching TMDB: "${cleanTitle}" (${year})`)
            } else {
                logger.info(`[TMDB] Searching: "${cleanTitle}" (no year found in title)`)
            }

            // Search for movie in TMDB with year parameter
            const searchResults = await tmdbService.searchMovies(cleanTitle, year)

            if (!searchResults || searchResults.length === 0) {
                logger.warn(`No TMDB results for "${cleanTitle}"${year ? ` (${year})` : ''}`)
                return null
            }

            // Log search results for transparency
            if (searchResults.length > 1) {
                logger.debug(`Found ${searchResults.length} TMDB results:`)
                searchResults.slice(0, 3).forEach((movie, i) => {
                    const movieYear = movie.releaseDate ? new Date(movie.releaseDate).getFullYear() : 'N/A'
                    logger.debug(`  ${i + 1}. ${movie.title} (${movieYear}) - Popularity: ${movie.popularity.toFixed(1)}`)
                })
            }

            // Get the most likely match (first result, now filtered by year)
            const tmdbMovie = searchResults[0]
            const matchYear = tmdbMovie.releaseDate ? new Date(tmdbMovie.releaseDate).getFullYear() : null
            logger.info(`[MATCHED] ${tmdbMovie.title} (${matchYear}) - TMDB ID: ${tmdbMovie.id}`)

            // Get detailed movie info
            const movieDetails = await tmdbService.getMovieDetails(tmdbMovie.id)

            // Return TMDB data WITH clean title and description
            return {
                tmdb_id: movieDetails.id,
                imdb_id: movieDetails.imdb_id,
                title: movieDetails.title,  // Clean TMDB title (replaces YouTube title)
                original_title: movieDetails.original_title,
                description: movieDetails.overview,  // Clean TMDB plot (replaces YouTube description)
                poster_path: movieDetails.poster_path,
                backdrop_path: movieDetails.backdrop_path,
                vote_average: movieDetails.vote_average,
                vote_count: movieDetails.vote_count,
                popularity: movieDetails.popularity,
                release_date: movieDetails.release_date,
                runtime_minutes: movieDetails.runtime,
                // Note: genres are returned separately for addMovieGenres() to handle
                genres: movieDetails.genres  // This is used by addMovieGenres(), not saved to movies table
            }

        } catch (error) {
            logger.warn(`TMDB enrichment failed for "${movieTitle}":`, error.message)
            return null
        }
    }

    // =============================================================================
    // OMDB INTEGRATION (FALLBACK)
    // =============================================================================

    async enrichWithOMDb(movieTitle) {
        /**
         * Enrich with OMDb (IMDB database) as fallback when TMDB fails
         * OMDb searches both movies AND TV shows (unlike TMDB which only searches movies)
         */
        try {
            if (!omdbService || !omdbService.apiKey) {
                return null
            }

            // Extract year from title if present (e.g., "Movie (2008)")
            const year = omdbService.extractYearFromTitle(movieTitle)
            const titleWithoutYear = movieTitle.replace(/\s*\(\d{4}\)$/, '')

            // Try exact title first
            let omdbData = await omdbService.searchByTitle(movieTitle)

            if (!omdbData && year) {
                // Try without year suffix
                logger.debug(`OMDb: Retrying without year suffix`)
                omdbData = await omdbService.searchByTitle(titleWithoutYear, year)
            }

            if (!omdbData) {
                // Try without "The" prefix
                const titleWithoutThe = titleWithoutYear.replace(/^The\s+/i, '')
                if (titleWithoutThe !== titleWithoutYear) {
                    logger.debug(`OMDb: Retrying without "The" prefix`)
                    omdbData = await omdbService.searchByTitle(titleWithoutThe, year)
                }
            }

            if (omdbData) {
                // OMDb returns data in different format than TMDB, already transformed
                return {
                    imdb_id: omdbData.imdb_id,
                    poster_path: omdbData.poster_path,
                    description: omdbData.description,
                    release_date: omdbData.release_date,
                    runtime_minutes: omdbData.runtime_minutes,
                    imdb_rating: omdbData.imdb_rating,
                    imdb_votes: omdbData.imdb_votes,
                    rated: omdbData.rated,
                    director: omdbData.director,
                    actors: omdbData.actors,
                    language: omdbData.language,
                    country: omdbData.country,
                    is_tv_show: omdbData.is_tv_show,
                    enrichment_source: 'omdb'
                }
            }

            return null

        } catch (error) {
            logger.warn(`OMDb enrichment failed for "${movieTitle}":`, error.message)
            return null
        }
    }

    async addMovieGenres(movieId, genres) {
        if (!genres || genres.length === 0) return

        try {
            // Ensure genres exist in database
            for (const genre of genres) {
                await this.ensureGenreExists(genre)
            }

            // Add movie-genre relationships
            const genreRelations = genres.map(genre => ({
                movie_id: movieId,
                genre_id: genre.id
            }))

            const { error: insertError } = await dbOperations.supabase
                .from('movie_genres')
                .upsert(genreRelations, { onConflict: 'movie_id,genre_id' })

            if (insertError) {
                throw new Error(`Failed to insert movie-genre relationships: ${insertError.message}`)
            }

        } catch (error) {
            logger.error(`Failed to add genres for movie ${movieId}:`, error.message)
            // Don't throw - allow enrichment to continue even if genres fail
        }
    }

    async ensureGenreExists(genre) {
        try {
            await dbOperations.supabase
                .from('genres')
                .upsert({
                    id: genre.id,
                    name: genre.name
                })
        } catch (error) {
            logger.error(`Failed to ensure genre exists: ${genre.name}`, error.message)
        }
    }

    // =============================================================================
    // CHANNEL MANAGEMENT
    // =============================================================================

    async ensureChannelExists(channelId) {
        try {
            // Check if channel exists
            const existing = await dbOperations.getChannelById(channelId)
            if (existing) {
                return existing
            }
        } catch (error) {
            // Channel doesn't exist, create it
        }

        try {
            // Get channel info from YouTube
            const channelInfo = await youtubeService.getChannelInfo(channelId)

            // Create channel in database
            const channelData = {
                id: channelInfo.id,
                title: channelInfo.title,
                description: channelInfo.description,
                thumbnail_url: channelInfo.thumbnailUrl,
                banner_url: channelInfo.bannerUrl,
                subscriber_count: channelInfo.subscriberCount,
                view_count: channelInfo.viewCount,
                video_count: channelInfo.videoCount,
                is_verified: channelInfo.isVerified,
                is_curated: this.curatedChannels.some(c => c.id === channelId),
                country: channelInfo.country
            }

            const channel = await dbOperations.createChannel(channelData)
            logger.info(`Created channel: ${channel.title}`)
            return channel

        } catch (error) {
            logger.error(`Failed to create channel ${channelId}:`, error.message)
            throw error
        }
    }

    // =============================================================================
    // VALIDATION AND MAINTENANCE
    // =============================================================================

    async validateExistingMovies(limit = 100) {
        logger.info(`🔍 Validating ${limit} existing movies`)

        const results = {
            checked: 0,
            stillAvailable: 0,
            nowUnavailable: 0,
            errors: []
        }

        try {
            // Get movies that haven't been validated recently
            const { data: movies } = await dbOperations.supabase
                .from('movies')
                .select('id, youtube_video_id, title')
                .lt('last_validated', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
                .limit(limit)

            for (const movie of movies) {
                try {
                    results.checked++

                    const availability = await youtubeService.checkVideoAvailability(movie.youtube_video_id)

                    if (availability.available && availability.embeddable) {
                        results.stillAvailable++

                        // Update movie stats if available
                        if (availability.details) {
                            await dbOperations.updateMovieStats(movie.youtube_video_id, {
                                viewCount: availability.details.viewCount,
                                likeCount: availability.details.likeCount,
                                commentCount: availability.details.commentCount
                            })
                        }
                    } else {
                        results.nowUnavailable++

                        // Mark as unavailable
                        await dbOperations.updateMovie(movie.id, {
                            is_available: availability.available,
                            is_embeddable: availability.embeddable,
                            validation_error: availability.error,
                            last_validated: new Date().toISOString()
                        })

                        logger.warn(`Movie now unavailable: ${movie.title}`)
                    }

                } catch (error) {
                    logger.error(`Error validating movie ${movie.title}:`, error.message)
                    results.errors.push({
                        movieId: movie.id,
                        error: error.message
                    })
                }
            }

        } catch (error) {
            logger.error('Error validating movies:', error.message)
            throw error
        }

        logger.info(`Validation completed: ${results.stillAvailable} still available, ${results.nowUnavailable} now unavailable`)
        return results
    }

    async getStatistics() {
        const stats = {}

        try {
            // Movie counts
            const { count: totalMovies } = await dbOperations.supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })

            const { count: availableMovies } = await dbOperations.supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .eq('is_available', true)

            const { count: featuredMovies } = await dbOperations.supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .eq('featured', true)

            // Channel counts
            const { count: totalChannels } = await dbOperations.supabase
                .from('channels')
                .select('*', { count: 'exact', head: true })

            stats.movies = {
                total: totalMovies,
                available: availableMovies,
                featured: featuredMovies,
                unavailable: totalMovies - availableMovies
            }

            stats.channels = {
                total: totalChannels,
                curated: this.curatedChannels.length
            }

        } catch (error) {
            logger.error('Error getting statistics:', error.message)
        }

        return stats
    }
}

export const movieCurator = new MovieCurator()
export default movieCurator
