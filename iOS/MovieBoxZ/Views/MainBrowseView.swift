import SwiftUI
import AVKit
import AVFoundation

struct MainBrowseView: View {
    @StateObject private var movieService = MovieService()
    @State private var featuredMovies: [Movie] = []
    @State private var trendingMovies: [Movie] = []
    @State private var popularMovies: [Movie] = []
    @State private var recentMovies: [Movie] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedMovie: Movie?

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
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        // Featured Movie Banner
                        if let featuredMovie = featuredMovies.first {
                            FeaturedMovieBanner(
                                movie: featuredMovie,
                                heroTitleSize: heroTitleSize,
                                bodyTextSize: bodyTextSize,
                                onPlayVideo: playVideo
                            )
                            #if os(tvOS)
                            .frame(height: 480)
                            #else
                            .frame(height: 500)
                            #endif
                        }

                        // Movie Categories
                        #if os(tvOS)
                        VStack(spacing: 60) {
                            if !trendingMovies.isEmpty {
                                MovieRowView(
                                    title: "Trending Now",
                                    movies: trendingMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo
                                )
                            }

                            if !popularMovies.isEmpty {
                                MovieRowView(
                                    title: "Popular Movies",
                                    movies: popularMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo
                                )
                            }

                            if !recentMovies.isEmpty {
                                MovieRowView(
                                    title: "Recently Added",
                                    movies: recentMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo
                                )
                            }
                        }
                        .padding(.top, 50)
                        .padding(.horizontal, 60)
                        .padding(.bottom, 100)
                        #else
                        VStack(spacing: 30) {
                            if !trendingMovies.isEmpty {
                                MovieRowView(
                                    title: "Trending Now",
                                    movies: trendingMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo
                                )
                            }

                            if !popularMovies.isEmpty {
                                MovieRowView(
                                    title: "Popular Movies",
                                    movies: popularMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo
                                )
                            }

                            if !recentMovies.isEmpty {
                                MovieRowView(
                                    title: "Recently Added",
                                    movies: recentMovies,
                                    sectionHeaderSize: sectionHeaderSize,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: playVideo
                                )
                            }
                        }
                        .padding(.top, 30)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 50)
                        #endif
                    }
                }
                .background(Color.black)
                .ignoresSafeArea()
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

                // Populate categories
                featuredMovies = Array(allMovies.prefix(1))
                trendingMovies = allMovies.filter { $0.trending }
                popularMovies = Array(allMovies.prefix(10))
                recentMovies = allMovies

                isLoading = false
            } catch {
                isLoading = false
                print("❌ Error loading movies: \(error)")
                errorMessage = "Unable to load movies. Please check your internet connection."
                showError = true
            }
        }
    }

    private func playVideo(_ videoId: String) {
        if let movie = featuredMovies.first(where: { $0.youtubeVideoId == videoId }) ??
                       trendingMovies.first(where: { $0.youtubeVideoId == videoId }) ??
                       popularMovies.first(where: { $0.youtubeVideoId == videoId }) ??
                       recentMovies.first(where: { $0.youtubeVideoId == videoId }) {

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

// MARK: - Featured Movie Banner

struct FeaturedMovieBanner: View {
    let movie: Movie
    let heroTitleSize: CGFloat
    let bodyTextSize: CGFloat
    let onPlayVideo: (String) -> Void

    var body: some View {
        ZStack {
            // Background Image with shimmer placeholder
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
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                @unknown default:
                    EmptyView()
                }
            }
            .clipped()

            // Gradient Overlay (ensures text readability)
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.black.opacity(0.3), location: 0.4),
                    .init(color: Color.black.opacity(0.9), location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )

            // Content
            VStack(alignment: .leading) {
                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                        // Title
                        Text(movie.title)
                            .font(.system(size: heroTitleSize, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(2)
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

                            if let rating = movie.voteAverage {
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

                        // Description
                        if let overview = movie.description {
                            Text(overview)
                                .font(.system(size: bodyTextSize))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(3)
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
                            .accessibilityLabel("Watch \(movie.title) on YouTube")
                            .accessibilityHint("Opens YouTube app to play the movie")
                        }

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

                    Spacer()
                }
                #if os(tvOS)
                .padding(.horizontal, 80)
                .padding(.bottom, 60)
                #else
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                #endif
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Section header with "See All" button
            HStack {
                Text(title)
                    .font(.system(size: sectionHeaderSize, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                // TODO: Implement full category view
                Button {
                    // Navigate to full category page
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
            .padding(.horizontal, 20)
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
                .padding(.horizontal, 20)
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
        .accessibilityLabel("\(movie.title). Released in \(movie.formattedReleaseYear ?? "Unknown"). Rating \(movie.formattedRating)")
        .accessibilityHint("Double tap to view movie details")
        #else
        Button {
            onPlayVideo(movie.youtubeVideoId)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(movie.title). Released in \(movie.formattedReleaseYear ?? "Unknown")")
        .accessibilityHint("Tap to view details")
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
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(2/3, contentMode: .fill)
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.gray)
                            Text("Failed to load")
                                .font(.caption)
                                .foregroundColor(.gray)
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
            Text(movie.title)
                .font(.system(size: cardTitleSize, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Metadata row: Rating • Year • Runtime
            HStack(spacing: 4) {
                if let rating = movie.voteAverage {
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

            // YouTube indicator
            HStack(spacing: 4) {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: cardMetadataSize - 2))
                Text("YouTube")
                    .font(.system(size: cardMetadataSize - 2))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        #if os(tvOS)
        .frame(width: 245)
        #else
        .frame(width: 126)
        #endif
    }
}

#Preview {
    MainBrowseView()
        .preferredColorScheme(.dark)
}
