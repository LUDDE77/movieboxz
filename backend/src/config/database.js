import { createClient } from '@supabase/supabase-js'
import { logger } from '../utils/logger.js'

const supabaseUrl = process.env.SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_KEY
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error('Missing required Supabase environment variables')
}

// Service role client for admin operations
export const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    }
})

// Anon client for user operations
export const supabase = createClient(supabaseUrl, supabaseAnonKey)

// Test database connection
export const testDatabaseConnection = async () => {
    try {
        const { data, error } = await supabaseAdmin
            .from('movies')
            .select('count')
            .limit(1)

        if (error && error.code !== 'PGRST116') {
            logger.error('Database connection test failed:', error)
            return false
        }

        logger.info('Database connection test successful')
        return true
    } catch (error) {
        logger.error('Database connection test error:', error)
        return false
    }
}