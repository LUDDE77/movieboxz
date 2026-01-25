import { dbOperations, supabase } from '../config/database.js'
import { channelPatternDetector } from '../services/channelPatternDetector.js'
import { logger } from '../utils/logger.js'

/**
 * Bulk Title Cleaning Script
 *
 * Re-cleans all movie titles using current channel patterns
 * Fixes movies that were imported before pattern detection system
 * or with incorrect pattern detection
 */

class TitleFixer {
    cleanMovieTitle(title, pattern = null) {
        /**
         * Intelligent title cleaning with pattern-aware extraction
         * (Copied from movieCurator.js for standalone execution)
         */

        // SAFETY CHECK: Override pattern if it contradicts actual title structure
        if (pattern && !pattern.pipe_separator && title.includes('|')) {
            logger.warn(`Pattern mismatch detected: pattern says no pipes but title has pipes`, {
                title: title,
                detected_pattern: pattern.type
            })
            // Override pattern to use pipe-based extraction
            pattern = {
                pipe_separator: true,
                title_position: 'first',
                type: 'first_segment_override',
                confidence: 0.6
            }
            logger.info(`Applied fallback pattern: first_segment with 60% confidence`)
        }

        let candidateTitles = []

        // Step 1: Extract title segment(s) based on detected pattern
        if (title.includes('|')) {
            const segments = title.split('|').map(s => s.trim())

            if (pattern && pattern.pipe_separator) {
                // Use AI-detected pattern
                logger.debug(`Using detected pattern: ${pattern.type} (position: ${pattern.title_position})`)

                if (pattern.title_position === 'first') {
                    candidateTitles.push(segments[0])
                } else if (pattern.title_position === 'last') {
                    candidateTitles.push(segments[segments.length - 1])
                } else if (pattern.title_position === 'both' || pattern.confidence < 0.7) {
                    // Low confidence or mixed patterns: try both
                    candidateTitles.push(segments[0])
                    if (segments.length > 1) {
                        candidateTitles.push(segments[segments.length - 1])
                    }
                }
            } else {
                // No pattern: try both first and last segments (fallback)
                candidateTitles.push(segments[0])
                if (segments.length > 1) {
                    candidateTitles.push(segments[segments.length - 1])
                }
            }
        } else {
            // No pipes: use full title
            candidateTitles.push(title)
        }

        // Step 2: Clean all candidate titles
        const cleanedCandidates = candidateTitles.map(candidate => {
            let cleaned = candidate

            // Remove common YouTube video indicators
            cleaned = cleaned
                .replace(/\b(full movie|complete film|full film|feature film)\b/gi, '')
                .replace(/\[.*?\]/g, '')
                .replace(/\b(HD|4K|1080p|720p|480p|DVD|BLURAY|BLU-RAY)\b/gi, '')
                .replace(/\b(official|original|remastered|restored)\b/gi, '')
                .replace(/\s*-\s*$/, '')
                .replace(/\s+/g, ' ')
                .trim()

            return cleaned
        })

        // Step 3: Pick shortest (usually the actual title without metadata)
        const bestTitle = cleanedCandidates.reduce((shortest, current) => {
            return current.length < shortest.length ? current : shortest
        })

        return bestTitle
    }

    async fixAllTitles(options = {}) {
        const {
            dryRun = false,
            limit = null,
            channelId = null
        } = options

        try {
            logger.info(`Starting title fix process...`, { dryRun, limit, channelId })

            // Build query
            let query = supabase
                .from('movies')
                .select('id, title, original_title, channel_id')

            // Filter by channel if specified
            if (channelId) {
                query = query.eq('channel_id', channelId)
            }

            // Apply limit if specified
            if (limit) {
                query = query.limit(limit)
            }

            const { data: movies, error } = await query

            if (error) {
                throw new Error(`Failed to fetch movies: ${error.message}`)
            }

            logger.info(`Found ${movies.length} movies to process`)

            const results = {
                total: movies.length,
                updated: 0,
                unchanged: 0,
                failed: 0,
                changes: []
            }

            // Process each movie
            for (const movie of movies) {
                try {
                    // Get channel pattern
                    let pattern = null
                    try {
                        pattern = await channelPatternDetector.getPattern(movie.channel_id)
                    } catch (error) {
                        logger.debug(`No pattern for channel ${movie.channel_id}`)
                    }

                    // Use original_title if available, otherwise current title
                    const sourceTitle = movie.original_title || movie.title

                    // Re-clean title
                    const cleanedTitle = this.cleanMovieTitle(sourceTitle, pattern)

                    // Check if title needs updating
                    if (cleanedTitle !== movie.title) {
                        logger.info(`Title change detected:`, {
                            id: movie.id,
                            old: movie.title,
                            new: cleanedTitle
                        })

                        results.changes.push({
                            id: movie.id,
                            oldTitle: movie.title,
                            newTitle: cleanedTitle
                        })

                        if (!dryRun) {
                            // Update database
                            const { error: updateError } = await supabase
                                .from('movies')
                                .update({
                                    title: cleanedTitle,
                                    updated_at: new Date().toISOString()
                                })
                                .eq('id', movie.id)

                            if (updateError) {
                                throw new Error(`Update failed: ${updateError.message}`)
                            }

                            logger.debug(`Updated movie ${movie.id}`)
                        }

                        results.updated++
                    } else {
                        results.unchanged++
                    }

                } catch (error) {
                    logger.error(`Failed to process movie ${movie.id}:`, error.message)
                    results.failed++
                }
            }

            // Summary
            logger.info(`Title fix completed:`, results)

            return results

        } catch (error) {
            logger.error(`Title fix process failed:`, error.message)
            throw error
        }
    }

    async fixSingleMovie(movieId) {
        try {
            // Get movie
            const { data: movie, error } = await supabase
                .from('movies')
                .select('id, title, original_title, channel_id')
                .eq('id', movieId)
                .single()

            if (error) {
                throw new Error(`Failed to fetch movie: ${error.message}`)
            }

            // Get channel pattern
            let pattern = null
            try {
                pattern = await channelPatternDetector.getPattern(movie.channel_id)
            } catch (error) {
                logger.debug(`No pattern for channel ${movie.channel_id}`)
            }

            // Use original_title if available
            const sourceTitle = movie.original_title || movie.title

            // Clean title
            const cleanedTitle = this.cleanMovieTitle(sourceTitle, pattern)

            // Update if different
            if (cleanedTitle !== movie.title) {
                const { error: updateError } = await supabase
                    .from('movies')
                    .update({
                        title: cleanedTitle,
                        updated_at: new Date().toISOString()
                    })
                    .eq('id', movieId)

                if (updateError) {
                    throw new Error(`Update failed: ${updateError.message}`)
                }

                logger.info(`Updated movie ${movieId}:`, {
                    old: movie.title,
                    new: cleanedTitle
                })

                return {
                    success: true,
                    oldTitle: movie.title,
                    newTitle: cleanedTitle
                }
            } else {
                logger.info(`Movie ${movieId} already has clean title`)
                return {
                    success: true,
                    message: 'Title already clean'
                }
            }

        } catch (error) {
            logger.error(`Failed to fix movie ${movieId}:`, error.message)
            throw error
        }
    }
}

export const titleFixer = new TitleFixer()
export default titleFixer
