import SwiftUI

// MARK: - Category Type Enum
enum CategoryType: Identifiable, Hashable {
    case genre(id: Int, name: String)
    case trending
    case popular
    case recent
    case allMovies
    case tvSeries
    case kids
    case uncategorized
    case topImdb

    var id: String {
        switch self {
        case .genre(let id, _): return "genre-\(id)"
        case .trending: return "trending"
        case .popular: return "popular"
        case .recent: return "recent"
        case .allMovies: return "all-movies"
        case .tvSeries: return "tv-series"
        case .kids: return "kids"
        case .uncategorized: return "uncategorized"
        case .topImdb: return "top-imdb"
        }
    }

    var title: String {
        switch self {
        case .genre(_, let name): return name
        case .trending: return "Trending Now"
        case .popular: return "Popular Movies"
        case .recent: return "Recently Added"
        case .allMovies: return "All Movies"
        case .tvSeries: return "TV Series"
        case .kids: return "Kids"
        case .uncategorized: return "Other"
        case .topImdb: return "High Score IMDB"
        }
    }
}

// MARK: - Category Detail View
// Full-screen view showing all movies in a category with dynamic data fetching

struct CategoryDetailView: View {
    let categoryType: CategoryType

    @EnvironmentObject private var movieService: MovieService
    @State private var movies: [Movie] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedMovie: Movie?
    @Environment(\.dismiss) private var dismiss

    // Platform-specific grid columns
    #if os(tvOS)
    private let columns = [
        GridItem(.adaptive(minimum: 245, maximum: 245), spacing: 40)
    ]
    private let cardTitleSize: CGFloat = 31
    private let cardMetadataSize: CGFloat = 25
    private let headerSize: CGFloat = 56
    #else
    private let columns = [
        GridItem(.adaptive(minimum: 126, maximum: 200), spacing: 15)
    ]
    private let cardTitleSize: CGFloat = 18
    private let cardMetadataSize: CGFloat = 14
    private let headerSize: CGFloat = 28
    #endif

    var body: some View {
        ZStack {
            Color.mbzInk.ignoresSafeArea()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                contentView
            }
        }
        .onAppear {
            loadMovies()
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
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.mbzGold)
            Text("Loading \(categoryType.title)...")
                .font(.system(size: cardTitleSize))
                .foregroundColor(.mbzMuted)
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)
            Text("Error Loading Movies")
                .font(.system(size: headerSize - 10, weight: .bold))
                .foregroundColor(.mbzScreen)
            Text(message)
                .font(.system(size: cardTitleSize))
                .foregroundColor(.mbzMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                loadMovies()
            } label: {
                Text("Try Again")
                    .font(.system(size: cardTitleSize, weight: .semibold))
                    .foregroundColor(.mbzInk)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.mbzGold)
                    .cornerRadius(10)
            }
            #if os(tvOS)
            .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 10)))
            #else
            .buttonStyle(.plain)
            #endif

            Button {
                dismiss()
            } label: {
                Text("Go Back")
                    .font(.system(size: cardTitleSize))
                    .foregroundColor(.mbzMuted)
            }
            #if os(tvOS)
            .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 8)))
            #else
            .buttonStyle(.plain)
            #endif
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: headerSize - 20))
                        .foregroundColor(.mbzGold)
                    }
                    #if os(tvOS)
                    .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 8)))
                    #else
                    .buttonStyle(.plain)
                    #endif

                    Spacer()

                    Text(categoryType.title)
                        .font(.system(size: headerSize, weight: .heavy))
                        .tracking(0.5)
                        .foregroundColor(.mbzGold)

                    Spacer()

                    // Placeholder for symmetry
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: headerSize - 20))
                    .opacity(0)
                }
                #if os(tvOS)
                .padding(.horizontal, 80)
                .padding(.top, 60)
                #else
                .padding(.horizontal, 16)
                .padding(.top, 20)
                #endif

                // Movie count
                Text("\(movies.count) \(movies.count == 1 ? "movie" : "movies")")
                    .font(.system(size: headerSize - 28))
                    .foregroundColor(.mbzMuted)
                    #if os(tvOS)
                    .padding(.horizontal, 80)
                    #else
                    .padding(.horizontal, 16)
                    #endif

                // Grid of movies
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach(movies) { movie in
                        MovieCard(
                            movie: movie,
                            cardTitleSize: cardTitleSize,
                            cardMetadataSize: cardMetadataSize,
                            onPlayVideo: { _ in
                                playVideo(movie)
                            }
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
    }

    // MARK: - Data Loading

    private func loadMovies() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedMovies: [Movie]

                switch categoryType {
                case .genre(let genreId, _):
                    // Fetch all movies for this genre (high limit to get all)
                    fetchedMovies = try await movieService.fetchMoviesByGenre(
                        genreId: genreId,
                        page: 1,
                        limit: 200
                    )

                case .trending:
                    fetchedMovies = try await movieService.fetchTrendingMovies(
                        page: 1,
                        limit: 200
                    )

                case .popular:
                    fetchedMovies = try await movieService.fetchPopularMovies(
                        page: 1,
                        limit: 200
                    )

                case .topImdb:
                    fetchedMovies = try await movieService.fetchTopImdbMovies(
                        page: 1,
                        limit: 200
                    )

                case .recent:
                    fetchedMovies = try await movieService.fetchRecentMovies(
                        page: 1,
                        limit: 200
                    )

                case .allMovies:
                    fetchedMovies = try await movieService.fetchAllMovies(
                        sort: "popularity",
                        page: 1,
                        limit: 200
                    )

                case .tvSeries:
                    // TV Movie genre (TMDB id 10770)
                    fetchedMovies = try await movieService.fetchMoviesByGenre(
                        genreId: 10770,
                        page: 1,
                        limit: 200
                    )

                case .kids:
                    // Family (10751) + Animation (16) genres combined and deduplicated
                    async let familyMovies = movieService.fetchMoviesByGenre(genreId: 10751, page: 1, limit: 100)
                    async let animationMovies = movieService.fetchMoviesByGenre(genreId: 16, page: 1, limit: 100)
                    let (family, animation) = try await (familyMovies, animationMovies)
                    var seen = Set<String>()
                    fetchedMovies = (family + animation).filter { seen.insert($0.id).inserted }

                case .uncategorized:
                    fetchedMovies = try await movieService.fetchUncategorizedMovies(
                        page: 1,
                        limit: 200
                    )
                }

                await MainActor.run {
                    self.movies = fetchedMovies
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Video Playback

    private func playVideo(_ movie: Movie) {
        // Track watch in LibraryManager
        LibraryManager.shared.trackWatch(
            movieId: movie.id,
            movieTitle: movie.displayTitle,
            posterURL: movie.posterURL
        )

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

#Preview {
    CategoryDetailView(
        categoryType: .genre(id: 28, name: "Action & Adventure")
    )
    .environmentObject(MovieService())
    .preferredColorScheme(.dark)
}
