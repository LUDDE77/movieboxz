import SwiftUI

// MARK: - CategoryType

enum CategoryType: Identifiable, Hashable {
    case genre(id: Int, name: String)
    case trending, popular, recent, allMovies, uncategorized, tvSeries, kids

    var id: String {
        switch self {
        case .genre(let id, _): return "genre-\(id)"
        case .trending: return "trending"
        case .popular: return "popular"
        case .recent: return "recent"
        case .allMovies: return "all"
        case .uncategorized: return "other"
        case .tvSeries: return "tv-series"
        case .kids: return "kids"
        }
    }

    var title: String {
        switch self {
        case .genre(_, let name): return name
        case .trending: return "Trending Now"
        case .popular: return "Popular"
        case .recent: return "Recently Added"
        case .allMovies: return "All Movies"
        case .uncategorized: return "Other"
        case .tvSeries: return "TV Series"
        case .kids: return "Kids"
        }
    }
}

// MARK: - CategoryGridView

struct CategoryGridView: View {
    let categoryType: CategoryType
    @StateObject private var service = MovieService()
    @State private var movies: [Movie] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedMovie: Movie?
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 14)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(categoryType.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    // Symmetry spacer
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 15))
                    .opacity(0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if isLoading {
                    Spacer()
                    ProgressView().tint(.white).scaleEffect(1.5)
                    Spacer()
                } else if let err = error {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50)).foregroundColor(.red)
                        Text(err).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await load() } }
                            .foregroundColor(.white).padding(.horizontal, 24).padding(.vertical, 10)
                            .background(Color.red).cornerRadius(8)
                    }
                    .padding()
                    Spacer()
                } else {
                    Text("\(movies.count) \(movies.count == 1 ? "movie" : "movies")")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(movies) { movie in
                                MovieCard(movie: movie, onTap: { selectedMovie = movie })
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 60)
                    }
                }
            }
        }
        .sheet(item: $selectedMovie) { MovieDetailView(movie: $0) }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            movies = try await fetchMovies()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func fetchMovies() async throws -> [Movie] {
        switch categoryType {
        case .genre(let id, _): return try await service.fetchMoviesByGenre(genreId: id, limit: 200)
        case .trending:         return try await service.fetchTrendingMovies(limit: 200)
        case .popular:          return try await service.fetchPopularMovies(limit: 200)
        case .recent:           return try await service.fetchRecentMovies(limit: 200)
        case .allMovies:        return try await service.fetchAllMovies(limit: 200)
        case .uncategorized:    return try await service.fetchUncategorizedMovies(limit: 200)
        case .tvSeries:         return try await service.fetchTVSeries(limit: 200)
        case .kids:             return try await service.fetchKidsContent(limit: 200)
        }
    }
}
