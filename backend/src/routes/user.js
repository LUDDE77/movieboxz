import express from 'express'
import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// =============================================================================
// AUTHENTICATION MIDDLEWARE
// =============================================================================

/**
 * Validate Supabase JWT token and extract user ID
 * Token should be in format: "Bearer <supabase_jwt>"
 */
const requireAuth = async (req, res, next) => {
    try {
        const authHeader = req.headers.authorization

        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({
                success: false,
                error: 'UNAUTHORIZED',
                message: 'Valid authorization token required'
            })
        }

        const token = authHeader.substring(7) // Remove 'Bearer ' prefix

        // Verify JWT token with Supabase
        const { data: { user }, error } = await supabase.auth.getUser(token)

        if (error || !user) {
            logger.warn('Invalid auth token', { error: error?.message })
            return res.status(401).json({
                success: false,
                error: 'UNAUTHORIZED',
                message: 'Invalid or expired token'
            })
        }

        // Attach user to request
        req.userId = user.id
        req.user = user

        next()
    } catch (error) {
        logger.error('Auth middleware error:', error)
        return res.status(401).json({
            success: false,
            error: 'UNAUTHORIZED',
            message: 'Authentication failed'
        })
    }
}

// =============================================================================
// FAVORITES ENDPOINTS
// =============================================================================

/**
 * GET /api/user/favorites
 * Get user's favorite movies and series
 */
router.get('/favorites', requireAuth, async (req, res, next) => {
    try {
        const limit = parseInt(req.query.limit) || 100
        const offset = parseInt(req.query.offset) || 0

        const { data: favorites, error, count } = await supabase
            .from('user_favorites')
            .select('*', { count: 'exact' })
            .eq('user_id', req.userId)
            .order('priority', { ascending: true })
            .order('added_at', { ascending: false })
            .range(offset, offset + limit - 1)

        if (error) throw error

        res.json({
            success: true,
            data: {
                favorites: favorites.map(fav => ({
                    id: fav.id,
                    contentType: fav.content_type,
                    movieId: fav.movie_id,
                    seriesId: fav.series_id,
                    addedDate: fav.added_at,
                    priority: fav.priority
                })),
                total: count
            }
        })
    } catch (error) {
        next(error)
    }
})

/**
 * POST /api/user/favorites
 * Add movie or series to favorites
 * Body: { movieId: string } OR { seriesId: string }
 */
router.post('/favorites', requireAuth, async (req, res, next) => {
    try {
        const { movieId, seriesId } = req.body

        if (!movieId && !seriesId) {
            return res.status(400).json({
                success: false,
                error: 'BAD_REQUEST',
                message: 'Either movieId or seriesId is required'
            })
        }

        if (movieId && seriesId) {
            return res.status(400).json({
                success: false,
                error: 'BAD_REQUEST',
                message: 'Cannot favorite both movie and series at once'
            })
        }

        const favoriteData = {
            user_id: req.userId,
            content_type: movieId ? 'movie' : 'series',
            movie_id: movieId || null,
            series_id: seriesId || null,
            priority: 0
        }

        const { data: favorite, error } = await supabase
            .from('user_favorites')
            .insert(favoriteData)
            .select()
            .single()

        if (error) {
            if (error.code === '23505') { // Unique constraint violation
                return res.status(409).json({
                    success: false,
                    error: 'DUPLICATE',
                    message: 'Already in favorites'
                })
            }
            throw error
        }

        res.json({
            success: true,
            data: {
                favorite: {
                    id: favorite.id,
                    contentType: favorite.content_type,
                    movieId: favorite.movie_id,
                    seriesId: favorite.series_id,
                    addedDate: favorite.added_at,
                    priority: favorite.priority
                }
            },
            message: 'Added to favorites'
        })
    } catch (error) {
        next(error)
    }
})

/**
 * DELETE /api/user/favorites/:contentType/:contentId
 * Remove from favorites
 * Examples:
 *   DELETE /api/user/favorites/movie/abc123
 *   DELETE /api/user/favorites/series/uuid-here
 */
router.delete('/favorites/:contentType/:contentId', requireAuth, async (req, res, next) => {
    try {
        const { contentType, contentId } = req.params

        if (!['movie', 'series'].includes(contentType)) {
            return res.status(400).json({
                success: false,
                error: 'BAD_REQUEST',
                message: 'contentType must be "movie" or "series"'
            })
        }

        const column = contentType === 'movie' ? 'movie_id' : 'series_id'

        const { error } = await supabase
            .from('user_favorites')
            .delete()
            .eq('user_id', req.userId)
            .eq(column, contentId)

        if (error) throw error

        res.json({
            success: true,
            message: 'Removed from favorites'
        })
    } catch (error) {
        next(error)
    }
})

/**
 * PUT /api/user/favorites/reorder
 * Reorder favorites (for iOS drag-and-drop)
 * Body: { items: [{ id: uuid, priority: number }] }
 */
router.put('/favorites/reorder', requireAuth, async (req, res, next) => {
    try {
        const { items } = req.body

        if (!Array.isArray(items)) {
            return res.status(400).json({
                success: false,
                error: 'BAD_REQUEST',
                message: 'items must be an array'
            })
        }

        // Update priorities in batch
        const updates = items.map(item =>
            supabase
                .from('user_favorites')
                .update({ priority: item.priority })
                .eq('id', item.id)
                .eq('user_id', req.userId) // Security: only update own favorites
        )

        await Promise.all(updates)

        res.json({
            success: true,
            message: 'Favorites reordered',
            updated: items.length
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// WATCH HISTORY ENDPOINTS
// =============================================================================

/**
 * GET /api/user/history
 * Get user's watch history
 */
router.get('/history', requireAuth, async (req, res, next) => {
    try {
        const limit = parseInt(req.query.limit) || 100
        const offset = parseInt(req.query.offset) || 0
        const since = req.query.since // ISO date string

        let query = supabase
            .from('watch_history')
            .select('*', { count: 'exact' })
            .eq('user_id', req.userId)
            .order('last_watched_at', { ascending: false })

        if (since) {
            query = query.gte('last_watched_at', since)
        }

        const { data: history, error, count } = await query
            .range(offset, offset + limit - 1)

        if (error) throw error

        res.json({
            success: true,
            data: {
                history: history.map(item => ({
                    id: item.id,
                    contentType: item.content_type,
                    movieId: item.movie_id,
                    episodeId: item.episode_id,
                    seriesId: item.series_id,
                    firstWatchedAt: item.first_watched_at,
                    lastWatchedAt: item.last_watched_at,
                    watchCount: item.watch_count,
                    platform: item.platform
                })),
                total: count
            }
        })
    } catch (error) {
        next(error)
    }
})

/**
 * POST /api/user/history
 * Track a watch event
 * Body: { movieId: string, platform: 'iOS' | 'tvOS' }
 *    OR { episodeId: string, seriesId: string, platform: 'iOS' | 'tvOS' }
 */
router.post('/history', requireAuth, async (req, res, next) => {
    try {
        const { movieId, episodeId, seriesId, platform } = req.body

        if (!movieId && !episodeId) {
            return res.status(400).json({
                success: false,
                error: 'BAD_REQUEST',
                message: 'Either movieId or episodeId is required'
            })
        }

        if (!platform || !['iOS', 'tvOS', 'web'].includes(platform)) {
            return res.status(400).json({
                success: false,
                error: 'BAD_REQUEST',
                message: 'platform must be iOS, tvOS, or web'
            })
        }

        // Check if already exists
        let query = supabase
            .from('watch_history')
            .select('*')
            .eq('user_id', req.userId)

        if (movieId) {
            query = query.eq('movie_id', movieId)
        } else {
            query = query.eq('episode_id', episodeId)
        }

        const { data: existing } = await query.maybeSingle()

        let historyItem
        if (existing) {
            // Update existing: increment count, update timestamp
            const { data, error } = await supabase
                .from('watch_history')
                .update({
                    last_watched_at: new Date().toISOString(),
                    watch_count: existing.watch_count + 1,
                    platform: platform
                })
                .eq('id', existing.id)
                .select()
                .single()

            if (error) throw error
            historyItem = data
        } else {
            // Insert new
            const { data, error } = await supabase
                .from('watch_history')
                .insert({
                    user_id: req.userId,
                    content_type: movieId ? 'movie' : 'episode',
                    movie_id: movieId || null,
                    episode_id: episodeId || null,
                    series_id: seriesId || null,
                    platform: platform,
                    watch_count: 1
                })
                .select()
                .single()

            if (error) throw error
            historyItem = data
        }

        res.json({
            success: true,
            data: {
                historyItem: {
                    id: historyItem.id,
                    contentType: historyItem.content_type,
                    movieId: historyItem.movie_id,
                    episodeId: historyItem.episode_id,
                    seriesId: historyItem.series_id,
                    firstWatchedAt: historyItem.first_watched_at,
                    lastWatchedAt: historyItem.last_watched_at,
                    watchCount: historyItem.watch_count,
                    platform: historyItem.platform
                }
            },
            message: 'Watch event tracked'
        })
    } catch (error) {
        next(error)
    }
})

/**
 * DELETE /api/user/history/:contentType/:contentId
 * Remove from watch history
 */
router.delete('/history/:contentType/:contentId', requireAuth, async (req, res, next) => {
    try {
        const { contentType, contentId } = req.params

        if (!['movie', 'episode'].includes(contentType)) {
            return res.status(400).json({
                success: false,
                error: 'BAD_REQUEST',
                message: 'contentType must be "movie" or "episode"'
            })
        }

        const column = contentType === 'movie' ? 'movie_id' : 'episode_id'

        const { error } = await supabase
            .from('watch_history')
            .delete()
            .eq('user_id', req.userId)
            .eq(column, contentId)

        if (error) throw error

        res.json({
            success: true,
            message: 'Removed from watch history'
        })
    } catch (error) {
        next(error)
    }
})

/**
 * DELETE /api/user/history
 * Clear all watch history
 */
router.delete('/history', requireAuth, async (req, res, next) => {
    try {
        const { count, error } = await supabase
            .from('watch_history')
            .delete({ count: 'exact' })
            .eq('user_id', req.userId)

        if (error) throw error

        res.json({
            success: true,
            message: 'Watch history cleared',
            deletedCount: count
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// SYNC ENDPOINT
// =============================================================================

/**
 * POST /api/user/sync
 * Sync favorites and history in one request
 * Useful for app launch
 */
router.post('/sync', requireAuth, async (req, res, next) => {
    try {
        const { lastSyncedAt } = req.body

        // Fetch favorites
        let favoritesQuery = supabase
            .from('user_favorites')
            .select('*')
            .eq('user_id', req.userId)
            .order('priority', { ascending: true })

        if (lastSyncedAt) {
            favoritesQuery = favoritesQuery.gte('updated_at', lastSyncedAt)
        }

        // Fetch history
        let historyQuery = supabase
            .from('watch_history')
            .select('*')
            .eq('user_id', req.userId)
            .order('last_watched_at', { ascending: false })
            .limit(100) // Last 100 items

        if (lastSyncedAt) {
            historyQuery = historyQuery.gte('updated_at', lastSyncedAt)
        }

        const [favoritesResult, historyResult] = await Promise.all([
            favoritesQuery,
            historyQuery
        ])

        if (favoritesResult.error) throw favoritesResult.error
        if (historyResult.error) throw historyResult.error

        res.json({
            success: true,
            data: {
                favorites: favoritesResult.data.map(fav => ({
                    id: fav.id,
                    contentType: fav.content_type,
                    movieId: fav.movie_id,
                    seriesId: fav.series_id,
                    addedDate: fav.added_at,
                    priority: fav.priority
                })),
                history: historyResult.data.map(item => ({
                    id: item.id,
                    contentType: item.content_type,
                    movieId: item.movie_id,
                    episodeId: item.episode_id,
                    seriesId: item.series_id,
                    firstWatchedAt: item.first_watched_at,
                    lastWatchedAt: item.last_watched_at,
                    watchCount: item.watch_count,
                    platform: item.platform
                })),
                syncedAt: new Date().toISOString()
            }
        })
    } catch (error) {
        next(error)
    }
})

// =============================================================================
// CONTINUE WATCHING ENDPOINT
// =============================================================================

/**
 * GET /api/user/continue-watching
 * Get recently watched content (for "Continue Watching" row)
 * Returns items watched in last 7 days with watch_count <= 2
 */
router.get('/continue-watching', requireAuth, async (req, res, next) => {
    try {
        const sevenDaysAgo = new Date()
        sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)

        const { data: items, error } = await supabase
            .from('watch_history')
            .select('*')
            .eq('user_id', req.userId)
            .gte('last_watched_at', sevenDaysAgo.toISOString())
            .lte('watch_count', 2)
            .order('last_watched_at', { ascending: false })
            .limit(20)

        if (error) throw error

        res.json({
            success: true,
            data: {
                items: items.map(item => ({
                    contentType: item.content_type,
                    movieId: item.movie_id,
                    episodeId: item.episode_id,
                    seriesId: item.series_id,
                    lastWatchedAt: item.last_watched_at,
                    watchCount: item.watch_count
                }))
            }
        })
    } catch (error) {
        next(error)
    }
})

export default router
