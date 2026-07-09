import { logger } from '../utils/logger.js'
import { validateEnv } from '../utils/validateEnv.js'

// Fail fast if required environment variables are missing.
// This module is imported for its side effect immediately after 'dotenv/config'
// in server.js, so it runs BEFORE config/database.js and the service
// constructors read process.env at import time.
const missingEnvVars = validateEnv(process.env)

if (missingEnvVars.length > 0) {
    logger.error(`Missing required environment variables: ${missingEnvVars.join(', ')}. Set them in .env (local) or the Railway service variables, then restart.`)
    process.exit(1)
}
