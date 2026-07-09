export const validateRequest = (schema) => {
    return (req, res, next) => {
        // Route params take precedence (e.g. /movies/:id on GET), then query, then body
        const dataToValidate = req.params && Object.keys(req.params).length > 0 ? req.params :
                              req.method === 'GET' ? req.query : req.body

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
        if (req.params && Object.keys(req.params).length > 0) {
            req.params = value
        } else if (req.method === 'GET') {
            req.query = value
        } else {
            req.body = value
        }

        next()
    }
}
