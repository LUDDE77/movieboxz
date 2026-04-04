/**
 * fetcher.js
 * Fetches all production movies from the MovieBoxZ backend API (paginated).
 */

export async function fetchAllMovies({ backendUrl, adminApiKey, limit = null, skipVerified = false }) {
    const movies = []
    const pageSize = 100
    let page = 1
    let total = null

    console.log('📥 Fetching movies from backend...')

    while (true) {
        const url = `${backendUrl}/api/movies?page=${page}&limit=${pageSize}`
        const res = await fetch(url, {
            headers: { 'x-admin-api-key': adminApiKey }
        })

        if (!res.ok) {
            throw new Error(`Failed to fetch movies (page ${page}): HTTP ${res.status}`)
        }

        const json = await res.json()
        const batch = json.movies || json.data?.movies || []
        if (total === null) {
            total = json.pagination?.total ?? json.total ?? batch.length
        }

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
