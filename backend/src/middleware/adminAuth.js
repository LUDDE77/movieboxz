import { logger } from '../utils/logger.js'

/**
 * Admin API key authentication middleware.
 * Validates the x-admin-api-key header against ADMIN_API_KEY env variable.
 */
export const adminAuth = (req, res, next) => {
    const apiKey = req.headers['x-admin-api-key']

    if (!apiKey || apiKey !== process.env.ADMIN_API_KEY) {
        return res.status(401).json({
            success: false,
            error: 'Unauthorized',
            message: 'Valid admin API key required'
        })
    }

    next()
}

export default adminAuth
