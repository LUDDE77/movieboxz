import SwiftUI

struct SearchView: View {
    @StateObject private var movieService = MovieService()
    @State private var searchText = ""
    @State private var searchResults: [Movie] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showingVideoPlayer = false
    @State private var currentMovie: Movie?

    var body: some View {
        NavigationView {
            VStack {
                searchBar
                searchContent
            }
            .navigationTitle("Search")
            .background(Color.black)
            .onChange(of: searchText) { newValue in
                if newValue.isEmpty {
                    searchResults = []
                }
            }
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let movie = currentMovie {
                MovieDetailView(movie: movie)
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var searchBar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search movies...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)

            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var searchContent: some View {
        if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
            emptyResultsView
        } else if searchResults.isEmpty && searchText.isEmpty {
            initialSearchView
        } else {
            searchResultsGrid
        }
    }

    private var emptyResultsView: some View {
        VStack {
            Spacer()
            VStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("No Results Found")
                    .font(.title2)
                    .fontWeight(.medium)
                    .padding(.top)
                Text("Try searching with different keywords")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var initialSearchView: some View {
        VStack {
            Spacer()
            VStack {
                Image(systemName: "tv")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("Search Movies")
                    .font(.title2)
                    .fontWeight(.medium)
                    .padding(.top)
                Text("Find your favorite YouTube movies")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var searchResultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 20) {
                ForEach(searchResults) { movie in
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

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        Task {
            isSearching = true
            do {
                searchResults = try await movieService.searchMovies(
                    query: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                    limit: 50
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func playVideo(_ videoId: String) {
        // Find the movie with this video ID
        if let movie = searchResults.first(where: { $0.youtubeVideoId == videoId }) {
            currentMovie = movie
            showingVideoPlayer = true
        }
    }
}

#Preview {
    SearchView()
        .preferredColorScheme(.dark)
}
