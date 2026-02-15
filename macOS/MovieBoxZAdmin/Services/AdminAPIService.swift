import Foundation

@MainActor
class AdminAPIService: ObservableObject {
    private let baseURL: String
    private let adminAPIKey: String

    init() {
        self.baseURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? ""
        self.adminAPIKey = UserDefaults.standard.string(forKey: "adminAPIKey") ?? ""

        print("🔧 [API] Initialized with base URL: \(baseURL)")
        print("🔑 [API] Admin API Key configured: \(adminAPIKey.isEmpty ? "NO" : "YES")")
    }

    // MARK: - Generic Request
    private func request<T: Codable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> APIResponse<T> {
        guard let url = URL(string: "\(baseURL)/api/admin\(endpoint)") else {
            print("❌ [API] Invalid URL: \(baseURL)/api/admin\(endpoint)")
            throw APIError.invalidURL
        }

        print("📡 [API] \(method) \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
                if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
                    print("📤 [API] Request body: \(bodyString)")
                }
            } catch {
                print("❌ [API] Failed to encode request body: \(error)")
                throw APIError.decodingError(error.localizedDescription)
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [API] Invalid response type")
                throw APIError.invalidResponse
            }

            print("📥 [API] Response status: \(httpResponse.statusCode)")

            if let responseString = String(data: data, encoding: .utf8) {
                // Log full response for channels endpoint to debug pattern loading
                if endpoint == "/channels" {
                    print("📥 [API] FULL CHANNELS Response:\n\(responseString)")
                } else {
                    print("📥 [API] Response body: \(responseString.prefix(500))...")
                }
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    print("❌ [API] Unauthorized - check API key")
                    throw APIError.unauthorized
                }
                print("❌ [API] HTTP error: \(httpResponse.statusCode)")
                throw APIError.httpError(httpResponse.statusCode)
            }

            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(APIResponse<T>.self, from: data)
                print("✅ [API] Successfully decoded response")

                // Extra logging for channels response
                if endpoint == "/channels" {
                    print("✅ [API] Decoded channels response successfully")
                }

                return result
            } catch {
                print("❌ [API] Decoding error: \(error)")
                if let decodingError = error as? DecodingError {
                    print("❌ [API] Decoding details: \(decodingError)")
                }
                throw APIError.decodingError(error.localizedDescription)
            }
        } catch let error as APIError {
            throw error
        } catch {
            print("❌ [API] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    // MARK: - Stats
    func getStats() async throws -> AdminStats {
        print("📊 [API] Fetching statistics...")
        let response: APIResponse<AdminStats> = try await request(endpoint: "/stats")
        print("✅ [API] Stats retrieved successfully")
        return response.data
    }

    // MARK: - Movies
    func getMovies(page: Int = 1, limit: Int = 50, search: String? = nil) async throws -> MoviesData {
        var endpoint = "?page=\(page)&limit=\(limit)"
        if let search = search, !search.isEmpty {
            endpoint += "&search=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search)"
        }

        guard let url = URL(string: "\(baseURL)/api/movies\(endpoint)") else {
            print("❌ [API] Invalid URL for movies endpoint")
            throw APIError.invalidURL
        }

        print("📡 [API] GET \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [API] Invalid response type")
                throw APIError.invalidResponse
            }

            print("📥 [API] Response status: \(httpResponse.statusCode)")

            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 [API] Response body: \(responseString.prefix(500))...")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    print("❌ [API] Unauthorized - check API key")
                    throw APIError.unauthorized
                }
                print("❌ [API] HTTP error: \(httpResponse.statusCode)")
                throw APIError.httpError(httpResponse.statusCode)
            }

            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(APIResponse<MoviesData>.self, from: data)
                print("✅ [API] Successfully decoded \(result.data.movies.count) movies")
                return result.data
            } catch {
                print("❌ [API] Decoding error: \(error)")
                if let decodingError = error as? DecodingError {
                    print("❌ [API] Decoding details: \(decodingError)")
                }
                throw APIError.decodingError(error.localizedDescription)
            }
        } catch let error as APIError {
            throw error
        } catch {
            print("❌ [API] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    // MARK: - Channels
    func getChannels(page: Int = 1, limit: Int = 50) async throws -> ChannelsData {
        print("📺 [API] Fetching channels...")

        guard let url = URL(string: "\(baseURL)/api/channels?page=\(page)&limit=\(limit)") else {
            print("❌ [API] Invalid URL for channels endpoint")
            throw APIError.invalidURL
        }

        print("📡 [API] GET \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [API] Invalid response type")
                throw APIError.invalidResponse
            }

            print("📥 [API] Response status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                print("❌ [API] HTTP error: \(httpResponse.statusCode)")
                throw APIError.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(APIResponse<ChannelsData>.self, from: data)
            print("✅ [API] Channels retrieved: \(result.data.channels.count)")
            return result.data
        } catch let error as APIError {
            throw error
        } catch {
            print("❌ [API] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    // MARK: - Genres
    func getGenres(page: Int = 1, limit: Int = 100) async throws -> GenresData {
        print("🎭 [API] Fetching genres...")

        guard let url = URL(string: "\(baseURL)/api/genres?page=\(page)&limit=\(limit)") else {
            print("❌ [API] Invalid URL for genres endpoint")
            throw APIError.invalidURL
        }

        print("📡 [API] GET \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [API] Invalid response type")
                throw APIError.invalidResponse
            }

            print("📥 [API] Response status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                print("❌ [API] HTTP error: \(httpResponse.statusCode)")
                throw APIError.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(APIResponse<GenresData>.self, from: data)
            print("✅ [API] Genres retrieved: \(result.data.genres.count)")
            return result.data
        } catch let error as APIError {
            throw error
        } catch {
            print("❌ [API] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    // MARK: - Staging Workflow

    /// Import movies from a YouTube channel to staging
    func importToStaging(channelId: String, channelTitle: String, limit: Int = 10, batchId: String? = nil) async throws -> ImportResponse {
        let endpoint = "/staging/import"
        let body = ImportRequest(channelId: channelId, channelTitle: channelTitle, limit: limit, batchId: batchId)

        print("📥 [API] Importing to staging: channel=\(channelTitle), limit=\(limit)")

        let response: APIResponse<ImportResponse> = try await request(endpoint: endpoint, method: "POST", body: body)
        print("✅ [API] Import completed: \(response.data.imported) imported, \(response.data.skipped) skipped")

        return response.data
    }

    /// Get staged movies with filtering and pagination
    func getStagedMovies(status: ApprovalStatus? = nil, filter: String? = nil, page: Int = 1, limit: Int = 50) async throws -> StagedMoviesData {
        var endpoint = "/staging/movies?page=\(page)&limit=\(limit)"

        if let status = status {
            endpoint += "&status=\(status.rawValue)"
        }

        if let filter = filter {
            endpoint += "&filter=\(filter)"
        }

        print("📋 [API] Fetching staged movies: status=\(status?.rawValue ?? "all"), filter=\(filter ?? "none")")

        let response: APIResponse<StagedMoviesData> = try await request(endpoint: endpoint, method: "GET")
        print("✅ [API] Found \(response.data.movies.count) staged movies")

        return response.data
    }

    /// Get staging area statistics
    func getStagingStats() async throws -> StagingStats {
        let endpoint = "/staging/stats"

        print("📊 [API] Fetching staging stats")

        let response: APIResponse<StagingStats> = try await request(endpoint: endpoint, method: "GET")
        print("✅ [API] Staging stats: \(response.data.pending) pending, \(response.data.enriched) enriched")

        return response.data
    }

    /// Preview enrichment for a staged movie (doesn't save)
    func previewEnrichment(movieId: String, priority: EnrichmentPriority = .full, fields: [String]? = nil, preferTmdb: Bool = true) async throws -> EnrichmentPreview {
        let endpoint = "/staging/movies/\(movieId)/preview-enrichment"
        let body = EnrichmentRequest(priority: priority, fields: fields, preferTmdb: preferTmdb, applyFromPreview: nil)

        print("🔍 [API] Previewing enrichment for movie \(movieId) with priority \(priority.rawValue)")

        let response: APIResponse<EnrichmentPreview> = try await request(endpoint: endpoint, method: "POST", body: body)
        print("✅ [API] Preview completed: confidence=\(response.data.confidence ?? 0), source=\(response.data.source ?? "none")")

        return response.data
    }

    /// Apply enrichment to a staged movie
    func applyEnrichment(movieId: String, priority: EnrichmentPriority = .full, fields: [String]? = nil, preferTmdb: Bool = true, applyFromPreview: Bool = false) async throws -> StagedMovie {
        let endpoint = "/staging/movies/\(movieId)/enrich"
        let body = EnrichmentRequest(priority: priority, fields: fields, preferTmdb: preferTmdb, applyFromPreview: applyFromPreview)

        print("✨ [API] Applying enrichment for movie \(movieId) with priority \(priority.rawValue)")

        let response: APIResponse<StagedMovie> = try await request(endpoint: endpoint, method: "POST", body: body)
        print("✅ [API] Enrichment applied successfully")

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

        print("🎯 [API] Manual IMDB enrichment for movie \(movieId) with IMDB \(imdbId)")

        let response: APIResponse<StagedMovie> = try await request(endpoint: endpoint, method: "POST", body: body)
        print("✅ [API] Manual IMDB enrichment successful - movie verified")

        return response.data
    }

    /// Clear all enrichment data - reset movie to unenriched state
    func clearEnrichment(movieId: String) async throws -> StagedMovie {
        let endpoint = "/staging/movies/\(movieId)/clear-enrichment"

        print("🗑️ [API] Clearing enrichment for movie \(movieId)")

        let response: APIResponse<StagedMovie> = try await request(endpoint: endpoint, method: "POST")
        print("✅ [API] Enrichment cleared successfully")

        return response.data
    }

    /// Start batch enrichment (async) - returns immediately with batch ID
    func batchEnrich(movieIds: [String], priority: EnrichmentPriority = .full) async throws -> BatchEnrichmentStartResponse {
        let endpoint = "/staging/batch-enrich"
        let body = BatchEnrichmentRequest(movieIds: movieIds, priority: priority.rawValue)

        print("📦 [API] Starting batch enrichment for \(movieIds.count) movies with priority \(priority.rawValue)")

        let response: APIResponse<BatchEnrichmentStartResponse> = try await request(endpoint: endpoint, method: "POST", body: body)
        print("✅ [API] Batch enrichment started: batchId=\(response.data.batchId), total=\(response.data.total)")

        return response.data
    }

    /// Get batch enrichment progress
    func getBatchEnrichmentProgress(batchId: String) async throws -> BatchEnrichmentProgress {
        let endpoint = "/staging/batch-enrich/\(batchId)/status"

        let response: APIResponse<BatchEnrichmentProgress> = try await request(endpoint: endpoint, method: "GET")

        if let percentage = response.data.percentage {
            print("📊 [API] Enrichment progress: \(percentage)% (\(response.data.enriched + response.data.failed + response.data.skipped)/\(response.data.total))")
        }

        return response.data
    }

    /// Update staged movie fields (manual editing)
    func updateStagedMovie(movieId: String, updates: [String: Any]) async throws -> StagedMovie {
        let endpoint = "/admin/staging/movies/\(movieId)"

        print("✏️ [API] Updating staged movie \(movieId) with \(updates.count) fields")

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
        print("✅ [API] Movie updated successfully")

        return response.data
    }

    /// Approve a staged movie for publishing
    func approveStagedMovie(movieId: String, notes: String? = nil) async throws -> StagedMovie {
        let endpoint = "/staging/movies/\(movieId)/approve"

        var body: [String: String] = [:]
        if let notes = notes {
            body["notes"] = notes
        }

        print("✅ [API] Approving staged movie \(movieId)")

        let response: APIResponse<StagedMovie> = try await request(endpoint: endpoint, method: "POST", body: body.isEmpty ? nil : body)
        print("✅ [API] Movie approved successfully")

        return response.data
    }

    /// Reject a staged movie
    func rejectStagedMovie(movieId: String, reason: String) async throws -> StagedMovie {
        let endpoint = "/staging/movies/\(movieId)/reject"
        let body = ["reason": reason]

        print("❌ [API] Rejecting staged movie \(movieId)")

        let response: APIResponse<StagedMovie> = try await request(endpoint: endpoint, method: "POST", body: body)
        print("✅ [API] Movie rejected successfully")

        return response.data
    }

    /// Publish approved staged movies to production
    func publishStagedMovies(movieIds: [String]? = nil) async throws -> PublishResponse {
        let endpoint = "/staging/publish"
        let body = PublishRequest(ids: movieIds)

        if let ids = movieIds {
            print("🚀 [API] Publishing \(ids.count) specific staged movies")
        } else {
            print("🚀 [API] Publishing all approved staged movies")
        }

        let response: APIResponse<PublishResponse> = try await request(endpoint: endpoint, method: "POST", body: body)
        print("✅ [API] Published \(response.data.published) movies, \(response.data.failed) failed")

        return response.data
    }

    /// Delete a staged movie
    func deleteStagedMovie(movieId: String) async throws {
        let endpoint = "/staging/movies/\(movieId)"

        print("🗑️ [API] Deleting staged movie \(movieId)")

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

        print("✅ [API] Movie deleted successfully")
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
        let endpoint = "/api/admin/channels/\(channelId)"

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

    // MARK: - Channel Management Advanced

    /// Get or create channel settings
    func getChannelSettings(channelId: String) async throws -> ChannelSettings {
        let endpoint = "/channel-management/\(channelId)/settings"

        print("⚙️ [API] Fetching channel settings for \(channelId)")

        let response: APIResponse<ChannelSettings> = try await request(endpoint: endpoint)
        print("✅ [API] Channel settings retrieved")

        return response.data
    }

    /// Update channel settings
    func updateChannelSettings(channelId: String, settings: ChannelSettings) async throws -> ChannelSettings {
        let endpoint = "/channel-management/\(channelId)/settings"

        print("💾 [API] Updating channel settings for \(channelId)")

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

        print("💾 [API] Duration filters - min: \(settings.minDurationMinutes?.description ?? "nil"), max: \(settings.maxDurationMinutes?.description ?? "nil"), filterShorts: \(settings.filterShorts)")

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
        print("✅ [API] Channel settings updated successfully")

        return response.data
    }

    /// Import all or limited videos from a channel to staging
    func importAllVideos(channelId: String, request: BulkImportRequest) async throws -> BulkImportResponse {
        let endpoint = "/channel-management/\(channelId)/import-all"

        print("📥 [API] Starting bulk import for channel \(channelId)")
        if let limit = request.limit {
            print("📥 [API] Import limit: \(limit) videos, sort: \(request.sortOrder)")
        } else {
            print("📥 [API] Importing all videos, sort: \(request.sortOrder)")
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
        print("✅ [API] Bulk import started: batchId=\(response.data.batchId), status=\(response.data.status)")

        return response.data
    }

    /// Get real-time import progress
    func getImportProgress(batchId: String) async throws -> ImportProgress {
        let endpoint = "/channel-management/imports/\(batchId)/status"

        let response: APIResponse<ImportProgress> = try await request(endpoint: endpoint)

        if let percentage = response.data.percentage {
            print("📊 [API] Import progress: \(percentage)% (\(response.data.imported + response.data.skipped + response.data.failed)/\(response.data.found))")
        }

        return response.data
    }

    /// Delete all movies from a channel
    func deleteChannelMovies(channelId: String, deleteFrom: String = "staging,production") async throws -> BatchDeleteResponse {
        let endpoint = "/channel-management/\(channelId)/movies?deleteFrom=\(deleteFrom)"

        print("🗑️ [API] Deleting channel movies from: \(deleteFrom)")

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
        print("✅ [API] Deleted: \(response.data.deletedFromStaging) from staging, \(response.data.deletedFromProduction) from production")

        return response.data
    }

    /// Re-import channel (delete existing and import fresh)
    func reimportChannel(channelId: String, deleteExisting: Bool = true, limit: Int? = nil, applySettings: Bool = true) async throws -> BulkImportResponse {
        let endpoint = "/channel-management/\(channelId)/reimport"

        print("🔄 [API] Re-importing channel \(channelId)")
        if deleteExisting {
            print("🗑️ [API] Will delete existing movies first")
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
        print("✅ [API] Re-import started: batchId=\(response.data.batchId)")

        return response.data
    }

    /// Get channel movies from staging and/or production
    func getChannelMovies(channelId: String, source: String = "staging,production", page: Int = 1, limit: Int = 50) async throws -> ChannelMoviesData {
        let endpoint = "/channel-management/\(channelId)/movies?source=\(source)&page=\(page)&limit=\(limit)"

        print("📋 [API] Fetching channel movies: source=\(source), page=\(page)")

        let response: APIResponse<ChannelMoviesData> = try await request(endpoint: endpoint)

        if let staging = response.data.staging {
            print("✅ [API] Found \(staging.movies.count) staged movies (total: \(staging.total))")
        }
        if let production = response.data.production {
            print("✅ [API] Found \(production.movies.count) production movies (total: \(production.total))")
        }

        return response.data
    }

    /// Get import history for a channel
    func getImportHistory(channelId: String, limit: Int = 20) async throws -> ImportHistoryData {
        let endpoint = "/channel-management/\(channelId)/import-history?limit=\(limit)"

        print("📜 [API] Fetching import history for channel \(channelId)")

        let response: APIResponse<ImportHistoryData> = try await request(endpoint: endpoint)
        print("✅ [API] Found \(response.data.imports.count) import records")

        return response.data
    }
}
