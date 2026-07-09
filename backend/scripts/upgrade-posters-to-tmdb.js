#!/usr/bin/env node
/**
 * upgrade-posters-to-tmdb.js
 *
 * Upgrades Amazon CDN poster URLs to stable TMDB poster paths.
 * For movies that already have a tmdb_id: calls GET /3/movie/{id} directly.
 * For movies with only an imdb_id: calls GET /3/find/{imdb_id} to discover TMDB ID + poster.
 * Leaves Amazon URL untouched if TMDB has no poster for that movie.
 *
 * Usage:
 *   TMDB_API_KEY=xxx SUPABASE_SERVICE_KEY=yyy node scripts/upgrade-posters-to-tmdb.js [--dry-run]
 */

import axios from 'axios'

const SUPABASE_URL = 'https://oltlikatlvbwavfxqazn.supabase.co'
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY
const TMDB_API_KEY = process.env.TMDB_API_KEY
const DRY_RUN = process.argv.includes('--dry-run')
const CONCURRENCY = 6
const BATCH_DELAY_MS = 250

function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

function sbHeaders() {
    return {
        'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
        'apikey': SUPABASE_SERVICE_KEY,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
    }
}

async function fetchMoviesWithAmazonPosters() {
    // Fetch all movies with Amazon poster URLs in pages of 1000
    const pageSize = 1000
    let offset = 0, all = []
    while (true) {
        const url = `${SUPABASE_URL}/rest/v1/movies` +
            `?select=id,title,imdb_id,tmdb_id,poster_path` +
            `&poster_path=like.https://m.media-amazon.com%25` +
            `&order=id&limit=${pageSize}&offset=${offset}`
        const res = await axios.get(url, { headers: sbHeaders(), timeout: 30000 })
        all = all.concat(res.data)
        if (res.data.length < pageSize) break
        offset += pageSize
    }
    return all
}

async function getTmdbPosterByTmdbId(tmdbId) {
    try {
        const res = await axios.get(
            `https://api.themoviedb.org/3/movie/${tmdbId}?api_key=${TMDB_API_KEY}`,
            { timeout: 10000, validateStatus: null }
        )
        if (res.status === 200 && res.data.poster_path) {
            return { posterPath: res.data.poster_path, tmdbId }
        }
    } catch { }
    return null
}

async function getTmdbPosterByImdbId(imdbId) {
    try {
        const res = await axios.get(
            `https://api.themoviedb.org/3/find/${imdbId}?external_source=imdb_id&api_key=${TMDB_API_KEY}`,
            { timeout: 10000, validateStatus: null }
        )
        if (res.status === 200) {
            const result = res.data?.movie_results?.[0]
            if (result?.poster_path) {
                return { posterPath: result.poster_path, tmdbId: result.id }
            }
        }
    } catch { }
    return null
}

async function updateMovie(id, posterPath, tmdbId) {
    if (DRY_RUN) return
    const body = { poster_path: posterPath, updated_at: new Date().toISOString() }
    if (tmdbId) body.tmdb_id = tmdbId
    await axios.patch(
        `${SUPABASE_URL}/rest/v1/movies?id=eq.${id}`,
        body,
        { headers: sbHeaders(), timeout: 15000 }
    )
}

async function pLimit(tasks, concurrency) {
    const results = []
    let i = 0
    async function worker() {
        while (i < tasks.length) { const idx = i++; results[idx] = await tasks[idx]() }
    }
    await Promise.all(Array.from({ length: Math.min(concurrency, tasks.length) }, worker))
    return results
}

async function main() {
    if (!SUPABASE_SERVICE_KEY || !TMDB_API_KEY) {
        console.error('ERROR: SUPABASE_SERVICE_KEY and TMDB_API_KEY are required.')
        process.exit(1)
    }
    console.log(`\n=== upgrade-posters-to-tmdb ===`)
    if (DRY_RUN) console.log('DRY RUN — no DB writes.')
    console.log()

    console.log('Fetching movies with Amazon poster URLs...')
    const movies = await fetchMoviesWithAmazonPosters()
    console.log(`Found ${movies.length} movies with Amazon posters.\n`)

    const hasTmdbId  = movies.filter(m => m.tmdb_id)
    const needsFind  = movies.filter(m => !m.tmdb_id && m.imdb_id)
    const noIds      = movies.filter(m => !m.tmdb_id && !m.imdb_id)

    console.log(`  ${hasTmdbId.length} have TMDB ID → direct lookup`)
    console.log(`  ${needsFind.length} have only IMDB ID → find lookup`)
    console.log(`  ${noIds.length} have no IDs → cannot upgrade\n`)

    const stats = { upgraded: 0, noTmdbPoster: 0, noIds: noIds.length, errors: 0 }
    const toProcess = [...hasTmdbId, ...needsFind]

    for (let i = 0; i < toProcess.length; i += CONCURRENCY) {
        const batch = toProcess.slice(i, i + CONCURRENCY)

        await pLimit(batch.map(movie => async () => {
            const n = i + batch.indexOf(movie) + 1
            const label = `[${n}/${toProcess.length}] ${movie.title}`

            try {
                let result = null
                if (movie.tmdb_id) {
                    result = await getTmdbPosterByTmdbId(movie.tmdb_id)
                } else {
                    result = await getTmdbPosterByImdbId(movie.imdb_id)
                }

                if (result) {
                    await updateMovie(movie.id, result.posterPath, result.tmdbId)
                    stats.upgraded++
                    console.log(`  ✅ ${label}  →  ${result.posterPath}`)
                } else {
                    stats.noTmdbPoster++
                    console.log(`  —  ${label}  (no TMDB poster, keeping Amazon URL)`)
                }
            } catch (e) {
                stats.errors++
                console.log(`  ❌ ${label}  ERROR: ${e.message}`)
            }
        }), CONCURRENCY)

        if (i + CONCURRENCY < toProcess.length) await sleep(BATCH_DELAY_MS)
    }

    console.log(`
=== Summary ===
  Total Amazon poster movies : ${movies.length}
  Upgraded to TMDB path      : ${stats.upgraded}
  No TMDB poster available   : ${stats.noTmdbPoster}
  No IDs (cannot upgrade)    : ${stats.noIds}
  Errors                     : ${stats.errors}
  ${DRY_RUN ? '(DRY RUN — no writes made)' : ''}
`)
}

main().catch(err => { console.error('Fatal:', err); process.exit(1) })
