import SwiftUI
import AppKit

struct StagingView: View {
    @StateObject private var apiService = AdminAPIService()
    @State private var stagedMovies: [StagedMovie] = []
    @State private var stats: StagingStats?
    @State private var channels: [Channel] = []

    // UI State
    @State private var selectedStatus: StatusFilter = .pending
    @State private var selectedChannelId: String = ""      // "" == all channels
    @State private var searchText: String = ""
    @State private var selectedMovie: StagedMovie?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var showImportSheet = false
    @State private var showEditSheet = false
    @State private var showPublishAlert = false

    // Pagination
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var totalCount = 0
    private let pageSize = 100

    // Search debounce
    @State private var searchDebounceTask: Task<Void, Never>?

    // Toast / status banner
    @State private var toast: ToastMessage?
    @State private var toastDismissTask: Task<Void, Never>?

    // TV Series state
    @State private var tvSeriesList: [TvSeries] = []
    @State private var movieForSeriesAssignment: StagedMovie?
    @State private var showSeriesSheet = false
    @State private var newSeriesTitle = ""
    @State private var isCreatingSeries = false

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

    // Multi-selection (bulk operations)
    @State private var selectedMovieIds: Set<String> = []

    // Bulk reject sheet
    @State private var showBulkRejectSheet = false
    @State private var bulkRejectReason = ""

    // Batch enrichment progress
    @State private var batchProgress: BatchEnrichmentProgress?
    @State private var showBatchProgressSheet = false
    @State private var batchPollTask: Task<Void, Never>?

    // Delete confirmation
    @State private var movieToDelete: StagedMovie?
    @State private var showDeleteConfirmation = false

    // Reject sheet (single)
    @State private var movieForRejection: StagedMovie?
    @State private var showRejectSheet = false
    @State private var rejectReason = ""

    enum StatusFilter: String, CaseIterable {
        case pending = "Pending"
        case enriched = "Enriched"
        case approved = "Approved"
        case rejected = "Rejected"

        var approvalStatus: ApprovalStatus? {
            switch self {
            case .pending: return .pending
            case .enriched: return nil     // handled via filter param
            case .approved: return .approved
            case .rejected: return .rejected
            }
        }

        var filterParam: String? {
            switch self {
            case .enriched: return "enriched"
            default: return nil
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
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
        .sheet(isPresented: $showSeriesSheet) {
            if let movie = movieForSeriesAssignment {
                SeriesPickerSheet(
                    movie: movie,
                    seriesList: tvSeriesList,
                    newSeriesTitle: $newSeriesTitle,
                    isCreating: isCreatingSeries,
                    onSelect: { series in
                        Task { await assignSeries(movie: movie, series: series) }
                        showSeriesSheet = false
                    },
                    onRemove: {
                        Task { await assignSeries(movie: movie, series: nil) }
                        showSeriesSheet = false
                    },
                    onCreate: {
                        Task { await createAndAssignSeries(movie: movie) }
                    },
                    onCancel: { showSeriesSheet = false }
                )
            }
        }
        .sheet(isPresented: $showBulkRejectSheet) {
            BulkRejectSheet(
                count: selectedMovieIds.count,
                reason: $bulkRejectReason,
                onReject: {
                    Task {
                        await rejectSelected(reason: bulkRejectReason.isEmpty ? "Bulk rejection" : bulkRejectReason)
                        showBulkRejectSheet = false
                        bulkRejectReason = ""
                    }
                },
                onCancel: {
                    showBulkRejectSheet = false
                    bulkRejectReason = ""
                }
            )
        }
        .sheet(isPresented: $showBatchProgressSheet) {
            BatchProgressSheet(
                progress: batchProgress,
                onClose: {
                    showBatchProgressSheet = false
                    batchPollTask?.cancel()
                    Task {
                        await loadStats()
                        await loadMovies(reset: true)
                    }
                }
            )
        }
        .alert("Publish Movies", isPresented: $showPublishAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Publish All Approved") {
                Task { await publishMovies() }
            }
        } message: {
            Text("Publish \(stats?.approved ?? 0) approved movies to production?")
        }
        .confirmationDialog(
            "Delete \"\(movieToDelete?.title ?? "this movie")\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let movie = movieToDelete {
                    Task { await deleteMovie(movie) }
                }
                movieToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                movieToDelete = nil
            }
        } message: {
            Text("This will permanently remove the staged movie. This action cannot be undone.")
        }
        .sheet(isPresented: $showRejectSheet) {
            if let movie = movieForRejection {
                RejectMovieSheet(
                    movie: movie,
                    reason: $rejectReason,
                    onReject: {
                        Task {
                            await rejectMovie(movie, reason: rejectReason.isEmpty ? "Manual rejection" : rejectReason)
                            showRejectSheet = false
                            rejectReason = ""
                            movieForRejection = nil
                        }
                    },
                    onCancel: {
                        showRejectSheet = false
                        rejectReason = ""
                        movieForRejection = nil
                    }
                )
            }
        }
        .task {
            await loadInitialData()
        }
        .onChange(of: selectedStatus) {
            Task { await loadMovies(reset: true) }
        }
        .onChange(of: selectedChannelId) {
            Task { await loadMovies(reset: true) }
        }
        .onChange(of: searchText) {
            scheduleSearch()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
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
                .disabled((stats?.approved ?? 0) == 0)

                Button(action: { Task { await loadStats(); await loadMovies(reset: true) } }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Search + channel filter
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search titles…", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

                Picker("Channel", selection: $selectedChannelId) {
                    Text("All channels").tag("")
                    ForEach(channels) { channel in
                        Text(channel.title).tag(channel.id)
                    }
                }
                .labelsHidden()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Status filter
            Picker("Status", selection: $selectedStatus) {
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            // Bulk action bar
            if !selectedMovieIds.isEmpty {
                bulkActionBar
            }

            Divider()

            movieList

            // Load more + count
            footerBar
        }
        .overlay(alignment: .bottom) {
            if let toast = toast {
                ToastBannerView(toast: toast) { self.toast = nil }
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var bulkActionBar: some View {
        HStack(spacing: 8) {
            Text("\(selectedMovieIds.count) selected")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("Approve") { Task { await approveSelected() } }
                .help("Approve selected")
            Button("Reject") { showBulkRejectSheet = true }
                .help("Reject selected with a shared reason")
            Button("Enrich") { Task { await batchEnrichSelected() } }
                .help("Batch enrich selected")
            Button("Clear") { selectedMovieIds.removeAll() }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
    }

    private var movieList: some View {
        Group {
            if isLoading && stagedMovies.isEmpty {
                ProgressView("Loading movies…")
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
                    MovieRow(
                        movie: movie,
                        isChecked: selectedMovieIds.contains(movie.id),
                        onToggleCheck: { toggleCheck(movie) },
                        tvSeriesList: tvSeriesList,
                        onDelete: {
                            movieToDelete = movie
                            showDeleteConfirmation = true
                        },
                        onAssignSeries: {
                            movieForSeriesAssignment = movie
                            showSeriesSheet = true
                        }
                    )
                    .tag(movie)
                    .contextMenu {
                        Button("Approve") { Task { await approveAndAdvance(movie) } }
                        Button("Reject") {
                            movieForRejection = movie
                            rejectReason = ""
                            showRejectSheet = true
                        }
                        Button("Enrich") { Task { await applyEnrichment(movie: movie, priority: enrichmentPriority) } }
                        Divider()
                        Button("Open on YouTube") { openYouTube(movie) }
                        Divider()
                        Button("Delete", role: .destructive) {
                            movieToDelete = movie
                            showDeleteConfirmation = true
                        }
                    }
                }
                .onKeyPress { press in handleKeyPress(press) }
            }
        }
    }

    private var footerBar: some View {
        HStack {
            if let errorMessage = errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                Text(errorMessage)
                    .font(.caption)
                    .lineLimit(1)
                Button("Dismiss") { self.errorMessage = nil }
                    .buttonStyle(.borderless)
            } else {
                Text("Showing \(stagedMovies.count) of \(totalCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if currentPage < totalPages {
                    Button(action: { Task { await loadMore() } }) {
                        if isLoadingMore {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Load More")
                        }
                    }
                    .disabled(isLoadingMore)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        Group {
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
                    onApprove: { Task { await approveAndAdvance(movie) } },
                    onReject: {
                        movieForRejection = movie
                        rejectReason = ""
                        showRejectSheet = true
                    },
                    onOpenYouTube: { openYouTube(movie) },
                    onToggleTvSeries: { isTvSeries in
                        Task { await toggleTvSeries(movie: movie, isTvSeries: isTvSeries) }
                    }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a movie to preview")
                        .font(.headline)
                    Text("Keys: A approve · R reject · E enrich · J/K move · Space YouTube")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Stats Header

    func statsHeader(stats: StagingStats) -> some View {
        HStack(spacing: 20) {
            StatBadge(title: "Total", value: stats.totalStaged, color: .blue)
            StatBadge(title: "Pending", value: stats.pending, color: .orange)
            StatBadge(title: "Enriched", value: stats.enriched, color: .yellow)
            StatBadge(title: "Approved", value: stats.approved, color: .green)
            StatBadge(title: "Rejected", value: stats.rejected, color: .red)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }

    // MARK: - Selection helpers

    private func toggleCheck(_ movie: StagedMovie) {
        if selectedMovieIds.contains(movie.id) {
            selectedMovieIds.remove(movie.id)
        } else {
            selectedMovieIds.insert(movie.id)
        }
    }

    private var currentIndex: Int? {
        guard let selected = selectedMovie else { return nil }
        return stagedMovies.firstIndex(where: { $0.id == selected.id })
    }

    private func moveSelection(by delta: Int) {
        guard !stagedMovies.isEmpty else { return }
        let idx = currentIndex ?? -1
        let next = max(0, min(stagedMovies.count - 1, idx + delta))
        selectedMovie = stagedMovies[next]
    }

    /// Advance selection to the next row (used after approve/reject).
    private func advanceSelection() {
        guard let idx = currentIndex else { return }
        if idx + 1 < stagedMovies.count {
            selectedMovie = stagedMovies[idx + 1]
        } else if idx - 1 >= 0 {
            selectedMovie = stagedMovies[idx - 1]
        } else {
            selectedMovie = nil
        }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow: moveSelection(by: -1); return .handled
        case .downArrow: moveSelection(by: 1); return .handled
        case .return:
            // Return "opens" detail — selection already drives the detail pane.
            return .handled
        default:
            break
        }

        switch press.characters.lowercased() {
        case "j": moveSelection(by: 1); return .handled
        case "k": moveSelection(by: -1); return .handled
        case "a":
            if let m = selectedMovie { Task { await approveAndAdvance(m) } }
            return .handled
        case "r":
            if let m = selectedMovie {
                movieForRejection = m
                rejectReason = ""
                showRejectSheet = true
            }
            return .handled
        case "e":
            if let m = selectedMovie { Task { await applyEnrichment(movie: m, priority: enrichmentPriority) } }
            return .handled
        case " ":
            if let m = selectedMovie { openYouTube(m) }
            return .handled
        default:
            return .ignored
        }
    }

    private func openYouTube(_ movie: StagedMovie) {
        if let url = movie.youtubeURL {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String, isError: Bool = false) {
        toastDismissTask?.cancel()
        withAnimation { toast = ToastMessage(text: message, isError: isError) }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                withAnimation { toast = nil }
            }
        }
    }

    // MARK: - Search debounce

    private func scheduleSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !Task.isCancelled {
                await loadMovies(reset: true)
            }
        }
    }

    // MARK: - API Actions

    func loadInitialData() async {
        await loadChannels()
        await loadStats()
        await loadMovies(reset: true)
        await loadTvSeries()
    }

    func loadTvSeries() async {
        do {
            tvSeriesList = try await apiService.fetchAllTvSeries()
        } catch {
            errorMessage = "Failed to load TV series: \(error.localizedDescription)"
        }
    }

    func loadChannels() async {
        do {
            let data = try await apiService.getChannels(limit: 100)
            channels = data.channels
        } catch {
            errorMessage = "Failed to load channels: \(error.localizedDescription)"
        }
    }

    func loadStats() async {
        do {
            stats = try await apiService.getStagingStats()
        } catch {
            errorMessage = "Failed to load stats: \(error.localizedDescription)"
        }
    }

    func loadMovies(reset: Bool) async {
        if reset {
            isLoading = true
            currentPage = 1
        }
        errorMessage = nil

        do {
            let data = try await apiService.getStagedMovies(
                status: selectedStatus.approvalStatus,
                filter: selectedStatus.filterParam,
                channelId: selectedChannelId.isEmpty ? nil : selectedChannelId,
                search: searchText.isEmpty ? nil : searchText,
                page: 1,
                limit: pageSize
            )
            stagedMovies = data.movies
            currentPage = data.pagination.page
            totalPages = max(data.pagination.pages ?? 1, 1)
            totalCount = data.pagination.total ?? 0
            // Keep the current selection if it is still present.
            if let sel = selectedMovie, !stagedMovies.contains(where: { $0.id == sel.id }) {
                selectedMovie = nil
            }
        } catch {
            errorMessage = "Failed to load movies: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func loadMore() async {
        guard currentPage < totalPages, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = currentPage + 1
        do {
            let data = try await apiService.getStagedMovies(
                status: selectedStatus.approvalStatus,
                filter: selectedStatus.filterParam,
                channelId: selectedChannelId.isEmpty ? nil : selectedChannelId,
                search: searchText.isEmpty ? nil : searchText,
                page: nextPage,
                limit: pageSize
            )
            // Append, avoiding duplicates.
            let existing = Set(stagedMovies.map(\.id))
            stagedMovies.append(contentsOf: data.movies.filter { !existing.contains($0.id) })
            currentPage = data.pagination.page
            totalPages = max(data.pagination.pages ?? 1, 1)
            totalCount = data.pagination.total ?? 0
        } catch {
            errorMessage = "Failed to load more: \(error.localizedDescription)"
        }
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
            showToast("Imported \(result.imported), skipped \(result.skipped)")
            await loadStats()
            await loadMovies(reset: true)
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
            showToast("Import failed", isError: true)
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
            showToast("Preview failed", isError: true)
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
            replaceMovie(updated)
            showToast("Enriched \"\(updated.title)\"")
            await loadStats()
        } catch {
            errorMessage = "Enrichment failed: \(error.localizedDescription)"
            showToast("Enrichment failed", isError: true)
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
            let updated = try await apiService.updateStagedMovie(movieId: movie.id, updates: updates)
            replaceMovie(updated)
            showToast("Saved changes")
        } catch {
            errorMessage = "Update failed: \(error.localizedDescription)"
            showToast("Update failed", isError: true)
        }
    }

    func approveAndAdvance(_ movie: StagedMovie) async {
        do {
            _ = try await apiService.approveStagedMovie(movieId: movie.id)
            // If we are viewing a non-approved filter, the row leaves the list.
            advanceSelection()
            removeMovieFromList(movie.id)
            selectedMovieIds.remove(movie.id)
            showToast("Approved \"\(movie.title)\"")
            await loadStats()
        } catch {
            errorMessage = "Approval failed: \(error.localizedDescription)"
            showToast("Approval failed", isError: true)
        }
    }

    func rejectMovie(_ movie: StagedMovie, reason: String) async {
        do {
            _ = try await apiService.rejectStagedMovie(movieId: movie.id, reason: reason)
            advanceSelection()
            removeMovieFromList(movie.id)
            selectedMovieIds.remove(movie.id)
            showToast("Rejected \"\(movie.title)\"")
            await loadStats()
        } catch {
            errorMessage = "Rejection failed: \(error.localizedDescription)"
            showToast("Rejection failed", isError: true)
        }
    }

    // MARK: - Bulk operations

    func approveSelected() async {
        let ids = Array(selectedMovieIds)
        guard !ids.isEmpty else { return }
        var succeeded = 0
        var failed = 0
        for id in ids {
            do {
                _ = try await apiService.approveStagedMovie(movieId: id)
                removeMovieFromList(id)
                succeeded += 1
            } catch {
                failed += 1
            }
        }
        selectedMovieIds.removeAll()
        showToast("Approved \(succeeded)\(failed > 0 ? ", \(failed) failed" : "")", isError: failed > 0)
        await loadStats()
    }

    func rejectSelected(reason: String) async {
        let ids = Array(selectedMovieIds)
        guard !ids.isEmpty else { return }
        var succeeded = 0
        var failed = 0
        for id in ids {
            do {
                _ = try await apiService.rejectStagedMovie(movieId: id, reason: reason)
                removeMovieFromList(id)
                succeeded += 1
            } catch {
                failed += 1
            }
        }
        selectedMovieIds.removeAll()
        showToast("Rejected \(succeeded)\(failed > 0 ? ", \(failed) failed" : "")", isError: failed > 0)
        await loadStats()
    }

    func batchEnrichSelected() async {
        let ids = Array(selectedMovieIds)
        guard !ids.isEmpty else { return }
        do {
            let start = try await apiService.batchEnrich(movieIds: ids, priority: enrichmentPriority)
            batchProgress = nil
            showBatchProgressSheet = true
            startPollingBatch(batchId: start.batchId)
        } catch {
            errorMessage = "Batch enrich failed: \(error.localizedDescription)"
            showToast("Batch enrich failed", isError: true)
        }
    }

    private func startPollingBatch(batchId: String) {
        batchPollTask?.cancel()
        batchPollTask = Task {
            while !Task.isCancelled {
                do {
                    let progress = try await apiService.getBatchEnrichmentProgress(batchId: batchId)
                    batchProgress = progress
                    if progress.status == "completed" || progress.status == "failed" {
                        break
                    }
                } catch {
                    // Keep polling briefly on transient errors.
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    // MARK: - Series / classification

    func toggleTvSeries(movie: StagedMovie, isTvSeries: Bool) async {
        do {
            let updated = try await apiService.updateStagedMovie(
                movieId: movie.id,
                updates: ["is_tv_series": isTvSeries]
            )
            replaceMovie(updated)
        } catch {
            errorMessage = "Failed to update TV series flag: \(error.localizedDescription)"
        }
    }

    func assignSeries(movie: StagedMovie, series: TvSeries?) async {
        do {
            let updated = try await apiService.assignTvSeriesToStagedMovie(
                movieId: movie.id,
                seriesId: series?.id
            )
            replaceMovie(updated)
        } catch {
            errorMessage = "Failed to assign series: \(error.localizedDescription)"
        }
    }

    func createAndAssignSeries(movie: StagedMovie) async {
        guard !newSeriesTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isCreatingSeries = true
        do {
            let created = try await apiService.createTvSeries(title: newSeriesTitle.trimmingCharacters(in: .whitespacesAndNewlines))
            tvSeriesList.append(created)
            newSeriesTitle = ""
            await assignSeries(movie: movie, series: created)
            showSeriesSheet = false
        } catch {
            errorMessage = "Failed to create series: \(error.localizedDescription)"
        }
        isCreatingSeries = false
    }

    func deleteMovie(_ movie: StagedMovie) async {
        do {
            try await apiService.deleteStagedMovie(movieId: movie.id)
            advanceSelection()
            removeMovieFromList(movie.id)
            selectedMovieIds.remove(movie.id)
            showToast("Deleted \"\(movie.title)\"")
            await loadStats()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func publishMovies() async {
        isLoading = true

        do {
            let result = try await apiService.publishStagedMovies()
            if result.failed > 0 {
                var message = "Published \(result.published), \(result.failed) failed"
                if let errors = result.errors, !errors.isEmpty {
                    let titles = errors.compactMap { $0.movieTitle }.prefix(3).joined(separator: ", ")
                    message += ": \(titles)"
                    if errors.count > 3 { message += " and \(errors.count - 3) more" }
                }
                errorMessage = message
                showToast("Published \(result.published), \(result.failed) failed", isError: true)
            } else {
                showToast("Published \(result.published) movie\(result.published == 1 ? "" : "s")")
            }

            await loadStats()
            await loadMovies(reset: true)
        } catch {
            errorMessage = "Publish failed: \(error.localizedDescription)"
            showToast("Publish failed", isError: true)
        }

        isLoading = false
    }

    // MARK: - List mutation helpers

    private func replaceMovie(_ updated: StagedMovie) {
        if let index = stagedMovies.firstIndex(where: { $0.id == updated.id }) {
            stagedMovies[index] = updated
        }
        if selectedMovie?.id == updated.id {
            selectedMovie = updated
        }
    }

    private func removeMovieFromList(_ id: String) {
        stagedMovies.removeAll { $0.id == id }
        totalCount = max(0, totalCount - 1)
        if selectedMovie?.id == id {
            selectedMovie = nil
        }
    }
}

// MARK: - Toast

struct ToastMessage: Equatable {
    let text: String
    let isError: Bool
}

struct ToastBannerView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(toast.text)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .font(.callout)
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(toast.isError ? Color.red : Color.green)
        .cornerRadius(10)
        .shadow(radius: 4)
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
    var isChecked: Bool = false
    var onToggleCheck: (() -> Void)? = nil
    var tvSeriesList: [TvSeries] = []
    var onDelete: (() -> Void)? = nil
    var onAssignSeries: (() -> Void)? = nil

    var assignedSeries: TvSeries? {
        guard let id = movie.tvSeriesId else { return nil }
        return tvSeriesList.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Multi-select checkbox
            Button(action: { onToggleCheck?() }) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Select for bulk actions")

            PosterImage(path: movie.posterPath, width: 40, height: 60, cornerRadius: 4, tmdbSize: "w92")

            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    StatusBadge(
                        text: movie.enrichmentStatus,
                        color: movie.hasEnrichment ? .green : .gray
                    )
                    StatusBadge(
                        text: movie.approvalStatus.rawValue.capitalized,
                        color: statusColor(movie.approvalStatus)
                    )
                    if movie.isTvSeries == true {
                        StatusBadge(text: "TV Series", color: .purple)
                    }
                    if let series = assignedSeries {
                        StatusBadge(text: series.title, color: .indigo)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: { onAssignSeries?() }) {
                    Image(systemName: assignedSeries != nil ? "tv.fill" : "tv")
                        .foregroundColor(assignedSeries != nil ? .indigo : .secondary)
                }
                .buttonStyle(.borderless)
                .help(assignedSeries != nil ? "Change TV Series" : "Assign to TV Series")

                Button(action: { onDelete?() }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
        }
        .padding(.vertical, 4)
    }

    func statusColor(_ status: ApprovalStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        case .publishing: return .blue
        case .published: return .gray
        }
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
    let onOpenYouTube: () -> Void
    let onToggleTvSeries: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with poster
                HStack(alignment: .top, spacing: 16) {
                    PosterImage(path: movie.posterPath, width: 150, height: 220, cornerRadius: 8, tmdbSize: "w300")

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

                        Button(action: onOpenYouTube) {
                            Label("Open on YouTube", systemImage: "play.rectangle.fill")
                        }
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
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
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Text("Preview")
                                }
                            }
                            .disabled(isPreviewingEnrichment || isApplyingEnrichment)

                            Button(action: { onApplyEnrichment(enrichmentPriority) }) {
                                if isApplyingEnrichment {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Text("Apply Enrichment")
                                }
                            }
                            .disabled(isPreviewingEnrichment || isApplyingEnrichment)
                            .buttonStyle(.borderedProminent)
                        }

                        if let preview = enrichmentPreview {
                            Divider()
                            EnrichmentCompareView(movie: movie, preview: preview)
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

                // Classification
                GroupBox("Classification") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { movie.isTvSeries ?? false },
                            set: { onToggleTvSeries($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TV Series")
                                    .font(.body)
                                Text("Mark this video as a TV series instead of a movie")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if movie.isTvShow == true {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text("OMDB also detected this as a TV show")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
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
        case .publishing: return .blue
        case .published: return .gray
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

// MARK: - Enrichment Compare (YouTube vs proposed match)

struct EnrichmentCompareView: View {
    let movie: StagedMovie
    let preview: EnrichmentPreview

    private func previewString(_ key: String) -> String? {
        preview.preview?[key]?.value as? String
    }

    private var proposedTitle: String? {
        previewString("title") ?? preview.metadata?.title
    }
    private var proposedPoster: String? { previewString("poster_path") }
    private var proposedDescription: String? { previewString("description") }
    private var proposedReleaseDate: String? { previewString("release_date") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Match Comparison")
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

            HStack(alignment: .top, spacing: 16) {
                // YouTube (current)
                VStack(alignment: .leading, spacing: 6) {
                    Text("YouTube")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AsyncImage(url: movie.youtubeThumbnailURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 160, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(movie.youtubeVideoTitle)
                        .font(.caption)
                        .lineLimit(3)
                        .frame(width: 160, alignment: .leading)
                }

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .padding(.top, 40)

                // Proposed match
                VStack(alignment: .leading, spacing: 6) {
                    Text("Proposed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    PosterImage(path: proposedPoster, width: 90, height: 135, cornerRadius: 6, tmdbSize: "w185")
                    Text(proposedTitle ?? "No match")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(3)
                        .frame(width: 160, alignment: .leading)
                    if let year = proposedReleaseDate?.prefix(4), !year.isEmpty {
                        Text(String(year))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let plot = proposedDescription, !plot.isEmpty {
                Text(plot)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }

            if let fieldsEnriched = preview.fieldsEnriched, !fieldsEnriched.isEmpty {
                Text("Fields: \(fieldsEnriched.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding(8)
        .background(Color.green.opacity(0.08))
        .cornerRadius(6)
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

// MARK: - Series Picker Sheet

struct SeriesPickerSheet: View {
    let movie: StagedMovie
    let seriesList: [TvSeries]
    @Binding var newSeriesTitle: String
    let isCreating: Bool
    let onSelect: (TvSeries) -> Void
    let onRemove: () -> Void
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Assign TV Series")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancel", action: onCancel)
            }
            .padding()

            Divider()

            Text("Movie: \(movie.title)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            if movie.tvSeriesId != nil {
                Button(action: onRemove) {
                    Label("Remove Series Assignment", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal)
                }
                .buttonStyle(.borderless)
                Divider().padding(.horizontal)
            }

            if seriesList.isEmpty {
                Text("No TV series yet. Create one below.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding()
            } else {
                List(seriesList) { series in
                    Button(action: { onSelect(series) }) {
                        HStack {
                            Image(systemName: movie.tvSeriesId == series.id ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(movie.tvSeriesId == series.id ? .indigo : .secondary)
                            Text(series.title)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxHeight: 250)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Create New Series")
                    .font(.headline)
                HStack {
                    TextField("Series title", text: $newSeriesTitle)
                        .textFieldStyle(.roundedBorder)
                    Button(action: onCreate) {
                        if isCreating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Text("Create & Assign")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newSeriesTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .padding()
        }
        .frame(width: 450)
    }
}

// MARK: - Reject Movie Sheet (single)

struct RejectMovieSheet: View {
    let movie: StagedMovie
    @Binding var reason: String
    let onReject: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Reject Movie")
                .font(.title2)
                .fontWeight(.bold)

            Text("Rejecting: \"\(movie.title)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Form {
                Section("Reason for rejection") {
                    TextEditor(text: $reason)
                        .frame(height: 100)
                        .border(Color.gray.opacity(0.2))
                }
            }
            .frame(height: 160)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Reject Movie", action: onReject)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding()
        .frame(width: 480)
    }
}

// MARK: - Bulk Reject Sheet

struct BulkRejectSheet: View {
    let count: Int
    @Binding var reason: String
    let onReject: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Reject \(count) Movie\(count == 1 ? "" : "s")")
                .font(.title2)
                .fontWeight(.bold)

            Text("A single reason will be applied to all selected movies.")
                .font(.caption)
                .foregroundColor(.secondary)

            Form {
                Section("Reason for rejection") {
                    TextEditor(text: $reason)
                        .frame(height: 100)
                        .border(Color.gray.opacity(0.2))
                }
            }
            .frame(height: 160)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Reject \(count)", action: onReject)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding()
        .frame(width: 480)
    }
}

// MARK: - Batch Progress Sheet

struct BatchProgressSheet: View {
    let progress: BatchEnrichmentProgress?
    let onClose: () -> Void

    private var isDone: Bool {
        progress?.status == "completed" || progress?.status == "failed"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Batch Enrichment")
                .font(.title2)
                .fontWeight(.bold)

            if let progress = progress {
                ProgressView(value: Double(progress.percentage ?? 0), total: 100) {
                    Text(progress.status.capitalized)
                } currentValueLabel: {
                    Text("\(progress.percentage ?? 0)%")
                }

                HStack(spacing: 20) {
                    StatBadge(title: "Enriched", value: progress.enriched, color: .green)
                    StatBadge(title: "Failed", value: progress.failed, color: .red)
                    StatBadge(title: "Skipped", value: progress.skipped, color: .gray)
                    StatBadge(title: "Total", value: progress.total, color: .blue)
                }

                if let current = progress.current {
                    Text(current)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            } else {
                ProgressView("Starting…")
            }

            Button(isDone ? "Done" : "Close", action: onClose)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 460)
    }
}
