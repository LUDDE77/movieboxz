import SwiftUI

// MARK: - Library View
// User's personal library with favorites (My List) and watch history
// Phase 1: Local persistence with UserDefaults (doesn't sync across devices)
// Phase 3: Will upgrade to Supabase for cross-device sync

struct LibraryView: View {
    @StateObject private var movieService = MovieService()
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
            Color.black.ignoresSafeArea()

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
        .sheet(item: $selectedMovie) { movie in
            MovieDetailView(movie: movie)
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            loadLibraryData()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Title
            Text("My Library")
                .font(.system(size: headerSize, weight: .bold))
                .foregroundColor(.white)

            // Tab Pills
            TopBarPills(selection: $viewMode)
                .onChange(of: viewMode) { oldValue, newValue in
                    // Reload data when switching tabs (in case it changed)
                    loadLibraryData()
                }
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
                .foregroundColor(.white.opacity(0.7))
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
                    .foregroundColor(.gray.opacity(0.5))

                Text("No Favorites Yet")
                    #if os(tvOS)
                    .font(.system(size: 42, weight: .bold))
                    #else
                    .font(.title2.bold())
                    #endif
                    .foregroundColor(.white)
                    .padding(.top, 8)

                Text("Browse movies and add them to your favorites")
                    #if os(tvOS)
                    .font(.system(size: 29))
                    #else
                    .font(.body)
                    #endif
                    .foregroundColor(.white.opacity(0.6))
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
                    .foregroundColor(.gray.opacity(0.5))

                Text("No Watch History")
                    #if os(tvOS)
                    .font(.system(size: 42, weight: .bold))
                    #else
                    .font(.title2.bold())
                    #endif
                    .foregroundColor(.white)
                    .padding(.top, 8)

                Text("Movies you watch will appear here")
                    #if os(tvOS)
                    .font(.system(size: 29))
                    #else
                    .font(.body)
                    #endif
                    .foregroundColor(.white.opacity(0.6))
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

    private func loadLibraryData() {
        Task {
            isLoading = true

            do {
                // Get favorite and watched movie IDs from LibraryManager
                let favoriteIds = libraryManager.favoriteMovieIds

                // Fetch all recent movies from backend
                let allMovies = try await movieService.fetchRecentMovies(limit: 100)

                // Filter movies by IDs
                favoriteMovies = allMovies.filter { favoriteIds.contains($0.id) }

                // For watch history, maintain order from LibraryManager
                watchedMovies = libraryManager.watchHistory.compactMap { historyItem in
                    allMovies.first { $0.id == historyItem.movieId }
                }

                isLoading = false
            } catch {
                print("❌ Error loading library: \(error)")
                favoriteMovies = []
                watchedMovies = []
                isLoading = false
            }
        }
    }

    // MARK: - Actions

    private func playVideo(_ videoId: String) {
        // Find the movie
        if let movie = favoriteMovies.first(where: { $0.youtubeVideoId == videoId }) ??
                       watchedMovies.first(where: { $0.youtubeVideoId == videoId }) {

            // Track watch in LibraryManager
            libraryManager.trackWatch(
                movieId: movie.id,
                movieTitle: movie.displayTitle,
                posterURL: movie.posterURL
            )

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
        .preferredColorScheme(.dark)
}
