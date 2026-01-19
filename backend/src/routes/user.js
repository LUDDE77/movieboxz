import express from 'express'
import { logger } from '../utils/logger.js'

const router = express.Router()

// GET /api/user/profile
router.get('/profile', async (req, res) => {
    try {
        res.json({
            success: true,
            data: null,
            message: 'User profile endpoint (coming soon)'
        })
    } catch (error) {
        logger.error('User profile error:', error)
        res.status(500).json({
            success: false,
            error: 'USER_PROFILE_ERROR',
            message: 'Failed to fetch user profile'
        })
    }
})

export default router