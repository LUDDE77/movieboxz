/**
 * reviewServer.js
 * Local Express server for manual IMDB review.
 * Serves the review HTML page and handles decisions.
 */

import express from 'express'
import { readFileSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import open from 'open'
import { applyImdbFix } from './autoFixer.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const TEMPLATE_PATH = join(__dirname, '../templates/review.html')

export async function startReviewServer({ queue, backendUrl, adminApiKey, port = 7788 }) {
    const reviewItems = queue.movies.filter(m => m.status === 'review-needed')
    if (!reviewItems.length) {
        console.log('   No items need manual review.')
        return
    }

    console.log(`\n🖥️  Starting review server for ${reviewItems.length} movies...`)

    const app = express()
    app.use(express.json())

    let server = null

    // GET /review/:movieId — serve the review page
    app.get('/review/:movieId', (req, res) => {
        const { movieId } = req.params
        const item = queue.movies.find(m => m.id === movieId && m.status === 'review-needed')
        if (!item) {
            const next = reviewItems.find(m => m.status === 'review-needed')
            if (next) return res.redirect(`/review/${next.id}`)
            return res.send('<h2>All movies reviewed! You can close this window.</h2>')
        }

        const pending = queue.movies.filter(m => m.status === 'review-needed')
        const currentIndex = pending.findIndex(m => m.id === movieId) + 1
        const progress = { current: currentIndex, total: pending.length }

        const template = readFileSync(TEMPLATE_PATH, 'utf8')
        const html = template.replace('__REVIEW_DATA__', JSON.stringify({
            movie: item,
            progress,
            backendUrl
        }))
        res.send(html)
    })

    // GET / — redirect to first pending item
    app.get('/', (req, res) => {
        const first = reviewItems.find(m => m.status === 'review-needed')
        if (first) return res.redirect(`/review/${first.id}`)
        res.send('<h2>All movies reviewed! You can close this window.</h2>')
    })

    // POST /decision — handle a review decision
    app.post('/decision', async (req, res) => {
        const { movieId, action, candidateImdbId } = req.body
        const item = queue.movies.find(m => m.id === movieId)
        if (!item) return res.status(404).json({ error: 'Movie not found' })

        try {
            if (action === 'use-original') {
                // User confirmed the stored IMDB ID is correct
                await applyImdbFix({ backendUrl, adminApiKey, movieId, imdbId: candidateImdbId })
                item.status = 'confirmed-original'
                item.decision = 'use-original'
                item.applied_imdb_id = candidateImdbId
                item.confirmedAt = new Date().toISOString()
                console.log(`   ✅ Original confirmed by user: ${item.title} → ${candidateImdbId}`)
            } else if (action === 'use-found' || action === 'use-custom') {
                // User chose the IMDB-found candidate or typed a custom ID
                await applyImdbFix({ backendUrl, adminApiKey, movieId, imdbId: candidateImdbId })
                const label = action === 'use-custom' ? 'custom' : 'found'
                item.status = `confirmed-${label}`
                item.decision = action
                item.applied_imdb_id = candidateImdbId
                item.confirmedAt = new Date().toISOString()
                console.log(`   ✅ ${label === 'custom' ? 'Custom' : 'Found'} ID confirmed by user: ${item.title} → ${candidateImdbId}`)
            } else if (action === 'skip') {
                item.status = 'skipped'
                item.decision = 'skip'
                console.log(`   ⏭️  Skipped: ${item.title}`)
            }

            // Save queue state
            item.decidedAt = new Date().toISOString()
            queue.save()

            // Find next pending
            const remaining = queue.movies.filter(m => m.status === 'review-needed')
            const nextId = remaining[0]?.id ?? null

            if (!nextId) {
                console.log('\n🎉 All reviews done! Closing review server...')
                setTimeout(() => server?.close(), 1500)
            }

            res.json({ success: true, nextId })
        } catch (err) {
            console.error(`   ❌ Decision error for ${item.title}:`, err.message)
            res.status(500).json({ error: err.message })
        }
    })

    // GET /api/progress — live progress data
    app.get('/api/progress', (req, res) => {
        const counts = {
            total: queue.movies.length,
            confirmed: queue.movies.filter(m => m.status === 'confirmed').length,
            updated: queue.movies.filter(m => m.status === 'updated').length,
            autoFixed: queue.movies.filter(m => m.status === 'auto-fixed').length,
            skipped: queue.movies.filter(m => ['skipped', 'low-confidence', 'confirmed-match'].includes(m.status)).length,
            pending: queue.movies.filter(m => m.status === 'review-needed').length
        }
        res.json(counts)
    })

    return new Promise((resolve) => {
        server = app.listen(port, async () => {
            const url = `http://localhost:${port}`
            console.log(`\n   🌐 Review server at ${url}`)
            console.log(`   Keyboard shortcuts: C=Confirm  U=Use Candidate  S=Skip  O=Open IMDB\n`)
            await open(url)
            resolve(server)
        })
    })
}
