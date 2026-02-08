import SwiftUI

struct ImportHistoryView: View {
    let channel: ChannelWithPattern
    @StateObject private var apiService = AdminAPIService()

    @State private var imports: [ImportHistory] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedImport: ImportHistory?
    @State private var showDetailsSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import History")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button(action: loadHistory) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .padding()
            .background(Color.gray.opacity(0.05))

            Divider()

            if isLoading && imports.isEmpty {
                ProgressView("Loading import history...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if imports.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No import history")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Import videos to see history here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Import list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(imports) { importRecord in
                            ImportHistoryRow(
                                importRecord: importRecord,
                                onViewDetails: {
                                    selectedImport = importRecord
                                    showDetailsSheet = true
                                },
                                onRerun: {
                                    rerunImport(importRecord)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showDetailsSheet) {
            if let importRecord = selectedImport {
                ImportDetailsSheet(importRecord: importRecord)
            }
        }
        .task {
            await loadHistory()
        }
    }

    // MARK: - Actions

    func loadHistory() async {
        isLoading = true
        error = nil

        do {
            let data = try await apiService.getImportHistory(channelId: channel.id, limit: 50)
            imports = data.imports
        } catch {
            self.error = "Failed to load import history: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func rerunImport(_ importRecord: ImportHistory) {
        Task {
            do {
                let request = BulkImportRequest(
                    limit: importRecord.importLimit,
                    sortOrder: importRecord.sortOrder ?? "latest",
                    applySettings: true,
                    autoEnrich: nil
                )

                _ = try await apiService.importAllVideos(
                    channelId: channel.id,
                    request: request
                )

                // Reload history after a short delay
                try await Task.sleep(nanoseconds: 1_000_000_000)
                await loadHistory()
            } catch {
                self.error = "Failed to re-run import: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Import History Row

struct ImportHistoryRow: View {
    let importRecord: ImportHistory
    let onViewDetails: () -> Void
    let onRerun: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Status icon
            Image(systemName: statusIcon)
                .font(.title)
                .foregroundColor(statusColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                // Import type and date
                HStack {
                    Text(importTypeLabel)
                        .font(.headline)

                    Spacer()

                    Text(formatDate(importRecord.startedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Stats
                HStack(spacing: 20) {
                    StatLabel(label: "Found", value: "\(importRecord.videosFound)", color: .blue)
                    StatLabel(label: "Imported", value: "\(importRecord.videosImported)", color: .green)

                    if importRecord.videosSkipped > 0 {
                        StatLabel(label: "Skipped", value: "\(importRecord.videosSkipped)", color: .orange)
                    }

                    if importRecord.videosFailed > 0 {
                        StatLabel(label: "Failed", value: "\(importRecord.videosFailed)", color: .red)
                    }

                    Spacer()

                    if let duration = importRecord.formattedDuration {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text(duration)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                // Sort order
                if let sortOrder = importRecord.sortOrder {
                    Text("Sort: \(ImportSortOrder(rawValue: sortOrder)?.displayName ?? sortOrder)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Error message
                if let error = importRecord.errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundColor(.red)
                }
            }

            // Actions
            VStack(spacing: 8) {
                Button(action: onViewDetails) {
                    Label("Details", systemImage: "info.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if importRecord.status == "completed" {
                    Button(action: onRerun) {
                        Label("Re-run", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor.opacity(0.3), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    var statusIcon: String {
        importRecord.statusEmoji == "✅" ? "checkmark.circle.fill" :
        importRecord.statusEmoji == "❌" ? "xmark.circle.fill" :
        importRecord.statusEmoji == "⏳" ? "clock.fill" :
        importRecord.statusEmoji == "🚫" ? "stop.circle.fill" :
        "pause.circle.fill"
    }

    var statusColor: Color {
        switch importRecord.status {
        case "completed": return .green
        case "failed": return .red
        case "running": return .blue
        case "cancelled": return .orange
        default: return .gray
        }
    }

    var importTypeLabel: String {
        if let limit = importRecord.importLimit {
            return "\(importRecord.importType.capitalized) Import (last \(limit))"
        } else {
            return "\(importRecord.importType.capitalized) Import (all videos)"
        }
    }

    func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

struct StatLabel: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Import Details Sheet

struct ImportDetailsSheet: View {
    let importRecord: ImportHistory

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import Details")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Batch ID: \(importRecord.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Text(importRecord.statusEmoji)
                    .font(.system(size: 40))
            }

            Divider()

            // Import Info
            VStack(alignment: .leading, spacing: 16) {
                DetailRow(label: "Import Type", value: importRecord.importType.capitalized)

                if let limit = importRecord.importLimit {
                    DetailRow(label: "Limit", value: "\(limit) videos")
                } else {
                    DetailRow(label: "Limit", value: "All videos")
                }

                if let sortOrder = importRecord.sortOrder {
                    DetailRow(label: "Sort Order", value: ImportSortOrder(rawValue: sortOrder)?.displayName ?? sortOrder)
                }

                DetailRow(label: "Status", value: importRecord.status.capitalized)

                Divider()

                DetailRow(label: "Videos Found", value: "\(importRecord.videosFound)")
                DetailRow(label: "Videos Imported", value: "\(importRecord.videosImported)")
                DetailRow(label: "Videos Skipped", value: "\(importRecord.videosSkipped)")
                DetailRow(label: "Videos Failed", value: "\(importRecord.videosFailed)")

                Divider()

                DetailRow(label: "Started At", value: formatDate(importRecord.startedAt))

                if let completed = importRecord.completedAt {
                    DetailRow(label: "Completed At", value: formatDate(completed))
                }

                if let duration = importRecord.formattedDuration {
                    DetailRow(label: "Duration", value: duration)
                }

                if let error = importRecord.errorMessage {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Error Message")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(error)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Spacer()
        }
        .padding(30)
        .frame(width: 600, height: 600)
    }

    func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .medium
        return displayFormatter.string(from: date)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label + ":")
                .font(.headline)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

#Preview {
    ImportHistoryView(
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
