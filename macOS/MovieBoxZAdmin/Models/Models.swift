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
    let posterPath: String?
    let backdropPath: String?
    let enrichmentSource: String?
    let featured: Bool?
    let trending: Bool?
    let staffPick: Bool?
    let addedAt: String?
    let lastValidated: String?

    enum CodingKeys: String, CodingKey {
        case id
        case youtubeVideoId = "youtube_video_id"
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
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case enrichmentSource = "enrichment_source"
        case featured
        case trending
        case staffPick = "staff_pick"
        case addedAt = "added_at"
        case lastValidated = "last_validated"
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
}

// Enrichment priority modes
enum EnrichmentPriority: String, Codable, CaseIterable {
    case posterOnly = "poster-only"
    case basic = "basic"
    case standard = "standard"
    case full = "full"

    var displayName: String {
        switch self {
        case .posterOnly: return "Poster Only"
        case .basic: return "Basic (Poster + Genres)"
        case .standard: return "Standard (+ Plot & Date)"
        case .full: return "Full Enrichment"
        }
    }
}

// Staged movie (mirrors production Movie with staging fields)
struct StagedMovie: Codable, Identifiable {
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
}

// Helper type for JSONB fields
struct AnyCodable: Codable {
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

// Publish request
struct PublishRequest: Codable {
    let ids: [String]?
}

// Publish response
struct PublishResponse: Codable {
    let published: Int
    let failed: Int
    let movieIds: [String]?

    enum CodingKeys: String, CodingKey {
        case published
        case failed
        case movieIds = "movieIds"
    }
}
