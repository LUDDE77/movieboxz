import { youtubeService } from './youtubeService.js'
import { dbOperations } from '../config/database.js'
import { logger } from '../utils/logger.js'

/**
 * Channel Pattern Detector
 *
 * Intelligently analyzes a YouTube channel's title structure to determine
 * the optimal extraction pattern for movie titles.
 *
 * Detects patterns like:
 * - first_segment: "Movie Title | Genre | Actor | Channel"
 * - last_segment: "Clickbait Description | Actual Movie Title"
 * - no_pipes: "Simple Movie Title (Year)"
 * - mixed: Inconsistent patterns (use dual-try approach)
 */
class ChannelPatternDetector {
    constructor() {
        // Minimum confidence threshold to accept a pattern
        this.confidenceThreshold = 0.7

        // Known channel name patterns to detect in segments
        this.channelNamePatterns = [
            /the midnight screening/i,
            /free movies/i,
            /contv/i,
            /cinema/i,
            /channel/i
        ]

        // Common clickbait words that indicate descriptive segments
        this.clickbaitWords = [
            'best', 'worst', 'top', 'amazing', 'incredible', 'must watch',
            'you won\'t believe', 'shocking', 'epic', 'ultimate', 'legendary',
            'rare', 'vs', 'versus', 'battle', 'when', 'how', 'why', 'what'
        ]

        // Movie title indicators
        this.movieTitleIndicators = [
            /\(\d{4}\)/,  // Year in parentheses like "(2021)"
            /^[A-Z][a-z]+/,  // Starts with capital letter
            /[:.]/  // Contains colon or period (common in titles)
        ]
    }

    /**
     * Analyze a channel's title structure
     *
     * @param {string} channelId - YouTube channel ID
     * @param {number} sampleSize - Number of titles to analyze (default: 25)
     * @returns {Object} Pattern analysis result
     */
    async analyzeChannel(channelId, sampleSize = 25) {
        try {
            logger.info(`🔍 Analyzing title pattern for channel: ${channelId}`)

            // Fetch sample videos from channel
            const videos = await youtubeService.getChannelVideos(channelId, {
                maxResults: sampleSize,
                order: 'date'
            })

            if (videos.length === 0) {
                throw new Error('No videos found in channel')
            }

            logger.info(`📊 Analyzing ${videos.length} sample titles...`)

            // Extract titles for analysis
            const titles = videos.map(v => v.title)

            // Analyze pipe separator usage
            const pipeAnalysis = this.analyzePipeSeparators(titles)

            // Determine title position if pipes exist
            let pattern
            if (pipeAnalysis.hasPipes) {
                pattern = this.determineTitlePosition(titles, pipeAnalysis)
            } else {
                pattern = {
                    type: 'no_pipes',
                    pipe_separator: false,
                    title_position: 'full',
                    confidence: 1.0
                }
            }

            // Build complete pattern metadata
            const result = {
                type: pattern.type,
                pipe_separator: pipeAnalysis.hasPipes,
                title_position: pattern.title_position,
                confidence: pattern.confidence,
                analyzed_at: new Date().toISOString(),
                sample_count: titles.length,
                notes: this.generatePatternNotes(pattern, pipeAnalysis),
                segments: pipeAnalysis.hasPipes ? {
                    average_count: pipeAnalysis.avgSegmentCount,
                    first_avg_length: pipeAnalysis.firstSegmentAvgLength,
                    last_avg_length: pipeAnalysis.lastSegmentAvgLength,
                    channel_name_in_last: pipeAnalysis.channelNameInLast
                } : null
            }

            logger.info(`✅ Pattern detected:`, {
                type: result.type,
                confidence: result.confidence,
                title_position: result.title_position
            })

            // Store pattern in database
            await this.storePattern(channelId, result)

            return result

        } catch (error) {
            logger.error(`Failed to analyze channel pattern:`, error.message)
            throw error
        }
    }

    /**
     * Analyze pipe separator usage across titles
     */
    analyzePipeSeparators(titles) {
        const titlesWithPipes = titles.filter(t => t.includes('|'))
        const hasPipes = titlesWithPipes.length > titles.length * 0.7 // 70% threshold

        if (!hasPipes) {
            return { hasPipes: false }
        }

        // Analyze segment characteristics
        const segmentCounts = []
        const firstSegmentLengths = []
        const lastSegmentLengths = []
        let channelNameInLastCount = 0

        titlesWithPipes.forEach(title => {
            const segments = title.split('|').map(s => s.trim())
            segmentCounts.push(segments.length)

            firstSegmentLengths.push(segments[0].length)
            lastSegmentLengths.push(segments[segments.length - 1].length)

            // Check if last segment contains channel name
            const lastSegment = segments[segments.length - 1].toLowerCase()
            if (this.channelNamePatterns.some(pattern => pattern.test(lastSegment))) {
                channelNameInLastCount++
            }
        })

        const avgSegmentCount = segmentCounts.reduce((a, b) => a + b, 0) / segmentCounts.length
        const firstSegmentAvgLength = firstSegmentLengths.reduce((a, b) => a + b, 0) / firstSegmentLengths.length
        const lastSegmentAvgLength = lastSegmentLengths.reduce((a, b) => a + b, 0) / lastSegmentLengths.length

        return {
            hasPipes: true,
            avgSegmentCount,
            firstSegmentAvgLength,
            lastSegmentAvgLength,
            channelNameInLast: channelNameInLastCount > titlesWithPipes.length * 0.7
        }
    }

    /**
     * Determine where the movie title is located (first or last segment)
     */
    determineTitlePosition(titles, pipeAnalysis) {
        const titlesWithPipes = titles.filter(t => t.includes('|'))

        let firstSegmentScore = 0
        let lastSegmentScore = 0

        titlesWithPipes.forEach(title => {
            const segments = title.split('|').map(s => s.trim())
            const firstSegment = segments[0]
            const lastSegment = segments[segments.length - 1]

            // Score first segment
            firstSegmentScore += this.scoreSegmentAsTitle(firstSegment, 'first')

            // Score last segment
            lastSegmentScore += this.scoreSegmentAsTitle(lastSegment, 'last')
        })

        // Normalize scores
        firstSegmentScore /= titlesWithPipes.length
        lastSegmentScore /= titlesWithPipes.length

        // Additional heuristics from segment analysis
        if (pipeAnalysis.channelNameInLast) {
            // If channel name is in last segment, title is likely NOT last
            firstSegmentScore += 0.3
        }

        if (pipeAnalysis.firstSegmentAvgLength > pipeAnalysis.lastSegmentAvgLength * 1.5) {
            // First segment is much longer → likely description/clickbait
            lastSegmentScore += 0.2
        } else if (pipeAnalysis.lastSegmentAvgLength > pipeAnalysis.firstSegmentAvgLength * 1.5) {
            // Last segment is much longer → likely description
            firstSegmentScore += 0.2
        }

        // Determine winner
        const isFirstSegment = firstSegmentScore > lastSegmentScore
        const confidence = Math.abs(firstSegmentScore - lastSegmentScore)

        logger.debug(`Segment scores: first=${firstSegmentScore.toFixed(2)}, last=${lastSegmentScore.toFixed(2)}`)

        if (confidence < 0.3) {
            // Low confidence, patterns are mixed
            return {
                type: 'mixed',
                title_position: 'both',
                confidence: 0.5
            }
        }

        return {
            type: isFirstSegment ? 'first_segment' : 'last_segment',
            title_position: isFirstSegment ? 'first' : 'last',
            confidence: Math.min(confidence, 1.0)
        }
    }

    /**
     * Score a segment as a potential movie title
     */
    scoreSegmentAsTitle(segment, position) {
        let score = 0

        // Length heuristic (movie titles are typically 10-50 chars)
        const length = segment.length
        if (length >= 10 && length <= 50) {
            score += 0.3
        } else if (length < 10 || length > 100) {
            score -= 0.2
        }

        // Contains year in parentheses (strong title indicator)
        if (/\(\d{4}\)/.test(segment)) {
            score += 0.4
        }

        // Contains clickbait words (likely NOT a title)
        const lowerSegment = segment.toLowerCase()
        if (this.clickbaitWords.some(word => lowerSegment.includes(word))) {
            score -= 0.3
        }

        // Contains channel name patterns (NOT a title)
        if (this.channelNamePatterns.some(pattern => pattern.test(segment))) {
            score -= 0.5
        }

        // Starts with capital letter (good title indicator)
        if (/^[A-Z]/.test(segment)) {
            score += 0.1
        }

        // Contains movie-specific punctuation (colon, period)
        if (/[:\.]/.test(segment)) {
            score += 0.1
        }

        // Has "FULL MOVIE" (indicates this segment contains promotional text)
        if (/full movie/i.test(segment)) {
            score -= 0.2
        }

        return score
    }

    /**
     * Generate human-readable notes about the pattern
     */
    generatePatternNotes(pattern, pipeAnalysis) {
        if (pattern.type === 'no_pipes') {
            return 'Channel uses simple title format without pipe separators'
        }

        if (pattern.type === 'mixed') {
            return 'Channel has inconsistent title patterns. Using dual-try extraction approach.'
        }

        if (pattern.type === 'first_segment') {
            return `Channel uses format: Movie Title | ${pipeAnalysis.channelNameInLast ? 'Genre | Actor | Channel Name' : 'Additional Info'}`
        }

        if (pattern.type === 'last_segment') {
            return 'Channel uses format: Clickbait Description | Actual Movie Title'
        }

        return 'Unknown pattern structure'
    }

    /**
     * Store detected pattern in database
     */
    async storePattern(channelId, pattern) {
        try {
            const { error } = await dbOperations.supabase
                .from('channels')
                .update({
                    title_pattern: pattern,
                    pattern_analyzed: true,
                    updated_at: new Date().toISOString()
                })
                .eq('id', channelId)

            if (error) {
                throw new Error(`Failed to store pattern: ${error.message}`)
            }

            logger.info(`💾 Stored pattern for channel ${channelId}`)
        } catch (error) {
            logger.error(`Error storing pattern:`, error.message)
            throw error
        }
    }

    /**
     * Get stored pattern for a channel
     */
    async getPattern(channelId) {
        try {
            const { data, error } = await dbOperations.supabase
                .from('channels')
                .select('title_pattern, pattern_analyzed')
                .eq('id', channelId)
                .single()

            if (error) {
                return null
            }

            return data.pattern_analyzed ? data.title_pattern : null
        } catch (error) {
            logger.error(`Error retrieving pattern:`, error.message)
            return null
        }
    }
}

export const channelPatternDetector = new ChannelPatternDetector()
export default channelPatternDetector
