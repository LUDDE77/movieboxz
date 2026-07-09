import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var movieService: MovieService
    @State private var searchText = ""
    @State private var searchResults: [Movie] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var currentMovie: Movie?

    #if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 245, maximum: 245), spacing: 40)]
    private let cardTitleSize: CGFloat = 31
    private let cardMetadataSize: CGFloat = 25
    #else
    private let columns = [GridItem(.adaptive(minimum: 126, maximum: 180), spacing: 15)]
    private let cardTitleSize: CGFloat = 18
    private let cardMetadataSize: CGFloat = 14
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(tvOS)
            tvOSLayout
            #else
            iOSLayout
            #endif
        }
        // Live debounced search: cancels and restarts automatically whenever
        // searchText changes, waits ~300ms before actually searching so we
        // don't fire a request on every keystroke. `.onSubmit` below still
        // triggers an immediate search.
        .task(id: searchText) {
            await debouncedSearch()
        }
        .sheet(item: $currentMovie) { movie in
            MovieDetailView(movie: movie)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - iOS Layout

    #if !os(tvOS)
    private var iOSLayout: some View {
        VStack(spacing: 0) {
            // Header + search bar
            VStack(spacing: 12) {
                Text("Search")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))
                        TextField("Search movies...", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .tint(.red)
                            .submitLabel(.search)
                            .onSubmit { performSearch() }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(10)

                    if isSearching {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Button("Search") { performSearch() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(Color.white.opacity(0.05))

            Divider().background(Color.white.opacity(0.1))

            // Results
            searchContent
        }
    }

    private var searchContent: some View {
        Group {
            if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                emptyState(icon: "magnifyingglass", title: "No Results", subtitle: "Try different keywords")
            } else if searchResults.isEmpty {
                emptyState(icon: "tv", title: "Search Movies", subtitle: "Find movies from curated YouTube channels")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("\(searchResults.count) \(searchResults.count == 1 ? "result" : "results")")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(searchResults) { movie in
                                MovieCard(
                                    movie: movie,
                                    cardTitleSize: cardTitleSize,
                                    cardMetadataSize: cardMetadataSize,
                                    onPlayVideo: { _ in currentMovie = movie }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 50)
                    }
                    .padding(.top, 16)
                }
            }
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.3))
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    #endif

    // MARK: - tvOS Layout

    #if os(tvOS)
    private var tvOSLayout: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(searchResults) { movie in
                    MovieCard(
                        movie: movie,
                        cardTitleSize: cardTitleSize,
                        cardMetadataSize: cardMetadataSize,
                        onPlayVideo: { _ in currentMovie = movie }
                    )
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 100)
        }
        .searchable(text: $searchText, placement: .automatic)
        .onSubmit(of: .search) { performSearch() }
    }
    #endif

    // MARK: - Search

    /// Immediate search — used by the Search button and onSubmit (both
    /// platforms), bypassing the debounce delay.
    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        Task {
            await runSearch(query: query)
        }
    }

    /// Live debounced search driven by `.task(id: searchText)`. Waits ~300ms
    /// so we don't hit the backend on every keystroke; automatically
    /// cancelled and restarted by SwiftUI whenever `searchText` changes.
    private func debouncedSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return // superseded by a newer keystroke
        }
        guard !Task.isCancelled else { return }

        await runSearch(query: query)
    }

    private func runSearch(query: String) async {
        isSearching = true
        do {
            searchResults = try await movieService.searchMovies(query: query, limit: 50)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }
}

#Preview {
    SearchView()
        .environmentObject(MovieService())
        .preferredColorScheme(.dark)
}
