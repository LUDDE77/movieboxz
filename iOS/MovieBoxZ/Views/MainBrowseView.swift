import SwiftUI
import AVKit
import AVFoundation

struct MainBrowseView: View {
    @StateObject private var movieService = MovieService()
    @State private var featuredMovies: [Movie] = []
    @State private var trendingMovies: [Movie] = []
    @State private var popularMovies: [Movie] = []
    @State private var recentMovies: [Movie] = []

    // Dynamic Genre Categories
    @State private var genreCategories: [(genre: Genre, movies: [Movie])] = []
    @State private var uncategorizedMovies: [Movie] = []

    // All Movies & TV Series
    @State private var allMovies: [Movie] = []
    @State private var tvSeries: [Movie] = [] // Placeholder for TV series

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedMovie: Movie?
    @State private var selectedCategory: CategoryType?

    // Hero carousel state
    @State private var currentHeroIndex: Int = 0
    @State private var heroTimer: Timer?

    // Platform-specific font sizes
    #if os(tvOS)
    private let heroTitleSize: CGFloat = 72
    private let sectionHeaderSize: CGFloat = 42
    private let cardTitleSize: CGFloat = 31
    private let cardMetadataSize: CGFloat = 25
    private let bodyTextSize: CGFloat = 29
    #else
    private let heroTitleSize: CGFloat = 28
    private let sectionHeaderSize: CGFloat = 20
    private let cardTitleSize: CGFloat = 14
    private let cardMetadataSize: CGFloat = 12
    private let bodyTextSize: CGFloat = 14
    #endif

    var body: some View {
        ZStack {
            // Full-screen black base — fills safe areas edge to edge
            Color.black.ignoresSafeArea()

            // iOS: Backdrop placed at ZStack level so it fills the full screen frame
            // offered by ContentView's GeometryReader layout.
            #if os(iOS)
            if !featuredMovies.isEmpty, !isLoading {
                let heroMovie = featuredMovies[min(currentHeroIndex, featuredMovies.count - 1)]
                // .id forces a new view on each index change so .transition fires.
                // Only the backdrop animates — content layout stays static.
                AsyncImage(url: heroMovie.backdropURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(currentHeroIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.8), value: currentHeroIndex)

                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.4),
                        .init(color: Color.black.opacity(0.3), location: 0.6),
                        .init(color: Color.black.opacity(0.7), location: 0.8),
                        .init(color: Color.black, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #endif

            if isLoading && featuredMovies.isEmpty {
                // Show skeleton screen on initial load
                LoadingSkeletonView()
            } else {
                #if os(tvOS)
                // tvOS: Natural Scrolling Hero (scrolls away)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // HERO SECTION (scrolls away naturally)
                        if !featuredMovies.isEmpty {
                            let heroMovie = featuredMovies[min(currentHeroIndex, featuredMovies.count - 1)]
                            FeaturedMovieBanner(
                                movie: heroMovie,
                                heroTitleSize: heroTitleSize,
                                bodyTextSize: bodyTextSize,
                                totalMovies: featuredMovies.count,
                                currentIndex: currentHeroIndex,
                                onSelectIndex: { idx in
                                    currentHeroIndex = idx
                                    startHeroTimer()
                                },
                                onPlayVideo: playVideo
                            )
                            .clipped()
                            .layoutPriority(1)
                        }

                        // CATEGORY SECTION (continuous scroll)
                        VStack(spacing: 100) {
                            if !trendingMovies.isEmpty {
                                MovieRowView(
                                    title: "Trending Now",
                                    movies: trendingMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo,
                                    onSeeAll: {
                                        selectedCategory = .trending
                                    }
                                )
                            }

                            if !popularMovies.isEmpty {
                                MovieRowView(
                                    title: "Popular Movies",
                                    movies: popularMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo,
                                    onSeeAll: {
                                        selectedCategory = .popular
                                    }
                                )
                            }

                            // Dynamic Genre Categories
                            ForEach(genreCategories, id: \.genre.id) { category in
                                if !category.movies.isEmpty {
                                    MovieRowView(
                                        title: category.genre.name,
                                        movies: category.movies,
                                        sectionHeaderSize: sectionHeaderSize,
                                        cardTitleSize: cardTitleSize,
                                        cardMetadataSize: cardMetadataSize,
                                        onPlayVideo: playVideo,
                                        onSeeAll: {
                                            selectedCategory = .genre(id: category.genre.id, name: category.genre.name)
                                        }
                                    )
                                }
                            }

                            // Uncategorized Movies
                            if !uncategorizedMovies.isEmpty {
                                MovieRowView(
                                    title: "Other",
                                    movies: uncategorizedMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo,
                                    onSeeAll: {
                                        selectedCategory = .uncategorized
                                    }
                                )
                            }

                            if !recentMovies.isEmpty {
                                MovieRowView(
                                    title: "Recently Added",
                                    movies: recentMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo,
                                    onSeeAll: {
                                        selectedCategory = .recent
                                    }
                                )
                            }

                            if !allMovies.isEmpty {
                                MovieRowView(
                                    title: "All Movies",
                                    movies: allMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo,
                                    onSeeAll: {
                                        selectedCategory = .allMovies
                                    }
                                )
                            }

                            if !tvSeries.isEmpty {
                                MovieRowView(
                                    title: "TV Series",
                                    movies: tvSeries,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo,
                                    onSeeAll: {
                                        selectedCategory = .tvSeries
                                    }
                                )
                            }
                        }
                        .padding(.top, 40) // Spacing after hero
                        .padding(.horizontal, 60)
                        .padding(.bottom, 100)
                    }
                }
                .background(Color.black)
                .ignoresSafeArea()
                #else
                // iOS: Landscape-optimized layout.
                // ContentView's GeometryReader passes the full physical screen frame here,
                // so screenGeo.size.height is the true screen height.
                GeometryReader { screenGeo in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Featured Movie Banner — fills full viewport height (cinematic landscape hero)
                            if !featuredMovies.isEmpty {
                                let heroMovie = featuredMovies[min(currentHeroIndex, featuredMovies.count - 1)]
                                FeaturedMovieBanner(
                                    movie: heroMovie,
                                    heroTitleSize: heroTitleSize,
                                    bodyTextSize: bodyTextSize,
                                    bannerHeight: screenGeo.size.height,
                                    totalMovies: featuredMovies.count,
                                    currentIndex: currentHeroIndex,
                                    onSelectIndex: { idx in
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            currentHeroIndex = idx
                                        }
                                        startHeroTimer() // reset timer on manual tap
                                    },
                                    onPlayVideo: playVideo
                                )
                                .frame(height: screenGeo.size.height)
                            }

                            // Movie Categories — solid black background so the
                            // fixed backdrop above doesn't show behind the carousels
                            VStack(spacing: 50) {
                                if !trendingMovies.isEmpty {
                                    MovieRowView(
                                        title: "Trending Now",
                                        movies: trendingMovies,
                                        sectionHeaderSize: sectionHeaderSize,
                                        cardTitleSize: cardTitleSize,
                                        cardMetadataSize: cardMetadataSize,
                                        onPlayVideo: playVideo,
                                        onSeeAll: { selectedCategory = .trending }
                                    )
                                }

                                if !popularMovies.isEmpty {
                                    MovieRowView(
                                        title: "Popular Movies",
                                        movies: popularMovies,
                                        sectionHeaderSize: sectionHeaderSize,
                                        cardTitleSize: cardTitleSize,
                                        cardMetadataSize: cardMetadataSize,
                                        onPlayVideo: playVideo,
                                        onSeeAll: { selectedCategory = .popular }
                                    )
                                }

                                ForEach(genreCategories, id: \.genre.id) { category in
                                    if !category.movies.isEmpty {
                                        MovieRowView(
                                            title: category.genre.name,
                                            movies: category.movies,
                                            sectionHeaderSize: sectionHeaderSize,
                                            cardTitleSize: cardTitleSize,
                                            cardMetadataSize: cardMetadataSize,
                                            onPlayVideo: playVideo,
                                            onSeeAll: { selectedCategory = .genre(id: category.genre.id, name: category.genre.name) }
                                        )
                                    }
                                }

                                if !uncategorizedMovies.isEmpty {
                                    MovieRowView(
                                        title: "Other",
                                        movies: uncategorizedMovies,
                                        sectionHeaderSize: sectionHeaderSize,
                                        cardTitleSize: cardTitleSize,
                                        cardMetadataSize: cardMetadataSize,
                                        onPlayVideo: playVideo,
                                        onSeeAll: { selectedCategory = .uncategorized }
                                    )
                                }

                                if !recentMovies.isEmpty {
                                    MovieRowView(
                                        title: "Recently Added",
                                        movies: recentMovies,
                                        sectionHeaderSize: sectionHeaderSize,
                                        cardTitleSize: cardTitleSize,
                                        cardMetadataSize: cardMetadataSize,
                                        onPlayVideo: playVideo,
                                        onSeeAll: { selectedCategory = .recent }
                                    )
                                }

                                if !allMovies.isEmpty {
                                    MovieRowView(
                                        title: "All Movies",
                                        movies: allMovies,
                                        sectionHeaderSize: sectionHeaderSize,
                                        cardTitleSize: cardTitleSize,
                                        cardMetadataSize: cardMetadataSize,
                                        onPlayVideo: playVideo,
                                        onSeeAll: { selectedCategory = .allMovies }
                                    )
                                }

                                if !tvSeries.isEmpty {
                                    MovieRowView(
                                        title: "TV Series",
                                        movies: tvSeries,
                                        sectionHeaderSize: sectionHeaderSize,
                                        cardTitleSize: cardTitleSize,
                                        cardMetadataSize: cardMetadataSize,
                                        onPlayVideo: playVideo,
                                        onSeeAll: { selectedCategory = .tvSeries }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                            .padding(.bottom, 50)
                            .background(Color.black)
                        }
                    }
                    .background(.clear)
                }
                #endif
            }
        }
        .onAppear {
            if featuredMovies.isEmpty {
                loadMovies()
            } else {
                startHeroTimer()
            }
        }
        .onDisappear {
            stopHeroTimer()
        }
        .sheet(item: $selectedMovie) { movie in
            MovieDetailView(movie: movie)
        }
        .sheet(item: $selectedCategory) { category in
            CategoryDetailView(categoryType: category)
        }
        .alert("Connection Error", isPresented: $showError) {
            Button("Retry") {
                loadMovies()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unable to load movies. Check your internet connection.")
        }
    }

    private func startHeroTimer() {
        stopHeroTimer()
        guard featuredMovies.count > 1 else { return }
        heroTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            currentHeroIndex = (currentHeroIndex + 1) % featuredMovies.count
        }
    }

    private func stopHeroTimer() {
        heroTimer?.invalidate()
        heroTimer = nil
    }

    private func loadMovies() {
        Task {
            do {
                isLoading = true
                errorMessage = nil

                // Load featured movies (admin-curated, up to 5)
                async let featuredResult = movieService.fetchFeaturedMovies()
                // Load popular and recent in parallel
                async let popularResult = movieService.fetchPopularMovies(page: 1, limit: 10)
                async let recentResult = movieService.fetchRecentMovies(page: 1, limit: 50)

                let (fetchedFeatured, fetchedPopular, allMovies) = try await (featuredResult, popularResult, recentResult)

                featuredMovies = fetchedFeatured.isEmpty ? Array(allMovies.prefix(3)) : fetchedFeatured
                popularMovies = fetchedPopular
                trendingMovies = allMovies.filter { $0.trending }
                recentMovies = allMovies
                currentHeroIndex = 0
                startHeroTimer()

                // Fetch all genres from backend
                let genres = try await movieService.fetchAllGenres()

                // Filter to only genres with movies
                let genresWithMovies = genres.filter { ($0.movieCount ?? 0) > 0 }

                // Fetch genre movies, allMovies, and uncategorized in parallel
                async let allMoviesResult = movieService.fetchAllMovies(sort: "popularity", limit: 50)
                async let uncategorizedResult = movieService.fetchUncategorizedMovies(limit: 10)

                var genreResults: [(genre: Genre, movies: [Movie])] = []
                await withTaskGroup(of: (Genre, [Movie]).self) { group in
                    for genre in genresWithMovies {
                        group.addTask {
                            let movies = (try? await self.movieService.fetchMoviesByGenre(genreId: genre.id, limit: 10)) ?? []
                            return (genre, movies)
                        }
                    }
                    for await (genre, movies) in group {
                        genreResults.append((genre: genre, movies: movies))
                    }
                }
                genreResults.sort { $0.genre.name < $1.genre.name }

                // Wait for all fetches to complete
                let (allMoviesData, uncategorizedData) = try await (allMoviesResult, uncategorizedResult)

                // Assign results
                self.genreCategories = genreResults
                self.allMovies = allMoviesData
                self.uncategorizedMovies = uncategorizedData

                // TODO: TV Series - Backend endpoint doesn't exist yet
                // When backend adds /api/series endpoint, add:
                // self.tvSeries = try await seriesService.fetchTVSeries(limit: 50)

                isLoading = false
            } catch {
                isLoading = false
                print("❌ Error loading movies: \(error)")
                errorMessage = "Unable to load movies. Please check your internet connection."
                showError = true
            }
        }
    }

    private func findMovie(byVideoId videoId: String) -> Movie? {
        // Search through core movie arrays
        let coreArrays = [
            featuredMovies,
            trendingMovies,
            popularMovies,
            recentMovies,
            allMovies,
            uncategorizedMovies,
            tvSeries
        ]

        for movies in coreArrays {
            if let movie = movies.first(where: { $0.youtubeVideoId == videoId }) {
                return movie
            }
        }

        // Search through genre categories
        for category in genreCategories {
            if let movie = category.movies.first(where: { $0.youtubeVideoId == videoId }) {
                return movie
            }
        }

        return nil
    }

    private func playVideo(_ videoId: String) {
        guard let movie = findMovie(byVideoId: videoId) else {
            return
        }

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

// MARK: - Featured Movie Banner

struct FeaturedMovieBanner: View {
    let movie: Movie
    let heroTitleSize: CGFloat
    let bodyTextSize: CGFloat
    var bannerHeight: CGFloat = 650
    var totalMovies: Int = 1
    var currentIndex: Int = 0
    var onSelectIndex: ((Int) -> Void)? = nil
    let onPlayVideo: (String) -> Void

    var body: some View {
        ZStack {
            #if os(tvOS)
            // tvOS: backdrop and gradient live inside the banner
            AsyncImage(url: movie.backdropURL) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(Color.gray.opacity(0.2)).shimmer()
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle().fill(Color.gray.opacity(0.3))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .id(currentIndex)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.8), value: currentIndex)

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.25),
                    .init(color: Color.black.opacity(0.2), location: 0.5),
                    .init(color: Color.black.opacity(0.6), location: 0.72),
                    .init(color: Color.black.opacity(0.85), location: 0.88),
                    .init(color: Color.black, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
            // iOS: backdrop and gradient are rendered at the parent ZStack level
            // in MainBrowseView, where .ignoresSafeArea() is guaranteed to work.
            // This view is transparent — just the content overlay.

            // Content
            #if os(tvOS)
            // tvOS: title/poster pinned at y=300 from banner top, rest flows down.
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 36) {
                    // Poster — fixed size, always same position
                    AsyncImage(url: movie.posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(2/3, contentMode: .fill)
                        default:
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                    }
                    .frame(width: 180, height: 270)
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
                    .clipped()
                    // Crossfade poster when movie changes
                    .id(currentIndex)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.6), value: currentIndex)

                    // Info column
                    VStack(alignment: .leading, spacing: 14) {
                        Text(movie.displayTitle)
                            .font(.system(size: heroTitleSize, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .shadow(radius: 10)

                        // Genre chips
                        if let genres = movie.genres, !genres.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(genres.prefix(3), id: \.id) { genre in
                                    Text(genre.name)
                                        .font(.system(size: bodyTextSize - 10, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(5)
                                }
                            }
                        }

                        // Metadata badges
                        HStack(spacing: 8) {
                            if let year = movie.formattedReleaseYear {
                                Text(year)
                                    .font(.system(size: bodyTextSize - 8, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(6)
                            }
                            if let rating = movie.voteAverage ?? movie.imdbRating {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill").foregroundColor(.yellow)
                                    Text(String(format: "%.1f", rating))
                                }
                                .font(.system(size: bodyTextSize - 8, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(6)
                            }
                            if let runtime = movie.runtimeMinutes, runtime > 0 {
                                Text(movie.formattedRuntime)
                                    .font(.system(size: bodyTextSize - 8, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(6)
                            }
                        }

                        if let overview = movie.description {
                            Text(overview)
                                .font(.system(size: bodyTextSize))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(2)
                                .shadow(radius: 5)
                        }

                        // Action buttons
                        HStack(spacing: 20) {
                            Button {
                                onPlayVideo(movie.youtubeVideoId)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.rectangle.fill").foregroundColor(.red)
                                    Text("Watch on YouTube")
                                }
                                .font(.system(size: bodyTextSize, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Watch \(movie.displayTitle) on YouTube")
                            .accessibilityHint("Opens YouTube app to play the movie")

                            Button {
                                LibraryManager.shared.toggleFavorite(movie.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: movie.isFavorite ? "heart.fill" : "heart")
                                        .foregroundColor(movie.isFavorite ? .red : .white)
                                    Text(movie.isFavorite ? "In My List" : "My List")
                                }
                                .font(.system(size: bodyTextSize, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(movie.isFavorite ? "Remove from My List" : "Add to My List")
                        }

                        // Channel attribution
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: bodyTextSize - 8))
                            Text(movie.channelTitle)
                                .font(.system(size: bodyTextSize - 8))
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }

                // Dots — outside the info column, centered across full width
                if totalMovies > 1 {
                    HStack(spacing: 10) {
                        ForEach(0..<totalMovies, id: \.self) { idx in
                            Button {
                                onSelectIndex?(idx)
                            } label: {
                                Circle()
                                    .fill(idx == currentIndex ? Color.white : Color.white.opacity(0.35))
                                    .frame(width: idx == currentIndex ? 14 : 10,
                                           height: idx == currentIndex ? 14 : 10)
                                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 80)
            .padding(.top, 300)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #else
            // iOS: ZStack(alignment: .bottom) pins this block to the bottom of the
            // banner frame — no Spacer() needed, so content never shifts per-movie.
            VStack(spacing: 0) {
                // Left-aligned content block
                VStack(alignment: .leading, spacing: 10) {
                    // Title
                    Text(movie.displayTitle)
                        .font(.system(size: heroTitleSize, weight: .black))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .shadow(radius: 10)

                    // Metadata badges: year · rating · runtime
                    HStack(spacing: 8) {
                        if let year = movie.formattedReleaseYear {
                            Text(year)
                                .font(.system(size: bodyTextSize - 4, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(6)
                        }
                        if let rating = movie.voteAverage ?? movie.imdbRating {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill").foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                            }
                            .font(.system(size: bodyTextSize - 4, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(6)
                        }
                        if let runtime = movie.runtimeMinutes, runtime > 0 {
                            Text(movie.formattedRuntime)
                                .font(.system(size: bodyTextSize - 4, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }

                    // Description
                    if let overview = movie.description {
                        Text(overview)
                            .font(.system(size: bodyTextSize))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .shadow(radius: 5)
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            onPlayVideo(movie.youtubeVideoId)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.rectangle.fill").foregroundColor(.red)
                                Text("Watch on YouTube")
                            }
                            .font(.system(size: bodyTextSize, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(Color.black.opacity(0.65))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Watch \(movie.displayTitle) on YouTube")

                        Button {
                            LibraryManager.shared.toggleFavorite(movie.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: movie.isFavorite ? "heart.fill" : "heart")
                                    .foregroundColor(movie.isFavorite ? .red : .white)
                                Text(movie.isFavorite ? "In My List" : "My List")
                            }
                            .font(.system(size: bodyTextSize, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)

                    // Channel attribution
                    HStack(spacing: 5) {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: bodyTextSize - 2))
                        Text(movie.channelTitle)
                            .font(.system(size: bodyTextSize - 2))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                // Full width, content left-anchored
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // Dots — .frame(maxWidth:.infinity, alignment:.center) centers the
                // HStack within the full banner width regardless of parent alignment.
                if totalMovies > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<totalMovies, id: \.self) { idx in
                            Button {
                                onSelectIndex?(idx)
                            } label: {
                                Circle()
                                    .fill(idx == currentIndex ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: idx == currentIndex ? 8 : 6,
                                           height: idx == currentIndex ? 8 : 6)
                                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 30)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            #endif
        }
        .frame(height: bannerHeight)
        .clipped()
        .layoutPriority(1)
    }
}

// MARK: - Movie Row View

struct MovieRowView: View {
    let title: String
    let movies: [Movie]
    let sectionHeaderSize: CGFloat
    let cardTitleSize: CGFloat
    let cardMetadataSize: CGFloat
    let onPlayVideo: (String) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Section header with "See All" button
            HStack {
                Text(title)
                    .font(.system(size: sectionHeaderSize, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                // See All button
                Button {
                    onSeeAll()
                } label: {
                    HStack(spacing: 4) {
                        Text("See All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: sectionHeaderSize - 18))
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            #if os(tvOS)
            .padding(.horizontal, 80)
            #else
            .padding(.horizontal, 16)
            #endif

            // Movie carousel
            ScrollView(.horizontal, showsIndicators: false) {
                #if os(tvOS)
                LazyHStack(spacing: 40) {
                    ForEach(movies.prefix(10)) { movie in
                        MovieCard(
                            movie: movie,
                            cardTitleSize: cardTitleSize,
                            cardMetadataSize: cardMetadataSize,
                            onPlayVideo: onPlayVideo
                        )
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 30) // Add vertical breathing room for focus animation
                #else
                LazyHStack(spacing: 15) {
                    ForEach(movies.prefix(10)) { movie in
                        MovieCard(
                            movie: movie,
                            cardTitleSize: cardTitleSize,
                            cardMetadataSize: cardMetadataSize,
                            onPlayVideo: onPlayVideo
                        )
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.vertical, 15) // Add vertical breathing room for focus animation
                #endif
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Movie Card

struct MovieCard: View {
    let movie: Movie
    let cardTitleSize: CGFloat
    let cardMetadataSize: CGFloat
    let onPlayVideo: (String) -> Void

    @State private var isPressed = false

    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif

    var body: some View {
        #if os(tvOS)
        Button {
            onPlayVideo(movie.youtubeVideoId)
        } label: {
            cardContent
        }
        .buttonStyle(.card)
        .scaleEffect(isFocused ? 1.12 : 1.0)  // Increased from 1.08
        .shadow(
            color: .black.opacity(isFocused ? 0.5 : 0.2),
            radius: isFocused ? 40 : 10,
            y: isFocused ? 15 : 5
        )
        .brightness(isFocused ? 0.1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .accessibilityLabel("\(movie.displayTitle). Released in \(movie.formattedReleaseYear ?? "Unknown"). Rating \(movie.formattedRating)")
        .accessibilityHint("Double tap to view movie details")
        .contextMenu {
            contextMenuContent
        }
        #else
        Button {
            onPlayVideo(movie.youtubeVideoId)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(movie.displayTitle). Released in \(movie.formattedReleaseYear ?? "Unknown")")
        .accessibilityHint("Tap to view details")
        .contextMenu {
            contextMenuContent
        }
        #endif
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Poster with shimmer placeholder
            AsyncImage(url: movie.posterURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(2/3, contentMode: .fill)
                        .shimmer()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                case .failure:
                    // Fallback to YouTube thumbnail if poster fails to load
                    AsyncImage(url: movie.youtubeThumbURL) { fallbackPhase in
                        switch fallbackPhase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(2/3, contentMode: .fill)
                        default:
                            // If YouTube thumbnail also fails, show placeholder
                            ZStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .aspectRatio(2/3, contentMode: .fill)
                                VStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.title)
                                        .foregroundColor(.gray)
                                    Text("No poster")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                @unknown default:
                    EmptyView()
                }
            }
            #if os(tvOS)
            .frame(width: 245, height: 368)
            .cornerRadius(12)
            #else
            .frame(width: 126, height: 189)
            .cornerRadius(8)
            #endif
            .clipped()

            // Title
            Text(movie.displayTitle)
                .font(.system(size: cardTitleSize, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Metadata row: Rating • Year • Runtime
            HStack(spacing: 4) {
                // Display rating: prefer TMDB, fallback to IMDB
                if let rating = movie.voteAverage ?? movie.imdbRating {
                    Image(systemName: "star.fill")
                        .font(.system(size: cardMetadataSize - 2))
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: cardMetadataSize))
                        .foregroundColor(.white.opacity(0.7))
                }

                if let year = movie.formattedReleaseYear {
                    Text("•")
                        .foregroundColor(.white.opacity(0.5))
                    Text(year)
                        .font(.system(size: cardMetadataSize))
                        .foregroundColor(.white.opacity(0.7))
                }

                if let runtime = movie.runtimeMinutes, runtime > 0 {
                    Text("•")
                        .foregroundColor(.white.opacity(0.5))
                    Text(movie.formattedRuntime)
                        .font(.system(size: cardMetadataSize))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            // YouTube attribution (TOS-compliant)
            YouTubeAttribution(movie: movie, style: .compact)
        }
        #if os(tvOS)
        .frame(width: 245)
        #else
        .frame(width: 126)
        #endif
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        // Add to / Remove from Favorites
        Button {
            LibraryManager.shared.toggleFavorite(movie.id)
        } label: {
            Label(
                movie.isFavorite ? "Remove from My List" : "Add to My List",
                systemImage: movie.isFavorite ? "heart.slash" : "heart"
            )
        }

        // Open in YouTube app
        Button {
            YouTubePlayerService.shared.playMovie(movie) { _ in }
        } label: {
            Label("Watch on YouTube", systemImage: "play.rectangle")
        }
    }
}

#Preview {
    MainBrowseView()
        .preferredColorScheme(.dark)
}
