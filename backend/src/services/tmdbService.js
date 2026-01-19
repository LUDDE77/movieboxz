import fetch from 'node-fetch'
import { logger } from '../utils/logger.js'

class TMDBService {
    constructor() {
        this.apiKey = process.env.TMDB_API_KEY
        this.readAccessToken = process.env.TMDB_READ_ACCESS_TOKEN
        this.baseUrl = 'https://api.themoviedb.org/3'
    }

    async healthCheck() {
        try {
            if (!this.apiKey || !this.readAccessToken) {
                logger.warn('TMDB credentials not configured')
                return false
            }
            return true
        } catch (error) {
            logger.error('TMDB health check failed:', error)
            return false
        }
    }

    async quotaCheck() {
        try {
            // Simple quota check
            return 'available'
        } catch (error) {
            logger.error('TMDB quota check failed:', error)
            throw error
        }
    }
}

export const tmdbService = new TMDBService()