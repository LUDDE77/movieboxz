import SwiftUI

// MARK: - Library View
// User's personal library with favorites (My List) and watch history
// Phase 1: Local persistence with UserDefaults (doesn't sync across devices)
// Phase 3: Will upgrade to Supabase for cross-device sync

struct LibraryView: View {
    @EnvironmentObject private var movieService: MovieService
    @StateObject private var libraryManager = LibraryManager.shared

    @State private var viewMode: ViewMode = .myList
    @State private var favoriteMovies: [Movie] = []
    @State private var watchedMovies: [Movie] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var selectedMovie: Movie?

    // Platform-specific sizes
    #if os(tvOS)
    private let headerSize: CGFloat = 56
    private let columns = [
        GridItem(.adaptive(minimum: 245, maximum: 245), spacing: 40)
    ]
    private let cardTitleSize: CGFloat = 31
    private let cardMetadataSize: CGFloat = 25
    #else
    private let headerSize: CGFloat = 28
    private let columns = [
        GridItem(.adaptive(minimum: 126, maximum: 180), spacing: 15)
    ]
    private let cardTitleSize: CGFloat = 18
    private let cardMetadataSize: CGFloat = 14
    #endif

    enum ViewMode: String, CaseIterable {
        case myList = "My List"
        case watched = "Watched"
    }

    var body: some View {
        ZStack {
            Color.mbzInk.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                headerSection

                // Content
                if isLoading {
                    loadingView
                } else {
                    contentSection
                }
            }
        }
        #if os(tvOS)
        .fullScreenCover(item: $selectedMovie) { movie in
            MovieDetailView(movie: movie)
        }
        #else
        .sheet(item: $selectedMovie) { movie in
            MovieDetailView(movie: movie)
        }
        #endif
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            loadLibraryData()
        }
        // Reflect favorites/watch changes made anywhere (e.g. the detail
        // sheet, or another tab on tvOS where this view stays alive) without
        // requiring an app relaunch. Refresh silently — no spinner flash.
        .onChange(of: libraryManager.favorites) {
            guard hasLoaded else { return }
            loadLibraryData(isRefresh: true)
        }
        .onChange(of: libraryManager.watchHistory.map(\.movieId)) {
            guard hasLoaded else { return }
            loadLibraryData(isRefresh: true)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Title
            Text("My Library")
                .font(.system(size: headerSize, weight: .heavy))
                .tracking(0.5)
                .foregroundColor(.mbzGold)

            // Tab Pills. Switching tabs just toggles which already-loaded list
            // (favorites vs watched) is shown — no refetch, so a flaky network
            // can't blank the list when you change tabs.
            TopBarPills(selection: $viewMode)
        }
        #if os(tvOS)
        .padding(.horizontal, 80)
        .padding(.top, 60)
        .padding(.bottom, 40)
        #else
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 24)
        #endif
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        let currentMovies = viewMode == .myList ? favoriteMovies : watchedMovies

        if currentMovies.isEmpty {
            emptyStateView
        } else {
            movieGridView(movies: currentMovies)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                #if os(tvOS)
                .scaleEffect(2.0)
                #else
                .scaleEffect(1.5)
                #endif
            Text("Loading Library...")
                #if os(tvOS)
                .font(.system(size: 31))
                #else
                .font(.headline)
                #endif
                .foregroundColor(.mbzMuted)
            Spacer()
        }
    }

    // MARK: - Empty State View

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            if viewMode == .myList {
                // My List empty state
                Image(systemName: "heart")
                    #if os(tvOS)
                    .font(.system(size: 120))
                    #else
                    .font(.system(size: 60))
                    #endif
                    .foregroundColor(.mbzMuted.opacity(0.6))

                Text("No Favorites Yet")
                    #if os(tvOS)
                    .font(.system(size: 42, weight: .bold))
                    #else
                    .font(.title2.bold())
                    #endif
                    .foregroundColor(.mbzScreen)
                    .padding(.top, 8)

                Text("Browse movies and add them to your favorites")
                    #if os(tvOS)
                    .font(.system(size: 29))
                    #else
                    .font(.body)
                    #endif
                    .foregroundColor(.mbzMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                // Watch History empty state
                Image(systemName: "clock")
                    #if os(tvOS)
                    .font(.system(size: 120))
                    #else
                    .font(.system(size: 60))
                    #endif
                    .foregroundColor(.mbzMuted.opacity(0.6))

                Text("No Watch History")
                    #if os(tvOS)
                    .font(.system(size: 42, weight: .bold))
                    #else
                    .font(.title2.bold())
                    #endif
                    .foregroundColor(.mbzScreen)
                    .padding(.top, 8)

                Text("Movies you watch will appear here")
                    #if os(tvOS)
                    .font(.system(size: 29))
                    #else
                    .font(.body)
                    #endif
                    .foregroundColor(.mbzMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }

    // MARK: - Movie Grid View

    private func movieGridView(movies: [Movie]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(movies) { movie in
                    MovieCard(
                        movie: movie,
                        cardTitleSize: cardTitleSize,
                        cardMetadataSize: cardMetadataSize,
                        onPlayVideo: playVideo
                    )
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 80)
            .padding(.bottom, 100)
            #else
            .padding(.horizontal, 16)
            .padding(.bottom, 50)
            #endif
        }
    }

    // MARK: - Data Loading

    private func loadLibraryData(isRefresh: Bool = false) {
        Task {
            // On a background refresh keep the current grid visible instead
            // of flashing the loading spinner.
            if !isRefresh { isLoading = true }

            // Get favorite and watched movie IDs from LibraryManager
            let favoriteIds = libraryManager.favoriteMovieIds
            let watchedIds = libraryManager.watchHistory.map { $0.movieId }

            // Fetch each favorited/watched movie by ID directly instead of
            // pulling a capped "recent" list and filtering — otherwise any
            // favorite older than the most recent N movies silently
            // disappears from "My List". Fetches run concurrently and
            // gracefully skip movies that fail to load (e.g. deleted).
            async let favoritesResult = fetchMovies(byIds: favoriteIds)
            async let watchedResult = fetchMovies(byIds: watchedIds)
            let (fetchedFavorites, fetchedWatched) = await (favoritesResult, watchedResult)

            let favoritesById = Dictionary(uniqueKeysWithValues: fetchedFavorites.map { ($0.id, $0) })
            let newFavorites = favoriteIds.compactMap { favoritesById[$0] }
            // Only replace the list when this load actually returned something
            // (or there genuinely are no favorites). A transient network failure
            // that fetches nothing must NOT wipe a list the user still has saved.
            if !newFavorites.isEmpty || favoriteIds.isEmpty {
                favoriteMovies = newFavorites
            }

            let watchedById = Dictionary(uniqueKeysWithValues: fetchedWatched.map { ($0.id, $0) })
            // Preserve most-recently-watched-first order from LibraryManager
            let newWatched = libraryManager.watchHistory.compactMap { watchedById[$0.movieId] }
            if !newWatched.isEmpty || libraryManager.watchHistory.isEmpty {
                watchedMovies = newWatched
            }

            isLoading = false
        }
    }

    /// Fetches movies by ID concurrently, skipping any that fail (deleted,
    /// unavailable, network error, etc.) instead of crashing or dropping
    /// the whole list.
    private func fetchMovies(byIds ids: [String]) async -> [Movie] {
        guard !ids.isEmpty else { return [] }
        return await withTaskGroup(of: Movie?.self) { group in
            for id in ids {
                group.addTask {
                    try? await movieService.fetchMovieDetails(id: id)
                }
            }
            var results: [Movie] = []
            for await movie in group {
                if let movie {
                    results.append(movie)
                }
            }
            return results
        }
    }

    // MARK: - Actions

    private func playVideo(_ videoId: String) {
        // Find the movie
        if let movie = favoriteMovies.first(where: { $0.youtubeVideoId == videoId }) ??
                       watchedMovies.first(where: { $0.youtubeVideoId == videoId }) {

            // Opening the detail card is NOT a watch — tracking happens only on
            // the actual YouTube hand-off (YouTubePlayerService.playMovie).
            // Show detail view
            #if os(tvOS)
            // tvOS: Delay presentation to let focus system settle
            DispatchQueue.main.async {
                self.selectedMovie = movie
            }
            #else
            selectedMovie = movie
            #endif
        }
    }
}

// MARK: - Preview

#Preview {
    LibraryView()
        .environmentObject(MovieService())
        .preferredColorScheme(.dark)
}
