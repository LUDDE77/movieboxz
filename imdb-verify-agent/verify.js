#!/usr/bin/env node
/**
 * verify.js — MovieBoxZ IMDB Verification Agent
 *
 * Usage:
 *   node verify.js [--limit N] [--auto-only] [--review-only] [--skip-verified] [--resume]
 *
 * Env vars (in .env):
 *   BACKEND_URL    — Railway URL or http://localhost:3000
 *   ADMIN_API_KEY  — Admin API key
 *   REVIEW_PORT    — Local review server port (default 7788)
 */

import 'dotenv/config'
import { readFileSync, writeFileSync, existsSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import { fetchAllMovies } from './lib/fetcher.js'
import { initBrowser, closeBrowser, searchIMDB } from './lib/imdbSearcher.js'
import { scoreCandidate, pickBestCandidate } from './lib/scorer.js'
import { applyImdbFix } from './lib/autoFixer.js'
import { startReviewServer } from './lib/reviewServer.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const QUEUE_PATH = join(__dirname, 'queue.json')

// ── Config ────────────────────────────────────────────────────────────────────

const config = {
    backendUrl:  (process.env.BACKEND_URL  || '').replace(/\/$/, ''),
    adminApiKey: process.env.ADMIN_API_KEY || '',
    reviewPort:  parseInt(process.env.REVIEW_PORT || '7788')
}

if (!config.backendUrl || !config.adminApiKey) {
    console.error('❌ BACKEND_URL and ADMIN_API_KEY must be set in .env')
    process.exit(1)
}

// ── CLI args ──────────────────────────────────────────────────────────────────

const args = process.argv.slice(2)
const opts = {
    limit:         args.includes('--limit') ? parseInt(args[args.indexOf('--limit') + 1]) : null,
    autoOnly:      args.includes('--auto-only'),
    reviewOnly:    args.includes('--review-only'),
    skipVerified:  args.includes('--skip-verified'),
    resume:        args.includes('--resume')
}

// ── Queue helpers ─────────────────────────────────────────────────────────────

function loadQueue() {
    if (existsSync(QUEUE_PATH)) {
        return JSON.parse(readFileSync(QUEUE_PATH, 'utf8'))
    }
    return null
}

function createQueue(movies) {
    return {
        runStarted: new Date().toISOString(),
        total: movies.length,
        movies: movies.map(m => ({
            id: m.id,
            title: m.title,
            year: m.release_date ? m.release_date.slice(0, 4) : null,
            director: m.director || null,
            actors: m.actors || null,
            release_date: m.release_date || null,
            stored_imdb_id: m.imdb_id || null,
            poster_url: m.poster_path
                ? (m.poster_path.startsWith('http') ? m.poster_path : `https://image.tmdb.org/t/p/w300${m.poster_path}`)
                : null,
            youtube_video_id: m.youtube_video_id || null,
            youtube_video_title: m.youtube_video_title || null,
            enrichment_source: m.enrichment_source || null,
            status: 'pending',
            candidates: [],
            confidence: null,
            processedAt: null
        })),
        save() { saveQueue(this) }
    }
}

function saveQueue(queue) {
    const { save, ...data } = queue
    writeFileSync(QUEUE_PATH, JSON.stringify(data, null, 2))
}

// ── Processing ────────────────────────────────────────────────────────────────

async function processMovie(item, queue) {
    try {
        // Search IMDB
        const rawCandidates = await searchIMDB(item)

        // Score each candidate
        const scoredCandidates = rawCandidates.map(c => ({
            ...c,
            score: scoreCandidate(item, c)
        }))
        scoredCandidates.sort((a, b) => b.score.confidence - a.score.confidence)
        item.candidates = scoredCandidates

        const best = scoredCandidates[0]

        if (!best) {
            item.status = 'low-confidence'
            item.confidence = 0
            return 'low-confidence'
        }

        const { verdict, confidence } = best.score
        item.confidence = confidence
        item.candidate_imdb_id = best.imdbId

        if (verdict === 'confirmed-match') {
            item.status = 'confirmed-match'
            return 'confirmed-match'
        }

        if (verdict === 'auto-fix' && !opts.reviewOnly) {
            try {
                await applyImdbFix({
                    backendUrl: config.backendUrl,
                    adminApiKey: config.adminApiKey,
                    movieId: item.id,
                    imdbId: best.imdbId
                })
                item.status = 'auto-fixed'
                item.applied_imdb_id = best.imdbId
                return 'auto-fixed'
            } catch (err) {
                item.status = 'review-needed'
                item.notes = `Auto-fix failed: ${err.message}`
                return 'review-needed'
            }
        }

        if (verdict === 'review' || opts.reviewOnly) {
            item.status = 'review-needed'
            return 'review-needed'
        }

        item.status = 'low-confidence'
        return 'low-confidence'

    } catch (err) {
        item.status = 'error'
        item.notes = err.message
        return 'error'
    } finally {
        item.processedAt = new Date().toISOString()
        queue.save()
    }
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
    console.log('\n🎬 MovieBoxZ IMDB Verification Agent')
    console.log('────────────────────────────────────')
    console.log(`   Backend: ${config.backendUrl}`)
    if (opts.limit)        console.log(`   Limit:   ${opts.limit} movies`)
    if (opts.autoOnly)     console.log(`   Mode:    auto-fix only`)
    if (opts.reviewOnly)   console.log(`   Mode:    review only (no auto-fix)`)
    if (opts.skipVerified) console.log(`   Skipping manually verified movies`)
    if (opts.resume)       console.log(`   Resuming from previous run`)
    console.log()

    // Load or create queue
    let queue
    if (opts.resume && existsSync(QUEUE_PATH)) {
        queue = loadQueue()
        queue.save = () => saveQueue(queue)
        const pending = queue.movies.filter(m => m.status === 'pending').length
        console.log(`♻️  Resuming — ${pending} movies still pending\n`)
    } else {
        const movies = await fetchAllMovies({
            backendUrl:   config.backendUrl,
            adminApiKey:  config.adminApiKey,
            limit:        opts.limit,
            skipVerified: opts.skipVerified
        })
        queue = createQueue(movies)
        queue.save = () => saveQueue(queue)
        saveQueue(queue)
        console.log()
    }

    const pending = queue.movies.filter(m => m.status === 'pending')
    if (!pending.length) {
        console.log('✅ No pending movies to process.')
    } else if (!opts.reviewOnly) {
        // ── Playwright processing loop ──────────────────────────────────────
        await initBrowser()

        const counts = { 'confirmed-match': 0, 'auto-fixed': 0, 'review-needed': 0, 'low-confidence': 0, 'error': 0 }

        for (let i = 0; i < pending.length; i++) {
            const item = pending[i]
            const num = `[${i + 1}/${pending.length}]`
            process.stdout.write(`${num} ${item.title} (${item.year || '?'})... `)

            const result = await processMovie(item, queue)
            counts[result] = (counts[result] || 0) + 1

            const icons = {
                'confirmed-match': `✓ confirmed match (${item.confidence}%)`,
                'auto-fixed':      `🔄 auto-fixed → ${item.candidate_imdb_id} (${item.confidence}%)`,
                'review-needed':   `👁  queued for review (${item.confidence}%)`,
                'low-confidence':  `⚡ low confidence (${item.confidence}%) — skipped`,
                'error':           `❌ error: ${item.notes}`
            }
            console.log(icons[result] || result)

            // Rate limit between searches to avoid IMDB blocks
            if (i < pending.length - 1) await new Promise(r => setTimeout(r, 1500))
        }

        await closeBrowser()

        // Summary
        console.log('\n── Summary ──────────────────────────────────────')
        console.log(`   Confirmed matches:  ${counts['confirmed-match']}`)
        console.log(`   Auto-fixed:         ${counts['auto-fixed']}`)
        console.log(`   Needs review:       ${counts['review-needed']}`)
        console.log(`   Low confidence:     ${counts['low-confidence']}`)
        if (counts['error']) console.log(`   Errors:             ${counts['error']}`)
        console.log()
    }

    // ── Review server ───────────────────────────────────────────────────────
    const reviewItems = queue.movies.filter(m => m.status === 'review-needed')
    if (reviewItems.length && !opts.autoOnly) {
        console.log(`📋 ${reviewItems.length} movie(s) need manual review`)
        await startReviewServer({
            queue,
            backendUrl:  config.backendUrl,
            adminApiKey: config.adminApiKey,
            port:        config.reviewPort
        })
    } else if (!reviewItems.length) {
        printFinalSummary(queue)
        process.exit(0)
    }
}

function printFinalSummary(queue) {
    const s = queue.movies.reduce((acc, m) => {
        acc[m.status] = (acc[m.status] || 0) + 1
        return acc
    }, {})
    console.log('\n── Final Results ──────────────────────────────────')
    Object.entries(s).forEach(([k, v]) => console.log(`   ${k}: ${v}`))
    console.log(`   Queue saved to: queue.json`)
    console.log()
}

main().catch(err => {
    console.error('\n❌ Fatal error:', err)
    process.exit(1)
})
