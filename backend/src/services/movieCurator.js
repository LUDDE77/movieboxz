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

        logger.info(`✅ Curation completed: ${results.moviesAdded} movies added from ${results.channelsProcessed} channels`)

        return results
    }

    async curateChannelMovies(channelId) {
        logger.info(`🔍 Curating movies from channel: ${channelId}`)

        const results = {
            channelId: channelId,
            moviesFound: 0,
            moviesAdded: 0,
            moviesSkipped: 0,
            errors: []
        }

        try {
            // Fetch channel info and ensure it's in database
            const channelInfo = await youtubeService.getChannelInfo(channelId)

            try {
                const existingChannel = await dbOperations.getChannelById(channelId).catch(() => null)

                if (existingChannel) {
                    await dbOperations.updateChannel(channelId, {
                        title: channelInfo.title,
                        description: channelInfo.description,
                        thumbnail_url: channelInfo.thumbnailUrl,
                        banner_url: channelInfo.bannerUrl,
                        subscriber_count: channelInfo.subscriberCount,
                        view_count: channelInfo.viewCount,
                        video_count: channelInfo.videoCount,
                        is_verified: channelInfo.isVerified,
                        country: channelInfo.country
                    })
                } else {
                    await dbOperations.createChannel({
                        id: channelInfo.id,
                        title: channelInfo.title,
                        description: channelInfo.description,
                        thumbnail_url: channelInfo.thumbnailUrl,
                        banner_url: channelInfo.bannerUrl,
                        subscriber_count: channelInfo.subscriberCount,
                        view_count: channelInfo.viewCount,
                        video_count: channelInfo.videoCount,
                        is_verified: channelInfo.isVerified,
                        country: channelInfo.country
                    })
                }
            } catch (error) {
                logger.error('Error saving channel info:', error.message)
                // Continue even if channel save fails
            }

            // Fetch videos from channel
            const videos = await youtubeService.getChannelVideos(channelId, {
                maxResults: 50,
                order: 'date'
            })

            logger.info(`Found ${videos.length} videos to process`)

            // Process each video
            for (const video of videos) {
                try {
                    if (this.isLikelyMovie(video)) {
                        results.moviesFound++

                        // Check if movie already exists
                        try {
                            await dbOperations.getMovieByYouTubeId(video.id)
                            results.moviesSkipped++
                            logger.info(`⏭️ Skipped (already exists): ${video.title}`)
                            continue
                        } catch (error) {
                            // Movie doesn't exist, continue processing
                        }

                        // Process and add movie
                        const success = await this.processMovie(video)
                        if (success) {
                            results.moviesAdded++
                            logger.info(`✅ Added: ${video.title}`)
                        } else {
                            results.errors.push({
                                videoId: video.id,
                                title: video.title,
                                error: 'Failed to process movie'
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

        } catch (error) {
            logger.error(`Error curating channel ${channelId}:`, error.message)
            throw error
        }

        logger.info(`Channel curation complete: ${results.moviesAdded}/${results.moviesFound} movies added`)

        return results
    }

    async processMovie(video) {
        try {
            logger.info(`Processing movie: ${video.title}`)

            // Clean up title
            const cleanTitle = this.cleanMovieTitle(video.title)

            // Determine quality
            const quality = this.determineVideoQuality(video)

            // Categorize movie
            const category = this.categorizeMovie(video)

            // Parse duration
            const durationMinutes = youtubeService.parseDuration(video.duration)

            // Extract year from title if possible
            const yearMatch = video.title.match(/\((\d{4})\)/)
            const releaseYear = yearMatch ? parseInt(yearMatch[1]) : null

            // Prepare movie data
            const movieData = {
                title: cleanTitle,
                original_title: video.title,
                description: video.description || null,
                youtube_video_id: video.id,
                channel_id: video.channelId,
                duration: durationMinutes,
                release_year: releaseYear,
                category: category,
                quality: quality,
                view_count: video.viewCount,
                like_count: video.likeCount,
                comment_count: video.commentCount,
                published_at: video.publishedAt,
                thumbnail_url: video.thumbnails?.high?.url || video.thumbnails?.medium?.url || video.thumbnails?.default?.url,
                is_available: true,
                is_embeddable: video.embeddable,
                added_at: new Date().toISOString()
            }

            // Try to enrich with TMDB data
            try {
                const tmdbData = await this.enrichWithTMDB(cleanTitle, releaseYear)
                if (tmdbData) {
                    Object.assign(movieData, tmdbData)
                }
            } catch (error) {
                logger.warn(`Could not enrich with TMDB: ${error.message}`)
                // Continue without TMDB data
            }

            // Create movie in database
            const movie = await dbOperations.createMovie(movieData)

            // If TMDB data was found, add genres
            if (movieData.tmdb_id && movieData.tmdb_data?.genres) {
                await this.addMovieGenres(movie.id, movieData.tmdb_data.genres)
            }

            logger.info(`✅ Successfully processed: ${cleanTitle}`)
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
            'classic': ['classic', 'vintage', 'golden age', 'old']
        }

        // Try to match genre
        for (const [category, keywords] of Object.entries(genreKeywords)) {
            if (keywords.some(keyword => text.includes(keyword))) {
                return category
            }
        }

        return 'classic' // Default category
    }

    // =============================================================================
    // TMDB INTEGRATION
    // =============================================================================

    async enrichWithTMDB(title, year = null) {
        try {
            // Search for movie on TMDB
            const searchResults = await tmdbService.searchMovie(title, year)

            if (!searchResults || searchResults.length === 0) {
                logger.info(`No TMDB results for: ${title}`)
                return null
            }

            // Get the first result (most likely match)
            const tmdbMovie = searchResults[0]

            // Get full movie details
            const movieDetails = await tmdbService.getMovieDetails(tmdbMovie.id)

            return {
                tmdb_id: movieDetails.id,
                imdb_id: movieDetails.imdb_id,
                title: movieDetails.title || title,
                original_title: movieDetails.original_title,
                description: movieDetails.overview || null,
                release_year: movieDetails.release_date ? new Date(movieDetails.release_date).getFullYear() : null,
                runtime: movieDetails.runtime,
                poster_url: movieDetails.poster_path ? `https://image.tmdb.org/t/p/w500${movieDetails.poster_path}` : null,
                backdrop_url: movieDetails.backdrop_path ? `https://image.tmdb.org/t/p/original${movieDetails.backdrop_path}` : null,
                vote_average: movieDetails.vote_average,
                vote_count: movieDetails.vote_count,
                popularity: movieDetails.popularity,
                language: movieDetails.original_language,
                tmdb_data: movieDetails // Store full TMDB response
            }

        } catch (error) {
            logger.warn(`TMDB enrichment failed for ${title}:`, error.message)
            return null
        }
    }

    async addMovieGenres(movieId, tmdbGenres) {
        try {
            // Get all genres from database
            const allGenres = await dbOperations.getGenres()

            for (const tmdbGenre of tmdbGenres) {
                // Find matching genre in database
                const genre = allGenres.find(g =>
                    g.name.toLowerCase() === tmdbGenre.name.toLowerCase() ||
                    g.tmdb_id === tmdbGenre.id
                )

                if (genre) {
                    // Link movie to genre
                    await supabase
                        .from('movie_genres')
                        .insert({
                            movie_id: movieId,
                            genre_id: genre.id
                        })
                        .onConflict('movie_id,genre_id')
                        .ignore()
                }
            }
        } catch (error) {
            logger.error(`Error adding genres for movie ${movieId}:`, error.message)
        }
    }
}

export const movieCurator = new MovieCurator()
export default movieCurator
