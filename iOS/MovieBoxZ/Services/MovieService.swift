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

    // MARK: - Shared Browse Data Cache
    // Populated once by loadBrowseData() and reused across tab switches so
    // MainBrowseView doesn't refetch/re-skeleton every time it reappears.
    @Published private(set) var featuredMovies: [Movie] = []
    @Published private(set) var trendingMovies: [Movie] = []
    @Published private(set) var popularMovies: [Movie] = []
    @Published private(set) var recentMovies: [Movie] = []
    @Published private(set) var genreCategories: [(genre: Genre, movies: [Movie])] = []
    @Published private(set) var uncategorizedMovies: [Movie] = []
    @Published private(set) var allBrowseMovies: [Movie] = []
    @Published private(set) var hasLoadedBrowseData = false

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

    // MARK: - Browse Data Loading (shared cache)

    /// Loads all data needed for the Browse tab (featured, trending, popular,
    /// recent, genre carousels, uncategorized, all movies) and caches it on
    /// this shared instance. Callers should check `hasLoadedBrowseData` first
    /// and only call this when data is missing, or pass `force: true` for a
    /// manual pull-to-refresh.
    func loadBrowseData(force: Bool = false) async throws {
        if hasLoadedBrowseData && !force { return }

        // Featured / popular / recent movies in parallel
        async let featuredResult = fetchFeaturedMovies()
        async let popularResult = fetchPopularMovies(page: 1, limit: 10)
        async let recentResult = fetchRecentMovies(page: 1, limit: 50)

        let (fetchedFeatured, fetchedPopular, recentBatch) = try await (featuredResult, popularResult, recentResult)

        // Fetch all genres from backend
        let genres = try await fetchAllGenres()
        let genresWithMovies = genres.filter { ($0.movieCount ?? 0) > 0 }

        // Fetch genre movies, allMovies, and uncategorized in parallel
        async let allMoviesResult = fetchAllMovies(sort: "popularity", limit: 50)
        async let uncategorizedResult = fetchUncategorizedMovies(limit: 10)

        var genreResults: [(genre: Genre, movies: [Movie])] = []
        await withTaskGroup(of: (Genre, [Movie]).self) { group in
            for genre in genresWithMovies {
                group.addTask {
                    let movies = (try? await self.fetchMoviesByGenre(genreId: genre.id, limit: 10)) ?? []
                    return (genre, movies)
                }
            }
            for await (genre, movies) in group {
                genreResults.append((genre: genre, movies: movies))
            }
        }
        genreResults.sort { $0.genre.name < $1.genre.name }

        let (allMoviesData, uncategorizedData) = try await (allMoviesResult, uncategorizedResult)

        self.featuredMovies = fetchedFeatured.isEmpty ? Array(recentBatch.prefix(3)) : fetchedFeatured
        self.popularMovies = fetchedPopular
        self.trendingMovies = recentBatch.filter { $0.trending }
        self.recentMovies = recentBatch
        self.genreCategories = genreResults
        self.allBrowseMovies = allMoviesData
        self.uncategorizedMovies = uncategorizedData
        self.hasLoadedBrowseData = true
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
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                // Try ISO8601 with fractional seconds first (e.g., "2026-01-19T16:02:17.722648+00:00")
                let iso8601Formatter = ISO8601DateFormatter()
                iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso8601Formatter.date(from: dateString) {
                    return date
                }

                // Fall back to standard ISO8601 (e.g., "2026-01-19T16:02:17+00:00")
                iso8601Formatter.formatOptions = [.withInternetDateTime]
                if let date = iso8601Formatter.date(from: dateString) {
                    return date
                }

                // Try simple date format (e.g., "1968-10-01")
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
            }
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

    func fetchTopImdbMovies(page: Int = 1, limit: Int = 20) async throws -> [Movie] {
        let response = try await performRequest(
            endpoint: "/movies/top-rated?source=imdb&page=\(page)&limit=\(limit)",
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

    // MARK: - Genre API Methods (Phase 2)

    func fetchAllGenres() async throws -> [Genre] {
        let response = try await performRequest(
            endpoint: "/browse/genres",
            type: GenresResponse.self
        )
        return response.data.genres
    }

    func fetchMoviesByGenre(
        genreId: Int,
        page: Int = 1,
        limit: Int = 20
    ) async throws -> [Movie] {
        let response = try await performRequest(
            endpoint: "/browse/genres/\(genreId)?page=\(page)&limit=\(limit)",
            type: GenreMoviesResponse.self
        )
        return response.data.movies
    }

    func fetchUncategorizedMovies(
        page: Int = 1,
        limit: Int = 20
    ) async throws -> [Movie] {
        let response = try await performRequest(
            endpoint: "/browse/uncategorized?page=\(page)&limit=\(limit)",
            type: MoviesResponse.self
        )
        return response.data.movies
    }

    // Convenience method for fetching all movies with filters
    func fetchAllMovies(
        genre: Int? = nil,
        channel: String? = nil,
        search: String? = nil,
        sort: String = "popular",
        page: Int = 1,
        limit: Int = 20
    ) async throws -> [Movie] {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort", value: sort)
        ]

        if let genre = genre {
            components.queryItems?.append(URLQueryItem(name: "genre", value: String(genre)))
        }

        if let channel = channel {
            components.queryItems?.append(URLQueryItem(name: "channel", value: channel))
        }

        if let search = search {
            components.queryItems?.append(URLQueryItem(name: "search", value: search))
        }

        let queryString = components.percentEncodedQuery ?? ""
        let response = try await performRequest(
            endpoint: "/movies?\(queryString)",
            type: MoviesResponse.self
        )
        return response.data.movies
    }

    func fetchTVSeries(page: Int = 1, limit: Int = 200) async throws -> [Movie] {
        let response = try await performRequest(
            endpoint: "/movies?is_tv_series=true&sort=recent&page=\(page)&limit=\(limit)",
            type: MoviesResponse.self
        )
        return response.data.movies
    }

    func fetchKidsContent(page: Int = 1, limit: Int = 200) async throws -> [Movie] {
        let response = try await performRequest(
            endpoint: "/movies?is_kids_content=true&sort=popular&page=\(page)&limit=\(limit)",
            type: MoviesResponse.self
        )
        return response.data.movies
    }

    func fetchSeriesList(page: Int = 1, limit: Int = 100, kidsOnly: Bool = false) async throws -> [TVSeries] {
        struct Inner: Codable { let series: [TVSeries] }
        struct Response: Codable { let success: Bool; let data: Inner }
        let kidsParam = kidsOnly ? "&kids=true" : ""
        let response = try await performRequest(
            endpoint: "/series?page=\(page)&limit=\(limit)\(kidsParam)",
            type: Response.self
        )
        return response.data.series
    }

    /// Load every TV series across all pages (the catalog has more series than one page).
    func fetchAllSeries(kidsOnly: Bool = false) async throws -> [TVSeries] {
        var all: [TVSeries] = []
        var page = 1
        while page <= 20 {
            let batch = try await fetchSeriesList(page: page, limit: 100, kidsOnly: kidsOnly)
            all.append(contentsOf: batch)
            if batch.count < 100 { break }
            page += 1
        }
        return all
    }

    func fetchSeriesEpisodes(seriesId: String) async throws -> SeriesDetailResponse {
        struct Response: Codable { let success: Bool; let data: SeriesDetailResponse }
        let response = try await performRequest(
            endpoint: "/series/\(seriesId)/episodes",
            type: Response.self
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

