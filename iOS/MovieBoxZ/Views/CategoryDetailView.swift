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
    case decade(yearMin: Int?, yearMax: Int?, title: String)

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
        case .decade(let mn, let mx, _): return "decade-\(mn.map(String.init) ?? "")-\(mx.map(String.init) ?? "")"
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
        case .decade(_, _, let title): return title
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
    @State private var total: Int?          // real total count from the backend
    @State private var page = 1             // last loaded page
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @Environment(\.dismiss) private var dismiss

    private let pageSize = 60

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
        #if os(tvOS)
        // Menu returns to the previous screen instead of falling through to
        // the system (which could background the app).
        .onExitCommand { dismiss() }
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

                // Movie count — the real category total from the backend when
                // known, otherwise the number loaded so far.
                Text(total.map { "\($0) \($0 == 1 ? "movie" : "movies")" } ?? "\(movies.count) movies")
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
                .padding(.bottom, 40)
                #else
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                #endif

                // Load More — appears when the category has more than the loaded page.
                if canLoadMore {
                    Button {
                        loadMore()
                    } label: {
                        HStack(spacing: 10) {
                            if isLoadingMore {
                                ProgressView().tint(.mbzInk)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text(isLoadingMore ? "Loading…" : "Load More")
                        }
                        .font(.system(size: cardTitleSize, weight: .semibold))
                        .foregroundColor(.mbzInk)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 14)
                        .background(Color.mbzGold)
                        .cornerRadius(12)
                    }
                    #if os(tvOS)
                    .buttonStyle(FocusBorderButtonStyle(variant: .action(cornerRadius: 12)))
                    #else
                    .buttonStyle(.plain)
                    #endif
                    .disabled(isLoadingMore)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 60)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadMovies() {
        page = 1
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try await fetchPage(1)
                await MainActor.run {
                    self.movies = result.movies
                    self.total = result.total
                    self.canLoadMore = result.hasMore
                    self.page = 1
                    self.isLoading = false
                }
            } catch is CancellationError {
                await MainActor.run { self.isLoading = false }
            } catch let urlError as URLError where urlError.code == .cancelled {
                await MainActor.run { self.isLoading = false }
            } catch {
                await MainActor.run {
                    // Friendly, non-technical message (no raw error strings).
                    self.errorMessage = "Couldn't load \(categoryType.title). Please check your connection and try again."
                    self.isLoading = false
                }
            }
        }
    }

    private func loadMore() {
        guard canLoadMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        let next = page + 1

        Task {
            do {
                let result = try await fetchPage(next)
                await MainActor.run {
                    // Append, de-duplicating against what's already shown.
                    var seen = Set(self.movies.map { $0.id })
                    let fresh = result.movies.filter { seen.insert($0.id).inserted }
                    self.movies.append(contentsOf: fresh)
                    if let t = result.total { self.total = t }
                    self.page = next
                    self.canLoadMore = result.hasMore
                    self.isLoadingMore = false
                }
            } catch {
                // Keep what we have; just stop the spinner so the user can retry.
                await MainActor.run { self.isLoadingMore = false }
            }
        }
    }

    /// Fetches one page for the current category, returning the movies, the real
    /// total count, and whether more pages remain.
    private func fetchPage(_ page: Int) async throws -> (movies: [Movie], total: Int?, hasMore: Bool) {
        // Kids = Family (10751) + Animation (16), deduped. Paginated in lockstep;
        // the exact combined total is unknown (overlap), so Load More runs while
        // either source still returns a full page.
        if case .kids = categoryType {
            async let familyPage = movieService.fetchMoviePage(endpoint: "/browse/genres/10751?page=\(page)&limit=\(pageSize)")
            async let animationPage = movieService.fetchMoviePage(endpoint: "/browse/genres/16?page=\(page)&limit=\(pageSize)")
            let (fam, ani) = try await (familyPage, animationPage)
            var seen = Set<String>()
            let combined = (fam.movies + ani.movies).filter { seen.insert($0.id).inserted }
            let more = fam.movies.count == pageSize || ani.movies.count == pageSize
            return (combined, nil, more)
        }

        guard let endpoint = endpoint(page: page) else { return ([], nil, false) }
        let result = try await movieService.fetchMoviePage(endpoint: endpoint)
        let hasMore: Bool
        if let total = result.total {
            hasMore = page * pageSize < total
        } else {
            // No total from the backend — assume more while pages come back full.
            hasMore = result.movies.count == pageSize
        }
        return (result.movies, result.total, hasMore)
    }

    /// The API endpoint for a given page of the current category.
    private func endpoint(page: Int) -> String? {
        let pl = "page=\(page)&limit=\(pageSize)"
        switch categoryType {
        case .genre(let id, _):        return "/browse/genres/\(id)?\(pl)"
        case .trending:                return "/movies/trending?\(pl)"
        case .popular:                 return "/movies/popular?\(pl)"
        case .topImdb:                 return "/movies/top-rated?source=imdb&\(pl)"
        case .recent:                  return "/movies/recent?\(pl)"
        case .allMovies:               return "/movies?sort=popularity&\(pl)"
        case .tvSeries:                return "/browse/genres/10770?\(pl)"
        case .uncategorized:           return "/browse/uncategorized?\(pl)"
        case .decade(let mn, let mx, _):
            var s = "/movies?sort=popular&\(pl)"
            if let mn { s += "&year_min=\(mn)" }
            if let mx { s += "&year_max=\(mx)" }
            return s
        case .kids:                    return nil // handled above
        }
    }

    // MARK: - Video Playback

    private func playVideo(_ movie: Movie) {
        // Opening the detail card is NOT a watch — tracking happens only on the
        // actual YouTube hand-off (YouTubePlayerService.playMovie).
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
