import { describe, it, expect } from 'vitest'
import { validateRequest } from '../src/middleware/validation.js'
import { movieIdSchema, movieQuerySchema } from '../src/schemas/movieSchemas.js'

function run(middleware, req) {
    let nextArg = 'not-called'
    middleware(req, {}, (arg) => { nextArg = arg })
    return nextArg
}

describe('validateRequest', () => {
    // Regression: GET /movies/:id used to validate req.query instead of req.params,
    // so every movie-by-id request failed with "Movie ID is required".
    it('validates route params on GET when params are present', () => {
        const req = {
            method: 'GET',
            params: { id: '3649fde0-73bf-4764-97b7-78d9048a4607' },
            query: {}
        }

        expect(run(validateRequest(movieIdSchema), req)).toBeUndefined()
        expect(req.params.id).toBe('3649fde0-73bf-4764-97b7-78d9048a4607')
    })

    it('rejects a non-UUID id param', () => {
        const req = { method: 'GET', params: { id: 'not-a-uuid' }, query: {} }

        const err = run(validateRequest(movieIdSchema), req)
        expect(err).toBeInstanceOf(Error)
        expect(err.name).toBe('ValidationError')
    })

    it('still validates the query string on GET routes without params', () => {
        const req = { method: 'GET', params: {}, query: { q: 'nosferatu' } }

        expect(run(validateRequest(movieQuerySchema), req)).toBeUndefined()
        expect(req.query.q).toBe('nosferatu')
        expect(req.query.page).toBe(1) // Joi default applied
    })

    it('rejects a missing search query', () => {
        const req = { method: 'GET', params: {}, query: {} }

        const err = run(validateRequest(movieQuerySchema), req)
        expect(err).toBeInstanceOf(Error)
        expect(err.name).toBe('ValidationError')
    })
})
