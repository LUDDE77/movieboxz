// CORS configuration for MovieBoxZ backend
export const corsConfig = {
    origin: function (origin, callback) {
        // Allow requests with no origin (mobile apps, Postman, etc.)
        if (!origin) return callback(null, true)

        // List of allowed origins
        const allowedOrigins = [
            'http://localhost:3000',
            'http://127.0.0.1:3000',
            'http://localhost:3001',
            'http://127.0.0.1:3001'
        ]

        // Add production origins from environment
        if (process.env.CORS_ORIGIN) {
            const envOrigins = process.env.CORS_ORIGIN.split(',')
            allowedOrigins.push(...envOrigins)
        }

        // Check if origin is allowed
        if (allowedOrigins.indexOf(origin) !== -1) {
            callback(null, true)
        } else {
            callback(new Error('Not allowed by CORS policy'))
        }
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: [
        'Content-Type',
        'Authorization',
        'X-Requested-With',
        'X-Admin-API-Key'
    ],
    credentials: true,
    optionsSuccessStatus: 200 // Some legacy browsers choke on 204
}