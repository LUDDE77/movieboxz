/**
 * Episode Matcher — pure fuzzy-matching utilities for TV series episode matching.
 *
 * Ported from scripts/enrich-cartoon-channel.js (the manual one-off script) so the
 * matching logic is reusable by the API and unit-testable without network/DB access.
 *
 * Flow:
 *   1. detectSeries()       — which series (of the candidates) does a YouTube title belong to?
 *   2. matchEpisode()       — which episode in that series' guide does the title match?
 *   3. proposeEpisodeMatch() — combines both into a single proposal (or an unmatched reason)
 */

// Minimum similarity (0-1) for an episode-name match to count
export const EPISODE_MATCH_THRESHOLD = 0.45

// Words ignored when scoring partial series-name matches
const SERIES_STOP_WORDS = new Set(['the', 'a', 'an', 'of', 'and', 'in', 'on'])

/**
 * Levenshtein edit distance (same approach as the imdb-verify-agent scorer).
 */
export function levenshtein(a, b) {
    const m = a.length, n = b.length
    const dp = Array.from({ length: m + 1 }, (_, i) =>
        Array.from({ length: n + 1 }, (_, j) => (i === 0 ? j : j === 0 ? i : 0))
    )
    for (let i = 1; i <= m; i++) {
        for (let j = 1; j <= n; j++) {
            dp[i][j] = a[i - 1] === b[j - 1]
                ? dp[i - 1][j - 1]
                : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1])
        }
    }
    return dp[m][n]
}

/**
 * Lowercase, strip everything but [a-z0-9 ] and collapse whitespace.
 * "He-Man!" -> "heman", "She-Ra: Princess of Power" -> "shera princess of power"
 */
export function normalizeTitle(value) {
    return String(value || '')
        .toLowerCase()
        .replace(/[^a-z0-9 ]/g, '')
        .replace(/\s+/g, ' ')
        .trim()
}

/**
 * Similarity of two titles on a 0-1 scale (1 = identical after normalization).
 */
export function titleSimilarity(a, b) {
    const na = normalizeTitle(a)
    const nb = normalizeTitle(b)
    if (!na || !nb) return 0
    if (na === nb) return 1
    const dist = levenshtein(na, nb)
    return 1 - dist / Math.max(na.length, nb.length)
}

/**
 * Determine which series a YouTube title belongs to.
 *
 * @param {string} youtubeTitle
 * @param {Array<{title: string}>} seriesList - candidate series (any extra props pass through)
 * @returns the best-matching entry of seriesList, or null
 *
 * Strategy: full containment of the normalized series name wins (longest name breaks
 * ties, so "The New Adventures of He-Man" beats "He-Man..." on New Adventures uploads).
 * Falls back to significant-token overlap (>= 50% of the series name's tokens).
 */
export function detectSeries(youtubeTitle, seriesList) {
    const nt = normalizeTitle(youtubeTitle)
    if (!nt) return null
    const titleTokens = new Set(nt.split(' '))

    let best = null
    for (const series of seriesList || []) {
        const ns = normalizeTitle(series?.title)
        if (!ns) continue

        let score
        if (nt.includes(ns)) {
            // Full containment always beats partial matches; longer names win ties
            score = 1 + ns.length / 1000
        } else {
            const tokens = ns.split(' ').filter(t => !SERIES_STOP_WORDS.has(t))
            if (!tokens.length) continue
            const hits = tokens.filter(t => titleTokens.has(t)).length
            score = hits / tokens.length
            if (score < 0.5) continue
        }

        if (!best || score > best.score) best = { series, score }
    }
    return best ? best.series : null
}

/**
 * Strip series branding / filler from a YouTube title so what's left is
 * (hopefully) the raw episode name.
 */
export function cleanEpisodeTitle(youtubeTitle, seriesTitle = null) {
    // YouTube titles are often "Episode Title | Series Name | Full Episode | ..."
    let s = String(youtubeTitle || '').split('|')[0]

    if (seriesTitle) {
        // Match the series name with flexible hyphens/whitespace ("He-Man" vs "He Man")
        const escaped = String(seriesTitle)
            .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
            .replace(/[-:\s]+/g, '[-:\\s]*')
        try {
            s = s.replace(new RegExp(escaped, 'gi'), ' ')
        } catch {
            // Malformed pattern — keep the original text
        }
    }

    return s
        .replace(/full\s*episodes?/gi, ' ')
        .replace(/\b(official|cartoons?|animated|remastered|classics?)\b/gi, ' ')
        .replace(/\b(1080p|720p|480p|hd|4k)\b/gi, ' ')
        .replace(/\bseason\s*\d+\b/gi, ' ')
        .replace(/\bep(?:isode)?\.?\s*\d+\b/gi, ' ')
        .replace(/[-–—:|]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim()
}

/**
 * Fuzzy-match a YouTube title against an episode guide.
 *
 * @param {string} youtubeTitle
 * @param {Array<{season:number, episode:number, name?:string, title?:string}>} episodes
 * @param {string|null} seriesTitle - stripped from the YouTube title before matching
 * @returns {{season, episode, name, confidence}|null} confidence is 0-100
 */
export function matchEpisode(youtubeTitle, episodes, seriesTitle = null) {
    if (!youtubeTitle || !Array.isArray(episodes) || episodes.length === 0) return null

    const firstSegment = String(youtubeTitle).split('|')[0].trim()
    const cleaned = cleanEpisodeTitle(youtubeTitle, seriesTitle)
    const candidates = [...new Set([cleaned, firstSegment, String(youtubeTitle)])].filter(Boolean)

    let best = null
    let bestScore = 0
    for (const ep of episodes) {
        const name = ep?.name ?? ep?.title
        if (!name) continue
        for (const candidate of candidates) {
            const score = titleSimilarity(candidate, name)
            if (score > bestScore) {
                bestScore = score
                best = ep
            }
        }
    }

    if (!best || bestScore < EPISODE_MATCH_THRESHOLD) return null
    return {
        season: best.season,
        episode: best.episode,
        name: best.name ?? best.title,
        confidence: Math.min(100, Math.round(bestScore * 100))
    }
}

/**
 * Extract an episode number from a YouTube title as a last-resort fallback.
 */
export function extractEpisodeNumber(title) {
    const patterns = [
        /\bep(?:isode)?\.?\s*(\d+)/i,
        /\be(\d+)\b/i,
        /#(\d+)/,
        /\b(\d+)\s*of\s*\d+/i
    ]
    for (const pattern of patterns) {
        const m = String(title || '').match(pattern)
        if (m) return parseInt(m[1])
    }
    return null
}

/**
 * End-to-end proposal for one YouTube title.
 *
 * @param {string} youtubeTitle
 * @param {Array<{tvSeriesId:string, title:string, episodes:Array}>} seriesOptions
 * @returns {{matched:true, tvSeriesId, season, episode, episodeName, confidence}
 *         | {matched:false, reason:string, tvSeriesId?:string}}
 */
export function proposeEpisodeMatch(youtubeTitle, seriesOptions) {
    const series = detectSeries(youtubeTitle, seriesOptions || [])
    if (!series) return { matched: false, reason: 'no_series_match' }

    if (!Array.isArray(series.episodes) || series.episodes.length === 0) {
        return { matched: false, reason: 'no_episode_guide', tvSeriesId: series.tvSeriesId }
    }

    const match = matchEpisode(youtubeTitle, series.episodes, series.title)
    if (!match) return { matched: false, reason: 'no_episode_match', tvSeriesId: series.tvSeriesId }

    return {
        matched: true,
        tvSeriesId: series.tvSeriesId,
        season: match.season,
        episode: match.episode,
        episodeName: match.name,
        confidence: match.confidence
    }
}
