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
import { applyImdbFix, approveMovie } from './autoFixer.js'
import { scrapeImdbWithPlaywright } from './imdbSearcher.js'
import { scoreCandidate } from './scorer.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const TEMPLATE_PATH = join(__dirname, '../templates/review.html')

export async function startReviewServer({ queue, backendUrl, adminApiKey, port = 7788, mode = 'production' }) {
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
            backendUrl,
            mode
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
            const approve = action.includes('+approve')
            const baseAction = action.replace('+approve', '')

            if (baseAction === 'use-original') {
                await applyImdbFix({ backendUrl, adminApiKey, movieId, imdbId: candidateImdbId, mode })
                item.status = approve ? 'approved' : 'confirmed-original'
                item.decision = action
                item.applied_imdb_id = candidateImdbId
                item.confirmedAt = new Date().toISOString()
                console.log(`   ✅ Original confirmed: ${item.title} → ${candidateImdbId}${approve ? ' + approved' : ''}`)
            } else if (baseAction === 'use-found' || baseAction === 'use-custom') {
                await applyImdbFix({ backendUrl, adminApiKey, movieId, imdbId: candidateImdbId, mode })
                const label = baseAction === 'use-custom' ? 'custom' : 'found'
                item.status = approve ? 'approved' : `confirmed-${label}`
                item.decision = action
                item.applied_imdb_id = candidateImdbId
                item.confirmedAt = new Date().toISOString()
                console.log(`   ✅ ${label === 'custom' ? 'Custom' : 'Found'} ID confirmed: ${item.title} → ${candidateImdbId}${approve ? ' + approved' : ''}`)
            } else if (baseAction === 'skip') {
                item.status = 'skipped'
                item.decision = 'skip'
                console.log(`   ⏭️  Skipped: ${item.title}`)
            }

            // Approve in staging if requested
            if (approve && mode === 'staging' && baseAction !== 'skip') {
                await approveMovie({ backendUrl, adminApiKey, movieId })
                console.log(`   ✅ Approved for publishing: ${item.title}`)
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

    // GET /api/lookup?imdbId=tt1234567 — scrape IMDB and return candidate data
    app.get('/api/lookup', async (req, res) => {
        const { imdbId, movieId } = req.query
        const m = String(imdbId || '').match(/tt\d+/)
        if (!m) return res.status(400).json({ error: 'Invalid IMDB ID' })

        try {
            const data = await scrapeImdbWithPlaywright(m[0])
            const candidate = {
                imdbId: m[0],
                title: data.title,
                year: data.year,
                directors: data.directors,
                actors: data.actors,
                type: data.type || 'Movie',
                posterUrl: data.posterUrl,
                description: data.description || '',
                genres: data.genres || [],
                imdbRating: data.imdbRating
            }

            // Score if we have the movie context
            if (movieId) {
                const item = queue.movies.find(q => q.id === movieId)
                if (item) candidate.score = scoreCandidate(item, candidate)
            }

            res.json({ success: true, candidate })
        } catch (err) {
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
