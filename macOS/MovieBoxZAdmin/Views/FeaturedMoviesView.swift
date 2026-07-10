import SwiftUI

struct FeaturedMoviesView: View {
    @StateObject private var apiService = AdminAPIService()

    @State private var featuredMovies: [FeaturedMovieItem] = []
    @State private var searchResults: [Movie] = []
    @State private var searchText = ""
    @State private var isLoadingFeatured = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        HSplitView {
            // Left: current featured slots
            featuredSlotsPanel
                .frame(minWidth: 320, maxWidth: 400)

            // Right: search to add movies
            searchPanel
                .frame(minWidth: 400)
        }
        .navigationTitle("Featured Movies")
        .task { await loadFeatured() }
    }

    // MARK: - Featured Slots Panel

    private var featuredSlotsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Featured Carousel")
                        .font(.headline)
                    Text("\(featuredMovies.count) / 5 slots used")
                        .font(.caption)
                        .foregroundColor(featuredMovies.count >= 5 ? .orange : .secondary)
                }
                Spacer()
                if isLoadingFeatured {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding()

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            if let success = successMessage {
                Text(success)
                    .foregroundColor(.green)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            // Slots list (always show 5 rows)
            ScrollView {
                VStack(spacing: 8) {
                    // Move up/down is position-based on the sorted list so it
                    // works even when featured_order values are non-contiguous
                    // (e.g. 1, 3, 5 after a removal).
                    let ordered = featuredMovies.sorted { $0.featuredOrder < $1.featuredOrder }
                    ForEach(1...5, id: \.self) { slot in
                        if let movie = featuredMovies.first(where: { $0.featuredOrder == slot }) {
                            FilledSlotRow(
                                slot: slot,
                                movie: movie,
                                canMoveUp: ordered.first?.id != movie.id,
                                canMoveDown: ordered.last?.id != movie.id,
                                onMoveUp: { Task { await moveUp(movie) } },
                                onMoveDown: { Task { await moveDown(movie) } },
                                onRemove: { Task { await removeFeatured(movie) } }
                            )
                        } else {
                            EmptySlotRow(slot: slot)
                        }
                    }
                    // Rows whose featured_order fell outside 1...5 (non-contiguous
                    // data) would otherwise be invisible and uneditable.
                    ForEach(ordered.filter { $0.featuredOrder < 1 || $0.featuredOrder > 5 }) { movie in
                        FilledSlotRow(
                            slot: movie.featuredOrder,
                            movie: movie,
                            canMoveUp: ordered.first?.id != movie.id,
                            canMoveDown: ordered.last?.id != movie.id,
                            onMoveUp: { Task { await moveUp(movie) } },
                            onMoveDown: { Task { await moveDown(movie) } },
                            onRemove: { Task { await removeFeatured(movie) } }
                        )
                    }
                }
                .padding()
            }

            Spacer()

            Text("Movies appear in the app's featured carousel in slot order.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding()
        }
    }

    // MARK: - Search Panel

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Search Movies to Feature")
                    .font(.headline)
                Spacer()
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search by title...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await searchMovies() } }
                if isSearching {
                    ProgressView().scaleEffect(0.7)
                }
                if !searchText.isEmpty {
                    Button { searchText = ""; searchResults = [] } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                VStack {
                    Spacer()
                    Text("No results for \"\(searchText)\"")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if searchResults.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Search for a movie to add it to the featured carousel")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else {
                List(searchResults) { movie in
                    SearchResultRow(
                        movie: movie,
                        isAlreadyFeatured: featuredMovies.contains(where: { $0.id == movie.id }),
                        isFull: featuredMovies.count >= 5,
                        onFeature: { Task { await addFeatured(movie) } }
                    )
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func loadFeatured() async {
        isLoadingFeatured = true
        // Note: does not clear errorMessage — actions reset it themselves, and
        // a resync reload after a failed action must not swallow the error text.
        do {
            featuredMovies = try await apiService.getFeaturedMovies()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingFeatured = false
    }

    private func searchMovies() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        do {
            let data = try await apiService.getMovies(page: 1, limit: 20, search: searchText)
            searchResults = data.movies
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    private func addFeatured(_ movie: Movie) async {
        errorMessage = nil
        successMessage = nil
        do {
            try await apiService.featureMovie(movieId: movie.id)
            successMessage = "\"\(movie.title)\" added to featured"
            await loadFeatured()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeFeatured(_ item: FeaturedMovieItem) async {
        errorMessage = nil
        successMessage = nil
        do {
            try await apiService.unfeatureMovie(movieId: item.id)
            successMessage = "\"\(item.title)\" removed from featured"
        } catch {
            // Surfaces the backend { error / message } text via localizedDescription.
            errorMessage = error.localizedDescription
        }
        // Reload in both cases so the UI reflects actual server state.
        await loadFeatured()
    }

    private func moveUp(_ item: FeaturedMovieItem) async {
        var ordered = featuredMovies.sorted { $0.featuredOrder < $1.featuredOrder }
        guard let idx = ordered.firstIndex(where: { $0.id == item.id }), idx > 0 else { return }
        ordered.swapAt(idx, idx - 1)
        await reorder(ordered)
    }

    private func moveDown(_ item: FeaturedMovieItem) async {
        var ordered = featuredMovies.sorted { $0.featuredOrder < $1.featuredOrder }
        guard let idx = ordered.firstIndex(where: { $0.id == item.id }), idx < ordered.count - 1 else { return }
        ordered.swapAt(idx, idx + 1)
        await reorder(ordered)
    }

    private func reorder(_ ordered: [FeaturedMovieItem]) async {
        errorMessage = nil
        do {
            try await apiService.reorderFeaturedMovies(movieIds: ordered.map(\.id))
        } catch {
            // Surfaces the backend { error / message } text via localizedDescription.
            errorMessage = error.localizedDescription
        }
        // Reload in both cases so the UI reflects actual server state.
        await loadFeatured()
    }
}

// MARK: - Filled Slot Row

struct FilledSlotRow: View {
    let slot: Int
    let movie: FeaturedMovieItem
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Slot number badge
            Text("\(slot)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(width: 26, height: 26)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(Circle())

            // Poster thumbnail (handles nil, full OMDB URLs and TMDB paths)
            PosterImage(path: movie.posterPath, width: 36, height: 54, cornerRadius: 4, tmdbSize: "w154")

            // Title
            Text(movie.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)

            Spacer()

            // Reorder arrows
            VStack(spacing: 2) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(!canMoveUp)
                .opacity(canMoveUp ? 1 : 0.3)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(!canMoveDown)
                .opacity(canMoveDown ? 1 : 0.3)
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Empty Slot Row

struct EmptySlotRow: View {
    let slot: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(slot)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(width: 26, height: 26)
                .background(Color.secondary.opacity(0.2))
                .foregroundColor(.secondary)
                .clipShape(Circle())

            Text("Empty slot — search and add a movie")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .italic()

            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let movie: Movie
    let isAlreadyFeatured: Bool
    let isFull: Bool
    let onFeature: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Handles nil, full OMDB URLs and TMDB relative paths uniformly.
            PosterImage(path: movie.posterPath, width: 30, height: 45, cornerRadius: 4, tmdbSize: "w92")

            VStack(alignment: .leading, spacing: 2) {
                Text(movie.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let year = movie.releaseYear {
                        Text("\(year)")
                    }
                    if let rating = movie.imdbRating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .foregroundColor(.yellow)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if isAlreadyFeatured {
                Label("Featured", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
            } else {
                Button(action: onFeature) {
                    Label("Feature", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isFull)
                .help(isFull ? "Remove a featured movie first (max 5)" : "Add to featured carousel")
            }
        }
        .padding(.vertical, 4)
    }
}
