import SwiftUI

struct BulkImportView: View {
    let channel: ChannelWithPattern
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
                            .help("Apply default channel tags and configurations to imported movies")

                        Toggle("Auto-enrich after import", isOn: $autoEnrich)
                            .help("Automatically enrich movies with metadata after importing")
                    }
                    .padding()
                }

                // Quick Action Buttons
                GroupBox(label: Label("Quick Actions", systemImage: "bolt.fill")) {
                    HStack(spacing: 12) {
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
                onCancel: cancelImport,
                onClose: { showProgressModal = false }
            )
        }
    }

    // MARK: - Actions

    func quickImport(limit: Int?) {
        importMode = limit == nil ? "all" : "limited"
        importLimit = limit.map(String.init) ?? ""
        sortOrder = "latest"
        startImport()
    }

    func startImport() {
        Task {
            isImporting = true
            error = nil

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
            }
        } catch {
            print("Failed to fetch progress: \(error)")
        }
    }

    func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func cancelImport() {
        // TODO: Implement cancel endpoint if needed
        stopProgressPolling()
        showProgressModal = false
    }
}

// MARK: - Import Progress Modal

struct ImportProgressModal: View {
    let progress: ImportProgress?
    let onCancel: () -> Void
    let onClose: () -> Void

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
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Import completed successfully!")
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
            createdAt: "",
            updatedAt: nil
        )
    )
}
