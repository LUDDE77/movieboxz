import Foundation

struct Movie: Codable, Identifiable {
    let id: String
    let youtubeVideoId: String

    // TMDB Metadata (Primary Display)
    let title: String
    let originalTitle: String?
    let description: String?
    let releaseDate: Date?
    let runtimeMinutes: Int?

    // YouTube Metadata (Required for TOS Compliance)
    let youtubeVideoTitle: String  // Original YouTube video title (REQUIRED)
    let channelId: String
    let channelTitle: String
    let channelThumbnail: String?

    // YouTube Statistics
    let viewCount: Int
    let likeCount: Int?
    let commentCount: Int?
    let publishedAt: Date?

    // Cache Management
    let lastRefreshed: Date?

    // TMDB metadata
    let tmdbId: Int?
    let imdbId: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?

    // App metadata
    let category: String?
    let quality: String?
    let featured: Bool
    let trending: Bool
    let isAvailable: Bool
    let isEmbeddable: Bool

    // Genres
    let genres: [Genre]?

    // Timestamps
    let addedAt: Date
    let lastValidated: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case youtubeVideoId = "youtube_video_id"
        case title
        case originalTitle = "original_title"
        case description
        case releaseDate = "release_date"
        case runtimeMinutes = "runtime_minutes"
        case youtubeVideoTitle = "youtube_video_title"
        case channelId = "channel_id"
        case channelTitle = "channel_title"
        case channelThumbnail = "channel_thumbnail"
        case viewCount = "view_count"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case publishedAt = "published_at"
        case lastRefreshed = "last_refreshed"
        case tmdbId = "tmdb_id"
        case imdbId = "imdb_id"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case category
        case quality
        case featured
        case trending
        case isAvailable = "is_available"
        case isEmbeddable = "is_embeddable"
        case genres
        case addedAt = "added_at"
        case lastValidated = "last_validated"
    }

    // Computed properties for UI

    /// Display title with fallback logic
    /// Uses TMDB title if available, falls back to YouTube video title if TMDB title is empty
    var displayTitle: String {
        let tmdbTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if tmdbTitle.isEmpty {
            return youtubeVideoTitle
        }
        return tmdbTitle
    }

    var posterURL: URL? {
        // Try TMDB/OMDb poster first (clean, professional)
        if let posterPath = posterPath {
            // Check if it's already a full URL (OMDb format)
            if posterPath.starts(with: "http://") || posterPath.starts(with: "https://") {
                return URL(string: posterPath)
            }
            // Otherwise, it's a TMDB relative path - prepend base URL
            return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
        }
        // Fallback to YouTube thumbnail
        return youtubeThumbURL
    }

    var backdropURL: URL? {
        // Try TMDB/OMDb backdrop first (clean, professional)
        if let backdropPath = backdropPath {
            // Check if it's already a full URL (OMDb format)
            if backdropPath.starts(with: "http://") || backdropPath.starts(with: "https://") {
                return URL(string: backdropPath)
            }
            // Otherwise, it's a TMDB relative path - prepend base URL
            return URL(string: "https://image.tmdb.org/t/p/original\(backdropPath)")
        }
        // Fallback to YouTube thumbnail (max quality)
        return URL(string: "https://img.youtube.com/vi/\(youtubeVideoId)/maxresdefault.jpg")
    }

    var youtubeThumbURL: URL {
        // Direct YouTube thumbnail (for attribution section)
        URL(string: "https://img.youtube.com/vi/\(youtubeVideoId)/hqdefault.jpg")!
    }

    var youtubeURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(youtubeVideoId)")
    }

    var youtubeAppURL: URL? {
        URL(string: "youtube://www.youtube.com/watch?v=\(youtubeVideoId)")
    }

    var channelURL: URL? {
        URL(string: "https://www.youtube.com/channel/\(channelId)")
    }

    var formattedRuntime: String {
        guard let runtime = runtimeMinutes else { return "N/A" }
        let hours = runtime / 60
        let minutes = runtime % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedRating: String {
        guard let rating = voteAverage else { return "N/A" }
        return String(format: "%.1f", rating)
    }

    var formattedReleaseYear: String? {
        guard let releaseDate = releaseDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: releaseDate)
    }

    var formattedViewCount: String {
        if viewCount >= 1_000_000 {
            return String(format: "%.1fM views", Double(viewCount) / 1_000_000)
        } else if viewCount >= 1_000 {
            return String(format: "%.1fK views", Double(viewCount) / 1_000)
        } else {
            return "\(viewCount) views"
        }
    }

    // Cache Management
    var needsRefresh: Bool {
        guard let lastRefreshed = lastRefreshed else { return true }
        let hoursSinceRefresh = Date().timeIntervalSince(lastRefreshed) / 3600
        return hoursSinceRefresh > 24 // Refresh after 24 hours
    }
}

struct Genre: Codable, Identifiable {
    let id: Int
    let name: String
    let tmdbId: Int?
    let movieCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tmdbId = "tmdb_id"
        case movieCount = "movie_count"
    }
}

// API Response structures
struct MoviesResponse: Codable {
    let success: Bool
    let data: MoviesData
    let message: String?
}

struct MoviesData: Codable {
    let movies: [Movie]
    let pagination: Pagination?
    let total: Int?
}

struct Pagination: Codable {
    let page: Int
    let limit: Int
    let total: Int?
    let pages: Int?
}

// Genre API Response structures
struct GenresResponse: Codable {
    let success: Bool
    let data: GenresData
    let message: String?
}

struct GenresData: Codable {
    let genres: [Genre]
}

struct GenreMoviesResponse: Codable {
    let success: Bool
    let data: GenreMoviesData
    let message: String?
}

struct GenreMoviesData: Codable {
    let genre: Genre
    let movies: [Movie]
    let pagination: Pagination
}
