import { youtubeService } from './youtubeService.js'
import { tmdbService } from './tmdbService.js'
import { dbOperations } from '../config/database.js'
import { logger } from '../utils/logger.js'

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
        const { jobId = null } = options

        logger.info(`🔍 Curating movies from channel: ${channelId}${jobId ? ` (Job: ${jobId})` : ''}`)

        const results = {
            moviesFound: 0,
            moviesAdded: 0,
            moviesSkipped: 0,
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
                            await dbOperations.getMovieByYouTubeId(video.id)
                            logger.debug(`Movie already exists: ${video.title}`)
                            results.moviesSkipped++
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
                                successful: results.moviesAdded,
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

            // Enhanced movie data with YouTube info
            const movieData = {
                youtube_video_id: video.id,
                title: this.cleanMovieTitle(video.title),
                original_title: video.title,
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
            try {
                const tmdbData = await this.enrichWithTMDB(movieData.title)
                if (tmdbData) {
                    Object.assign(movieData, tmdbData)
                    logger.debug(`Enhanced with TMDB data: ${tmdbData.title}`)
                }
            } catch (tmdbError) {
                logger.warn(`TMDB enrichment failed for "${movieData.title}":`, tmdbError.message)
            }

            // Determine category
            movieData.category = this.categorizeMovie(movieData)

            // Create movie in database
            const movie = await dbOperations.createMovie(movieData)

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

    cleanMovieTitle(title) {
        return title
            // Remove common movie indicators
            .replace(/\b(full movie|complete film|full film|feature film)\b/gi, '')
            // Remove years in parentheses
            .replace(/\(\d{4}\)/g, '')
            // Remove brackets and their content
            .replace(/\[.*?\]/g, '')
            // Remove quality indicators
            .replace(/\b(HD|4K|1080p|720p|480p)\b/gi, '')
            // Remove extra whitespace
            .replace(/\s+/g, ' ')
            .trim()
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

            // Search for movie in TMDB
            const searchResults = await tmdbService.searchMovies(movieTitle)

            if (!searchResults || searchResults.length === 0) {
                return null
            }

            // Get the most likely match (first result)
            const tmdbMovie = searchResults[0]

            // Get detailed movie info
            const movieDetails = await tmdbService.getMovieDetails(tmdbMovie.id)

            // Return TMDB data WITHOUT genres (genres are handled separately via addMovieGenres)
            return {
                tmdb_id: movieDetails.id,
                imdb_id: movieDetails.imdb_id,
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

            await dbOperations.supabase
                .from('movie_genres')
                .insert(genreRelations)

        } catch (error) {
            logger.error(`Failed to add genres for movie ${movieId}:`, error.message)
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