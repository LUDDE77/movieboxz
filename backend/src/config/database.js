import { createClient } from '@supabase/supabase-js'
import { logger } from '../utils/logger.js'

const supabaseUrl = process.env.SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_KEY
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error('Missing required Supabase environment variables')
}

logger.info('Supabase configuration:', {
    url: supabaseUrl,
    serviceKeyFormat: supabaseServiceKey?.startsWith('sb_secret_') ? 'modern' : 'legacy',
    anonKeyFormat: supabaseAnonKey?.startsWith('sb_publishable_') ? 'modern' : 'legacy'
})

// Service role client for admin operations
export const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    },
    db: {
        schema: 'public'
    },
    global: {
        headers: {
            'apikey': supabaseServiceKey
        }
    }
})

// Anon client for user operations
export const supabase = createClient(supabaseUrl, supabaseAnonKey || supabaseServiceKey, {
    auth: {
        autoRefreshToken: true,
        persistSession: true
    },
    db: {
        schema: 'public'
    }
})

// Test database connection
export const testDatabaseConnection = async () => {
    try {
        logger.info('Testing database connection...')
        
        // Test with service role client first
        const { data, error } = await supabaseAdmin
            .from('movies')
            .select('count')
            .limit(1)

        if (error) {
            logger.error('Database connection test error details:', {
                message: error.message,
                code: error.code,
                hint: error.hint,
                details: error.details
            })
            
            // If service role fails, try with anon client
            const { data: anonData, error: anonError } = await supabase
                .from('movies')
                .select('count')
                .limit(1)
                
            if (anonError) {
                logger.error('Anon client connection also failed:', {
                    message: anonError.message,
                    code: anonError.code,
                    hint: anonError.hint
                })
                return false
            }
            
            logger.info('Anon client connection successful, using fallback')
            return true
        }

        logger.info('Database connection test successful')
        return true
    } catch (error) {
        logger.error('Database connection test failed:', {
            message: error.message,
            stack: error.stack,
            env: {
                url: process.env.SUPABASE_URL,
                serviceKeyExists: !!process.env.SUPABASE_SERVICE_KEY,
                anonKeyExists: !!process.env.SUPABASE_ANON_KEY
            }
        })
        return false
    }
}

// Common database operations
export const dbOperations = {
    // Movies
    async getMovies(filters = {}, limit = 20, offset = 0) {
        let query = supabaseAdmin
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

        return {
            movies: data || [],
            total: count,
            limit,
            offset
        }
    },

    async getMovieById(id) {
        const { data, error } = await supabaseAdmin
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

        return data
    },

    async getMovieByYouTubeId(youtubeVideoId) {
        const { data, error } = await supabaseAdmin
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

        return data
    },

    async createMovie(movieData) {
        const { data, error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
            .from('genres')
            .select('*')
            .order('name')

        if (error) {
            throw error
        }

        return data || []
    },

    // User operations
    async getUserProfile(userId) {
        const { data, error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
        const { error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
        const { data, error: logError } = await supabaseAdmin
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
        const { data, error } = await supabaseAdmin
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
    }
}

export default supabaseAdmin