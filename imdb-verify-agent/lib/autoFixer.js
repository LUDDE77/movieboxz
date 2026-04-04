/**
 * autoFixer.js
 * Calls the backend enrich-manual-imdb endpoint to apply a verified IMDB ID.
 */

export async function applyImdbFix({ backendUrl, adminApiKey, movieId, imdbId }) {
    const url = `${backendUrl}/api/admin/movies/${movieId}/enrich-manual-imdb`
    const res = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'x-admin-api-key': adminApiKey
        },
        body: JSON.stringify({ imdbId, verifiedBy: 'imdb-verify-agent' })
    })

    if (!res.ok) {
        const text = await res.text()
        throw new Error(`API error ${res.status}: ${text.slice(0, 200)}`)
    }

    const json = await res.json()
    return json.data
}
