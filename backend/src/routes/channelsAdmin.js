import express from 'express'
import { supabase } from '../config/database.js'
import { youtubeService } from '../services/youtubeService.js'
import channelPatternManager from '../services/channelPatternManager.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// GET /api/admin/channels - List all channels with patterns
router.get('/', async (req, res, next) => {
    try {
        const { data: channels, error } = await supabase
            .from('channels')
            .select(`
                *,
                channel_patterns(*)
            `)
            .order('title')

        if (error) throw error

        // Format response
        const formattedChannels = (channels || []).map(channel => ({
            id: channel.id,
            title: channel.title,
            description: channel.description,
            thumbnail_url: channel.thumbnail_url,
            subscriber_count: channel.subscriber_count,
            video_count: channel.video_count,
            is_curated: channel.is_curated,
            has_pattern: channel.channel_patterns && channel.channel_patterns.length > 0,
            pattern: channel.channel_patterns?.[0] || null,
            created_at: channel.created_at,
            updated_at: channel.updated_at
        }))

        res.json({
            success: true,
            data: {
                channels: formattedChannels,
                total: formattedChannels.length
            }
        })
    } catch (error) {
        logger.error('[Channels Admin] List error:', error)
        next(error)
    }
})

// POST /api/admin/channels - Add a new channel
router.post('/', async (req, res, next) => {
    try {
        const { channelId } = req.body

        if (!channelId) {
            return res.status(400).json({
                success: false,
                error: 'Missing required field: channelId'
            })
        }

        // Check if channel already exists
        const { data: existing } = await supabase
            .from('channels')
            .select('id')
            .eq('id', channelId)
            .single()

        if (existing) {
            return res.status(409).json({
                success: false,
                error: 'Channel already exists'
            })
        }

        // Fetch channel info from YouTube
        logger.info(`[Channels Admin] Fetching info for channel: ${channelId}`)
        const channelInfo = await youtubeService.getChannelInfo(channelId)

        // Create channel record
        const { data: newChannel, error } = await supabase
            .from('channels')
            .insert({
                id: channelId,
                title: channelInfo.title,
                description: channelInfo.description,
                thumbnail_url: channelInfo.thumbnails?.high?.url || channelInfo.thumbnails?.default?.url,
                banner_url: channelInfo.bannerImageUrl,
                subscriber_count: parseInt(channelInfo.subscriberCount) || 0,
                video_count: parseInt(channelInfo.videoCount) || 0,
                view_count: parseInt(channelInfo.viewCount) || 0,
                country: channelInfo.country,
                is_curated: false
            })
            .select()
            .single()

        if (error) throw error

        logger.info(`[Channels Admin] Added channel: ${channelInfo.title}`)

        res.json({
            success: true,
            data: newChannel,
            message: `Channel "${channelInfo.title}" added successfully`
        })
    } catch (error) {
        logger.error('[Channels Admin] Add channel error:', error)
        next(error)
    }
})

// GET /api/admin/channels/:id/pattern - Get channel pattern
router.get('/:id/pattern', async (req, res, next) => {
    try {
        const { id } = req.params

        const pattern = await channelPatternManager.getPattern(id)

        if (!pattern) {
            return res.json({
                success: true,
                data: null,
                message: 'No pattern configured for this channel'
            })
        }

        res.json({
            success: true,
            data: pattern
        })
    } catch (error) {
        logger.error('[Channels Admin] Get pattern error:', error)
        next(error)
    }
})

// PUT /api/admin/channels/:id/pattern - Update channel pattern
router.put('/:id/pattern', async (req, res, next) => {
    try {
        const { id } = req.params
        const { channelName, patterns, fallbackPattern } = req.body

        if (!patterns || !Array.isArray(patterns) || patterns.length === 0) {
            return res.status(400).json({
                success: false,
                error: 'Missing or invalid patterns array'
            })
        }

        // Validate pattern structure
        for (const pattern of patterns) {
            if (!pattern.regex || !pattern.parameters) {
                return res.status(400).json({
                    success: false,
                    error: 'Each pattern must have "regex" and "parameters" fields'
                })
            }
        }

        // Get channel name if not provided
        let name = channelName
        if (!name) {
            const { data: channel } = await supabase
                .from('channels')
                .select('title')
                .eq('id', id)
                .single()
            name = channel?.title || id
        }

        // Save pattern
        const savedPattern = await channelPatternManager.savePattern(
            id,
            name,
            patterns,
            fallbackPattern
        )

        logger.info(`[Channels Admin] Updated pattern for channel: ${name}`)

        res.json({
            success: true,
            data: savedPattern,
            message: `Pattern updated for "${name}"`
        })
    } catch (error) {
        logger.error('[Channels Admin] Update pattern error:', error)
        next(error)
    }
})

// DELETE /api/admin/channels/:id/pattern - Delete channel pattern
router.delete('/:id/pattern', async (req, res, next) => {
    try {
        const { id } = req.params

        await channelPatternManager.deletePattern(id)

        logger.info(`[Channels Admin] Deleted pattern for channel: ${id}`)

        res.json({
            success: true,
            message: 'Pattern deleted successfully'
        })
    } catch (error) {
        logger.error('[Channels Admin] Delete pattern error:', error)
        next(error)
    }
})

// POST /api/admin/channels/:id/test-pattern - Test a pattern against sample videos
router.post('/:id/test-pattern', async (req, res, next) => {
    try {
        const { id } = req.params
        const { patterns, fallbackPattern, sampleCount = 5 } = req.body

        if (!patterns || !Array.isArray(patterns)) {
            return res.status(400).json({
                success: false,
                error: 'Missing or invalid patterns array'
            })
        }

        // Fetch sample videos from channel
        logger.info(`[Channels Admin] Fetching ${sampleCount} sample videos for pattern testing`)
        const videos = await youtubeService.getChannelVideos(id, {
            maxResults: sampleCount,
            fetchDetails: false
        })

        // Test pattern on each video
        const results = []
        for (const video of videos) {
            const testPattern = {
                patterns: patterns.map(p => ({
                    ...p,
                    regex: new RegExp(p.regex, 'i')
                })),
                fallback_pattern: fallbackPattern
            }

            const extracted = channelPatternManager.extractMetadata(video.title, testPattern)

            results.push({
                youtubeTitle: video.title,
                extracted: extracted || { error: 'No match' },
                matched: !!extracted
            })
        }

        const matchRate = (results.filter(r => r.matched).length / results.length) * 100

        res.json({
            success: true,
            data: {
                results,
                matchRate: matchRate.toFixed(1) + '%',
                matched: results.filter(r => r.matched).length,
                total: results.length
            }
        })
    } catch (error) {
        logger.error('[Channels Admin] Test pattern error:', error)
        next(error)
    }
})

// DELETE /api/admin/channels/:id - Delete a channel
router.delete('/:id', async (req, res, next) => {
    try {
        const { id } = req.params

        // Check if channel has movies
        const { count } = await supabase
            .from('movies')
            .select('*', { count: 'exact', head: true })
            .eq('channel_id', id)

        if (count && count > 0) {
            return res.status(409).json({
                success: false,
                error: `Cannot delete channel with ${count} movies. Delete movies first.`
            })
        }

        // Delete channel pattern first
        await channelPatternManager.deletePattern(id)

        // Delete channel
        const { error } = await supabase
            .from('channels')
            .delete()
            .eq('id', id)

        if (error) throw error

        logger.info(`[Channels Admin] Deleted channel: ${id}`)

        res.json({
            success: true,
            message: 'Channel deleted successfully'
        })
    } catch (error) {
        logger.error('[Channels Admin] Delete channel error:', error)
        next(error)
    }
})

export default router
