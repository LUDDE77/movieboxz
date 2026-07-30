import { supabase } from '../config/database.js'
import { logger } from '../utils/logger.js'

// Privacy-safe, aggregate usage tracking. We NEVER store a user id, device id, IP,
// or anything identifying — only anonymous per-day event counts, optionally bucketed
// by platform (from User-Agent) and country (from the X-Country header the app
// already sends). Counts are batched in memory and flushed to usage_daily every 60s.

const buffer = new Map() // "day|event|platform|country|ref" -> count
const SEP = ''
const MAX_BUFFER_KEYS = 5000 // safety cap if the table doesn't exist yet
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
    try {
        const c = classify(req)
        if (c && buffer.size < MAX_BUFFER_KEYS + 200) {
            const day = new Date().toISOString().slice(0, 10)
            const platform = platformOf(req.get('User-Agent') || '')
            const cc = String(req.headers['x-country'] || '').trim().toUpperCase()
            const country = /^[A-Z]{2}$/.test(cc) ? cc : ''
            const key = [day, c.event, platform, country, c.ref || ''].join(SEP)
            buffer.set(key, (buffer.get(key) || 0) + 1)
        }
    } catch { /* never break a request over analytics */ }
    next()
}

let flushing = false
export async function flushUsage() {
    if (flushing || buffer.size === 0) return
    flushing = true
    const entries = [...buffer.entries()]
    buffer.clear()
    try {
        for (let i = 0; i < entries.length; i++) {
            const [key, delta] = entries[i]
            const [day, event, platform, country, ref] = key.split(SEP)
            const { error } = await supabase.rpc('increment_usage_daily', {
                p_day: day, p_event: event, p_platform: platform,
                p_country: country, p_ref_id: ref, p_delta: delta
            })
            if (error) {
                // Table/RPC not present yet (or transient) — re-buffer the rest and
                // retry next tick, but respect the safety cap to bound memory.
                if (buffer.size < MAX_BUFFER_KEYS) {
                    for (let j = i; j < entries.length; j++) {
                        const [k, d] = entries[j]
                        buffer.set(k, (buffer.get(k) || 0) + d)
                    }
                }
                logger.warn(`usage flush deferred: ${error.message}`)
                break
            }
        }
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
