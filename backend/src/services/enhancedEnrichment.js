import { tmdbService } from './tmdbService.js'
import { omdbService } from './omdbService.js'
import { logger } from '../utils/logger.js'
import axios from 'axios'

class EnhancedEnrichment {
    constructor() {
        // Channel-specific title patterns
        this.channelPatterns = {
            'The Midnight Screening': {
                // Pattern: TITLE FULL MOVIE | ACTORS | GENRE Movies | The Midnight Screening
                pattern: /^(.+?)\s*FULL MOVIE\s*\|\s*(.+?)\s*\|\s*(?:[\w\s]+Movies?)\s*\|\s*The Midnight Screening$/i,
                titleGroup: 1,
                actorGroup: 2
            },
            'UC6A_LC-A5NVJ2vw9A0OjCug': {
                // Pattern: TITLE FULL MOVIE | ACTORS | GENRE Movies | The Midnight Screening
                pattern: /^(.+?)\s*FULL MOVIE\s*\|\s*(.+?)\s*\|\s*(?:[\w\s]+Movies?)\s*\|\s*The Midnight Screening$/i,
                titleGroup: 1,
                actorGroup: 2
            }
        }

        this.confidenceThresholds = {
            autoAccept: 70,
            manualReview: 50,
            reject: 50
        }
    }