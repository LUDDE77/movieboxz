import SwiftUI

// MARK: - Genre

struct Genre: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let tmdbId: Int?
    let movieCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case tmdbId = "tmdb_id"
        case movieCount = "movie_count"
    }
}

// MARK: - Movie

struct Movie: Codable, Identifiable, Hashable {
    let id: String
    let youtubeVideoId: String
    let title: String?
    let originalTitle: String?
    let description: String?
    let releaseDate: Date?
    let runtimeMinutes: Int?

    // YouTube (TOS required fields)
    let youtubeVideoTitle: String?
    let channelId: String
    let channelTitle: String
    let channelThumbnail: String?
    let viewCount: Int?
    let likeCount: Int?
    let commentCount: Int?
    let publishedAt: Date?
    let lastRefreshed: Date?

    // TMDB metadata
    let tmdbId: Int?
    let imdbId: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?

    // OMDb metadata
    let imdbRating: Double?
    let rated: String?

    // App metadata
    let category: String?
    let quality: String?
    let featured: Bool?
    let trending: Bool?
    let isAvailable: Bool?
    let isEmbeddable: Bool?

    let genres: [Genre]?
    let addedAt: Date?
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
        case imdbRating = "imdb_rating"
        case rated
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

    // MARK: - Computed

    var displayTitle: String {
        title ?? youtubeVideoTitle ?? "Unknown Title"
    }

    var posterURL: URL? {
        if let path = posterPath {
            if path.hasPrefix("http") {
                return URL(string: path)
            }
            return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
        }
        return youtubeThumbURL
    }

    var backdropURL: URL? {
        if let path = backdropPath {
            return URL(string: "https://image.tmdb.org/t/p/w1280\(path)")
        }
        return URL(string: "https://img.youtube.com/vi/\(youtubeVideoId)/hqdefault.jpg")
    }

    var youtubeThumbURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(youtubeVideoId)/hqdefault.jpg")
    }

    var youtubeURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(youtubeVideoId)")
    }

    var youtubeAppURL: URL? {
        URL(string: "youtube:///watch?v=\(youtubeVideoId)")
    }

    var formattedRuntime: String {
        guard let mins = runtimeMinutes, mins > 0 else { return "Unknown" }
        let h = mins / 60
        let m = mins % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    var formattedReleaseYear: String? {
        guard let date = releaseDate else { return nil }
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        return "\(year)"
    }

    var formattedViewCount: String {
        guard let count = viewCount else { return "0 views" }
        if count >= 1_000_000 {
            return String(format: "%.1fM views", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK views", Double(count) / 1_000)
        }
        return "\(count) views"
    }

    var formattedRating: String {
        if let r = voteAverage { return String(format: "%.1f", r) }
        if let r = imdbRating { return String(format: "%.1f", r) }
        return "N/A"
    }

}

// MARK: - API Response Types

struct MoviesResponse: Codable {
    let success: Bool
    let data: MoviesData?
}

struct MoviesData: Codable {
    let movies: [Movie]
    let pagination: Pagination?
}

struct Pagination: Codable {
    let page: Int
    let limit: Int
    let total: Int
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case page, limit, total
        // Backend returns "pages" not "total_pages"
        case totalPages = "pages"
    }
}

struct GenresResponse: Codable {
    let success: Bool
    let data: GenresData?
}

struct GenresData: Codable {
    let genres: [Genre]
}

struct GenreMoviesResponse: Codable {
    let success: Bool
    let data: GenreMoviesData?
}

struct GenreMoviesData: Codable {
    let genre: Genre
    let movies: [Movie]
    let pagination: Pagination?
}

struct SingleMovieResponse: Codable {
    let success: Bool
    let data: Movie?
}
