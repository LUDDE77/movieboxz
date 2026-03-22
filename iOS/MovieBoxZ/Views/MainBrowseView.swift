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

    // Platform-specific font sizes
    #if os(tvOS)
    private let heroTitleSize: CGFloat = 72
    private let sectionHeaderSize: CGFloat = 42
    private let cardTitleSize: CGFloat = 31
    private let cardMetadataSize: CGFloat = 25
    private let bodyTextSize: CGFloat = 29
    #else
    private let heroTitleSize: CGFloat = 56
    private let sectionHeaderSize: CGFloat = 24
    private let cardTitleSize: CGFloat = 18
    private let cardMetadataSize: CGFloat = 14
    private let bodyTextSize: CGFloat = 18
    #endif

    var body: some View {
        ZStack {
            if isLoading && featuredMovies.isEmpty {
                // Show skeleton screen on initial load
                LoadingSkeletonView()
            } else {
                #if os(tvOS)
                // tvOS: Natural Scrolling Hero (scrolls away)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // HERO SECTION (scrolls away naturally)
                        if let featuredMovie = featuredMovies.first {
                            FeaturedMovieBanner(
                                movie: featuredMovie,
                                heroTitleSize: heroTitleSize,
                                bodyTextSize: bodyTextSize,
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
                // iOS: Original scrolling layout
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Featured Movie Banner
                        if let featuredMovie = featuredMovies.first {
                            FeaturedMovieBanner(
                                movie: featuredMovie,
                                heroTitleSize: heroTitleSize,
                                bodyTextSize: bodyTextSize,
                                onPlayVideo: playVideo
                            )
                            .frame(height: 400)
                        }

                        // Movie Categories
                        VStack(spacing: 50) {
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
                        .padding(.top, 30)
                        .padding(.bottom, 50)
                    }
                }
                .background(Color.black)
                .ignoresSafeArea()
                #endif
            }
        }
        .onAppear {
            if featuredMovies.isEmpty {
                loadMovies()
            }
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

    private func loadMovies() {
        Task {
            do {
                isLoading = true
                errorMessage = nil

                // Load all recent movies
                let allMovies = try await movieService.fetchRecentMovies(limit: 50)

                // Populate core categories
                featuredMovies = Array(allMovies.prefix(1))
                trendingMovies = allMovies.filter { $0.trending }
                popularMovies = Array(allMovies.prefix(10))
                recentMovies = allMovies

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
    let onPlayVideo: (String) -> Void

    private let bannerHeight: CGFloat = 650

    var body: some View {
        GeometryReader { geo in
            let bannerWidth = geo.size.width
            ZStack {
                // Background Image - fills available width
                AsyncImage(url: movie.backdropURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .shimmer()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: bannerWidth, height: bannerHeight)
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: bannerWidth, height: bannerHeight)
                .position(x: bannerWidth / 2, y: bannerHeight / 2)

                // Gradient Overlay (stronger fade in bottom 40%)
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
                .frame(width: bannerWidth, height: bannerHeight)

            // Content - absolute position at bottom (independent of backdrop)
            VStack {
                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                        // Title
                        Text(movie.displayTitle)
                            .font(.system(size: heroTitleSize, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .shadow(radius: 10)

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

                            // Display rating: prefer TMDB, fallback to IMDB
                            if let rating = movie.voteAverage ?? movie.imdbRating {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                    Text(String(format: "%.1f", rating))
                                }
                                .font(.system(size: bodyTextSize - 8, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(6)
                            }
                        }

                        // Description (2 lines maximum)
                        if let overview = movie.description {
                            Text(overview)
                                .font(.system(size: bodyTextSize))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(2)
                                .shadow(radius: 5)
                                .padding(.vertical, 4)
                        }

                        HStack(spacing: 15) {
                            // Play button with YouTube branding
                            Button {
                                onPlayVideo(movie.youtubeVideoId)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundColor(.red)
                                    Text("Watch on YouTube")
                                }
                                .font(.system(size: bodyTextSize, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 25)
                                .padding(.vertical, 12)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Watch \(movie.displayTitle) on YouTube")
                            .accessibilityHint("Opens YouTube app to play the movie")

                            Spacer()

                            // YouTube channel attribution
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: bodyTextSize - 10))
                                Text(movie.channelTitle)
                                    .font(.system(size: bodyTextSize - 10))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }

                    Spacer()
                }
                #if os(tvOS)
                .frame(height: 200)
                .padding(.horizontal, 80)
                .padding(.bottom, 30)
                #else
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
                #endif
            }
            .frame(width: bannerWidth, height: bannerHeight)
        }
        .clipped()
        .layoutPriority(1)
        }
        .frame(height: bannerHeight)
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
                .padding(.vertical, 15) // Add vertical breathing room for focus animation
                #endif
            }
        }
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
