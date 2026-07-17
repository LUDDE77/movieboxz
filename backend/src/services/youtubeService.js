import { google } from 'googleapis'
import { logger } from '../utils/logger.js'
import { dbOperations } from '../config/database.js'

class YouTubeService {
    constructor() {
        // Support multiple API keys for quota management
        // Format: YOUTUBE_API_KEY=key1,key2,key3 or separate env vars
        const primaryKey = process.env.YOUTUBE_API_KEY
        const secondaryKey = process.env.YOUTUBE_API_KEY_SECONDARY

        this.apiKeys = [primaryKey]
        if (secondaryKey && secondaryKey.trim() !== '') {
            this.apiKeys.push(secondaryKey.trim())
        }

        // Track quota per key
        this.currentKeyIndex = 0
        this.dailyQuota = parseInt(process.env.YOUTUBE_QUOTA_PER_DAY) || 10000
        this.quotaPerKey = this.apiKeys.map(() => ({
            used: 0,
            lastReset: new Date()
        }))

        // Initialize YouTube client with first key
        this.youtube = google.youtube({
            version: 'v3',
            auth: this.apiKeys[this.currentKeyIndex]
        })

        logger.info(`YouTube API initialized with ${this.apiKeys.length} API key(s)`)
    }

    switchToNextKey() {
        const nextIndex = (this.currentKeyIndex + 1) % this.apiKeys.length

        // Check if next key is also exhausted
        if (this.quotaPerKey[nextIndex].used >= this.dailyQuota) {
            // All keys exhausted
            if (nextIndex === 0) {
                logger.error('All YouTube API keys exhausted their quota')
                return false
            }
            // Try next key
            this.currentKeyIndex = nextIndex
            return this.switchToNextKey()
        }

        this.currentKeyIndex = nextIndex
        this.youtube = google.youtube({
            version: 'v3',
            auth: this.apiKeys[this.currentKeyIndex]
        })

        logger.info(`Switched to YouTube API key #${this.currentKeyIndex + 1} (quota: ${this.quotaPerKey[this.currentKeyIndex].used}/${this.dailyQuota})`)
        return true
    }

    // =============================================================================
    // HEALTH AND QUOTA MANAGEMENT
    // =============================================================================

    async healthCheck() {
        // Key presence check only — no API call.
        // search.list costs 100 quota units per call; calling it on every health ping
        // exhausts the daily 10,000-unit quota within hours.
        const hasKey = this.apiKeys.some(k => k && k.trim().length > 0)
        logger.info(`YouTube API health check: key configured = ${hasKey}`)
        return hasKey
    }

    async quotaCheck() {
        // Check if quota needs to reset for each key (daily reset)
        const now = new Date()
        this.quotaPerKey.forEach((quota, index) => {
            if (now.getDate() !== quota.lastReset.getDate()) {
                this.quotaPerKey[index].used = 0
                this.quotaPerKey[index].lastReset = now
            }
        })

        const currentQuota = this.quotaPerKey[this.currentKeyIndex]
        const totalUsed = this.quotaPerKey.reduce((sum, q) => sum + q.used, 0)
        const totalRemaining = (this.dailyQuota * this.apiKeys.length) - totalUsed

        return {
            currentKey: this.currentKeyIndex + 1,
            totalKeys: this.apiKeys.length,
            dailyLimit: this.dailyQuota,
            used: currentQuota.used,
            remaining: this.dailyQuota - currentQuota.used,
            totalUsed: totalUsed,
            totalRemaining: totalRemaining,
            resetTime: currentQuota.lastReset.toISOString()
        }
    }

    /**
     * Check quota BEFORE making an API call. Resets counters daily, and if the
     * current key cannot cover the cost, tries to switch keys. Throws an error
     * with code 'quotaExceeded' if the daily budget would be exceeded.
     */
    ensureQuota(cost = 1) {
        // Daily reset per key
        const now = new Date()
        this.quotaPerKey.forEach((quota, index) => {
            if (now.getDate() !== quota.lastReset.getDate()) {
                this.quotaPerKey[index].used = 0
                this.quotaPerKey[index].lastReset = now
            }
        })

        if (this.quotaPerKey[this.currentKeyIndex].used + cost <= this.dailyQuota) {
            return
        }

        // Current key can't cover the cost — try switching to another key
        const switched = this.switchToNextKey()
        if (switched && this.quotaPerKey[this.currentKeyIndex].used + cost <= this.dailyQuota) {
            return
        }

        const error = new Error(`YouTube API daily quota (${this.dailyQuota} units/key) would be exceeded by this call (cost: ${cost}). Quota resets at midnight Pacific time.`)
        error.code = 'quotaExceeded'
        throw error
    }

    updateQuotaUsage(cost) {
        this.quotaPerKey[this.currentKeyIndex].used += cost
        const currentUsed = this.quotaPerKey[this.currentKeyIndex].used

        if (currentUsed >= this.dailyQuota) {
            logger.warn(`YouTube API key #${this.currentKeyIndex + 1} quota exhausted: ${currentUsed}/${this.dailyQuota}`)

            // Try to switch to next key
            if (this.currentKeyIndex < this.apiKeys.length - 1) {
                const switched = this.switchToNextKey()
                if (switched) {
                    logger.info(`✅ Auto-switched to API key #${this.currentKeyIndex + 1}`)
                } else {
                    logger.error('❌ All API keys exhausted, quota limit reached')
                }
            }
        }
    }

    // =============================================================================
    // VIDEO OPERATIONS
    // =============================================================================

    async getVideoInfo(videoId) {
        const startTime = Date.now()

        try {
            logger.info(`Fetching YouTube video info: ${videoId}`)

            this.ensureQuota(1)
            const response = await this.youtube.videos.list({
                part: ['snippet', 'contentDetails', 'status', 'statistics'],
                id: [videoId]
            })

            this.updateQuotaUsage(1) // videos.list costs 1 unit per call

            // Log API usage
            await dbOperations.logApiUsage(
                'youtube',
                'videos.list',
                'GET',
                1,
                200,
                Date.now() - startTime
            )

            if (!response.data.items || response.data.items.length === 0) {
                throw new Error(`Video not found: ${videoId}`)
            }

            const video = response.data.items[0]

            return {
                id: video.id,
                title: video.snippet.title,
                description: video.snippet.description,
                channelId: video.snippet.channelId,
                channelTitle: video.snippet.channelTitle,
                publishedAt: video.snippet.publishedAt,
                thumbnails: video.snippet.thumbnails,
                duration: video.contentDetails.duration,
                definition: video.contentDetails.definition,
                embeddable: video.status.embeddable,
                uploadStatus: video.status.uploadStatus,
                privacyStatus: video.status.privacyStatus,
                viewCount: parseInt(video.statistics.viewCount) || 0,
                likeCount: parseInt(video.statistics.likeCount) || 0,
                commentCount: parseInt(video.statistics.commentCount) || 0,
                regionRestriction: video.contentDetails.regionRestriction
            }
        } catch (error) {
            logger.error(`Error fetching video ${videoId}:`, error.message)

            // Log failed API usage
            await dbOperations.logApiUsage(
                'youtube',
                'videos.list',
                'GET',
                1,
                error.response?.status || 500,
                Date.now() - startTime,
                error.message
            )

            throw error
        }
    }

    // Batch-fetch durations (in minutes) for many video IDs. videos.list accepts
    // up to 50 IDs per call and costs 1 quota unit per call regardless of count,
    // so this is ~1 unit per 50 videos. Returns a Map<videoId, minutes>. Video IDs
    // that YouTube no longer returns (deleted/private) are simply absent from the map.
    async getVideoDurations(videoIds) {
        const result = new Map()
        const ids = [...new Set((videoIds || []).filter(Boolean))]

        for (let i = 0; i < ids.length; i += 50) {
            const batch = ids.slice(i, i + 50)
            const startTime = Date.now()
            try {
                this.ensureQuota(1)
                const response = await this.youtube.videos.list({
                    part: ['contentDetails'],
                    id: batch,
                    maxResults: 50
                })
                this.updateQuotaUsage(1)
                await dbOperations.logApiUsage('youtube', 'videos.list', 'GET', 1, 200, Date.now() - startTime)

                for (const video of (response.data.items || [])) {
                    result.set(video.id, this.parseDuration(video.contentDetails?.duration))
                }
            } catch (error) {
                logger.error(`Error fetching durations for batch starting at ${i}:`, error.message)
                await dbOperations.logApiUsage('youtube', 'videos.list', 'GET', 1, error.response?.status || 500, Date.now() - startTime, error.message)
                throw error
            }
        }

        return result
    }

    async checkVideoAvailability(videoId) {
        try {
            const videoInfo = await this.getVideoInfo(videoId)

            const isAvailable = videoInfo.uploadStatus === 'processed' &&
                              videoInfo.privacyStatus === 'public'

            return {
                available: isAvailable,
                embeddable: videoInfo.embeddable,
                error: !isAvailable ? 'Video is private, unlisted, or removed' : null,
                details: {
                    uploadStatus: videoInfo.uploadStatus,
                    privacyStatus: videoInfo.privacyStatus,
                    viewCount: videoInfo.viewCount,
                    regionRestriction: videoInfo.regionRestriction
                }
            }
        } catch (error) {
            return {
                available: false,
                embeddable: false,
                error: error.message,
                details: null
            }
        }
    }

    /**
     * Fetch videos from a channel's uploads playlist.
     *
     * Supports fetch-before-filter semantics: pass a `filter` predicate and a
     * `postFilterLimit` and the method pages through the uploads playlist,
     * applying the filter as it goes, until `postFilterLimit` videos survive the
     * filter or the channel is exhausted (or the `safetyCap` of fetched videos is
     * hit). This prevents limited imports from under-delivering when many videos
     * are filtered out.
     *
     * @param {string} channelId
     * @param {object} options
     * @param {number} [options.maxResults=500] Upper bound on videos fetched when no postFilterLimit is given
     * @param {number|null} [options.postFilterLimit=null] Stop once this many videos survive the filter (ignored for order='oldest')
     * @param {function} [options.filter=null] Predicate (video) => boolean applied as pages are fetched
     * @param {string} [options.order=null] 'oldest' fetches everything (within safetyCap) then reverses; otherwise newest-first (playlist default)
     * @param {number} [options.safetyCap=2000] Hard cap on videos fetched before giving up
     * @param {string|null} [options.publishedAfter=null]
     * @param {string|null} [options.publishedBefore=null]
     * @returns {Promise<Array>} Array of video objects. A boolean `.truncated` property is attached to the array indicating the fetch stopped at the safety cap while more videos remained.
     */
    async getChannelVideos(channelId, options = {}) {
        const startTime = Date.now()

        try {
            const {
                maxResults = 500,
                postFilterLimit = null,
                filter = null,
                order = null,
                safetyCap = 2000,
                publishedAfter = null,
                publishedBefore = null
            } = options

            // For 'oldest' we must fetch the whole channel (within safetyCap) then reverse,
            // so we cannot early-stop on postFilterLimit.
            const isOldest = order === 'oldest'
            // Upper bound on how many videos to fetch (pre-filter). When a post-filter
            // limit or oldest ordering is requested, fetch up to the safety cap.
            const fetchCeiling = (postFilterLimit || isOldest) ? safetyCap : Math.min(maxResults, safetyCap)

            logger.info(`Fetching videos from channel: ${channelId} (via uploads playlist), ceiling: ${fetchCeiling}, postFilterLimit: ${postFilterLimit || 'none'}, order: ${order || 'newest'}`)

            // Step 1: Get the channel's uploads playlist ID — costs 1 unit (was 100 with search.list)
            this.ensureQuota(1)
            const channelResponse = await this.youtube.channels.list({
                part: ['contentDetails'],
                id: [channelId]
            })
            this.updateQuotaUsage(1)

            if (!channelResponse.data.items || channelResponse.data.items.length === 0) {
                throw new Error(`Channel not found: ${channelId}`)
            }

            const uploadsPlaylistId = channelResponse.data.items[0].contentDetails.relatedPlaylists.uploads
            logger.info(`Uploads playlist: ${uploadsPlaylistId}`)

            // Step 2: Fetch playlist pages — costs 1 unit/page (was 100 units/page with search.list)
            let allVideos = []        // videos surviving the filter
            let nextPageToken = null
            let totalFetched = 0      // pre-filter videos fetched
            let collected = 0         // post-filter videos collected
            let pageCount = 0
            let totalQuotaUsed = 1 // channels.list above
            let truncated = false

            do {
                pageCount++
                const pageSize = Math.min(50, fetchCeiling - totalFetched)

                this.ensureQuota(1)
                const playlistResponse = await this.youtube.playlistItems.list({
                    part: ['contentDetails', 'snippet'],
                    playlistId: uploadsPlaylistId,
                    maxResults: pageSize,
                    pageToken: nextPageToken
                })
                this.updateQuotaUsage(1) // playlistItems.list costs 1 unit
                totalQuotaUsed += 1

                if (!playlistResponse.data.items || playlistResponse.data.items.length === 0) {
                    nextPageToken = null
                    break
                }

                // Filter by date if requested (playlist API has no date filter — filter client-side)
                let items = playlistResponse.data.items
                if (publishedAfter || publishedBefore) {
                    const after = publishedAfter ? new Date(publishedAfter) : null
                    const before = publishedBefore ? new Date(publishedBefore) : null
                    items = items.filter(item => {
                        const pub = new Date(item.snippet.publishedAt)
                        if (after && pub < after) return false
                        if (before && pub > before) return false
                        return true
                    })
                }

                const videoIds = items
                    .map(item => item.contentDetails?.videoId)
                    .filter(Boolean)

                nextPageToken = playlistResponse.data.nextPageToken

                if (videoIds.length === 0) {
                    continue
                }

                // Step 3: Get full video details — costs 1 unit per page of 50
                this.ensureQuota(1)
                const videosResponse = await this.youtube.videos.list({
                    part: ['snippet', 'contentDetails', 'status', 'statistics'],
                    id: videoIds
                })
                this.updateQuotaUsage(1)
                totalQuotaUsed += 1

                const videos = videosResponse.data.items.map(video => ({
                    id: video.id,
                    title: video.snippet.title,
                    description: video.snippet.description,
                    channelId: video.snippet.channelId,
                    channelTitle: video.snippet.channelTitle,
                    publishedAt: video.snippet.publishedAt,
                    thumbnails: video.snippet.thumbnails,
                    duration: video.contentDetails.duration,
                    embeddable: video.status.embeddable,
                    uploadStatus: video.status.uploadStatus,
                    privacyStatus: video.status.privacyStatus,
                    viewCount: parseInt(video.statistics.viewCount) || 0,
                    likeCount: parseInt(video.statistics.likeCount) || 0,
                    commentCount: parseInt(video.statistics.commentCount) || 0,
                    regionRestriction: video.contentDetails.regionRestriction || null
                }))

                totalFetched += videos.length

                // Apply the caller's filter as we go so limited imports don't under-deliver
                for (const video of videos) {
                    if (filter && !filter(video)) continue
                    allVideos.push(video)
                    collected++
                }

                logger.info(`Page ${pageCount}: fetched ${videos.length} (kept ${allVideos.length}/${totalFetched}, quota: ${totalQuotaUsed} units)`)

                // Early-stop once enough videos survive the filter (not for 'oldest', which needs the full set)
                if (!isOldest && postFilterLimit && collected >= postFilterLimit) {
                    break
                }

                await new Promise(resolve => setTimeout(resolve, 100))

            } while (nextPageToken && totalFetched < fetchCeiling)

            // Stopped at the safety cap while more videos remained on the channel
            if (nextPageToken && totalFetched >= fetchCeiling) {
                truncated = true
                logger.warn(`⚠️ Stopped at safety cap of ${fetchCeiling} fetched videos for channel ${channelId} — channel not fully exhausted`)
            }

            // 'oldest' — uploads playlist is newest-first, so reverse to get oldest-first
            if (isOldest) {
                allVideos.reverse()
            }

            // Apply the post-filter limit after ordering
            if (postFilterLimit && allVideos.length > postFilterLimit) {
                allVideos = allVideos.slice(0, postFilterLimit)
            }

            logger.info(`✅ Fetched ${totalFetched} videos in ${pageCount} page(s), kept ${allVideos.length}, using ${totalQuotaUsed} quota units (was ~${pageCount * 101} with search.list)`)

            await dbOperations.logApiUsage(
                'youtube',
                `playlistItems.list + videos.list (${pageCount} pages)`,
                'GET',
                totalQuotaUsed,
                200,
                Date.now() - startTime
            )

            // Attach truncation flag to the array (non-breaking for callers that ignore it)
            allVideos.truncated = truncated
            return allVideos

        } catch (error) {
            logger.error(`Error fetching channel videos ${channelId}:`, error.message)

            await dbOperations.logApiUsage(
                'youtube',
                'playlistItems.list + videos.list',
                'GET',
                0,
                error.response?.status || 500,
                Date.now() - startTime,
                error.message
            )

            throw error
        }
    }

    /**
     * Resolve channel identifier to channel ID
     * Supports: channel IDs (UC...), @handles, and pasted URLs
     * (youtube.com/channel/UC..., youtube.com/@handle, youtube.com/c/name, youtube.com/user/name)
     */
    async resolveChannelIdentifier(identifier) {
        let cleanIdentifier = String(identifier).trim()

        // Full URL — extract the channel ID or handle before hitting the API
        if (cleanIdentifier.startsWith('http')) {
            const url = new URL(cleanIdentifier)

            // Format: youtube.com/channel/UC...
            if (url.pathname.startsWith('/channel/')) {
                const channelId = url.pathname.split('/channel/')[1].split('/')[0]
                logger.info(`Extracted channel ID from URL: ${channelId}`)
                return channelId
            }

            // Format: youtube.com/@handle
            if (url.pathname.startsWith('/@')) {
                cleanIdentifier = url.pathname.split('/@')[1].split('/')[0]
                logger.info(`Extracted handle from URL: @${cleanIdentifier}`)
            } else if (url.pathname.startsWith('/c/') || url.pathname.startsWith('/user/')) {
                // Format: youtube.com/c/name or youtube.com/user/name
                cleanIdentifier = url.pathname.split('/')[2]
                logger.info(`Extracted username from URL: ${cleanIdentifier}`)
            }
        }

        // Remove any leading @ symbol
        if (cleanIdentifier.startsWith('@')) {
            cleanIdentifier = cleanIdentifier.substring(1)
        }

        // If it looks like a channel ID (starts with UC), return as-is
        if (cleanIdentifier.startsWith('UC')) {
            return cleanIdentifier
        }

        // Otherwise, treat as handle and look up (channels.list = 1 unit, never search.list)
        logger.info(`Resolving @${cleanIdentifier} to channel ID`)

        try {
            this.ensureQuota(1)
            const response = await this.youtube.channels.list({
                part: ['id'],
                forHandle: cleanIdentifier,
                maxResults: 1
            })

            this.updateQuotaUsage(1)

            if (!response.data.items || response.data.items.length === 0) {
                throw new Error(`Channel not found with handle: @${cleanIdentifier}`)
            }

            const channelId = response.data.items[0].id
            logger.info(`Resolved @${cleanIdentifier} → ${channelId}`)
            return channelId
        } catch (error) {
            logger.error(`Failed to resolve @${cleanIdentifier}:`, error.message)
            throw new Error(`Channel not found: ${identifier}`)
        }
    }

    async getChannelInfo(channelIdOrHandle) {
        const startTime = Date.now()

        try {
            logger.info(`Fetching YouTube channel info: ${channelIdOrHandle}`)

            // Resolve handle to channel ID if needed
            const channelId = await this.resolveChannelIdentifier(channelIdOrHandle)

            this.ensureQuota(1)
            const response = await this.youtube.channels.list({
                part: ['snippet', 'statistics', 'status', 'brandingSettings'],
                id: [channelId]
            })

            this.updateQuotaUsage(1) // channels.list costs 1 unit

            await dbOperations.logApiUsage(
                'youtube',
                'channels.list',
                'GET',
                1,
                200,
                Date.now() - startTime
            )

            if (!response.data.items || response.data.items.length === 0) {
                throw new Error(`Channel not found: ${channelIdOrHandle}`)
            }

            const channel = response.data.items[0]

            return {
                id: channel.id,
                title: channel.snippet.title,
                description: channel.snippet.description,
                customUrl: channel.snippet.customUrl,
                thumbnails: channel.snippet.thumbnails,
                bannerImageUrl: channel.brandingSettings?.image?.bannerExternalUrl,
                publishedAt: channel.snippet.publishedAt,
                country: channel.snippet.country,
                subscriberCount: parseInt(channel.statistics.subscriberCount) || 0,
                viewCount: parseInt(channel.statistics.viewCount) || 0,
                videoCount: parseInt(channel.statistics.videoCount) || 0,
                isVerified: channel.status?.isLinked || false
            }
        } catch (error) {
            logger.error(`Error fetching channel ${channelIdOrHandle}:`, error.message)

            await dbOperations.logApiUsage(
                'youtube',
                'channels.list',
                'GET',
                1,
                error.response?.status || 500,
                Date.now() - startTime,
                error.message
            )

            throw error
        }
    }

    /**
     * Get videos from a YouTube playlist
     * @param {string} playlistId - The playlist ID
     * @param {object} options - Options for fetching
     * @param {number} options.maxResults - Maximum number of videos to fetch (default: 500)
     * @returns {Promise<Array>} Array of video objects
     */
    async getPlaylistItems(playlistId, options = {}) {
        const startTime = Date.now()

        try {
            const { maxResults = 500 } = options

            logger.info(`Fetching up to ${maxResults} videos from playlist: ${playlistId}`)

            let allVideos = []
            let nextPageToken = null
            let totalFetched = 0
            let pageCount = 0
            let totalQuotaUsed = 0

            // Loop to fetch all pages until we reach maxResults or no more pages
            do {
                pageCount++
                const pageSize = Math.min(50, maxResults - totalFetched)  // API max is 50 per request

                // Get playlist items
                const playlistParams = {
                    part: ['snippet', 'contentDetails'],
                    playlistId: playlistId,
                    maxResults: pageSize,
                    pageToken: nextPageToken
                }

                logger.info(`Fetching playlist page ${pageCount} (${pageSize} items)...`)

                this.ensureQuota(1)
                const playlistResponse = await this.youtube.playlistItems.list(playlistParams)
                this.updateQuotaUsage(1) // playlistItems.list costs 1 unit
                totalQuotaUsed += 1

                if (!playlistResponse.data.items || playlistResponse.data.items.length === 0) {
                    logger.info('No more videos found in playlist')
                    break
                }

                // Get video IDs for detailed info
                const videoIds = playlistResponse.data.items
                    .map(item => item.contentDetails?.videoId)
                    .filter(Boolean)

                // Get detailed video information
                this.ensureQuota(1)
                const videosResponse = await this.youtube.videos.list({
                    part: ['snippet', 'contentDetails', 'status', 'statistics'],
                    id: videoIds
                })

                this.updateQuotaUsage(1) // videos.list costs 1 unit
                totalQuotaUsed += 1

                // Map video data
                const videos = videosResponse.data.items.map(video => ({
                    id: video.id,
                    title: video.snippet.title,
                    description: video.snippet.description,
                    channelId: video.snippet.channelId,
                    channelTitle: video.snippet.channelTitle,
                    publishedAt: video.snippet.publishedAt,
                    thumbnails: video.snippet.thumbnails,
                    duration: video.contentDetails.duration,
                    embeddable: video.status.embeddable,
                    uploadStatus: video.status.uploadStatus,
                    privacyStatus: video.status.privacyStatus,
                    viewCount: parseInt(video.statistics.viewCount) || 0,
                    likeCount: parseInt(video.statistics.likeCount) || 0,
                    commentCount: parseInt(video.statistics.commentCount) || 0,
                    regionRestriction: video.contentDetails.regionRestriction || null
                }))

                allVideos.push(...videos)
                totalFetched += videos.length

                // Get next page token
                nextPageToken = playlistResponse.data.nextPageToken

                logger.info(`Fetched ${videos.length} videos (Total: ${totalFetched}/${maxResults}, Quota: ${totalQuotaUsed} units)`)

                // Small delay to avoid rate limiting (100ms)
                await new Promise(resolve => setTimeout(resolve, 100))

            } while (nextPageToken && totalFetched < maxResults)

            logger.info(`✅ Completed fetching ${totalFetched} videos from playlist across ${pageCount} page(s), used ${totalQuotaUsed} quota units`)

            // Log API usage
            await dbOperations.logApiUsage(
                'youtube',
                `playlistItems.list + videos.list (${pageCount} pages)`,
                'GET',
                totalQuotaUsed,
                200,
                Date.now() - startTime
            )

            return allVideos

        } catch (error) {
            logger.error(`Error fetching playlist items ${playlistId}:`, error.message)

            await dbOperations.logApiUsage(
                'youtube',
                'playlistItems.list + videos.list',
                'GET',
                0,
                error.response?.status || 500,
                Date.now() - startTime,
                error.message
            )

            throw error
        }
    }

    // =============================================================================
    // MOVIE DISCOVERY HELPERS
    // =============================================================================

    isLikelyMovie(video) {
        const title = video.title.toLowerCase()
        const description = video.description?.toLowerCase() || ''

        // Duration check (movies are typically 60+ minutes)
        const duration = this.parseDuration(video.duration)
        if (duration < 60) {
            return false
        }

        // Negative keywords that suggest it's NOT a movie
        const negativeKeywords = [
            'trailer',
            'clip',
            'scene',
            'making of',
            'behind the scenes',
            'interview',
            'review',
            'analysis',
            'reaction',
            'part 1',
            'part 2',
            'episode',
            'documentary' // Added: most movie channels don't include documentaries
        ]

        // Check for negative keywords
        const hasNegativeKeyword = negativeKeywords.some(keyword =>
            title.includes(keyword) || description.includes(keyword)
        )

        // For dedicated movie channels, any 60+ minute video without negative keywords
        // is likely a full movie (even if title is just "Casablanca (1942)")
        return !hasNegativeKeyword
    }

    parseDuration(isoDuration) {
        if (!isoDuration) return 0

        const match = isoDuration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/)
        if (!match) return 0

        const hours = parseInt(match[1]) || 0
        const minutes = parseInt(match[2]) || 0
        const seconds = parseInt(match[3]) || 0

        return hours * 60 + minutes + Math.floor(seconds / 60)
    }

    // =============================================================================
    // OAUTH OPERATIONS (for user authentication)
    // =============================================================================

    async exchangeCodeForTokens(code, redirectUri) {
        try {
            const oauth2Client = new google.auth.OAuth2(
                process.env.YOUTUBE_OAUTH_CLIENT_ID,
                process.env.YOUTUBE_OAUTH_CLIENT_SECRET,
                redirectUri
            )

            const { tokens } = await oauth2Client.getToken(code)
            oauth2Client.setCredentials(tokens)

            // Get user info
            const youtube = google.youtube({
                version: 'v3',
                auth: oauth2Client
            })

            const channelResponse = await youtube.channels.list({
                part: ['snippet'],
                mine: true
            })

            let userInfo = null
            if (channelResponse.data.items && channelResponse.data.items.length > 0) {
                const channel = channelResponse.data.items[0]
                userInfo = {
                    youtubeChannelId: channel.id,
                    displayName: channel.snippet.title,
                    thumbnailUrl: channel.snippet.thumbnails?.default?.url
                }
            }

            return {
                accessToken: tokens.access_token,
                refreshToken: tokens.refresh_token,
                expiresAt: new Date(tokens.expiry_date).toISOString(),
                userInfo
            }
        } catch (error) {
            logger.error('Error exchanging OAuth code:', error.message)
            throw error
        }
    }

    async refreshAccessToken(refreshToken) {
        try {
            const oauth2Client = new google.auth.OAuth2(
                process.env.YOUTUBE_OAUTH_CLIENT_ID,
                process.env.YOUTUBE_OAUTH_CLIENT_SECRET
            )

            oauth2Client.setCredentials({
                refresh_token: refreshToken
            })

            const { credentials } = await oauth2Client.refreshAccessToken()

            return {
                accessToken: credentials.access_token,
                expiresAt: new Date(credentials.expiry_date).toISOString()
            }
        } catch (error) {
            logger.error('Error refreshing access token:', error.message)
            throw error
        }
    }
}

export const youtubeService = new YouTubeService()
export default youtubeService
