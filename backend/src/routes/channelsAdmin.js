import express from 'express'
import { supabase } from '../config/database.js'
import { youtubeService } from '../services/youtubeService.js'
import channelPatternManager from '../services/channelPatternManager.js'
import { logger } from '../utils/logger.js'
import { adminAuth } from '../middleware/adminAuth.js'

const router = express.Router()

// Apply admin auth to all channel admin routes
router.use(adminAuth)

// GET /api/admin/channels - List all channels with patterns
router.get('/', async (req, res, next) => {
    try {
        // Fetch all channels
        const { data: channels, error: channelsError } = await supabase
            .from('channels')
            .select('*')
            .order('title')

        if (channelsError) throw channelsError

        // Fetch all active patterns
        const { data: patterns, error: patternsError } = await supabase
            .from('channel_patterns')
            .select('*')
            .eq('is_active', true)

        if (patternsError) throw patternsError

        // Create a map of channel_id -> pattern
        const patternMap = new Map()
        if (patterns) {
            patterns.forEach(pattern => {
                patternMap.set(pattern.channel_id, pattern)
            })
        }

        logger.info(`[Channels Admin] Fetched ${channels?.length || 0} channels and ${patterns?.length || 0} patterns`)

        // Format response - merge channels with their patterns
        const formattedChannels = (channels || []).map(channel => {
            const pattern = patternMap.get(channel.id) || null

            return {
                id: channel.id,
                title: channel.title,
                description: channel.description,
                thumbnail_url: channel.thumbnail_url,
                subscriber_count: channel.subscriber_count,
                video_count: channel.video_count,
                is_curated: channel.is_curated,
                has_pattern: pattern !== null,
                pattern: pattern,
                // Content type flags
                has_movies: channel.has_movies !== false, // defaults to true
                has_series: channel.has_series || false,
                has_kids_content: channel.has_kids_content || false,
                // Pattern source
                pattern_source: channel.pattern_source || 'title',
                created_at: channel.created_at,
                updated_at: channel.updated_at
            }
        })

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

        // Fetch channel info from YouTube (resolves handles to channel IDs)
        logger.info(`[Channels Admin] Fetching info for channel: ${channelId}`)
        const channelInfo = await youtubeService.getChannelInfo(channelId)

        // Check if channel already exists using resolved ID
        const { data: existingResolved } = await supabase
            .from('channels')
            .select('id')
            .eq('id', channelInfo.id)
            .single()

        if (existingResolved) {
            return res.status(409).json({
                success: false,
                error: 'Channel already exists'
            })
        }

        // Create channel record using resolved channel ID
        const { data: newChannel, error } = await supabase
            .from('channels')
            .insert({
                id: channelInfo.id,
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

        // Validate pattern structure and that each regex compiles
        for (const pattern of patterns) {
            if (!pattern.regex || !pattern.parameters) {
                return res.status(400).json({
                    success: false,
                    error: 'Each pattern must have "regex" and "parameters" fields'
                })
            }
            try {
                new RegExp(pattern.regex, 'i')
            } catch (regexError) {
                return res.status(400).json({
                    success: false,
                    error: `Invalid regex "${pattern.regex}": ${regexError.message}`
                })
            }
        }

        // Validate the fallback regex if provided
        if (fallbackPattern && fallbackPattern.regex) {
            try {
                new RegExp(fallbackPattern.regex, 'i')
            } catch (regexError) {
                return res.status(400).json({
                    success: false,
                    error: `Invalid fallback regex "${fallbackPattern.regex}": ${regexError.message}`
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
// Body: { patterns, fallbackPattern, sampleCount (1-50, default 5),
//         sampleMode: 'newest'|'oldest'|'random', sampleTitles: [strings] }
// When sampleTitles is provided, the pattern is tested against those titles
// instead of fetching videos from YouTube (saves quota).
router.post('/:id/test-pattern', async (req, res, next) => {
    try {
        const { id } = req.params
        const {
            patterns,
            fallbackPattern,
            sampleMode = 'newest',
            sampleTitles = null
        } = req.body

        // Clamp sampleCount to 1-50 (default 5)
        let sampleCount = parseInt(req.body.sampleCount) || 5
        sampleCount = Math.max(1, Math.min(50, sampleCount))

        if (!patterns || !Array.isArray(patterns)) {
            return res.status(400).json({
                success: false,
                error: 'Missing or invalid patterns array'
            })
        }

        // Compile the pattern regexes up front so a bad regex returns 400 (not 500)
        let testPattern
        try {
            testPattern = {
                patterns: patterns.map(p => ({
                    ...p,
                    regex: new RegExp(p.regex, 'i')
                })),
                fallback_pattern: fallbackPattern
            }
        } catch (regexError) {
            return res.status(400).json({
                success: false,
                error: `Invalid regex: ${regexError.message}`
            })
        }

        // Determine the titles to test against
        let titles
        if (Array.isArray(sampleTitles) && sampleTitles.length > 0) {
            // Test against caller-supplied titles — no YouTube fetch
            titles = sampleTitles.slice(0, sampleCount)
        } else {
            logger.info(`[Channels Admin] Fetching ${sampleCount} sample videos (${sampleMode}) for pattern testing`)
            const videos = await youtubeService.getChannelVideos(id, {
                maxResults: sampleMode === 'random' ? Math.max(sampleCount * 4, 50) : sampleCount,
                order: sampleMode === 'oldest' ? 'oldest' : null
            })

            let candidates = videos.map(v => v.title)
            if (sampleMode === 'random') {
                candidates = candidates
                    .map(t => ({ t, r: Math.random() }))
                    .sort((a, b) => a.r - b.r)
                    .map(x => x.t)
            }
            titles = candidates.slice(0, sampleCount)
        }

        // Test pattern on each title
        const results = titles.map(title => {
            const extracted = channelPatternManager.extractMetadata(title, testPattern)
            return {
                youtubeTitle: title,
                extracted: extracted || { error: 'No match' },
                matched: !!extracted
            }
        })

        const matchRate = results.length > 0
            ? (results.filter(r => r.matched).length / results.length) * 100
            : 0

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

// PUT /api/admin/channels/:id - Update channel metadata
router.put('/:id', async (req, res, next) => {
    try {
        const { id } = req.params
        const updates = req.body

        // Validate allowed fields
        const allowedFields = [
            'has_movies', 'has_series', 'has_kids_content', 'pattern_source'
        ]

        const cleanUpdates = {}
        allowedFields.forEach(field => {
            if (updates[field] !== undefined) {
                cleanUpdates[field] = updates[field]
            }
        })

        if (Object.keys(cleanUpdates).length === 0) {
            return res.status(400).json({
                success: false,
                error: 'No valid fields to update'
            })
        }

        // Update channel
        const { data: channel, error } = await supabase
            .from('channels')
            .update(cleanUpdates)
            .eq('id', id)
            .select()
            .single()

        if (error) throw error

        if (!channel) {
            return res.status(404).json({
                success: false,
                error: 'Channel not found'
            })
        }

        // Keep channel_settings in sync — only channel_settings flags reach imported movies.
        // channels.has_kids_content -> channel_settings.is_kids_content
        // channels.has_series       -> channel_settings.is_tv_series_channel
        const settingsSync = {}
        if (updates.has_kids_content !== undefined) {
            settingsSync.is_kids_content = updates.has_kids_content
        }
        if (updates.has_series !== undefined) {
            settingsSync.is_tv_series_channel = updates.has_series
        }
        if (Object.keys(settingsSync).length > 0) {
            const { error: settingsError } = await supabase
                .from('channel_settings')
                .upsert({ channel_id: id, ...settingsSync }, { onConflict: 'channel_id' })
            if (settingsError) {
                logger.error(`[Channels Admin] Failed to sync channel_settings for ${id}:`, settingsError)
            } else {
                logger.info(`[Channels Admin] Synced channel_settings flags for ${id}:`, settingsSync)
            }
        }

        logger.info(`[Channels Admin] Updated channel ${id}:`, cleanUpdates)

        res.json({
            success: true,
            data: channel,
            message: 'Channel updated successfully'
        })
    } catch (error) {
        logger.error('[Channels Admin] Update channel error:', error)
        next(error)
    }
})

// DELETE /api/admin/channels/:id - Delete a channel
// Must be defined last to avoid matching other routes
router.delete('/:id', async (req, res, next) => {
    const startTime = Date.now()
    logger.info(`\n${'='.repeat(80)}`)
    logger.info(`[Channels Admin] 🗑️  CHANNEL DELETE REQUEST`)
    logger.info(`[Channels Admin] Raw params.id: ${req.params.id}`)
    logger.info(`[Channels Admin] Full URL path: ${req.path}`)
    logger.info(`[Channels Admin] Full URL: ${req.originalUrl}`)
    logger.info(`${'='.repeat(80)}\n`)

    try {
        logger.info(`[Channels Admin] Step 1: Decode channel ID`)
        // Decode the ID to handle @ symbols and other special characters
        const id = decodeURIComponent(req.params.id)
        logger.info(`[Channels Admin] ✅ Decoded ID: ${id}`)
        logger.info(`[Channels Admin]   Original: ${req.params.id}`)
        logger.info(`[Channels Admin]   Decoded:  ${id}`)

        logger.info(`[Channels Admin] Step 2: Check if channel exists`)
        const { data: channel, error: channelError } = await supabase
            .from('channels')
            .select('id, title')
            .eq('id', id)
            .single()

        if (channelError) {
            logger.error(`[Channels Admin] ❌ Error checking channel existence:`)
            logger.error(`[Channels Admin]   Error code: ${channelError.code}`)
            logger.error(`[Channels Admin]   Error message: ${channelError.message}`)
            logger.error(`[Channels Admin]   Error details:`, JSON.stringify(channelError, null, 2))
        }

        if (!channel) {
            logger.error(`[Channels Admin] ❌ Channel not found with ID: ${id}`)
            logger.error(`[Channels Admin]   Searched in: channels table`)
            logger.error(`[Channels Admin]   WHERE id = '${id}'`)
            return res.status(404).json({
                success: false,
                error: `Channel not found with ID: ${id}`,
                details: {
                    searchedId: id,
                    originalId: req.params.id,
                    decodedId: decodeURIComponent(req.params.id)
                }
            })
        }

        logger.info(`[Channels Admin] ✅ Channel found: ${channel.title} (${channel.id})`)

        logger.info(`[Channels Admin] Step 3: Check for movies in production`)
        const { count: prodCount, error: prodError } = await supabase
            .from('movies')
            .select('*', { count: 'exact', head: true })
            .eq('channel_id', id)

        if (prodError) {
            logger.error(`[Channels Admin] ❌ Error checking production movies:`, prodError)
        }
        logger.info(`[Channels Admin]   Production movies: ${prodCount || 0}`)

        logger.info(`[Channels Admin] Step 4: Check for movies in staging`)
        const { count: stagingCount, error: stagingError } = await supabase
            .from('staged_movies')
            .select('*', { count: 'exact', head: true })
            .eq('channel_id', id)

        if (stagingError) {
            logger.error(`[Channels Admin] ❌ Error checking staging movies:`, stagingError)
        }
        logger.info(`[Channels Admin]   Staging movies: ${stagingCount || 0}`)

        const totalMovies = (prodCount || 0) + (stagingCount || 0)
        logger.info(`[Channels Admin]   Total movies: ${totalMovies}`)

        if (totalMovies > 0) {
            logger.warn(`[Channels Admin] ⚠️  Cannot delete - channel has movies`)
            const locations = []
            if (prodCount > 0) locations.push(`${prodCount} in production`)
            if (stagingCount > 0) locations.push(`${stagingCount} in staging`)

            logger.info(`[Channels Admin]   Locations: ${locations.join(' and ')}`)

            return res.status(409).json({
                success: false,
                error: `Cannot delete channel with ${locations.join(' and ')}. Delete movies first using the channel management page.`,
                details: {
                    production: prodCount || 0,
                    staging: stagingCount || 0,
                    total: totalMovies
                }
            })
        }

        logger.info(`[Channels Admin] ✅ No movies found - safe to delete`)

        logger.info(`[Channels Admin] Step 5: Delete channel pattern`)
        try {
            await channelPatternManager.deletePattern(id)
            logger.info(`[Channels Admin] ✅ Channel pattern deleted (or none existed)`)
        } catch (patternError) {
            logger.warn(`[Channels Admin] ⚠️  Error deleting pattern (may not exist):`, patternError.message)
        }

        logger.info(`[Channels Admin] Step 6: Delete channel from database`)
        logger.info(`[Channels Admin]   → DELETE FROM channels WHERE id = '${id}'`)
        const { error: deleteError } = await supabase
            .from('channels')
            .delete()
            .eq('id', id)

        if (deleteError) {
            logger.error(`[Channels Admin] ❌ Database delete error:`)
            logger.error(`[Channels Admin]   Error code: ${deleteError.code}`)
            logger.error(`[Channels Admin]   Error message: ${deleteError.message}`)
            logger.error(`[Channels Admin]   Error details:`, JSON.stringify(deleteError, null, 2))
            throw deleteError
        }

        logger.info(`[Channels Admin] ✅ Channel deleted successfully`)

        const duration = Date.now() - startTime
        logger.info(`\n${'='.repeat(80)}`)
        logger.info(`[Channels Admin] ✅ CHANNEL DELETE COMPLETED`)
        logger.info(`[Channels Admin] Duration: ${duration}ms`)
        logger.info(`[Channels Admin] Channel: ${channel.title} (${id})`)
        logger.info(`${'='.repeat(80)}\n`)

        res.json({
            success: true,
            message: 'Channel deleted successfully'
        })
    } catch (error) {
        const duration = Date.now() - startTime
        logger.error(`\n${'='.repeat(80)}`)
        logger.error(`[Channels Admin] ❌ CHANNEL DELETE FAILED`)
        logger.error(`[Channels Admin] Duration: ${duration}ms`)
        logger.error(`[Channels Admin] Error type: ${error.constructor.name}`)
        logger.error(`[Channels Admin] Error message: ${error.message}`)
        logger.error(`[Channels Admin] Error stack:`, error.stack)
        logger.error(`${'='.repeat(80)}\n`)
        next(error)
    }
})

export default router
