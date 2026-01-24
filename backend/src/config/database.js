import { createClient } from '@supabase/supabase-js'
import { logger } from '../utils/logger.js'

// Initialize Supabase client
const supabaseUrl = process.env.SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_KEY
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseServiceKey) {
    logger.error('Missing required Supabase environment variables')
    process.exit(1)
}

// Service client (for backend operations)
export const supabase = createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    }
})

// Public client (for user-facing operations)
export const supabasePublic = createClient(supabaseUrl, supabaseAnonKey)

// Database connection test
export const testDatabaseConnection = async () => {
    try {
        logger.info(`Testing database connection to: ${supabaseUrl}`)

        const { data, error } = await supabase
            .from('movies')
            .select('id')
            .limit(1)

        if (error) {
            logger.error('❌ Database connection failed - Supabase error:', {
                message: error.message,
                details: error.details,
                hint: error.hint,
                code: error.code,
                full: JSON.stringify(error)
            })
            throw error
        }

        logger.info('✅ Database connection successful', { data })
        return true
    } catch (error) {
        logger.error('❌ Database connection failed - Exception:', {
            name: error.name,
            message: error.message,
            code: error.code,
            stack: error.stack?.split('\n').slice(0, 3).join('\n')
        })
        return false
    }
}

// Common database operations
export const dbOperations = {
    // Movies
    async getMovies(filters = {}, limit = 20, offset = 0) {
        let query = supabase
            .from('movies')
            .select(`
                *,
                channels(id, title, thumbnail_url),
                movie_genres(genres(id, name))
            `)
            .eq('is_available', true)

        // Apply filters
        if (filters.category) {
            query = query.eq('category', filters.category)
        }

        if (filters.featured) {
            query = query.eq('featured', true)
        }

        if (filters.trending) {
            query = query.eq('trending', true)
        }

        if (filters.channelId) {
            query = query.eq('channel_id', filters.channelId)
        }

        if (filters.search) {
            query = query.textSearch('search_vector', filters.search)
        }

        // Sorting
        const sortBy = filters.sortBy || 'added_at'
        const sortOrder = filters.sortOrder || 'desc'
        query = query.order(sortBy, { ascending: sortOrder === 'asc' })

        // Pagination
        if (limit) {
            query = query.range(offset, offset + limit - 1)
        }

        const { data, error, count } = await query

        if (error) {
            throw error
        }

        // Transform data to flatten nested structures for iOS compatibility
        const transformedMovies = (data || []).map(movie => {
            const { channels, movie_genres, ...movieData } = movie
            return {
                ...movieData,
                channel_title: channels?.title || null,
                channel_thumbnail: channels?.thumbnail_url || null,
                genres: movie_genres?.map(mg => mg.genres) || []
            }
        })

        return {
            movies: transformedMovies,
            total: count,
            limit,
            offset
        }
    },

    async getMovieById(id) {
        const { data, error } = await supabase
            .from('movies')
            .select(`
                *,
                channels(*),
                movie_genres(genres(*)),
                movie_people(*)
            `)
            .eq('id', id)
            .single()

        if (error) {
            throw error
        }

        // Transform data to flatten nested structures for iOS compatibility
        const { channels, movie_genres, ...movieData } = data
        return {
            ...movieData,
            channel_title: channels?.title || null,
            channel_thumbnail: channels?.thumbnail_url || null,
            genres: movie_genres?.map(mg => mg.genres) || []
        }
    },

    async getMovieByYouTubeId(youtubeVideoId) {
        const { data, error } = await supabase
            .from('movies')
            .select(`
                *,
                channels(*),
                movie_genres(genres(*))
            `)
            .eq('youtube_video_id', youtubeVideoId)
            .single()

        if (error) {
            throw error
        }

        // Transform data to flatten nested structures for iOS compatibility
        const { channels, movie_genres, ...movieData } = data
        return {
            ...movieData,
            channel_title: channels?.title || null,
            channel_thumbnail: channels?.thumbnail_url || null,
            genres: movie_genres?.map(mg => mg.genres) || []
        }
    },

    async createMovie(movieData) {
        const { data, error } = await supabase
            .from('movies')
            .insert([movieData])
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async updateMovie(id, updateData) {
        const { data, error } = await supabase
            .from('movies')
            .update({
                ...updateData,
                updated_at: new Date().toISOString()
            })
            .eq('id', id)
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async updateMovieStats(youtubeVideoId, stats) {
        const { data, error } = await supabase
            .from('movies')
            .update({
                view_count: stats.viewCount,
                like_count: stats.likeCount,
                comment_count: stats.commentCount,
                last_validated: new Date().toISOString(),
                updated_at: new Date().toISOString()
            })
            .eq('youtube_video_id', youtubeVideoId)
            .select()

        if (error) {
            throw error
        }

        return data
    },

    // Channels
    async getChannels(limit = 50, offset = 0) {
        const { data, error } = await supabase
            .from('channels')
            .select('*')
            .order('subscriber_count', { ascending: false })
            .range(offset, offset + limit - 1)

        if (error) {
            throw error
        }

        return data || []
    },

    async getChannelById(channelId) {
        const { data, error } = await supabase
            .from('channels')
            .select('*')
            .eq('id', channelId)
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async createChannel(channelData) {
        const { data, error } = await supabase
            .from('channels')
            .insert([channelData])
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async updateChannel(channelId, updateData) {
        const { data, error } = await supabase
            .from('channels')
            .update({
                ...updateData,
                updated_at: new Date().toISOString()
            })
            .eq('id', channelId)
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    // Genres
    async getGenres() {
        const { data, error } = await supabase
            .from('genres')
            .select('*')
            .order('name')

        if (error) {
            throw error
        }

        return data || []
    },

    async getGenresWithCounts() {
        const { data, error } = await supabase
            .from('genres')
            .select(`
                id,
                tmdb_id,
                name,
                movie_genres(count)
            `)
            .order('name')

        if (error) {
            throw error
        }

        // Transform to include movie_count
        return (data || []).map(genre => ({
            id: genre.id,
            tmdb_id: genre.tmdb_id,
            name: genre.name,
            movie_count: genre.movie_genres?.[0]?.count || 0
        }))
    },

    async getGenreById(genreId) {
        const { data, error } = await supabase
            .from('genres')
            .select(`
                id,
                tmdb_id,
                name,
                movie_genres(count)
            `)
            .eq('id', genreId)
            .single()

        if (error) {
            if (error.code === 'PGRST116') {
                return null // Not found
            }
            throw error
        }

        // Add movie count
        return {
            id: data.id,
            tmdb_id: data.tmdb_id,
            name: data.name,
            movie_count: data.movie_genres?.[0]?.count || 0
        }
    },

    async getMoviesByGenre(genreId, limit = 20, offset = 0, sortBy = 'view_count', sortOrder = 'desc') {
        // Get movies that have this genre
        let query = supabase
            .from('movie_genres')
            .select(`
                movies!inner(
                    *,
                    channels(id, title, thumbnail_url),
                    movie_genres(genres(id, name))
                )
            `, { count: 'exact' })
            .eq('genre_id', genreId)
            .eq('movies.is_available', true)

        // Apply sorting on the movies relation
        query = query.order(sortBy, {
            foreignTable: 'movies',
            ascending: sortOrder === 'asc'
        })

        // Pagination
        query = query.range(offset, offset + limit - 1)

        const { data, error, count } = await query

        if (error) {
            throw error
        }

        // Extract and transform movies from the junction table
        const movies = (data || []).map(item => {
            const movie = item.movies
            const { channels, movie_genres, ...movieData } = movie
            return {
                ...movieData,
                channel_title: channels?.title || null,
                channel_thumbnail: channels?.thumbnail_url || null,
                genres: movie_genres?.map(mg => mg.genres) || []
            }
        })

        return {
            movies,
            total: count,
            limit,
            offset
        }
    },

    // User operations
    async getUserProfile(userId) {
        const { data, error } = await supabase
            .from('user_profiles')
            .select('*')
            .eq('id', userId)
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async getUserFavorites(userId, limit = 50) {
        const { data, error } = await supabase
            .from('user_favorites')
            .select(`
                *,
                movies(*)
            `)
            .eq('user_id', userId)
            .order('added_at', { ascending: false })
            .limit(limit)

        if (error) {
            throw error
        }

        return data || []
    },

    async addToFavorites(userId, movieId) {
        const { data, error } = await supabase
            .from('user_favorites')
            .insert([{
                user_id: userId,
                movie_id: movieId
            }])
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async removeFromFavorites(userId, movieId) {
        const { error } = await supabase
            .from('user_favorites')
            .delete()
            .eq('user_id', userId)
            .eq('movie_id', movieId)

        if (error) {
            throw error
        }

        return true
    },

    // Watch history
    async updateWatchHistory(userId, movieId, progressData) {
        const { data, error } = await supabase
            .from('watch_history')
            .upsert({
                user_id: userId,
                movie_id: movieId,
                ...progressData
            })
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async getWatchHistory(userId, limit = 50) {
        const { data, error } = await supabase
            .from('watch_history')
            .select(`
                *,
                movies(*)
            `)
            .eq('user_id', userId)
            .order('last_watched_at', { ascending: false })
            .limit(limit)

        if (error) {
            throw error
        }

        return data || []
    },

    // API usage tracking
    async logApiUsage(service, endpoint, method, quotaCost = 1, responseStatus = 200, responseTime = 0, error = null) {
        const { data, error: logError } = await supabase
            .from('api_usage')
            .insert([{
                service,
                endpoint,
                method,
                quota_cost: quotaCost,
                response_status: responseStatus,
                response_time_ms: responseTime,
                error_message: error
            }])

        if (logError) {
            logger.error('Failed to log API usage:', logError)
        }

        return data
    },

    // Collections
    async getCollections(isPublic = true) {
        const { data, error } = await supabase
            .from('movie_collections')
            .select(`
                *,
                collection_movies(
                    sort_order,
                    movies(*)
                )
            `)
            .eq('is_public', isPublic)
            .order('sort_order')

        if (error) {
            throw error
        }

        return data || []
    },

    // Curation Jobs
    async createCurationJob(jobData) {
        const { data, error } = await supabase
            .from('curation_jobs')
            .insert([{
                job_type: jobData.jobType || 'channel_scan',
                status: 'pending',
                channel_id: jobData.channelId,
                total_items: 0,
                processed_items: 0,
                successful_items: 0,
                failed_items: 0,
                result_summary: jobData.resultSummary || {},
                error_log: []
            }])
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async getCurationJob(jobId) {
        const { data, error } = await supabase
            .from('curation_jobs')
            .select(`
                *,
                channels(id, title)
            `)
            .eq('id', jobId)
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async getCurationJobs(filters = {}, limit = 50, offset = 0) {
        let query = supabase
            .from('curation_jobs')
            .select(`
                *,
                channels(id, title)
            `)

        if (filters.status) {
            query = query.eq('status', filters.status)
        }

        if (filters.jobType) {
            query = query.eq('job_type', filters.jobType)
        }

        if (filters.channelId) {
            query = query.eq('channel_id', filters.channelId)
        }

        query = query
            .order('created_at', { ascending: false })
            .range(offset, offset + limit - 1)

        const { data, error } = await query

        if (error) {
            throw error
        }

        return data || []
    },

    async updateCurationJob(jobId, updateData) {
        const { data, error } = await supabase
            .from('curation_jobs')
            .update(updateData)
            .eq('id', jobId)
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async startCurationJob(jobId) {
        const { data, error } = await supabase
            .from('curation_jobs')
            .update({
                status: 'running',
                started_at: new Date().toISOString()
            })
            .eq('id', jobId)
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async completeCurationJob(jobId, results) {
        const { data, error } = await supabase
            .from('curation_jobs')
            .update({
                status: results.errors && results.errors.length > 0 ? 'completed' : 'completed',
                completed_at: new Date().toISOString(),
                total_items: results.moviesFound || 0,
                processed_items: results.moviesFound || 0,
                successful_items: results.moviesAdded || 0,
                failed_items: (results.moviesFound || 0) - (results.moviesAdded || 0),
                result_summary: results,
                error_log: results.errors || []
            })
            .eq('id', jobId)
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async failCurationJob(jobId, errorMessage) {
        const { data, error } = await supabase
            .from('curation_jobs')
            .update({
                status: 'failed',
                completed_at: new Date().toISOString(),
                error_log: [errorMessage]
            })
            .eq('id', jobId)
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async updateCurationJobProgress(jobId, progress) {
        const { data, error } = await supabase
            .from('curation_jobs')
            .update({
                processed_items: progress.processed || 0,
                successful_items: progress.successful || 0,
                failed_items: progress.failed || 0
            })
            .eq('id', jobId)
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    }
}

// Alias for backwards compatibility with health.js
export const testConnection = testDatabaseConnection

export default supabase