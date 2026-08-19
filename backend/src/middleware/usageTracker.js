import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'

// Privacy-safe, aggregate usage tracking. We NEVER store a user id, device id, IP,
// or anything identifying — only anonymous per-day (and per-hour) event counts,
// bucketed by platform (from User-Agent) and country (from the X-Country header).
// Counts are batched in memory and flushed every 60s.

const bufferDaily = new Map()  // "day|event|platform|country|ref" -> count
const bufferHourly = new Map() // "day|hour|event|country" -> count   (coarser, for time-of-day)
const SEP = String.fromCharCode(31) // unit separator — safe delimiter, never in the data
const MAX_BUFFER_KEYS = 5000
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function classify(req) {
    if (req.method !== 'GET') return null
    const p = req.path
    if (p === '/api/browse/home') return { event: 'app_open' }
    if (p === '/api/movies/search') {
        const q = String(req.query.q || req.query.query || req.query.search || '')
            .trim().toLowerCase().slice(0, 60)
        return { event: 'search', ref: q }
    }
    let m = p.match(/^\/api\/movies\/([^/]+)$/)
    if (m && UUID.test(m[1])) return { event: 'movie_view', ref: m[1] }
    m = p.match(/^\/api\/series\/([^/]+)(?:\/episodes)?$/)
    if (m && UUID.test(m[1])) return { event: 'series_view', ref: m[1] }
    return null
}

function platformOf(ua = '') {
    if (/apple ?tv|tvos/i.test(ua)) return 'tvos'
    if (/iphone|ipad|ios/i.test(ua)) return 'ios'
    return 'app'
}

export function usageTracker(req, res, next) {
    // Never count admin-tool or internal traffic: the consumer apps never send an
    // admin key, so any request carrying one is the macOS Admin app (or a maintenance
    // script) and must be excluded from consumer usage analytics.
    if (req.headers['x-admin-api-key']) return next()
    try {
        const c = classify(req)
        if (c && bufferDaily.size < MAX_BUFFER_KEYS + 200) {
            const now = new Date()
            const day = now.toISOString().slice(0, 10)
            const hour = now.getUTCHours()
            const platform = platformOf(req.get('User-Agent') || '')
            const cc = String(req.headers['x-country'] || '').trim().toUpperCase()
            const country = /^[A-Z]{2}$/.test(cc) ? cc : ''
            const dKey = [day, c.event, platform, country, c.ref || ''].join(SEP)
            bufferDaily.set(dKey, (bufferDaily.get(dKey) || 0) + 1)
            const hKey = [day, hour, c.event, country].join(SEP)
            bufferHourly.set(hKey, (bufferHourly.get(hKey) || 0) + 1)
        }
    } catch { /* never break a request over analytics */ }
    next()
}

// Flush one buffer through its RPC. Each row is independent: a row that errors is
// SKIPPED (logged and dropped) so one bad row can never stall the whole pipeline.
// Losing a single row's count is acceptable; a multi-day stall is not.
async function flushBuffer(buf, rpcName, argsFor) {
    if (buf.size === 0) return
    const entries = [...buf.entries()]
    buf.clear()
    let skipped = 0
    for (const [key, delta] of entries) {
        try {
            const { error } = await supabase.rpc(rpcName, argsFor(key, delta))
            if (error) { skipped++; continue }
        } catch (e) {
            skipped++
        }
    }
    if (skipped) logger.warn(`${rpcName}: skipped ${skipped}/${entries.length} bad rows this flush`)
}

let flushing = false
export async function flushUsage() {
    if (flushing) return
    flushing = true
    try {
        await flushBuffer(bufferDaily, 'increment_usage_daily', (key, delta) => {
            const [day, event, platform, country, ref] = key.split(SEP)
            return { p_day: day, p_event: event, p_platform: platform, p_country: country, p_ref_id: ref, p_delta: delta }
        })
        await flushBuffer(bufferHourly, 'increment_usage_hourly', (key, delta) => {
            const [day, hour, event, country] = key.split(SEP)
            return { p_day: day, p_hour: parseInt(hour, 10), p_event: event, p_country: country, p_delta: delta }
        })
    } catch (e) {
        logger.warn(`usage flush exception: ${e.message}`)
    } finally {
        flushing = false
    }
}

export function startUsageFlusher(intervalMs = 60000) {
    const t = setInterval(() => { flushUsage().catch(() => {}) }, intervalMs)
    if (t.unref) t.unref()
    return t
}
