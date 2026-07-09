#!/usr/bin/env node
/**
 * check-and-fix-posters.js
 *
 * Checks all production movie poster URLs for dead links and attempts to fix them
 * via TMDB (stable path) or OMDB (Amazon CDN URL), falling back to null.
 *
 * Usage:
 *   TMDB_API_KEY=xxx OMDB_API_KEY=yyy SUPABASE_SERVICE_KEY=zzz \
 *     node scripts/check-and-fix-posters.js [--dry-run] [--only-dead]
 *
 * Flags:
 *   --dry-run    Check but do not write any updates to the DB
 *   --only-dead  Skip checking live posters; only process dead/null poster_path rows
 */

import axios from 'axios'

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const BACKEND_URL = 'https://movieboxz-backend-production.up.railway.app'
const ADMIN_KEY = process.env.ADMIN_API_KEY
const SUPABASE_URL = 'https://oltlikatlvbwavfxqazn.supabase.co'
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY
const TMDB_API_KEY = process.env.TMDB_API_KEY
const OMDB_API_KEY = process.env.OMDB_API_KEY

const DRY_RUN = process.argv.includes('--dry-run')
const ONLY_DEAD = process.argv.includes('--only-dead')

const CONCURRENCY = 8
const BATCH_DELAY_MS = 200

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sleep(ms) {
  return new Promise(r => setTimeout(r, ms))
}

/** Supabase REST headers */
function supabaseHeaders() {
  return {
    'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
    'apikey': SUPABASE_SERVICE_KEY,
    'Content-Type': 'application/json',
    'Prefer': 'return=minimal',
  }
}

/** Run an array of async tasks with a fixed concurrency limit. */
async function pLimit(tasks, concurrency) {
  const results = []
  let index = 0

  async function worker() {
    while (index < tasks.length) {
      const i = index++
      results[i] = await tasks[i]()
    }
  }

  const workers = Array.from({ length: Math.min(concurrency, tasks.length) }, () => worker())
  await Promise.all(workers)
  return results
}

// ---------------------------------------------------------------------------
// Supabase queries
// ---------------------------------------------------------------------------

/** Fetch all movies (paginated, up to 10 000) */
async function fetchAllMovies() {
  const pageSize = 1000
  let offset = 0
  let all = []

  while (true) {
    const url =
      `${SUPABASE_URL}/rest/v1/movies` +
      `?select=id,title,imdb_id,poster_path` +
      `&order=id` +
      `&limit=${pageSize}&offset=${offset}`

    const res = await axios.get(url, { headers: supabaseHeaders(), timeout: 30000 })
    const rows = res.data
    all = all.concat(rows)
    if (rows.length < pageSize) break
    offset += pageSize
  }

  return all
}

/** PATCH a single movie's poster_path in the DB. */
async function updatePosterPath(movieId, posterPath) {
  if (DRY_RUN) return

  const url = `${SUPABASE_URL}/rest/v1/movies?id=eq.${movieId}`
  await axios.patch(
    url,
    { poster_path: posterPath, updated_at: new Date().toISOString() },
    { headers: supabaseHeaders(), timeout: 15000 }
  )
}

// ---------------------------------------------------------------------------
// URL checking
// ---------------------------------------------------------------------------

/**
 * Returns true if the URL is reachable (HTTP 2xx).
 * For TMDB paths (starting with "/"), constructs the full w185 URL first.
 */
async function isUrlAlive(rawUrl) {
  let url = rawUrl
  if (rawUrl.startsWith('/')) {
    url = `https://image.tmdb.org/t/p/w185${rawUrl}`
  }

  try {
    const res = await axios({ method: 'head', url, timeout: 8000, validateStatus: null })
    return res.status >= 200 && res.status < 300
  } catch {
    return false
  }
}

// ---------------------------------------------------------------------------
// Metadata lookups
// ---------------------------------------------------------------------------

/**
 * Try TMDB /find by IMDB ID.
 * Returns a TMDB poster_path string (e.g. "/abc123.jpg") or null.
 */
async function fetchPosterFromTMDB(imdbId) {
  if (!TMDB_API_KEY || !imdbId) return null

  try {
    const res = await axios.get(
      `https://api.themoviedb.org/3/find/${imdbId}` +
        `?external_source=imdb_id&api_key=${TMDB_API_KEY}`,
      { timeout: 10000, validateStatus: null }
    )
    if (res.status !== 200) return null
    const results = res.data?.movie_results
    if (Array.isArray(results) && results.length > 0 && results[0].poster_path) {
      return results[0].poster_path // e.g. "/abc123.jpg"
    }
  } catch {
    // network error — fall through
  }
  return null
}

/**
 * Try OMDB by IMDB ID.
 * Returns the Poster URL string or null.
 */
async function fetchPosterFromOMDB(imdbId) {
  if (!OMDB_API_KEY || !imdbId) return null

  try {
    const res = await axios.get(
      `https://www.omdbapi.com/?i=${imdbId}&apikey=${OMDB_API_KEY}`,
      { timeout: 10000, validateStatus: null }
    )
    if (res.status !== 200) return null
    const poster = res.data?.Poster
    if (poster && poster !== 'N/A') return poster
  } catch {
    // network error — fall through
  }
  return null
}

// ---------------------------------------------------------------------------
// Per-movie fix logic
// ---------------------------------------------------------------------------

/**
 * Attempt to find a replacement poster for a movie.
 * Returns { source: 'tmdb'|'omdb'|'none', posterPath: string|null }
 */
async function findReplacementPoster(movie) {
  // 1. Try TMDB (stable path, preferred)
  const tmdbPath = await fetchPosterFromTMDB(movie.imdb_id)
  if (tmdbPath) return { source: 'tmdb', posterPath: tmdbPath }

  // 2. Fall back to OMDB (Amazon CDN URL)
  const omdbUrl = await fetchPosterFromOMDB(movie.imdb_id)
  if (omdbUrl) return { source: 'omdb', posterPath: omdbUrl }

  return { source: 'none', posterPath: null }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  // Validate required env vars
  if (!SUPABASE_SERVICE_KEY) {
    console.error('ERROR: SUPABASE_SERVICE_KEY env var is required.')
    process.exit(1)
  }
  if (!TMDB_API_KEY) {
    console.warn('WARNING: TMDB_API_KEY not set — TMDB lookups will be skipped.')
  }
  if (!OMDB_API_KEY) {
    console.warn('WARNING: OMDB_API_KEY not set — OMDB fallback will be skipped.')
  }

  console.log(`\n=== check-and-fix-posters ===`)
  if (DRY_RUN) console.log('DRY RUN — no DB writes will happen.')
  if (ONLY_DEAD) console.log('--only-dead — skipping live-poster checks.')
  console.log()

  // ---- Fetch all movies ----
  console.log('Fetching all production movies from Supabase...')
  const allMovies = await fetchAllMovies()
  console.log(`Fetched ${allMovies.length} movies.\n`)

  // ---- Separate null-poster from has-poster rows ----
  const nullPosterMovies = allMovies.filter(m => !m.poster_path)
  const hasPosterMovies  = allMovies.filter(m => !!m.poster_path)

  console.log(`  With poster_path   : ${hasPosterMovies.length}`)
  console.log(`  Without poster_path: ${nullPosterMovies.length}`)
  console.log()

  // ---- Counters ----
  const stats = {
    totalChecked: 0,
    deadFound: 0,
    fixedViaTMDB: 0,
    fixedViaOMDB: 0,
    nulled: 0,
    alreadyLive: 0,
    errors: 0,
  }

  // ---- Step 1: Check existing poster URLs (unless --only-dead) ----
  const deadMovies = [] // movies needing repair

  if (!ONLY_DEAD) {
    console.log(`Checking ${hasPosterMovies.length} poster URLs in batches of ${CONCURRENCY}...\n`)

    for (let i = 0; i < hasPosterMovies.length; i += CONCURRENCY) {
      const batch = hasPosterMovies.slice(i, i + CONCURRENCY)

      await pLimit(
        batch.map(movie => async () => {
          stats.totalChecked++
          const n = stats.totalChecked
          const label = `[${n}/${hasPosterMovies.length}] ${movie.title}`

          try {
            const alive = await isUrlAlive(movie.poster_path)
            if (alive) {
              stats.alreadyLive++
              process.stdout.write(`  LIVE   ${label}\n`)
            } else {
              stats.deadFound++
              deadMovies.push(movie)
              process.stdout.write(`  DEAD   ${label}\n`)
            }
          } catch (e) {
            stats.errors++
            process.stdout.write(`  ERROR  ${label} — ${e.message}\n`)
          }
        }),
        CONCURRENCY
      )

      if (i + CONCURRENCY < hasPosterMovies.length) {
        await sleep(BATCH_DELAY_MS)
      }
    }

    console.log()
  } else {
    // In --only-dead mode, treat all movies with poster_path as "already live" (skip check)
    stats.alreadyLive = hasPosterMovies.length
    console.log(`--only-dead: skipped checking ${hasPosterMovies.length} existing poster URLs.\n`)
  }

  // ---- Step 2: Build the repair list (dead + null) ----
  const toFix = [...deadMovies, ...nullPosterMovies]
  console.log(`Movies to fix: ${toFix.length} (${deadMovies.length} dead + ${nullPosterMovies.length} null)\n`)

  if (toFix.length === 0) {
    console.log('Nothing to fix!')
  } else {
    console.log(`Looking up replacement posters for ${toFix.length} movies...\n`)

    for (let i = 0; i < toFix.length; i += CONCURRENCY) {
      const batch = toFix.slice(i, i + CONCURRENCY)

      await pLimit(
        batch.map(movie => async () => {
          const n = i + batch.indexOf(movie) + 1
          const label = `[${n}/${toFix.length}] ${movie.title}`

          const { source, posterPath } = await findReplacementPoster(movie)

          if (source === 'tmdb') {
            stats.fixedViaTMDB++
            process.stdout.write(`  FIXED(tmdb)  ${label}\n`)
          } else if (source === 'omdb') {
            stats.fixedViaOMDB++
            process.stdout.write(`  FIXED(omdb)  ${label}\n`)
          } else {
            stats.nulled++
            process.stdout.write(`  NULLED       ${label}\n`)
          }

          try {
            await updatePosterPath(movie.id, posterPath)
          } catch (e) {
            stats.errors++
            process.stdout.write(`  DB-ERROR     ${label} — ${e.message}\n`)
          }
        }),
        CONCURRENCY
      )

      if (i + CONCURRENCY < toFix.length) {
        await sleep(BATCH_DELAY_MS)
      }
    }
  }

  // ---- Summary ----
  console.log(`
=== Summary ===
  Total movies in DB         : ${allMovies.length}
  Poster URLs checked        : ${ONLY_DEAD ? 0 : hasPosterMovies.length}
  Dead URLs found            : ${stats.deadFound}
  Null posters processed     : ${nullPosterMovies.length}
  Fixed via TMDB             : ${stats.fixedViaTMDB}
  Fixed via OMDB             : ${stats.fixedViaOMDB}
  Nulled (no source found)   : ${stats.nulled}
  Already live (no change)   : ${stats.alreadyLive}
  Errors                     : ${stats.errors}
  ${DRY_RUN ? '(DRY RUN — no writes made)' : ''}
`)
}

main().catch(err => {
  console.error('Fatal error:', err)
  process.exit(1)
})
