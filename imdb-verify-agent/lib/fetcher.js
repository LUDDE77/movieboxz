/**
 * fetcher.js
 * Fetches movies from the MovieBoxZ backend API (paginated).
 * Supports both production movies and staged movies.
 */

export async function fetchAllMovies({ backendUrl, adminApiKey, limit = null, skipVerified = false }) {
    const movies = []
    const pageSize = 100
    let page = 1
    let total = null

    console.log('📥 Fetching production movies from backend...')

    while (true) {
        const url = `${backendUrl}/api/movies?page=${page}&limit=${pageSize}`
        const res = await fetch(url, { headers: { 'x-admin-api-key': adminApiKey } })
        if (!res.ok) throw new Error(`Failed to fetch movies (page ${page}): HTTP ${res.status}`)

        const json = await res.json()
        const batch = json.movies || json.data?.movies || []
        if (total === null) total = json.pagination?.total ?? json.total ?? batch.length

        for (const movie of batch) {
            if (skipVerified && movie.enrichment_source === 'manual_imdb') continue
            movies.push(movie)
            if (limit && movies.length >= limit) {
                console.log(`   ✅ Fetched ${movies.length} movies (limit reached)`)
                return movies
            }
        }

        if (batch.length < pageSize) break
        page++
    }

    console.log(`   ✅ Fetched ${movies.length} of ${total} total movies`)
    return movies
}

export async function fetchStagingMovies({ backendUrl, adminApiKey, limit = null, skipVerified = false }) {
    const movies = []
    const pageSize = 100
    let page = 1
    let total = null

    console.log('📥 Fetching staged movies from backend...')

    while (true) {
        const url = `${backendUrl}/api/admin/staging/movies?status=pending&page=${page}&limit=${pageSize}`
        const res = await fetch(url, { headers: { 'x-admin-api-key': adminApiKey } })
        if (!res.ok) throw new Error(`Failed to fetch staging movies (page ${page}): HTTP ${res.status}`)

        const json = await res.json()
        const batch = json.data?.movies || json.movies || []
        if (total === null) total = json.data?.pagination?.total ?? json.pagination?.total ?? batch.length

        for (const movie of batch) {
            if (skipVerified && movie.manually_verified) continue
            // Normalise the imdb_id field — staging uses manual_imdb_id or imdb_id
            movie.imdb_id = movie.manual_imdb_id || movie.imdb_id || null
            movies.push(movie)
            if (limit && movies.length >= limit) {
                console.log(`   ✅ Fetched ${movies.length} staged movies (limit reached)`)
                return movies
            }
        }

        if (batch.length < pageSize) break
        page++
    }

    console.log(`   ✅ Fetched ${movies.length} of ${total} total staged movies`)
    return movies
}
