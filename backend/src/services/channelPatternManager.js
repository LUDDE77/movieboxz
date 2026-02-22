import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'

/**
 * ChannelPatternManager Service
 *
 * Manages configurable title extraction patterns for YouTube channels.
 * Extracts movie metadata (title, actors, genre, year) from video titles
 * using regex patterns stored in the database.
 */
class ChannelPatternManager {
    constructor() {
        this.patterns = new Map() // Cache patterns in memory
    }

    /**
     * Get pattern configuration for a channel from database
     *
     * @param {string} channelId - YouTube channel ID
     * @returns {Promise<Object|null>} Pattern configuration or null if not found
     */
    async getPattern(channelId) {
        try {
            // Check cache first
            if (this.patterns.has(channelId)) {
                logger.debug(`Using cached pattern for channel: ${channelId}`)
                return this.patterns.get(channelId)
            }

            // Fetch from database
            const { data, error } = await supabase
                .from('channel_patterns')
                .select('*')
                .eq('channel_id', channelId)
                .eq('is_active', true)
                .single()

            if (error) {
                if (error.code === 'PGRST116') {
                    // No rows found - not an error, just no pattern configured
                    logger.debug(`No pattern configured for channel: ${channelId}`)
                    return null
                }
                throw error
            }

            if (data) {
                // Convert regex strings to RegExp objects
                const processedData = {
                    ...data,
                    patterns: data.patterns.map(p => ({
                        ...p,
                        regex: new RegExp(p.regex, 'i') // Case-insensitive by default
                    }))
                }

                // Cache it
                this.patterns.set(channelId, processedData)
                logger.debug(`Loaded pattern for channel: ${data.channel_name}`)
                return processedData
            }

            return null

        } catch (error) {
            logger.error('Error getting channel pattern:', error)
            return null
        }
    }

    /**
     * Extract metadata from YouTube title using channel pattern
     *
     * @param {string} youtubeTitle - YouTube video title
     * @param {Object} pattern - Channel pattern configuration
     * @returns {Object|null} Extracted metadata or null if no match
     */
    extractMetadata(youtubeTitle, pattern) {
        if (!pattern || !pattern.patterns || pattern.patterns.length === 0) {
            logger.debug('No patterns available for extraction')
            return null
        }

        // Try each pattern in order
        for (const patternDef of pattern.patterns) {
            const match = youtubeTitle.match(patternDef.regex)

            if (match) {
                logger.info(`🎯 [Pattern] Matched! YouTube title: "${youtubeTitle}"`)
                logger.info(`🎯 [Pattern] Regex groups:`, {
                    group1: match[1],
                    group2: match[2],
                    group3: match[3],
                    group4: match[4]
                })

                const metadata = {}

                // Extract each parameter using capture groups
                for (const [param, captureGroup] of Object.entries(patternDef.parameters)) {
                    if (typeof captureGroup === 'number') {
                        // Capture group - extract from regex match
                        metadata[param] = match[captureGroup]?.trim()
                    } else {
                        // Static value
                        metadata[param] = captureGroup
                    }
                }

                logger.info(`🎯 [Pattern] Metadata extracted:`, {
                    title: metadata.title,
                    genre: metadata.genre,
                    actors: metadata.actors,
                    year: metadata.year,
                    episode_name: metadata.episode_name,
                    season: metadata.season,
                    episode: metadata.episode
                })

                // Clean up actors field - if it ends with "Movie(s)", it's a genre not an actor
                if (metadata.actors && /\b[Mm]ovies?\b/.test(metadata.actors)) {
                    logger.info(`🧹 [Pattern] Actor field "${metadata.actors}" contains "Movies", clearing it (it's a genre, not an actor)`)
                    metadata.actors = null
                } else if (metadata.actors) {
                    logger.info(`✅ [Pattern] Actor field looks valid: "${metadata.actors}"`)
                }

                // Parse actors array if present
                if (metadata.actors) {
                    metadata.actorsArray = this.parseActors(metadata.actors)
                }

                // Parse year to integer
                if (metadata.year) {
                    metadata.year = parseInt(metadata.year, 10)
                }

                // Strip emojis from title and episode_name
                if (metadata.title) {
                    metadata.title = this.stripEmojis(metadata.title)
                }
                if (metadata.episode_name) {
                    metadata.episode_name = this.stripEmojis(metadata.episode_name)
                }

                // Parse season and episode to integers
                if (metadata.season) {
                    metadata.season = parseInt(metadata.season, 10)
                }
                if (metadata.episode) {
                    metadata.episode = parseInt(metadata.episode, 10)
                }

                logger.debug('Pattern matched successfully', {
                    title: metadata.title,
                    actors: metadata.actorsArray,
                    genre: metadata.genre,
                    year: metadata.year,
                    episode_name: metadata.episode_name,
                    season: metadata.season,
                    episode: metadata.episode
                })

                return {
                    ...metadata,
                    patternMatched: true,
                    confidence: 1.0,
                    rawTitle: youtubeTitle
                }
            }
        }

        // No pattern matched - try fallback
        if (pattern.fallback_pattern) {
            logger.debug('No regex matched, using fallback pattern')
            return this.applyFallbackPattern(youtubeTitle, pattern.fallback_pattern)
        }

        logger.debug('No pattern matched for title:', youtubeTitle)
        return null
    }

    /**
     * Parse actors from a string into an array
     * Handles delimiters: comma, ampersand, "and"
     *
     * @param {string} actorsString - Raw actors string
     * @returns {Array<string>} Array of actor names
     */
    parseActors(actorsString) {
        if (!actorsString) return []

        return actorsString
            .split(/[,&]|\s+and\s+/i) // Split on comma, ampersand, or " and "
            .map(a => a.trim())
            .filter(a => a.length > 0)
    }

    /**
     * Remove emojis from a string
     *
     * @param {string} text - Text containing emojis
     * @returns {string} Text with emojis removed
     */
    stripEmojis(text) {
        if (!text) return text

        // Remove emojis using comprehensive regex
        // This covers: emoticons, symbols, pictographs, transport, flags, etc.
        return text
            .replace(/[\u{1F600}-\u{1F64F}]/gu, '') // Emoticons
            .replace(/[\u{1F300}-\u{1F5FF}]/gu, '') // Misc Symbols and Pictographs
            .replace(/[\u{1F680}-\u{1F6FF}]/gu, '') // Transport and Map
            .replace(/[\u{1F1E0}-\u{1F1FF}]/gu, '') // Flags
            .replace(/[\u{2600}-\u{26FF}]/gu, '')   // Misc symbols (stars, crosses, etc)
            .replace(/[\u{2700}-\u{27BF}]/gu, '')   // Dingbats
            .replace(/[\u{1F900}-\u{1F9FF}]/gu, '') // Supplemental Symbols and Pictographs
            .replace(/[\u{1FA00}-\u{1FA6F}]/gu, '') // Chess Symbols
            .replace(/[\u{1FA70}-\u{1FAFF}]/gu, '') // Symbols and Pictographs Extended-A
            .replace(/[\u{FE00}-\u{FE0F}]/gu, '')   // Variation Selectors
            .replace(/[\u{1F018}-\u{1F270}]/gu, '') // Various asian characters
            .replace(/[\u{238C}-\u{2454}]/gu, '')   // Misc items
            .replace(/[\u{20D0}-\u{20FF}]/gu, '')   // Combining Diacritical Marks
            .replace(/[\u{2190}-\u{21FF}]/gu, '')   // Arrows
            .replace(/[\u{2300}-\u{23FF}]/gu, '')   // Misc Technical (including ⭐)
            .replace(/[\u{2B00}-\u{2BFF}]/gu, '')   // Misc Symbols and Arrows
            .replace(/\s+/g, ' ')                    // Collapse multiple spaces
            .trim()
    }

    /**
     * Apply fallback pattern when no regex matches
     *
     * @param {string} youtubeTitle - YouTube video title
     * @param {Object} fallbackPattern - Fallback pattern configuration
     * @returns {Object} Extracted metadata using fallback
     */
    applyFallbackPattern(youtubeTitle, fallbackPattern) {
        if (fallbackPattern.type === 'first_segment') {
            const divider = fallbackPattern.divider || '|'
            const segments = youtubeTitle.split(divider)
            let title = segments[0]?.trim()

            if (!title) {
                return null
            }

            // Strip emojis if requested
            title = this.stripEmojis(title)

            // Remove common suffixes like "Full Movie", "FULL MOVIE", etc.
            title = title.replace(/\s*[Ff][Uu][Ll][Ll]\s*[Mm][Oo][Vv][Ii][Ee]\s*$/i, '').trim()
            title = title.replace(/\s*[Ff][Uu][Ll][Ll]\s*[Ee][Pp][Ii][Ss][Oo][Dd][Ee]\s*$/i, '').trim()

            return {
                title,
                patternMatched: false,
                confidence: 0.5,
                rawTitle: youtubeTitle,
                fallbackUsed: true
            }
        }

        return null
    }

    /**
     * Save or update pattern configuration for a channel
     *
     * @param {string} channelId - YouTube channel ID
     * @param {string} channelName - Human-readable channel name
     * @param {Array} patterns - Array of pattern objects
     * @param {Object} fallbackPattern - Fallback pattern object
     * @returns {Promise<Object>} Saved pattern data
     */
    async savePattern(channelId, channelName, patterns, fallbackPattern = null) {
        try {
            // Validate patterns
            if (!Array.isArray(patterns) || patterns.length === 0) {
                throw new Error('Patterns must be a non-empty array')
            }

            // Ensure all patterns have required fields
            for (const pattern of patterns) {
                if (!pattern.regex || !pattern.parameters) {
                    throw new Error('Each pattern must have regex and parameters')
                }
            }

            const { data, error } = await supabase
                .from('channel_patterns')
                .upsert({
                    channel_id: channelId,
                    channel_name: channelName,
                    patterns: patterns,
                    fallback_pattern: fallbackPattern,
                    updated_at: new Date().toISOString()
                }, {
                    onConflict: 'channel_id'
                })
                .select()
                .single()

            if (error) {
                throw error
            }

            // Invalidate cache
            this.patterns.delete(channelId)

            logger.info(`Saved pattern for channel: ${channelName}`, {
                channel_id: channelId,
                pattern_count: patterns.length
            })

            return data

        } catch (error) {
            logger.error('Error saving channel pattern:', error)
            throw error
        }
    }

    /**
     * Get all configured channel patterns
     *
     * @returns {Promise<Array>} All channel patterns
     */
    async getAllPatterns() {
        try {
            const { data, error } = await supabase
                .from('channel_patterns')
                .select('*')
                .eq('is_active', true)
                .order('channel_name')

            if (error) {
                throw error
            }

            return data || []

        } catch (error) {
            logger.error('Error getting all patterns:', error)
            throw error
        }
    }

    /**
     * Delete pattern configuration for a channel
     *
     * @param {string} channelId - YouTube channel ID
     * @returns {Promise<void>}
     */
    async deletePattern(channelId) {
        try {
            const { error } = await supabase
                .from('channel_patterns')
                .delete()
                .eq('channel_id', channelId)

            if (error) {
                throw error
            }

            // Invalidate cache
            this.patterns.delete(channelId)

            logger.info(`Deleted pattern for channel: ${channelId}`)

        } catch (error) {
            logger.error('Error deleting channel pattern:', error)
            throw error
        }
    }

    /**
     * Clear the pattern cache
     */
    clearCache() {
        this.patterns.clear()
        logger.info('Pattern cache cleared')
    }
}

// Export singleton instance
export default new ChannelPatternManager()
