/**
 * autoFixer.js
 * Applies a verified IMDB ID to a production movie.
 * Primary: calls enrich-manual-imdb (server does axios scraping)
 * Fallback: scrapes IMDB locally with Playwright and calls enrich-from-data
 */

import { scrapeImdbWithPlaywright } from './imdbSearcher.js'

export async function applyImdbFix({ backendUrl, adminApiKey, movieId, imdbId }) {
    // Try the server-side enrichment first
    try {
        const result = await callEnrichManualImdb({ backendUrl, adminApiKey, movieId, imdbId })
        return result
    } catch (err) {
        // 500 means the server's axios scraper was blocked — fall back to local Playwright
        if (err.message.includes('500')) {
            console.log(`   ⚠️  Server enrichment failed for ${imdbId} — using local Playwright fallback`)
            return await applyWithPlaywrightFallback({ backendUrl, adminApiKey, movieId, imdbId })
        }
        throw err
    }
}

async function callEnrichManualImdb({ backendUrl, adminApiKey, movieId, imdbId }) {
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

async function applyWithPlaywrightFallback({ backendUrl, adminApiKey, movieId, imdbId }) {
    // Scrape the IMDB title page locally with Playwright
    const imdbData = await scrapeImdbWithPlaywright(imdbId)

    // Send scraped data directly to the backend
    const url = `${backendUrl}/api/admin/movies/${movieId}/enrich-from-data`
    const res = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'x-admin-api-key': adminApiKey
        },
        body: JSON.stringify({ imdbId, ...imdbData })
    })

    if (!res.ok) {
        const text = await res.text()
        throw new Error(`enrich-from-data error ${res.status}: ${text.slice(0, 200)}`)
    }

    const json = await res.json()
    return json.data
}
