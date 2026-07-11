import Foundation

// MARK: - Errors

enum MovieServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let code): return "Server error: \(code)"
        case .networkError: return "Network connection error"
        case .decodingError: return "Failed to parse response"
        }
    }
}

// MARK: - MovieService

@MainActor
class MovieService: ObservableObject {
    static let baseURL = "https://movieboxz-backend-production.up.railway.app/api"

    @Published var isConnected = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: str) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: str) { return date }
            let simple = DateFormatter()
            simple.dateFormat = "yyyy-MM-dd"
            if let date = simple.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date: \(str)")
        }
        return d
    }()

    init() {
        Task { await checkConnection() }
    }

    // MARK: - Generic Request

    private func fetch<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: Self.baseURL + path) else { throw MovieServiceError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw MovieServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw MovieServiceError.httpError(http.statusCode) }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding error for \(path): \(error)")
            throw MovieServiceError.decodingError
        }
    }

    // MARK: - Health

    func checkConnection() async {
        do {
            let _: HealthResponse = try await fetch("/health")
            isConnected = true
        } catch {
            isConnected = false
        }
    }

    // MARK: - Movies  (routes: /api/movies/*)

    func fetchFeaturedMovies() async throws -> [Movie] {
        let r: MoviesResponse = try await fetch("/movies/featured")
        return r.data?.movies ?? []
    }

    func fetchTrendingMovies(page: Int = 1, limit: Int = 20) async throws -> [Movie] {
        let r: MoviesResponse = try await fetch("/movies/trending?page=\(page)&limit=\(limit)")
        return r.data?.movies ?? []
    }

    func fetchPopularMovies(page: Int = 1, limit: Int = 20) async throws -> [Movie] {
        let r: MoviesResponse = try await fetch("/movies/popular?page=\(page)&limit=\(limit)")
        return r.data?.movies ?? []
    }

    func fetchRecentMovies(page: Int = 1, limit: Int = 20) async throws -> [Movie] {
        let r: MoviesResponse = try await fetch("/movies/recent?page=\(page)&limit=\(limit)")
        return r.data?.movies ?? []
    }

    func fetchAllMovies(sort: String = "popularity", page: Int = 1, limit: Int = 50) async throws -> [Movie] {
        let r: MoviesResponse = try await fetch("/movies?sort=\(sort)&page=\(page)&limit=\(limit)")
        return r.data?.movies ?? []
    }

    func searchMovies(query: String, page: Int = 1, limit: Int = 50) async throws -> [Movie] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let r: MoviesResponse = try await fetch("/movies/search?q=\(encoded)&page=\(page)&limit=\(limit)")
        return r.data?.movies ?? []
    }

    // MARK: - Genres  (routes: /api/browse/genres/*)

    func fetchAllGenres() async throws -> [Genre] {
        let r: GenresResponse = try await fetch("/browse/genres")
        return r.data?.genres ?? []
    }

    // Backend route is /browse/genres/:id (returns { genre, movies, pagination })
    func fetchMoviesByGenre(genreId: Int, page: Int = 1, limit: Int = 20) async throws -> [Movie] {
        let r: GenreMoviesResponse = try await fetch("/browse/genres/\(genreId)?page=\(page)&limit=\(limit)")
        return r.data?.movies ?? []
    }

    func fetchUncategorizedMovies(page: Int = 1, limit: Int = 20) async throws -> [Movie] {
        // Fall back to all movies; the uncategorized filter endpoint is not confirmed live
        let r: MoviesResponse = try await fetch("/movies?page=\(page)&limit=\(limit)")
        return (r.data?.movies ?? []).filter { $0.genres?.isEmpty ?? true }
    }

    func fetchTVSeries(page: Int = 1, limit: Int = 200) async throws -> [Movie] {
        let r: MoviesResponse = try await fetch("/movies?is_tv_series=true&sort=recent&page=\(page)&limit=\(limit)")
        return r.data?.movies ?? []
    }

    func fetchKidsContent(page: Int = 1, limit: Int = 200) async throws -> [Movie] {
        let r: MoviesResponse = try await fetch("/movies?is_kids_content=true&sort=popular&page=\(page)&limit=\(limit)")
        return r.data?.movies ?? []
    }
}

// MARK: - HealthResponse

struct HealthResponse: Decodable {
    let status: String?
}
