import SwiftUI

// MARK: - Verification Queue (manual enrichment queue)
//
// Master list of movies that failed automatic enrichment. Admins review the
// YouTube metadata + proposed candidates and either match to an IMDB ID,
// skip, or delete the entry.
//
// Keyboard: ↑/↓ or j/k to navigate the list, S to skip the selected item.

struct VerificationQueueView: View {
    @StateObject private var apiService = AdminAPIService()

    // Data
    @State private var items: [EnrichmentQueueItem] = []
    @State private var stats: EnrichmentQueueStats?
    @State private var channels: [ChannelWithPattern] = []
    @State private var total = 0

    // Filters + paging
    @State private var selectedStatus = "pending"
    @State private var selectedChannelId = ""
    @State private var offset = 0
    private let pageSize = 50

    // Selection + state
    @State private var selectedItemId: String?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isActing = false

    // Action inputs
    @State private var manualImdbId = ""
    @State private var skipNote = ""
    @State private var showDeleteConfirm = false

    // Toast
    @State private var toast: ToastMessage?
    @State private var toastDismissTask: Task<Void, Never>?

    private let statusOptions = ["pending", "in_progress", "matched", "skipped"]

    private var selectedItem: EnrichmentQueueItem? {
        items.first { $0.id == selectedItemId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HSplitView {
                listPanel
                    .frame(minWidth: 300, maxWidth: 420)

                detailPanel
                    .frame(minWidth: 480)
            }
        }
        .navigationTitle("Verification Queue")
        .overlay(alignment: .top) {
            if let toast = toast {
                ToastBannerView(toast: toast) { self.toast = nil }
                    .padding(.top, 8)
            }
        }
        .task {
            await loadChannels()
            await loadQueue()
        }
        .confirmationDialog(
            "Delete this queue entry?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The entry \"\(selectedItem?.youtubeVideoTitle ?? "")\" will be removed from the queue. This cannot be undone.")
        }
    }

    // MARK: - Header (stats + filters)

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                if let stats = stats {
                    StatBadge(title: "Total", value: stats.total, color: .blue)
                    StatBadge(title: "Pending", value: stats.pending, color: .orange)
                    StatBadge(title: "In Progress", value: stats.inProgress, color: .yellow)
                    StatBadge(title: "Matched", value: stats.matched, color: .green)
                    StatBadge(title: "Skipped", value: stats.skipped, color: .gray)
                } else {
                    Text("Loading stats…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    Task { await loadQueue() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            HStack(spacing: 12) {
                Picker("Status", selection: $selectedStatus) {
                    ForEach(statusOptions, id: \.self) { status in
                        Text(status.replacingOccurrences(of: "_", with: " ").capitalized).tag(status)
                    }
                }
                .frame(maxWidth: 220)
                .onChange(of: selectedStatus) { _, _ in
                    offset = 0
                    Task { await loadQueue() }
                }

                Picker("Channel", selection: $selectedChannelId) {
                    Text("All Channels").tag("")
                    ForEach(channels) { channel in
                        Text(channel.title).tag(channel.id)
                    }
                }
                .frame(maxWidth: 280)
                .onChange(of: selectedChannelId) { _, _ in
                    offset = 0
                    Task { await loadQueue() }
                }

                Spacer()

                // Pagination
                HStack(spacing: 8) {
                    Button {
                        offset = max(0, offset - pageSize)
                        Task { await loadQueue() }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(offset == 0 || isLoading)

                    Text(paginationLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()

                    Button {
                        offset += pageSize
                        Task { await loadQueue() }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(offset + pageSize >= total || isLoading)
                }
            }
        }
        .padding(12)
    }

    private var paginationLabel: String {
        guard total > 0 else { return "0 items" }
        let from = offset + 1
        let to = min(offset + items.count, total)
        return "\(from)–\(to) of \(total)"
    }

    // MARK: - List Panel

    private var listPanel: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Loading queue…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError = loadError {
                VStack(spacing: 8) {
                    Text("Failed to load queue")
                        .font(.headline)
                    Text(loadError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") { Task { await loadQueue() } }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text("Queue is empty")
                        .font(.headline)
                    Text("No \(selectedStatus.replacingOccurrences(of: "_", with: " ")) items\(selectedChannelId.isEmpty ? "" : " for this channel").")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedItemId) {
                    ForEach(items) { item in
                        queueRow(item)
                            .tag(item.id)
                    }
                }
                .listStyle(.inset)
                .onKeyPress(characters: CharacterSet(charactersIn: "jksJKS")) { press in
                    switch press.characters.lowercased() {
                    case "j":
                        moveSelection(by: 1)
                        return .handled
                    case "k":
                        moveSelection(by: -1)
                        return .handled
                    case "s":
                        if selectedItem != nil, !isActing {
                            Task { await skipSelected() }
                        }
                        return .handled
                    default:
                        return .ignored
                    }
                }
            }
        }
    }

    private func queueRow(_ item: EnrichmentQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.extractedTitle ?? item.youtubeVideoTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            HStack(spacing: 6) {
                if let channelTitle = item.channelTitle {
                    Text(channelTitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let confidence = item.confidence {
                    StatusBadge(text: "\(Int(confidence))%", color: confidenceColor(confidence))
                }
                StatusBadge(text: item.enrichmentStatus, color: statusColor(item.enrichmentStatus))
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if let item = selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 20) {
                            metadataColumn(item)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Divider()

                            candidatesColumn(item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()

                        actionsSection(item)
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a queue item to review")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Use ↑/↓ or J/K to navigate, S to skip.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func metadataColumn(_ item: EnrichmentQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YouTube Video")
                .font(.headline)

            AsyncImage(url: item.youtubeThumbnailURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    ZStack {
                        Color.gray.opacity(0.15)
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: 320, maxHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.youtubeVideoTitle)
                .font(.subheadline)
                .fontWeight(.semibold)
                .textSelection(.enabled)

            if let url = item.youtubeURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open on YouTube", systemImage: "play.rectangle")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }

            Divider()

            Text("Extracted Metadata")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Title", value: item.extractedTitle ?? "—", showColon: true)
                DetailRow(label: "Actors", value: (item.extractedActors?.isEmpty == false) ? item.extractedActors!.joined(separator: ", ") : "—", showColon: true)
                DetailRow(label: "Genre", value: item.extractedGenre ?? "—", showColon: true)
                DetailRow(label: "Year", value: item.extractedYear.map(String.init) ?? "—", showColon: true)
                DetailRow(label: "Duration", value: item.durationMinutes.map { "\($0) min" } ?? "—", showColon: true)
                DetailRow(label: "Published", value: formatDate(item.publishedAt), showColon: true)
                DetailRow(label: "Channel", value: item.channelTitle ?? "—", showColon: true)
            }

            Divider()

            Text("Why Queued")
                .font(.headline)

            HStack(spacing: 8) {
                if let confidence = item.confidence {
                    StatusBadge(text: "Confidence \(Int(confidence))%", color: confidenceColor(confidence))
                }
                StatusBadge(text: item.enrichmentStatus, color: statusColor(item.enrichmentStatus))
            }

            Text(item.reason ?? "No reason recorded")
                .font(.caption)
                .foregroundColor(.secondary)

            if let notes = item.manualNotes, !notes.isEmpty {
                Text("Notes: \(notes)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let matchedImdb = item.manualImdbId, !matchedImdb.isEmpty {
                DetailRow(label: "Matched IMDB", value: matchedImdb, labelWidth: 100, showColon: true)
            }
        }
    }

    private func candidatesColumn(_ item: EnrichmentQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Candidates")
                .font(.headline)

            if let candidates = item.candidates, !candidates.isEmpty {
                ForEach(candidates) { candidate in
                    candidateCard(candidate)
                }
            } else {
                Text("No candidates were proposed for this video.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            }
        }
    }

    private func candidateCard(_ candidate: EnrichmentCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PosterImage(path: candidate.posterPath, width: 46, height: 69)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.title ?? "Untitled")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let year = candidate.releaseYear {
                        Text(year)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let source = candidate.source {
                        StatusBadge(text: source.uppercased(), color: .blue)
                    }
                }

                HStack(spacing: 8) {
                    if let imdbId = candidate.imdbId {
                        Text(imdbId)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    if let tmdbId = candidate.tmdbId {
                        Text("TMDB \(tmdbId)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button("Match") {
                if let imdbId = candidate.imdbId {
                    Task { await matchSelected(imdbId: imdbId) }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(candidate.imdbId == nil || candidate.imdbId?.isEmpty == true || isActing)
            .help(candidate.imdbId == nil ? "Candidate has no IMDB ID — use the manual field below" : "Match with \(candidate.imdbId ?? "")")
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func actionsSection(_ item: EnrichmentQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Manual IMDB ID (e.g. tt1234567)", text: $manualImdbId)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                Button {
                    let id = manualImdbId.trimmingCharacters(in: .whitespaces)
                    Task { await matchSelected(imdbId: id) }
                } label: {
                    Label("Match", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidImdbInput || isActing)
            }

            HStack(spacing: 8) {
                TextField("Skip note (optional)", text: $skipNote)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                Button {
                    Task { await skipSelected() }
                } label: {
                    Label("Skip", systemImage: "arrow.right.to.line")
                }
                .disabled(isActing)

                Spacer()

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(isActing)
            }

            if isActing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Working…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var isValidImdbInput: Bool {
        let trimmed = manualImdbId.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("tt") && trimmed.count >= 7
    }

    // MARK: - Actions

    private func matchSelected(imdbId: String) async {
        guard let item = selectedItem, !imdbId.isEmpty else { return }
        isActing = true
        do {
            let message = try await apiService.matchEnrichmentQueueItem(queueId: item.id, imdbId: imdbId)
            showToast(message ?? "Matched \(imdbId)")
            manualImdbId = ""
            await refreshAndAdvance(afterActingOn: item.id)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
        isActing = false
    }

    private func skipSelected() async {
        guard let item = selectedItem else { return }
        isActing = true
        do {
            let note = skipNote.trimmingCharacters(in: .whitespaces)
            let message = try await apiService.skipEnrichmentQueueItem(queueId: item.id, reason: note.isEmpty ? nil : note)
            showToast(message ?? "Skipped")
            skipNote = ""
            await refreshAndAdvance(afterActingOn: item.id)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
        isActing = false
    }

    private func deleteSelected() async {
        guard let item = selectedItem else { return }
        isActing = true
        do {
            let message = try await apiService.deleteEnrichmentQueueItem(queueId: item.id)
            showToast(message ?? "Deleted queue entry")
            await refreshAndAdvance(afterActingOn: item.id)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
        isActing = false
    }

    /// Reload the queue and select the next pending item after the one just acted on.
    private func refreshAndAdvance(afterActingOn actedId: String) async {
        let previousIndex = items.firstIndex { $0.id == actedId } ?? 0
        await loadQueue(preserveSelection: false)

        guard !items.isEmpty else {
            selectedItemId = nil
            return
        }

        // Prefer the next pending item at/after the old position, then any pending,
        // then just the row at the old position.
        let fromIndex = min(previousIndex, items.count - 1)
        if let next = items[fromIndex...].first(where: { $0.enrichmentStatus == "pending" }) {
            selectedItemId = next.id
        } else if let anyPending = items.first(where: { $0.enrichmentStatus == "pending" }) {
            selectedItemId = anyPending.id
        } else {
            selectedItemId = items[fromIndex].id
        }
    }

    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        guard let currentId = selectedItemId,
              let index = items.firstIndex(where: { $0.id == currentId }) else {
            selectedItemId = items.first?.id
            return
        }
        let newIndex = min(max(index + delta, 0), items.count - 1)
        selectedItemId = items[newIndex].id
    }

    // MARK: - Data Loading

    private func loadQueue(preserveSelection: Bool = true) async {
        isLoading = true
        loadError = nil
        let previousSelection = selectedItemId

        do {
            async let statsTask = apiService.getEnrichmentQueueStats(
                channelId: selectedChannelId.isEmpty ? nil : selectedChannelId
            )
            let data = try await apiService.getEnrichmentQueue(
                status: selectedStatus,
                channelId: selectedChannelId.isEmpty ? nil : selectedChannelId,
                limit: pageSize,
                offset: offset
            )
            items = data.items
            total = data.total ?? data.items.count
            stats = try? await statsTask

            if preserveSelection, let previousSelection,
               items.contains(where: { $0.id == previousSelection }) {
                selectedItemId = previousSelection
            } else if preserveSelection {
                selectedItemId = items.first?.id
            }
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    private func loadChannels() async {
        do {
            let data = try await apiService.getChannelsWithPatterns()
            channels = data.channels.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        } catch {
            // Channel filter is optional — the queue still works without it.
        }
    }

    // MARK: - Helpers

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 85...: return .green
        case 70..<85: return .orange
        default: return .red
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pending": return .orange
        case "in_progress": return .yellow
        case "matched": return .green
        case "skipped": return .gray
        default: return .secondary
        }
    }

    private func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "—" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: dateString) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateString)
        }()
        guard let date else { return dateString }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none
        return display.string(from: date)
    }

    private func showToast(_ message: String, isError: Bool = false) {
        toastDismissTask?.cancel()
        withAnimation { toast = ToastMessage(text: message, isError: isError) }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                withAnimation { toast = nil }
            }
        }
    }
}

#Preview {
    VerificationQueueView()
}
