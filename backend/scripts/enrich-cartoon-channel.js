#!/usr/bin/env node
/**
 * enrich-cartoon-channel.js
 *
 * Enriches kids cartoon channel episodes in staging:
 *   1. Identifies which TV series each video belongs to
 *   2. Fuzzy-matches YouTube title to IMDB episode guide
 *   3. Sets season_number, episode_number, episode_name, tv_series_id, series_type
 *   4. Calls enrich-manual-imdb with the episode IMDB ID (falls back to series ID)
 *
 * Usage:
 *   node scripts/enrich-cartoon-channel.js --channel "Masters of the Universe: He-Man & She-Ra"
 *   node scripts/enrich-cartoon-channel.js --channel "Masters of the Universe: He-Man & She-Ra" --dry-run
 */

import axios from 'axios'
import { readFileSync } from 'fs'
import { createInterface } from 'readline'

const BACKEND_URL = 'https://movieboxz-backend-production.up.railway.app'
const ADMIN_KEY = process.env.ADMIN_API_KEY
const headers = { 'x-admin-api-key': ADMIN_KEY, 'Content-Type': 'application/json' }

const args = process.argv.slice(2)
const DRY_RUN = args.includes('--dry-run')
const CHANNEL_ARG = args.find((_, i) => args[i - 1] === '--channel') || 'Masters of the Universe: He-Man & She-Ra'

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

// ---------------------------------------------------------------------------
// Levenshtein distance (same approach as imdb-verify-agent scorer)
// ---------------------------------------------------------------------------
function levenshtein(a, b) {
    const m = a.length, n = b.length
    const dp = Array.from({ length: m + 1 }, (_, i) => Array.from({ length: n + 1 }, (_, j) => i === 0 ? j : j === 0 ? i : 0))
    for (let i = 1; i <= m; i++)
        for (let j = 1; j <= n; j++)
            dp[i][j] = a[i - 1] === b[j - 1] ? dp[i - 1][j - 1] : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1])
    return dp[m][n]
}

function titleSimilarity(a, b) {
    const normalize = s => s.toLowerCase().replace(/[^a-z0-9 ]/g, '').replace(/\s+/g, ' ').trim()
    const na = normalize(a), nb = normalize(b)
    if (!na || !nb) return 0
    const dist = levenshtein(na, nb)
    return 1 - dist / Math.max(na.length, nb.length)
}

// ---------------------------------------------------------------------------
// Series definitions — add more series here as needed
// ---------------------------------------------------------------------------
const SERIES_DEFINITIONS = [
    {
        key: 'heman_original',
        name: 'He-Man and the Masters of the Universe',
        imdb_id: 'tt0126158',
        tv_series_uuid: '6c783b97-5cd1-4e12-a5b2-742b54fb2784',
        series_type: 'tv_series',
        episodeFile: '/tmp/episodes-tt0126158-clean.json',
        // Title patterns that identify this series
        patterns: [/he.?man/i, /masters of the universe/i],
        // Patterns that identify NEW Adventures (to avoid false matches)
        excludePatterns: [/new adventures/i],
    },
    {
        key: 'shera',
        name: 'She-Ra: Princess of Power',
        imdb_id: 'tt0126171',
        tv_series_uuid: '8c0e1b33-cf01-40a3-98eb-628368053070',
        series_type: 'tv_series',
        episodeFile: '/tmp/episodes-tt0126171-clean.json',
        patterns: [/she.?ra/i, /princess of power/i],
        excludePatterns: [],
    },
    {
        key: 'heman_new',
        name: 'The New Adventures of He-Man',
        imdb_id: 'tt0169477',
        tv_series_uuid: '9d5707ee-5663-4dcd-97c1-f29bde1bbac4',
        series_type: 'tv_series',
        episodeFile: '/tmp/episodes-tt0100546-clean.json',
        patterns: [/new adventures of he.?man/i, /new adventures.*he.?man/i],
        excludePatterns: [],
    },
]

// ---------------------------------------------------------------------------
// Load episode guide from JSON file
// ---------------------------------------------------------------------------
function loadEpisodeGuide(seriesDef) {
    if (!seriesDef.episodeFile) return []
    try {
        const raw = readFileSync(seriesDef.episodeFile, 'utf8')
        const data = JSON.parse(raw)
        return data.episodes || []
    } catch {
        console.warn(`  ⚠️  Could not load episode file: ${seriesDef.episodeFile}`)
        return []
    }
}

// ---------------------------------------------------------------------------
// Identify which series a staged movie belongs to
// ---------------------------------------------------------------------------
function identifySeries(movie) {
    const title = (movie.youtube_video_title || movie.title || '').toLowerCase()
    for (const series of SERIES_DEFINITIONS) {
        const excluded = series.excludePatterns.some(p => p.test(title))
        if (excluded) continue
        const matched = series.patterns.some(p => p.test(title))
        if (matched) return series
    }
    return null
}

// ---------------------------------------------------------------------------
// Match a YouTube title to the best episode in the guide
// ---------------------------------------------------------------------------
function matchEpisode(youtubeTitle, episodes) {
    if (!episodes.length) return null

    // YouTube titles are often "Episode Title | Series Name | Full Episode | ..."
    // Take only the first segment before any pipe — that's the actual episode title
    const firstSegment = youtubeTitle.split('|')[0].trim()

    // Also clean the first segment to remove common branding words
    const clean = firstSegment
        .replace(/he-?man|she-?ra|masters of the universe|princess of power/gi, '')
        .replace(/episode\s*\d+/i, '')
        .replace(/season\s*\d+/i, '')
        .replace(/official|full episode|cartoon|animated/gi, '')
        .replace(/[-–—]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim()

    let best = null
    let bestScore = 0

    // Try the first pipe-segment (episode title only)
    for (const ep of episodes) {
        const score = titleSimilarity(firstSegment, ep.title)
        if (score > bestScore) { bestScore = score; best = ep }
    }

    // Try cleaned version
    if (clean) {
        for (const ep of episodes) {
            const score = titleSimilarity(clean, ep.title)
            if (score > bestScore) { bestScore = score; best = ep }
        }
    }

    // Also try the full original title as fallback
    for (const ep of episodes) {
        const score = titleSimilarity(youtubeTitle, ep.title)
        if (score > bestScore) { bestScore = score; best = ep }
    }

    return best && bestScore >= 0.45 ? { episode: best, confidence: bestScore } : null
}

// ---------------------------------------------------------------------------
// Extract episode number from YouTube title as fallback
// ---------------------------------------------------------------------------
function extractEpisodeFromTitle(title) {
    const patterns = [
        /\bep(?:isode)?\.?\s*(\d+)/i,
        /\be(\d+)\b/i,
        /#(\d+)/,
        /\b(\d+)\s*of\s*\d+/i,
    ]
    for (const p of patterns) {
        const m = title.match(p)
        if (m) return parseInt(m[1])
    }
    return null
}

// ---------------------------------------------------------------------------
// Fetch all staged movies for a channel
// ---------------------------------------------------------------------------
async function fetchStagedMovies(channelName) {
    let all = [], page = 1
    while (true) {
        const res = await axios.get(`${BACKEND_URL}/api/admin/staging/movies`, {
            params: { channel: channelName, status: 'pending', limit: 100, page },
            headers
        })
        const movies = res.data.data?.movies || res.data.movies || []
        all = all.concat(movies)
        if (movies.length < 100) break
        page++
    }
    return all
}

// ---------------------------------------------------------------------------
// Fetch or create a tv_series record, return its UUID
// ---------------------------------------------------------------------------
async function getOrCreateTvSeries(seriesDef) {
    // Fetch all existing series and look for a match
    const res = await axios.get(`${BACKEND_URL}/api/admin/tv-series`, {
        params: { limit: 100 },
        headers
    })
    const existing = res.data.data?.series || res.data.series || []
    const found = existing.find(s => s.title.toLowerCase() === seriesDef.name.toLowerCase())
    if (found) {
        console.log(`  📺  Found existing series: "${found.title}" (${found.id})`)
        return found.id
    }

    if (DRY_RUN) {
        console.log(`  [DRY-RUN] Would create series: "${seriesDef.name}"`)
        return 'dry-run-uuid'
    }

    const create = await axios.post(`${BACKEND_URL}/api/admin/tv-series`, {
        title: seriesDef.name,
        imdb_id: seriesDef.imdb_id,
        description: `${seriesDef.name} — classic animated series`
    }, { headers })
    const newSeries = create.data.data || create.data
    console.log(`  ✅  Created series: "${newSeries.title}" (${newSeries.id})`)
    return newSeries.id
}

// ---------------------------------------------------------------------------
// Patch staging movie with episode metadata
// ---------------------------------------------------------------------------
async function patchEpisodeMetadata(movieId, fields) {
    if (DRY_RUN) return
    await axios.patch(`${BACKEND_URL}/api/admin/staging/movies/${movieId}`, fields, { headers })
}

// ---------------------------------------------------------------------------
// Enrich staged movie with IMDB ID
// ---------------------------------------------------------------------------
async function enrichWithImdb(movieId, imdbId) {
    if (DRY_RUN) return
    try {
        await axios.post(
            `${BACKEND_URL}/api/admin/staging/movies/${movieId}/enrich-manual-imdb`,
            { imdbId, verifiedBy: 'enrich-cartoon-channel' },
            { headers }
        )
    } catch (err) {
        const status = err.response?.status
        if (status === 404 || status === 500) {
            console.log(`    ⚠️  Server enrichment failed (${status}) — IMDB ID ${imdbId} may not be in OMDB`)
        } else {
            throw err
        }
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
    console.log(`🎬 Cartoon Channel Enrichment`)
    console.log(`   Channel: ${CHANNEL_ARG}`)
    console.log(`   Mode:    ${DRY_RUN ? 'DRY RUN (no changes)' : 'LIVE'}\n`)

    // Step 1: Fetch staged movies
    console.log('📥 Fetching staged movies...')
    const movies = await fetchStagedMovies(CHANNEL_ARG)
    console.log(`   Found ${movies.length} pending movies\n`)

    if (!movies.length) {
        console.log('Nothing to process.')
        return
    }

    // Step 2: Load episode guides and create/find tv_series records
    const seriesUuids = {}
    const episodeGuides = {}

    for (const def of SERIES_DEFINITIONS) {
        episodeGuides[def.key] = loadEpisodeGuide(def)
        console.log(`📺 Series: "${def.name}" — ${episodeGuides[def.key].length} episodes in guide`)
    }
    console.log()

    // Only create series records for ones we actually detect in the channel
    const detectedSeries = new Set()
    for (const movie of movies) {
        const series = identifySeries(movie)
        if (series) detectedSeries.add(series.key)
    }

    console.log(`🔍 Detected series in channel: ${[...detectedSeries].join(', ')}\n`)
    console.log('📡 TV series UUIDs (pre-created in Supabase):')

    for (const key of detectedSeries) {
        const def = SERIES_DEFINITIONS.find(s => s.key === key)
        seriesUuids[key] = def.tv_series_uuid
        console.log(`  📺 "${def.name}" → ${def.tv_series_uuid}`)
    }
    console.log()

    // Step 3: Process each episode
    const results = { matched: 0, fallback: 0, unmatched: 0, unknown_series: 0 }
    const unmatched = []

    for (let i = 0; i < movies.length; i++) {
        const movie = movies[i]
        const ytTitle = movie.youtube_video_title || movie.title || ''
        const prefix = `[${i + 1}/${movies.length}]`

        // Identify series
        const seriesDef = identifySeries(movie)
        if (!seriesDef) {
            console.log(`${prefix} ❓ Unknown series: "${ytTitle.slice(0, 60)}"`)
            results.unknown_series++
            unmatched.push({ title: ytTitle, reason: 'Unknown series' })
            continue
        }

        const guide = episodeGuides[seriesDef.key]
        const tvSeriesId = seriesUuids[seriesDef.key]

        // Try to match episode
        const match = matchEpisode(ytTitle, guide)

        if (match) {
            const ep = match.episode
            const pct = Math.round(match.confidence * 100)
            console.log(`${prefix} ✅ S${ep.season}E${ep.episode} "${ep.title}" (${pct}%) — "${ytTitle.slice(0, 40)}"`)

            await patchEpisodeMetadata(movie.id, {
                tv_series_id: tvSeriesId,
                is_tv_series: true,
                is_tv_show: true,
                is_kids_content: true,
                season_number: ep.season,
                episode_number: ep.episode,
                episode_name: ep.title,
            })

            const imdbId = ep.imdb_id || seriesDef.imdb_id
            await enrichWithImdb(movie.id, imdbId)
            results.matched++

        } else {
            // Fallback: try extracting episode number from title
            const epNum = extractEpisodeFromTitle(ytTitle)
            if (epNum) {
                console.log(`${prefix} ⚠️  No title match — using ep# from title: E${epNum} — "${ytTitle.slice(0, 40)}"`)
                await patchEpisodeMetadata(movie.id, {
                    tv_series_id: tvSeriesId,
                        is_tv_series: true,
                    is_tv_show: true,
                    is_kids_content: true,
                    episode_number: epNum,
                })
                await enrichWithImdb(movie.id, seriesDef.imdb_id)
                results.fallback++
            } else {
                console.log(`${prefix} ❌ No match: "${ytTitle.slice(0, 60)}"`)
                // Still set the series info even without episode number
                await patchEpisodeMetadata(movie.id, {
                    tv_series_id: tvSeriesId,
                        is_tv_series: true,
                    is_tv_show: true,
                    is_kids_content: true,
                })
                await enrichWithImdb(movie.id, seriesDef.imdb_id)
                results.unmatched++
                unmatched.push({ title: ytTitle, series: seriesDef.name })
            }
        }

        await sleep(600)
    }

    // Summary
    console.log('\n' + '─'.repeat(60))
    console.log('Results:')
    console.log(`  ✅ Fully matched (title + episode):  ${results.matched}`)
    console.log(`  ⚠️  Episode # from title (no name):   ${results.fallback}`)
    console.log(`  ❌ No episode match (series only):    ${results.unmatched}`)
    console.log(`  ❓ Unknown series:                    ${results.unknown_series}`)

    if (unmatched.length) {
        console.log('\nUnmatched episodes (need manual review):')
        for (const u of unmatched) {
            console.log(`  - ${u.title}${u.reason ? ` (${u.reason})` : ''}`)
        }
    }

    console.log('\nDone.')
}

main().catch(console.error)
