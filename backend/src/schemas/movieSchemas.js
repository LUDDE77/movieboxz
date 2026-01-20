import Joi from 'joi'

// Schema for movie query parameters
export const movieQuerySchema = Joi.object({
    q: Joi.string().min(1).max(100).required().messages({
        'string.empty': 'Search query cannot be empty',
        'string.max': 'Search query cannot exceed 100 characters',
        'any.required': 'Search query is required'
    }),
    category: Joi.string().valid(
        'action', 'adventure', 'animation', 'comedy', 'crime',
        'documentary', 'drama', 'family', 'fantasy', 'history',
        'horror', 'music', 'mystery', 'romance', 'science_fiction',
        'thriller', 'war', 'western', 'classic'
    ),
    year: Joi.number().integer().min(1900).max(new Date().getFullYear()),
    page: Joi.number().integer().min(1).max(100).default(1),
    limit: Joi.number().integer().min(1).max(50).default(20)
})

// Schema for movie ID parameter
export const movieIdSchema = Joi.object({
    id: Joi.string().uuid().required().messages({
        'string.guid': 'Movie ID must be a valid UUID',
        'any.required': 'Movie ID is required'
    })
})

// Schema for creating a movie
export const createMovieSchema = Joi.object({
    youtube_video_id: Joi.string().min(11).max(11).required(),
    title: Joi.string().min(1).max(500).required(),
    description: Joi.string().max(5000).allow(''),
    channel_id: Joi.string().min(24).max(24).required(),
    category: Joi.string().valid(
        'action', 'adventure', 'animation', 'comedy', 'crime',
        'documentary', 'drama', 'family', 'fantasy', 'history',
        'horror', 'music', 'mystery', 'romance', 'science_fiction',
        'thriller', 'war', 'western', 'classic'
    ),
    runtime_minutes: Joi.number().integer().min(1).max(600),
    release_date: Joi.date(),
    featured: Joi.boolean().default(false),
    trending: Joi.boolean().default(false)
})
