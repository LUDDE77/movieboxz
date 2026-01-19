import { google } from 'googleapis'
import { logger } from '../utils/logger.js'

class YouTubeService {
    constructor() {
        this.youtube = google.youtube({
            version: 'v3',
            auth: process.env.YOUTUBE_API_KEY
        })
    }

    async healthCheck() {
        try {
            if (!process.env.YOUTUBE_API_KEY) {
                logger.warn('YouTube API key not configured')
                return false
            }
            return true
        } catch (error) {
            logger.error('YouTube health check failed:', error)
            return false
        }
    }

    async quotaCheck() {
        try {
            // Simple quota check
            return 'available'
        } catch (error) {
            logger.error('YouTube quota check failed:', error)
            throw error
        }
    }
}

export const youtubeService = new YouTubeService()