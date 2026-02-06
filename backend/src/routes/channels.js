import express from 'express'
import { logger } from '../utils/logger.js'
import { supabase } from '../config/database.js'

const router = express.Router()

// GET /api/channels - List all channels with movie counts
router.get('/', async (req, res) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 50
        const offset = (page - 1) * limit

        // Get channels with movie counts using Supabase
        const { data, error, count } = await supabase
            .from('channels')
            .select(`
                id,
                title,
                movies(count)
            `, { count: 'exact' })
            .range(offset, offset + limit - 1)
            .order('title')

        if (error) throw error

        const channels = (data || []).map(channel => ({
            id: channel.id,
            title: channel.title,
            movie_count: channel.movies?.[0]?.count || 0,
            last_curated: null // Can add this later if needed
        }))

        res.json({
            success: true,
            data: {
                channels,
                pagination: {
                    page,
                    limit,
                    total: count || 0,
                    pages: Math.ceil((count || 0) / limit)
                }
            }
        })
    } catch (error) {
        logger.error('Channels error:', error)
        res.status(500).json({
            success: false,
            error: 'CHANNELS_ERROR',
            message: 'Failed to fetch channels'
        })
    }
})

export default router