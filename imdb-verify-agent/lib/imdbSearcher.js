/**
 * imdbSearcher.js
 * Uses Playwright to search IMDB for movie candidates.
 * Reuses a single browser instance across all movies for performance.
 */

import { chromium } from 'playwright'

let browser = null
let context = null

export async function initBrowser() {
    browser = await chromium.launch({ headless: true })
    context = await browser.newContext({
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        locale: 'en-US',
        extraHTTPHeaders: { 'Accept-Language': 'en-US,en;q=0.9' }
    })
    console.log('🎭 Playwright browser started')
}

export async function closeBrowser() {
    await context?.close()
    await browser?.close()
    context = null
    browser = null
    console.log('🎭 Playwright browser closed')
}

/**
 * Search for a movie on IMDB.
 * Strategy 1: IMDB suggestion API (fast JSON, no browser needed) using the
 *             YouTube video title — same API as the IMDB search box
 * Strategy 2: Fallback to the cleaned movie title if YouTube title gives nothing
 * Then: visit each candidate's IMDB page with Playwright to get full JSON-LD data.
 * @param {object} movie - { title, youtube_video_title, release_date, director, actors }
 * @returns {Array} candidates with { imdbId, title, year, directors, actors, type, posterUrl }
 */
export async function searchIMDB(movie) {
    // ── Step 1: get tt-IDs from IMDB suggestion API (no browser) ──────────────
    const ytTitle = movie.youtube_video_title || ''
    const cleanedTitle = buildQuery(movie)

    // Try the YouTube title first (keeps year/subtitle info that helps matching)
    let rawIds = await fetchImdbSuggestions(ytTitle)

    // If YouTube title gives nothing, try the cleaned title
    if (!rawIds.length) {
        rawIds = await fetchImdbSuggestions(cleanedTitle)
    }

    // ── Step 2: enrich top 3 candidates by visiting their IMDB pages ──────────
    const page = await context.newPage()
    try {
        const candidates = []
        for (const raw of rawIds.slice(0, 3)) {
            try {
                const enriched = await enrichCandidate(page, raw)
                candidates.push(enriched)
            } catch {
                candidates.push({ ...raw, directors: [], actors: [], type: 'Movie' })
            }
            await page.waitForTimeout(300)
        }
        return candidates
    } finally {
        await page.close()
    }
}

/**
 * Call the IMDB suggestion/autocomplete JSON API.
 * This is the same endpoint the IMDB search box uses — no auth, no CAPTCHA.
 * Returns up to 5 candidate objects: { imdbId, title, year, posterUrl }
 */
async function fetchImdbSuggestions(query) {
    if (!query || query.length < 2) return []

    // Clean up YouTube noise words that confuse the API
    const cleaned = query
        .replace(/\b(full movie|full episode|hd|4k|1080p|720p|free|official|trailer)\b/gi, '')
        .replace(/\s+/g, ' ')
        .trim()

    if (!cleaned) return []

    try {
        const encoded = encodeURIComponent(cleaned)
        const url = `https://v2.sg.media-imdb.com/suggestion/x/${encoded}.json`
        const res = await fetch(url, {
            headers: { 'Accept': 'application/json', 'Accept-Language': 'en-US,en;q=0.9' },
            signal: AbortSignal.timeout(8000)
        })
        if (!res.ok) return []
        const data = await res.json()

        return (data.d || [])
            .filter(r => r.id && r.id.startsWith('tt'))
            .map(r => ({
                imdbId: r.id,
                title: r.l || '',
                year: r.y ? String(r.y) : '',
                posterUrl: r.i?.imageUrl || ''
            }))
            .slice(0, 5)
    } catch {
        return []
    }
}

async function enrichCandidate(page, raw) {
    const titleUrl = `https://www.imdb.com/title/${raw.imdbId}/`
    await page.goto(titleUrl, { waitUntil: 'domcontentloaded', timeout: 12000 })
    await page.waitForTimeout(1000)

    // Extract JSON-LD structured data
    const jsonLd = await page.evaluate(() => {
        const scripts = document.querySelectorAll('script[type="application/ld+json"]')
        for (const s of scripts) {
            try {
                const data = JSON.parse(s.textContent)
                if (data['@type'] === 'Movie' || data['@type'] === 'TVSeries') return data
            } catch {}
        }
        return null
    })

    if (jsonLd) {
        return {
            imdbId: raw.imdbId,
            title: jsonLd.name || raw.title,
            year: extractYearFromDate(jsonLd.datePublished) || raw.year,
            directors: extractNames(jsonLd.director),
            actors: extractNames(jsonLd.actor),
            type: jsonLd['@type'] || 'Movie',
            posterUrl: typeof jsonLd.image === 'string' ? jsonLd.image : (jsonLd.image?.url || raw.posterUrl),
            description: jsonLd.description?.slice(0, 200) || ''
        }
    }

    // Fallback: scrape visible page elements
    const pageData = await page.evaluate(() => {
        const titleEl = document.querySelector('[data-testid="hero__pageTitle"] span, h1[data-testid="hero-title-block__title"]')
        const yearEl = document.querySelector('[data-testid="hero-title-block__metadata"] a, .sc-8c396aa2-2')
        const dirEls = document.querySelectorAll('[data-testid="title-pc-principal-credit"] a')
        const dirs = [...dirEls].slice(0, 3).map(e => e.textContent.trim()).filter(Boolean)
        const posterEl = document.querySelector('.ipc-image, [data-testid="hero-media__poster"] img')
        return {
            title: titleEl?.textContent?.trim() || '',
            year: yearEl?.textContent?.trim() || '',
            directors: dirs,
            posterUrl: posterEl?.src || ''
        }
    })

    return {
        imdbId: raw.imdbId,
        title: pageData.title || raw.title,
        year: pageData.year || raw.year,
        directors: pageData.directors,
        actors: [],
        type: 'Movie',
        posterUrl: pageData.posterUrl || raw.posterUrl,
        description: ''
    }
}

/**
 * Scrape a single IMDB title page by ID using Playwright.
 * Used as a fallback enrichment source when the server's axios scraper is blocked.
 * Reuses the shared browser if available; opens a temporary one otherwise.
 * @param {string} imdbId - e.g. "tt1234567"
 * @returns {{ title, year, directors, actors, description, posterUrl, genres, imdbRating, type }}
 */
export async function scrapeImdbWithPlaywright(imdbId) {
    let ownBrowser = false
    let page = null

    // If the shared browser context isn't running, open a temporary one
    if (!context) {
        const { chromium } = await import('playwright')
        const tempBrowser = await chromium.launch({ headless: true })
        const tempContext = await tempBrowser.newContext({
            userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            locale: 'en-US',
            extraHTTPHeaders: { 'Accept-Language': 'en-US,en;q=0.9' }
        })
        page = await tempContext.newPage()
        ownBrowser = true

        try {
            const data = await _scrapeOnePage(page, imdbId)
            return data
        } finally {
            await page.close()
            await tempContext.close()
            await tempBrowser.close()
        }
    } else {
        page = await context.newPage()
        try {
            return await _scrapeOnePage(page, imdbId)
        } finally {
            await page.close()
        }
    }
}

async function _scrapeOnePage(page, imdbId) {
    const titleUrl = `https://www.imdb.com/title/${imdbId}/`
    await page.goto(titleUrl, { waitUntil: 'domcontentloaded', timeout: 15000 })
    await page.waitForTimeout(1500)

    // Handle cookie consent
    try {
        const btn = page.locator('button:has-text("Accept"), button:has-text("Godkänn")')
        if (await btn.first().isVisible({ timeout: 1000 })) {
            await btn.first().click()
            await page.waitForTimeout(800)
        }
    } catch {}

    // Try JSON-LD first
    const jsonLd = await page.evaluate(() => {
        const scripts = document.querySelectorAll('script[type="application/ld+json"]')
        for (const s of scripts) {
            try {
                const data = JSON.parse(s.textContent)
                if (data['@type'] === 'Movie' || data['@type'] === 'TVSeries') return data
            } catch {}
        }
        return null
    })

    if (jsonLd) {
        // Extract IMDB user rating from aggregateRating
        const imdbRating = jsonLd.aggregateRating?.ratingValue
            ? String(jsonLd.aggregateRating.ratingValue)
            : null

        // Extract genre array
        const genres = jsonLd.genre
            ? (Array.isArray(jsonLd.genre) ? jsonLd.genre : [jsonLd.genre])
            : []

        return {
            title: jsonLd.name || '',
            year: extractYearFromDate(jsonLd.datePublished) || '',
            directors: extractNames(jsonLd.director),
            actors: extractNames(jsonLd.actor),
            description: jsonLd.description?.slice(0, 300) || '',
            posterUrl: typeof jsonLd.image === 'string' ? jsonLd.image : (jsonLd.image?.url || ''),
            genres,
            imdbRating,
            type: jsonLd['@type'] || 'Movie'
        }
    }

    // DOM fallback
    const dom = await page.evaluate(() => {
        const titleEl = document.querySelector('[data-testid="hero__pageTitle"] span, h1[data-testid="hero-title-block__title"]')
        const posterEl = document.querySelector('[data-testid="hero-media__poster"] img, .ipc-image')
        return {
            title: titleEl?.textContent?.trim() || '',
            posterUrl: posterEl?.src || ''
        }
    })

    return {
        title: dom.title,
        year: '',
        directors: [],
        actors: [],
        description: '',
        posterUrl: dom.posterUrl,
        genres: [],
        imdbRating: null,
        type: 'Movie'
    }
}

function buildQuery(movie) {
    let q = movie.title || ''
    const year = extractYearFromDate(movie.release_date) || movie.year
    if (year) q += ` ${year}`
    return q.trim()
}

function extractYearFromDate(str) {
    if (!str) return null
    const m = String(str).match(/\b(19|20)\d{2}\b/)
    return m ? m[0] : null
}

function extractNames(data) {
    if (!data) return []
    const arr = Array.isArray(data) ? data : [data]
    return arr.map(d => d?.name).filter(Boolean)
}
