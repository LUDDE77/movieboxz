import SwiftUI

// MARK: - Duplicate Manager
//
// Lists production duplicate groups (same imdb_id, or same series/season/episode)
// and lets the admin pick which movie to KEEP; the rest are deleted via
// POST /api/admin/duplicates/resolve.

struct DuplicateManagerView: View {
    @StateObject private var apiService = AdminAPIService()

    @State private var groups: [DuplicateGroup] = []
    @State private var selectedGroupId: String?
    @State private var keepId: String?

    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isResolving = false
    @State private var showResolveConfirm = false

    @State private var toast: ToastMessage?
    @State private var toastDismissTask: Task<Void, Never>?

    private var selectedGroup: DuplicateGroup? {
        groups.first { $0.id == selectedGroupId }
    }

    private var moviesToDelete: [DuplicateMovie] {
        guard let group = selectedGroup, let keepId else { return [] }
        return group.movies.filter { $0.id != keepId }
    }

    var body: some View {
        HSplitView {
            groupListPanel
                .frame(minWidth: 300, maxWidth: 420)

            groupDetailPanel
                .frame(minWidth: 480)
        }
        .navigationTitle("Duplicates")
        .overlay(alignment: .top) {
            if let toast = toast {
                ToastBannerView(toast: toast) { self.toast = nil }
                    .padding(.top, 8)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadGroups() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task {
            await loadGroups()
        }
        .onChange(of: selectedGroupId) { _, _ in
            applyDefaultKeepSelection()
        }
        .confirmationDialog(
            "Resolve duplicate group?",
            isPresented: $showResolveConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(moviesToDelete.count) duplicate\(moviesToDelete.count == 1 ? "" : "s")", role: .destructive) {
                Task { await resolveSelectedGroup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resolveConfirmationMessage)
        }
    }

    private var resolveConfirmationMessage: String {
        guard let group = selectedGroup, let keepId,
              let keeper = group.movies.first(where: { $0.id == keepId }) else {
            return ""
        }
        let deleteList = moviesToDelete
            .map { "• \($0.title) (\($0.channelTitle ?? "unknown channel"))" }
            .joined(separator: "\n")
        return "KEEP: \(keeper.title) (\(keeper.channelTitle ?? "unknown channel"))\n\nDELETE permanently:\n\(deleteList)"
    }

    // MARK: - Group List

    private var groupListPanel: some View {
        Group {
            if isLoading && groups.isEmpty {
                ProgressView("Scanning for duplicates…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError = loadError {
                VStack(spacing: 8) {
                    Text("Failed to load duplicates")
                        .font(.headline)
                    Text(loadError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") { Task { await loadGroups() } }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text("No duplicates found")
                        .font(.headline)
                    Text("Production movies are clean — no shared IMDB IDs or episode triples.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(groups.count) duplicate group\(groups.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()

                    List(selection: $selectedGroupId) {
                        ForEach(groups) { group in
                            groupRow(group)
                                .tag(group.id)
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
    }

    private func groupRow(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StatusBadge(
                    text: group.type.uppercased(),
                    color: group.type == "imdb" ? .blue : .purple
                )
                Text(group.movies.first?.title ?? group.key)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            HStack {
                Text(group.key)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(group.movies.count) copies")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Group Detail

    private var groupDetailPanel: some View {
        Group {
            if let group = selectedGroup {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            StatusBadge(
                                text: group.type == "imdb" ? "SAME IMDB ID" : "SAME EPISODE",
                                color: group.type == "imdb" ? .blue : .purple
                            )
                            Text(group.key)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                            Spacer()
                        }

                        Text("Select the copy to KEEP — all others will be deleted from production.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(group.movies) { movie in
                            memberCard(movie)
                        }

                        Divider()

                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                showResolveConfirm = true
                            } label: {
                                if isResolving {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 180)
                                } else {
                                    Label("Resolve group — delete \(moviesToDelete.count)", systemImage: "trash")
                                        .frame(minWidth: 180)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(keepId == nil || moviesToDelete.isEmpty || isResolving)
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a duplicate group")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Pick which copy to keep; the rest are deleted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func memberCard(_ movie: DuplicateMovie) -> some View {
        let isKeeper = movie.id == keepId

        return HStack(alignment: .top, spacing: 12) {
            // Radio selection
            Button {
                keepId = movie.id
            } label: {
                Image(systemName: isKeeper ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundColor(isKeeper ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Keep this copy")

            PosterImage(path: movie.posterPath, width: 60, height: 90)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(movie.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    if isKeeper {
                        StatusBadge(text: "KEEP", color: .green)
                    } else {
                        StatusBadge(text: "DELETE", color: .red)
                    }
                }

                HStack(spacing: 8) {
                    if let channel = movie.channelTitle {
                        Label(channel, systemImage: "tv")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let views = movie.viewCount {
                        Label(formatViews(views), systemImage: "eye")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    StatusBadge(
                        text: (movie.isAvailable ?? false) ? "Available" : "Unavailable",
                        color: (movie.isAvailable ?? false) ? .green : .red
                    )
                    if let season = movie.seasonNumber, let episode = movie.episodeNumber {
                        Text("S\(season)E\(episode)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("Added \(formatDate(movie.createdAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let url = movie.youtubeURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("YouTube", systemImage: "play.rectangle.fill")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .help("Open the video in your browser")
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isKeeper ? Color.green.opacity(0.6) : Color.clear, lineWidth: 2)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { keepId = movie.id }
    }

    // MARK: - Actions

    private func resolveSelectedGroup() async {
        guard let group = selectedGroup, let keepId else { return }
        let deleteIds = moviesToDelete.map(\.id)
        guard !deleteIds.isEmpty else { return }

        isResolving = true
        do {
            let result = try await apiService.resolveDuplicateGroup(keepId: keepId, deleteIds: deleteIds)
            groups.removeAll { $0.id == group.id }
            selectedGroupId = nil
            self.keepId = nil
            showToast(result.message ?? "Deleted \(result.deleted) duplicate\(result.deleted == 1 ? "" : "s")")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
        isResolving = false
    }

    // MARK: - Data

    private func loadGroups() async {
        isLoading = true
        loadError = nil
        do {
            let data = try await apiService.getDuplicateGroups()
            groups = data.groups
            if let selectedGroupId, !groups.contains(where: { $0.id == selectedGroupId }) {
                self.selectedGroupId = nil
                keepId = nil
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    /// Default keeper: the available copy with the highest view count
    /// (falling back to highest view count overall).
    private func applyDefaultKeepSelection() {
        guard let group = selectedGroup else {
            keepId = nil
            return
        }
        let available = group.movies.filter { $0.isAvailable ?? false }
        let pool = available.isEmpty ? group.movies : available
        keepId = pool.max(by: { ($0.viewCount ?? 0) < ($1.viewCount ?? 0) })?.id
    }

    // MARK: - Helpers

    private func formatViews(_ views: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: views)) ?? "\(views)") views"
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
        display.dateStyle = .short
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
    DuplicateManagerView()
}
