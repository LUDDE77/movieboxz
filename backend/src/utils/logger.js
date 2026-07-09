import winston from 'winston'

// Create logger with different levels and formats
const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: winston.format.combine(
        winston.format.timestamp({
            format: 'YYYY-MM-DD HH:mm:ss'
        }),
        winston.format.errors({ stack: true }),
        winston.format.json()
    ),
    defaultMeta: {
        service: 'movieboxz-backend',
        version: '1.0.0'
    },
    transports: [
        // Write to console
        new winston.transports.Console({
            format: winston.format.combine(
                winston.format.colorize(),
                winston.format.simple()
            )
        })
    ]
})

// Console-only in all environments: Railway's filesystem is ephemeral, so file
// transports just consume disk until the next deploy. Railway captures stdout/stderr.

export { logger }