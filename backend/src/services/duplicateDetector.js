import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'

/**
 * DuplicateDetector Service
 *
 * Detects duplicate movies from different YouTube channels using:
 * 1. TMDB ID matching (100% confidence)
 * 2. Fuzzy title matching with pg_trgm (70-100% confidence)
 * 3. Release year matching (helps distinguish remakes)
 *
 * Quality scoring algorithm ranks backups by:
 * - View count (0-40 points)
 * - Channel reputation (0-30 points)
 * - Embeddability (0-10 points)
 * - Upload recency (0-20 points)
 */
class DuplicateDetector {
    constructor() {
        this.FUZZY_MATCH_THRESHOLD = 0.7 // Minimum similarity score (0-1)
        this.YEAR_TOLERANCE = 1 // Allow ±1 year difference
    }

    /**
     * Find or create a movie group for a YouTube video
     *
     * @param {Object} movieData - Movie metadata
     * @param {number} movieData.tmdb_id - TMDB movie ID (most reliable)
     * @param {string} movieData.title - Movie title
     * @param {number} movieData.release_year - Release year
     * @param {string} movieData.youtube_video_id - YouTube video ID
     * @returns {Promise<{group: Object, matchType: string, confidence: number}>}
     */
    async findOrCreateMovieGroup(movieData) {
        const { tmdb_id, title, release_year, youtube_video_id } = movieData

        try {
            // Step 1: Try TMDB ID match (highest confidence)
            if (tmdb_id) {
                const { data: group, error } = await supabase
                    .from('movie_groups')
                    .select('*')
                    .eq('tmdb_id', tmdb_id)
                    .single()

                if (!error && group) {
                    logger.debug(`TMDB ID match found: ${group.canonical_title}`, {
                        tmdb_id,
                        group_id: group.id
                    })

                    return {
                        group,
                        matchType: 'tmdb_id',
                        confidence: 1.0
                    }
                }
            }

            // Step 2: Try fuzzy title + year match
            const normalizedTitle = this.normalizeTitle(title)

            const { data: groups, error: fuzzyError } = await supabase
                .rpc('find_similar_movie_groups', {
                    search_title: normalizedTitle,
                    search_year: release_year,
                    year_tolerance: this.YEAR_TOLERANCE,
                    similarity_threshold: this.FUZZY_MATCH_THRESHOLD
                })

            if (!fuzzyError && groups && groups.length > 0) {
                const bestMatch = groups[0]

                logger.debug(`Fuzzy title match found: ${bestMatch.canonical_title}`, {
                    normalized_title: normalizedTitle,
                    similarity: bestMatch.similarity,
                    group_id: bestMatch.id
                })

                return {
                    group: bestMatch,
                    matchType: 'title_fuzzy',
                    confidence: bestMatch.similarity
                }
            }

            // Step 3: No match found - create new group
            const { data: newGroup, error: createError } = await supabase
                .from('movie_groups')
                .insert({
                    tmdb_id: tmdb_id || null,
                    canonical_title: title,
                    normalized_title: normalizedTitle,
                    release_year: release_year || null
                })
                .select()
                .single()

            if (createError) {
                throw createError
            }

            logger.info(`Created new movie group: ${title}`, {
                group_id: newGroup.id,
                tmdb_id
            })

            return {
                group: newGroup,
                matchType: 'new_group',
                confidence: 1.0
            }

        } catch (error) {
            logger.error('Error finding/creating movie group:', error)
            throw error
        }
    }

    /**
     * Calculate quality score for ranking backups (0-100)
     *
     * Scoring breakdown:
     * - View count: 0-40 points (log scale)
     * - Channel reputation: 0-30 points
     * - Embeddability: 0-10 points
     * - Upload recency: 0-20 points (newer = better)
     *
     * @param {Object} movieData - Movie metadata
     * @returns {number} Quality score (0-100)
     */
    calculateQualityScore(movieData) {
        let score = 0

        // View count (0-40 points, logarithmic scale)
        if (movieData.view_count) {
            const viewCount = parseInt(movieData.view_count)
            if (viewCount > 0) {
                // log10(1M views) = 6 → 30 points
                // log10(10M views) = 7 → 35 points
                // log10(100M views) = 8 → 40 points
                score += Math.min(Math.log10(viewCount) * 5, 40)
            }
        }

        // Channel reputation (0-30 points)
        const channelRep = this.getChannelReputation(movieData.channel_id)
        score += channelRep * 30

        // Embeddability (0-10 points)
        if (movieData.is_embeddable) {
            score += 10
        }

        // Upload recency (0-20 points, newer = better)
        if (movieData.published_at) {
            const publishedDate = new Date(movieData.published_at)
            const now = new Date()
            const daysSinceUpload = (now - publishedDate) / (1000 * 60 * 60 * 24)
            const yearsSinceUpload = daysSinceUpload / 365

            // 0 years = 20 points, 1 year = 10 points, 2+ years = 0 points
            score += Math.max(20 - (yearsSinceUpload * 10), 0)
        }

        return Math.round(score)
    }

    /**
     * Get channel reputation score (0-1)
     *
     * TODO: Implement proper channel reputation system based on:
     * - Subscriber count
     * - Verified status
     * - Upload consistency
     * - Content quality metrics
     *
     * @param {string} channelId - YouTube channel ID
     * @returns {number} Reputation score (0-1)
     */
    getChannelReputation(channelId) {
        // Placeholder - return 0.5 (average) for now
        // In production, query channels table and calculate reputation
        return 0.5
    }

    /**
     * Normalize title for fuzzy matching
     *
     * Removes:
     * - Punctuation
     * - Common words (the, a, an, full, movie, hd, 4k, etc.)
     * - Extra whitespace
     *
     * @param {string} title - Original title
     * @returns {string} Normalized title
     */
    normalizeTitle(title) {
        if (!title) return ''

        return title
            .toLowerCase()
            .replace(/[^\w\s]/g, '') // Remove punctuation
            .replace(/\b(the|a|an|full|movie|hd|4k|1080p|720p|dvd|bluray|blu-ray)\b/g, '') // Remove common words
            .replace(/\s+/g, ' ') // Normalize whitespace
            .trim()
    }

    /**
     * Check if a movie should be primary based on quality score
     *
     * @param {string} movieGroupId - Movie group ID
     * @param {number} newQualityScore - Quality score of new movie
     * @returns {Promise<{isPrimary: boolean, existingPrimaryId: string|null}>}
     */
    async shouldBePrimary(movieGroupId, newQualityScore) {
        try {
            const { data: existingPrimary, error } = await supabase
                .from('movies')
                .select('id, quality_score')
                .eq('movie_group_id', movieGroupId)
                .eq('is_primary', true)
                .single()

            if (error && error.code !== 'PGRST116') {
                // PGRST116 = no rows found (expected if no primary exists yet)
                throw error
            }

            if (!existingPrimary) {
                // No existing primary - this should be primary
                return {
                    isPrimary: true,
                    existingPrimaryId: null
                }
            }

            // Compare quality scores
            const isPrimary = newQualityScore > existingPrimary.quality_score

            logger.debug('Quality comparison:', {
                new_score: newQualityScore,
                existing_score: existingPrimary.quality_score,
                should_promote: isPrimary
            })

            return {
                isPrimary,
                existingPrimaryId: existingPrimary.id
            }

        } catch (error) {
            logger.error('Error checking primary status:', error)
            throw error
        }
    }

    /**
     * Demote existing primary to backup
     *
     * @param {string} movieId - Movie ID to demote
     * @returns {Promise<void>}
     */
    async demotePrimary(movieId) {
        try {
            const { error } = await supabase
                .from('movies')
                .update({ is_primary: false })
                .eq('id', movieId)

            if (error) {
                throw error
            }

            logger.info(`Demoted movie ${movieId} from primary to backup`)

        } catch (error) {
            logger.error('Error demoting primary:', error)
            throw error
        }
    }

    /**
     * Get all versions (duplicates) of a movie
     *
     * @param {string} movieGroupId - Movie group ID
     * @returns {Promise<Array>} Array of movies in group
     */
    async getMovieVersions(movieGroupId) {
        try {
            const { data: movies, error } = await supabase
                .from('movies')
                .select('*')
                .eq('movie_group_id', movieGroupId)
                .order('is_primary', { ascending: false })
                .order('quality_score', { ascending: false })

            if (error) {
                throw error
            }

            return movies || []

        } catch (error) {
            logger.error('Error getting movie versions:', error)
            throw error
        }
    }

    /**
     * Get backup count for a movie group
     *
     * @param {string} movieGroupId - Movie group ID
     * @returns {Promise<number>} Number of available backups
     */
    async getBackupCount(movieGroupId) {
        try {
            const { count, error } = await supabase
                .from('movies')
                .select('id', { count: 'exact', head: true })
                .eq('movie_group_id', movieGroupId)
                .eq('is_available', true)
                .eq('is_primary', false)

            if (error) {
                throw error
            }

            return count || 0

        } catch (error) {
            logger.error('Error getting backup count:', error)
            return 0
        }
    }
}

// Export singleton instance
export default new DuplicateDetector()
