import express from 'express'
import { logger } from '../utils/logger.js'

const router = express.Router()

// GET /api/admin/status
router.get('/status', async (req, res) => {
    try {
        res.json({
            success: true,
            data: {
                status: 'operational',
                version: '1.0.0',
                environment: process.env.NODE_ENV || 'development'
            },
            message: 'Admin status endpoint'
        })
    } catch (error) {
        logger.error('Admin status error:', error)
        res.status(500).json({
            success: false,
            error: 'ADMIN_STATUS_ERROR',
            message: 'Failed to get admin status'
        })
    }
})

export default router