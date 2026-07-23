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
    @Published private(set) var topImdbMovies: [Movie] = []
    @Published private(set) var decade2000s: [Movie] = []    // "Modern Cinema"
    @Published private(set) var decade8090: [Movie] = []     // "The 80s & 90s"
    @Published private(set) var decade6070: [Movie] = []     // "The 60s & 70s"
    @Published private(set) var decadeClassic: [Movie] = []  // "Classic Cinema"
    @Published private(set) var hasLoadedBrowseData = false

    private let baseURL: String
    private let session: URLSession

    // MARK: - Region Override
    // UserDefaults key holding an optional 2-letter ISO-3166-1 alpha-2 country
    // code. Empty/absent means "Auto" (use the device locale). On-device only —
    // no permission, no tracking, ephemeral.
    private static let regionOverrideKey = "regionOverride"

    /// The raw stored override code, or nil if set to Auto. For the Settings UI.
    var regionOverrideCode: String? {
        let stored = UserDefaults.standard.string(forKey: Self.regionOverrideKey)
        guard let stored, stored.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil else {
            return nil
        }
        return stored
    }

    /// The country to send in the `X-Country` header: the validated override if
    /// present, otherwise the device locale region.
    var effectiveRegion: String? {
        if let override = regionOverrideCode {
            return override
        }
        return Locale.current.region?.identifier
    }

    /// Persists (or clears) the region override and invalidates the shared
    /// browse cache so the catalog reloads for the new country the next time
    /// MainBrowseView appears.
    func setRegionOverride(_ code: String?) {
        if let code, code.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil {
            UserDefaults.standard.set(code, forKey: Self.regionOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.regionOverrideKey)
        }

        // Invalidate the shared browse cache so the next load refetches with
        // the new country header.
        hasLoadedBrowseData = false
        featuredMovies = []
        trendingMovies = []
        popularMovies = []
        recentMovies = []
        genreCategories = []
        uncategorizedMovies = []
        allBrowseMovies = []
    }

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

        // One request for the entire Browse tab (featured, popular, trending,
        // recent, all, uncategorized, High Score IMDb, every genre carousel and
        // the decade rails) instead of ~20 — much friendlier to the rate limit.
        var endpoint = "/browse/home"
        #if DEBUG
        // Screenshot automation: show only curated public-domain films so App Store
        // captures never display copyrighted posters/stars (Apple 4.1(a)).
        if CommandLine.arguments.contains("UI_SCREENSHOT_DEMO") { endpoint += "?demo=pd" }
        #endif
        let response = try await performRequest(endpoint: endpoint, type: BrowseHomeResponse.self)
        let d = response.data

        self.featuredMovies = d.featured.isEmpty ? Array(d.recent.prefix(3)) : d.featured
        self.popularMovies = d.popular
        self.trendingMovies = d.trending
        self.recentMovies = d.recent
        self.genreCategories = d.genres
            .map { (genre: $0.genre, movies: $0.movies) }
            .sorted { $0.genre.name < $1.genre.name }
        self.allBrowseMovies = d.allMovies
        self.uncategorizedMovies = d.uncategorized
        self.topImdbMovies = d.topImdb
        self.decade2000s = d.eras.modern
        self.decade8090 = d.eras.eighties90s
        self.decade6070 = d.eras.sixties70s
        self.decadeClassic = d.eras.classic
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

        // Tell the backend the viewer's country so it can hide movies that
        // YouTube won't play in this region. Uses the user's Region override if
        // set, otherwise the device locale (ISO 3166-1 alpha-2) — on-device
        // only, no permission, not tracking, ephemeral.
        if let region = effectiveRegion, region.count == 2 {
            request.setValue(region.uppercased(), forHTTPHeaderField: "X-Country")
        }

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

    /// Fetches movies constrained to a release-year range. Either bound is
    /// optional: send only `yearMin` for "and newer", only `yearMax` for
    /// "and older". Backend excludes TV episodes by default.
    func fetchMoviesByYearRange(
        yearMin: Int? = nil,
        yearMax: Int? = nil,
        sort: String = "popular",
        page: Int = 1,
        limit: Int = 20
    ) async throws -> [Movie] {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let yearMin = yearMin {
            components.queryItems?.append(URLQueryItem(name: "year_min", value: String(yearMin)))
        }

        if let yearMax = yearMax {
            components.queryItems?.append(URLQueryItem(name: "year_max", value: String(yearMax)))
        }

        let queryString = components.percentEncodedQuery ?? ""
        let response = try await performRequest(
            endpoint: "/movies?\(queryString)",
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
        // Percent-encode the category so values with spaces/&/# produce a
        // valid URL instead of nil (which would throw .invalidURL).
        let encodedCategory = category.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? category
        let response = try await performRequest(
            endpoint: "/movies/category/\(encodedCategory)?page=\(page)&limit=\(limit)",
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

    /// Fetch one page of any category endpoint, returning the movies AND the
    /// real total count (from pagination) so "See All" screens can show the
    /// count and a Load More button. Works for both /movies* and /browse/*.
    func fetchMoviePage(endpoint: String) async throws -> MoviePage {
        let response = try await performRequest(endpoint: endpoint, type: PagedMoviesResponse.self)
        return MoviePage(movies: response.data.movies, total: response.totalCount)
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

