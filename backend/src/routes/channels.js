import express from 'express'
import { logger } from '../utils/logger.js'

const router = express.Router()

// GET /api/channels
router.get('/', async (req, res) => {
    try {
        res.json({
            success: true,
            data: [],
            message: 'Channels endpoint (coming soon)'
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