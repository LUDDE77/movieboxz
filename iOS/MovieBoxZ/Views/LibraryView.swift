import SwiftUI

struct LibraryView: View {
    @StateObject private var movieService = MovieService()
    @State private var favoriteMovies: [Movie] = []
    @State private var watchHistory: [Movie] = []
    @State private var isLoading = true
    @State private var selectedTab = 0
    @State private var showingVideoPlayer = false
    @State private var currentMovie: Movie?

    var body: some View {
        NavigationView {
            VStack {
                // Tab Selector
                Picker("Library Section", selection: $selectedTab) {
                    Text("Favorites").tag(0)
                    Text("Watch History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 10)

                if isLoading {
                    Spacer()
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading Library...")
                            .padding(.top)
                    }
                    Spacer()
                } else {
                    TabView(selection: $selectedTab) {
                        // Favorites Tab
                        libraryContent(
                            movies: favoriteMovies,
                            emptyStateIcon: "heart",
                            emptyStateTitle: "No Favorites Yet",
                            emptyStateMessage: "Movies you favorite will appear here"
                        )
                        .tag(0)

                        // Watch History Tab
                        libraryContent(
                            movies: watchHistory,
                            emptyStateIcon: "clock",
                            emptyStateTitle: "No Watch History",
                            emptyStateMessage: "Movies you watch will appear here"
                        )
                        .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("My Library")
            .background(Color.black)
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let movie = currentMovie {
                MovieDetailView(movie: movie)
            }
        }
        .onAppear {
            loadLibraryData()
        }
    }

    @ViewBuilder
    private func libraryContent(
        movies: [Movie],
        emptyStateIcon: String,
        emptyStateTitle: String,
        emptyStateMessage: String
    ) -> some View {
        if movies.isEmpty {
            VStack {
                Image(systemName: emptyStateIcon)
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text(emptyStateTitle)
                    .font(.title2)
                    .fontWeight(.medium)
                    .padding(.top)
                Text(emptyStateMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 20) {
                    ForEach(movies) { movie in
                        MovieCard(
                            movie: movie,
                            cardTitleSize: 16,
                            cardMetadataSize: 12,
                            onPlayVideo: playVideo
                        )
                        .frame(width: 120, height: 200)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
    }

    private func loadLibraryData() {
        Task {
            isLoading = true

            // TODO: Implement user favorites and watch history API calls
            // For now, we'll use empty arrays
            favoriteMovies = []
            watchHistory = []

            isLoading = false
        }
    }

    private func playVideo(_ videoId: String) {
        // Find the movie with this video ID
        if let movie = favoriteMovies.first(where: { $0.youtubeVideoId == videoId }) ??
                       watchHistory.first(where: { $0.youtubeVideoId == videoId }) {
            currentMovie = movie
            showingVideoPlayer = true
        }
    }
}

#Preview {
    LibraryView()
        .preferredColorScheme(.dark)
}
