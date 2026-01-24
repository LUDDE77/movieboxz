import { youtubeService } from './youtubeService.js'
import { tmdbService } from './tmdbService.js'
import { supabase } from '../config/database.js'
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
            const { data: existing, error: checkError } = await supabase
                .from('tv_series')
                .select('id')
                .eq('tmdb_id', tmdbData.id)
                .maybeSingle()

            if (checkError) {
                throw new Error(`Error checking for existing series: ${checkError.message}`)
            }

            if (existing) {
                logger.info(`Series already exists: ${tmdbData.name}`)
                return existing
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
                poster_path: tmdbData.poster_path,
                backdrop_path: tmdbData.backdrop_path,
                vote_average: tmdbData.vote_average,
                number_of_seasons: tmdbData.number_of_seasons,
                number_of_episodes: tmdbData.number_of_episodes
            }

            // Insert series
            const { data: series, error: insertError } = await supabase
                .from('tv_series')
                .insert(seriesData)
                .select()
                .single()

            if (insertError) {
                throw new Error(`Failed to create series: ${insertError.message}`)
            }

            // Add genres
            if (tmdbData.genres && tmdbData.genres.length > 0) {
                await this.addSeriesGenres(series.id, tmdbData.genres)
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
            const { data: existingSeason } = await supabase
                .from('seasons')
                .select('id')
                .eq('series_id', seriesId)
                .eq('season_number', seasonNumber)
                .maybeSingle()

            let season
            if (existingSeason) {
                season = existingSeason
                logger.debug(`Season ${seasonNumber} already exists`)
            } else {
                // Create season
                const { data: newSeason, error: seasonError } = await supabase
                    .from('seasons')
                    .insert({
                        series_id: seriesId,
                        season_number: seasonData.season_number,
                        title: seasonData.name,
                        description: seasonData.overview,
                        air_date: seasonData.air_date,
                        poster_path: seasonData.poster_path,
                        episode_count: seasonData.episodes?.length || 0
                    })
                    .select()
                    .single()

                if (seasonError) {
                    throw new Error(`Failed to create season: ${seasonError.message}`)
                }

                season = newSeason
            }

            // Create episodes
            let episodesCreated = 0
            for (const episodeData of seasonData.episodes || []) {
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
            const { data: existing } = await supabase
                .from('episodes')
                .select('id')
                .eq('series_id', seriesId)
                .eq('season_number', episodeData.season_number)
                .eq('episode_number', episodeData.episode_number)
                .maybeSingle()

            if (existing) {
                return false
            }

            // Create episode (without YouTube link yet)
            const { error: insertError } = await supabase
                .from('episodes')
                .insert({
                    series_id: seriesId,
                    season_id: seasonId,
                    season_number: episodeData.season_number,
                    episode_number: episodeData.episode_number,
                    title: episodeData.name,
                    description: episodeData.overview,
                    air_date: episodeData.air_date,
                    runtime_minutes: episodeData.runtime,
                    still_path: episodeData.still_path,
                    vote_average: episodeData.vote_average,
                    youtube_video_id: null,
                    is_available: false  // Not available until YouTube video linked
                })

            if (insertError) {
                throw insertError
            }

            return true

        } catch (error) {
            logger.error(`Failed to create episode S${episodeData.season_number}E${episodeData.episode_number}:`, error.message)
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
                await supabase
                    .from('genres')
                    .upsert({ id: genre.id, name: genre.name }, { onConflict: 'id', ignoreDuplicates: true })

                // Link to series
                await supabase
                    .from('series_genres')
                    .insert({ series_id: seriesId, genre_id: genre.id })
                    .select()
                    // Ignore conflict if already exists
                    .then(result => {
                        if (result.error && !result.error.message.includes('duplicate')) {
                            throw result.error
                        }
                    })
            }
        } catch (error) {
            logger.error('Failed to add series genres:', error.message)
        }
    }
}

export const seriesCurator = new SeriesCurator()
export default seriesCurator
