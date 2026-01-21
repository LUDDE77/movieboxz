import SwiftUI
import AVKit
import AVFoundation

struct MainBrowseView: View {
    @StateObject private var movieService = MovieService()
    @State private var featuredMovies: [Movie] = []
    @State private var trendingMovies: [Movie] = []
    @State private var popularMovies: [Movie] = []
    @State private var recentMovies: [Movie] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingVideoPlayer = false
    @State private var currentMovie: Movie?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Featured Movie Banner or Empty State
                if let featuredMovie = featuredMovies.first {
                    FeaturedMovieBanner(movie: featuredMovie, onPlayVideo: playVideo)
                        .frame(height: 500)
                } else if !isLoading {
                    // Empty State
                    VStack(spacing: 20) {
                        Image(systemName: "tv")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.6))

                        Text("Welcome to MovieBoxZ")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Your Netflix-style movie discovery app")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.yellow)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                    }
                    .frame(height: 400)
                    .padding()
                }

                // Movie Categories
                #if os(tvOS)
                // tvOS: Extra spacing to accommodate focus effects
                VStack(spacing: 60) {
                    if !trendingMovies.isEmpty {
                        MovieRowView(
                            title: "Trending Now",
                            movies: trendingMovies,
                            movieService: movieService,
                            onPlayVideo: playVideo
                        )
                    }

                    if !popularMovies.isEmpty {
                        MovieRowView(
                            title: "Popular Movies",
                            movies: popularMovies,
                            movieService: movieService,
                            onPlayVideo: playVideo
                        )
                    }

                    if !recentMovies.isEmpty {
                        MovieRowView(
                            title: "Recently Added",
                            movies: recentMovies,
                            movieService: movieService,
                            onPlayVideo: playVideo
                        )
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 100)
                #else
                // iOS: Standard spacing
                VStack(spacing: 30) {
                    if !trendingMovies.isEmpty {
                        MovieRowView(
                            title: "Trending Now",
                            movies: trendingMovies,
                            movieService: movieService,
                            onPlayVideo: playVideo
                        )
                    }

                    if !popularMovies.isEmpty {
                        MovieRowView(
                            title: "Popular Movies",
                            movies: popularMovies,
                            movieService: movieService,
                            onPlayVideo: playVideo
                        )
                    }

                    if !recentMovies.isEmpty {
                        MovieRowView(
                            title: "Recently Added",
                            movies: recentMovies,
                            movieService: movieService,
                            onPlayVideo: playVideo
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
                #endif
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .overlay(
            // Loading State
            Group {
                if isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading Movies...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.8))
                }
            }
        )
        .onAppear {
            loadMovies()
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let movie = currentMovie {
                MovieDetailView(movie: movie)
            }
        }
    }

    private func loadMovies() {
        Task {
            do {
                isLoading = true

                // Load all recent movies (40+ from database)
                let allMovies = try await movieService.fetchRecentMovies(limit: 50)

                // Set featured to first movie for banner
                featuredMovies = Array(allMovies.prefix(1))

                // Populate categories with real movies
                trendingMovies = allMovies.filter { $0.trending }
                popularMovies = Array(allMovies.prefix(10)) // First 10 as popular
                recentMovies = allMovies  // Show all recent movies

                isLoading = false
                errorMessage = nil
            } catch {
                isLoading = false
                print("❌ Error loading movies: \(error)")
                if let decodingError = error as? DecodingError {
                    print("❌ Decoding error details: \(decodingError)")
                }
                errorMessage = "Error loading movies: \(error.localizedDescription)"
            }
        }
    }

    private func playVideo(_ videoId: String) {
        // Find the movie with this video ID from any of our categories
        if let movie = featuredMovies.first(where: { $0.youtubeVideoId == videoId }) ??
                       trendingMovies.first(where: { $0.youtubeVideoId == videoId }) ??
                       popularMovies.first(where: { $0.youtubeVideoId == videoId }) ??
                       recentMovies.first(where: { $0.youtubeVideoId == videoId }) {
            currentMovie = movie
            showingVideoPlayer = true
        }
    }
}

// MARK: - Featured Movie Banner

struct FeaturedMovieBanner: View {
    let movie: Movie
    let onPlayVideo: (String) -> Void

    var body: some View {
        ZStack {
            // Background Image
            AsyncImage(url: movie.backdropURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .clipped()

            // Gradient Overlay
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.black.opacity(0.3), location: 0.4),
                    .init(color: Color.black.opacity(0.8), location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )

            // Movie Info
            VStack(alignment: .leading) {
                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(movie.title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(2)

                        if let overview = movie.description {
                            Text(overview)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(.bottom, 5)
                        }

                        HStack(spacing: 15) {
                            Button {
                                onPlayVideo(movie.youtubeVideoId)
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Play")
                                }
                                .font(.headline)
                                .foregroundColor(.black)
                                .padding(.horizontal, 25)
                                .padding(.vertical, 12)
                                .background(Color.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)

                            Text("Ch: \(movie.channelTitle)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                                .padding(.vertical, 12)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Movie Row View

struct MovieRowView: View {
    let title: String
    let movies: [Movie]
    let movieService: MovieService
    let onPlayVideo: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                #if os(tvOS)
                // tvOS: Larger spacing to accommodate focus scaling
                LazyHStack(spacing: 40) {
                    ForEach(movies) { movie in
                        MovieCard(movie: movie, movieService: movieService, onPlayVideo: onPlayVideo)
                            .frame(width: 250, height: 375)
                    }
                }
                .padding(.horizontal, 60)
                #else
                // iOS: Compact spacing for touch interface
                LazyHStack(spacing: 15) {
                    ForEach(movies) { movie in
                        MovieCard(movie: movie, movieService: movieService, onPlayVideo: onPlayVideo)
                            .frame(width: 180, height: 270)
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
    let movieService: MovieService
    let onPlayVideo: (String) -> Void
    @State private var isPressed = false
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif

    var body: some View {
        #if os(tvOS)
        // tvOS: Use Button for proper remote control support
        Button {
            onPlayVideo(movie.youtubeVideoId)
        } label: {
            cardContent
        }
        .buttonStyle(.card)
        #else
        // iOS: Use tap gesture
        cardContent
            .onTapGesture {
                onPlayVideo(movie.youtubeVideoId)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .onLongPressGesture(minimumDuration: 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed.toggle()
                }
            }
        #endif
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Movie Poster
            AsyncImage(url: movie.posterURL) { image in
                image
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        VStack {
                            Image(systemName: "film.fill")
                                .font(.title)
                                .foregroundColor(.gray)
                            Text("No Image")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
                    .aspectRatio(2/3, contentMode: .fill)
            }
            .cornerRadius(8)
            .clipped()
            #if os(iOS)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            #endif

            // Movie Info
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(movie.channelTitle)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    MainBrowseView()
        .preferredColorScheme(.dark)
}
