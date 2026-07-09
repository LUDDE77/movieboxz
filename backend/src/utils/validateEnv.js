/**
 * Startup environment validation.
 *
 * Returns the list of required environment variables that are missing or blank,
 * so the server can fail fast with a clear error instead of crashing later with
 * confusing runtime errors (401s, Supabase client failures, etc.).
 */
export const REQUIRED_ENV_VARS = [
    'ADMIN_API_KEY',
    'YOUTUBE_API_KEY',
    'TMDB_API_KEY',
    'OMDB_API_KEY',
    'SUPABASE_URL',
    'SUPABASE_SERVICE_KEY',
    'SUPABASE_ANON_KEY'
]

export function validateEnv(env = process.env) {
    return REQUIRED_ENV_VARS.filter(name => {
        const value = env[name]
        return value === undefined || value === null || String(value).trim() === ''
    })
}

export default validateEnv
