import SwiftUI

struct LibraryView: View {
    @ObservedObject private var library = LibraryManager.shared
    @StateObject private var service = MovieService()
    @State private var tab: LibTab = .favorites
    @State private var favoriteMovies: [Movie] = []
    @State private var watchedMovies: [Movie] = []
    @State private var isLoading = false
    @State private var selectedMovie: Movie?

    enum LibTab: String, CaseIterable {
        case favorites = "My List"
        case history = "Watched"
    }

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 14)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                tabPicker
                movieContent
            }
        }
        .sheet(item: $selectedMovie) { m in MovieDetailView(movie: m) }
        .task { await loadMovies() }
        .onChange(of: library.favorites) { Task { await loadMovies() } }
        .onChange(of: library.watchHistory.count) { Task { await loadMovies() } }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(LibTab.allCases, id: \.self) { t in
                tabButton(t)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func tabButton(_ t: LibTab) -> some View {
        let isSelected = tab == t
        return Button { tab = t } label: {
            Text(t.rawValue)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var movieContent: some View {
        if isLoading {
            Spacer()
            ProgressView().tint(.white).scaleEffect(1.5)
            Spacer()
        } else {
            let movies = tab == .favorites ? favoriteMovies : watchedMovies
            if movies.isEmpty {
                emptyState
            } else {
                movieGrid(movies)
            }
        }
    }

    private func movieGrid(_ movies: [Movie]) -> some View {
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

    private var emptyState: some View {
        let isFav = tab == .favorites
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: isFav ? "heart.slash" : "clock.badge.xmark")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            Text(isFav ? "No Favourites Yet" : "No Watch History")
                .font(.title3).fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.6))
            Text(isFav ? "Tap ♡ on any movie to save it here" : "Movies you watch will appear here")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))
            Spacer()
        }
    }

    private func loadMovies() async {
        isLoading = true
        let allMovies = (try? await service.fetchAllMovies(limit: 200)) ?? []
        favoriteMovies = allMovies.filter { library.isFavorite($0.id) }
        let historyIds = library.watchHistory.map { $0.movieId }
        watchedMovies = historyIds.compactMap { id in allMovies.first { $0.id == id } }
        isLoading = false
    }
}
