import { createClient } from '@supabase/supabase-js'
import { logger } from '../utils/logger.js'

// Initialize Supabase client for JWT verification
const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY
)

/**
 * Authentication middleware for protecting user-specific routes
 * Validates Supabase JWT tokens and extracts user_id
 */
export const authenticateUser = async (req, res, next) => {
    try {
        // Get token from Authorization header
        const authHeader = req.headers.authorization

        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({
                success: false,
                error: 'Authentication required',
                message: 'Please provide a valid Bearer token in the Authorization header',
                code: 'UNAUTHORIZED'
            })
        }

        // Extract token
        const token = authHeader.substring(7) // Remove 'Bearer ' prefix

        // Verify token with Supabase
        const { data: { user }, error } = await supabase.auth.getUser(token)

        if (error || !user) {
            logger.warn(`Authentication failed: ${error?.message || 'Invalid token'}`)
            return res.status(401).json({
                success: false,
                error: 'Authentication failed',
                message: 'Invalid or expired token',
                code: 'UNAUTHORIZED'
            })
        }

        // Attach user to request object
        req.user = user
        req.userId = user.id

        logger.debug(`Authenticated user: ${user.id}`)

        next()
    } catch (error) {
        logger.error('Authentication error:', error.message)
        return res.status(500).json({
            success: false,
            error: 'Internal server error',
            message: 'Failed to authenticate request',
            code: 'INTERNAL_ERROR'
        })
    }
}

/**
 * Optional authentication middleware
 * Attaches user info if token is present, but doesn't require it
 */
export const optionalAuth = async (req, res, next) => {
    try {
        const authHeader = req.headers.authorization

        if (authHeader && authHeader.startsWith('Bearer ')) {
            const token = authHeader.substring(7)
            const { data: { user } } = await supabase.auth.getUser(token)

            if (user) {
                req.user = user
                req.userId = user.id
                logger.debug(`Optional auth: authenticated user ${user.id}`)
            }
        }

        next()
    } catch (error) {
        // Don't fail on optional auth errors, just log them
        logger.debug('Optional auth failed:', error.message)
        next()
    }
}

export default {
    authenticateUser,
    optionalAuth
}
