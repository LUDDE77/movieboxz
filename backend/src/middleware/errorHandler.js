import { logger } from '../utils/logger.js'

export const errorHandler = (err, req, res, next) => {
    logger.error('API Error:', {
        error: err.message,
        stack: err.stack,
        url: req.url,
        method: req.method,
        ip: req.ip,
        userAgent: req.get('User-Agent')
    })

    // Default error
    let error = {
        message: 'Internal server error',
        status: 500,
        code: 'INTERNAL_ERROR'
    }

    // Supabase/PostgreSQL errors
    if (err.code === '23505') {
        error = {
            message: 'Duplicate entry - this resource already exists',
            status: 409,
            code: 'DUPLICATE_ENTRY'
        }
    } else if (err.code === '23503') {
        error = {
            message: 'Referenced resource not found',
            status: 404,
            code: 'FOREIGN_KEY_VIOLATION'
        }
    } else if (err.code === 'PGRST116') {
        error = {
            message: 'Resource not found',
            status: 404,
            code: 'NOT_FOUND'
        }
    }

    // YouTube API errors
    if (err.message?.includes('quotaExceeded')) {
        error = {
            message: 'YouTube API quota exceeded, please try again later',
            status: 429,
            code: 'YOUTUBE_QUOTA_EXCEEDED'
        }
    } else if (err.message?.includes('videoNotFound')) {
        error = {
            message: 'YouTube video not found or no longer available',
            status: 404,
            code: 'YOUTUBE_VIDEO_NOT_FOUND'
        }
    }

    // TMDB API errors
    if (err.message?.includes('TMDB')) {
        error = {
            message: 'Movie database service temporarily unavailable',
            status: 503,
            code: 'TMDB_SERVICE_ERROR'
        }
    }

    // Validation errors
    if (err.name === 'ValidationError') {
        error = {
            message: err.message,
            status: 400,
            code: 'VALIDATION_ERROR',
            details: err.details
        }
    }

    // JWT errors
    if (err.name === 'JsonWebTokenError') {
        error = {
            message: 'Invalid authentication token',
            status: 401,
            code: 'INVALID_TOKEN'
        }
    } else if (err.name === 'TokenExpiredError') {
        error = {
            message: 'Authentication token expired',
            status: 401,
            code: 'TOKEN_EXPIRED'
        }
    }

    // Rate limiting errors
    if (err.type === 'entity.too.large') {
        error = {
            message: 'Request payload too large',
            status: 413,
            code: 'PAYLOAD_TOO_LARGE'
        }
    }

    // Send error response
    res.status(error.status).json({
        success: false,
        error: error.code,
        message: error.message,
        ...(error.details && { details: error.details }),
        ...(process.env.NODE_ENV === 'development' && {
            stack: err.stack,
            originalError: err.message
        }),
        timestamp: new Date().toISOString(),
        requestId: req.id || 'unknown'
    })
}