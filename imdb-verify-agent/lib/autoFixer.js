/**
 * autoFixer.js
 * Applies a verified IMDB ID to a movie (production or staging).
 * Primary: calls enrich-manual-imdb (server does axios scraping)
 * Fallback: scrapes IMDB locally with Playwright and calls enrich-from-data
 */

import { scrapeImdbWithPlaywright } from './imdbSearcher.js'

export async function applyImdbFix({ backendUrl, adminApiKey, movieId, imdbId, mode = 'production' }) {
    try {
        return await callEnrichManualImdb({ backendUrl, adminApiKey, movieId, imdbId, mode })
    } catch (err) {
        if (err.message.includes('500') || err.message.includes('404')) {
            console.log(`   ⚠️  Server enrichment failed for ${imdbId} — using local Playwright fallback`)
            return await applyWithPlaywrightFallback({ backendUrl, adminApiKey, movieId, imdbId, mode })
        }
        throw err
    }
}

export async function approveMovie({ backendUrl, adminApiKey, movieId }) {
    const url = `${backendUrl}/api/admin/staging/movies/${movieId}/approve`
    const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-admin-api-key': adminApiKey },
        body: JSON.stringify({ approvedBy: 'imdb-verify-agent' })
    })
    if (!res.ok) {
        const text = await res.text()
        throw new Error(`Approve error ${res.status}: ${text.slice(0, 200)}`)
    }
    return (await res.json()).data
}

function enrichUrl(backendUrl, movieId, mode) {
    return mode === 'staging'
        ? `${backendUrl}/api/admin/staging/movies/${movieId}/enrich-manual-imdb`
        : `${backendUrl}/api/admin/movies/${movieId}/enrich-manual-imdb`
}

function enrichFromDataUrl(backendUrl, movieId, mode) {
    return mode === 'staging'
        ? `${backendUrl}/api/admin/staging/movies/${movieId}/enrich-from-data`
        : `${backendUrl}/api/admin/movies/${movieId}/enrich-from-data`
}

async function callEnrichManualImdb({ backendUrl, adminApiKey, movieId, imdbId, mode }) {
    const url = enrichUrl(backendUrl, movieId, mode)
    const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-admin-api-key': adminApiKey },
        body: JSON.stringify({ imdbId, verifiedBy: 'imdb-verify-agent' })
    })
    if (!res.ok) {
        const text = await res.text()
        throw new Error(`API error ${res.status}: ${text.slice(0, 200)}`)
    }
    return (await res.json()).data
}

async function applyWithPlaywrightFallback({ backendUrl, adminApiKey, movieId, imdbId, mode }) {
    const imdbData = await scrapeImdbWithPlaywright(imdbId)
    const url = enrichFromDataUrl(backendUrl, movieId, mode)
    const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-admin-api-key': adminApiKey },
        body: JSON.stringify({ imdbId, ...imdbData })
    })
    if (!res.ok) {
        const text = await res.text()
        throw new Error(`enrich-from-data error ${res.status}: ${text.slice(0, 200)}`)
    }
    return (await res.json()).data
}
