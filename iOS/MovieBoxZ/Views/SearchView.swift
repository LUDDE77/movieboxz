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
            Color.mbzInk.ignoresSafeArea()

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
        #if os(tvOS)
        .fullScreenCover(item: $currentMovie) { movie in
            MovieDetailView(movie: movie)
        }
        #else
        .sheet(item: $currentMovie) { movie in
            MovieDetailView(movie: movie)
        }
        #endif
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
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(.mbzGold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.mbzMuted)
                        TextField("Search movies...", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.mbzScreen)
                            .tint(.mbzGold)
                            .submitLabel(.search)
                            .onSubmit { performSearch() }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.mbzMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.mbzSlate)
                    .cornerRadius(10)

                    if isSearching {
                        ProgressView()
                            .tint(.mbzGold)
                    } else {
                        Button("Search") { performSearch() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.mbzInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.mbzGold)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(Color.mbzSlate.opacity(0.4))

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
                            .foregroundColor(.mbzMuted)
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
                .foregroundColor(.mbzMuted.opacity(0.5))
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.mbzScreen)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(.mbzMuted)
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
            let results = try await movieService.searchMovies(query: query, limit: 50)
            guard !Task.isCancelled else { return }   // superseded by a newer search
            searchResults = results
        } catch is CancellationError {
            return // superseded — not a real error, don't surface an alert
        } catch let urlError as URLError where urlError.code == .cancelled {
            return // request cancelled by a newer keystroke — not a real error
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if !Task.isCancelled { isSearching = false }
    }
}

#Preview {
    SearchView()
        .environmentObject(MovieService())
        .preferredColorScheme(.dark)
}
