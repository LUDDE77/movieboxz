import SwiftUI

// MARK: - Sort options (raw values are the backend sort whitelist keys)

enum MovieSortOption: String, CaseIterable, Identifiable {
    case viewCount = "view_count"
    case rating = "vote_average"
    case recentlyPublished = "published_at"
    case recentlyAdded = "created_at"
    case title = "title"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .viewCount: return "View Count"
        case .rating: return "Rating"
        case .recentlyPublished: return "Recently Published"
        case .recentlyAdded: return "Recently Added"
        case .title: return "Title"
        }
    }
}

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
    @State private var includeUnavailable = true
    @State private var sortOption: MovieSortOption = .recentlyAdded

    // Tools state
    @State private var showFixTitlesSheet = false
    @State private var showEnrichSheet = false

    // In-flight load task (cancelled on pagination to prevent races)
    @State private var loadTask: Task<Void, Never>?

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
        .sheet(isPresented: $showFixTitlesSheet) {
            FixTitlesSheet(apiService: apiService, onApplied: {
                Task { await loadMovies() }
            })
        }
        .sheet(isPresented: $showEnrichSheet) {
            EnrichChannelSheet(apiService: apiService, onFinished: {
                Task { await loadMovies() }
            })
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
                    .frame(width: 220)
                    .onSubmit {
                        Task {
                            currentPage = 1
                            await loadMovies()
                        }
                    }

                Picker("Sort", selection: $sortOption) {
                    ForEach(MovieSortOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .frame(width: 200)
                .onChange(of: sortOption) { _, _ in
                    currentPage = 1
                    Task { await loadMovies() }
                }

                toggleButton(
                    label: "Include Unavailable",
                    icon: "link.badge.plus",
                    isOn: includeUnavailable,
                    color: .red
                ) {
                    includeUnavailable.toggle()
                    Task { currentPage = 1; await loadMovies() }
                }
                .help("Show movies whose YouTube link is dead (is_available = false)")

                toggleButton(
                    label: "Needs Verification",
                    icon: "exclamationmark.magnifyingglass",
                    isOn: showNeedsVerification,
                    color: .orange
                ) {
                    showNeedsVerification.toggle()
                    Task { currentPage = 1; await loadMovies() }
                }

                toggleButton(
                    label: showOriginal ? "Showing Original" : "Show Original",
                    icon: "film.stack",
                    isOn: showOriginal,
                    color: .indigo
                ) {
                    showOriginal.toggle()
                }

                Menu {
                    Button {
                        showFixTitlesSheet = true
                    } label: {
                        Label("Fix Titles (Preview)…", systemImage: "textformat.abc")
                    }
                    Button {
                        showEnrichSheet = true
                    } label: {
                        Label("Re-enrich Channel…", systemImage: "sparkles")
                    }
                } label: {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }
                .frame(width: 100)

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
                            onSelect: { selectedMovie = movie },
                            onToggleVerification: {
                                Task {
                                    await updateMovieWithChanges(movie, updates: ["needs_verification": !(movie.needsVerification ?? false)])
                                }
                            }
                        )
                        .contextMenu {
                            Button {
                                Task {
                                    await updateMovieWithChanges(movie, updates: ["is_available": !movie.isAvailable])
                                }
                            } label: {
                                Label(
                                    movie.isAvailable ? "Mark Unavailable" : "Mark Available",
                                    systemImage: movie.isAvailable ? "link.badge.plus" : "checkmark.circle"
                                )
                            }
                            Button {
                                editingMovie = movie
                            } label: {
                                Label("Edit…", systemImage: "pencil")
                            }
                            if let url = movie.youtubeURL {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    Label("Open on YouTube", systemImage: "play.circle")
                                }
                            }
                        }
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
                // Header
                if showOriginal {
                    // Side-by-side: Production (left) vs Original YouTube (right)
                    HStack(alignment: .top, spacing: 20) {
                        // Production / Enriched
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Production", systemImage: "sparkles")
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
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } placeholder: { Color.gray.opacity(0.2) }
                                .frame(width: 120, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 120, height: 180)
                                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                            }

                            Text(movie.title)
                                .font(.headline)
                                .lineLimit(3)
                                .frame(width: 160, alignment: .leading)
                        }

                        // Original YouTube
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Original YouTube", systemImage: "film")
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
                            } placeholder: { Color.gray.opacity(0.2) }
                            .frame(width: 160, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(movie.youtubeVideoTitle.isEmpty ? "(no title)" : movie.youtubeVideoTitle)
                                .font(.headline)
                                .lineLimit(3)
                                .frame(width: 160, alignment: .leading)
                        }

                        Spacer()
                    }
                    .padding(.bottom, 8)
                }

                // Normal header — only shown when NOT in original mode
                if !showOriginal {
                    HStack(alignment: .top, spacing: 16) {
                        if let posterPath = movie.posterPath {
                            let posterURL: URL? = {
                                if posterPath.hasPrefix("http") {
                                    return URL(string: posterPath)
                                } else {
                                    return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
                                }
                            }()

                            AsyncImage(url: posterURL) { image in
                                image.resizable().aspectRatio(contentMode: .fit)
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
                                    Image(systemName: "star.fill").foregroundColor(.yellow)
                                    Text(String(format: "%.1f", rating)).font(.headline)
                                    if let votes = movie.imdbVotes {
                                        Text("(\(votes) votes)").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }

                            if !movie.genres.isEmpty {
                                Text(movie.genres.map { $0.name }.joined(separator: ", "))
                                    .font(.subheadline).foregroundColor(.secondary)
                            }

                            HStack(spacing: 8) {
                                if !movie.isAvailable {
                                    StatusBadge(text: "Unavailable", color: .red)
                                }
                                if movie.needsVerification == true {
                                    StatusBadge(text: "Needs Verification", color: .orange)
                                }
                                if movie.isTvSeries == true { StatusBadge(text: "TV Series", color: .purple) }
                                if movie.isKidsContent == true { StatusBadge(text: "Kids", color: .green) }
                                if movie.isTvShow == true && movie.isTvSeries != true { StatusBadge(text: "TV Show", color: .blue) }
                            }

                            Spacer()
                            actionButtons(movie)
                        }
                    }
                } else {
                    // In original mode: show action buttons below the comparison
                    actionButtons(movie)
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

    // MARK: - Helper Views

    @ViewBuilder
    private func actionButtons(_ movie: Movie) -> some View {
        HStack(spacing: 12) {
            Button(action: { editingMovie = movie }) {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.bordered)

            Button(action: { Task { await enrichMovie(movie, priority: enrichmentPriority) } }) {
                if isEnriching {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Label("Enrich", systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isEnriching)

            if let url = movie.youtubeURL {
                Button(action: { NSWorkspace.shared.open(url) }) {
                    Label("YouTube", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
            }

            Button(action: {
                Task {
                    await updateMovieWithChanges(movie, updates: ["is_available": !movie.isAvailable])
                }
            }) {
                Label(
                    movie.isAvailable ? "Mark Unavailable" : "Mark Available",
                    systemImage: movie.isAvailable ? "link.badge.plus" : "checkmark.circle"
                )
            }
            .buttonStyle(.bordered)
            .tint(movie.isAvailable ? .red : .green)
        }
    }

    @ViewBuilder
    private func toggleButton(label: String, icon: String, isOn: Bool, color: Color, action: @escaping () -> Void) -> some View {
        if isOn {
            Button(action: action) { Label(label, systemImage: icon) }
                .buttonStyle(.borderedProminent)
                .tint(color)
        } else {
            Button(action: action) { Label(label, systemImage: icon) }
                .buttonStyle(.bordered)
                .tint(color)
        }
    }

    // MARK: - Actions

    func loadMovies() async {
        // Cancel any previous in-flight request to prevent pagination races
        loadTask?.cancel()

        let task = Task {
            isLoading = true
            errorMessage = nil

            do {
                // The admin endpoint supports include_unavailable + sort but not
                // the needs_verification filter, so that filter still uses the
                // public listing (which accepts needs_verification).
                let data: MoviesData
                if showNeedsVerification {
                    data = try await apiService.getMovies(
                        page: currentPage,
                        limit: itemsPerPage,
                        search: searchText.isEmpty ? nil : searchText,
                        needsVerification: true
                    )
                } else {
                    data = try await apiService.getAdminMovies(
                        includeUnavailable: includeUnavailable,
                        page: currentPage,
                        limit: itemsPerPage,
                        sort: sortOption.rawValue,
                        search: searchText.isEmpty ? nil : searchText
                    )
                }
                if !Task.isCancelled {
                    movies = data.movies
                    totalPages = data.pagination.pages ?? 1
                    totalMovies = data.pagination.total ?? 0
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Failed to load movies: \(error.localizedDescription)"
                }
            }

            if !Task.isCancelled {
                isLoading = false
            }
        }

        loadTask = task
        await task.value
    }

    func updateMovieWithChanges(_ movie: Movie, updates: [String: Any]) async {
        do {
            let updated = try await apiService.updateProductionMovie(movieId: movie.id, updates: updates)
            if selectedMovie?.id == updated.id {
                selectedMovie = updated
            }
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
    var onToggleVerification: (() -> Void)? = nil

    private var metaBadges: some View {
        HStack(spacing: 6) {
            if let year = movie.releaseYear {
                Text("\(year)").font(.caption).foregroundColor(.secondary)
            }
            if !movie.isAvailable { StatusBadge(text: "Unavailable", color: .red) }
            if movie.isTvSeries == true { StatusBadge(text: "TV Series", color: .purple) }
            if movie.isKidsContent == true { StatusBadge(text: "Kids", color: .green) }
            if let rating = movie.imdbRating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.caption2).foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating)).font(.caption)
                }
            }
            if movie.tmdbId != nil || movie.imdbId != nil {
                Image(systemName: "sparkles").font(.caption).foregroundColor(.blue)
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main selectable area
            HStack(spacing: 12) {
                if showOriginal {
                    // Split: production poster (left) + YouTube thumb (right)
                    HStack(spacing: 6) {
                        // Production poster
                        Group {
                            if let posterPath = movie.posterPath {
                                let posterURL: URL? = posterPath.hasPrefix("http")
                                    ? URL(string: posterPath)
                                    : URL(string: "https://image.tmdb.org/t/p/w92\(posterPath)")
                                AsyncImage(url: posterURL) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: { Color.blue.opacity(0.1) }
                            } else {
                                Color.blue.opacity(0.1)
                                    .overlay(Image(systemName: "sparkles").font(.caption).foregroundColor(.blue))
                            }
                        }
                        .frame(width: 45, height: 67)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.blue.opacity(0.3), lineWidth: 1))

                        // YouTube thumbnail
                        let thumbURL = URL(string: "https://img.youtube.com/vi/\(movie.youtubeVideoId)/mqdefault.jpg")
                        AsyncImage(url: thumbURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { Color.indigo.opacity(0.1) }
                        .frame(width: 60, height: 45)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                    }

                    // Titles: enriched on top, YouTube below
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles").font(.caption2).foregroundColor(.blue)
                            Text(movie.title).font(.headline).lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "film").font(.caption2).foregroundColor(.indigo)
                            Text(movie.youtubeVideoTitle.isEmpty ? "(no title)" : movie.youtubeVideoTitle)
                                .font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                        }
                        metaBadges
                    }
                } else {
                    // Normal: single poster + title
                    if let posterPath = movie.posterPath {
                        let posterURL: URL? = posterPath.hasPrefix("http")
                            ? URL(string: posterPath)
                            : URL(string: "https://image.tmdb.org/t/p/w92\(posterPath)")
                        AsyncImage(url: posterURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { Color.gray.opacity(0.2) }
                        .frame(width: 60, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 90)
                            .overlay(Image(systemName: "film").foregroundColor(.secondary))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(movie.title).font(.headline).lineLimit(2)
                        metaBadges
                        if let channel = movie.channelTitle {
                            Text(channel).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }

                Spacer()
            }
            .padding(8)
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }

            // Verification toggle — separate from select tap
            Button(action: { onToggleVerification?() }) {
                Image(systemName: movie.needsVerification == true ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(movie.needsVerification == true ? .orange : Color.secondary.opacity(0.4))
                    .padding(.trailing, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .help(movie.needsVerification == true ? "Unmark needs verification" : "Mark as needs verification")
        }
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : (movie.needsVerification == true ? Color.orange.opacity(0.4) : Color.clear), lineWidth: 2)
        )
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

// MARK: - Fix Titles Sheet

/// Previews title fixes (dryRun: true) and applies them on confirmation.
struct FixTitlesSheet: View {
    let apiService: AdminAPIService
    let onApplied: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isRunning = false
    @State private var result: FixTitlesResult?
    @State private var didApply = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(didApply ? "Fix Titles — Applied" : "Fix Titles — Preview")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(didApply ? "Applying title fixes…" : "Running preview (no changes applied)…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry Preview") {
                        Task { await runPreview() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = result {
                HStack(spacing: 16) {
                    summaryStat("Scanned", result.total, .secondary)
                    summaryStat(didApply ? "Updated" : "Would update", result.updated, .blue)
                    summaryStat("Unchanged", result.unchanged, .secondary)
                    summaryStat("Failed", result.failed, result.failed > 0 ? .red : .secondary)
                }

                if let changes = result.changes, !changes.isEmpty {
                    List(changes) { change in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.oldTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .strikethrough()
                            Text(change.newTitle)
                                .font(.body)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.bordered)
                } else {
                    Text(didApply ? "Titles updated." : "No titles need fixing.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            HStack {
                Spacer()
                if !didApply, let result = result, result.updated > 0 {
                    Button {
                        Task { await apply() }
                    } label: {
                        Label("Apply \(result.updated) Change\(result.updated == 1 ? "" : "s")", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .task { await runPreview() }
    }

    private func summaryStat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 80)
    }

    private func runPreview() async {
        isRunning = true
        errorMessage = nil
        do {
            result = try await apiService.fixTitles(dryRun: true)
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }

    private func apply() async {
        isRunning = true
        errorMessage = nil
        didApply = true
        do {
            result = try await apiService.fixTitles(dryRun: false)
            onApplied()
        } catch {
            didApply = false
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }
}

// MARK: - Re-enrich Channel Sheet

/// Runs POST /api/admin/enrich-enhanced for a chosen channel (or all channels).
struct EnrichChannelSheet: View {
    let apiService: AdminAPIService
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var channels: [Channel] = []
    @State private var selectedChannelId: String = ""   // "" = all channels
    @State private var limitText: String = "100"
    @State private var onlyUnenriched = true
    @State private var isRunning = false
    @State private var result: EnrichEnhancedResult?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Re-enrich Channel")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Picker("Channel", selection: $selectedChannelId) {
                Text("All channels").tag("")
                ForEach(channels) { channel in
                    Text(channel.title).tag(channel.id)
                }
            }

            HStack {
                Text("Limit")
                TextField("100", text: $limitText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("movies")
                    .foregroundColor(.secondary)
            }

            Toggle("Only movies without enrichment (no TMDB ID)", isOn: $onlyUnenriched)

            Text("Uses enhanced actor-based matching + IMDB scraping. This can take a while for large limits.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let result = result {
                GroupBox {
                    HStack(spacing: 20) {
                        Label("\(result.total) processed", systemImage: "film")
                        Label("\(result.enriched) enriched", systemImage: "sparkles")
                            .foregroundColor(.green)
                        Label("\(result.failed) failed", systemImage: "xmark.circle")
                            .foregroundColor(result.failed > 0 ? .red : .secondary)
                    }
                    .font(.callout)
                    .padding(6)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button {
                    Task { await run() }
                } label: {
                    if isRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Enriching…")
                        }
                    } else {
                        Label("Run Enrichment", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || Int(limitText.trimmingCharacters(in: .whitespaces)) == nil)
            }
        }
        .padding(20)
        .frame(width: 460, height: 380)
        .task { await loadChannels() }
    }

    private func loadChannels() async {
        do {
            channels = try await apiService.getChannels(page: 1, limit: 200).channels
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        } catch {
            // Non-fatal: the "All channels" option still works.
            errorMessage = "Could not load channel list: \(error.localizedDescription)"
        }
    }

    private func run() async {
        guard let limit = Int(limitText.trimmingCharacters(in: .whitespaces)), limit > 0 else {
            errorMessage = "Limit must be a positive number"
            return
        }
        isRunning = true
        errorMessage = nil
        result = nil
        do {
            result = try await apiService.enrichEnhanced(
                channelId: selectedChannelId.isEmpty ? nil : selectedChannelId,
                limit: limit,
                onlyUnenriched: onlyUnenriched
            )
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }
}

#Preview {
    MoviesView()
}
