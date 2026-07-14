import Foundation
import os

/// Debug-gated logger. Never logs the API key or full response bodies in release.
private let apiLog = Logger(subsystem: "com.movieboxz.admin", category: "api")

@inline(__always)
private func dlog(_ message: @autoclosure () -> String) {
    #if DEBUG
    let text = message()
    apiLog.debug("\(text, privacy: .public)")
    #endif
}

/// Extract a human-readable error message from a backend error body ({ error, message }).
private func backendErrorMessage(from data: Data, statusCode: Int) -> String {
    if let basic = try? JSONDecoder().decode(BasicResponse.self, from: data) {
        if let error = basic.error, !error.isEmpty { return error }
        if let message = basic.message, !message.isEmpty { return message }
    }
    // Fall back to a raw string body if it is short and non-empty.
    if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
       !raw.isEmpty, raw.count < 300 {
        return raw
    }
    return "Request failed (HTTP \(statusCode))"
}

@MainActor
class AdminAPIService: ObservableObject {
    private let baseURL: String
    private let adminAPIKey: String

    init() {
        self.baseURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? ""
        self.adminAPIKey = UserDefaults.standard.string(forKey: "adminAPIKey") ?? ""

        dlog("🔧 [API] Initialized with base URL: \(baseURL)")
        dlog("🔑 [API] Admin API Key configured: \(adminAPIKey.isEmpty ? "NO" : "YES")")
    }

    /// Build an admin API URL with correctly percent-encoded query items.
    /// Uses URLComponents so `&`, `+`, spaces etc. in values (e.g. "Tom & Jerry")
    /// are encoded instead of leaking into the query string.
    private func makeURL(path: String, queryItems: [URLQueryItem] = [], apiPrefix: String = "/api/admin") -> URL? {
        var components = URLComponents(string: "\(baseURL)\(apiPrefix)\(path)")
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        return components?.url
    }

    // MARK: - Generic Request
    private func request<T: Codable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> APIResponse<T> {
        guard let url = URL(string: "\(baseURL)/api/admin\(endpoint)") else {
            dlog("❌ [API] Invalid URL: \(baseURL)/api/admin\(endpoint)")
            throw APIError.invalidURL
        }

        dlog("📡 [API] \(method) \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
                if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
                    dlog("📤 [API] Request body: \(bodyString)")
                }
            } catch {
                dlog("❌ [API] Failed to encode request body: \(error)")
                throw APIError.decodingError(error.localizedDescription)
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                dlog("❌ [API] Invalid response type")
                throw APIError.invalidResponse
            }

            dlog("📥 [API] Response status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    dlog("❌ [API] Unauthorized - check API key")
                    throw APIError.unauthorized
                }
                let message = backendErrorMessage(from: data, statusCode: httpResponse.statusCode)
                dlog("❌ [API] HTTP \(httpResponse.statusCode): \(message)")
                throw APIError.server(status: httpResponse.statusCode, message: message)
            }

            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(APIResponse<T>.self, from: data)
                dlog("✅ [API] Successfully decoded response")
                return result
            } catch {
                dlog("❌ [API] Decoding error: \(error)")
                throw APIError.decodingError(error.localizedDescription)
            }
        } catch let error as APIError {
            throw error
        } catch {
            dlog("❌ [API] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    // MARK: - Basic (no-data) Request
    /// For endpoints that return only `{ success, message }` (e.g. featured delete/reorder).
    /// Parses the backend error body on failure and throws `.server`.
    @discardableResult
    private func requestBasic(endpoint: String, method: String = "GET", body: Encodable? = nil) async throws -> BasicResponse {
        guard let url = URL(string: "\(baseURL)/api/admin\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = try? JSONEncoder().encode(body)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw APIError.unauthorized
                }
                throw APIError.server(status: httpResponse.statusCode,
                                      message: backendErrorMessage(from: data, statusCode: httpResponse.statusCode))
            }
            // Body may be empty or { success, message } — tolerate either.
            if let decoded = try? JSONDecoder().decode(BasicResponse.self, from: data) {
                return decoded
            }
            return BasicResponse(success: true, message: nil, error: nil)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Stats
    func getStats() async throws -> AdminStats {
        dlog("📊 [API] Fetching statistics...")
        let response: APIResponse<AdminStats> = try await request(endpoint: "/stats")
        dlog("✅ [API] Stats retrieved successfully")
        return response.data
    }

    // MARK: - Movies
    func getMovies(page: Int = 1, limit: Int = 50, search: String? = nil, needsVerification: Bool = false) async throws -> MoviesData {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let search = search, !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        if needsVerification {
            items.append(URLQueryItem(name: "needs_verification", value: "true"))
        }

        guard let url = makeURL(path: "", queryItems: items, apiPrefix: "/api/movies") else {
            dlog("❌ [API] Invalid URL for movies endpoint")
            throw APIError.invalidURL
        }

        dlog("📡 [API] GET \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            dlog("📥 [API] Response status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw APIError.unauthorized
                }
                throw APIError.server(status: httpResponse.statusCode,
                                      message: backendErrorMessage(from: data, statusCode: httpResponse.statusCode))
            }

            do {
                let result = try JSONDecoder().decode(APIResponse<MoviesData>.self, from: data)
                dlog("✅ [API] Successfully decoded \(result.data.movies.count) movies")
                return result.data
            } catch {
                throw APIError.decodingError(error.localizedDescription)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Admin Movies (includes unavailable)
    /// GET /api/admin/movies — admin listing that can include unavailable movies.
    func getAdminMovies(includeUnavailable: Bool = false,
                        page: Int = 1,
                        limit: Int = 50,
                        sort: String? = nil,
                        search: String? = nil) async throws -> MoviesData {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if includeUnavailable {
            items.append(URLQueryItem(name: "include_unavailable", value: "true"))
        }
        if let sort = sort, !sort.isEmpty {
            items.append(URLQueryItem(name: "sort", value: sort))
        }
        if let search = search, !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }

        guard let url = makeURL(path: "/movies", queryItems: items) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw APIError.unauthorized
                }
                throw APIError.server(status: httpResponse.statusCode,
                                      message: backendErrorMessage(from: data, statusCode: httpResponse.statusCode))
            }
            do {
                let result = try JSONDecoder().decode(APIResponse<MoviesData>.self, from: data)
                return result.data
            } catch {
                throw APIError.decodingError(error.localizedDescription)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - YouTube Quota
    /// GET /api/admin/quota
    func getQuota() async throws -> QuotaInfo {
        let response: APIResponse<QuotaInfo> = try await request(endpoint: "/quota")
        return response.data
    }

    // MARK: - Channels
    func getChannels(page: Int = 1, limit: Int = 50) async throws -> ChannelsData {
        dlog("📺 [API] Fetching channels...")

        guard let url = URL(string: "\(baseURL)/api/channels?page=\(page)&limit=\(limit)") else {
            dlog("❌ [API] Invalid URL for channels endpoint")
            throw APIError.invalidURL
        }

        dlog("📡 [API] GET \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                dlog("❌ [API] Invalid response type")
                throw APIError.invalidResponse
            }

            dlog("📥 [API] Response status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                dlog("❌ [API] HTTP error: \(httpResponse.statusCode)")
                throw APIError.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(APIResponse<ChannelsData>.self, from: data)
            dlog("✅ [API] Channels retrieved: \(result.data.channels.count)")
            return result.data
        } catch let error as APIError {
            throw error
        } catch {
            dlog("❌ [API] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    // MARK: - Genres
    func getGenres(page: Int = 1, limit: Int = 100) async throws -> GenresData {
        dlog("🎭 [API] Fetching genres...")

        guard let url = URL(string: "\(baseURL)/api/browse/genres?page=\(page)&limit=\(limit)") else {
            dlog("❌ [API] Invalid URL for genres endpoint")
            throw APIError.invalidURL
        }

        dlog("📡 [API] GET \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                dlog("❌ [API] Invalid response type")
                throw APIError.invalidResponse
            }

            dlog("📥 [API] Response status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                dlog("❌ [API] HTTP error: \(httpResponse.statusCode)")
                throw APIError.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(APIResponse<GenresData>.self, from: data)
            dlog("✅ [API] Genres retrieved: \(result.data.genres.count)")
            return result.data
        } catch let error as APIError {
            throw error
        } catch {
            dlog("❌ [API] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    // MARK: - Staging Workflow

    /// Import movies from a YouTube channel to staging
    func importToStaging(channelId: String, channelTitle: String, limit: Int = 10, batchId: String? = nil) async throws -> ImportResponse {
        let endpoint = "/staging/import"
        let body = ImportRequest(channelId: channelId, channelTitle: channelTitle, limit: limit, batchId: batchId)

        dlog("📥 [API] Importing to staging: channel=\(channelTitle), limit=\(limit)")

        let response: APIResponse<ImportResponse> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Import completed: \(response.data.imported) imported, \(response.data.skipped) skipped")

        return response.data
    }

    /// Get staged movies with filtering, search and pagination.
    /// Returns the full `StagedMoviesData` (including `pagination`) so callers can page.
    func getStagedMovies(status: ApprovalStatus? = nil,
                         filter: String? = nil,
                         channelId: String? = nil,
                         search: String? = nil,
                         page: Int = 1,
                         limit: Int = 50) async throws -> StagedMoviesData {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let status = status {
            items.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let filter = filter {
            items.append(URLQueryItem(name: "filter", value: filter))
        }
        if let channelId = channelId, !channelId.isEmpty {
            items.append(URLQueryItem(name: "channel_id", value: channelId))
        }
        if let search = search, !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }

        // Build a correctly-encoded query string, then hand the path+query to the
        // generic request helper (values like "Tom & Jerry" are encoded properly).
        var components = URLComponents()
        components.queryItems = items
        let query = components.percentEncodedQuery ?? ""
        let endpoint = "/staging/movies?\(query)"

        dlog("📋 [API] Fetching staged movies: status=\(status?.rawValue ?? "all"), filter=\(filter ?? "none"), page=\(page)")

        let response: APIResponse<StagedMoviesData> = try await request(endpoint: endpoint, method: "GET")
        dlog("✅ [API] Found \(response.data.movies.count) staged movies")

        return response.data
    }

    /// Get staging area statistics
    func getStagingStats() async throws -> StagingStats {
        let endpoint = "/staging/stats"

        dlog("📊 [API] Fetching staging stats")

        let response: APIResponse<StagingStats> = try await request(endpoint: endpoint, method: "GET")
        dlog("✅ [API] Staging stats: \(response.data.pending) pending, \(response.data.enriched) enriched")

        return response.data
    }

    /// Preview enrichment for a staged movie (doesn't save)
    func previewEnrichment(movieId: String, priority: EnrichmentPriority = .full, fields: [String]? = nil, preferTmdb: Bool = true) async throws -> EnrichmentPreview {
        let endpoint = "/staging/movies/\(movieId)/preview-enrichment"
        let body = EnrichmentRequest(priority: priority, fields: fields, preferTmdb: preferTmdb, applyFromPreview: nil)

        dlog("🔍 [API] Previewing enrichment for movie \(movieId) with priority \(priority.rawValue)")

        let response: APIResponse<EnrichmentPreview> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Preview completed: confidence=\(response.data.confidence ?? 0), source=\(response.data.source ?? "none")")

        return response.data
    }

    /// Apply enrichment to a staged movie
    func applyEnrichment(movieId: String, priority: EnrichmentPriority = .full, fields: [String]? = nil, preferTmdb: Bool = true, applyFromPreview: Bool = false) async throws -> StagedMovie {
        let endpoint = "/staging/movies/\(movieId)/enrich"
        let body = EnrichmentRequest(priority: priority, fields: fields, preferTmdb: preferTmdb, applyFromPreview: applyFromPreview)

        dlog("✨ [API] Applying enrichment for movie \(movieId) with priority \(priority.rawValue)")

        let response: APIResponse<StagedMovie> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Enrichment applied successfully")

        return response.data
    }

    /// Manually enrich from user-provided IMDB ID - system will trust this choice
    func enrichFromManualIMDB(movieId: String, imdbId: String, verifiedBy: String = "admin") async throws -> StagedMovie {
        let endpoint = "/staging/movies/\(movieId)/enrich-manual-imdb"

        struct ManualIMDBRequest: Codable {
            let imdbId: String
            let verifiedBy: String
        }

        let body = ManualIMDBRequest(imdbId: imdbId, verifiedBy: verifiedBy)

        dlog("🎯 [API] Manual IMDB enrichment for movie \(movieId) with IMDB \(imdbId)")

        let response: APIResponse<StagedMovie> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Manual IMDB enrichment successful - movie verified")

        return response.data
    }

    /// Clear all enrichment data - reset movie to unenriched state
    func clearEnrichment(movieId: String) async throws -> StagedMovie {
        let endpoint = "/staging/movies/\(movieId)/clear-enrichment"

        dlog("🗑️ [API] Clearing enrichment for movie \(movieId)")

        let response: APIResponse<StagedMovie> = try await request(endpoint: endpoint, method: "POST")
        dlog("✅ [API] Enrichment cleared successfully")

        return response.data
    }

    /// Start batch enrichment (async) - returns immediately with batch ID
    func batchEnrich(movieIds: [String], priority: EnrichmentPriority = .full) async throws -> BatchEnrichmentStartResponse {
        let endpoint = "/staging/batch-enrich"
        let body = BatchEnrichmentRequest(movieIds: movieIds, priority: priority.rawValue)

        dlog("📦 [API] Starting batch enrichment for \(movieIds.count) movies with priority \(priority.rawValue)")

        let response: APIResponse<BatchEnrichmentStartResponse> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Batch enrichment started: batchId=\(response.data.batchId), total=\(response.data.total)")

        return response.data
    }

    /// Get batch enrichment progress
    func getBatchEnrichmentProgress(batchId: String) async throws -> BatchEnrichmentProgress {
        let endpoint = "/staging/batch-enrich/\(batchId)/status"

        let response: APIResponse<BatchEnrichmentProgress> = try await request(endpoint: endpoint, method: "GET")

        if let percentage = response.data.percentage {
            dlog("📊 [API] Enrichment progress: \(percentage)% (\(response.data.enriched + response.data.failed + response.data.skipped)/\(response.data.total))")
        }

        return response.data
    }

    /// Update staged movie fields (manual editing)
    func updateStagedMovie(movieId: String, updates: [String: Any]) async throws -> StagedMovie {
        let endpoint = "/admin/staging/movies/\(movieId)"

        dlog("✏️ [API] Updating staged movie \(movieId) with \(updates.count) fields")

        // Custom implementation for [String: Any] body
        guard let url = URL(string: "\(baseURL)/api\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: updates)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        let response = try JSONDecoder().decode(APIResponse<StagedMovie>.self, from: data)
        dlog("✅ [API] Movie updated successfully")

        return response.data
    }

    /// Approve a staged movie for publishing
    func approveStagedMovie(movieId: String, notes: String? = nil) async throws -> StagedMovie {
        let endpoint = "/staging/movies/\(movieId)/approve"

        var body: [String: String] = [:]
        if let notes = notes {
            body["notes"] = notes
        }

        dlog("✅ [API] Approving staged movie \(movieId)")

        let response: APIResponse<StagedMovie> = try await request(endpoint: endpoint, method: "POST", body: body.isEmpty ? nil : body)
        dlog("✅ [API] Movie approved successfully")

        return response.data
    }

    /// Reject a staged movie
    func rejectStagedMovie(movieId: String, reason: String) async throws -> StagedMovie {
        let endpoint = "/staging/movies/\(movieId)/reject"
        let body = ["reason": reason]

        dlog("❌ [API] Rejecting staged movie \(movieId)")

        let response: APIResponse<StagedMovie> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Movie rejected successfully")

        return response.data
    }

    /// Publish approved staged movies to production
    func publishStagedMovies(movieIds: [String]? = nil) async throws -> PublishResponse {
        let endpoint = "/staging/publish"
        let body = PublishRequest(ids: movieIds)

        if let ids = movieIds {
            dlog("🚀 [API] Publishing \(ids.count) specific staged movies")
        } else {
            dlog("🚀 [API] Publishing all approved staged movies")
        }

        let response: APIResponse<PublishResponse> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Published \(response.data.published) movies, \(response.data.failed) failed")

        return response.data
    }

    /// Delete a staged movie
    func deleteStagedMovie(movieId: String) async throws {
        let endpoint = "/staging/movies/\(movieId)"

        dlog("🗑️ [API] Deleting staged movie \(movieId)")

        guard let url = URL(string: "\(baseURL)/api\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")

        let (_, httpResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        dlog("✅ [API] Movie deleted successfully")
    }

    // MARK: - TV Series

    struct SeriesPageData: Codable {
        let series: [TvSeries]
        let pagination: PaginationInfo
    }

    /// Compatibility: returns just the series array (first page up to `limit`).
    func getTvSeriesList(limit: Int = 100) async throws -> [TvSeries] {
        try await getTvSeriesListPaged(page: 1, limit: limit).series
    }

    /// Paged TV series listing that surfaces pagination (tolerant of `pages`/`totalPages`).
    func getTvSeriesListPaged(page: Int = 1, limit: Int = 100) async throws -> SeriesPageData {
        let response: APIResponse<SeriesPageData> = try await request(endpoint: "/series?page=\(page)&limit=\(limit)")
        return response.data
    }

    /// Fetch every TV series by paging until exhausted — convenient for pickers.
    func fetchAllTvSeries(pageSize: Int = 100) async throws -> [TvSeries] {
        var all: [TvSeries] = []
        var page = 1
        while true {
            let data = try await getTvSeriesListPaged(page: page, limit: pageSize)
            all.append(contentsOf: data.series)
            let totalPages = max(data.pagination.pages, 1)
            if page >= totalPages || data.series.isEmpty { break }
            page += 1
            if page > 1000 { break } // safety valve
        }
        return all
    }

    func createTvSeries(title: String) async throws -> TvSeries {
        struct Body: Codable { let title: String }
        struct SeriesWrapper: Codable { let series: TvSeries }
        let response: APIResponse<SeriesWrapper> = try await request(
            endpoint: "/series/create",
            method: "POST",
            body: Body(title: title)
        )
        return response.data.series
    }

    func assignTvSeriesToStagedMovie(movieId: String, seriesId: String?) async throws -> StagedMovie {
        var updates: [String: Any] = [:]
        if let sid = seriesId {
            updates["tv_series_id"] = sid
        } else {
            updates["tv_series_id"] = NSNull()
        }
        return try await updateStagedMovie(movieId: movieId, updates: updates)
    }

    // MARK: - TV Series Admin

    /// Compatibility: returns just the movies for the first page.
    func getTVContent() async throws -> [Movie] {
        dlog("📺 [API] Fetching TV content...")
        let response: APIResponse<TVContentData> = try await request(endpoint: "/tv-content?page=1&limit=500")
        dlog("✅ [API] TV content retrieved: \(response.data.movies.count) movies")
        return response.data.movies
    }

    /// Paged TV content with pagination surfaced (tolerant of `pages`/`totalPages`).
    func getTVContentPaged(page: Int = 1, limit: Int = 100) async throws -> TVContentPagedData {
        let response: APIResponse<TVContentPagedData> = try await request(endpoint: "/tv-content?page=\(page)&limit=\(limit)")
        return response.data
    }

    func getAdminTVSeriesList() async throws -> [TvSeries] {
        dlog("📺 [API] Fetching TV series list...")
        let response: APIResponse<TvSeriesListData> = try await request(endpoint: "/tv-series")
        dlog("✅ [API] TV series retrieved: \(response.data.series.count) series")
        return response.data.series
    }

    func createAdminTVSeries(title: String, imdbId: String?, description: String?) async throws -> TvSeries {
        dlog("📺 [API] Creating TV series: \(title)")

        struct Body: Codable {
            let title: String
            let imdb_id: String?
            let description: String?
        }

        let body = Body(title: title, imdb_id: imdbId, description: description)
        let response: APIResponse<TvSeries> = try await request(endpoint: "/tv-series", method: "POST", body: body)
        dlog("✅ [API] TV series created: \(response.data.title)")
        return response.data
    }

    /// Update a movie's TV info. Decodes the slim `TVInfoUpdateResult` the endpoint
    /// actually returns (no genres/view_count/like_count), so the save no longer
    /// false-fails on decode.
    ///
    /// - `seasonNumber` / `episodeNumber`: sent only when non-nil (unchanged values
    ///    are not overwritten).
    /// - `tvSeriesId`: sent when non-nil.
    /// - `clearSeries`: when true, explicitly sends `tv_series_id: null` to detach the
    ///    movie from any series (mutually exclusive with providing a `tvSeriesId`).
    func updateMovieTVInfo(
        movieId: String,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        seriesType: String? = nil,
        tvSeriesId: String? = nil,
        clearSeries: Bool,
        isTvShow: Bool? = nil,
        isTvSeries: Bool? = nil
    ) async throws -> TVInfoUpdateResult {
        var body: [String: Any] = [:]
        if let v = seasonNumber { body["season_number"] = v }
        if let v = episodeNumber { body["episode_number"] = v }
        if let v = seriesType { body["series_type"] = v }
        if clearSeries {
            body["tv_series_id"] = NSNull()
        } else if let v = tvSeriesId {
            body["tv_series_id"] = v
        }
        if let v = isTvShow { body["is_tv_show"] = v }
        if let v = isTvSeries { body["is_tv_series"] = v }

        return try await performTVInfoUpdate(movieId: movieId, body: body)
    }

    private func performTVInfoUpdate(movieId: String, body: [String: Any]) async throws -> TVInfoUpdateResult {
        dlog("✏️ [API] Updating TV info for movie \(movieId)")

        guard let url = URL(string: "\(baseURL)/api/admin/movies/\(movieId)/tv-info") else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.server(status: httpResponse.statusCode,
                                  message: backendErrorMessage(from: data, statusCode: httpResponse.statusCode))
        }

        let apiResponse = try JSONDecoder().decode(APIResponse<TVInfoUpdateResult>.self, from: data)
        dlog("✅ [API] Movie TV info updated successfully")
        return apiResponse.data
    }

    /// Deprecated compatibility overload returning a `Movie` (built from the slim
    /// result with default genres/counts). Kept so `TVSeriesView` keeps compiling;
    /// a later agent will migrate it to the `TVInfoUpdateResult` API above.
    @available(*, deprecated, message: "Use updateMovieTVInfo(...clearSeries:) -> TVInfoUpdateResult")
    func updateMovieTVInfo(
        movieId: String,
        seasonNumber: Int?,
        episodeNumber: Int?,
        seriesType: String?,
        tvSeriesId: String?,
        isTvShow: Bool?,
        isTvSeries: Bool?
    ) async throws -> Movie {
        var body: [String: Any] = [:]
        if let v = seasonNumber { body["season_number"] = v }
        if let v = episodeNumber { body["episode_number"] = v }
        if let v = seriesType { body["series_type"] = v }
        if let v = tvSeriesId { body["tv_series_id"] = v }
        if let v = isTvShow { body["is_tv_show"] = v }
        if let v = isTvSeries { body["is_tv_series"] = v }

        let result = try await performTVInfoUpdate(movieId: movieId, body: body)
        return Movie(from: result)
    }

    // MARK: - Channel Management

    func getChannelsWithPatterns() async throws -> ChannelsWithPatternsData {
        let endpoint = "/channels"
        let response: APIResponse<ChannelsWithPatternsData> = try await request(endpoint: endpoint)
        return response.data
    }

    func addChannel(channelId: String) async throws -> ChannelWithPattern {
        let endpoint = "/channels"
        let body = ["channelId": channelId]
        let response: APIResponse<ChannelWithPattern> = try await request(endpoint: endpoint, method: "POST", body: body)
        return response.data
    }

    func getChannelPattern(channelId: String) async throws -> ChannelPattern? {
        let endpoint = "/channels/\(channelId)/pattern"
        let response: APIResponse<ChannelPattern?> = try await request(endpoint: endpoint)
        return response.data
    }

    func updateChannelPattern(channelId: String, channelName: String, patterns: [[String: Any]], fallbackPattern: [String: String]? = nil) async throws -> ChannelPattern {
        let endpoint = "/api/admin/channels/\(channelId)/pattern"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")

        var body: [String: Any] = [
            "channelName": channelName,
            "patterns": patterns
        ]
        if let fallbackPattern = fallbackPattern {
            body["fallbackPattern"] = fallbackPattern
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let response = try JSONDecoder().decode(APIResponse<ChannelPattern>.self, from: data)
        return response.data
    }

    func deleteChannelPattern(channelId: String) async throws {
        let endpoint = "/api/admin/channels/\(channelId)/pattern"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")

        let (_, httpResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = httpResponse as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError((httpResponse as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func testChannelPattern(channelId: String, patterns: [[String: Any]], fallbackPattern: [String: String]? = nil, sampleCount: Int = 5) async throws -> PatternTestData {
        let endpoint = "/api/admin/channels/\(channelId)/test-pattern"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")

        var body: [String: Any] = [
            "patterns": patterns,
            "sampleCount": sampleCount
        ]
        if let fallbackPattern = fallbackPattern {
            body["fallbackPattern"] = fallbackPattern
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let response = try JSONDecoder().decode(APIResponse<PatternTestData>.self, from: data)
        return response.data
    }

    func deleteChannel(channelId: String) async throws {
        dlog("🗑️ [DeleteChannel] Deleting channel: \(channelId)")

        // URL-encode the channel ID - create custom character set that excludes @ symbol
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "@") // Ensure @ is encoded

        guard let encodedId = channelId.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            dlog("🗑️ [DeleteChannel] ❌ Failed to URL-encode channel ID")
            throw APIError.invalidURL
        }

        let endpoint = "/api/admin/channels/\(encodedId)"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            dlog("🗑️ [DeleteChannel] ❌ Failed to create URL: \(baseURL)\(endpoint)")
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = httpResponse as? HTTPURLResponse else {
            dlog("🗑️ [DeleteChannel] ❌ Invalid response type")
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseBody = String(data: data, encoding: .utf8), !responseBody.isEmpty {
                dlog("🗑️ [DeleteChannel] ❌ HTTP \(httpResponse.statusCode): \(responseBody)")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        dlog("🗑️ [DeleteChannel] ✅ Channel deleted successfully")
    }

    /// Update channel classification (content type and pattern source)
    func updateChannelClassification(channelId: String, hasMovies: Bool, hasSeries: Bool, hasKidsContent: Bool, patternSource: String) async throws -> ChannelWithPattern {
        dlog("🏷️ [API] Updating channel classification for \(channelId)")
        dlog("🏷️ [API]   hasMovies: \(hasMovies)")
        dlog("🏷️ [API]   hasSeries: \(hasSeries)")
        dlog("🏷️ [API]   hasKidsContent: \(hasKidsContent)")
        dlog("🏷️ [API]   patternSource: \(patternSource)")

        struct UpdateBody: Codable {
            let has_movies: Bool
            let has_series: Bool
            let has_kids_content: Bool
            let pattern_source: String
        }

        let body = UpdateBody(
            has_movies: hasMovies,
            has_series: hasSeries,
            has_kids_content: hasKidsContent,
            pattern_source: patternSource
        )

        let endpoint = "/channels/\(channelId)"
        let response: APIResponse<ChannelWithPattern> = try await request(endpoint: endpoint, method: "PUT", body: body)
        dlog("✅ [API] Channel classification updated")

        return response.data
    }

    // MARK: - Channel Management Advanced

    /// Get or create channel settings
    func getChannelSettings(channelId: String) async throws -> ChannelSettings {
        let endpoint = "/channel-management/\(channelId)/settings"

        dlog("⚙️ [API] Fetching channel settings for \(channelId)")

        let response: APIResponse<ChannelSettings> = try await request(endpoint: endpoint)
        dlog("✅ [API] Channel settings retrieved")

        return response.data
    }

    /// Update channel settings
    func updateChannelSettings(channelId: String, settings: ChannelSettings) async throws -> ChannelSettings {
        let endpoint = "/channel-management/\(channelId)/settings"

        dlog("💾 [API] Updating channel settings for \(channelId)")

        // Build body with only the fields that can be updated
        struct UpdateBody: Codable {
            let autoImportEnabled: Bool
            let autoImportSchedule: String
            let importLimit: Int?
            let importSortOrder: String
            let defaultEnrichmentPriority: String
            let autoEnrichOnImport: Bool
            let autoApproveThreshold: Double?
            let requireManualReview: Bool
            let channelTag: String?
            let isFeatured: Bool
            let qualityTier: String
            let minDurationMinutes: Int?
            let maxDurationMinutes: Int?
            let filterShorts: Bool

            enum CodingKeys: String, CodingKey {
                case autoImportEnabled = "auto_import_enabled"
                case autoImportSchedule = "auto_import_schedule"
                case importLimit = "import_limit"
                case importSortOrder = "import_sort_order"
                case defaultEnrichmentPriority = "default_enrichment_priority"
                case autoEnrichOnImport = "auto_enrich_on_import"
                case autoApproveThreshold = "auto_approve_threshold"
                case requireManualReview = "require_manual_review"
                case channelTag = "channel_tag"
                case isFeatured = "is_featured"
                case qualityTier = "quality_tier"
                case minDurationMinutes = "min_duration_minutes"
                case maxDurationMinutes = "max_duration_minutes"
                case filterShorts = "filter_shorts"
            }
        }

        dlog("💾 [API] Duration filters - min: \(settings.minDurationMinutes?.description ?? "nil"), max: \(settings.maxDurationMinutes?.description ?? "nil"), filterShorts: \(settings.filterShorts)")

        let body = UpdateBody(
            autoImportEnabled: settings.autoImportEnabled,
            autoImportSchedule: settings.autoImportSchedule,
            importLimit: settings.importLimit,
            importSortOrder: settings.importSortOrder,
            defaultEnrichmentPriority: settings.defaultEnrichmentPriority,
            autoEnrichOnImport: settings.autoEnrichOnImport,
            autoApproveThreshold: settings.autoApproveThreshold,
            requireManualReview: settings.requireManualReview,
            channelTag: settings.channelTag,
            isFeatured: settings.isFeatured,
            qualityTier: settings.qualityTier,
            minDurationMinutes: settings.minDurationMinutes,
            maxDurationMinutes: settings.maxDurationMinutes,
            filterShorts: settings.filterShorts
        )

        let response: APIResponse<ChannelSettings> = try await request(endpoint: endpoint, method: "PUT", body: body)
        dlog("✅ [API] Channel settings updated successfully")

        return response.data
    }

    /// Import all or limited videos from a channel to staging
    func importAllVideos(channelId: String, request: BulkImportRequest) async throws -> BulkImportResponse {
        let endpoint = "/channel-management/\(channelId)/import-all"

        dlog("📥 [API] Starting bulk import for channel \(channelId)")
        if let limit = request.limit {
            dlog("📥 [API] Import limit: \(limit) videos, sort: \(request.sortOrder)")
        } else {
            dlog("📥 [API] Importing all videos, sort: \(request.sortOrder)")
        }

        struct RequestBody: Codable {
            let limit: Int?
            let sortOrder: String
            let applySettings: Bool
            let autoEnrich: Bool?
        }

        let body = RequestBody(
            limit: request.limit,
            sortOrder: request.sortOrder,
            applySettings: request.applySettings,
            autoEnrich: request.autoEnrich
        )

        let response: APIResponse<BulkImportResponse> = try await self.request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Bulk import started: batchId=\(response.data.batchId), status=\(response.data.status)")

        return response.data
    }

    /// Get real-time import progress
    func getImportProgress(batchId: String) async throws -> ImportProgress {
        let endpoint = "/channel-management/imports/\(batchId)/status"

        let response: APIResponse<ImportProgress> = try await request(endpoint: endpoint)

        if let percentage = response.data.percentage {
            dlog("📊 [API] Import progress: \(percentage)% (\(response.data.imported + response.data.skipped + response.data.failed)/\(response.data.found))")
        }

        return response.data
    }

    /// Delete all movies from a channel
    func deleteChannelMovies(channelId: String, deleteFrom: String = "staging,production") async throws -> BatchDeleteResponse {
        let endpoint = "/channel-management/\(channelId)/movies?deleteFrom=\(deleteFrom)"

        dlog("🗑️ [API] Deleting channel movies from: \(deleteFrom)")

        guard let url = URL(string: "\(baseURL)/api/admin\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        let response = try JSONDecoder().decode(APIResponse<BatchDeleteResponse>.self, from: data)
        dlog("✅ [API] Deleted: \(response.data.deletedFromStaging) from staging, \(response.data.deletedFromProduction) from production")

        return response.data
    }

    /// Re-import channel (delete existing and import fresh)
    func reimportChannel(channelId: String, deleteExisting: Bool = true, limit: Int? = nil, applySettings: Bool = true) async throws -> BulkImportResponse {
        let endpoint = "/channel-management/\(channelId)/reimport"

        dlog("🔄 [API] Re-importing channel \(channelId)")
        if deleteExisting {
            dlog("🗑️ [API] Will delete existing movies first")
        }

        struct RequestBody: Codable {
            let deleteExisting: Bool
            let applySettings: Bool
            let limit: Int?
        }

        let body = RequestBody(
            deleteExisting: deleteExisting,
            applySettings: applySettings,
            limit: limit
        )

        let response: APIResponse<BulkImportResponse> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Re-import started: batchId=\(response.data.batchId)")

        return response.data
    }

    /// Get channel movies from staging and/or production
    func getChannelMovies(channelId: String, source: String = "staging,production", page: Int = 1, limit: Int = 50) async throws -> ChannelMoviesData {
        let endpoint = "/channel-management/\(channelId)/movies?source=\(source)&page=\(page)&limit=\(limit)"

        dlog("📋 [API] Fetching channel movies: source=\(source), page=\(page)")

        let response: APIResponse<ChannelMoviesData> = try await request(endpoint: endpoint)

        if let staging = response.data.staging {
            dlog("✅ [API] Found \(staging.movies.count) staged movies (total: \(staging.total))")
        }
        if let production = response.data.production {
            dlog("✅ [API] Found \(production.movies.count) production movies (total: \(production.total))")
        }

        return response.data
    }

    /// Get import history for a channel
    func getImportHistory(channelId: String, limit: Int = 20) async throws -> ImportHistoryData {
        let endpoint = "/channel-management/\(channelId)/import-history?limit=\(limit)"

        dlog("📜 [API] Fetching import history for channel \(channelId)")

        let response: APIResponse<ImportHistoryData> = try await request(endpoint: endpoint)
        dlog("✅ [API] Found \(response.data.imports.count) import records")

        return response.data
    }

    // MARK: - Production Movie Management

    /// Update a production movie
    func updateProductionMovie(movieId: String, updates: [String: Any]) async throws -> Movie {
        let endpoint = "/movies/\(movieId)"

        dlog("✏️ [API] Updating production movie \(movieId)")

        guard let url = URL(string: "\(baseURL)/api/admin\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")

        request.httpBody = try JSONSerialization.data(withJSONObject: updates)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(APIResponse<Movie>.self, from: data)
        dlog("✅ [API] Production movie updated successfully")

        return apiResponse.data
    }

    /// Enrich a production movie
    func enrichProductionMovie(movieId: String, priority: EnrichmentPriority) async throws -> Movie {
        let endpoint = "/movies/\(movieId)/enrich"
        let body = ["priority": priority.rawValue]

        dlog("✨ [API] Enriching production movie \(movieId) with priority: \(priority.rawValue)")

        let response: APIResponse<Movie> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Production movie enriched successfully")

        return response.data
    }

    /// Update genres for a production movie
    func updateProductionMovieGenres(movieId: String, genreIds: [String]) async throws -> Movie {
        let endpoint = "/movies/\(movieId)/genres"

        struct GenreUpdateBody: Codable {
            let genreIds: [String]
        }

        let body = GenreUpdateBody(genreIds: genreIds)

        dlog("🏷️ [API] Updating genres for production movie \(movieId)")

        let response: APIResponse<Movie> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Production movie genres updated successfully")

        return response.data
    }

    // MARK: - Featured Movies Management

    struct FeaturedListData: Codable {
        let movies: [FeaturedMovieItem]
        let count: Int
    }

    struct EmptyData: Codable {}

    func getFeaturedMovies() async throws -> [FeaturedMovieItem] {
        let response: APIResponse<FeaturedListData> = try await request(endpoint: "/featured")
        return response.data.movies
    }

    func featureMovie(movieId: String) async throws {
        struct EmptyResponse: Codable {}
        let _: APIResponse<EmptyResponse> = try await request(endpoint: "/featured/\(movieId)", method: "POST")
    }

    func unfeatureMovie(movieId: String) async throws {
        // Returns only { success, message } — decode tolerantly so it doesn't false-fail.
        try await requestBasic(endpoint: "/featured/\(movieId)", method: "DELETE")
    }

    func reorderFeaturedMovies(movieIds: [String]) async throws {
        struct ReorderBody: Codable { let movieIds: [String] }
        // Returns only { success, message } — decode tolerantly so it doesn't false-fail.
        try await requestBasic(endpoint: "/featured/reorder", method: "PATCH", body: ReorderBody(movieIds: movieIds))
    }

    /// Enrich a production movie with a manual IMDB ID
    func enrichProductionMovieWithManualIMDB(movieId: String, imdbId: String) async throws -> Movie {
        let endpoint = "/movies/\(movieId)/enrich-manual-imdb"

        struct ManualIMDBBody: Codable {
            let imdbId: String
        }

        let body = ManualIMDBBody(imdbId: imdbId)

        dlog("🎯 [API] Manual IMDB enrichment for production movie \(movieId) with IMDB \(imdbId)")

        let response: APIResponse<Movie> = try await request(endpoint: endpoint, method: "POST", body: body)
        dlog("✅ [API] Production movie enriched with manual IMDB successfully")

        return response.data
    }

    // MARK: - Import / Maintenance Operations

    /// POST /api/admin/channel-management/imports/:batchId/cancel
    /// Cancels a running import. Returns the backend message.
    @discardableResult
    func cancelImport(batchId: String) async throws -> String? {
        let response = try await requestBasic(
            endpoint: "/channel-management/imports/\(batchId)/cancel",
            method: "POST"
        )
        return response.message
    }

    /// POST /api/admin/channels/:channelId/import-latest
    /// Imports the latest N videos from a channel to staging (async; returns batch info).
    func importLatest(channelId: String, limit: Int = 20, sortOrder: String = "latest", applySettings: Bool = true) async throws -> BulkImportResponse {
        struct Body: Codable {
            let limit: Int
            let sortOrder: String
            let applySettings: Bool
        }
        let body = Body(limit: limit, sortOrder: sortOrder, applySettings: applySettings)
        let response: APIResponse<BulkImportResponse> = try await request(
            endpoint: "/channel-management/\(channelId)/import-latest",
            method: "POST",
            body: body
        )
        return response.data
    }

    /// POST /api/admin/movies/fix-titles
    /// Bulk re-cleans production movie titles using current channel patterns.
    /// Pass `dryRun: true` to preview without applying.
    func fixTitles(dryRun: Bool = true, limit: Int? = nil, channelId: String? = nil) async throws -> FixTitlesResult {
        struct Body: Codable {
            let dryRun: Bool
            let limit: Int?
            let channelId: String?
        }
        let body = Body(dryRun: dryRun, limit: limit, channelId: channelId)
        let response: APIResponse<FixTitlesResult> = try await request(
            endpoint: "/movies/fix-titles",
            method: "POST",
            body: body
        )
        return response.data
    }

    /// POST /api/admin/enrich-enhanced
    /// Re-enriches production movies using enhanced actor-based matching + IMDB scraping.
    func enrichEnhanced(channelTitle: String? = nil, channelId: String? = nil, limit: Int = 100, onlyUnenriched: Bool = true) async throws -> EnrichEnhancedResult {
        struct Body: Codable {
            let channelTitle: String?
            let channelId: String?
            let limit: Int
            let onlyUnenriched: Bool
        }
        let body = Body(channelTitle: channelTitle, channelId: channelId, limit: limit, onlyUnenriched: onlyUnenriched)
        let response: APIResponse<EnrichEnhancedResult> = try await request(
            endpoint: "/enrich-enhanced",
            method: "POST",
            body: body
        )
        return response.data
    }

    // MARK: - Manual Enrichment (Verification) Queue

    /// Build a "path?query" endpoint string with correctly percent-encoded values.
    private func endpointWithQuery(_ path: String, _ items: [URLQueryItem]) -> String {
        guard !items.isEmpty else { return path }
        var components = URLComponents()
        components.queryItems = items
        let query = components.percentEncodedQuery ?? ""
        return query.isEmpty ? path : "\(path)?\(query)"
    }

    /// GET /api/admin/manual-enrichment-queue
    func getEnrichmentQueue(status: String = "pending",
                            channelId: String? = nil,
                            limit: Int = 50,
                            offset: Int = 0) async throws -> EnrichmentQueueData {
        var items = [
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let channelId, !channelId.isEmpty {
            items.append(URLQueryItem(name: "channelId", value: channelId))
        }

        dlog("📋 [API] Fetching enrichment queue: status=\(status), offset=\(offset)")

        let response: APIResponse<EnrichmentQueueData> = try await request(
            endpoint: endpointWithQuery("/manual-enrichment-queue", items)
        )
        return response.data
    }

    /// GET /api/admin/manual-enrichment-queue/stats
    func getEnrichmentQueueStats(channelId: String? = nil) async throws -> EnrichmentQueueStats {
        var items: [URLQueryItem] = []
        if let channelId, !channelId.isEmpty {
            items.append(URLQueryItem(name: "channelId", value: channelId))
        }
        let response: APIResponse<EnrichmentQueueStatsData> = try await request(
            endpoint: endpointWithQuery("/manual-enrichment-queue/stats", items)
        )
        return response.data.stats
    }

    /// GET /api/admin/manual-enrichment-queue/:queueId
    func getEnrichmentQueueItem(queueId: String) async throws -> EnrichmentQueueItem {
        let response: APIResponse<EnrichmentQueueItemData> = try await request(
            endpoint: "/manual-enrichment-queue/\(queueId)"
        )
        return response.data.item
    }

    /// POST /api/admin/manual-enrichment-queue/:queueId/match
    /// Marks the entry matched and enriches the movie from the given IMDB ID.
    /// Returns the backend message ("Movie matched successfully: <title>").
    @discardableResult
    func matchEnrichmentQueueItem(queueId: String, imdbId: String, notes: String? = nil) async throws -> String? {
        struct Body: Codable {
            let imdbId: String
            let notes: String?
        }
        dlog("🎯 [API] Matching queue entry \(queueId) with IMDB \(imdbId)")
        let response = try await requestBasic(
            endpoint: "/manual-enrichment-queue/\(queueId)/match",
            method: "POST",
            body: Body(imdbId: imdbId, notes: notes)
        )
        return response.message
    }

    /// POST /api/admin/manual-enrichment-queue/:queueId/skip
    @discardableResult
    func skipEnrichmentQueueItem(queueId: String, reason: String? = nil) async throws -> String? {
        struct Body: Codable {
            let reason: String?
        }
        dlog("⏭️ [API] Skipping queue entry \(queueId)")
        let response = try await requestBasic(
            endpoint: "/manual-enrichment-queue/\(queueId)/skip",
            method: "POST",
            body: Body(reason: reason)
        )
        return response.message
    }

    /// DELETE /api/admin/manual-enrichment-queue/:queueId
    @discardableResult
    func deleteEnrichmentQueueItem(queueId: String) async throws -> String? {
        dlog("🗑️ [API] Deleting queue entry \(queueId)")
        let response = try await requestBasic(
            endpoint: "/manual-enrichment-queue/\(queueId)",
            method: "DELETE"
        )
        return response.message
    }

    // MARK: - Duplicate Manager

    /// GET /api/admin/duplicates — groups of production duplicates (imdb/episode).
    func getDuplicateGroups() async throws -> DuplicateGroupsData {
        dlog("👯 [API] Fetching duplicate groups")
        let response: APIResponse<DuplicateGroupsData> = try await request(endpoint: "/duplicates")
        return response.data
    }

    /// POST /api/admin/duplicates/resolve — keep one movie, delete the rest of the group.
    /// Returns the deleted count and the backend message.
    func resolveDuplicateGroup(keepId: String, deleteIds: [String]) async throws -> (deleted: Int, message: String?) {
        struct Body: Codable {
            let keepId: String
            let deleteIds: [String]
        }
        dlog("👯 [API] Resolving duplicate group: keep \(keepId), delete \(deleteIds.count)")
        let response: APIResponse<DuplicateResolveData> = try await request(
            endpoint: "/duplicates/resolve",
            method: "POST",
            body: Body(keepId: keepId, deleteIds: deleteIds)
        )
        return (response.data.deleted, response.message)
    }

    // MARK: - Episode Matching

    /// GET /api/admin/tv-series/:id/episode-guide — nil when no guide is stored (404).
    func getEpisodeGuide(seriesId: String) async throws -> EpisodeGuideInfo? {
        do {
            let response: APIResponse<EpisodeGuideInfo> = try await request(
                endpoint: "/tv-series/\(seriesId)/episode-guide"
            )
            return response.data
        } catch APIError.server(let status, _) where status == 404 {
            return nil
        }
    }

    /// POST /api/admin/tv-series/:id/episode-guide — fetch + store the guide from TMDB.
    func fetchEpisodeGuideFromTMDB(seriesId: String, tmdbId: Int) async throws -> EpisodeGuideFetchResult {
        struct Body: Codable {
            let tmdbId: Int
        }
        dlog("📺 [API] Fetching episode guide for series \(seriesId) from TMDB \(tmdbId)")
        let response: APIResponse<EpisodeGuideFetchResult> = try await request(
            endpoint: "/tv-series/\(seriesId)/episode-guide",
            method: "POST",
            body: Body(tmdbId: tmdbId)
        )
        return response.data
    }

    /// POST /api/admin/channel-management/:channelId/match-episodes — DRY RUN, writes nothing.
    func matchEpisodes(channelId: String, seriesIds: [String]) async throws -> EpisodeMatchDryRunData {
        struct Body: Codable {
            let seriesIds: [String]
        }
        dlog("🔗 [API] Dry-run episode matching for channel \(channelId) (\(seriesIds.count) series)")
        let response: APIResponse<EpisodeMatchDryRunData> = try await request(
            endpoint: "/channel-management/\(channelId)/match-episodes",
            method: "POST",
            body: Body(seriesIds: seriesIds)
        )
        return response.data
    }

    /// POST /api/admin/channel-management/:channelId/confirm-episode-matches
    func confirmEpisodeMatches(channelId: String, matches: [EpisodeMatchConfirmation]) async throws -> EpisodeMatchConfirmData {
        struct Body: Codable {
            let matches: [EpisodeMatchConfirmation]
        }
        dlog("🔗 [API] Confirming \(matches.count) episode matches for channel \(channelId)")
        let response: APIResponse<EpisodeMatchConfirmData> = try await request(
            endpoint: "/channel-management/\(channelId)/confirm-episode-matches",
            method: "POST",
            body: Body(matches: matches)
        )
        return response.data
    }

    // MARK: - Review (below-threshold pick triage)

    /// GET /staging/movies?status=pending&filter=enriched&channel_id=…&page=N&limit=50
    /// Returns pending movies whose pick scored below the auto-approve threshold,
    /// including the original YouTube description backfill.
    func getReviewQueue(channelId: String? = nil, page: Int = 1, limit: Int = 50) async throws -> ReviewQueueData {
        var items = [
            URLQueryItem(name: "status", value: "pending"),
            URLQueryItem(name: "filter", value: "enriched"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let channelId, !channelId.isEmpty {
            items.append(URLQueryItem(name: "channel_id", value: channelId))
        }
        dlog("🗂️ [API] Fetching review queue: page=\(page), channel=\(channelId ?? "all")")
        let response: APIResponse<ReviewQueueData> = try await request(
            endpoint: endpointWithQuery("/staging/movies", items)
        )
        return response.data
    }

    /// POST /staging/movies/:id/approve — approves the current pick for publishing.
    @discardableResult
    func approveReviewMovie(movieId: String) async throws -> String? {
        dlog("✅ [API] Approving review movie \(movieId)")
        let response = try await requestBasic(endpoint: "/staging/movies/\(movieId)/approve", method: "POST")
        return response.message
    }

    /// POST /staging/movies/:id/reject { reason }
    @discardableResult
    func rejectReviewMovie(movieId: String, reason: String) async throws -> String? {
        struct Body: Codable { let reason: String }
        dlog("❌ [API] Rejecting review movie \(movieId)")
        let response = try await requestBasic(
            endpoint: "/staging/movies/\(movieId)/reject",
            method: "POST",
            body: Body(reason: reason)
        )
        return response.message
    }

    /// GET /staging/movies/:id/tmdb-candidates?q=<optional override>
    func getTmdbCandidates(movieId: String, query: String? = nil) async throws -> TmdbCandidatesData {
        var items: [URLQueryItem] = []
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        dlog("🔎 [API] Fetching TMDB candidates for \(movieId), q=\(query ?? "auto")")
        let response: APIResponse<TmdbCandidatesData> = try await request(
            endpoint: endpointWithQuery("/staging/movies/\(movieId)/tmdb-candidates", items)
        )
        return response.data
    }

    /// POST /staging/movies/:id/set-match { tmdbId } — re-picks the match and
    /// returns the updated movie row so the UI can refresh in place.
    func setReviewMatch(movieId: String, tmdbId: Int) async throws -> ReviewMovie {
        struct Body: Codable { let tmdbId: Int }
        dlog("🎯 [API] Setting match for \(movieId) → TMDB \(tmdbId)")
        let response: APIResponse<ReviewMovie> = try await request(
            endpoint: "/staging/movies/\(movieId)/set-match",
            method: "POST",
            body: Body(tmdbId: tmdbId)
        )
        return response.data
    }

    /// POST /staging/movies/:id/enrich-manual-imdb { imdbId } — applies a known
    /// IMDB id directly (OMDB fetch, marks the row manually_verified) and returns
    /// the updated movie row so the UI can refresh the pick in place.
    func enrichReviewMovieByImdb(movieId: String, imdbId: String) async throws -> ReviewMovie {
        struct Body: Codable { let imdbId: String }
        dlog("🎯 [API] Manual IMDB enrich for review movie \(movieId) → \(imdbId)")
        let response: APIResponse<ReviewMovie> = try await request(
            endpoint: "/staging/movies/\(movieId)/enrich-manual-imdb",
            method: "POST",
            body: Body(imdbId: imdbId)
        )
        return response.data
    }
}
