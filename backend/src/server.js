// Load environment variables BEFORE all other imports so that modules reading
// process.env at import time (config/database.js, service constructors) see them
import 'dotenv/config'
// Fail fast on missing required env vars before any other module reads process.env
import './config/checkEnv.js'

import express from 'express'
import cors from 'cors'
import helmet from 'helmet'
import compression from 'compression'
import rateLimit from 'express-rate-limit'
import slowDown from 'express-slow-down'
import crypto from 'crypto'

// Import routes
import moviesRouter from './routes/movies.js'
import channelsRouter from './routes/channels.js'
import channelsAdminRouter from './routes/channelsAdmin.js'
import channelManagementRouter, { sweepZombieImports } from './routes/channelManagement.js'
import browseRouter from './routes/browse.js'
import userRouter from './routes/user.js'
import adminRouter from './routes/admin.js'
import healthRouter from './routes/health.js'
import stagingRouter from './routes/staging-simple.js'
import duplicatesAdminRouter from './routes/duplicatesAdmin.js'
import validationAdminRouter from './routes/validationAdmin.js'
import { tvSeriesAdminRouter } from './routes/tvSeriesAdmin.js'
import seriesRouter from './routes/series.js'
import genresAdminRouter from './routes/genresAdmin.js'

// Import middleware
import { errorHandler } from './middleware/errorHandler.js'
import { requestLogger } from './middleware/requestLogger.js'
import { usageTracker, startUsageFlusher } from './middleware/usageTracker.js'
import { corsConfig } from './config/cors.js'

// Import services
import { logger } from './utils/logger.js'
import { initializeCronJobs } from './services/cronJobs.js'
import jobScheduler from './jobs/scheduler.js'

const app = express()
app.set('trust proxy', 1) // Behind Railway's proxy — needed so req.ip (rate limiting) is the client IP
const port = process.env.PORT || 3000

// =============================================================================
// MIDDLEWARE SETUP
// =============================================================================

// Security middleware
app.use(helmet({
    crossOriginResourcePolicy: { policy: "cross-origin" }
}))

// CORS configuration
app.use(cors(corsConfig))

// Compression
app.use(compression())

// Request parsing
app.use(express.json({ limit: '10mb' }))
app.use(express.urlencoded({ extended: true, limit: '10mb' }))

// Logging (single structured request logger — morgan removed to avoid duplicate log lines)
app.use(requestLogger)
app.use(usageTracker) // privacy-safe aggregate usage counts (no personal data)

// Rate limiting.
// Requests carrying the CORRECT admin key are exempt — admin automation (bulk
// enrichment, imports) legitimately exceeds consumer limits. Invalid keys stay
// rate-limited here and are also throttled by adminAuth's failed-attempt guard.
const hasValidAdminKey = (req) => {
    const provided = req.get('x-admin-api-key')
    const expected = process.env.ADMIN_API_KEY
    if (!provided || !expected) return false
    const a = crypto.createHash('sha256').update(provided).digest()
    const b = crypto.createHash('sha256').update(expected).digest()
    return crypto.timingSafeEqual(a, b)
}

const limiter = rateLimit({
    windowMs: parseInt(process.env.API_RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000, // 15 minutes
    max: parseInt(process.env.API_RATE_LIMIT_MAX_REQUESTS) || 100, // limit each IP to 100 requests per windowMs
    message: {
        error: 'Too many requests from this IP, please try again later.',
        code: 'RATE_LIMIT_EXCEEDED'
    },
    standardHeaders: true,
    legacyHeaders: false,
    skip: hasValidAdminKey
})

const speedLimiter = slowDown({
    windowMs: 15 * 60 * 1000, // 15 minutes
    delayAfter: 50, // allow 50 requests per 15 minutes, then...
    delayMs: () => 500, // add a flat 500ms of delay per request above 50 (express-slow-down v2 API)
    maxDelayMs: 20000, // maximum delay of 20 seconds
    skip: hasValidAdminKey
})

app.use('/api', limiter)
app.use('/api', speedLimiter)

// =============================================================================
// ROUTES
// =============================================================================

// Health check (no rate limiting)
app.use('/api/health', healthRouter)

// API routes
app.use('/api/movies', moviesRouter)
app.use('/api/series', seriesRouter)
app.use('/api/channels', channelsRouter)
app.use('/api/browse', browseRouter)
app.use('/api/user', userRouter)
// Mount specific admin routes BEFORE general admin router to prevent conflicts
app.use('/api/admin/channels', channelsAdminRouter)
app.use('/api/admin/channel-management', channelManagementRouter)
app.use('/api/admin/staging', stagingRouter)
app.use('/api/admin/duplicates', duplicatesAdminRouter)
app.use('/api/admin/validation', validationAdminRouter)
app.use('/api/admin/genres', genresAdminRouter)
app.use('/api/admin', tvSeriesAdminRouter)
app.use('/api/admin', adminRouter)

// Root endpoint
app.get('/', (req, res) => {
    res.json({
        name: 'MovieBoxZ Backend API',
        version: '1.0.0',
        description: 'Netflix-style YouTube movie discovery platform',
        status: 'running',
        environment: process.env.NODE_ENV || 'development',
        timestamp: new Date().toISOString(),
        endpoints: {
            health: '/api/health',
            movies: '/api/movies',
            channels: '/api/channels',
            browse: '/api/browse',
            user: '/api/user',
            admin: '/api/admin'
        }
    })
})

// Catch-all for unmatched routes
app.all('*', (req, res) => {
    res.status(404).json({
        error: 'Route not found',
        message: `Cannot ${req.method} ${req.path}`,
        availableEndpoints: {
            health: 'GET /api/health',
            movies: 'GET /api/movies/*',
            channels: 'GET /api/channels/*',
            browse: 'GET /api/browse/*',
            user: 'GET /api/user/*',
            admin: 'POST /api/admin/*'
        }
    })
})

// =============================================================================
// ERROR HANDLING
// =============================================================================

app.use(errorHandler)

// =============================================================================
// SERVER STARTUP
// =============================================================================

// Graceful shutdown handler
const gracefulShutdown = (signal) => {
    logger.info(`Received ${signal}. Starting graceful shutdown...`)

    // Stop scheduled jobs first so no new work starts while we drain connections
    try {
        jobScheduler.stop()
    } catch (error) {
        logger.error('Error stopping job scheduler during shutdown:', error)
    }

    server.close(() => {
        logger.info('HTTP server closed.')
        process.exit(0)
    })

    // Force close after 30 seconds
    setTimeout(() => {
        logger.error('Could not close connections in time, forcefully shutting down')
        process.exit(1)
    }, 30000)
}

const server = app.listen(port, () => {
    logger.info(`🎬 MovieBoxZ Backend API running on port ${port}`)
    logger.info(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`)
    logger.info(`📊 API Documentation: http://localhost:${port}/`)

    // Sweep imports orphaned in 'running' by a previous crash/restart
    try {
        sweepZombieImports().catch(error => logger.error('Zombie import sweep failed at boot:', error))
    } catch (error) {
        logger.error('Zombie import sweep failed at boot:', error)
    }

    // Flush aggregate usage counters to the DB every 60s
    startUsageFlusher()

    // Initialize cron jobs in production
    if (process.env.NODE_ENV === 'production') {
        logger.info('🔄 Initializing cron jobs...')
        initializeCronJobs()
    }
})

// Handle graceful shutdown
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'))
process.on('SIGINT', () => gracefulShutdown('SIGINT'))

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
    logger.error('Uncaught Exception:', error)
    process.exit(1)
})

// Log unhandled rejections but keep the process alive — a single failed background
// promise (e.g. a cron job) should not take down the whole API server
process.on('unhandledRejection', (reason, promise) => {
    logger.error('Unhandled Rejection at:', promise, 'reason:', reason)
})

export default app