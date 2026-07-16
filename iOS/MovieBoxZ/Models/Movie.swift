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

    // OMDb metadata
    let imdbRating: Double?  // IMDB rating from OMDb (fallback when voteAverage is null)
    let rated: String?       // MPAA rating (G, PG, PG-13, R, etc.)

    // App metadata
    let category: String?
    let quality: String?
    let featured: Bool
    let trending: Bool
    let isAvailable: Bool
    let isEmbeddable: Bool

    // Genres
    let genres: [Genre]?

    // TV Series fields
    let isTvSeries: Bool?
    let tvSeriesId: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let seriesType: String?

    // Hero Builder: admin-curated image (full URL) for the featured carousel.
    let heroImageUrl: String?

    init(id: String, youtubeVideoId: String, title: String, originalTitle: String?, description: String?,
         releaseDate: Date?, runtimeMinutes: Int?, youtubeVideoTitle: String, channelId: String,
         channelTitle: String, channelThumbnail: String?, viewCount: Int, likeCount: Int?,
         commentCount: Int?, publishedAt: Date?, lastRefreshed: Date?, tmdbId: Int?, imdbId: String?,
         posterPath: String?, backdropPath: String?, voteAverage: Double?, voteCount: Int?,
         popularity: Double?, imdbRating: Double?, rated: String?, category: String?, quality: String?,
         featured: Bool, trending: Bool, isAvailable: Bool, isEmbeddable: Bool, genres: [Genre]?,
         addedAt: Date, lastValidated: Date?,
         isTvSeries: Bool? = nil, tvSeriesId: String? = nil, seasonNumber: Int? = nil,
         episodeNumber: Int? = nil, seriesType: String? = nil, heroImageUrl: String? = nil) {
        self.id = id
        self.youtubeVideoId = youtubeVideoId
        self.title = title
        self.originalTitle = originalTitle
        self.description = description
        self.releaseDate = releaseDate
        self.runtimeMinutes = runtimeMinutes
        self.youtubeVideoTitle = youtubeVideoTitle
        self.channelId = channelId
        self.channelTitle = channelTitle
        self.channelThumbnail = channelThumbnail
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.publishedAt = publishedAt
        self.lastRefreshed = lastRefreshed
        self.tmdbId = tmdbId
        self.imdbId = imdbId
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.popularity = popularity
        self.imdbRating = imdbRating
        self.rated = rated
        self.category = category
        self.quality = quality
        self.featured = featured
        self.trending = trending
        self.isAvailable = isAvailable
        self.isEmbeddable = isEmbeddable
        self.genres = genres
        self.addedAt = addedAt
        self.lastValidated = lastValidated
        self.isTvSeries = isTvSeries
        self.tvSeriesId = tvSeriesId
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.seriesType = seriesType
        self.heroImageUrl = heroImageUrl
    }

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
        case imdbRating = "imdb_rating"
        case rated
        case category
        case quality
        case featured
        case trending
        case isAvailable = "is_available"
        case isEmbeddable = "is_embeddable"
        case genres
        case isTvSeries = "is_tv_series"
        case tvSeriesId = "tv_series_id"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case seriesType = "series_type"
        case heroImageUrl = "hero_image_url"
        case addedAt = "added_at"
        case lastValidated = "last_validated"
    }

    // Resilient decoding: each field is decoded with `try?` and a sane
    // default so a single dirty/null/wrong-typed column in one row can't
    // throw a DecodingError and blank the ENTIRE array (a rail, a genre
    // page, search results). Availability flags default to `true` so a
    // missing flag shows the movie rather than silently hiding it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        youtubeVideoId    = (try? c.decode(String.self, forKey: .youtubeVideoId)) ?? ""
        title             = (try? c.decode(String.self, forKey: .title)) ?? ""
        originalTitle     = try? c.decode(String.self, forKey: .originalTitle)
        description       = try? c.decode(String.self, forKey: .description)
        releaseDate       = try? c.decode(Date.self, forKey: .releaseDate)
        runtimeMinutes    = try? c.decode(Int.self, forKey: .runtimeMinutes)
        youtubeVideoTitle = (try? c.decode(String.self, forKey: .youtubeVideoTitle)) ?? ""
        channelId         = (try? c.decode(String.self, forKey: .channelId)) ?? ""
        channelTitle      = (try? c.decode(String.self, forKey: .channelTitle)) ?? ""
        channelThumbnail  = try? c.decode(String.self, forKey: .channelThumbnail)
        viewCount         = (try? c.decode(Int.self, forKey: .viewCount)) ?? 0
        likeCount         = try? c.decode(Int.self, forKey: .likeCount)
        commentCount      = try? c.decode(Int.self, forKey: .commentCount)
        publishedAt       = try? c.decode(Date.self, forKey: .publishedAt)
        lastRefreshed     = try? c.decode(Date.self, forKey: .lastRefreshed)
        tmdbId            = try? c.decode(Int.self, forKey: .tmdbId)
        imdbId            = try? c.decode(String.self, forKey: .imdbId)
        posterPath        = try? c.decode(String.self, forKey: .posterPath)
        backdropPath      = try? c.decode(String.self, forKey: .backdropPath)
        voteAverage       = try? c.decode(Double.self, forKey: .voteAverage)
        voteCount         = try? c.decode(Int.self, forKey: .voteCount)
        popularity        = try? c.decode(Double.self, forKey: .popularity)
        imdbRating        = try? c.decode(Double.self, forKey: .imdbRating)
        rated             = try? c.decode(String.self, forKey: .rated)
        category          = try? c.decode(String.self, forKey: .category)
        quality           = try? c.decode(String.self, forKey: .quality)
        featured          = (try? c.decode(Bool.self, forKey: .featured)) ?? false
        trending          = (try? c.decode(Bool.self, forKey: .trending)) ?? false
        isAvailable       = (try? c.decode(Bool.self, forKey: .isAvailable)) ?? true
        isEmbeddable      = (try? c.decode(Bool.self, forKey: .isEmbeddable)) ?? true
        genres            = try? c.decode([Genre].self, forKey: .genres)
        isTvSeries        = try? c.decode(Bool.self, forKey: .isTvSeries)
        tvSeriesId        = try? c.decode(String.self, forKey: .tvSeriesId)
        seasonNumber      = try? c.decode(Int.self, forKey: .seasonNumber)
        episodeNumber     = try? c.decode(Int.self, forKey: .episodeNumber)
        seriesType        = try? c.decode(String.self, forKey: .seriesType)
        heroImageUrl      = try? c.decode(String.self, forKey: .heroImageUrl)
        addedAt           = (try? c.decode(Date.self, forKey: .addedAt)) ?? Date()
        lastValidated     = try? c.decode(Date.self, forKey: .lastValidated)
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
            return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
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
            return URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
        }
        // Fallback to YouTube thumbnail (hqdefault always exists, maxresdefault often 404s)
        return URL(string: "https://img.youtube.com/vi/\(youtubeVideoId)/hqdefault.jpg")
    }

    /// A real 16:9 landscape backdrop (TMDB/OMDb) only — nil when the movie
    /// has no proper wide art. The tvOS hero uses this so it can fall back to
    /// an ambient blurred poster instead of stretching a low-res YouTube
    /// thumbnail across a 4K screen.
    var heroBackdropURL: URL? {
        guard let backdropPath = backdropPath else { return nil }
        if backdropPath.starts(with: "http://") || backdropPath.starts(with: "https://") {
            return URL(string: backdropPath)
        }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
    }

    /// True when the movie has a genuine landscape backdrop suitable for a
    /// full-bleed hero (vs. only a portrait poster / YouTube thumbnail).
    var hasLandscapeBackdrop: Bool { backdropPath != nil }

    /// The image shown in the featured hero carousel: the admin-curated Hero
    /// Builder image if set, else the real landscape backdrop, else the poster.
    var heroDisplayURL: URL? {
        if let hero = heroImageUrl, let url = URL(string: hero) { return url }
        return heroBackdropURL ?? posterURL
    }

    /// True when the hero image is a deliberate/landscape choice that should be
    /// shown sharp (admin-picked, or a real backdrop) rather than blurred.
    var hasWideHero: Bool { heroImageUrl != nil || backdropPath != nil }

    var youtubeThumbURL: URL? {
        // Direct YouTube thumbnail (for attribution section).
        // Optional (not force-unwrapped): a malformed youtubeVideoId would
        // otherwise crash every screen that shows a thumbnail.
        URL(string: "https://img.youtube.com/vi/\(youtubeVideoId)/hqdefault.jpg")
    }

    var youtubeURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(youtubeVideoId)")
    }

    var youtubeAppURL: URL? {
        URL(string: "youtube:///watch?v=\(youtubeVideoId)")
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
        // Prefer TMDB rating, fallback to IMDB rating (OMDb)
        if let rating = voteAverage {
            return String(format: "%.1f", rating)
        }
        if let rating = imdbRating {
            return String(format: "%.1f", rating)
        }
        return "N/A"
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

/// The entire Browse tab in one response (from GET /api/browse/home) — replaces
/// ~20 separate requests.
struct BrowseHomeResponse: Codable {
    let data: BrowseHomeData

    struct BrowseHomeData: Codable {
        let featured: [Movie]
        let popular: [Movie]
        let trending: [Movie]
        let recent: [Movie]
        let allMovies: [Movie]
        let uncategorized: [Movie]
        let topImdb: [Movie]
        let genres: [GenreCarousel]
        let eras: Eras
    }
    struct GenreCarousel: Codable {
        let genre: Genre
        let movies: [Movie]
    }
    struct Eras: Codable {
        let modern: [Movie]
        let eighties90s: [Movie]
        let sixties70s: [Movie]
        let classic: [Movie]
    }
}

/// A page of a category, with the real total count so "See All" screens can
/// show the true count and a Load More button.
struct MoviePage {
    let movies: [Movie]
    let total: Int?
}

/// Decodes both the /movies* (MoviesData) and /browse/genres/:id
/// (GenreMoviesData) paged shapes — both expose `data.movies` and a total
/// via `data.pagination.total` (MoviesData may also carry `data.total`).
struct PagedMoviesResponse: Codable {
    let data: PageData
    struct PageData: Codable {
        let movies: [Movie]
        let total: Int?
        let pagination: Pagination?
    }
    var totalCount: Int? { data.total ?? data.pagination?.total }
}

// MARK: - TV Series Models

struct TVSeries: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let posterPath: String?
    let yearStart: Int?
    let yearEnd: Int?
    let episodeCount: Int?
    let seasonCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case posterPath = "poster_path"
        case yearStart = "year_start"
        case yearEnd = "year_end"
        case episodeCount = "episode_count"
        case seasonCount = "season_count"
    }

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }
}

struct SeriesSeason: Identifiable {
    let seasonNumber: Int
    let episodes: [Movie]
    var id: Int { seasonNumber }
}

struct SeriesDetailResponse: Codable {
    let series: TVSeriesDetail
    let seasons: [SeasonResponse]
}

struct TVSeriesDetail: Codable {
    let id: String
    let title: String
    let description: String?
    let posterPath: String?
    let yearStart: Int?
    let yearEnd: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case posterPath = "poster_path"
        case yearStart = "year_start"
        case yearEnd = "year_end"
    }

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }
}

struct SeasonResponse: Codable {
    let seasonNumber: Int
    let episodes: [Movie]

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "seasonNumber"
        case episodes
    }
}