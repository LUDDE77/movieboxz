import crypto from 'crypto'
import { logger } from '../utils/logger.js'

// In-memory failed-attempt throttling per IP.
// After MAX_FAILURES failed attempts within WINDOW_MS, reject with 429 without comparing keys.
const FAILURE_WINDOW_MS = 15 * 60 * 1000 // 15 minutes
const MAX_FAILURES = 10

const failedAttempts = new Map() // ip -> array of failure timestamps (ms)

function recentFailures(ip, now) {
    const timestamps = (failedAttempts.get(ip) || []).filter(t => now - t < FAILURE_WINDOW_MS)
    if (timestamps.length > 0) {
        failedAttempts.set(ip, timestamps)
    } else {
        failedAttempts.delete(ip)
    }
    return timestamps
}

function recordFailure(ip, now) {
    const timestamps = recentFailures(ip, now)
    timestamps.push(now)
    failedAttempts.set(ip, timestamps)
}

/** Test helper: clear throttling state. */
export function resetAdminAuthThrottle() {
    failedAttempts.clear()
}

/**
 * Constant-time key comparison. Both sides are hashed with SHA-256 first so the
 * buffers always have equal length (timingSafeEqual throws on length mismatch,
 * which would itself leak length information).
 */
function safeCompare(provided, expected) {
    const providedHash = crypto.createHash('sha256').update(String(provided)).digest()
    const expectedHash = crypto.createHash('sha256').update(String(expected)).digest()
    return crypto.timingSafeEqual(providedHash, expectedHash)
}

/**
 * Admin API key authentication middleware.
 * Validates the x-admin-api-key header against ADMIN_API_KEY env variable.
 */
export const adminAuth = (req, res, next) => {
    const now = Date.now()
    const ip = req.ip || req.socket?.remoteAddress || 'unknown'

    // Throttle brute-force attempts before doing any comparison
    if (recentFailures(ip, now).length >= MAX_FAILURES) {
        logger.warn(`Admin auth throttled for IP ${ip} (too many failed attempts)`)
        return res.status(429).json({
            success: false,
            error: 'Too many failed authentication attempts',
            message: 'Try again later'
        })
    }

    const apiKey = req.headers['x-admin-api-key']
    const expectedKey = process.env.ADMIN_API_KEY

    if (!apiKey || !expectedKey || !safeCompare(apiKey, expectedKey)) {
        recordFailure(ip, now)
        return res.status(401).json({
            success: false,
            error: 'Unauthorized',
            message: 'Valid admin API key required'
        })
    }

    next()
}

export default adminAuth
