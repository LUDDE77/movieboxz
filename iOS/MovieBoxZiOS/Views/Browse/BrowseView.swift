import SwiftUI

struct BrowseView: View {
    // Dimensions of the content area (screen minus the side rail), passed from ContentView.
    let contentWidth: CGFloat
    let contentHeight: CGFloat

    @StateObject private var service = MovieService()
    @State private var featured: Movie?
    @State private var trending: [Movie] = []
    @State private var popular: [Movie] = []
    @State private var recent: [Movie] = []
    @State private var genres: [(genre: Genre, movies: [Movie])] = []
    @State private var allMovies: [Movie] = []
    @State private var uncategorized: [Movie] = []
    @State private var isLoading = true
    @State private var selectedMovie: Movie?
    @State private var selectedCategory: CategoryType?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let movie = featured, !isLoading {
                AsyncImage(url: movie.backdropURL) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: contentWidth, height: contentHeight)
                .clipped()
                .ignoresSafeArea()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: Color.black.opacity(0.5), location: 0.6),
                        .init(color: .black, location: 0.85)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            if isLoading {
                LoadingSkeletonView()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if let movie = featured {
                            FeaturedBanner(
                                movie: movie,
                                width: contentWidth,
                                height: contentHeight,
                                onPlay: { selectedMovie = movie }
                            )
                            .frame(height: contentHeight)
                        }

                        VStack(spacing: 40) {
                            if !trending.isEmpty {
                                MovieRowView(title: "Trending Now", movies: trending, screenWidth: contentWidth,
                                    onTap: { selectedMovie = $0 }, onSeeAll: { selectedCategory = .trending })
                            }
                            if !popular.isEmpty {
                                MovieRowView(title: "Popular", movies: popular, screenWidth: contentWidth,
                                    onTap: { selectedMovie = $0 }, onSeeAll: { selectedCategory = .popular })
                            }
                            ForEach(genres, id: \.genre.id) { item in
                                if !item.movies.isEmpty {
                                    MovieRowView(title: item.genre.name, movies: item.movies, screenWidth: contentWidth,
                                        onTap: { selectedMovie = $0 },
                                        onSeeAll: { selectedCategory = .genre(id: item.genre.id, name: item.genre.name) })
                                }
                            }
                            if !uncategorized.isEmpty {
                                MovieRowView(title: "Other", movies: uncategorized, screenWidth: contentWidth,
                                    onTap: { selectedMovie = $0 }, onSeeAll: { selectedCategory = .uncategorized })
                            }
                            if !recent.isEmpty {
                                MovieRowView(title: "Recently Added", movies: recent, screenWidth: contentWidth,
                                    onTap: { selectedMovie = $0 }, onSeeAll: { selectedCategory = .recent })
                            }
                            if !allMovies.isEmpty {
                                MovieRowView(title: "All Movies", movies: allMovies, screenWidth: contentWidth,
                                    onTap: { selectedMovie = $0 }, onSeeAll: { selectedCategory = .allMovies })
                            }
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                        .background(Color.black)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $selectedMovie) { MovieDetailView(movie: $0) }
        .sheet(item: $selectedCategory) { CategoryGridView(categoryType: $0) }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            let recents = try await service.fetchRecentMovies(limit: 50)
            featured = recents.first
            recent = recents

            async let t = service.fetchTrendingMovies(limit: 20)
            async let p = service.fetchPopularMovies(limit: 20)
            async let g = service.fetchAllGenres()
            async let a = service.fetchAllMovies(limit: 50)
            async let u = service.fetchUncategorizedMovies(limit: 10)

            trending      = (try? await t) ?? []
            popular       = (try? await p) ?? []
            let fetchedGenres = (try? await g) ?? []
            allMovies     = (try? await a) ?? []
            uncategorized = (try? await u) ?? []

            var results: [(genre: Genre, movies: [Movie])] = []
            await withTaskGroup(of: (Genre, [Movie]).self) { group in
                for genre in fetchedGenres where (genre.movieCount ?? 0) > 0 {
                    group.addTask {
                        let movies = (try? await MovieService().fetchMoviesByGenre(genreId: genre.id, limit: 10)) ?? []
                        return (genre, movies)
                    }
                }
                for await pair in group { results.append((genre: pair.0, movies: pair.1)) }
            }
            genres = results.sorted { $0.genre.name < $1.genre.name }
        } catch {
            print("BrowseView load error: \(error)")
        }
        isLoading = false
    }
}
