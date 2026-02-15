import SwiftUI

struct ChannelMoviesView: View {
    let channel: ChannelWithPattern
    @StateObject private var apiService = AdminAPIService()

    @State private var source = "staging,production"
    @State private var searchText = ""
    @State private var moviesData: ChannelMoviesData?
    @State private var isLoading = false
    @State private var error: String?
    @State private var successMessage: String?

    // Pagination
    @State private var currentPage = 1
    @State private var itemsPerPage = 100

    // Batch operations
    @State private var selectedMovieIds: Set<String> = []
    @State private var showDeleteConfirm = false
    @State private var showReimportConfirm = false
    @State private var isPerformingBatchAction = false

    // Enrichment progress
    @State private var showEnrichmentProgress = false
    @State private var enrichmentProgress: EnrichmentProgress?

    var body: some View {
        VStack(spacing: 0) {
            // Header with filters and stats
            VStack(spacing: 12) {
                HStack {
                    Text("Channel Movies")
                        .font(.title)
                        .fontWeight(.bold)

                    Spacer()

                    // Stats
                    if let data = moviesData {
                        HStack(spacing: 20) {
                            if let staging = data.staging {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(staging.total)")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Text("Staging")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if let production = data.production {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(production.total)")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                    Text("Production")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Button {
                        Task { await loadMovies() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }

                // Filters
                HStack {
                    // Source filter
                    Picker("Source", selection: $source) {
                        Text("All").tag("staging,production")
                        Text("Staging Only").tag("staging")
                        Text("Production Only").tag("production")
                    }
                    .frame(width: 200)
                    .onChange(of: source) { _, _ in
                        Task { await loadMovies() }
                    }

                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search movies...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))

            // Batch Actions Bar
            if !selectedMovieIds.isEmpty {
                HStack {
                    Text("\(selectedMovieIds.count) selected")
                        .font(.headline)

                    Spacer()

                    Button(action: { Task { await batchEnrich() } }) {
                        Label("Enrich Selected", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPerformingBatchAction)

                    Button(action: { /* batch approve */ }) {
                        Label("Approve Selected", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPerformingBatchAction)

                    Button(role: .destructive, action: { /* batch delete */ }) {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .disabled(isPerformingBatchAction)

                    Button("Clear Selection") {
                        selectedMovieIds.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
            }

            Divider()

            // Channel-wide Actions
            HStack {
                Button(action: { Task { await enrichAllUnenriched() } }) {
                    Label("Enrich All Unenriched", systemImage: "sparkles.rectangle.stack")
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingBatchAction)

                Button(action: { showReimportConfirm = true }) {
                    Label("Re-import Channel", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingBatchAction)

                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Label("Delete All Movies", systemImage: "trash.circle")
                }
                .disabled(isPerformingBatchAction)

                Spacer()
            }
            .padding()

            Divider()

            // Messages
            if let success = successMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(success)
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
            }

            if let error = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
            }

            // Movie Lists
            if isLoading {
                ProgressView("Loading movies...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Staging Movies
                        if let staging = moviesData?.staging, !staging.movies.isEmpty {
                            MovieSection(
                                title: "Staging (\(staging.total))",
                                movies: staging.movies,
                                selectedIds: $selectedMovieIds,
                                color: .orange,
                                onUpdate: loadMovies
                            )
                        }

                        // Production Movies
                        if let production = moviesData?.production, !production.movies.isEmpty {
                            MovieSection(
                                title: "Production (\(production.total))",
                                movies: production.movies,
                                selectedIds: $selectedMovieIds,
                                color: .green,
                                onUpdate: loadMovies
                            )
                        }

                        // Pagination Controls - always show when we have movies
                        if let moviesData = moviesData,
                           (moviesData.staging != nil || moviesData.production != nil) {
                            let pagination = moviesData.pagination
                            let staging = moviesData.staging
                            let production = moviesData.production

                            // Calculate total pages
                            let totalPages: Int = {
                                if let pages = pagination?.pages {
                                    return pages
                                }
                                if let total = pagination?.total {
                                    return max(1, (total + itemsPerPage - 1) / itemsPerPage)
                                }
                                return 1
                            }()

                            // Count movies shown
                            let moviesShown = (staging?.movies.count ?? 0) + (production?.movies.count ?? 0)
                            let totalMovies = (staging?.total ?? 0) + (production?.total ?? 0)

                            HStack(spacing: 12) {
                                Button(action: { previousPage() }) {
                                    Label("Previous", systemImage: "chevron.left")
                                }
                                .disabled(currentPage == 1)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Page \(currentPage) of \(totalPages)")
                                        .font(.headline)
                                        .foregroundColor(.secondary)

                                    HStack(spacing: 4) {
                                        Text("Showing \(moviesShown) movies")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.blue)
                                        if totalMovies > 0 {
                                            Text("•")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("\(totalMovies) total")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                Button(action: { nextPage() }) {
                                    Label("Next", systemImage: "chevron.right")
                                }
                                .disabled(currentPage >= totalPages || moviesShown < itemsPerPage)

                                Spacer()

                                Picker("Items per page", selection: $itemsPerPage) {
                                    Text("50").tag(50)
                                    Text("100").tag(100)
                                    Text("200").tag(200)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 150)
                                .onChange(of: itemsPerPage) { oldValue, newValue in
                                    currentPage = 1
                                    Task { await loadMovies() }
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }

                        if moviesData?.staging?.movies.isEmpty == true && moviesData?.production?.movies.isEmpty == true {
                            VStack(spacing: 12) {
                                Image(systemName: "film")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                Text("No movies found")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Import videos from this channel to see them here")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(60)
                        }
                    }
                    .padding()
                }
            }
        }
        .confirmationDialog("Delete All Movies", isPresented: $showDeleteConfirm) {
            Button("Delete from Staging Only", role: .destructive) {
                deleteAllMovies(from: "staging")
            }
            Button("Delete from Production Only", role: .destructive) {
                deleteAllMovies(from: "production")
            }
            Button("Delete from Both", role: .destructive) {
                deleteAllMovies(from: "staging,production")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all movies from this channel. This action cannot be undone.")
        }
        .confirmationDialog("Re-import Channel", isPresented: $showReimportConfirm) {
            Button("Re-import (Keep Existing)") {
                reimportChannel(deleteExisting: false)
            }
            Button("Re-import (Delete & Re-import)", role: .destructive) {
                reimportChannel(deleteExisting: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether to keep existing movies or delete and re-import everything.")
        }
        .sheet(isPresented: $showEnrichmentProgress) {
            EnrichmentProgressModal(
                progress: enrichmentProgress,
                onClose: { showEnrichmentProgress = false }
            )
        }
        .task {
            await loadMovies()
        }
    }

    // MARK: - Actions

    func loadMovies() async {
        isLoading = true
        error = nil

        do {
            let data = try await apiService.getChannelMovies(
                channelId: channel.id,
                source: source,
                page: currentPage,
                limit: itemsPerPage
            )
            moviesData = data
        } catch {
            self.error = "Failed to load movies: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func nextPage() {
        guard let pagination = moviesData?.pagination else { return }

        // Calculate total pages if not provided
        let totalPages = pagination.pages ?? {
            guard let total = pagination.total else { return 1 }
            return (total + itemsPerPage - 1) / itemsPerPage
        }()

        guard currentPage < totalPages else { return }
        currentPage += 1
        Task { await loadMovies() }
    }

    func previousPage() {
        guard currentPage > 1 else { return }
        currentPage -= 1
        Task { await loadMovies() }
    }

    func deleteAllMovies(from source: String) {
        Task {
            isPerformingBatchAction = true
            error = nil
            successMessage = nil

            do {
                let result = try await apiService.deleteChannelMovies(
                    channelId: channel.id,
                    deleteFrom: source
                )

                let total = result.deletedFromStaging + result.deletedFromProduction
                successMessage = "Deleted \(total) movies (\(result.deletedFromStaging) from staging, \(result.deletedFromProduction) from production)"

                await loadMovies()

                // Clear success message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    successMessage = nil
                }
            } catch {
                self.error = "Failed to delete movies: \(error.localizedDescription)"
            }

            isPerformingBatchAction = false
        }
    }

    func reimportChannel(deleteExisting: Bool) {
        Task {
            isPerformingBatchAction = true
            error = nil
            successMessage = nil

            do {
                let response = try await apiService.reimportChannel(
                    channelId: channel.id,
                    deleteExisting: deleteExisting,
                    limit: nil,
                    applySettings: true
                )

                successMessage = "Re-import started (Batch ID: \(response.batchId)). Check Import History for progress."

                if deleteExisting {
                    await loadMovies()
                }

                // Clear success message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    successMessage = nil
                }
            } catch {
                self.error = "Failed to start re-import: \(error.localizedDescription)"
            }

            isPerformingBatchAction = false
        }
    }

    func batchEnrich() async {
        isPerformingBatchAction = true
        error = nil
        successMessage = nil

        // Show progress modal
        enrichmentProgress = EnrichmentProgress(
            status: "running",
            total: selectedMovieIds.count,
            enriched: 0,
            failed: 0,
            skipped: 0,
            current: nil
        )
        showEnrichmentProgress = true

        do {
            // Start enrichment (returns immediately with batch ID)
            let startResponse = try await apiService.batchEnrich(
                movieIds: Array(selectedMovieIds),
                priority: .full
            )

            // Poll for progress updates
            await pollEnrichmentProgress(batchId: startResponse.batchId)

            // Reload movies to show enrichment data
            await loadMovies()

            // Clear selection
            selectedMovieIds.removeAll()
        } catch {
            // Update progress to failed
            enrichmentProgress = EnrichmentProgress(
                status: "failed",
                total: selectedMovieIds.count,
                enriched: 0,
                failed: 0,
                skipped: 0,
                current: nil
            )
            self.error = "Failed to enrich movies: \(error.localizedDescription)"
        }

        isPerformingBatchAction = false
    }

    func pollEnrichmentProgress(batchId: String) async {
        while true {
            do {
                let progress = try await apiService.getBatchEnrichmentProgress(batchId: batchId)

                // Update UI with progress
                enrichmentProgress = EnrichmentProgress(
                    status: progress.status,
                    total: progress.total,
                    enriched: progress.enriched,
                    failed: progress.failed,
                    skipped: progress.skipped,
                    current: progress.current
                )

                // Break if completed or failed
                if progress.status == "completed" || progress.status == "failed" {
                    break
                }

                // Wait before next poll (1 second)
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                print("Error polling enrichment progress: \(error)")
                break
            }
        }
    }

    func enrichAllUnenriched() async {
        isPerformingBatchAction = true
        error = nil
        successMessage = nil

        do {
            // Get all unenriched staging movies for this channel
            guard let staging = moviesData?.staging else {
                self.error = "No staging movies found"
                isPerformingBatchAction = false
                return
            }

            let unenrichedIds = staging.movies
                .filter { $0.tmdbId == nil && $0.imdbId == nil }
                .map { $0.id }

            if unenrichedIds.isEmpty {
                successMessage = "All movies are already enriched!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    successMessage = nil
                }
                isPerformingBatchAction = false
                return
            }

            // Show progress modal
            enrichmentProgress = EnrichmentProgress(
                status: "running",
                total: unenrichedIds.count,
                enriched: 0,
                failed: 0,
                skipped: 0,
                current: nil
            )
            showEnrichmentProgress = true

            // Start enrichment (returns immediately with batch ID)
            let startResponse = try await apiService.batchEnrich(
                movieIds: unenrichedIds,
                priority: .full
            )

            // Poll for progress updates
            await pollEnrichmentProgress(batchId: startResponse.batchId)

            // Reload movies to show enrichment data
            await loadMovies()
        } catch {
            // Update progress to failed
            enrichmentProgress = EnrichmentProgress(
                status: "failed",
                total: 0,
                enriched: 0,
                failed: 0,
                skipped: 0,
                current: nil
            )
            self.error = "Failed to enrich movies: \(error.localizedDescription)"
        }

        isPerformingBatchAction = false
    }
}

// MARK: - Movie Section

struct MovieSection: View {
    let title: String
    let movies: [StagedMovie]
    @Binding var selectedIds: Set<String>
    let color: Color
    let onUpdate: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(title, systemImage: "film")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(color)

                    Text("Showing \(movies.count) movies on this page")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                Spacer()

                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        movies.forEach { selectedIds.remove($0.id) }
                    } else {
                        movies.forEach { selectedIds.insert($0.id) }
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }

            ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
                ChannelMovieRow(
                    rowNumber: index + 1,
                    movie: movie,
                    isSelected: selectedIds.contains(movie.id),
                    onToggleSelection: {
                        if selectedIds.contains(movie.id) {
                            selectedIds.remove(movie.id)
                        } else {
                            selectedIds.insert(movie.id)
                        }
                    },
                    onUpdate: {
                        Task {
                            await onUpdate()
                        }
                    }
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    var allSelected: Bool {
        !movies.isEmpty && movies.allSatisfy { selectedIds.contains($0.id) }
    }
}

// MARK: - Channel Movie Row

struct ChannelMovieRow: View {
    let rowNumber: Int
    let movie: StagedMovie
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onUpdate: () -> Void
    @State private var showDetail = false

    var body: some View {
        rowContent
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.white)
            .cornerRadius(8)
            .overlay(borderOverlay)
            .sheet(isPresented: $showDetail) {
                ChannelMovieDetailView(movie: movie, onUpdate: onUpdate)
            }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            rowNumberView
            checkboxView
            postersView
            movieInfoView
            Spacer()
            actionsView
        }
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1)
    }

    // MARK: - Subviews

    private var rowNumberView: some View {
        Text("\(rowNumber)")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .frame(width: 30, alignment: .trailing)
    }

    private var checkboxView: some View {
        Button(action: onToggleSelection) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.title2)
                .foregroundColor(isSelected ? .blue : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var postersView: some View {
        HStack(spacing: 8) {
            youtubeThumbnailView
            tmdbPosterView
        }
    }

    @ViewBuilder
    private var youtubeThumbnailView: some View {
        if let thumbnailURL = movie.youtubeThumbnailURL {
            AsyncImage(url: thumbnailURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
                    .overlay(ProgressView().scaleEffect(0.5))
            }
            .frame(width: 80, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(playIconOverlay, alignment: .bottomTrailing)
        }
    }

    private var playIconOverlay: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.caption2)
            .foregroundColor(.white)
            .padding(4)
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
            .padding(4)
    }

    @ViewBuilder
    private var tmdbPosterView: some View {
        if let posterPath = movie.posterPath {
            AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w92\(posterPath)")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 60, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var movieInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleSection
            Divider()
            metadataSection
            statusBadge
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(movie.title)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "play.rectangle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
                Text(movie.youtubeVideoTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        if let releaseDate = movie.releaseDate {
            let year = String(releaseDate.prefix(4))
            Text("Year: \(year)")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if let category = movie.category {
            Text("Category: \(category)")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if let actors = movie.actors {
            let actorList = actors.split(separator: ",").prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }
            Text("Actors: \(actorList.joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var statusBadge: some View {
        Text(movie.approvalStatus.rawValue.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor(movie.approvalStatus.rawValue))
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private var actionsView: some View {
        VStack(spacing: 8) {
            if movie.enrichmentSource != nil {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
            }

            Button(action: { showDetail = true }) {
                Label("Details", systemImage: "info.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "approved": return .green
        case "rejected": return .red
        case "pending": return .orange
        default: return .gray
        }
    }
}

// MARK: - Enrichment Progress Model

struct EnrichmentProgress {
    let status: String
    let total: Int
    let enriched: Int
    let failed: Int
    let skipped: Int
    let current: String?

    var percentage: Int {
        guard total > 0 else { return 0 }
        let completed = enriched + failed + skipped
        return Int((Double(completed) / Double(total)) * 100)
    }
}

// MARK: - Enrichment Progress Modal

struct EnrichmentProgressModal: View {
    let progress: EnrichmentProgress?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: statusIcon)
                    .font(.largeTitle)
                    .foregroundColor(statusColor)
                Text("Enriching Movies")
                    .font(.title)
                    .fontWeight(.bold)
            }

            if let progress = progress {
                // Progress bar
                if progress.status == "running" {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(progress.percentage), total: 100.0)
                            .frame(width: 400)

                        Text("\(progress.percentage)%")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }

                // Current movie
                if let currentTitle = progress.current {
                    VStack(spacing: 4) {
                        Text("Current movie:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currentTitle)
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: 400)
                    }
                }

                // Statistics
                VStack(spacing: 12) {
                    HStack(spacing: 40) {
                        StatItem(label: "Total", value: "\(progress.total)", color: .blue)
                        StatItem(label: "Enriched", value: "\(progress.enriched)", color: .green)
                        StatItem(label: "Skipped", value: "\(progress.skipped)", color: .orange)
                        StatItem(label: "Failed", value: "\(progress.failed)", color: .red)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Status-specific actions
                if progress.status == "completed" {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Enrichment completed!")
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)

                    Button("Close") {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if progress.status == "failed" {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Enrichment failed")
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)

                    Button("Close") {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    ProgressView("Enriching movies...")
                        .scaleEffect(1.2)
                }
            } else {
                ProgressView("Initializing enrichment...")
            }
        }
        .padding(40)
        .frame(width: 600)
    }

    var statusIcon: String {
        guard let progress = progress else { return "sparkles" }
        switch progress.status {
        case "completed": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        default: return "sparkles"
        }
    }

    var statusColor: Color {
        guard let progress = progress else { return .blue }
        switch progress.status {
        case "completed": return .green
        case "failed": return .red
        default: return .blue
        }
    }
}

#Preview {
    ChannelMoviesView(
        channel: ChannelWithPattern(
            id: "UC123",
            title: "Test Channel",
            description: "A test channel",
            thumbnailUrl: nil,
            subscriberCount: 1000,
            videoCount: 100,
            isCurated: false,
            hasPattern: false,
            pattern: nil,
            createdAt: "",
            updatedAt: nil
        )
    )
}
