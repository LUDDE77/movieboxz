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
        if (secondaryKey) {
            this.apiKeys.push(secondaryKey)
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
        try {
            // Simple API call to test connection
            await this.youtube.search.list({
                part: ['snippet'],
                q: 'test',
                maxResults: 1,
                type: 'video'
            })

            return true
        } catch (error) {
            logger.error('YouTube API health check failed:', error.message)
            return false
        }
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

    async getChannelVideos(channelId, options = {}) {
        const startTime = Date.now()

        try {
            const {
                maxResults = 500,  // Increased default from 50 to 500
                order = 'date',
                publishedAfter = null,
                publishedBefore = null
            } = options

            logger.info(`Fetching up to ${maxResults} videos from channel: ${channelId}`)

            let allVideos = []
            let nextPageToken = null
            let totalFetched = 0
            let pageCount = 0
            let totalQuotaUsed = 0

            // Loop to fetch all pages until we reach maxResults or no more pages
            do {
                pageCount++
                const pageSize = Math.min(50, maxResults - totalFetched)  // API max is 50 per request

                // Search for videos in the channel
                const searchParams = {
                    part: ['snippet'],
                    channelId: channelId,
                    type: 'video',
                    order: order,
                    maxResults: pageSize,
                    pageToken: nextPageToken  // Pagination support
                }

                if (publishedAfter) {
                    searchParams.publishedAfter = publishedAfter
                }

                if (publishedBefore) {
                    searchParams.publishedBefore = publishedBefore
                }

                logger.info(`Fetching page ${pageCount} (${pageSize} videos)...`)

                const searchResponse = await this.youtube.search.list(searchParams)
                this.updateQuotaUsage(100) // search.list costs 100 units
                totalQuotaUsed += 100

                if (!searchResponse.data.items || searchResponse.data.items.length === 0) {
                    logger.info('No more videos found')
                    break
                }

                // Get video IDs for detailed info
                const videoIds = searchResponse.data.items.map(item => item.id.videoId)

                // Get detailed video information
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
                    commentCount: parseInt(video.statistics.commentCount) || 0
                }))

                allVideos.push(...videos)
                totalFetched += videos.length

                // Get next page token
                nextPageToken = searchResponse.data.nextPageToken

                logger.info(`Fetched ${videos.length} videos (Total: ${totalFetched}/${maxResults}, Quota: ${totalQuotaUsed} units)`)

                // Small delay to avoid rate limiting (100ms)
                await new Promise(resolve => setTimeout(resolve, 100))

            } while (nextPageToken && totalFetched < maxResults)

            logger.info(`✅ Completed fetching ${totalFetched} videos across ${pageCount} page(s), used ${totalQuotaUsed} quota units`)

            // Log API usage
            await dbOperations.logApiUsage(
                'youtube',
                `search.list + videos.list (${pageCount} pages)`,
                'GET',
                totalQuotaUsed,
                200,
                Date.now() - startTime
            )

            return allVideos

        } catch (error) {
            logger.error(`Error fetching channel videos ${channelId}:`, error.message)

            await dbOperations.logApiUsage(
                'youtube',
                'search.list + videos.list',
                'GET',
                0,
                error.response?.status || 500,
                Date.now() - startTime,
                error.message
            )

            throw error
        }
    }

    async resolveChannelIdentifier(identifier) {
        const startTime = Date.now()

        try {
            logger.info(`Resolving channel identifier: ${identifier}`)

            // Case 1: Direct channel ID (starts with UC)
            if (identifier.match(/^UC[\w-]{22}$/)) {
                logger.info('Identifier is a direct channel ID')
                return identifier
            }

            // Case 2: Full URL - extract channel ID or username
            if (identifier.startsWith('http')) {
                const url = new URL(identifier)

                // Format: youtube.com/channel/UC...
                if (url.pathname.startsWith('/channel/')) {
                    const channelId = url.pathname.split('/channel/')[1].split('/')[0]
                    logger.info(`Extracted channel ID from URL: ${channelId}`)
                    return channelId
                }

                // Format: youtube.com/@username
                if (url.pathname.startsWith('/@')) {
                    const username = url.pathname.split('/@')[1].split('/')[0]
                    logger.info(`Extracted username from URL: @${username}`)
                    identifier = username // Continue to search by username
                }

                // Format: youtube.com/c/username or youtube.com/user/username
                if (url.pathname.startsWith('/c/') || url.pathname.startsWith('/user/')) {
                    const username = url.pathname.split('/')[2].split('/')[0]
                    logger.info(`Extracted username from URL: ${username}`)
                    identifier = username // Continue to search by username
                }
            }

            // Case 3: Username or @username - search for channel
            const username = identifier.startsWith('@') ? identifier.substring(1) : identifier

            logger.info(`Searching for channel by username: ${username}`)

            const searchResponse = await this.youtube.search.list({
                part: ['snippet'],
                q: username,
                type: 'channel',
                maxResults: 5
            })

            this.updateQuotaUsage(100) // search.list costs 100 units

            await dbOperations.logApiUsage(
                'youtube',
                'search.list',
                'GET',
                100,
                200,
                Date.now() - startTime
            )

            if (!searchResponse.data.items || searchResponse.data.items.length === 0) {
                throw new Error(`No channel found matching: ${identifier}`)
            }

            // Try to find exact match first
            const exactMatch = searchResponse.data.items.find(item => {
                const channelTitle = item.snippet.title.toLowerCase()
                const customUrl = item.snippet.customUrl?.toLowerCase() || ''
                const searchTerm = username.toLowerCase()

                return channelTitle === searchTerm ||
                       customUrl === searchTerm ||
                       customUrl === `@${searchTerm}`
            })

            const channel = exactMatch || searchResponse.data.items[0]
            const channelId = channel.id.channelId

            logger.info(`Resolved to channel: ${channel.snippet.title} (${channelId})`)

            return channelId

        } catch (error) {
            logger.error(`Error resolving channel identifier ${identifier}:`, error.message)

            await dbOperations.logApiUsage(
                'youtube',
                'resolveChannelIdentifier',
                'GET',
                100,
                error.response?.status || 500,
                Date.now() - startTime,
                error.message
            )

            throw error
        }
    }

    async getChannelInfo(channelId) {
        const startTime = Date.now()

        try {
            logger.info(`Fetching YouTube channel info: ${channelId}`)

            const response = await this.youtube.channels.list({
                part: ['snippet', 'statistics', 'status'],
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
                throw new Error(`Channel not found: ${channelId}`)
            }

            const channel = response.data.items[0]

            return {
                id: channel.id,
                title: channel.snippet.title,
                description: channel.snippet.description,
                customUrl: channel.snippet.customUrl,
                thumbnailUrl: channel.snippet.thumbnails?.default?.url,
                bannerUrl: channel.snippet.thumbnails?.high?.url,
                publishedAt: channel.snippet.publishedAt,
                country: channel.snippet.country,
                subscriberCount: parseInt(channel.statistics.subscriberCount) || 0,
                viewCount: parseInt(channel.statistics.viewCount) || 0,
                videoCount: parseInt(channel.statistics.videoCount) || 0,
                isVerified: channel.status?.isLinked || false
            }
        } catch (error) {
            logger.error(`Error fetching channel ${channelId}:`, error.message)

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
