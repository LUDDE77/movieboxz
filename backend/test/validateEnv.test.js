import { describe, it, expect } from 'vitest'
import { validateEnv, REQUIRED_ENV_VARS } from '../src/utils/validateEnv.js'

function completeEnv() {
    return {
        ADMIN_API_KEY: 'admin-key',
        YOUTUBE_API_KEY: 'yt-key',
        TMDB_API_KEY: 'tmdb-key',
        OMDB_API_KEY: 'omdb-key',
        SUPABASE_URL: 'https://example.supabase.co',
        SUPABASE_SERVICE_KEY: 'service-key',
        SUPABASE_ANON_KEY: 'anon-key'
    }
}

describe('validateEnv', () => {
    it('returns an empty array when all required vars are present', () => {
        expect(validateEnv(completeEnv())).toEqual([])
    })

    it('reports every required var as missing for an empty env', () => {
        expect(validateEnv({})).toEqual(REQUIRED_ENV_VARS)
    })

    it('reports a single missing var', () => {
        const env = completeEnv()
        delete env.ADMIN_API_KEY

        expect(validateEnv(env)).toEqual(['ADMIN_API_KEY'])
    })

    it('treats empty and whitespace-only values as missing', () => {
        const env = completeEnv()
        env.YOUTUBE_API_KEY = ''
        env.SUPABASE_SERVICE_KEY = '   '

        expect(validateEnv(env)).toEqual(['YOUTUBE_API_KEY', 'SUPABASE_SERVICE_KEY'])
    })

    it('validates the exact set of required variables', () => {
        expect(REQUIRED_ENV_VARS).toEqual([
            'ADMIN_API_KEY',
            'YOUTUBE_API_KEY',
            'TMDB_API_KEY',
            'OMDB_API_KEY',
            'SUPABASE_URL',
            'SUPABASE_SERVICE_KEY',
            'SUPABASE_ANON_KEY'
        ])
    })
})
