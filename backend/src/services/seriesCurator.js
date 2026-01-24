import { youtubeService } from './youtubeService.js'
import { tmdbService } from './tmdbService.js'
import { dbOperations } from '../config/database.js'
import { logger } from '../utils/logger.js'
import stringSimilarity from 'string-similarity'

class SeriesCurator {
    constructor() {
        // Minimum similarity threshold for episode matching
        this.episodeMatchThreshold = 0.6

        // Episode title patterns to clean
        this.episodePrefixPatterns = [
            /^bonanza\s*[-|]\s*/i,
            /^[a-z\s]+\s*[-|]\s*/i  // Any series name followed by dash/pipe
        ]
    }

    // =============================================================================
    // TMDB-FIRST IMPORT
    // =============================================================================

    /**
     * Import a TV series from TMDB by ID
     * Creates series, seasons, and episodes in database (all episodes start as unavailable)
     */
    async importSeriesFromTMDB(tmdbId, channelId = null) {
        try {
            logger.info(`🎬 Importing TV series from TMDB: ${tmdbId}`)

            // Get full series details from TMDB
            const tmdbData = await tmdbService.getTVSeriesDetails(tmdbId)

            logger.info(`Found series: ${tmdbData.name} (${tmdbData.number_of_seasons} seasons, ${tmdbData.number_of_episodes} episodes)`)

            // Create series in database
            const series = await this.createSeriesInDB(tmdbData, channelId)

            // Create all seasons and episodes
            const seasonsCreated = []
            for (const seasonInfo of tmdbData.seasons) {
                // Skip specials (season 0) for now
                if (seasonInfo.season_number === 0) {
                    logger.debug('Skipping specials (Season 0)')
                    continue
                }

                const season = await this.createSeasonWithEpisodes(
                    series.id,
                    tmdbId,
                    seasonInfo.season_number,
                    channelId
                )

                seasonsCreated.push(season)
            }

            logger.info(`✅ Imported series: ${series.title} (${seasonsCreated.length} seasons created)`)

            return {
                series,
                seasonsCreated: seasonsCreated.length,
                episodesCreated: seasonsCreated.reduce((sum, s) => sum + s.episodeCount, 0)
            }

        } catch (error) {
            logger.error(`Failed to import series ${tmdbId}:`, error.message)
            throw error
        }
    }

    /**
     * Search for series by name and import the best match
     */
    async importSeriesByName(seriesName, channelId = null) {
        try {
            logger.info(`Searching TMDB for series: "${seriesName}"`)

            const searchResults = await tmdbService.searchTVSeries(seriesName)

            if (searchResults.length === 0) {
                throw new Error(`No series found for: ${seriesName}`)
            }

            // Use the first (best) result
            const bestMatch = searchResults[0]
            logger.info(`Best match: ${bestMatch.name} (TMDB ID: ${bestMatch.id})`)

            return await this.importSeriesFromTMDB(bestMatch.id, channelId)

        } catch (error) {
            logger.error(`Failed to import series by name "${seriesName}":`, error.message)
            throw error
        }
    }

    // =============================================================================
    // DATABASE OPERATIONS
    // =============================================================================

    async createSeriesInDB(tmdbData, channelId = null) {
        try {
            // Check if series already exists
            const existing = await dbOperations.query(
                'SELECT id FROM tv_series WHERE tmdb_id = $1',
                [tmdbData.id]
            )

            if (existing.rows.length > 0) {
                logger.info(`Series already exists: ${tmdbData.name}`)
                return existing.rows[0]
            }

            // Prepare series data
            const seriesData = {
                tmdb_id: tmdbData.id,
                title: tmdbData.name,
                original_title: tmdbData.original_name,
                description: tmdbData.overview,
                tagline: tmdbData.tagline,
                first_air_date: tmdbData.first_air_date,
                last_air_date: tmdbData.last_air_date,
                status: tmdbData.status,
                channel_id: channelId,
                tmdb_data: tmdbData,
                poster_path: tmdbData.poster_path,
                backdrop_path: tmdbData.backdrop_path,
                vote_average: tmdbData.vote_average,
                vote_count: tmdbData.vote_count,
                popularity: tmdbData.popularity,
                number_of_seasons: tmdbData.number_of_seasons,
                number_of_episodes: tmdbData.number_of_episodes,
                episode_run_time: tmdbData.episode_run_time,
                category: this.categorizeSeries(tmdbData),
                language: tmdbData.original_language || 'en',
                origin_country: tmdbData.origin_country,
                content_rating: tmdbData.content_rating,
                featured: false,
                trending: false,
                staff_pick: false,
                is_available: false  // Will be true once episodes are linked
            }

            // Insert series
            const result = await dbOperations.query(
                `INSERT INTO tv_series (
                    tmdb_id, title, original_title, description, tagline,
                    first_air_date, last_air_date, status, channel_id,
                    tmdb_data, poster_path, backdrop_path,
                    vote_average, vote_count, popularity,
                    number_of_seasons, number_of_episodes, episode_run_time,
                    category, language, origin_country, content_rating,
                    featured, trending, staff_pick, is_available
                ) VALUES (
                    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
                    $13, $14, $15, $16, $17, $18, $19, $20, $21, $22,
                    $23, $24, $25, $26
                ) RETURNING *`,
                [
                    seriesData.tmdb_id, seriesData.title, seriesData.original_title,
                    seriesData.description, seriesData.tagline,
                    seriesData.first_air_date, seriesData.last_air_date,
                    seriesData.status, seriesData.channel_id,
                    JSON.stringify(seriesData.tmdb_data),
                    seriesData.poster_path, seriesData.backdrop_path,
                    seriesData.vote_average, seriesData.vote_count, seriesData.popularity,
                    seriesData.number_of_seasons, seriesData.number_of_episodes,
                    seriesData.episode_run_time,
                    seriesData.category, seriesData.language, seriesData.origin_country,
                    seriesData.content_rating, seriesData.featured, seriesData.trending,
                    seriesData.staff_pick, seriesData.is_available
                ]
            )

            const series = result.rows[0]

            // Add genres
            if (tmdbData.genres && tmdbData.genres.length > 0) {
                await this.addSeriesGenres(series.id, tmdbData.genres)
            }

            // Add cast/crew
            if (tmdbData.credits) {
                await this.addSeriesPeople(series.id, tmdbData.credits)
            }

            return series

        } catch (error) {
            logger.error('Failed to create series in database:', error.message)
            throw error
        }
    }

    async createSeasonWithEpisodes(seriesId, tmdbSeriesId, seasonNumber, channelId = null) {
        try {
            logger.debug(`Creating season ${seasonNumber} for series ${seriesId}`)

            // Get season details from TMDB
            const seasonData = await tmdbService.getSeasonDetails(tmdbSeriesId, seasonNumber)

            // Check if season exists
            const existingSeason = await dbOperations.query(
                'SELECT id FROM seasons WHERE series_id = $1 AND season_number = $2',
                [seriesId, seasonNumber]
            )

            let season
            if (existingSeason.rows.length > 0) {
                season = existingSeason.rows[0]
                logger.debug(`Season ${seasonNumber} already exists`)
            } else {
                // Create season
                const seasonResult = await dbOperations.query(
                    `INSERT INTO seasons (
                        series_id, season_number, title, description, air_date,
                        tmdb_season_id, tmdb_data, poster_path, vote_average
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                    RETURNING *`,
                    [
                        seriesId,
                        seasonData.season_number,
                        seasonData.name,
                        seasonData.overview,
                        seasonData.air_date,
                        seasonData.id,
                        JSON.stringify(seasonData),
                        seasonData.poster_path,
                        seasonData.vote_average
                    ]
                )

                season = seasonResult.rows[0]
            }

            // Create episodes
            let episodesCreated = 0
            for (const episodeData of seasonData.episodes) {
                const created = await this.createEpisodeInDB(
                    seriesId,
                    season.id,
                    episodeData,
                    channelId
                )

                if (created) episodesCreated++
            }

            logger.info(`Created season ${seasonNumber} with ${episodesCreated} episodes`)

            return {
                season,
                episodeCount: episodesCreated
            }

        } catch (error) {
            logger.error(`Failed to create season ${seasonNumber}:`, error.message)
            throw error
        }
    }

    async createEpisodeInDB(seriesId, seasonId, episodeData, channelId = null) {
        try {
            // Check if episode exists
            const existing = await dbOperations.query(
                `SELECT id FROM episodes
                 WHERE series_id = $1 AND season_number = $2 AND episode_number = $3`,
                [seriesId, episodeData.season_number, episodeData.episode_number]
            )

            if (existing.rows.length > 0) {
                return false
            }

            // Create episode (without YouTube link yet)
            await dbOperations.query(
                `INSERT INTO episodes (
                    series_id, season_id, season_number, episode_number,
                    title, description, air_date, runtime_minutes,
                    tmdb_episode_id, tmdb_data, still_path,
                    vote_average, vote_count, channel_id,
                    is_available, last_validated
                ) VALUES (
                    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NOW()
                )`,
                [
                    seriesId,
                    seasonId,
                    episodeData.season_number,
                    episodeData.episode_number,
                    episodeData.name,
                    episodeData.overview,
                    episodeData.air_date,
                    episodeData.runtime,
                    episodeData.id,
                    JSON.stringify(episodeData),
                    episodeData.still_path,
                    episodeData.vote_average,
                    episodeData.vote_count,
                    channelId,
                    false  // Not available until YouTube video linked
                ]
            )

            return true

        } catch (error) {
            logger.error(`Failed to create episode S${episodeData.season_number}E${episodeData.episode_number}:`, error.message)
            return false
        }
    }

    // =============================================================================
    // YOUTUBE LINKING
    // =============================================================================

    /**
     * Link YouTube videos from a channel to existing episodes
     * Uses fuzzy matching to match video titles to episode titles
     */
    async linkYouTubeEpisodes(seriesId, channelId, options = {}) {
        try {
            const {
                autoConfirm = false,
                dryRun = false
            } = options

            logger.info(`🔗 Linking YouTube episodes for series ${seriesId} from channel ${channelId}`)

            // Get all unlinked episodes for this series
            const unlinkedEpisodes = await dbOperations.query(
                `SELECT id, season_number, episode_number, title
                 FROM episodes
                 WHERE series_id = $1 AND youtube_video_id IS NULL
                 ORDER BY season_number, episode_number`,
                [seriesId]
            )

            logger.info(`Found ${unlinkedEpisodes.rows.length} unlinked episodes`)

            // Get videos from YouTube channel
            const videos = await youtubeService.getChannelVideos(channelId, {
                maxResults: 500,
                order: 'date'
            })

            logger.info(`Found ${videos.length} videos in channel`)

            // Match episodes to videos
            const matches = []
            for (const episode of unlinkedEpisodes.rows) {
                const match = this.findBestEpisodeMatch(episode, videos)

                if (match) {
                    matches.push({
                        episode,
                        video: match.video,
                        similarity: match.similarity,
                        confidence: match.similarity > 0.8 ? 'high' : 'medium'
                    })
                }
            }

            logger.info(`Found ${matches.length} potential matches`)

            // Apply matches
            let linked = 0
            const results = []

            for (const match of matches) {
                if (match.confidence === 'high' || autoConfirm) {
                    if (!dryRun) {
                        await this.linkEpisodeToYouTube(match.episode.id, match.video)
                        linked++
                    }

                    results.push({
                        ...match,
                        action: dryRun ? 'would_link' : 'linked'
                    })
                } else {
                    results.push({
                        ...match,
                        action: 'requires_confirmation'
                    })
                }
            }

            logger.info(`✅ Linked ${linked} episodes to YouTube videos`)

            return {
                totalEpisodes: unlinkedEpisodes.rows.length,
                totalVideos: videos.length,
                matchesFound: matches.length,
                episodesLinked: linked,
                results
            }

        } catch (error) {
            logger.error('Failed to link YouTube episodes:', error.message)
            throw error
        }
    }

    /**
     * Find best matching video for an episode using fuzzy title matching
     */
    findBestEpisodeMatch(episode, videos) {
        const episodeTitle = this.cleanEpisodeTitle(episode.title)

        let bestMatch = null
        let bestSimilarity = 0

        for (const video of videos) {
            const videoTitle = this.cleanEpisodeTitle(video.title)

            // Calculate similarity
            const similarity = stringSimilarity.compareTwoStrings(
                episodeTitle.toLowerCase(),
                videoTitle.toLowerCase()
            )

            if (similarity > bestSimilarity && similarity >= this.episodeMatchThreshold) {
                bestSimilarity = similarity
                bestMatch = video
            }
        }

        if (bestMatch) {
            return {
                video: bestMatch,
                similarity: bestSimilarity
            }
        }

        return null
    }

    /**
     * Clean episode title for better matching
     */
    cleanEpisodeTitle(title) {
        let cleaned = title

        // Remove common series name prefixes (e.g., "Bonanza | Episode Title")
        for (const pattern of this.episodePrefixPatterns) {
            cleaned = cleaned.replace(pattern, '')
        }

        // Remove episode numbers (S01E01, etc.)
        cleaned = cleaned.replace(/\s*[Ss]\d+[Ee]\d+\s*/g, ' ')

        // Remove extra whitespace
        cleaned = cleaned.replace(/\s+/g, ' ').trim()

        return cleaned
    }

    /**
     * Link an episode to a YouTube video
     */
    async linkEpisodeToYouTube(episodeId, video) {
        try {
            await dbOperations.query(
                `UPDATE episodes SET
                    youtube_video_id = $1,
                    view_count = $2,
                    like_count = $3,
                    comment_count = $4,
                    published_at = $5,
                    is_available = true,
                    is_embeddable = $6,
                    last_validated = NOW()
                 WHERE id = $7`,
                [
                    video.id,
                    video.viewCount || 0,
                    video.likeCount || 0,
                    video.commentCount || 0,
                    video.publishedAt,
                    video.embeddable || true,
                    episodeId
                ]
            )

            logger.debug(`Linked episode ${episodeId} to YouTube video ${video.id}`)
            return true

        } catch (error) {
            logger.error(`Failed to link episode ${episodeId}:`, error.message)
            return false
        }
    }

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    categorizeSeries(tmdbData) {
        // Map TMDB genres to app categories
        const genreMap = {
            10759: 'action',      // Action & Adventure
            16: 'animation',      // Animation
            35: 'comedy',         // Comedy
            80: 'crime',          // Crime
            99: 'documentary',    // Documentary
            18: 'drama',          // Drama
            10751: 'family',      // Family
            10762: 'kids',        // Kids
            9648: 'mystery',      // Mystery
            10763: 'news',        // News
            10764: 'reality',     // Reality
            10765: 'scifi',       // Sci-Fi & Fantasy
            10766: 'soap',        // Soap
            10767: 'talk',        // Talk
            10768: 'war',         // War & Politics
            37: 'western'         // Western
        }

        if (tmdbData.genres && tmdbData.genres.length > 0) {
            const primaryGenre = tmdbData.genres[0]
            return genreMap[primaryGenre.id] || 'other'
        }

        return 'other'
    }

    async addSeriesGenres(seriesId, genres) {
        try {
            for (const genre of genres) {
                // Ensure genre exists
                await dbOperations.query(
                    `INSERT INTO genres (id, name) VALUES ($1, $2)
                     ON CONFLICT (id) DO NOTHING`,
                    [genre.id, genre.name]
                )

                // Link to series
                await dbOperations.query(
                    `INSERT INTO series_genres (series_id, genre_id)
                     VALUES ($1, $2)
                     ON CONFLICT DO NOTHING`,
                    [seriesId, genre.id]
                )
            }
        } catch (error) {
            logger.error('Failed to add series genres:', error.message)
        }
    }

    async addSeriesPeople(seriesId, credits) {
        try {
            // Add cast (top 10)
            const cast = credits.cast.slice(0, 10)
            for (let i = 0; i < cast.length; i++) {
                const person = cast[i]
                await dbOperations.query(
                    `INSERT INTO series_people (
                        series_id, tmdb_person_id, name, role,
                        character_name, profile_path, order_index
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7)
                    ON CONFLICT DO NOTHING`,
                    [
                        seriesId,
                        person.id,
                        person.name,
                        'actor',
                        person.roles?.[0]?.character || null,
                        person.profilePath,
                        i
                    ]
                )
            }

            // Add creators
            const crew = credits.crew.filter(p =>
                p.jobs?.some(j => j.job === 'Creator' || j.job === 'Executive Producer')
            )

            for (const person of crew.slice(0, 5)) {
                await dbOperations.query(
                    `INSERT INTO series_people (
                        series_id, tmdb_person_id, name, role,
                        job, profile_path
                    ) VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT DO NOTHING`,
                    [
                        seriesId,
                        person.id,
                        person.name,
                        'crew',
                        person.jobs?.[0]?.job || 'Producer',
                        person.profilePath
                    ]
                )
            }
        } catch (error) {
            logger.error('Failed to add series people:', error.message)
        }
    }
}

export const seriesCurator = new SeriesCurator()
export default seriesCurator
