import { youtubeService } from './youtubeService.js'
import { tmdbService } from './tmdbService.js'
import { omdbService } from './omdbService.js'
import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'
import channelPatternManager from './channelPatternManager.js'
import manualEnrichmentQueue from './manualEnrichmentQueue.js'
import duplicateDetector from './duplicateDetector.js'
import { enhancedEnrichment } from './enhancedEnrichment.js'

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
            },
            {
                id: 'UC6A_LC-A5NVJ2vw9A0OjCug',
                name: 'The Midnight Screening',
                description: 'Horror and classic movies'
            },
            {
                id: 'UCHvnMsLnyQZscrq-fOckiiw',
                name: 'BlackTree TV',
                description: 'Movies and entertainment'
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

    /**
     * Parse ISO 8601 duration format (PT2H30M15S) to minutes
     */
    parseDuration(duration) {
        if (!duration) return 0

        const match = duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/)
        if (!match) return 0

        const hours = parseInt(match[1] || 0)
        const minutes = parseInt(match[2] || 0)
        const seconds = parseInt(match[3] || 0)

        return hours * 60 + minutes + (seconds / 60)
    }

    /**
     * Check if video meets movie criteria
     */
    isLikelyMovie(video) {
        try {
            const durationMinutes = this.parseDuration(video.duration)
            const titleLower = (video.title || '').toLowerCase()
            const descriptionLower = (video.description || '').toLowerCase()
            const combinedText = `${titleLower} ${descriptionLower}`

            // Check duration
            if (durationMinutes < this.requirements.minDurationMinutes ||
                durationMinutes > this.requirements.maxDurationMinutes) {
                return false
            }

            // Check for exclude keywords
            const hasExcludeKeyword = this.excludeKeywords.some(keyword =>
                titleLower.includes(keyword)
            )
            if (hasExcludeKeyword) {
                return false
            }

            // Check embeddable status
            if (video.embeddable === false) {
                return false
            }

            // Check privacy status
            if (video.privacyStatus !== 'public') {
                return false
            }

            // Check if it's likely a movie based on keywords
            const hasMovieKeyword = this.movieKeywords.some(keyword =>
                combinedText.includes(keyword)
            )

            // For certain channels (like The Midnight Screening), be more lenient
            const isTrustedChannel = this.curatedChannels.some(ch =>
                ch.id === video.channelId ||
                ch.name === video.channelTitle
            )

            // If it's from a trusted channel, just check duration
            if (isTrustedChannel) {
                return true
            }

            // Otherwise require movie keywords
            return hasMovieKeyword

        } catch (error) {
            logger.error(`Error checking if video is movie: ${error.message}`)
            return false
        }
    }

    /**
     * Extract metadata from YouTube video title using channel patterns
     * Returns extracted metadata including title, actors, genre, year
     */
    async extractMetadata(youtubeTitle, channelId) {
        try {
            // Get channel pattern from database
            const pattern = await channelPatternManager.getPattern(channelId)

            if (pattern) {
                // Extract metadata using pattern
                const metadata = channelPatternManager.extractMetadata(youtubeTitle, pattern)
                if (metadata) {
                    logger.debug('Pattern extraction successful', {
                        title: metadata.title,
                        actors: metadata.actorsArray,
                        genre: metadata.genre,
                        year: metadata.year
                    })
                    return metadata
                }
            }

            // No pattern or pattern didn't match - fallback to basic extraction
            logger.debug('Using fallback title extraction for:', youtubeTitle)
            return this.fallbackTitleExtraction(youtubeTitle)

        } catch (error) {
            logger.error('Error extracting metadata:', error)
            return this.fallbackTitleExtraction(youtubeTitle)
        }
    }

    /**
     * Fallback title extraction when no pattern matches
     */
    fallbackTitleExtraction(youtubeTitle) {
        let title = youtubeTitle

        // Remove common suffixes
        const suffixPatterns = [
            /\s*\|\s*.+$/,  // Remove everything after |
            /\s*-\s*Full Movie.*$/i,
            /\s*Full Movie.*$/i,
            /\s*\(?\d{4}\)?$/,  // Remove year
            /\s*HD.*$/i,
            /\s*4K.*$/i,
            /\s*1080p.*$/i,
            /\s*720p.*$/i,
            /\s*Free Movie.*$/i,
            /\s*Classic Film.*$/i
        ]

        for (const pattern of suffixPatterns) {
            title = title.replace(pattern, '')
        }

        return {
            title: title.trim(),
            patternMatched: false,
            confidence: 0.3,
            rawTitle: youtubeTitle
        }
    }

    /**
     * Process and add a movie to database
     */
    async processMovie(video, options = {}) {
        try {
            // Extract metadata using channel patterns
            const extractedMetadata = await this.extractMetadata(video.title, video.channelId)
            const movieTitle = extractedMetadata.title

            logger.info(`Processing: ${movieTitle}`, {
                patternMatched: extractedMetadata.patternMatched,
                actors: extractedMetadata.actorsArray,
                genre: extractedMetadata.genre,
                year: extractedMetadata.year
            })

            // Check for duplicates
            const isDuplicate = await duplicateDetector.isDuplicate({
                youtube_video_id: video.id,
                channel_id: video.channelId,
                youtube_video_title: video.title
            })

            if (isDuplicate && !options.forceReenrich) {
                logger.info(`Skipping duplicate: ${movieTitle}`)
                return false
            }

            // Prepare movie data
            const movieData = {
                youtube_video_id: video.id,
                title: movieTitle,
                youtube_video_title: video.title,
                description: video.description,
                channel_id: video.channelId,
                channel_title: video.channelTitle,
                published_at: video.publishedAt,
                duration_minutes: Math.round(this.parseDuration(video.duration)),
                view_count: parseInt(video.viewCount) || 0,
                like_count: parseInt(video.likeCount) || 0,
                comment_count: parseInt(video.commentCount) || 0,
                channel_thumbnail: video.thumbnails?.high?.url || video.thumbnails?.default?.url,
                is_available: video.uploadStatus === 'processed' && video.privacyStatus === 'public',
                is_embeddable: video.embeddable !== false,
                last_validated: new Date().toISOString()
            }

            // Try to enrich with metadata, passing extracted hints
            let enrichmentData = null
            let enrichmentSuccess = false

            try {
                // Pass actor, year, and genre hints from pattern extraction
                enrichmentData = await enhancedEnrichment.enrichMovie({
                    ...movieData,
                    actorHints: extractedMetadata.actorsArray,
                    yearHint: extractedMetadata.year,
                    genreHint: extractedMetadata.genre
                })

                if (enrichmentData && enrichmentData.confidence >= 70) {
                    enrichmentSuccess = true
                    // Only assign database-valid fields, exclude confidence and other non-DB fields
                    movieData.tmdb_id = enrichmentData.tmdb_id
                    movieData.imdb_id = enrichmentData.imdb_id
                    movieData.title = enrichmentData.title || movieData.title
                    movieData.original_title = enrichmentData.original_title
                    movieData.description = enrichmentData.description || movieData.description
                    movieData.release_date = enrichmentData.release_date
                    movieData.runtime_minutes = enrichmentData.runtime_minutes || movieData.duration_minutes
                    movieData.poster_path = enrichmentData.poster_path
                    movieData.backdrop_path = enrichmentData.backdrop_path
                    movieData.vote_average = enrichmentData.vote_average
                    movieData.vote_count = enrichmentData.vote_count
                    movieData.popularity = enrichmentData.popularity
                    movieData.imdb_rating = enrichmentData.imdb_rating
                    movieData.rated = enrichmentData.rated
                    movieData.director = enrichmentData.director
                    movieData.actors = enrichmentData.actors
                    movieData.country = enrichmentData.country
                    movieData.language = enrichmentData.language
                    movieData.is_tv_show = enrichmentData.media_type === 'tv'
                    movieData.enrichment_source = enrichmentData.source
                    // Note: Do NOT include confidence, actorMatch or other non-DB fields

                    logger.info(` Enrichment successful: ${movieTitle} (confidence: ${enrichmentData.confidence})`)
                } else {
                    logger.warn(`Low confidence enrichment for ${movieTitle}: ${enrichmentData?.confidence || 0}%`)
                }
            } catch (enrichError) {
                logger.warn(`Failed to enrich ${movieTitle}: ${enrichError.message}`)
                // Continue without enrichment
            }

            // If enrichment failed or confidence is low, add to manual queue
            if (!enrichmentSuccess) {
                try {
                    await manualEnrichmentQueue.addToQueue(movieData, extractedMetadata)
                    logger.info(` Added to manual enrichment queue: ${movieTitle}`)
                } catch (queueError) {
                    logger.error(`Failed to add to manual queue: ${queueError.message}`)
                }
            }

            // Save movie to database
            const savedMovie = await dbOperations.createMovie(movieData)

            // Add genres if enrichment provided them
            if (savedMovie && enrichmentData?.genres?.length > 0) {
                await this.addMovieGenres(savedMovie.id, enrichmentData.genres)
            }

            logger.info(` Added movie: ${movieTitle}`)
            return true

        } catch (error) {
            logger.error(`Failed to process movie ${video.id}: ${error.message}`)
            return false
        }
    }

    /**
     * Add genres to a movie
     */
    async addMovieGenres(movieId, genres) {
        try {
            for (const genre of genres) {
                // Ensure genre exists
                let genreRecord = await dbOperations.getGenreByTmdbId(genre.id)
                if (!genreRecord) {
                    genreRecord = await dbOperations.createGenre({
                        tmdb_id: genre.id,
                        name: genre.name
                    })
                }

                // Create movie-genre relationship
                await dbOperations.addMovieGenre(movieId, genreRecord.id)
            }
        } catch (error) {
            logger.error(`Failed to add genres for movie ${movieId}: ${error.message}`)
        }
    }

    /**
     * Fetch movies from a channel (for staging import)
     * @param {string} channelIdOrTitle - Channel ID or title
     * @param {number} limit - Maximum number of videos to fetch
     * @returns {Promise<Array>} Array of movie objects formatted for staging
     */
    async fetchChannelMovies(channelIdOrTitle, limit = 50) {
        try {
            logger.info(`Fetching movies from channel: ${channelIdOrTitle}`)

            // Resolve channel ID
            const channelId = await youtubeService.resolveChannelIdentifier(channelIdOrTitle)

            // Get channel info
            const channelInfo = await youtubeService.getChannelInfo(channelId)

            // Fetch videos from channel
            const videos = await youtubeService.getChannelVideos(channelId, {
                maxResults: limit
            })

            // Filter and format videos that look like movies
            const movies = videos
                .filter(video => this.isLikelyMovie(video))
                .map(video => ({
                    youtubeVideoId: video.id,
                    title: video.title,
                    cleanTitle: null, // Will be populated by pattern extraction
                    description: video.description,
                    channelId: video.channelId,
                    channelTitle: video.channelTitle,
                    publishedAt: video.publishedAt,
                    durationMinutes: this.parseDuration(video.duration),
                    viewCount: video.viewCount,
                    likeCount: video.likeCount,
                    commentCount: video.commentCount,
                    thumbnails: video.thumbnails
                }))

            logger.info(`Found ${movies.length} movies from ${videos.length} videos`)
            return movies

        } catch (error) {
            logger.error(`Error fetching channel movies: ${error.message}`)
            throw error
        }
    }

    /**
     * Fetch movies from a YouTube playlist (for staging import)
     * @param {string} playlistId - Playlist ID
     * @param {number} limit - Maximum number of videos to fetch
     * @returns {Promise<Array>} Array of movie objects formatted for staging
     */
    async fetchPlaylistMovies(playlistId, limit = 50) {
        try {
            logger.info(`Fetching movies from playlist: ${playlistId}`)

            // Fetch videos from playlist
            const videos = await youtubeService.getPlaylistItems(playlistId, {
                maxResults: limit
            })

            // Filter and format videos that look like movies
            const movies = videos
                .filter(video => this.isLikelyMovie(video))
                .map(video => ({
                    youtubeVideoId: video.id,
                    title: video.title,
                    cleanTitle: null, // Will be populated by pattern extraction
                    description: video.description,
                    channelId: video.channelId,
                    channelTitle: video.channelTitle,
                    publishedAt: video.publishedAt,
                    durationMinutes: this.parseDuration(video.duration),
                    viewCount: video.viewCount,
                    likeCount: video.likeCount,
                    commentCount: video.commentCount,
                    thumbnails: video.thumbnails
                }))

            logger.info(`Found ${movies.length} movies from ${videos.length} videos in playlist`)
            return movies

        } catch (error) {
            logger.error(`Error fetching playlist movies: ${error.message}`)
            throw error
        }
    }

    /**
     * Curate movies from a channel
     */
    async curateChannelMovies(channelId, options = {}) {
        const results = {
            channelId,
            moviesFound: 0,
            moviesAdded: 0,
            moviesUpdated: 0,
            moviesSkipped: 0,
            errors: []
        }

        try {
            // Get channel info
            const channelInfo = await youtubeService.getChannelInfo(channelId)
            logger.info(`Curating movies from channel: ${channelInfo.title}`)

            // Update job if provided
            if (options.jobId) {
                await dbOperations.updateCurationJobProgress(options.jobId, {
                    status: 'processing'
                })
            }

            // Fetch recent videos from channel
            const videos = await youtubeService.getChannelVideos(channelId, {
                maxResults: options.limit || 50,
                fetchDetails: true
            })

            results.moviesFound = videos.length
            logger.info(`Found ${videos.length} videos to process`)

            // Process each video
            for (const video of videos) {
                try {
                    if (this.isLikelyMovie(video)) {
                        logger.info(`Processing video: ${video.title}`)
                        const success = await this.processMovie(video, options)
                        if (success) {
                            results.moviesAdded++
                        } else {
                            results.moviesSkipped++
                            logger.info(`Skipped due to duplicate or processing error: ${video.title}`)
                        }
                    } else {
                        results.moviesSkipped++
                        logger.info(`Skipped - not a movie: ${video.title}, duration: ${this.parseDuration(video.duration)} mins`)
                    }

                    // Update progress
                    if (options.jobId && (results.moviesAdded + results.moviesSkipped) % 10 === 0) {
                        await dbOperations.updateCurationJobProgress(options.jobId, {
                            processed: results.moviesAdded + results.moviesSkipped,
                            successful: results.moviesAdded,
                            failed: results.errors.length
                        })
                    }

                } catch (error) {
                    logger.error(`Error processing video ${video.id}: ${error.message}`)
                    results.errors.push({
                        videoId: video.id,
                        title: video.title,
                        error: error.message
                    })
                }
            }

            // Update channel last curated time
            // TODO: Fix database schema - last_curated column doesn't exist
            // await dbOperations.updateChannel(channelId, {
            //     last_curated: new Date().toISOString(),
            //     video_count: channelInfo.videoCount,
            //     subscriber_count: channelInfo.subscriberCount
            // })

            // Complete job if provided
            if (options.jobId) {
                await dbOperations.completeCurationJob(options.jobId, results)
            }

            logger.info(` Channel curation completed: ${results.moviesAdded} movies added`)
            return results

        } catch (error) {
            logger.error(`Channel curation failed: ${error.message}`)
            results.errors.push({
                error: error.message
            })

            // Fail job if provided
            if (options.jobId) {
                await dbOperations.failCurationJob(options.jobId, error.message)
            }

            throw error
        }
    }

    /**
     * Get statistics
     */
    async getStatistics() {
        try {
            // Movie counts
            const { count: totalMovies } = await supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })

            const { count: availableMovies } = await supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .eq('is_available', true)

            const { count: enrichedMovies } = await supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .not('tmdb_id', 'is', null)

            const { count: pendingEnrichment } = await supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .is('tmdb_id', null)
                .eq('is_available', true)

            // Channel counts
            const { count: totalChannels } = await supabase
                .from('channels')
                .select('*', { count: 'exact', head: true })

            // Genre counts
            const { count: totalGenres } = await supabase
                .from('genres')
                .select('*', { count: 'exact', head: true })

            // Recently added movies (last 7 days)
            const sevenDaysAgo = new Date()
            sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)
            const { count: recentlyAdded } = await supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .gte('created_at', sevenDaysAgo.toISOString())

            // Last curation time
            const { data: lastChannel } = await supabase
                .from('channels')
                .select('last_curated')
                .not('last_curated', 'is', null)
                .order('last_curated', { ascending: false })
                .limit(1)
                .single()

            // Return flat structure matching Swift AdminStats model
            return {
                total_movies: totalMovies || 0,
                available_movies: availableMovies || 0,
                total_channels: totalChannels || 0,
                total_genres: totalGenres || 0,
                enriched_movies: enrichedMovies || 0,
                pending_enrichment: pendingEnrichment || 0,
                recently_added: recentlyAdded || 0,
                last_curation: lastChannel?.last_curated || null
            }

        } catch (error) {
            logger.error('Error getting statistics:', error.message)
            // Return empty stats on error
            return {
                total_movies: 0,
                available_movies: 0,
                total_channels: 0,
                total_genres: 0,
                enriched_movies: 0,
                pending_enrichment: 0,
                recently_added: 0,
                last_curation: null
            }
        }
    }
}

export const movieCurator = new MovieCurator()
export default movieCurator