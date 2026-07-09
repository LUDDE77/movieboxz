#!/usr/bin/env node
/**
 * upgrade-backdrops-to-tmdb.js
 *
 * Fills in missing or non-TMDB backdrop_path values from TMDB.
 * Targets:
 *   - Movies with backdrop_path IS NULL
 *   - Movies with backdrop_path starting with http (full URL, could expire)
 *
 * For each, tries TMDB /movie/{tmdb_id} or /find/{imdb_id}.
 * Leaves null if TMDB has no backdrop (app falls back to YouTube thumbnail).
 *
 * Usage:
 *   TMDB_API_KEY=xxx SUPABASE_SERVICE_KEY=yyy node scripts/upgrade-backdrops-to-tmdb.js [--dry-run]
 */

import axios from 'axios'

const SUPABASE_URL = 'https://oltlikatlvbwavfxqazn.supabase.co'
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY
const TMDB_API_KEY = process.env.TMDB_API_KEY
const DRY_RUN = process.argv.includes('--dry-run')
const CONCURRENCY = 8
const BATCH_DELAY_MS = 200

function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

function sbHeaders() {
    return {
        'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
        'apikey': SUPABASE_SERVICE_KEY,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
    }
}

async function fetchMoviesNeedingBackdrop() {
    const pageSize = 1000
    let offset = 0, all = []
    while (true) {
        // Fetch movies where backdrop_path is null OR a full URL (not a TMDB path)
        // We do two queries and merge
        const [nullRes, urlRes] = await Promise.all([
            axios.get(
                `${SUPABASE_URL}/rest/v1/movies` +
                `?select=id,title,imdb_id,tmdb_id,backdrop_path` +
                `&backdrop_path=is.null` +
                `&order=id&limit=${pageSize}&offset=${offset}`,
                { headers: sbHeaders(), timeout: 30000 }
            ),
            axios.get(
                `${SUPABASE_URL}/rest/v1/movies` +
                `?select=id,title,imdb_id,tmdb_id,backdrop_path` +
                `&backdrop_path=like.http%25` +
                `&order=id&limit=${pageSize}&offset=${offset}`,
                { headers: sbHeaders(), timeout: 30000 }
            ),
        ])
        const batch = [...nullRes.data, ...urlRes.data]
        all = all.concat(batch)
        if (nullRes.data.length < pageSize && urlRes.data.length < pageSize) break
        offset += pageSize
    }
    // Deduplicate by id
    return [...new Map(all.map(m => [m.id, m])).values()]
}

async function getTmdbBackdropByTmdbId(tmdbId) {
    try {
        const res = await axios.get(
            `https://api.themoviedb.org/3/movie/${tmdbId}?api_key=${TMDB_API_KEY}`,
            { timeout: 10000, validateStatus: null }
        )
        if (res.status === 200 && res.data.backdrop_path) {
            return { backdropPath: res.data.backdrop_path, tmdbId }
        }
    } catch { }
    return null
}

async function getTmdbBackdropByImdbId(imdbId) {
    try {
        const res = await axios.get(
            `https://api.themoviedb.org/3/find/${imdbId}?external_source=imdb_id&api_key=${TMDB_API_KEY}`,
            { timeout: 10000, validateStatus: null }
        )
        if (res.status === 200) {
            const result = res.data?.movie_results?.[0]
            if (result?.backdrop_path) {
                return { backdropPath: result.backdrop_path, tmdbId: result.id }
            }
        }
    } catch { }
    return null
}

async function updateMovie(id, backdropPath, tmdbId) {
    if (DRY_RUN) return
    const body = { backdrop_path: backdropPath, updated_at: new Date().toISOString() }
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
    console.log(`\n=== upgrade-backdrops-to-tmdb ===`)
    if (DRY_RUN) console.log('DRY RUN — no DB writes.')
    console.log()

    console.log('Fetching movies with missing or non-TMDB backdrops...')
    const movies = await fetchMoviesNeedingBackdrop()
    console.log(`Found ${movies.length} movies to process.\n`)

    const hasTmdbId = movies.filter(m => m.tmdb_id)
    const needsFind = movies.filter(m => !m.tmdb_id && m.imdb_id)
    const noIds     = movies.filter(m => !m.tmdb_id && !m.imdb_id)

    console.log(`  ${hasTmdbId.length} have TMDB ID → direct lookup`)
    console.log(`  ${needsFind.length} have only IMDB ID → find lookup`)
    console.log(`  ${noIds.length} have no IDs → cannot look up\n`)

    const stats = { fixed: 0, noBackdrop: 0, noIds: noIds.length, errors: 0 }
    const toProcess = [...hasTmdbId, ...needsFind]

    for (let i = 0; i < toProcess.length; i += CONCURRENCY) {
        const batch = toProcess.slice(i, i + CONCURRENCY)

        await pLimit(batch.map(movie => async () => {
            const n = i + batch.indexOf(movie) + 1
            const label = `[${n}/${toProcess.length}] ${movie.title}`

            try {
                let result = null
                if (movie.tmdb_id) {
                    result = await getTmdbBackdropByTmdbId(movie.tmdb_id)
                } else {
                    result = await getTmdbBackdropByImdbId(movie.imdb_id)
                }

                if (result) {
                    await updateMovie(movie.id, result.backdropPath, result.tmdbId)
                    stats.fixed++
                    console.log(`  ✅ ${label}  →  ${result.backdropPath}`)
                } else {
                    stats.noBackdrop++
                    console.log(`  —  ${label}  (no TMDB backdrop)`)
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
  Total processed            : ${movies.length}
  Fixed with TMDB backdrop   : ${stats.fixed}
  No TMDB backdrop available : ${stats.noBackdrop}
  No IDs (cannot look up)    : ${stats.noIds}
  Errors                     : ${stats.errors}
  ${DRY_RUN ? '(DRY RUN — no writes made)' : ''}
`)
}

main().catch(err => { console.error('Fatal:', err); process.exit(1) })
