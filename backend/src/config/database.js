import { createClient } from '@supabase/supabase-js'
import { logger } from '../utils/logger.js'
import dotenv from 'dotenv'

// Load environment variables
dotenv.config()

// Supabase client configuration
const supabaseUrl = process.env.SUPABASE_URL
const supabaseKey = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseKey) {
    logger.error('❌ Supabase credentials missing')
    throw new Error('SUPABASE_URL and SUPABASE_SERVICE_KEY/SUPABASE_ANON_KEY must be set')
}

// Initialize Supabase client
const supabase = createClient(supabaseUrl, supabaseKey, {
    auth: {
        persistSession: false,
        autoRefreshToken: false
    },
    db: {
        schema: 'public'
    }
})

logger.info('✅ Supabase client initialized')

// Test database connection
export async function testConnection() {
    try {
        const { data, error } = await supabase
            .from('movies')
            .select('count', { count: 'exact', head: true })

        if (error) throw error

        logger.info('✅ Database connection successful')
        return true
    } catch (error) {
        logger.error('❌ Database connection failed:', error.message)
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

    async deleteMovie(id) {
        const { error } = await supabase
            .from('movies')
            .delete()
            .eq('id', id)

        if (error) {
            throw error
        }

        return true
    },

    // Channels
    async getChannels(limit = 20, offset = 0) {
        const { data, error, count } = await supabase
            .from('channels')
            .select('*', { count: 'exact' })
            .order('title', { ascending: true })
            .range(offset, offset + limit - 1)

        if (error) {
            throw error
        }

        return {
            channels: data || [],
            total: count,
            limit,
            offset
        }
    },

    async getChannelById(id) {
        const { data, error } = await supabase
            .from('channels')
            .select('*')
            .eq('id', id)
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

    async updateChannel(id, updateData) {
        const { data, error } = await supabase
            .from('channels')
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

    // Users
    async createUser(userData) {
        const { data, error } = await supabase
            .from('users')
            .insert([userData])
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async getUserById(id) {
        const { data, error } = await supabase
            .from('users')
            .select('*')
            .eq('id', id)
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async updateUser(id, updateData) {
        const { data, error } = await supabase
            .from('users')
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

    // Watch History
    async addToWatchHistory(userId, movieId, progress = 0) {
        const { data, error } = await supabase
            .from('watch_history')
            .upsert([
                {
                    user_id: userId,
                    movie_id: movieId,
                    progress,
                    last_watched: new Date().toISOString()
                }
            ], {
                onConflict: 'user_id,movie_id'
            })
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
    },

    async getWatchHistory(userId, limit = 20, offset = 0) {
        const { data, error, count } = await supabase
            .from('watch_history')
            .select(`
                *,
                movies(*)
            `, { count: 'exact' })
            .eq('user_id', userId)
            .order('last_watched', { ascending: false })
            .range(offset, offset + limit - 1)

        if (error) {
            throw error
        }

        return {
            history: data || [],
            total: count,
            limit,
            offset
        }
    },

    // My List
    async addToMyList(userId, movieId) {
        const { data, error } = await supabase
            .from('my_list')
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

    async removeFromMyList(userId, movieId) {
        const { error } = await supabase
            .from('my_list')
            .delete()
            .eq('user_id', userId)
            .eq('movie_id', movieId)

        if (error) {
            throw error
        }

        return true
    },

    async getMyList(userId, limit = 20, offset = 0) {
        const { data, error, count } = await supabase
            .from('my_list')
            .select(`
                *,
                movies(*)
            `, { count: 'exact' })
            .eq('user_id', userId)
            .order('added_at', { ascending: false })
            .range(offset, offset + limit - 1)

        if (error) {
            throw error
        }

        return {
            movies: data?.map(item => item.movies) || [],
            total: count,
            limit,
            offset
        }
    },

    // Curation Jobs
    async createCurationJob(jobData) {
        const { data, error } = await supabase
            .from('curation_jobs')
            .insert([{
                ...jobData,
                status: 'pending',
                created_at: new Date().toISOString()
            }])
            .select()
            .single()

        if (error) {
            throw error
        }

        return data
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

    async getCurationJobs(filters = {}, limit = 20, offset = 0) {
        let query = supabase
            .from('curation_jobs')
            .select(`
                *,
                channels(id, title)
            `, { count: 'exact' })

        // Apply filters
        if (filters.status) {
            query = query.eq('status', filters.status)
        }

        if (filters.jobType) {
            query = query.eq('job_type', filters.jobType)
        }

        if (filters.channelId) {
            query = query.eq('channel_id', filters.channelId)
        }

        // Sort by created_at descending
        query = query.order('created_at', { ascending: false })

        // Pagination
        if (limit) {
            query = query.range(offset, offset + limit - 1)
        }

        const { data, error } = await query

        if (error) {
            throw error
        }
        return data || []
    }
}

export default supabase
