import SwiftUI

struct StagingView: View {
    @StateObject private var apiService = AdminAPIService()
    @State private var stagedMovies: [StagedMovie] = []
    @State private var stats: StagingStats?
    @State private var channels: [Channel] = []

    // UI State
    @State private var selectedFilter: MovieFilter = .pending
    @State private var selectedMovie: StagedMovie?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showImportSheet = false
    @State private var showEnrichmentSheet = false
    @State private var showEditSheet = false
    @State private var showPublishAlert = false

    // Import form
    @State private var importChannelId = ""
    @State private var importChannelTitle = ""
    @State private var importLimit = 10

    // Enrichment form
    @State private var enrichmentPriority: EnrichmentPriority = .full
    @State private var enrichmentPreview: EnrichmentPreview?
    @State private var isPreviewingEnrichment = false
    @State private var isApplyingEnrichment = false

    // Edit form
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var editReleaseDate = ""

    // Selection
    @State private var selectedMovieIds: Set<String> = []

    enum MovieFilter: String, CaseIterable {
        case pending = "Pending"
        case enriched = "Enriched"
        case unenriched = "Unenriched"

        var approvalStatus: ApprovalStatus? {
            switch self {
            case .pending: return .pending
            case .enriched, .unenriched: return nil
            }
        }

        var filterParam: String? {
            switch self {
            case .pending: return nil
            case .enriched: return "enriched"
            case .unenriched: return "unenriched"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar - Movie List
            VStack(spacing: 0) {
                // Stats Header
                if let stats = stats {
                    statsHeader(stats: stats)
                }

                // Toolbar
                HStack {
                    Button(action: { showImportSheet = true }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }

                    Spacer()

                    Button(action: { showPublishAlert = true }) {
                        Label("Publish", systemImage: "arrow.up.circle")
                    }
                    .disabled(stats?.approved ?? 0 == 0)

                    Button(action: { Task { await loadMovies() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding()

                // Filter Tabs
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(MovieFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Divider()

                // Movie List
                if isLoading && stagedMovies.isEmpty {
                    ProgressView("Loading movies...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if stagedMovies.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No movies in staging")
                            .font(.headline)
                        Text("Import movies from a channel to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(stagedMovies, selection: $selectedMovie) { movie in
                        MovieRow(movie: movie, isSelected: selectedMovieIds.contains(movie.id))
                            .tag(movie)
                            .contextMenu {
                                Button("Approve") {
                                    Task { await approveMovie(movie) }
                                }
                                Button("Reject") {
                                    Task { await rejectMovie(movie, reason: "Manual rejection") }
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    Task { await deleteMovie(movie) }
                                }
                            }
                    }
                }

                // Error message
                if let errorMessage = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text(errorMessage)
                        Spacer()
                        Button("Dismiss") {
                            self.errorMessage = nil
                        }
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                }
            }
        } detail: {
            // Detail - Movie Preview & Actions
            if let movie = selectedMovie {
                MovieDetailView(
                    movie: movie,
                    enrichmentPreview: enrichmentPreview,
                    enrichmentPriority: $enrichmentPriority,
                    isPreviewingEnrichment: isPreviewingEnrichment,
                    isApplyingEnrichment: isApplyingEnrichment,
                    onPreviewEnrichment: { priority in
                        Task { await previewEnrichment(movie: movie, priority: priority) }
                    },
                    onApplyEnrichment: { priority in
                        Task { await applyEnrichment(movie: movie, priority: priority) }
                    },
                    onEdit: {
                        showEditSheet = true
                        editTitle = movie.title
                        editDescription = movie.description ?? ""
                        editReleaseDate = movie.releaseDate ?? ""
                    },
                    onApprove: {
                        Task { await approveMovie(movie) }
                    },
                    onReject: {
                        Task { await rejectMovie(movie, reason: "Manual rejection") }
                    }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a movie to preview")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportSheet(
                channels: channels,
                channelId: $importChannelId,
                channelTitle: $importChannelTitle,
                limit: $importLimit,
                onImport: {
                    Task {
                        await importMovies()
                        showImportSheet = false
                    }
                },
                onCancel: { showImportSheet = false }
            )
        }
        .sheet(isPresented: $showEditSheet) {
            if let movie = selectedMovie {
                EditMovieSheet(
                    movie: movie,
                    title: $editTitle,
                    description: $editDescription,
                    releaseDate: $editReleaseDate,
                    onSave: {
                        Task {
                            await updateMovie(movie)
                            showEditSheet = false
                        }
                    },
                    onCancel: { showEditSheet = false }
                )
            }
        }
        .alert("Publish Movies", isPresented: $showPublishAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Publish All Approved") {
                Task { await publishMovies() }
            }
        } message: {
            Text("Publish \(stats?.approved ?? 0) approved movies to production?")
        }
        .task {
            await loadInitialData()
        }
        .onChange(of: selectedFilter) {
            Task { await loadMovies() }
        }
    }

    // MARK: - Stats Header

    func statsHeader(stats: StagingStats) -> some View {
        HStack(spacing: 20) {
            StatBadge(title: "Total", value: stats.totalStaged, color: .blue)
            StatBadge(title: "Pending", value: stats.pending, color: .orange)
            StatBadge(title: "Approved", value: stats.approved, color: .green)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }

    // MARK: - API Actions

    func loadInitialData() async {
        await loadChannels()
        await loadStats()
        await loadMovies()
    }

    func loadChannels() async {
        do {
            let data = try await apiService.getChannels(limit: 100)
            channels = data.channels
        } catch {
            print("Failed to load channels: \(error)")
        }
    }

    func loadStats() async {
        do {
            stats = try await apiService.getStagingStats()
        } catch {
            print("Failed to load stats: \(error)")
        }
    }

    func loadMovies() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await apiService.getStagedMovies(
                status: selectedFilter.approvalStatus,
                filter: selectedFilter.filterParam,
                limit: 100
            )
            stagedMovies = data.movies
        } catch {
            errorMessage = "Failed to load movies: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func importMovies() async {
        guard !importChannelId.isEmpty, !importChannelTitle.isEmpty else {
            errorMessage = "Please select a channel"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await apiService.importToStaging(
                channelId: importChannelId,
                channelTitle: importChannelTitle,
                limit: importLimit
            )

            print("Imported \(result.imported) movies, skipped \(result.skipped)")

            await loadStats()
            await loadMovies()
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func previewEnrichment(movie: StagedMovie, priority: EnrichmentPriority) async {
        isPreviewingEnrichment = true
        enrichmentPreview = nil

        do {
            enrichmentPreview = try await apiService.previewEnrichment(
                movieId: movie.id,
                priority: priority
            )
        } catch {
            errorMessage = "Preview failed: \(error.localizedDescription)"
        }

        isPreviewingEnrichment = false
    }

    func applyEnrichment(movie: StagedMovie, priority: EnrichmentPriority) async {
        isApplyingEnrichment = true

        do {
            let updated = try await apiService.applyEnrichment(
                movieId: movie.id,
                priority: priority,
                applyFromPreview: enrichmentPreview != nil
            )

            // Update movie in list
            if let index = stagedMovies.firstIndex(where: { $0.id == movie.id }) {
                stagedMovies[index] = updated
                selectedMovie = updated
            }

            await loadStats()
        } catch {
            errorMessage = "Enrichment failed: \(error.localizedDescription)"
        }

        isApplyingEnrichment = false
    }

    func updateMovie(_ movie: StagedMovie) async {
        let updates: [String: Any] = [
            "title": editTitle,
            "description": editDescription,
            "release_date": editReleaseDate
        ]

        do {
            let updated = try await apiService.updateStagedMovie(
                movieId: movie.id,
                updates: updates
            )

            if let index = stagedMovies.firstIndex(where: { $0.id == movie.id }) {
                stagedMovies[index] = updated
                selectedMovie = updated
            }
        } catch {
            errorMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    func approveMovie(_ movie: StagedMovie) async {
        do {
            let updated = try await apiService.approveStagedMovie(movieId: movie.id)

            if let index = stagedMovies.firstIndex(where: { $0.id == movie.id }) {
                stagedMovies[index] = updated
                selectedMovie = updated
            }

            await loadStats()
        } catch {
            errorMessage = "Approval failed: \(error.localizedDescription)"
        }
    }

    func rejectMovie(_ movie: StagedMovie, reason: String) async {
        do {
            let updated = try await apiService.rejectStagedMovie(
                movieId: movie.id,
                reason: reason
            )

            if let index = stagedMovies.firstIndex(where: { $0.id == movie.id }) {
                stagedMovies[index] = updated
                selectedMovie = updated
            }

            await loadStats()
        } catch {
            errorMessage = "Rejection failed: \(error.localizedDescription)"
        }
    }

    func deleteMovie(_ movie: StagedMovie) async {
        do {
            try await apiService.deleteStagedMovie(movieId: movie.id)
            stagedMovies.removeAll { $0.id == movie.id }
            if selectedMovie?.id == movie.id {
                selectedMovie = nil
            }
            await loadStats()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func publishMovies() async {
        isLoading = true

        do {
            let result = try await apiService.publishStagedMovies()
            print("Published \(result.published) movies, \(result.failed) failed")

            await loadStats()
            await loadMovies()
        } catch {
            errorMessage = "Publish failed: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct MovieRow: View {
    let movie: StagedMovie
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Poster thumbnail
            if let posterPath = movie.posterPath {
                // Handle both full URLs (OMDB) and paths (TMDB)
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
                    Color.gray.opacity(0.3)
                }
                .frame(width: 40, height: 60)
                .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 60)
                    .cornerRadius(4)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Enrichment status
                    StatusBadge(
                        text: movie.enrichmentStatus,
                        color: movie.hasEnrichment ? .green : .gray
                    )

                    // Approval status
                    StatusBadge(
                        text: movie.approvalStatus.rawValue.capitalized,
                        color: statusColor(movie.approvalStatus)
                    )
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    func statusColor(_ status: ApprovalStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

struct MovieDetailView: View {
    let movie: StagedMovie
    let enrichmentPreview: EnrichmentPreview?
    @Binding var enrichmentPriority: EnrichmentPriority
    let isPreviewingEnrichment: Bool
    let isApplyingEnrichment: Bool
    let onPreviewEnrichment: (EnrichmentPriority) -> Void
    let onApplyEnrichment: (EnrichmentPriority) -> Void
    let onEdit: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with poster
                HStack(alignment: .top, spacing: 16) {
                    if let posterPath = movie.posterPath {
                        // Handle both full URLs (OMDB) and paths (TMDB)
                        let posterURL: URL? = {
                            if posterPath.hasPrefix("http") {
                                return URL(string: posterPath)
                            } else {
                                return URL(string: "https://image.tmdb.org/t/p/w300\(posterPath)")
                            }
                        }()

                        AsyncImage(url: posterURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 150)
                        .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(movie.title)
                            .font(.title)
                            .fontWeight(.bold)

                        if let releaseDate = movie.releaseDate {
                            Text(releaseDate)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let rating = movie.imdbRating {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .fontWeight(.semibold)
                            }
                        }

                        HStack {
                            StatusBadge(text: movie.enrichmentStatus, color: movie.hasEnrichment ? .green : .gray)
                            StatusBadge(text: movie.approvalStatus.rawValue.capitalized, color: statusColor(movie.approvalStatus))
                        }
                    }
                }

                Divider()

                // Description
                if let description = movie.description {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(description)
                            .font(.body)
                    }
                }

                // Enrichment section
                GroupBox("Enrichment") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Priority", selection: $enrichmentPriority) {
                            ForEach(EnrichmentPriority.allCases, id: \.self) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack {
                            Button(action: { onPreviewEnrichment(enrichmentPriority) }) {
                                if isPreviewingEnrichment {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Preview")
                                }
                            }
                            .disabled(isPreviewingEnrichment || isApplyingEnrichment)

                            Button(action: { onApplyEnrichment(enrichmentPriority) }) {
                                if isApplyingEnrichment {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Apply Enrichment")
                                }
                            }
                            .disabled(isPreviewingEnrichment || isApplyingEnrichment)
                            .buttonStyle(.borderedProminent)
                        }

                        // Preview results
                        if let preview = enrichmentPreview {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Preview Results")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    if let confidence = preview.confidence {
                                        Text("Confidence: \(Int(confidence * 100))%")
                                            .font(.caption)
                                            .foregroundColor(confidence > 0.8 ? .green : .orange)
                                    }
                                }

                                if let source = preview.source {
                                    Text("Source: \(source.uppercased())")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if let fieldsEnriched = preview.fieldsEnriched, !fieldsEnriched.isEmpty {
                                    Text("Fields to enrich: \(fieldsEnriched.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }

                // Actions
                GroupBox("Actions") {
                    VStack(spacing: 8) {
                        Button(action: onEdit) {
                            Label("Edit Manually", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }

                        Divider()

                        HStack {
                            Button(action: onApprove) {
                                Label("Approve", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(movie.approvalStatus == .approved)

                            Button(action: onReject) {
                                Label("Reject", systemImage: "xmark.circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                }

                // Metadata
                GroupBox("Metadata") {
                    VStack(alignment: .leading, spacing: 8) {
                        MetadataRow(label: "YouTube ID", value: movie.youtubeVideoId)
                        if let tmdbId = movie.tmdbId {
                            MetadataRow(label: "TMDB ID", value: String(tmdbId))
                        }
                        if let imdbId = movie.imdbId {
                            MetadataRow(label: "IMDB ID", value: imdbId)
                        }
                        if let director = movie.director {
                            MetadataRow(label: "Director", value: director)
                        }
                        if let actors = movie.actors {
                            MetadataRow(label: "Actors", value: actors)
                        }
                        MetadataRow(label: "Created", value: formatDate(movie.createdAt))
                    }
                }
            }
            .padding()
        }
    }

    func statusColor(_ status: ApprovalStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }

    func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct MetadataRow: View {
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
        }
    }
}

struct ImportSheet: View {
    let channels: [Channel]
    @Binding var channelId: String
    @Binding var channelTitle: String
    @Binding var limit: Int
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Import Movies to Staging")
                .font(.title2)
                .fontWeight(.bold)

            Form {
                Picker("Channel", selection: Binding(
                    get: { channelId },
                    set: { newId in
                        channelId = newId
                        if let channel = channels.first(where: { $0.id == newId }) {
                            channelTitle = channel.title
                        }
                    }
                )) {
                    Text("Select a channel").tag("")
                    ForEach(channels) { channel in
                        Text(channel.title).tag(channel.id)
                    }
                }

                Stepper("Limit: \(limit)", value: $limit, in: 1...50)
            }
            .frame(height: 150)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Import", action: onImport)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(channelId.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct EditMovieSheet: View {
    let movie: StagedMovie
    @Binding var title: String
    @Binding var description: String
    @Binding var releaseDate: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Movie")
                .font(.title2)
                .fontWeight(.bold)

            Form {
                TextField("Title", text: $title)
                TextField("Release Date (YYYY-MM-DD)", text: $releaseDate)
                TextEditor(text: $description)
                    .frame(height: 150)
                    .border(Color.gray.opacity(0.2))
            }
            .frame(height: 300)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500)
    }
}
