import { youtubeService } from './youtubeService.js'
import { tmdbService } from './tmdbService.js'
import { omdbService } from './omdbService.js'
import { dbOperations } from '../config/database.js'
import { logger } from '../utils/logger.js'
import { channelPatternDetector } from './channelPatternDetector.js'
import duplicateDetector from './duplicateDetector.js'
import enhancedEnrichment from './enhancedEnrichment.js'

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
     * Extract movie title from YouTube video title
     */
    extractMovieTitle(youtubeTitle, channelId) {
        // Use channel pattern detector if available
        const pattern = channelPatternDetector?.getPattern?.(channelId)
        if (pattern) {
            return channelPatternDetector.extractTitle(youtubeTitle, pattern)
        }

        // Fallback to basic extraction
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

        return title.trim()
    }

    /**
     * Process and add a movie to database
     */
    async processMovie(video, options = {}) {
        try {
            const movieTitle = this.extractMovieTitle(video.title, video.channelId)

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

            // Try to enrich with metadata
            let enrichmentData = null
            try {
                enrichmentData = await enhancedEnrichment.enrichMovie(movieData)
                if (enrichmentData && enrichmentData.confidence >= 50) {
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
                }
            } catch (enrichError) {
                logger.warn(`Failed to enrich ${movieTitle}: ${enrichError.message}`)
                // Continue without enrichment
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
                        const success = await this.processMovie(video, options)
                        if (success) {
                            results.moviesAdded++
                        } else {
                            results.moviesSkipped++
                        }
                    } else {
                        results.moviesSkipped++
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
            await dbOperations.updateChannel(channelId, {
                last_curated: new Date().toISOString(),
                video_count: channelInfo.videoCount,
                subscriber_count: channelInfo.subscriberCount
            })

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
            const { count: totalMovies } = await dbOperations.supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })

            const { count: availableMovies } = await dbOperations.supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .eq('is_available', true)

            const { count: enrichedMovies } = await dbOperations.supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .not('tmdb_id', 'is', null)

            const { count: pendingEnrichment } = await dbOperations.supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .is('tmdb_id', null)
                .eq('is_available', true)

            // Channel counts
            const { count: totalChannels } = await dbOperations.supabase
                .from('channels')
                .select('*', { count: 'exact', head: true })

            // Genre counts
            const { count: totalGenres } = await dbOperations.supabase
                .from('genres')
                .select('*', { count: 'exact', head: true })

            // Recently added movies (last 7 days)
            const sevenDaysAgo = new Date()
            sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)
            const { count: recentlyAdded } = await dbOperations.supabase
                .from('movies')
                .select('*', { count: 'exact', head: true })
                .gte('created_at', sevenDaysAgo.toISOString())

            // Last curation time
            const { data: lastChannel } = await dbOperations.supabase
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