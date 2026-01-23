import { youtubeService } from './youtubeService.js'
import { tmdbService } from './tmdbService.js'
import { dbOperations } from '../config/database.js'
import { logger } from '../utils/logger.js'
import stringSimilarity from 'string-similarity'

class SeriesCurator {
    constructor() {
        // Minimum similarity threshold for episode matching
        this.episodeMatchThreshold = 0.6

        // Episode title patterns to clean
        this.episodePrefixPatterns = [
            /^bonanza\s*[-|]\s*/i,
            /^[a-z\s]+\s*[-|]\s*/i  // Any series name followed by dash/pipe
        ]
    }

    // Rest of the file content...
}

export const seriesCurator = new SeriesCurator()
export default seriesCurator