import { logger } from '../utils/logger.js'

export const requestLogger = (req, res, next) => {
    const start = Date.now()

    // Generate unique request ID
    req.id = Math.random().toString(36).substr(2, 9)

    // Log request
    logger.info('Request received', {
        id: req.id,
        method: req.method,
        url: req.url,
        userAgent: req.get('User-Agent'),
        ip: req.ip,
        timestamp: new Date().toISOString()
    })

    // Override res.end to log response
    const originalEnd = res.end
    res.end = function(chunk, encoding) {
        const duration = Date.now() - start

        logger.info('Request completed', {
            id: req.id,
            method: req.method,
            url: req.url,
            status: res.statusCode,
            duration: `${duration}ms`,
            timestamp: new Date().toISOString()
        })

        originalEnd.call(res, chunk, encoding)
    }

    next()
}