import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'
import { enhancedEnrichment } from './enhancedEnrichment.js'

/**
 * ManualEnrichmentQueue Service
 *
 * Manages the manual enrichment queue for movies that failed automatic matching.
 * Allows administrators to manually provide IMDB IDs for proper enrichment.
 */
class ManualEnrichmentQueue {
    /**
     * Add a movie to the manual enrichment queue
     *
     * @param {Object} movieData - Movie data from YouTube
     * @param {Object} extractedMetadata - Metadata extracted from title using patterns
     * @returns {Promise<Object>} Queue entry
     */
    async addToQueue(movieData, extractedMetadata = null) {
        try {
            // Check if already in queue
            const { data: existing } = await supabase
                .from('manual_enrichment_queue')
                .select('id')
                .eq('youtube_video_id', movieData.youtube_video_id)
                .single()

            if (existing) {
                logger.debug(`Movie already in manual queue: ${movieData.youtube_video_id}`)
                return existing
            }

            // Add to queue
            const { data, error } = await supabase
                .from('manual_enrichment_queue')
                .insert({
                    youtube_video_id: movieData.youtube_video_id,
                    youtube_video_title: movieData.youtube_video_title || movieData.title,
                    channel_id: movieData.channel_id,
                    channel_title: movieData.channel_title || movieData.channelTitle,
                    extracted_title: extractedMetadata?.title,
                    extracted_actors: extractedMetadata?.actorsArray,
                    extracted_genre: extractedMetadata?.genre,
                    extracted_year: extractedMetadata?.year,
                    description: movieData.description,
                    published_at: movieData.published_at || movieData.publishedAt,
                    duration_minutes: movieData.duration_minutes || movieData.durationMinutes,
                    thumbnail_url: movieData.thumbnail_url || movieData.channelThumbnail,
                    enrichment_status: 'pending'
                })
                .select()
                .single()

            if (error) {
                throw error
            }

            logger.info(`Added to manual enrichment queue: ${extractedMetadata?.title || movieData.title}`, {
                youtube_video_id: movieData.youtube_video_id,
                queue_id: data.id
            })

            return data

        } catch (error) {
            logger.error('Error adding to manual enrichment queue:', error)
            throw error
        }
    }

    /**
     * Get pending items from the queue
     *
     * @param {Object} options - Query options
     * @param {string} options.channelId - Filter by channel ID
     * @param {string} options.status - Filter by status (default: 'pending')
     * @param {number} options.limit - Max results (default: 50)
     * @param {number} options.offset - Pagination offset (default: 0)
     * @returns {Promise<Array>} Queue entries
     */
    async getQueue(options = {}) {
        try {
            const {
                channelId = null,
                status = 'pending',
                limit = 50,
                offset = 0
            } = options

            let query = supabase
                .from('manual_enrichment_queue')
                .select('*', { count: 'exact' })
                .order('created_at', { ascending: false })
                .range(offset, offset + limit - 1)

            if (status) {
                query = query.eq('enrichment_status', status)
            }

            if (channelId) {
                query = query.eq('channel_id', channelId)
            }

            const { data, error, count } = await query

            if (error) {
                throw error
            }

            return {
                items: data || [],
                total: count,
                limit,
                offset
            }

        } catch (error) {
            logger.error('Error getting manual enrichment queue:', error)
            throw error
        }
    }

    /**
     * Get a single queue entry by ID
     *
     * @param {string} queueId - Queue entry ID
     * @returns {Promise<Object>} Queue entry
     */
    async getQueueItem(queueId) {
        try {
            const { data, error } = await supabase
                .from('manual_enrichment_queue')
                .select('*')
                .eq('id', queueId)
                .single()

            if (error) {
                throw error
            }

            return data

        } catch (error) {
            logger.error('Error getting queue item:', error)
            throw error
        }
    }

    /**
     * Process a manual match - update queue entry and enrich movie
     *
     * @param {string} queueId - Queue entry ID
     * @param {string} imdbId - Manual IMDB ID (e.g., "tt1090903")
     * @param {string} notes - Optional notes
     * @returns {Promise<Object>} Enriched movie data
     */
    async processManualMatch(queueId, imdbId, notes = null) {
        try {
            // 1. Get queue entry
            const queueEntry = await this.getQueueItem(queueId)

            if (!queueEntry) {
                throw new Error(`Queue entry not found: ${queueId}`)
            }

            // 2. Mark as in_progress
            await this.updateStatus(queueId, 'in_progress')

            // 3. Enrich using IMDB ID
            logger.info(`Processing manual match: ${queueEntry.extracted_title}`, {
                imdb_id: imdbId,
                queue_id: queueId
            })

            const enrichmentData = await enhancedEnrichment.enrichByIMDBId(imdbId)

            if (!enrichmentData) {
                throw new Error(`Failed to enrich movie with IMDB ID: ${imdbId}`)
            }

            // 4. Update or create movie record
            const movieData = {
                youtube_video_id: queueEntry.youtube_video_id,
                title: enrichmentData.title || queueEntry.extracted_title,
                youtube_video_title: queueEntry.youtube_video_title,
                channel_id: queueEntry.channel_id,
                channel_title: queueEntry.channel_title,
                description: queueEntry.description,
                published_at: queueEntry.published_at,
                duration_minutes: queueEntry.duration_minutes,
                thumbnail_url: queueEntry.thumbnail_url,

                // Enrichment data
                imdb_id: enrichmentData.imdb_id,
                tmdb_id: enrichmentData.tmdb_id,
                poster_url: enrichmentData.poster_url,
                backdrop_url: enrichmentData.backdrop_url,
                overview: enrichmentData.overview,
                release_year: enrichmentData.release_year,
                runtime: enrichmentData.runtime,
                rating: enrichmentData.rating,
                genres: enrichmentData.genres,
                cast: enrichmentData.cast,
                director: enrichmentData.director,
                enrichment_confidence: 100, // Manual match = 100% confidence
                enrichment_source: 'manual',
                is_enriched: true
            }

            // 4. Save movie to database using upsert
            const { data: savedMovie, error: movieError } = await supabase
                .from('movies')
                .upsert(movieData, {
                    onConflict: 'youtube_video_id',
                    ignoreDuplicates: false
                })
                .select()
                .single()

            if (movieError) {
                throw new Error(`Failed to save movie: ${movieError.message}`)
            }

            // 5. Update queue entry
            const { error: updateError } = await supabase
                .from('manual_enrichment_queue')
                .update({
                    manual_imdb_id: imdbId,
                    manual_tmdb_id: enrichmentData.tmdb_id,
                    manual_notes: notes,
                    enrichment_status: 'matched',
                    processed_at: new Date().toISOString()
                })
                .eq('id', queueId)

            if (updateError) {
                throw updateError
            }

            logger.info(`Manual match completed successfully: ${enrichmentData.title}`, {
                imdb_id: imdbId,
                tmdb_id: enrichmentData.tmdb_id,
                movie_id: savedMovie.id
            })

            return {
                movie: savedMovie,
                enrichment: enrichmentData,
                queueEntry: queueEntry
            }

        } catch (error) {
            // Mark as failed on error
            await this.updateStatus(queueId, 'pending', error.message)
            logger.error('Error processing manual match:', error)
            throw error
        }
    }

    /**
     * Update the status of a queue entry
     *
     * @param {string} queueId - Queue entry ID
     * @param {string} status - New status
     * @param {string} notes - Optional notes
     * @returns {Promise<void>}
     */
    async updateStatus(queueId, status, notes = null) {
        try {
            const updateData = {
                enrichment_status: status,
                updated_at: new Date().toISOString()
            }

            if (notes) {
                updateData.manual_notes = notes
            }

            if (status === 'matched' || status === 'skipped') {
                updateData.processed_at = new Date().toISOString()
            }

            const { error } = await supabase
                .from('manual_enrichment_queue')
                .update(updateData)
                .eq('id', queueId)

            if (error) {
                throw error
            }

            logger.debug(`Queue entry status updated: ${status}`, { queue_id: queueId })

        } catch (error) {
            logger.error('Error updating queue status:', error)
            throw error
        }
    }

    /**
     * Skip a queue entry (won't be enriched)
     *
     * @param {string} queueId - Queue entry ID
     * @param {string} reason - Reason for skipping
     * @returns {Promise<void>}
     */
    async skipEntry(queueId, reason = null) {
        try {
            await this.updateStatus(queueId, 'skipped', reason)
            logger.info(`Queue entry skipped: ${queueId}`, { reason })

        } catch (error) {
            logger.error('Error skipping queue entry:', error)
            throw error
        }
    }

    /**
     * Delete a queue entry
     *
     * @param {string} queueId - Queue entry ID
     * @returns {Promise<void>}
     */
    async deleteEntry(queueId) {
        try {
            const { error } = await supabase
                .from('manual_enrichment_queue')
                .delete()
                .eq('id', queueId)

            if (error) {
                throw error
            }

            logger.info(`Queue entry deleted: ${queueId}`)

        } catch (error) {
            logger.error('Error deleting queue entry:', error)
            throw error
        }
    }

    /**
     * Get queue statistics
     *
     * @param {string} channelId - Optional channel filter
     * @returns {Promise<Object>} Statistics
     */
    async getStats(channelId = null) {
        try {
            let query = supabase
                .from('manual_enrichment_queue')
                .select('enrichment_status')

            if (channelId) {
                query = query.eq('channel_id', channelId)
            }

            const { data, error } = await query

            if (error) {
                throw error
            }

            const stats = {
                total: data.length,
                pending: 0,
                in_progress: 0,
                matched: 0,
                skipped: 0
            }

            data.forEach(item => {
                stats[item.enrichment_status] = (stats[item.enrichment_status] || 0) + 1
            })

            return stats

        } catch (error) {
            logger.error('Error getting queue stats:', error)
            throw error
        }
    }
}

// Export singleton instance
export default new ManualEnrichmentQueue()
