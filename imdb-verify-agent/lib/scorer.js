/**
 * scorer.js
 * Pure confidence scoring: compares a stored movie against an IMDB candidate.
 * Returns { confidence: 0-100, breakdown: {...}, verdict }
 *
 * Scoring components:
 *   Title similarity   30 pts
 *   Year match         25 pts
 *   Director match     20 pts
 *   Actor overlap      15 pts
 *   Media type         10 pts
 *
 * Verdicts:
 *   confidence >= 85 → 'auto-fix' (or 'confirmed-match' if IDs already match)
 *   confidence 50-84 → 'review'
 *   confidence < 50  → 'low-confidence'
 */

// Levenshtein distance
function levenshtein(a, b) {
    const m = a.length, n = b.length
    const dp = Array.from({ length: m + 1 }, (_, i) =>
        Array.from({ length: n + 1 }, (_, j) => (i === 0 ? j : j === 0 ? i : 0))
    )
    for (let i = 1; i <= m; i++) {
        for (let j = 1; j <= n; j++) {
            dp[i][j] = a[i-1] === b[j-1]
                ? dp[i-1][j-1]
                : 1 + Math.min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
        }
    }
    return dp[m][n]
}

function normalize(str) {
    if (!str) return ''
    return str
        .toLowerCase()
        .replace(/^(the|a|an)\s+/i, '')   // strip leading articles
        .replace(/[^\w\s]/g, '')            // remove punctuation
        .replace(/\s+/g, ' ')
        .trim()
}

function titleSimilarity(a, b) {
    const na = normalize(a), nb = normalize(b)
    if (!na || !nb) return 0
    if (na === nb) return 1.0
    const maxLen = Math.max(na.length, nb.length)
    return 1 - levenshtein(na, nb) / maxLen
}

function extractYear(str) {
    if (!str) return null
    const m = String(str).match(/\b(19|20)\d{2}\b/)
    return m ? parseInt(m[0]) : null
}

function normalizeNames(str) {
    if (!str) return []
    return str.toLowerCase().split(/[,&\/\n]/).map(s => s.trim()).filter(Boolean)
}

export function scoreCandidate(storedMovie, candidate) {
    const breakdown = {}
    let total = 0

    // ── 1. Title (30 pts) ──────────────────────────────────────────────────
    const titleSim = titleSimilarity(storedMovie.title, candidate.title)
    let titlePts = 0
    if (titleSim >= 1.0)       titlePts = 30
    else if (titleSim >= 0.90) titlePts = 25
    else if (titleSim >= 0.75) titlePts = 15
    else if (titleSim >= 0.60) titlePts = 8
    breakdown.title = { pts: titlePts, max: 30, sim: Math.round(titleSim * 100) }
    total += titlePts

    // ── 2. Year (25 pts) ───────────────────────────────────────────────────
    const storedYear = extractYear(storedMovie.release_date) ?? extractYear(storedMovie.year)
    const candYear   = extractYear(candidate.year)
    let yearPts = 0
    if (storedYear && candYear) {
        const diff = Math.abs(storedYear - candYear)
        if (diff === 0)      yearPts = 25
        else if (diff === 1) yearPts = 18
        else if (diff === 2) yearPts = 10
        else if (diff === 3) yearPts = 5
    } else if (!storedYear) {
        // neutral - no data to compare, award half
        yearPts = 12
    }
    breakdown.year = { pts: yearPts, max: 25, stored: storedYear, candidate: candYear }
    total += yearPts

    // ── 3. Director (20 pts) ───────────────────────────────────────────────
    let dirPts = 0
    if (!storedMovie.director) {
        dirPts = 10 // neutral
    } else if (candidate.directors?.length) {
        const storedDirs = normalizeNames(storedMovie.director)
        const candDirs   = candidate.directors.map(d => d.toLowerCase().trim())
        const matched = storedDirs.filter(sd =>
            candDirs.some(cd => cd.includes(sd) || sd.includes(cd))
        )
        if (matched.length >= storedDirs.length && matched.length > 0) dirPts = 20
        else if (matched.length > 0) dirPts = 12
    }
    breakdown.director = { pts: dirPts, max: 20, stored: storedMovie.director, candidate: candidate.directors?.join(', ') }
    total += dirPts

    // ── 4. Actor overlap (15 pts) ──────────────────────────────────────────
    let actPts = 0
    if (!storedMovie.actors) {
        actPts = 7 // neutral
    } else if (candidate.actors?.length) {
        const storedActors = normalizeNames(storedMovie.actors)
        const candActors   = candidate.actors.map(a => a.toLowerCase().trim())
        const matched = storedActors.filter(sa =>
            candActors.some(ca => ca.includes(sa) || sa.includes(ca))
        )
        if (matched.length >= 2)     actPts = 15
        else if (matched.length >= 1) actPts = 8
    }
    breakdown.actors = { pts: actPts, max: 15, stored: storedMovie.actors, candidateCount: candidate.actors?.length }
    total += actPts

    // ── 5. Media type (10 pts) ─────────────────────────────────────────────
    const typePts = candidate.type === 'Movie' ? 10 : candidate.type === 'TVSeries' ? 0 : 5
    breakdown.type = { pts: typePts, max: 10, candidateType: candidate.type }
    total += typePts

    // ── Verdict ────────────────────────────────────────────────────────────
    let verdict
    if (total >= 85) {
        verdict = storedMovie.imdb_id === candidate.imdbId ? 'confirmed-match' : 'auto-fix'
    } else if (total >= 50) {
        verdict = 'review'
    } else {
        verdict = 'low-confidence'
    }

    return { confidence: total, breakdown, verdict }
}

export function pickBestCandidate(storedMovie, candidates) {
    if (!candidates.length) return null
    const scored = candidates.map(c => ({
        ...c,
        score: scoreCandidate(storedMovie, c)
    }))
    scored.sort((a, b) => b.score.confidence - a.score.confidence)
    return scored[0]
}
