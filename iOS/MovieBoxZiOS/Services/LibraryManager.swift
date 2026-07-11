import Foundation

// MARK: - WatchHistoryItem

struct WatchHistoryItem: Codable, Equatable {
    var id: UUID = UUID()
    let movieId: String
    let movieTitle: String
    let posterURL: URL?
    let watchedAt: Date

    enum CodingKeys: String, CodingKey {
        case movieId, movieTitle, posterURL, watchedAt
    }
}

// MARK: - LibraryManager

@MainActor
class LibraryManager: ObservableObject {
    static let shared = LibraryManager()

    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var watchHistory: [WatchHistoryItem] = []

    private let favKey = "movieboxz.favorites"
    private let histKey = "movieboxz.watchHistory"

    private init() {
        load()
    }

    // MARK: - Favorites

    func isFavorite(_ movieId: String) -> Bool { favorites.contains(movieId) }

    func toggleFavorite(_ movieId: String) {
        if favorites.contains(movieId) {
            favorites.remove(movieId)
        } else {
            favorites.insert(movieId)
        }
        saveFavorites()
    }

    func addToFavorites(_ movieId: String) {
        favorites.insert(movieId)
        saveFavorites()
    }

    func removeFromFavorites(_ movieId: String) {
        favorites.remove(movieId)
        saveFavorites()
    }

    var favoriteMovieIds: [String] { Array(favorites) }

    // MARK: - Watch History

    func isWatched(_ movieId: String) -> Bool {
        watchHistory.contains { $0.movieId == movieId }
    }

    func trackWatch(movieId: String, movieTitle: String, posterURL: URL?) {
        watchHistory.removeAll { $0.movieId == movieId }
        let item = WatchHistoryItem(movieId: movieId, movieTitle: movieTitle, posterURL: posterURL, watchedAt: Date())
        watchHistory.insert(item, at: 0)
        if watchHistory.count > 100 { watchHistory = Array(watchHistory.prefix(100)) }
        saveHistory()
    }

    func removeFromHistory(_ movieId: String) {
        watchHistory.removeAll { $0.movieId == movieId }
        saveHistory()
    }

    func clearHistory() {
        watchHistory = []
        saveHistory()
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: favKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            favorites = Set(ids)
        }
        if let data = UserDefaults.standard.data(forKey: histKey),
           let items = try? JSONDecoder().decode([WatchHistoryItem].self, from: data) {
            watchHistory = items
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(Array(favorites)) {
            UserDefaults.standard.set(data, forKey: favKey)
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(watchHistory) {
            UserDefaults.standard.set(data, forKey: histKey)
        }
    }
}
