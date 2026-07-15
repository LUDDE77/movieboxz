import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct MainBrowseView: View {
    @EnvironmentObject private var movieService: MovieService

    // Browse data (featured/trending/popular/recent/genres/uncategorized/all)
    // lives on the shared MovieService so it survives tab switches instead
    // of being refetched (and re-skeletoned) every time this view reappears.
    private var featuredMovies: [Movie] { movieService.featuredMovies }
    private var trendingMovies: [Movie] { movieService.trendingMovies }
    private var popularMovies: [Movie] { movieService.popularMovies }
    private var recentMovies: [Movie] { movieService.recentMovies }
    private var genreCategories: [(genre: Genre, movies: [Movie])] { movieService.genreCategories }
    private var uncategorizedMovies: [Movie] { movieService.uncategorizedMovies }
    private var allMovies: [Movie] { movieService.allBrowseMovies }

    @State private var tvSeries: [Movie] = [] // Placeholder for TV series
    @State private var topImdbMovies: [Movie] = [] // High Score IMDB row

    // Browse-by-era rows
    @State private var decade2000s: [Movie] = []   // "Modern Cinema"
    @State private var decade8090: [Movie] = []    // "The 80s & 90s"
    @State private var decade6070: [Movie] = []    // "The 60s & 70s"
    @State private var decadeClassic: [Movie] = [] // "Classic Cinema"

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
            // Full-screen ink base — fills safe areas edge to edge
            Color.mbzInk.ignoresSafeArea()

            // iOS: Backdrop placed at ZStack level so it fills the full screen frame
            // offered by ContentView's GeometryReader layout.
            #if os(iOS)
            if !featuredMovies.isEmpty, !isLoading {
                let heroMovie = featuredMovies[min(currentHeroIndex, featuredMovies.count - 1)]
                // CrossfadeBackdrop keeps the previously-loaded backdrop on screen
                // until the next one has finished loading, then crossfades between
                // them — no flash to an empty/gray frame on index change.
                // .ignoresSafeArea() so the hero bleeds edge-to-edge on iPhone
                // (dynamic island / home indicator), matching iPad/tvOS.
                CrossfadeBackdrop(url: heroMovie.backdropURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.4),
                        .init(color: Color.mbzInk.opacity(0.3), location: 0.6),
                        .init(color: Color.mbzInk.opacity(0.7), location: 0.8),
                        .init(color: Color.mbzInk, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
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
                                bannerHeight: 780,
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

                        // CATEGORY SECTION (continuous scroll) — Lazy so off-screen
                        // rails don't instantiate cards / fire image loads until
                        // scrolled near.
                        LazyVStack(spacing: 100) {
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

                            if !topImdbMovies.isEmpty {
                                MovieRowView(
                                    title: "High Score IMDB",
                                    movies: topImdbMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo,
                                    onSeeAll: {
                                        selectedCategory = .topImdb
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

                            // Browse by era — after genres, before Other/Recent
                            eraRows

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
                .background(Color.mbzInk)
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

                                if !topImdbMovies.isEmpty {
                                    MovieRowView(
                                        title: "High Score IMDB",
                                        movies: topImdbMovies,
                                        sectionHeaderSize: sectionHeaderSize,
                                        cardTitleSize: cardTitleSize,
                                        cardMetadataSize: cardMetadataSize,
                                        onPlayVideo: playVideo,
                                        onSeeAll: { selectedCategory = .topImdb }
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

                                // Browse by era — after genres, before Other/Recent
                                eraRows

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
                            .background(Color.mbzInk)
                        }
                    }
                    .background(.clear)
                    .refreshable {
                        await refreshMovies()
                    }
                }
                // Re-assert ignoresSafeArea() here (matching the tvOS branch above)
                // so screenGeo.size is the true full-screen frame and the hero/
                // content bleed edge-to-edge on iPhone instead of being inset by
                // the dynamic-island/home-indicator safe areas.
                .ignoresSafeArea()
                #endif
            }
        }
        .onAppear {
            if movieService.hasLoadedBrowseData {
                // Data already cached from a previous appearance (or the
                // splash-screen preload) — just resume the hero carousel,
                // no refetch, no skeleton.
                currentHeroIndex = min(currentHeroIndex, max(featuredMovies.count - 1, 0))
                startHeroTimer()
                if topImdbMovies.isEmpty {
                    loadTopImdb()
                }
                if decade2000s.isEmpty && decade8090.isEmpty && decade6070.isEmpty && decadeClassic.isEmpty {
                    loadEraRowsIfNeeded()
                }
            } else {
                loadMovies()
            }
        }
        .onDisappear {
            stopHeroTimer()
        }
        #if os(tvOS)
        .fullScreenCover(item: $selectedMovie) { movie in
            MovieDetailView(movie: movie)
        }
        .fullScreenCover(item: $selectedCategory) { category in
            CategoryDetailView(categoryType: category)
        }
        #else
        .sheet(item: $selectedMovie) { movie in
            MovieDetailView(movie: movie)
        }
        .sheet(item: $selectedCategory) { category in
            CategoryDetailView(categoryType: category)
        }
        #endif
        .alert("Connection Error", isPresented: $showError) {
            Button("Retry") {
                loadMovies()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unable to load movies. Check your internet connection.")
        }
    }

    // Browse-by-era rows — rendered as a group after the dynamic genre
    // carousels and before the "Other"/Recent rows. Shared by both the tvOS
    // and iOS layout branches so they never drift.
    @ViewBuilder
    private var eraRows: some View {
        if !decade2000s.isEmpty {
            MovieRowView(
                title: "Modern Cinema",
                movies: decade2000s,
                sectionHeaderSize: sectionHeaderSize,
                cardTitleSize: cardTitleSize,
                cardMetadataSize: cardMetadataSize,
                onPlayVideo: playVideo,
                onSeeAll: { selectedCategory = .decade(yearMin: 2000, yearMax: nil, title: "Modern Cinema") }
            )
        }

        if !decade8090.isEmpty {
            MovieRowView(
                title: "The 80s & 90s",
                movies: decade8090,
                sectionHeaderSize: sectionHeaderSize,
                cardTitleSize: cardTitleSize,
                cardMetadataSize: cardMetadataSize,
                onPlayVideo: playVideo,
                onSeeAll: { selectedCategory = .decade(yearMin: 1980, yearMax: 1999, title: "The 80s & 90s") }
            )
        }

        if !decade6070.isEmpty {
            MovieRowView(
                title: "The 60s & 70s",
                movies: decade6070,
                sectionHeaderSize: sectionHeaderSize,
                cardTitleSize: cardTitleSize,
                cardMetadataSize: cardMetadataSize,
                onPlayVideo: playVideo,
                onSeeAll: { selectedCategory = .decade(yearMin: 1960, yearMax: 1979, title: "The 60s & 70s") }
            )
        }

        if !decadeClassic.isEmpty {
            MovieRowView(
                title: "Classic Cinema",
                movies: decadeClassic,
                sectionHeaderSize: sectionHeaderSize,
                cardTitleSize: cardTitleSize,
                cardMetadataSize: cardMetadataSize,
                onPlayVideo: playVideo,
                onSeeAll: { selectedCategory = .decade(yearMin: nil, yearMax: 1959, title: "Classic Cinema") }
            )
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

                async let topImdb = movieService.fetchTopImdbMovies(limit: 20)

                try await movieService.loadBrowseData()

                // Resilient: only overwrite on success so a transient failure
                // leaves any previously-loaded row intact (never blanks it).
                if let v = try? await topImdb { topImdbMovies = v }
                await loadEraRows()

                currentHeroIndex = 0
                startHeroTimer()

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

    /// Loads just the High Score IMDB row (used when the shared browse cache is
    /// already populated but this @State row hasn't been fetched yet). Resilient:
    /// a failure leaves the row empty.
    private func loadTopImdb() {
        Task {
            if let v = try? await movieService.fetchTopImdbMovies(limit: 20) {
                topImdbMovies = v
            }
        }
    }

    /// Loads the four browse-by-era rows in parallel. Resilient: a failure on
    /// any one bound leaves that row empty rather than erroring the page.
    private func loadEraRows() async {
        async let d2000 = movieService.fetchMoviesByYearRange(yearMin: 2000, yearMax: nil, limit: 20)
        async let d8090 = movieService.fetchMoviesByYearRange(yearMin: 1980, yearMax: 1999, limit: 20)
        async let d6070 = movieService.fetchMoviesByYearRange(yearMin: 1960, yearMax: 1979, limit: 20)
        async let dClassic = movieService.fetchMoviesByYearRange(yearMin: nil, yearMax: 1959, limit: 20)

        // Only overwrite each row on success — a transient failure keeps the
        // previously-loaded row instead of blanking it on refresh.
        if let v = try? await d2000 { decade2000s = v }
        if let v = try? await d8090 { decade8090 = v }
        if let v = try? await d6070 { decade6070 = v }
        if let v = try? await dClassic { decadeClassic = v }
    }

    /// Loads just the browse-by-era rows when the shared cache is already
    /// populated but these @State rows haven't been fetched yet.
    private func loadEraRowsIfNeeded() {
        Task { await loadEraRows() }
    }

    /// Manual reload path for pull-to-refresh — bypasses the cache.
    private func refreshMovies() async {
        do {
            async let topImdb = movieService.fetchTopImdbMovies(limit: 20)
            try await movieService.loadBrowseData(force: true)
            if let v = try? await topImdb { topImdbMovies = v }
            await loadEraRows()
            currentHeroIndex = 0
            startHeroTimer()
        } catch {
            print("❌ Error refreshing movies: \(error)")
            errorMessage = "Unable to refresh movies. Please check your internet connection."
            showError = true
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
            tvSeries,
            topImdbMovies,
            decade2000s,
            decade8090,
            decade6070,
            decadeClassic
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

// MARK: - Crossfade Backdrop

/// Hero backdrop image that never flashes to empty/gray when the movie
/// changes. It keeps whatever image is currently on screen ("base") visible
/// while the next URL loads in the background, then crossfades a new layer
/// ("incoming") on top of it before promoting it to the base. Because the
/// view identity never changes across index changes (no `.id()` on the
/// caller), this state survives every hero rotation.
struct CrossfadeBackdrop: View {
    let url: URL?

    @State private var baseImage: Image?
    @State private var incomingImage: Image?
    @State private var incomingOpacity: Double = 0
    @State private var loadedURL: URL?

    var body: some View {
        ZStack {
            if let baseImage {
                baseImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Dark ink base (not a light gray) so an in-flight load reads as
                // an intentional dark stage rather than a blank flash.
                Color.mbzInk
            }
            if let incomingImage {
                incomingImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(incomingOpacity)
            }
        }
        .task(id: url) {
            await load(url)
        }
    }

    @MainActor
    private func load(_ url: URL?) async {
        guard let url, url != loadedURL else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let uiImage = UIImage(data: data) else { return }
        guard !Task.isCancelled else { return }
        let image = Image(uiImage: uiImage)

        if baseImage == nil {
            // First load ever — nothing to crossfade from yet.
            baseImage = image
            loadedURL = url
            return
        }

        incomingImage = image
        incomingOpacity = 0
        withAnimation(.easeInOut(duration: 0.8)) {
            incomingOpacity = 1
        }
        loadedURL = url

        try? await Task.sleep(nanoseconds: 850_000_000)

        // Only promote if this is still the most recently requested image
        // (guards against rapid dot-tapping racing multiple loads).
        guard !Task.isCancelled, loadedURL == url else { return }
        baseImage = incomingImage
        incomingImage = nil
        incomingOpacity = 0
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

    // Fixed block heights so the info layout is IDENTICAL for every movie —
    // reserved regardless of whether a given movie actually has a short
    // title, a description, or any metadata badges. This is what keeps the
    // buttons/channel line pinned to the same Y as the carousel rotates.
    #if os(tvOS)
    private var titleBlockHeight: CGFloat { heroTitleSize * 1.25 } // 1 line
    private var genreRowHeight: CGFloat { (bodyTextSize - 10) * 1.3 + 10 }
    private var metadataRowHeight: CGFloat { (bodyTextSize - 8) * 1.3 + 12 }
    private var descriptionBlockHeight: CGFloat { bodyTextSize * 1.3 * 2 } // 2 lines
    #else
    private var titleBlockHeight: CGFloat { heroTitleSize * 1.25 * 2 } // 2 lines
    private var metadataRowHeight: CGFloat { (bodyTextSize - 4) * 1.3 + 10 }
    private var descriptionBlockHeight: CGFloat { bodyTextSize * 1.3 * 2 } // 2 lines
    #endif

    var body: some View {
        ZStack {
            #if os(tvOS)
            // tvOS: full-bleed cinematic backdrop. CrossfadeBackdrop keeps the
            // previous image visible until the next finishes loading, then
            // crossfades — no flash to gray.
            // ONE backdrop view (stable identity across movie changes) so its
            // crossfade image state never resets to a blank frame. Movies with
            // a real 16:9 backdrop show it sharp; movies without one blur their
            // poster into an ambient wash (radius/scale toggled by modifier, not
            // by swapping the view — swapping would reload from scratch).
            CrossfadeBackdrop(url: movie.heroBackdropURL ?? movie.posterURL)
                .scaleEffect(movie.hasLandscapeBackdrop ? 1.0 : 1.1)
                .blur(radius: movie.hasLandscapeBackdrop ? 0 : 40)
                .overlay(movie.hasLandscapeBackdrop ? Color.clear : Color.mbzInk.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // Bottom scrim — anchors the content and blends into the rows below.
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.25),
                    .init(color: Color.mbzInk.opacity(0.2), location: 0.5),
                    .init(color: Color.mbzInk.opacity(0.6), location: 0.72),
                    .init(color: Color.mbzInk.opacity(0.85), location: 0.88),
                    .init(color: Color.mbzInk, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Left scrim — keeps the bottom-left title/synopsis legible over
            // bright artwork.
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.mbzInk.opacity(0.8), location: 0.0),
                    .init(color: Color.mbzInk.opacity(0.35), location: 0.4),
                    .init(color: .clear, location: 0.7)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top scrim — keeps the overlaid tab bar readable over the backdrop.
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.mbzInk.opacity(0.65), location: 0.0),
                    .init(color: .clear, location: 0.2)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
            // iOS: backdrop and gradient are rendered at the parent ZStack level
            // in MainBrowseView, where .ignoresSafeArea() is guaranteed to work.
            // This view is transparent — just the content overlay.

            // Content — cinematic full-bleed hero, anchored bottom-left, no
            // floating poster (the backdrop is the hero; title + metadata sit
            // over the scrim like Apple TV+/Netflix).
            #if os(tvOS)
            VStack(alignment: .leading, spacing: 18) {
                        // Title — always reserves 1-line height so the rest of
                        // the block sits at the same Y for every movie.
                        Text(movie.displayTitle)
                            .font(.system(size: heroTitleSize, weight: .black))
                            .foregroundColor(.mbzScreen)
                            .lineLimit(1)
                            .frame(height: titleBlockHeight, alignment: .bottomLeading)
                            .shadow(radius: 10)

                        // Genre chips — HStack always present (even with zero
                        // chips) so this row's height never collapses to 0.
                        HStack(spacing: 8) {
                            if let genres = movie.genres, !genres.isEmpty {
                                ForEach(genres.prefix(3), id: \.id) { genre in
                                    Text(genre.name)
                                        .font(.system(size: bodyTextSize - 10, weight: .medium))
                                        .foregroundColor(.mbzMuted)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .frame(height: genreRowHeight, alignment: .leading)

                        // Metadata badges — fixed row height regardless of how
                        // many of year/rating/runtime are actually available.
                        HStack(spacing: 8) {
                            if let year = movie.formattedReleaseYear {
                                Text(year)
                                    .font(.system(size: bodyTextSize - 8, weight: .semibold))
                                    .foregroundColor(.mbzScreen)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.mbzSlate.opacity(0.8))
                                    .cornerRadius(6)
                            }
                            if let rating = movie.voteAverage ?? movie.imdbRating {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill").foregroundColor(.mbzGold)
                                    Text(String(format: "%.1f", rating))
                                }
                                .font(.system(size: bodyTextSize - 8, weight: .semibold))
                                .foregroundColor(.mbzScreen)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.mbzSlate.opacity(0.8))
                                .cornerRadius(6)
                            }
                            if let runtime = movie.runtimeMinutes, runtime > 0 {
                                Text(movie.formattedRuntime)
                                    .font(.system(size: bodyTextSize - 8, weight: .semibold))
                                    .foregroundColor(.mbzScreen)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.mbzSlate.opacity(0.8))
                                    .cornerRadius(6)
                            }
                        }
                        .frame(height: metadataRowHeight, alignment: .leading)

                        // Description — always reserves its 2-line height, even
                        // when the movie has no description, via an invisible
                        // placeholder of the same size.
                        Text(movie.description ?? " ")
                            .font(.system(size: bodyTextSize))
                            .foregroundColor(.mbzMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(height: descriptionBlockHeight, alignment: .topLeading)
                            .opacity(movie.description == nil ? 0 : 1)
                            .shadow(radius: 5)

                        // Action buttons
                        HStack(spacing: 20) {
                            Button {
                                onPlayVideo(movie.youtubeVideoId)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle.fill").foregroundColor(.mbzScreen)
                                    Text("More Info")
                                }
                                .font(.system(size: bodyTextSize, weight: .bold))
                                .foregroundColor(.mbzInk)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 16)
                                .background(Color.mbzGold)
                                .cornerRadius(12)
                            }
                            .buttonStyle(FocusBorderButtonStyle(variant: .action(cornerRadius: 12)))
                            .accessibilityLabel("More info about \(movie.displayTitle)")
                            .accessibilityHint("Opens movie details")

                            Button {
                                LibraryManager.shared.toggleFavorite(movie.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: movie.isFavorite ? "heart.fill" : "heart")
                                        .foregroundColor(movie.isFavorite ? .mbzGold : .mbzScreen)
                                    Text(movie.isFavorite ? "In My List" : "My List")
                                }
                                .font(.system(size: bodyTextSize, weight: .semibold))
                                .foregroundColor(.mbzScreen)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .background(Color.mbzSlate.opacity(0.6))
                                .cornerRadius(10)
                            }
                            #if os(tvOS)
                            .buttonStyle(FocusBorderButtonStyle(variant: .action(cornerRadius: 10)))
                            #else
                            .buttonStyle(.plain)
                            #endif
                            .accessibilityLabel(movie.isFavorite ? "Remove from My List" : "Add to My List")
                        }

                        // Channel attribution
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.mbzRed)
                                .font(.system(size: bodyTextSize - 8))
                            Text(movie.channelTitle)
                                .font(.system(size: bodyTextSize - 8))
                                .foregroundColor(.mbzMuted)
                                .lineLimit(1)
                        }

                // Dots — decorative page indicator, left-aligned under the
                // content (non-interactive on tvOS to avoid a focus trap).
                if totalMovies > 1 {
                    HStack(spacing: 10) {
                        ForEach(0..<totalMovies, id: \.self) { idx in
                            Circle()
                                .fill(idx == currentIndex ? Color.mbzGold : Color.mbzScreen.opacity(0.35))
                                .frame(width: idx == currentIndex ? 14 : 10,
                                       height: idx == currentIndex ? 14 : 10)
                                .animation(.easeInOut(duration: 0.2), value: currentIndex)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            #else
            // iOS: ZStack(alignment: .bottom) pins this block to the bottom of the
            // banner frame — no Spacer() needed, so content never shifts per-movie.
            VStack(spacing: 0) {
                // Left-aligned content block
                VStack(alignment: .leading, spacing: 10) {
                    // Title — always reserves 2-line height so shorter titles
                    // don't shift the metadata/description/buttons below.
                    Text(movie.displayTitle)
                        .font(.system(size: heroTitleSize, weight: .black))
                        .foregroundColor(.mbzScreen)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: titleBlockHeight, alignment: .bottomLeading)
                        .shadow(radius: 10)

                    // Metadata badges: year · rating · runtime — fixed row
                    // height regardless of how many badges are present.
                    HStack(spacing: 8) {
                        if let year = movie.formattedReleaseYear {
                            Text(year)
                                .font(.system(size: bodyTextSize - 4, weight: .semibold))
                                .foregroundColor(.mbzScreen)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.mbzSlate.opacity(0.8))
                                .cornerRadius(6)
                        }
                        if let rating = movie.voteAverage ?? movie.imdbRating {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill").foregroundColor(.mbzGold)
                                Text(String(format: "%.1f", rating))
                            }
                            .font(.system(size: bodyTextSize - 4, weight: .semibold))
                            .foregroundColor(.mbzScreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.mbzSlate.opacity(0.8))
                            .cornerRadius(6)
                        }
                        if let runtime = movie.runtimeMinutes, runtime > 0 {
                            Text(movie.formattedRuntime)
                                .font(.system(size: bodyTextSize - 4, weight: .semibold))
                                .foregroundColor(.mbzScreen)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.mbzSlate.opacity(0.8))
                                .cornerRadius(6)
                        }
                    }
                    .frame(height: metadataRowHeight, alignment: .leading)

                    // Description — always reserves its 2-line height, even
                    // when the movie has no description, via an invisible
                    // placeholder of the same size (so buttons below never move).
                    Text(movie.description ?? " ")
                        .font(.system(size: bodyTextSize))
                        .foregroundColor(.mbzMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: descriptionBlockHeight, alignment: .topLeading)
                        .opacity(movie.description == nil ? 0 : 1)
                        .shadow(radius: 5)

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            onPlayVideo(movie.youtubeVideoId)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill").foregroundColor(.mbzScreen)
                                Text("More Info")
                            }
                            .font(.system(size: bodyTextSize, weight: .semibold))
                            .foregroundColor(.mbzScreen)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(Color.mbzSlate.opacity(0.9))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("More info about \(movie.displayTitle)")
                        .accessibilityHint("Opens movie details")

                        Button {
                            LibraryManager.shared.toggleFavorite(movie.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: movie.isFavorite ? "heart.fill" : "heart")
                                    .foregroundColor(movie.isFavorite ? .mbzGold : .mbzScreen)
                                Text(movie.isFavorite ? "In My List" : "My List")
                            }
                            .font(.system(size: bodyTextSize, weight: .medium))
                            .foregroundColor(.mbzScreen)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(Color.mbzSlate.opacity(0.6))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)

                    // Channel attribution
                    HStack(spacing: 5) {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.mbzRed)
                            .font(.system(size: bodyTextSize - 2))
                        Text(movie.channelTitle)
                            .font(.system(size: bodyTextSize - 2))
                            .foregroundColor(.mbzMuted)
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
                                    .fill(idx == currentIndex ? Color.mbzGold : Color.mbzMuted.opacity(0.4))
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
                    .font(.system(size: sectionHeaderSize, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(.mbzGold)
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
                    .font(.system(size: sectionHeaderSize - 18, weight: .semibold))
                    .foregroundColor(.mbzGold.opacity(0.85))
                }
                #if os(tvOS)
                .buttonStyle(FocusBorderButtonStyle(variant: .action(cornerRadius: 8)))
                #else
                .buttonStyle(.plain)
                #endif
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
    private let cornerR: CGFloat = 12
    private let posterW: CGFloat = 245
    private let posterH: CGFloat = 368
    #else
    private let cornerR: CGFloat = 8
    private let posterW: CGFloat = 126
    private let posterH: CGFloat = 189
    #endif

    var body: some View {
        #if os(tvOS)
        Button {
            onPlayVideo(movie.youtubeVideoId)
        } label: {
            cardContent
        }
        .buttonStyle(FocusBorderButtonStyle())
        .brightness(isFocused ? 0.08 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isFocused)
        .accessibilityLabel("\(movie.displayTitle). Released in \(movie.formattedReleaseYear ?? "Unknown"). Rating \(movie.formattedRating)")
        .accessibilityHint("Double tap to view movie details")
        // tvOS: no .contextMenu here — a single clean select→detail
        // interaction avoids competing with the focus/select action
        // (contextMenuContent's actions are reachable from MovieDetailView).
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
            // Poster — rating chip + YouTube cue sit ON the artwork so the
            // caption stays to a clean title + year.
            poster
                .overlay(alignment: .topLeading) {
                    if let rating = movie.voteAverage ?? movie.imdbRating {
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: cardMetadataSize, weight: .bold, design: .monospaced))
                            .foregroundColor(.mbzInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.mbzGold)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // "Plays on YouTube" cue (red = play), keeps the ToS nod quiet
                    Image(systemName: "play.fill")
                        .font(.system(size: max(cardMetadataSize - 2, 8), weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.mbzRed)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }

            // Title — single line for an even baseline across the rail
            Text(movie.displayTitle)
                .font(.system(size: cardTitleSize, weight: .semibold))
                .foregroundColor(.mbzScreen)
                .lineLimit(1)
                .truncationMode(.tail)

            // Year only — runtime/rating live on the artwork or the detail screen
            if let year = movie.formattedReleaseYear {
                Text(year)
                    .font(.system(size: cardMetadataSize, weight: .regular, design: .monospaced))
                    .foregroundColor(.mbzMuted)
            }
        }
        .frame(width: posterW)
    }

    // Poster image with shimmer + YouTube-thumb fallback and a hairline edge.
    private var poster: some View {
        AsyncImage(url: movie.posterURL) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color.mbzSlate)
                    .aspectRatio(2/3, contentMode: .fill)
                    .shimmer()
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
            case .failure:
                AsyncImage(url: movie.youtubeThumbURL) { fallbackPhase in
                    switch fallbackPhase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(2/3, contentMode: .fill)
                    default:
                        ZStack {
                            Rectangle()
                                .fill(Color.mbzSlate)
                                .aspectRatio(2/3, contentMode: .fill)
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.title)
                                    .foregroundColor(.mbzMuted)
                                Text("No poster")
                                    .font(.caption)
                                    .foregroundColor(.mbzMuted)
                            }
                        }
                    }
                }
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: posterW, height: posterH)
        .clipShape(RoundedRectangle(cornerRadius: cornerR))
        .overlay(
            RoundedRectangle(cornerRadius: cornerR)
                .stroke(Color.mbzScreen.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        // Add to / Remove from Favorites
        Button {
            #if os(iOS)
            HapticFeedback.light()
            #endif
            LibraryManager.shared.toggleFavorite(movie.id)
        } label: {
            Label(
                movie.isFavorite ? "Remove from My List" : "Add to My List",
                systemImage: movie.isFavorite ? "heart.slash" : "heart"
            )
        }

        // Open in YouTube app — routed through the branded pre-roll (ad seam)
        Button {
            #if os(iOS)
            HapticFeedback.medium()
            #endif
            WatchCoordinator.shared.requestWatch(movie)
        } label: {
            Label("Watch on YouTube", systemImage: "play.rectangle")
        }
    }
}

#Preview {
    MainBrowseView()
        .environmentObject(MovieService())
        .preferredColorScheme(.dark)
}
