import Foundation

extension DateFormatter {
    static let movieDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

@MainActor
class MovieService: ObservableObject {
    @Published var isConnected = false

    private let baseURL: String
    private let session: URLSession

    init() {
        // Configure for development/production
        self.baseURL = "https://movieboxz-backend-production.up.railway.app/api"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        checkConnection()
    }

    // MARK: - Connection Management

    func checkConnection() {
        Task {
            do {
                _ = try await performRequest(endpoint: "/health", type: HealthResponse.self)
                self.isConnected = true
            } catch {
                self.isConnected = false
                print("Backend connection failed: \(error)")
            }
        }
    }

    // MARK: - Generic Request Method

    private func performRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        type: T.Type
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw MovieServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = body
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MovieServiceError.invalidResponse
            }

            guard 200...299 ~= httpResponse.statusCode else {
                throw MovieServiceError.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)

        } catch {
            if error is MovieServiceError {
                throw error
            } else {
                throw MovieServiceError.networkError(error)
            }
        }
    }

    // MARK: - Movie API Methods

    func fetchFeaturedMovies() async throws -> [Movie] {
        let response = try await performRequest(
            endpoint: "/movies/featured",
            type: MoviesResponse.self
        )
        return response.data.movies
    }

    func fetchTrendingMovies(page: Int = 1, limit: Int = 20) async throws -> [Movie] {
        let response = try await performRequest(
            endpoint: "/movies/trending?page=\(page)&limit=\(limit)",
            type: MoviesResponse.self
        )
        return response.data.movies
    }

    func fetchPopularMovies(page: Int = 1, limit: Int = 20) async throws -> [Movie] {
        let response = try await performRequest(
            endpoint: "/movies/popular?page=\(page)&limit=\(limit)",
            type: MoviesResponse.self
        )
        return response.data.movies
    }

    func fetchRecentMovies(page: Int = 1, limit: Int = 20) async throws -> [Movie] {
        let response = try await performRequest(
            endpoint: "/movies/recent?page=\(page)&limit=\(limit)",
            type: MoviesResponse.self
        )
        return response.data.movies
    }

    func searchMovies(
        query: String,
        category: String? = nil,
        year: Int? = nil,
        page: Int = 1,
        limit: Int = 20
    ) async throws -> [Movie] {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let category = category {
            components.queryItems?.append(URLQueryItem(name: "category", value: category))
        }

        if let year = year {
            components.queryItems?.append(URLQueryItem(name: "year", value: String(year)))
        }

        let queryString = components.percentEncodedQuery ?? ""
        let response = try await performRequest(
            endpoint: "/movies/search?\(queryString)",
            type: MoviesResponse.self
        )
        return response.data.movies
    }

    func fetchMoviesByCategory(
        category: String,
        page: Int = 1,
        limit: Int = 20
    ) async throws -> [Movie] {
        let response = try await performRequest(
            endpoint: "/movies/category/\(category)?page=\(page)&limit=\(limit)",
            type: MoviesResponse.self
        )
        return response.data.movies
    }

    func fetchMovieDetails(id: String) async throws -> Movie {
        let response = try await performRequest(
            endpoint: "/movies/\(id)",
            type: MovieDetailResponse.self
        )
        return response.data
    }

    func checkMovieAvailability(id: String) async throws -> MovieAvailability {
        let response = try await performRequest(
            endpoint: "/movies/\(id)/availability",
            type: AvailabilityResponse.self
        )
        return response.data
    }
}

// MARK: - HTTP Method Enum

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
}

// MARK: - Error Types

enum MovieServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Data parsing error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Response Types

struct HealthResponse: Codable {
    let status: String
    let timestamp: String
    let version: String
}

struct MovieDetailResponse: Codable {
    let success: Bool
    let data: Movie
    let message: String?
}

struct AvailabilityResponse: Codable {
    let success: Bool
    let data: MovieAvailability
    let message: String?
}

struct MovieAvailability: Codable {
    let movieId: String
    let youtubeVideoId: String
    let available: Bool
    let embeddable: Bool
    let error: String?
    let checkedAt: String
    let playbackOptions: PlaybackOptions?

    enum CodingKeys: String, CodingKey {
        case movieId = "movieId"
        case youtubeVideoId = "youtubeVideoId"
        case available
        case embeddable
        case error
        case checkedAt = "checkedAt"
        case playbackOptions = "playbackOptions"
    }
}

struct PlaybackOptions: Codable {
    let youtubeApp: String
    let youtubeWeb: String
    let embed: Bool

    enum CodingKeys: String, CodingKey {
        case youtubeApp = "youtubeApp"
        case youtubeWeb = "youtubeWeb"
        case embed
    }
}
