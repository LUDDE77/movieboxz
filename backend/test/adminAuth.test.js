import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import express from 'express'
import request from 'supertest'
import { adminAuth, resetAdminAuthThrottle } from '../src/middleware/adminAuth.js'

const TEST_KEY = 'test-admin-key-12345'

function buildApp() {
    const app = express()
    app.get('/api/admin/protected', adminAuth, (req, res) => {
        res.json({ success: true })
    })
    return app
}

describe('adminAuth middleware', () => {
    let app
    let previousKey

    beforeEach(() => {
        previousKey = process.env.ADMIN_API_KEY
        process.env.ADMIN_API_KEY = TEST_KEY
        resetAdminAuthThrottle()
        app = buildApp()
    })

    afterEach(() => {
        process.env.ADMIN_API_KEY = previousKey
        resetAdminAuthThrottle()
    })

    it('returns 401 when no key is provided', async () => {
        const res = await request(app).get('/api/admin/protected')

        expect(res.status).toBe(401)
        expect(res.body.success).toBe(false)
        expect(res.body.error).toBe('Unauthorized')
    })

    it('returns 401 when a wrong key is provided', async () => {
        const res = await request(app)
            .get('/api/admin/protected')
            .set('x-admin-api-key', 'wrong-key')

        expect(res.status).toBe(401)
        expect(res.body.success).toBe(false)
    })

    it('returns 401 when the wrong key has a different length (timing-safe compare must not throw)', async () => {
        const res = await request(app)
            .get('/api/admin/protected')
            .set('x-admin-api-key', 'x')

        expect(res.status).toBe(401)
    })

    it('passes through with the correct key', async () => {
        const res = await request(app)
            .get('/api/admin/protected')
            .set('x-admin-api-key', TEST_KEY)

        expect(res.status).toBe(200)
        expect(res.body.success).toBe(true)
    })

    it('returns 401 when ADMIN_API_KEY is not configured, even for an empty key', async () => {
        delete process.env.ADMIN_API_KEY

        const res = await request(app)
            .get('/api/admin/protected')
            .set('x-admin-api-key', '')

        expect(res.status).toBe(401)
    })

    it('throttles with 429 after 10 failed attempts from the same IP', async () => {
        for (let i = 0; i < 10; i++) {
            const res = await request(app)
                .get('/api/admin/protected')
                .set('x-admin-api-key', 'wrong-key')
            expect(res.status).toBe(401)
        }

        // 11th attempt is throttled — even with the CORRECT key
        const throttled = await request(app)
            .get('/api/admin/protected')
            .set('x-admin-api-key', TEST_KEY)

        expect(throttled.status).toBe(429)
        expect(throttled.body.error).toBe('Too many failed authentication attempts')
    })

    it('allows requests again after the throttle state is cleared', async () => {
        for (let i = 0; i < 10; i++) {
            await request(app)
                .get('/api/admin/protected')
                .set('x-admin-api-key', 'wrong-key')
        }

        resetAdminAuthThrottle()

        const res = await request(app)
            .get('/api/admin/protected')
            .set('x-admin-api-key', TEST_KEY)

        expect(res.status).toBe(200)
    })
})
