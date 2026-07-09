#!/usr/bin/env node
/**
 * enrich-tv-series-from-tmdb.js
 *
 * Fetches TMDB data for tv_series records that have an imdb_id but are missing
 * poster_path, backdrop_path, or year_start. Uses /find/{imdb_id} to discover
 * the TMDB TV show ID, then fetches full details.
 *
 * Usage:
 *   TMDB_API_KEY=xxx SUPABASE_SERVICE_KEY=yyy node scripts/enrich-tv-series-from-tmdb.js [--dry-run]
 */

import axios from 'axios'

const SUPABASE_URL = 'https://oltlikatlvbwavfxqazn.supabase.co'
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY
const TMDB_API_KEY = process.env.TMDB_API_KEY
const DRY_RUN = process.argv.includes('--dry-run')

function sbHeaders() {
    return {
        'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
        'apikey': SUPABASE_SERVICE_KEY,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
    }
}

async function fetchSeriesNeedingEnrichment() {
    const res = await axios.get(
        `${SUPABASE_URL}/rest/v1/tv_series` +
        `?select=id,title,imdb_id,tmdb_id,poster_path,backdrop_path,year_start` +
        `&imdb_id=not.is.null` +
        `&order=title`,
        { headers: sbHeaders(), timeout: 30000 }
    )
    return res.data
}

async function findTmdbShow(imdbId) {
    try {
        const res = await axios.get(
            `https://api.themoviedb.org/3/find/${imdbId}?external_source=imdb_id&api_key=${TMDB_API_KEY}`,
            { timeout: 10000, validateStatus: null }
        )
        if (res.status === 200) {
            const result = res.data?.tv_results?.[0]
            if (result) return result
        }
    } catch { }
    return null
}

async function getTmdbShowDetails(tmdbId) {
    try {
        const res = await axios.get(
            `https://api.themoviedb.org/3/tv/${tmdbId}?api_key=${TMDB_API_KEY}`,
            { timeout: 10000, validateStatus: null }
        )
        if (res.status === 200) return res.data
    } catch { }
    return null
}

async function updateSeries(id, fields) {
    if (DRY_RUN) return
    await axios.patch(
        `${SUPABASE_URL}/rest/v1/tv_series?id=eq.${id}`,
        { ...fields, updated_at: new Date().toISOString() },
        { headers: sbHeaders(), timeout: 15000 }
    )
}

async function main() {
    if (!SUPABASE_SERVICE_KEY || !TMDB_API_KEY) {
        console.error('ERROR: SUPABASE_SERVICE_KEY and TMDB_API_KEY are required.')
        process.exit(1)
    }
    console.log(`\n=== enrich-tv-series-from-tmdb ===`)
    if (DRY_RUN) console.log('DRY RUN — no DB writes.')
    console.log()

    const series = await fetchSeriesNeedingEnrichment()
    console.log(`Found ${series.length} TV series with IMDB IDs to process.\n`)

    let updated = 0, noResults = 0, errors = 0

    for (const show of series) {
        const label = `${show.title} (${show.imdb_id})`
        try {
            // Use existing tmdb_id or discover via /find
            let tmdbId = show.tmdb_id
            let findResult = null

            if (!tmdbId) {
                findResult = await findTmdbShow(show.imdb_id)
                if (!findResult) {
                    console.log(`  —  ${label}  (no TMDB TV result)`)
                    noResults++
                    continue
                }
                tmdbId = findResult.id
            }

            const details = await getTmdbShowDetails(tmdbId)
            if (!details) {
                console.log(`  —  ${label}  (TMDB details not found for id=${tmdbId})`)
                noResults++
                continue
            }

            const yearStart = details.first_air_date ? parseInt(details.first_air_date.split('-')[0]) : null
            const yearEnd = details.last_air_date ? parseInt(details.last_air_date.split('-')[0]) : null

            const fields = {
                tmdb_id: tmdbId,
                poster_path: details.poster_path || show.poster_path || null,
                backdrop_path: details.backdrop_path || show.backdrop_path || null,
                year_start: yearStart,
                year_end: details.status === 'Ended' ? yearEnd : null,
                number_of_seasons: details.number_of_seasons || 0,
                number_of_episodes: details.number_of_episodes || 0,
                status: details.status || null,
                vote_average: details.vote_average ? String(details.vote_average) : null,
            }

            await updateSeries(show.id, fields)
            updated++
            console.log(`  ✅ ${label}`)
            console.log(`     TMDB ID: ${tmdbId}`)
            console.log(`     Poster:  ${fields.poster_path || '—'}`)
            console.log(`     Years:   ${yearStart}–${yearEnd || ''}`)
            console.log(`     Seasons: ${fields.number_of_seasons}, Episodes: ${fields.number_of_episodes}`)
        } catch (e) {
            errors++
            console.log(`  ❌ ${label}  ERROR: ${e.message}`)
        }
    }

    console.log(`
=== Summary ===
  Processed : ${series.length}
  Updated   : ${updated}
  No result : ${noResults}
  Errors    : ${errors}
  ${DRY_RUN ? '(DRY RUN — no writes made)' : ''}
`)
}

main().catch(err => { console.error('Fatal:', err); process.exit(1) })
