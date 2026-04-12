import Foundation

// MARK: - API Response
struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T
    let message: String?
}

// MARK: - Admin Stats
struct AdminStats: Codable {
    let totalMovies: Int
    let availableMovies: Int
    let totalChannels: Int
    let totalGenres: Int
    let enrichedMovies: Int
    let pendingEnrichment: Int
    let recentlyAdded: Int
    let lastCuration: String?

    enum CodingKeys: String, CodingKey {
        case totalMovies = "total_movies"
        case availableMovies = "available_movies"
        case totalChannels = "total_channels"
        case totalGenres = "total_genres"
        case enrichedMovies = "enriched_movies"
        case pendingEnrichment = "pending_enrichment"
        case recentlyAdded = "recently_added"
        case lastCuration = "last_curation"
    }
}

// MARK: - Movie
struct Movie: Codable, Identifiable {
    let id: String
    let youtubeVideoId: String
    let youtubeVideoTitle: String
    let title: String
    let originalTitle: String?
    let channelTitle: String?
    let releaseDate: String?
    let runtimeMinutes: Int?
    let imdbRating: Double?
    let imdbVotes: Int?
    let genres: [Genre]
    let tmdbId: Int?
    let imdbId: String?
    let isAvailable: Bool
    let viewCount: Int
    let likeCount: Int
    let commentCount: Int?
    let createdAt: String
    let updatedAt: String?
    let publishedAt: String?
    let description: String?
    let category: String?
    let quality: String?
    let language: String?
    let rated: String?
    let director: String?
    let actors: String?
    let country: String?
    let isTvShow: Bool?
    let isTvSeries: Bool?
    let tvSeriesId: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let seriesType: String?
    let isKidsContent: Bool?
    let posterPath: String?
    let backdropPath: String?
    let enrichmentSource: String?
    let featured: Bool?
    let featuredOrder: Int?
    let trending: Bool?
    let staffPick: Bool?
    let addedAt: String?
    let lastValidated: String?
    let needsVerification: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case youtubeVideoId = "youtube_video_id"
        case youtubeVideoTitle = "youtube_video_title"
        case title
        case originalTitle = "original_title"
        case channelTitle = "channel_title"
        case releaseDate = "release_date"
        case runtimeMinutes = "runtime_minutes"
        case imdbRating = "imdb_rating"
        case imdbVotes = "imdb_votes"
        case genres
        case tmdbId = "tmdb_id"
        case imdbId = "imdb_id"
        case isAvailable = "is_available"
        case viewCount = "view_count"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case publishedAt = "published_at"
        case description
        case category
        case quality
        case language
        case rated
        case director
        case actors
        case country
        case isTvShow = "is_tv_show"
        case isTvSeries = "is_tv_series"
        case tvSeriesId = "tv_series_id"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case seriesType = "series_type"
        case isKidsContent = "is_kids_content"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case enrichmentSource = "enrichment_source"
        case featured
        case featuredOrder = "featured_order"
        case trending
        case staffPick = "staff_pick"
        case addedAt = "added_at"
        case lastValidated = "last_validated"
        case needsVerification = "needs_verification"
    }

    // Computed properties for display
    var displayTitle: String { title }
    var releaseYear: Int? {
        guard let releaseDate = releaseDate else { return nil }
        return Int(releaseDate.prefix(4))
    }
    var runtime: Int? { runtimeMinutes }
    var rating: Double? { imdbRating }
    var status: String { isAvailable ? "available" : "unavailable" }
    var youtubeURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(youtubeVideoId)")
    }
}

// MARK: - Featured Movie (lightweight, for featured carousel management)
struct FeaturedMovieItem: Codable, Identifiable {
    let id: String
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let featuredOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case featuredOrder = "featured_order"
    }

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
    }
}

// MARK: - Genre
struct Genre: Codable, Identifiable, Hashable {
    let id: Int
    let tmdbId: Int?
    let name: String
    let movieCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case tmdbId = "tmdb_id"
        case name
        case movieCount = "movie_count"
    }
}

// MARK: - Channel
struct Channel: Codable, Identifiable {
    let id: String
    let title: String
    let movieCount: Int
    let lastCurated: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case movieCount = "movie_count"
        case lastCurated = "last_curated"
    }
}

// MARK: - Channel Pattern Configuration

struct ChannelPattern: Codable, Identifiable, Hashable {
    let id: String
    let channelId: String
    let channelName: String
    let patterns: [PatternRule]
    let fallbackPattern: FallbackPattern?
    let isActive: Bool
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case channelId = "channel_id"
        case channelName = "channel_name"
        case patterns
        case fallbackPattern = "fallback_pattern"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PatternRule: Codable, Identifiable, Hashable {
    let regex: String
    let parameters: [String: PatternParameter]

    var id: String { regex }
}

enum PatternParameter: Codable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "PatternParameter must be Int or String")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

struct FallbackPattern: Codable, Hashable {
    let type: String
    let divider: String?
}

struct ChannelWithPattern: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let thumbnailUrl: String?
    let subscriberCount: Int?
    let videoCount: Int?
    let isCurated: Bool
    let hasPattern: Bool?
    let pattern: ChannelPattern?
    // Content type classification
    let hasMovies: Bool
    let hasSeries: Bool
    let hasKidsContent: Bool
    // Pattern source
    let patternSource: String
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case thumbnailUrl = "thumbnail_url"
        case subscriberCount = "subscriber_count"
        case videoCount = "video_count"
        case isCurated = "is_curated"
        case hasPattern = "has_pattern"
        case pattern
        case hasMovies = "has_movies"
        case hasSeries = "has_series"
        case hasKidsContent = "has_kids_content"
        case patternSource = "pattern_source"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChannelsWithPatternsData: Codable {
    let channels: [ChannelWithPattern]
    let total: Int
}

struct PatternTestResult: Codable {
    let youtubeTitle: String
    let extracted: ExtractedMetadata
    let matched: Bool
}

struct ExtractedMetadata: Codable {
    let title: String?
    let actors: String?
    let actorsArray: [String]?
    let genre: String?
    let year: Int?
    let patternMatched: Bool?
    let confidence: Double?
    let rawTitle: String?
    let error: String?
}

struct PatternTestData: Codable {
    let results: [PatternTestResult]
    let matchRate: String
    let matched: Int
    let total: Int
}

// MARK: - TV Series
struct TvSeries: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let imdbId: String?
    let description: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let isAvailable: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case imdbId = "imdb_id"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case isAvailable = "is_available"
        case createdAt = "created_at"
    }
}

struct TvSeriesListData: Codable {
    let series: [TvSeries]
    let total: Int
}

// Admin TV content response
struct TVContentData: Codable {
    let movies: [Movie]
    let total: Int
}

// MARK: - Pagination
struct Pagination: Codable {
    let page: Int
    let limit: Int
    let total: Int?
    let pages: Int?
}

// MARK: - Movies Data
struct MoviesData: Codable {
    let movies: [Movie]
    let pagination: Pagination
}

// MARK: - Channels Data
struct ChannelsData: Codable {
    let channels: [Channel]
    let pagination: Pagination
}

// MARK: - Genres Data
struct GenresData: Codable {
    let genres: [Genre]
    let pagination: Pagination
}

// MARK: - API Error
enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(String)
    case networkError(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized: Invalid API key"
        }
    }
}

// MARK: - Staging Workflow Models

// Approval status for staged movies
enum ApprovalStatus: String, Codable {
    case pending
    case approved
    case rejected
    case publishing
    case published
}

// Enrichment priority modes
enum EnrichmentPriority: String, Codable, CaseIterable {
    case poster = "poster"
    case posterOnly = "poster-only"
    case basic = "basic"
    case standard = "standard"
    case full = "full"

    var displayName: String {
        switch self {
        case .poster: return "Poster Only"
        case .posterOnly: return "Poster Only (Legacy)"
        case .basic: return "Basic (Poster + Genres)"
        case .standard: return "Standard (+ Plot & Date)"
        case .full: return "Full Enrichment"
        }
    }
}

// Staged movie (mirrors production Movie with staging fields)
struct StagedMovie: Codable, Identifiable, Hashable {
    let id: String
    let youtubeVideoId: String
    let youtubeVideoTitle: String
    let title: String
    let originalTitle: String?
    let description: String?
    let releaseDate: String?
    let runtimeMinutes: Int?
    let channelId: String
    let channelTitle: String?
    let viewCount: Int?
    let likeCount: Int?
    let commentCount: Int?
    let publishedAt: String?
    let tmdbId: Int?
    let imdbId: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let imdbRating: Double?
    let imdbVotes: Int?
    let rated: String?
    let director: String?
    let actors: String?
    let language: String?
    let country: String?
    let isTvShow: Bool?
    let category: String?
    let enrichmentSource: String?
    let enrichmentConfidence: Double?

    // Manual IMDB override fields
    let manualImdbId: String?
    let manuallyVerified: Bool?
    let verifiedBy: String?
    let verifiedAt: String?

    // Staging-specific fields
    let enrichmentPreview: [String: AnyCodable]?
    let manualChanges: [String: AnyCodable]?
    let approvalStatus: ApprovalStatus
    let approvedBy: String?
    let approvedAt: String?
    let rejectedReason: String?
    let notes: String?
    let importBatchId: String?
    let publishedMovieId: String?
    let createdAt: String
    let updatedAt: String?

    // Pattern extraction fields
    let patternMatched: Bool?
    let patternConfidence: Double?
    let extractedActor: String?
    let extractedGenre: String?
    let extractedYear: Int?
    let importSortOrder: String?
    let importIndex: Int?
    let channelTag: String?
    var isTvSeries: Bool?
    var tvSeriesId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case youtubeVideoId = "youtube_video_id"
        case youtubeVideoTitle = "youtube_video_title"
        case title
        case originalTitle = "original_title"
        case description
        case releaseDate = "release_date"
        case runtimeMinutes = "runtime_minutes"
        case channelId = "channel_id"
        case channelTitle = "channel_title"
        case viewCount = "view_count"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case publishedAt = "published_at"
        case tmdbId = "tmdb_id"
        case imdbId = "imdb_id"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case imdbRating = "imdb_rating"
        case imdbVotes = "imdb_votes"
        case rated
        case director
        case actors
        case language
        case country
        case isTvShow = "is_tv_show"
        case category
        case enrichmentSource = "enrichment_source"
        case enrichmentConfidence = "enrichment_confidence"
        case manualImdbId = "manual_imdb_id"
        case manuallyVerified = "manually_verified"
        case verifiedBy = "verified_by"
        case verifiedAt = "verified_at"
        case enrichmentPreview = "enrichment_preview"
        case manualChanges = "manual_changes"
        case approvalStatus = "approval_status"
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
        case rejectedReason = "rejected_reason"
        case notes
        case importBatchId = "import_batch_id"
        case publishedMovieId = "published_movie_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case patternMatched = "pattern_matched"
        case patternConfidence = "pattern_confidence"
        case extractedActor = "extracted_actor"
        case extractedGenre = "extracted_genre"
        case extractedYear = "extracted_year"
        case importSortOrder = "import_sort_order"
        case importIndex = "import_index"
        case channelTag = "channel_tag"
        case isTvSeries = "is_tv_series"
        case tvSeriesId = "tv_series_id"
    }

    // Computed properties
    var hasEnrichment: Bool {
        tmdbId != nil || imdbId != nil
    }

    var enrichmentStatus: String {
        if let source = enrichmentSource {
            return source.uppercased()
        }
        return "None"
    }

    var youtubeURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(youtubeVideoId)")
    }

    var youtubeThumbnailURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(youtubeVideoId)/hqdefault.jpg")
    }
}

// Helper type for JSONB fields
struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        switch value {
        case let int as Int:
            hasher.combine(int)
        case let double as Double:
            hasher.combine(double)
        case let string as String:
            hasher.combine(string)
        case let bool as Bool:
            hasher.combine(bool)
        default:
            hasher.combine(0) // Default hash for complex types
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case let (lInt as Int, rInt as Int):
            return lInt == rInt
        case let (lDouble as Double, rDouble as Double):
            return lDouble == rDouble
        case let (lString as String, rString as String):
            return lString == rString
        case let (lBool as Bool, rBool as Bool):
            return lBool == rBool
        default:
            return false // Complex types default to not equal
        }
    }
}

// Enrichment preview result
struct EnrichmentPreview: Codable {
    let success: Bool
    let confidence: Double?
    let source: String?
    let preview: [String: AnyCodable]?
    let fieldsEnriched: [String]?
    let fieldsSkipped: [String]?
    let message: String?
    let metadata: EnrichmentMetadata?
}

// Enrichment metadata
struct EnrichmentMetadata: Codable {
    let tmdbId: Int?
    let imdbId: String?
    let title: String?
    let actorMatch: Bool?
    let matchedVariation: String?

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case imdbId = "imdb_id"
        case title
        case actorMatch = "actor_match"
        case matchedVariation = "matched_variation"
    }
}

// Staging stats
struct StagingStats: Codable {
    let totalStaged: Int
    let pending: Int
    let enriched: Int
    let unenriched: Int
    let approved: Int
    let rejected: Int

    enum CodingKeys: String, CodingKey {
        case totalStaged = "total_staged"
        case pending
        case enriched
        case unenriched
        case approved
        case rejected
    }
}

// Staged movies data with pagination
struct StagedMoviesData: Codable {
    let movies: [StagedMovie]
    let pagination: Pagination
}

// Import request
struct ImportRequest: Codable {
    let channelId: String
    let channelTitle: String
    let limit: Int
    let batchId: String?

    enum CodingKeys: String, CodingKey {
        case channelId = "channelId"
        case channelTitle = "channelTitle"
        case limit
        case batchId = "batchId"
    }
}

// Import response
struct ImportResponse: Codable {
    let imported: Int
    let skipped: Int
    let batchId: String?
    let movies: [StagedMovie]?

    enum CodingKeys: String, CodingKey {
        case imported
        case skipped
        case batchId = "batchId"
        case movies
    }
}

// Enrichment request
struct EnrichmentRequest: Codable {
    let priority: EnrichmentPriority
    let fields: [String]?
    let preferTmdb: Bool
    let applyFromPreview: Bool?

    enum CodingKeys: String, CodingKey {
        case priority
        case fields
        case preferTmdb = "preferTmdb"
        case applyFromPreview = "applyFromPreview"
    }
}

// Batch enrichment request
struct BatchEnrichmentRequest: Codable {
    let movieIds: [String]
    let priority: String

    enum CodingKeys: String, CodingKey {
        case movieIds
        case priority
    }
}

// Batch enrichment result
struct BatchEnrichmentResult: Codable {
    let total: Int
    let enriched: Int
    let failed: Int
    let skipped: Int
    let details: [BatchEnrichmentDetail]

    enum CodingKeys: String, CodingKey {
        case total
        case enriched
        case failed
        case skipped
        case details
    }
}

// Batch enrichment detail
struct BatchEnrichmentDetail: Codable {
    let movieId: String
    let title: String?
    let success: Bool
    let source: String?
    let confidence: Int?
    let fieldsEnriched: Int?
    let skipped: Bool?
    let reason: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case movieId
        case title
        case success
        case source
        case confidence
        case fieldsEnriched
        case skipped
        case reason
        case error
    }
}

// Batch enrichment start response
struct BatchEnrichmentStartResponse: Codable {
    let batchId: String
    let status: String
    let total: Int
}

// Batch enrichment progress
struct BatchEnrichmentProgress: Codable {
    let status: String
    let total: Int
    let enriched: Int
    let failed: Int
    let skipped: Int
    let current: String?
    let currentIndex: Int
    let percentage: Int?
    let startedAt: String?
    let completedAt: String?
}

// Publish request
struct PublishRequest: Codable {
    let ids: [String]?
}

// Publish error detail
struct PublishErrorDetail: Codable {
    let movieId: String
    let movieTitle: String?
    let error: String?
    let errorCode: String?
    let errorDetails: String?
}

// Publish response
struct PublishResponse: Codable {
    let published: Int
    let failed: Int
    let movieIds: [String]?
    let errors: [PublishErrorDetail]?

    enum CodingKeys: String, CodingKey {
        case published
        case failed
        case movieIds = "movieIds"
        case errors
    }
}

// MARK: - Channel Management Models

// Channel Settings
struct ChannelSettings: Codable, Identifiable, Hashable {
    var id: String { channelId }
    let channelId: String
    var autoImportEnabled: Bool
    var autoImportSchedule: String
    var importLimit: Int?
    var importSortOrder: String
    var defaultEnrichmentPriority: String
    var autoEnrichOnImport: Bool
    var autoApproveThreshold: Double?
    var requireManualReview: Bool
    var channelTag: String?
    var isFeatured: Bool
    var qualityTier: String
    var minDurationMinutes: Int?
    var maxDurationMinutes: Int?
    var filterShorts: Bool
    var isKidsContent: Bool
    var isTvSeriesChannel: Bool
    let lastImportAt: String?
    let totalImported: Int
    let totalPublished: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
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
        case isKidsContent = "is_kids_content"
        case isTvSeriesChannel = "is_tv_series_channel"
        case lastImportAt = "last_import_at"
        case totalImported = "total_imported"
        case totalPublished = "total_published"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChannelSettingsData: Codable {
    let settings: ChannelSettings
}

// Import History
struct ImportHistory: Codable, Identifiable, Hashable {
    let id: String
    let channelId: String
    let importType: String
    let importLimit: Int?
    let sortOrder: String?
    let videosFound: Int
    let videosImported: Int
    let videosSkipped: Int
    let videosFailed: Int
    let status: String
    let errorMessage: String?
    let startedAt: String
    let completedAt: String?
    let durationSeconds: Int?
    let currentVideoTitle: String?
    let currentVideoIndex: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case channelId = "channel_id"
        case importType = "import_type"
        case importLimit = "import_limit"
        case sortOrder = "sort_order"
        case videosFound = "videos_found"
        case videosImported = "videos_imported"
        case videosSkipped = "videos_skipped"
        case videosFailed = "videos_failed"
        case status
        case errorMessage = "error_message"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationSeconds = "duration_seconds"
        case currentVideoTitle = "current_video_title"
        case currentVideoIndex = "current_video_index"
    }
    
    var statusEmoji: String {
        switch status {
        case "completed": return "✅"
        case "failed": return "❌"
        case "running": return "⏳"
        case "cancelled": return "🚫"
        default: return "⏸️"
        }
    }
    
    var formattedDuration: String {
        guard let seconds = durationSeconds else { return "—" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes)m \(remainingSeconds)s"
    }
}

struct ImportHistoryData: Codable {
    let imports: [ImportHistory]
    let total: Int
}

// Import Progress
struct ImportProgress: Codable {
    let status: String
    let found: Int
    let imported: Int
    let skipped: Int
    let failed: Int
    let current: String?
    let currentIndex: Int?
    let channelTitle: String?
    let percentage: Int?
    
    enum CodingKeys: String, CodingKey {
        case status
        case found
        case imported
        case skipped
        case failed
        case current
        case currentIndex
        case channelTitle
        case percentage
    }
}

// Bulk Import Request/Response
struct BulkImportRequest: Codable {
    let limit: Int?
    let sortOrder: String
    let applySettings: Bool
    let autoEnrich: Bool?
    
    enum CodingKeys: String, CodingKey {
        case limit
        case sortOrder
        case applySettings
        case autoEnrich
    }
}

struct BulkImportResponse: Codable {
    let batchId: String
    let status: String
    let message: String
    
    enum CodingKeys: String, CodingKey {
        case batchId
        case status
        case message
    }
}

// Channel Movies
struct ChannelMoviesData: Codable {
    let staging: MovieList?
    let production: MovieList?
    let pagination: Pagination?
    
    struct MovieList: Codable {
        let movies: [StagedMovie]
        let total: Int
    }
}

// Batch Delete Response
struct BatchDeleteResponse: Codable {
    let deletedFromStaging: Int
    let deletedFromProduction: Int
    
    enum CodingKeys: String, CodingKey {
        case deletedFromStaging
        case deletedFromProduction
    }
}

// Sort Order Options
enum ImportSortOrder: String, CaseIterable {
    case latest = "latest"
    case oldest = "oldest"
    case alphabeticalAZ = "alphabetical_az"
    case alphabeticalZA = "alphabetical_za"
    case views = "views"
    
    var displayName: String {
        switch self {
        case .latest: return "Latest uploaded (newest first)"
        case .oldest: return "Oldest uploaded (oldest first)"
        case .alphabeticalAZ: return "Alphabetical (A-Z)"
        case .alphabeticalZA: return "Alphabetical (Z-A)"
        case .views: return "Most viewed"
        }
    }
}

// Quality Tier Options
enum QualityTier: String, CaseIterable {
    case premium = "premium"
    case standard = "standard"
    case basic = "basic"
    
    var displayName: String {
        switch self {
        case .premium: return "Premium"
        case .standard: return "Standard"
        case .basic: return "Basic"
        }
    }
}
