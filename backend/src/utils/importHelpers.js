/**
 * Pure helpers for the channel import / admin pipeline.
 *
 * This module intentionally has NO database, network, or service imports so the
 * logic can be unit tested in isolation (no env, no mocks required).
 */

// Sort orders the import pipeline can actually honor. Note: 'rating' is NOT here —
// staged videos have no rating yet, so it was never a real option.
export const VALID_IMPORT_SORTS = ['latest', 'oldest', 'alphabetical_az', 'alphabetical_za', 'views']

// Daily YouTube Data API budget (units)
export const YOUTUBE_DAILY_BUDGET = 10000

/**
 * Parse an ISO 8601 duration (PT2H30M15S) into whole minutes.
 * @param {string} iso
 * @returns {number}
 */
export function parseIsoDurationMinutes(iso) {
    if (!iso) return 0
    const match = iso.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/)
    if (!match) return 0
    const hours = parseInt(match[1]) || 0
    const minutes = parseInt(match[2]) || 0
    const seconds = parseInt(match[3]) || 0
    return hours * 60 + minutes + Math.floor(seconds / 60)
}

/**
 * Build a duration/shorts filter predicate from channel settings.
 * Returned predicate takes a video object (with a `.duration` ISO 8601 string)
 * and returns true if the video should be kept.
 *
 * @param {object|null} channelSettings
 * @returns {(video: object) => boolean}
 */
export function buildDurationFilter(channelSettings) {
    if (!channelSettings) {
        return () => true
    }

    const { min_duration_minutes, max_duration_minutes, filter_shorts } = channelSettings

    return (video) => {
        const durationMinutes = parseIsoDurationMinutes(video.duration)
        if (filter_shorts && durationMinutes < 1) return false
        if (min_duration_minutes && durationMinutes < min_duration_minutes) return false
        if (max_duration_minutes && durationMinutes > max_duration_minutes) return false
        return true
    }
}

/**
 * Sum quota_cost across api_usage rows.
 * @param {Array<{quota_cost?: number}>} rows
 * @returns {number}
 */
export function sumQuotaUnits(rows) {
    if (!Array.isArray(rows)) return 0
    return rows.reduce((sum, row) => sum + (parseInt(row?.quota_cost) || 0), 0)
}

/**
 * Check whether a string compiles as a RegExp.
 * @param {string} pattern
 * @returns {{ valid: boolean, error: string|null }}
 */
export function validateRegex(pattern) {
    try {
        new RegExp(pattern, 'i')
        return { valid: true, error: null }
    } catch (error) {
        return { valid: false, error: error.message }
    }
}

/**
 * Post-process a flat list of fetched videos the way the import pipeline does:
 * apply the filter, order (oldest reverses newest-first uploads), then limit.
 * Mirrors the collection/truncation logic in youtubeService.getChannelVideos so
 * it can be unit tested without network access.
 *
 * @param {Array} videos Newest-first list of videos
 * @param {object} opts
 * @param {(v: object) => boolean} [opts.filter]
 * @param {string} [opts.order] 'oldest' reverses
 * @param {number|null} [opts.limit]
 * @returns {Array}
 */
export function selectVideos(videos, { filter = null, order = null, limit = null } = {}) {
    let kept = filter ? videos.filter(filter) : videos.slice()
    if (order === 'oldest') {
        kept = kept.reverse()
    }
    if (limit && kept.length > limit) {
        kept = kept.slice(0, limit)
    }
    return kept
}
