import express from 'express'
import { logger } from '../utils/logger.js'
import { pool } from '../config/database.js'

const router = express.Router()

// GET /api/channels - List all channels with movie counts
router.get('/', async (req, res) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 50
        const offset = (page - 1) * limit

        // Get total count
        const countResult = await pool.query('SELECT COUNT(*) FROM channels')
        const total = parseInt(countResult.rows[0].count)

        // Get channels with movie counts
        const result = await pool.query(`
            SELECT
                c.id,
                c.title,
                COUNT(m.id) as movie_count,
                MAX(m.created_at) as last_curated
            FROM channels c
            LEFT JOIN movies m ON m.channel_id = c.id
            GROUP BY c.id, c.title
            ORDER BY movie_count DESC
            LIMIT $1 OFFSET $2
        `, [limit, offset])

        const channels = result.rows.map(row => ({
            id: row.id,
            title: row.title,
            movie_count: parseInt(row.movie_count),
            last_curated: row.last_curated
        }))

        res.json({
            success: true,
            data: {
                channels,
                pagination: {
                    page,
                    limit,
                    total,
                    pages: Math.ceil(total / limit)
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