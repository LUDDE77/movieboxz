import express from 'express'
import { testConnection } from '../config/database.js'
import { youtubeService } from '../services/youtubeService.js'
import { tmdbService } from '../services/tmdbService.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// =============================================================================
// GET /api/health
// Basic health check
// =============================================================================
router.get('/', async (req, res) => {
    const startTime = Date.now()

    try {
        // Check database connection
        const dbHealthy = await testConnection()

        // Check external APIs (light check)
        const youtubeHealthy = await youtubeService.healthCheck()
        const tmdbHealthy = await tmdbService.healthCheck()

        const responseTime = Date.now() - startTime
        const allHealthy = dbHealthy && youtubeHealthy && tmdbHealthy

        res.status(allHealthy ? 200 : 503).json({
            status: allHealthy ? 'healthy' : 'unhealthy',
            timestamp: new Date().toISOString(),
            version: '1.0.0',
            environment: process.env.NODE_ENV || 'development',
            uptime: process.uptime(),
            responseTime: `${responseTime}ms`,
            services: {
                database: {
                    status: dbHealthy ? 'healthy' : 'unhealthy',
                    provider: 'supabase'
                },
                youtube: {
                    status: youtubeHealthy ? 'healthy' : 'unhealthy',
                    provider: 'google'
                },
                tmdb: {
                    status: tmdbHealthy ? 'healthy' : 'unhealthy',
                    provider: 'themoviedb'
                }
            },
            memory: {
                used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
                total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
                unit: 'MB'
            }
        })
    } catch (error) {
        logger.error('Health check failed:', error)

        res.status(503).json({
            status: 'unhealthy',
            timestamp: new Date().toISOString(),
            error: error.message,
            responseTime: `${Date.now() - startTime}ms`
        })
    }
})

// =============================================================================
// GET /api/health/detailed
// Detailed health check with more information
// =============================================================================
router.get('/detailed', async (req, res) => {
    const startTime = Date.now()

    try {
        // More comprehensive checks
        const checks = await Promise.allSettled([
            testConnection(),
            youtubeService.quotaCheck(),
            tmdbService.quotaCheck()
        ])

        const [dbResult, youtubeResult, tmdbResult] = checks

        const responseTime = Date.now() - startTime

        res.json({
            status: 'detailed_check',
            timestamp: new Date().toISOString(),
            responseTime: `${responseTime}ms`,
            environment: process.env.NODE_ENV || 'development',
            uptime: process.uptime(),
            checks: {
                database: {
                    status: dbResult.status === 'fulfilled' && dbResult.value ? 'healthy' : 'unhealthy',
                    error: dbResult.status === 'rejected' ? dbResult.reason?.message : null
                },
                youtube_api: {
                    status: youtubeResult.status === 'fulfilled' ? 'healthy' : 'unhealthy',
                    quota_remaining: youtubeResult.status === 'fulfilled' ? youtubeResult.value : null,
                    error: youtubeResult.status === 'rejected' ? youtubeResult.reason?.message : null
                },
                tmdb_api: {
                    status: tmdbResult.status === 'fulfilled' ? 'healthy' : 'unhealthy',
                    quota_remaining: tmdbResult.status === 'fulfilled' ? tmdbResult.value : null,
                    error: tmdbResult.status === 'rejected' ? tmdbResult.reason?.message : null
                }
            },
            system: {
                node_version: process.version,
                platform: process.platform,
                memory: process.memoryUsage(),
                cpu_usage: process.cpuUsage(),
                load_average: require('os').loadavg()
            },
            features: {
                movie_discovery: true,
                youtube_integration: true,
                tmdb_metadata: true,
                user_authentication: true,
                curation_service: true
            }
        })
    } catch (error) {
        logger.error('Detailed health check failed:', error)

        res.status(503).json({
            status: 'error',
            timestamp: new Date().toISOString(),
            error: error.message,
            responseTime: `${Date.now() - startTime}ms`
        })
    }
})

export default router
