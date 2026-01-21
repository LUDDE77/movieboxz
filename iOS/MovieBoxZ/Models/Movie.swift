import Foundation

struct Movie: Codable, Identifiable {
    let id: String
    let youtubeVideoId: String
    let title: String
    let originalTitle: String?
    let description: String?
    let releaseDate: Date?
    let runtimeMinutes: Int?

    // Channel information (YouTube compliance)
    let channelId: String
    let channelTitle: String
    let channelThumbnail: String?

    // Statistics
    let viewCount: Int
    let likeCount: Int?
    let commentCount: Int?
    let publishedAt: Date?

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
        case channelId = "channel_id"
        case channelTitle = "channel_title"
        case channelThumbnail = "channel_thumbnail"
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
    var posterURL: URL? {
        // Try TMDB poster first
        if let posterPath = posterPath {
            return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
        }
        // Fallback to YouTube thumbnail (high quality)
        return URL(string: "https://img.youtube.com/vi/\(youtubeVideoId)/hqdefault.jpg")
    }

    var backdropURL: URL? {
        // Try TMDB backdrop first
        if let backdropPath = backdropPath {
            return URL(string: "https://image.tmdb.org/t/p/original\(backdropPath)")
        }
        // Fallback to YouTube thumbnail (max quality)
        return URL(string: "https://img.youtube.com/vi/\(youtubeVideoId)/maxresdefault.jpg")
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
}

struct Genre: Codable, Identifiable {
    let id: Int
    let name: String
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
