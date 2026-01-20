export const validateRequest = (schema) => {
    return (req, res, next) => {
        // Validate query parameters, body, or params based on request
        const dataToValidate = req.method === 'GET' ? req.query :
                              req.params.id ? req.params : req.body

        const { error, value } = schema.validate(dataToValidate, {
            allowUnknown: false,
            stripUnknown: true
        })

        if (error) {
            const validationError = new Error(error.details[0].message)
            validationError.name = 'ValidationError'
            validationError.details = error.details.map(detail => ({
                field: detail.path.join('.'),
                message: detail.message,
                value: detail.context?.value
            }))

            return next(validationError)
        }

        // Replace original data with validated data
        if (req.method === 'GET') {
            req.query = value
        } else if (req.params.id) {
            req.params = value
        } else {
            req.body = value
        }

        next()
    }
}
