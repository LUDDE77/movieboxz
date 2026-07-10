import SwiftUI

struct BulkImportView: View {
    let channel: ChannelWithPattern
    /// Called when the admin wants to review imported movies (switches to the Movies tab).
    var onReviewMovies: (() -> Void)? = nil

    @StateObject private var apiService = AdminAPIService()

    @State private var importMode = "limited"
    @State private var importLimit = "20"
    @State private var sortOrder = "latest"
    @State private var applySettings = true
    @State private var autoEnrich = false

    @State private var isImporting = false
    @State private var showProgressModal = false
    @State private var currentBatchId: String?
    @State private var importProgress: ImportProgress?
    @State private var error: String?
    @State private var progressTimer: Timer?
    @State private var isCancelling = false

    // YouTube quota awareness
    @State private var quota: QuotaInfo?

    /// Rough YouTube API cost of the configured import:
    /// 1 unit for the uploads-playlist lookup, then ~2 units per 50 videos
    /// (1 playlistItems.list page + 1 videos.list details page).
    var estimatedQuotaCost: Int {
        let videos: Int
        if importMode == "limited" {
            videos = Int(importLimit) ?? 0
        } else {
            // Full imports are capped server-side at 2000 fetched videos.
            videos = min(channel.videoCount ?? 500, 2000)
        }
        guard videos > 0 else { return 0 }
        let pages = (videos + 49) / 50
        return 1 + pages * 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bulk Import")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Import multiple videos from the channel at once")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                // Quota Awareness
                GroupBox(label: Label("YouTube API Quota", systemImage: "gauge.with.needle")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let quota = quota {
                            HStack(spacing: 16) {
                                Text("Used today: \(quota.used) / \(quota.budget)")
                                Text("Remaining: \(quota.remaining)")
                                    .fontWeight(.semibold)
                                    .foregroundColor(quotaColor(quota))
                                Spacer()
                                Button {
                                    Task { await loadQuota() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .help("Refresh quota")
                            }
                            .font(.subheadline)

                            ProgressView(value: Double(min(quota.used, quota.budget)), total: Double(max(quota.budget, 1)))
                                .tint(quotaColor(quota))
                        } else {
                            Text("Quota usage unavailable")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "sum")
                                .font(.caption)
                            Text("Estimated cost of this import: ~\(estimatedQuotaCost) units")
                                .font(.caption)
                        }
                        .foregroundColor(estimateExceedsRemaining ? .red : .secondary)

                        if estimateExceedsRemaining {
                            Text("This import may exceed the remaining daily quota.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                }

                // Import Mode Selection
                GroupBox(label: Label("Import Mode", systemImage: "arrow.down.circle")) {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Mode", selection: $importMode) {
                            Text("Limited (specify count)").tag("limited")
                            Text("All videos from channel").tag("all")
                        }
                        .pickerStyle(.radioGroup)

                        if importMode == "limited" {
                            HStack {
                                Text("Number of videos:")
                                    .frame(width: 150, alignment: .leading)
                                TextField("20", text: $importLimit)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                Text("videos")
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack {
                            Text("Sort order:")
                                .frame(width: 150, alignment: .leading)
                            Picker("", selection: $sortOrder) {
                                ForEach(ImportSortOrder.allCases, id: \.rawValue) { order in
                                    Text(order.displayName).tag(order.rawValue)
                                }
                            }
                            .frame(width: 300)
                        }
                    }
                    .padding()
                }

                // Import Options
                GroupBox(label: Label("Import Options", systemImage: "gear")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Apply channel settings automatically", isOn: $applySettings)
                            .help("Apply default channel tags, duration filters, and configurations to imported movies")

                        Toggle("Auto-enrich after import", isOn: $autoEnrich)
                            .help("Automatically enrich movies with metadata after importing")

                        if applySettings {
                            Text("Duration filters from channel settings will be applied during import.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }

                // Quick Action Buttons
                GroupBox(label: Label("Quick Actions", systemImage: "bolt.fill")) {
                    HStack(spacing: 12) {
                        Button(action: { startImportLatest() }) {
                            VStack {
                                Label("Import Latest", systemImage: "arrow.down.to.line")
                                    .font(.headline)
                                Text("Newest 20 — cheap incremental")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Cheapest option: imports only the latest 20 uploads (~2 quota units). Already-imported videos are skipped.")

                        Button(action: { quickImport(limit: 10) }) {
                            VStack {
                                Text("Last 10")
                                    .font(.headline)
                                Text("Latest 10 videos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.bordered)

                        Button(action: { quickImport(limit: 50) }) {
                            VStack {
                                Text("Last 50")
                                    .font(.headline)
                                Text("Latest 50 videos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.bordered)

                        Button(action: { quickImport(limit: nil) }) {
                            VStack {
                                Text("All New")
                                    .font(.headline)
                                Text("All channel videos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .disabled(isImporting)
                }

                // Error Message
                if let error = error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                // Start Import Button
                HStack {
                    Spacer()
                    Button(action: startImport) {
                        if isImporting {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Starting import...")
                            }
                        } else {
                            Label("Start Import", systemImage: "play.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isImporting || (importMode == "limited" && importLimit.isEmpty))
                    Spacer()
                }
                .padding(.top)
            }
            .padding()
        }
        .sheet(isPresented: $showProgressModal) {
            ImportProgressModal(
                progress: importProgress,
                isCancelling: isCancelling,
                onCancel: cancelImport,
                onClose: {
                    showProgressModal = false
                    Task { await loadQuota() }
                },
                onReviewMovies: {
                    showProgressModal = false
                    onReviewMovies?()
                }
            )
        }
        .task {
            await loadQuota()
        }
        .onDisappear {
            // Prevent the polling timer from leaking when the tab/channel changes.
            stopProgressPolling()
        }
    }

    // MARK: - Quota

    var estimateExceedsRemaining: Bool {
        guard let quota = quota else { return false }
        return estimatedQuotaCost > quota.remaining
    }

    func quotaColor(_ quota: QuotaInfo) -> Color {
        let fraction = Double(quota.remaining) / Double(max(quota.budget, 1))
        if fraction > 0.5 { return .green }
        if fraction > 0.15 { return .orange }
        return .red
    }

    func loadQuota() async {
        do {
            quota = try await apiService.getQuota()
        } catch {
            print("Failed to load quota: \(error)")
        }
    }

    // MARK: - Actions

    func quickImport(limit: Int?) {
        importMode = limit == nil ? "all" : "limited"
        importLimit = limit.map(String.init) ?? ""
        sortOrder = "latest"
        startImport()
    }

    /// Cheap incremental import: latest 20 uploads only (~2 quota units).
    func startImportLatest() {
        Task {
            isImporting = true
            error = nil
            isCancelling = false

            do {
                let response = try await apiService.importLatest(
                    channelId: channel.id,
                    limit: 20,
                    sortOrder: "latest",
                    applySettings: applySettings
                )

                currentBatchId = response.batchId
                importProgress = nil
                showProgressModal = true
                startProgressPolling()
            } catch {
                self.error = "Failed to start import: \(error.localizedDescription)"
            }

            isImporting = false
        }
    }

    func startImport() {
        Task {
            isImporting = true
            error = nil
            isCancelling = false

            do {
                let limit = importMode == "all" ? nil : Int(importLimit)

                let request = BulkImportRequest(
                    limit: limit,
                    sortOrder: sortOrder,
                    applySettings: applySettings,
                    autoEnrich: autoEnrich ? true : nil
                )

                let response = try await apiService.importAllVideos(
                    channelId: channel.id,
                    request: request
                )

                currentBatchId = response.batchId
                importProgress = nil
                showProgressModal = true

                // Start polling for progress
                startProgressPolling()
            } catch {
                self.error = "Failed to start import: \(error.localizedDescription)"
            }

            isImporting = false
        }
    }

    func startProgressPolling() {
        guard let batchId = currentBatchId else { return }

        // Initial fetch
        Task {
            await fetchProgress(batchId: batchId)
        }

        // Poll every 2 seconds
        progressTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                await fetchProgress(batchId: batchId)
            }
        }
    }

    func fetchProgress(batchId: String) async {
        do {
            let progress = try await apiService.getImportProgress(batchId: batchId)
            importProgress = progress

            // Stop polling if completed, failed, or cancelled
            if progress.status == "completed" || progress.status == "failed" || progress.status == "cancelled" {
                stopProgressPolling()
                isCancelling = false
            }
        } catch {
            print("Failed to fetch progress: \(error)")
        }
    }

    func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Real server-side cancel: POSTs the cancel endpoint, then keeps polling
    /// until the backend reports the import as cancelled.
    func cancelImport() {
        guard let batchId = currentBatchId, !isCancelling else { return }

        isCancelling = true
        Task {
            do {
                _ = try await apiService.cancelImport(batchId: batchId)
                // Keep polling — the import loop notices the cancellation and
                // finalizes; fetchProgress flips the modal to "cancelled".
                if progressTimer == nil {
                    startProgressPolling()
                }
            } catch {
                isCancelling = false
                self.error = "Failed to cancel import: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Import Progress Modal

struct ImportProgressModal: View {
    let progress: ImportProgress?
    var isCancelling: Bool = false
    let onCancel: () -> Void
    let onClose: () -> Void
    var onReviewMovies: (() -> Void)? = nil

    /// Pattern match percentage of the imported videos, when reported.
    private var patternMatchInfo: (matched: Int, imported: Int, percent: Int)? {
        guard let progress = progress,
              let matched = progress.patternMatchCount,
              progress.imported > 0 else { return nil }
        let percent = Int((Double(matched) / Double(progress.imported)) * 100)
        return (matched, progress.imported, percent)
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: statusIcon)
                    .font(.largeTitle)
                    .foregroundColor(statusColor)
                Text("Importing Videos")
                    .font(.title)
                    .fontWeight(.bold)
            }

            if let progress = progress {
                // Channel info
                if let channelTitle = progress.channelTitle {
                    Text(channelTitle)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                // Progress bar
                if let percentage = progress.percentage {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(percentage), total: 100.0)
                            .frame(width: 400)

                        Text("\(percentage)%")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                }

                // Current video
                if let currentTitle = progress.current {
                    VStack(spacing: 4) {
                        Text("Current video:")
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
                        StatItem(label: "Found", value: "\(progress.found)", color: .blue)
                        StatItem(label: "Imported", value: "\(progress.imported)", color: .green)
                        StatItem(label: "Skipped", value: "\(progress.skipped)", color: .orange)
                        StatItem(label: "Failed", value: "\(progress.failed)", color: .red)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Status-specific actions
                if progress.status == "completed" {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Import completed successfully!")
                                .fontWeight(.semibold)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)

                        // Pattern match rate summary
                        if let match = patternMatchInfo {
                            VStack(spacing: 6) {
                                HStack {
                                    Image(systemName: match.percent < 50 ? "exclamationmark.triangle.fill" : "doc.text.magnifyingglass")
                                        .foregroundColor(match.percent < 50 ? (match.percent < 25 ? .red : .orange) : .green)
                                    Text("Pattern matched \(match.matched) of \(match.imported) imported (\(match.percent)%)")
                                        .fontWeight(.medium)
                                }
                                if match.percent < 50 {
                                    Text("Low match rate — titles may not be parsed correctly. Review the pattern in the Pattern tab.")
                                        .font(.caption)
                                        .foregroundColor(match.percent < 25 ? .red : .orange)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background((match.percent < 50 ? (match.percent < 25 ? Color.red : Color.orange) : Color.green).opacity(0.1))
                            .cornerRadius(8)
                        }

                        // Truncation warning
                        if progress.truncated == true {
                            HStack {
                                Image(systemName: "scissors")
                                    .foregroundColor(.orange)
                                Text("Import stopped at safety cap — channel has more videos")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }

                        HStack(spacing: 12) {
                            if onReviewMovies != nil {
                                Button {
                                    onReviewMovies?()
                                } label: {
                                    Label("Review Imported Movies", systemImage: "film")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }

                            Button("Close") {
                                onClose()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                } else if progress.status == "failed" {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Import failed")
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
                } else if progress.status == "cancelled" {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.orange)
                        Text("Import cancelled")
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)

                    Button("Close") {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if isCancelling {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Cancelling — waiting for the server to stop the import…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Cancel Import") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ProgressView("Initializing import...")
            }
        }
        .padding(40)
        .frame(width: 600)
    }

    var statusIcon: String {
        guard let progress = progress else { return "arrow.down.circle" }
        switch progress.status {
        case "completed": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        case "cancelled": return "stop.circle.fill"
        default: return "arrow.down.circle"
        }
    }

    var statusColor: Color {
        guard let progress = progress else { return .blue }
        switch progress.status {
        case "completed": return .green
        case "failed": return .red
        case "cancelled": return .orange
        default: return .blue
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    BulkImportView(
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
            hasMovies: true,
            hasSeries: false,
            hasKidsContent: false,
            patternSource: "title",
            createdAt: "",
            updatedAt: nil
        )
    )
}
