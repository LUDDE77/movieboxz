import SwiftUI

struct MainBrowseView: View {
    @StateObject private var movieService = MovieService()
    @State private var featuredMovies: [Movie] = []
    @State private var trendingMovies: [Movie] = []
    @State private var popularMovies: [Movie] = []
    @State private var recentMovies: [Movie] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    #if os(tvOS)
    @Namespace private var browseNamespace
    #endif

    // Non-empty rails in display order — lets us mark the first one as the
    // default focus target on tvOS.
    private var rails: [(title: String, movies: [Movie])] {
        [
            ("Trending Now", trendingMovies),
            ("Popular Movies", popularMovies),
            ("Recently Added", recentMovies)
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Featured Movie Banner
                if let featuredMovie = featuredMovies.first {
                    FeaturedMovieBanner(movie: featuredMovie)
                        .frame(height: 500)
                }

                // Movie Categories
                VStack(spacing: 30) {
                    ForEach(Array(rails.enumerated()), id: \.offset) { index, rail in
                        MovieRowView(
                            title: rail.title,
                            movies: rail.movies,
                            movieService: movieService
                        )
                        #if os(tvOS)
                        .prefersDefaultFocus(index == 0, in: browseNamespace)
                        #endif
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
            #if os(tvOS)
            .focusScope(browseNamespace)
            #endif
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
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            loadMovies()
        }
    }

    private func loadMovies() {
        Task {
            do {
                isLoading = true

                // Load movies concurrently
                async let featured = movieService.fetchFeaturedMovies()
                async let trending = movieService.fetchTrendingMovies(limit: 20)
                async let popular = movieService.fetchPopularMovies(limit: 20)
                async let recent = movieService.fetchRecentMovies(limit: 20)

                featuredMovies = try await featured
                trendingMovies = try await trending
                popularMovies = try await popular
                recentMovies = try await recent

                isLoading = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Featured Movie Banner

struct FeaturedMovieBanner: View {
    let movie: Movie

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

                        if let overview = movie.overview {
                            Text(overview)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 15) {
                            Button {
                                openYouTubeVideo(movie.youtubeVideoId)
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Play on YouTube")
                                }
                                .font(.headline)
                                .foregroundColor(.black)
                                .padding(.horizontal, 25)
                                .padding(.vertical, 12)
                                .background(Color.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)

                            Text("Channel: \(movie.channelTitle)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.vertical, 12)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }

    private func openYouTubeVideo(_ videoId: String) {
        if let youtubeURL = URL(string: "youtube://\(videoId)") {
            if UIApplication.shared.canOpenURL(youtubeURL) {
                UIApplication.shared.open(youtubeURL)
            } else if let webURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)") {
                UIApplication.shared.open(webURL)
            }
        }
    }
}

// MARK: - Movie Row View

struct MovieRowView: View {
    let title: String
    let movies: [Movie]
    let movieService: MovieService

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
                LazyHStack(spacing: 15) {
                    ForEach(movies) { movie in
                        MovieCard(movie: movie, movieService: movieService)
                            .frame(width: 180, height: 270)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        #if os(tvOS)
        // Group each rail so vertical moves land on a sensible card and the
        // horizontal scroll remembers its position.
        .focusSection()
        #endif
    }
}

// MARK: - Movie Card

struct MovieCard: View {
    let movie: Movie
    let movieService: MovieService
    @State private var isPressed = false

    var body: some View {
        #if os(tvOS)
        // Native card style gives the focus lift/shadow and a reliable
        // select press, and stops gesture recognizers from swallowing Menu
        // (which caused the "press twice to exit" feel).
        Button {
            openYouTubeVideo(movie.youtubeVideoId)
        } label: {
            cardContent
        }
        .buttonStyle(.card)
        #else
        cardContent
            .onTapGesture {
                openYouTubeVideo(movie.youtubeVideoId)
            }
            .onLongPressGesture(minimumDuration: 0) { isPressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = isPressing
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
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)

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

    private func openYouTubeVideo(_ videoId: String) {
        #if os(iOS)
        if let youtubeURL = URL(string: "youtube://\(videoId)") {
            if UIApplication.shared.canOpenURL(youtubeURL) {
                UIApplication.shared.open(youtubeURL)
            } else if let webURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)") {
                UIApplication.shared.open(webURL)
            }
        }
        #elseif os(tvOS)
        if let webURL = URL(string: "https://www.youtube.com/tv#/watch?v=\(videoId)") {
            UIApplication.shared.open(webURL)
        }
        #endif
    }
}

#Preview {
    MainBrowseView()
        .preferredColorScheme(.dark)
}