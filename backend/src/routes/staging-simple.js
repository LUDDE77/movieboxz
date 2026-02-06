import express from 'express'
import { pool } from '../config/database.js'
import { selectiveEnrichment } from '../services/selectiveEnrichment.js'
import { logger } from '../utils/logger.js'

const router = express.Router()

// GET /api/admin/staging/stats - Get staging statistics
router.get('/stats', async (req, res, next) => {
    try {
        // Count by approval status
        const statusResult = await pool.query(`
            SELECT
                COUNT(*) FILTER (WHERE approval_status = 'pending') as pending,
                COUNT(*) FILTER (WHERE approval_status = 'approved') as approved,
                COUNT(*) FILTER (WHERE approval_status = 'rejected') as rejected,
                COUNT(*) as total_staged
            FROM staged_movies
        `)

        // Count by enrichment status
        const enrichmentResult = await pool.query(`
            SELECT
                COUNT(*) FILTER (WHERE tmdb_id IS NOT NULL OR imdb_id IS NOT NULL) as enriched,
                COUNT(*) FILTER (WHERE tmdb_id IS NULL AND imdb_id IS NULL) as unenriched
            FROM staged_movies
        `)

        const stats = {
            total_staged: parseInt(statusResult.rows[0].total_staged),
            pending: parseInt(statusResult.rows[0].pending),
            approved: parseInt(statusResult.rows[0].approved),
            rejected: parseInt(statusResult.rows[0].rejected),
            enriched: parseInt(enrichmentResult.rows[0].enriched),
            unenriched: parseInt(enrichmentResult.rows[0].unenriched)
        }

        res.json({
            success: true,
            data: stats
        })
    } catch (error) {
        logger.error('[Staging] Stats error:', error)
        next(error)
    }
})

// GET /api/admin/staging/movies - List staged movies
router.get('/movies', async (req, res, next) => {
    try {
        const page = parseInt(req.query.page) || 1
        const limit = parseInt(req.query.limit) || 50
        const offset = (page - 1) * limit
        const status = req.query.status
        const filter = req.query.filter

        let whereClause = 'WHERE 1=1'
        const params = []

        if (status) {
            params.push(status)
            whereClause += ` AND approval_status = $${params.length}`
        }

        if (filter === 'enriched') {
            whereClause += ' AND (tmdb_id IS NOT NULL OR imdb_id IS NOT NULL)'
        } else if (filter === 'unenriched') {
            whereClause += ' AND tmdb_id IS NULL AND imdb_id IS NULL'
        }

        // Get total count
        const countResult = await pool.query(`
            SELECT COUNT(*) FROM staged_movies ${whereClause}
        `, params)
        const total = parseInt(countResult.rows[0].count)

        // Get movies
        params.push(limit, offset)
        const result = await pool.query(`
            SELECT
                sm.*,
                c.title as channel_title
            FROM staged_movies sm
            LEFT JOIN channels c ON c.id = sm.channel_id
            ${whereClause}
            ORDER BY sm.created_at DESC
            LIMIT $${params.length - 1} OFFSET $${params.length}
        `, params)

        res.json({
            success: true,
            data: {
                movies: result.rows,
                pagination: {
                    page,
                    limit,
                    total,
                    pages: Math.ceil(total / limit)
                }
            }
        })
    } catch (error) {
        logger.error('[Staging] List movies error:', error)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/preview-enrichment
router.post('/movies/:id/preview-enrichment', async (req, res, next) => {
    try {
        const { id } = req.params
        const { priority = 'full', fields = null, preferTmdb = true } = req.body

        const result = await pool.query('SELECT * FROM staged_movies WHERE id = $1', [id])
        if (result.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Movie not found' })
        }

        const movie = result.rows[0]

        const enrichmentResult = await selectiveEnrichment.enrichSelective(movie, {
            priority,
            fields,
            preferTmdb,
            previewOnly: true,
            respectManual: true,
            manualChanges: movie.manual_changes
        })

        // Save preview to database
        await pool.query(
            'UPDATE staged_movies SET enrichment_preview = $1, updated_at = NOW() WHERE id = $2',
            [JSON.stringify(enrichmentResult.preview), id]
        )

        res.json({
            success: true,
            data: enrichmentResult
        })
    } catch (error) {
        logger.error('[Staging] Preview enrichment error:', error)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/enrich
router.post('/movies/:id/enrich', async (req, res, next) => {
    try {
        const { id } = req.params
        const { priority = 'full', fields = null, preferTmdb = true, applyFromPreview = false } = req.body

        const result = await pool.query('SELECT * FROM staged_movies WHERE id = $1', [id])
        if (result.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Movie not found' })
        }

        const movie = result.rows[0]

        const enrichmentResult = await selectiveEnrichment.enrichSelective(movie, {
            priority,
            fields,
            preferTmdb,
            previewOnly: false,
            respectManual: true,
            manualChanges: movie.manual_changes
        })

        if (enrichmentResult.success) {
            const preview = enrichmentResult.preview
            const updateFields = []
            const updateValues = []
            let valueIndex = 1

            // Build dynamic update query
            Object.keys(preview).forEach(key => {
                updateFields.push(`${key} = $${valueIndex}`)
                updateValues.push(preview[key])
                valueIndex++
            })

            updateFields.push(`enrichment_source = $${valueIndex}`)
            updateValues.push(enrichmentResult.source)
            valueIndex++

            updateFields.push(`enrichment_confidence = $${valueIndex}`)
            updateValues.push(enrichmentResult.confidence)
            valueIndex++

            updateFields.push(`updated_at = NOW()`)
            updateValues.push(id)

            const updateQuery = `
                UPDATE staged_movies
                SET ${updateFields.join(', ')}
                WHERE id = $${valueIndex}
                RETURNING *
            `

            const updateResult = await pool.query(updateQuery, updateValues)

            res.json({
                success: true,
                data: updateResult.rows[0]
            })
        } else {
            res.status(400).json({
                success: false,
                error: 'Enrichment failed',
                message: enrichmentResult.message || 'Could not enrich movie'
            })
        }
    } catch (error) {
        logger.error('[Staging] Apply enrichment error:', error)
        next(error)
    }
})

// PATCH /api/admin/staging/movies/:id - Manual edit
router.patch('/movies/:id', async (req, res, next) => {
    try {
        const { id } = req.params
        const updates = req.body

        const fields = []
        const values = []
        let index = 1

        Object.keys(updates).forEach(key => {
            fields.push(`${key} = $${index}`)
            values.push(updates[key])
            index++
        })

        fields.push(`updated_at = NOW()`)
        values.push(id)

        const result = await pool.query(`
            UPDATE staged_movies
            SET ${fields.join(', ')}
            WHERE id = $${index}
            RETURNING *
        `, values)

        if (result.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Movie not found' })
        }

        res.json({
            success: true,
            data: result.rows[0]
        })
    } catch (error) {
        logger.error('[Staging] Update movie error:', error)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/approve
router.post('/movies/:id/approve', async (req, res, next) => {
    try {
        const { id } = req.params
        const { notes } = req.body

        const result = await pool.query(`
            UPDATE staged_movies
            SET
                approval_status = 'approved',
                approved_at = NOW(),
                notes = $1,
                updated_at = NOW()
            WHERE id = $2
            RETURNING *
        `, [notes || null, id])

        if (result.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Movie not found' })
        }

        res.json({
            success: true,
            data: result.rows[0]
        })
    } catch (error) {
        logger.error('[Staging] Approve movie error:', error)
        next(error)
    }
})

// POST /api/admin/staging/movies/:id/reject
router.post('/movies/:id/reject', async (req, res, next) => {
    try {
        const { id } = req.params
        const { reason } = req.body

        const result = await pool.query(`
            UPDATE staged_movies
            SET
                approval_status = 'rejected',
                rejected_reason = $1,
                updated_at = NOW()
            WHERE id = $2
            RETURNING *
        `, [reason, id])

        if (result.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Movie not found' })
        }

        res.json({
            success: true,
            data: result.rows[0]
        })
    } catch (error) {
        logger.error('[Staging] Reject movie error:', error)
        next(error)
    }
})

// POST /api/admin/staging/publish - Publish approved movies
router.post('/publish', async (req, res, next) => {
    try {
        const { ids } = req.body
        let published = 0
        let failed = 0
        const movieIds = []

        let stagedMovies
        if (ids && ids.length > 0) {
            const placeholders = ids.map((_, i) => `$${i + 1}`).join(',')
            const result = await pool.query(
                `SELECT * FROM staged_movies WHERE id IN (${placeholders}) AND approval_status = 'approved'`,
                ids
            )
            stagedMovies = result.rows
        } else {
            const result = await pool.query(
                `SELECT * FROM staged_movies WHERE approval_status = 'approved' ORDER BY created_at ASC`
            )
            stagedMovies = result.rows
        }

        for (const stagedMovie of stagedMovies) {
            try {
                // Insert into movies table
                const insertResult = await pool.query(`
                    INSERT INTO movies (
                        youtube_video_id, youtube_video_title, title, original_title,
                        description, release_date, runtime_minutes, channel_id,
                        view_count, like_count, comment_count, published_at,
                        tmdb_id, imdb_id, poster_path, backdrop_path,
                        vote_average, vote_count, popularity,
                        imdb_rating, imdb_votes, rated, director, actors,
                        language, country, is_tv_show, category,
                        enrichment_source, enrichment_confidence,
                        is_available, created_at, updated_at
                    ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                        $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
                        $21, $22, $23, $24, $25, $26, $27, $28, $29, $30,
                        true, NOW(), NOW()
                    ) RETURNING id
                `, [
                    stagedMovie.youtube_video_id, stagedMovie.youtube_video_title,
                    stagedMovie.title, stagedMovie.original_title,
                    stagedMovie.description, stagedMovie.release_date,
                    stagedMovie.runtime_minutes, stagedMovie.channel_id,
                    stagedMovie.view_count, stagedMovie.like_count,
                    stagedMovie.comment_count, stagedMovie.published_at,
                    stagedMovie.tmdb_id, stagedMovie.imdb_id,
                    stagedMovie.poster_path, stagedMovie.backdrop_path,
                    stagedMovie.vote_average, stagedMovie.vote_count,
                    stagedMovie.popularity, stagedMovie.imdb_rating,
                    stagedMovie.imdb_votes, stagedMovie.rated,
                    stagedMovie.director, stagedMovie.actors,
                    stagedMovie.language, stagedMovie.country,
                    stagedMovie.is_tv_show, stagedMovie.category,
                    stagedMovie.enrichment_source, stagedMovie.enrichment_confidence
                ])

                const movieId = insertResult.rows[0].id
                movieIds.push(movieId)

                // Update staged movie with published_movie_id
                await pool.query(
                    'UPDATE staged_movies SET published_movie_id = $1, updated_at = NOW() WHERE id = $2',
                    [movieId, stagedMovie.id]
                )

                published++
            } catch (error) {
                logger.error(`[Staging] Failed to publish movie ${stagedMovie.id}:`, error)
                failed++
            }
        }

        res.json({
            success: true,
            data: {
                published,
                failed,
                movieIds
            }
        })
    } catch (error) {
        logger.error('[Staging] Publish error:', error)
        next(error)
    }
})

export default router
