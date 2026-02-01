import Foundation
import SwiftUI

// MARK: - Library Manager
// Manages user's favorites (My List) and watch history
// Phase 1: UserDefaults persistence (local only, doesn't sync)
// Phase 3: Will migrate to Supabase for cross-device sync

@MainActor
class LibraryManager: ObservableObject {
    static let shared = LibraryManager()

    // MARK: - Published Properties

    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var watchHistory: [WatchHistoryItem] = []

    // MARK: - UserDefaults Keys

    private let favoritesKey = "movieboxz.favorites"
    private let watchHistoryKey = "movieboxz.watchHistory"

    // MARK: - Initialization

    private init() {
        loadFavorites()
        loadWatchHistory()
    }

    // MARK: - Favorites (My List)

    /// Check if a movie is in favorites
    func isFavorite(_ movieId: String) -> Bool {
        favorites.contains(movieId)
    }

    /// Add movie to favorites
    func addToFavorites(_ movieId: String) {
        favorites.insert(movieId)
        saveFavorites()
    }

    /// Remove movie from favorites
    func removeFromFavorites(_ movieId: String) {
        favorites.remove(movieId)
        saveFavorites()
    }

    /// Toggle favorite status
    func toggleFavorite(_ movieId: String) {
        if isFavorite(movieId) {
            removeFromFavorites(movieId)
        } else {
            addToFavorites(movieId)
        }
    }

    /// Get all favorite movie IDs as array
    var favoriteMovieIds: [String] {
        Array(favorites)
    }

    // MARK: - Watch History

    /// Track that user attempted to watch a movie
    /// Note: We can only track attempts, not actual completion
    /// (YouTube app handles playback, we don't have completion data)
    func trackWatch(movieId: String, movieTitle: String, posterURL: URL?) {
        // Remove existing entry if present (to update timestamp)
        watchHistory.removeAll { $0.movieId == movieId }

        // Add new entry at the beginning
        let item = WatchHistoryItem(
            movieId: movieId,
            movieTitle: movieTitle,
            posterURL: posterURL,
            watchedAt: Date()
        )
        watchHistory.insert(item, at: 0)

        // Keep only last 100 items
        if watchHistory.count > 100 {
            watchHistory = Array(watchHistory.prefix(100))
        }

        saveWatchHistory()
    }

    /// Check if movie is in watch history
    func isWatched(_ movieId: String) -> Bool {
        watchHistory.contains { $0.movieId == movieId }
    }

    /// Remove movie from watch history
    func removeFromHistory(_ movieId: String) {
        watchHistory.removeAll { $0.movieId == movieId }
        saveWatchHistory()
    }

    /// Clear all watch history
    func clearHistory() {
        watchHistory.removeAll()
        saveWatchHistory()
    }

    // MARK: - Persistence (UserDefaults)

    private func loadFavorites() {
        if let data = UserDefaults.standard.array(forKey: favoritesKey) as? [String] {
            favorites = Set(data)
        }
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
    }

    private func loadWatchHistory() {
        if let data = UserDefaults.standard.data(forKey: watchHistoryKey) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([WatchHistoryItem].self, from: data) {
                watchHistory = decoded
            }
        }
    }

    private func saveWatchHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let encoded = try? encoder.encode(watchHistory) {
            UserDefaults.standard.set(encoded, forKey: watchHistoryKey)
        }
    }
}

// MARK: - Watch History Item

struct WatchHistoryItem: Codable, Identifiable {
    let id = UUID()
    let movieId: String
    let movieTitle: String
    let posterURL: URL?
    let watchedAt: Date

    enum CodingKeys: String, CodingKey {
        case movieId
        case movieTitle
        case posterURL
        case watchedAt
    }

    // Custom Codable implementation (UUID is not persisted, regenerated on load)
    init(movieId: String, movieTitle: String, posterURL: URL?, watchedAt: Date) {
        self.movieId = movieId
        self.movieTitle = movieTitle
        self.posterURL = posterURL
        self.watchedAt = watchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        movieId = try container.decode(String.self, forKey: .movieId)
        movieTitle = try container.decode(String.self, forKey: .movieTitle)
        posterURL = try container.decodeIfPresent(URL.self, forKey: .posterURL)
        watchedAt = try container.decode(Date.self, forKey: .watchedAt)
    }
}

// MARK: - Movie Extension (Convenience Methods)

extension Movie {
    @MainActor
    var isFavorite: Bool {
        LibraryManager.shared.isFavorite(id)
    }

    @MainActor
    var isWatched: Bool {
        LibraryManager.shared.isWatched(id)
    }
}
