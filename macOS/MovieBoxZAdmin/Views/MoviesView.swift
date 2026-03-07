import SwiftUI

struct MoviesView: View {
    @StateObject private var apiService = AdminAPIService()
    @State private var movies: [Movie] = []
    @State private var selectedMovie: Movie?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var totalMovies = 0
    @State private var itemsPerPage = 50

    // Filter state
    @State private var showNeedsVerification = false

    // View mode
    @State private var showOriginal = false

    // Edit state
    @State private var editingMovie: Movie?

    // Enrichment state
    @State private var isEnriching = false
    @State private var enrichmentPriority: EnrichmentPriority = .full

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            if let error = errorMessage {
                errorView(error)
            } else if isLoading && movies.isEmpty {
                ProgressView("Loading movies...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if movies.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .sheet(item: $editingMovie) { movie in
            ProductionMovieEditView(
                movie: movie,
                onSave: { updatedMovie in
                    // Update the movie in the list
                    if let index = movies.firstIndex(where: { $0.id == updatedMovie.id }) {
                        movies[index] = updatedMovie
                    }
                    // Update selected movie if it's the one being edited
                    if selectedMovie?.id == updatedMovie.id {
                        selectedMovie = updatedMovie
                    }
                    editingMovie = nil
                },
                onCancel: {
                    editingMovie = nil
                }
            )
        }
        .task {
            await loadMovies()
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("Production Movies")
                        .font(.title)
                        .fontWeight(.bold)

                    Text(totalMovies > 0 ? "\(totalMovies)" : "—")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(8)
                }

                Text(totalMovies > 0 ? "\(totalMovies) movies in production" : "Loading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                TextField("Search movies...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                    .onSubmit {
                        Task {
                            currentPage = 1
                            await loadMovies()
                        }
                    }

                Button(action: {
                    showNeedsVerification.toggle()
                    Task { currentPage = 1; await loadMovies() }
                }) {
                    Label("Needs Verification", systemImage: "exclamationmark.magnifyingglass")
                }
                .buttonStyle(showNeedsVerification ? .borderedProminent : .bordered)
                .tint(.orange)

                Button(action: { showOriginal.toggle() }) {
                    Label(showOriginal ? "Showing Original" : "Show Original", systemImage: "film.stack")
                }
                .buttonStyle(showOriginal ? .borderedProminent : .bordered)
                .tint(.indigo)

                Button(action: { Task { await loadMovies() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .padding()
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            Text("Error loading movies")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No movies in production")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Publish approved movies from staging to see them here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        HSplitView {
            // Left: Movie list
            movieList
                .frame(minWidth: 400, maxWidth: .infinity)

            // Right: Detail view
            if let movie = selectedMovie {
                movieDetailView(movie)
                    .frame(minWidth: 400, maxWidth: .infinity)
            } else {
                VStack {
                    Image(systemName: "film")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a movie to view details")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var movieList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(movies) { movie in
                        ProductionMovieRow(
                            movie: movie,
                            isSelected: selectedMovie?.id == movie.id,
                            showOriginal: showOriginal,
                            onSelect: { selectedMovie = movie }
                        )
                    }
                }
                .padding()
            }

            Divider()

            // Pagination
            HStack(spacing: 16) {
                Text("Page \(currentPage) of \(totalPages)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    currentPage -= 1
                    Task { await loadMovies() }
                }) {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(currentPage <= 1 || isLoading)
                .buttonStyle(.bordered)

                Button(action: {
                    currentPage += 1
                    Task { await loadMovies() }
                }) {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(currentPage >= totalPages || isLoading)
                .buttonStyle(.bordered)

                Divider()
                    .frame(height: 20)

                Text("Per page:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $itemsPerPage) {
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: itemsPerPage) { oldValue, newValue in
                    if oldValue != newValue {
                        currentPage = 1
                        Task { await loadMovies() }
                    }
                }
            }
            .padding()
        }
    }

    private func movieDetailView(_ movie: Movie) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with poster
                if showOriginal {
                    // Side-by-side comparison: original (left) vs enriched (right)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Original YouTube")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.indigo)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.indigo.opacity(0.12))
                                .cornerRadius(4)

                            let thumbURL = URL(string: "https://img.youtube.com/vi/\(movie.youtubeVideoId)/mqdefault.jpg")
                            AsyncImage(url: thumbURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 180, height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(movie.youtubeVideoTitle.isEmpty ? "(no title)" : movie.youtubeVideoTitle)
                                .font(.headline)
                                .lineLimit(3)
                                .frame(width: 180, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Enriched")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(4)

                            if let posterPath = movie.posterPath {
                                let posterURL: URL? = posterPath.hasPrefix("http")
                                    ? URL(string: posterPath)
                                    : URL(string: "https://image.tmdb.org/t/p/w185\(posterPath)")
                                AsyncImage(url: posterURL) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(width: 90, height: 135)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 90, height: 135)
                                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                            }

                            Text(movie.title)
                                .font(.headline)
                                .lineLimit(3)
                                .frame(width: 180, alignment: .leading)
                        }

                        Spacer()
                    }
                    .padding(.bottom, 4)
                }

                HStack(alignment: .top, spacing: 16) {
                    // Poster (enriched only, hidden in original mode since shown above)
                    if !showOriginal, let posterPath = movie.posterPath {
                        let posterURL: URL? = {
                            if posterPath.hasPrefix("http") {
                                return URL(string: posterPath)
                            } else {
                                return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
                            }
                        }()

                        AsyncImage(url: posterURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 200, height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(movie.title)
                            .font(.title)
                            .fontWeight(.bold)

                        if let releaseYear = movie.releaseYear {
                            Text("\(releaseYear)")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }

                        if let rating = movie.imdbRating {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.headline)
                                if let votes = movie.imdbVotes {
                                    Text("(\(votes) votes)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        if !movie.genres.isEmpty {
                            Text(movie.genres.map { $0.name }.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // Content flags
                        HStack(spacing: 8) {
                            // Needs Verification checkbox — toggle directly on the row
                            Button(action: {
                                Task {
                                    await updateMovieWithChanges(movie, updates: ["needs_verification": !(movie.needsVerification ?? false)])
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: movie.needsVerification == true ? "checkmark.square.fill" : "square")
                                        .foregroundColor(movie.needsVerification == true ? .orange : .secondary)
                                    Text("Needs Verification")
                                        .font(.caption)
                                        .foregroundColor(movie.needsVerification == true ? .orange : .secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            if movie.isTvSeries == true {
                                StatusBadge(text: "TV Series", color: .purple)
                            }
                            if movie.isKidsContent == true {
                                StatusBadge(text: "Kids", color: .green)
                            }
                            if movie.isTvShow == true && movie.isTvSeries != true {
                                StatusBadge(text: "TV Show", color: .blue)
                            }
                        }

                        Spacer()

                        // Action buttons
                        HStack(spacing: 12) {
                            Button(action: {
                                print("\n🖊️ [MoviesView] EDIT BUTTON CLICKED")
                                print("🖊️ [MoviesView] Movie ID: \(movie.id)")
                                print("🖊️ [MoviesView] Movie Title: \(movie.title)")
                                print("🖊️ [MoviesView] Setting editingMovie to trigger sheet...")
                                editingMovie = movie
                                print("🖊️ [MoviesView] editingMovie set: \(editingMovie != nil)\n")
                            }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)

                            Button(action: {
                                Task {
                                    await enrichMovie(movie, priority: enrichmentPriority)
                                }
                            }) {
                                if isEnriching {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Label("Enrich", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isEnriching)

                            if let url = movie.youtubeURL {
                                Button(action: {
                                    NSWorkspace.shared.open(url)
                                }) {
                                    Label("YouTube", systemImage: "play.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Divider()

                // Description
                if let description = movie.description, !description.isEmpty {
                    GroupBox(label: Label("Description", systemImage: "text.alignleft")) {
                        Text(description)
                            .font(.body)
                            .padding(.vertical, 4)
                    }
                }

                // Movie details
                GroupBox(label: Label("Details", systemImage: "info.circle")) {
                    VStack(spacing: 8) {
                        DetailRow(label: "Runtime", value: movie.runtimeMinutes.map { "\($0) min" } ?? "—")
                        DetailRow(label: "Language", value: movie.language ?? "—")
                        DetailRow(label: "Country", value: movie.country ?? "—")
                        DetailRow(label: "Rated", value: movie.rated ?? "—")
                        if let director = movie.director {
                            DetailRow(label: "Director", value: director)
                        }
                        if let actors = movie.actors {
                            DetailRow(label: "Actors", value: actors)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Enrichment info
                if movie.tmdbId != nil || movie.imdbId != nil {
                    GroupBox(label: Label("Enrichment", systemImage: "sparkles")) {
                        VStack(spacing: 8) {
                            if let tmdbId = movie.tmdbId {
                                DetailRow(label: "TMDB ID", value: "\(tmdbId)")
                            }
                            if let imdbId = movie.imdbId {
                                DetailRow(label: "IMDB ID", value: imdbId)
                            }
                            if let source = movie.enrichmentSource {
                                DetailRow(label: "Source", value: source)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // YouTube stats
                GroupBox(label: Label("YouTube Stats", systemImage: "chart.bar")) {
                    VStack(spacing: 8) {
                        DetailRow(label: "Views", value: "\(movie.viewCount)")
                        DetailRow(label: "Likes", value: "\(movie.likeCount)")
                        if let comments = movie.commentCount {
                            DetailRow(label: "Comments", value: "\(comments)")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
    }

    // MARK: - Actions

    func loadMovies() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await apiService.getMovies(
                page: currentPage,
                limit: itemsPerPage,
                search: searchText.isEmpty ? nil : searchText,
                needsVerification: showNeedsVerification
            )
            movies = data.movies
            totalPages = data.pagination.pages ?? 1
            totalMovies = data.pagination.total ?? 0
        } catch {
            errorMessage = "Failed to load movies: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func updateMovieWithChanges(_ movie: Movie, updates: [String: Any]) async {
        do {
            let _ = try await apiService.updateProductionMovie(movieId: movie.id, updates: updates)
            await loadMovies()
        } catch {
            errorMessage = "Failed to update movie: \(error.localizedDescription)"
        }
    }

    func enrichMovie(_ movie: Movie, priority: EnrichmentPriority) async {
        isEnriching = true
        do {
            let _ = try await apiService.enrichProductionMovie(movieId: movie.id, priority: priority)
            await loadMovies()
        } catch {
            errorMessage = "Failed to enrich movie: \(error.localizedDescription)"
        }
        isEnriching = false
    }
}

// MARK: - Movie Row

struct ProductionMovieRow: View {
    let movie: Movie
    let isSelected: Bool
    var showOriginal: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Poster thumbnail or YouTube thumbnail
                if showOriginal {
                    let thumbURL = URL(string: "https://img.youtube.com/vi/\(movie.youtubeVideoId)/mqdefault.jpg")
                    AsyncImage(url: thumbURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 60, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let posterPath = movie.posterPath {
                    let posterURL: URL? = {
                        if posterPath.hasPrefix("http") {
                            return URL(string: posterPath)
                        } else {
                            return URL(string: "https://image.tmdb.org/t/p/w92\(posterPath)")
                        }
                    }()

                    AsyncImage(url: posterURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 60, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 90)
                        .overlay(
                            Image(systemName: "film")
                                .foregroundColor(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    if showOriginal {
                        Text(movie.youtubeVideoTitle.isEmpty ? movie.title : movie.youtubeVideoTitle)
                            .font(.headline)
                            .lineLimit(2)
                        if !movie.youtubeVideoTitle.isEmpty && movie.youtubeVideoTitle != movie.title {
                            Text(movie.title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .lineLimit(1)
                        }
                    } else {
                        Text(movie.title)
                            .font(.headline)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if let year = movie.releaseYear {
                            Text("\(year)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if movie.isTvSeries == true {
                            StatusBadge(text: "TV Series", color: .purple)
                        }
                        if movie.isKidsContent == true {
                            StatusBadge(text: "Kids", color: .green)
                        }

                        if let rating = movie.imdbRating {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.caption)
                            }
                        }

                        if movie.tmdbId != nil || movie.imdbId != nil {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    if let channel = movie.channelTitle {
                        Text(channel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper Views

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Helper Views


#Preview {
    MoviesView()
}
