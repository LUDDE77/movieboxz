import SwiftUI

// MARK: - Import History Extras
// The backend returns `auto_enriched` and `error_details` on import_history
// rows, but the shared `ImportHistory` model (Models.swift, not owned here)
// does not decode them yet. Until it does, they are fetched with a
// supplementary decode of the same endpoint.

struct ImportErrorDetail: Codable, Hashable {
    let videoId: String?
    let title: String?
    let error: String?
}

struct ImportHistoryExtras: Codable {
    let id: String
    let autoEnriched: Bool?
    let errorDetails: [ImportErrorDetail]?

    enum CodingKeys: String, CodingKey {
        case id
        case autoEnriched = "auto_enriched"
        case errorDetails = "error_details"
    }
}

private struct ImportHistoryExtrasData: Codable {
    let imports: [ImportHistoryExtras]
}

struct ImportHistoryView: View {
    let channel: ChannelWithPattern
    @StateObject private var apiService = AdminAPIService()

    @State private var imports: [ImportHistory] = []
    @State private var extrasById: [String: ImportHistoryExtras] = [:]
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

                Button {
                    Task { await loadHistory() }
                } label: {
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
                ImportDetailsSheet(
                    importRecord: importRecord,
                    extras: extrasById[importRecord.id]
                )
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

        // Supplementary decode of the same endpoint for auto_enriched /
        // error_details (missing from the shared ImportHistory model).
        // Failure here degrades gracefully — the extras just stay hidden.
        do {
            let data = try await ChannelAdminDirectAPI.send(
                path: "/channel-management/\(channel.id)/import-history?limit=50",
                method: "GET"
            )
            let extras = try ChannelAdminDirectAPI.decode(ImportHistoryExtrasData.self, from: data)
            extrasById = Dictionary(uniqueKeysWithValues: extras.imports.map { ($0.id, $0) })
        } catch {
            print("Failed to load import history extras: \(error)")
        }

        isLoading = false
    }

    func rerunImport(_ importRecord: ImportHistory) {
        Task {
            do {
                // Preserve the original run's auto-enrich choice (from the
                // supplementary extras fetch; nil if unavailable).
                let originalAutoEnrich = extrasById[importRecord.id]?.autoEnriched
                let request = BulkImportRequest(
                    limit: importRecord.importLimit,
                    sortOrder: importRecord.sortOrder ?? "latest",
                    applySettings: true,
                    autoEnrich: originalAutoEnrich == true ? true : nil
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

                    // Pattern match rate (when reported by the backend)
                    if let match = patternMatch {
                        StatLabel(
                            label: "Pattern",
                            value: "\(match.matched)/\(match.imported) (\(match.percent)%)",
                            color: match.percent >= 50 ? .green : (match.percent >= 25 ? .orange : .red)
                        )
                    }

                    if importRecord.truncated == true {
                        Text("Stopped at cap")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                            .help("Import stopped at the safety cap — the channel has more videos")
                    }

                    Spacer()

                    if importRecord.durationSeconds != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text(importRecord.formattedDuration)
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
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor.opacity(0.3), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    /// Pattern match rate of the imported videos, when reported.
    var patternMatch: (matched: Int, imported: Int, percent: Int)? {
        guard let matched = importRecord.patternMatchCount,
              importRecord.videosImported > 0 else { return nil }
        let percent = Int((Double(matched) / Double(importRecord.videosImported)) * 100)
        return (matched, importRecord.videosImported, percent)
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
    var extras: ImportHistoryExtras? = nil

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
                DetailRow(label: "Import Type", value: importRecord.importType.capitalized, labelWidth: 150, showColon: true)

                if let limit = importRecord.importLimit {
                    DetailRow(label: "Limit", value: "\(limit) videos", labelWidth: 150, showColon: true)
                } else {
                    DetailRow(label: "Limit", value: "All videos", labelWidth: 150, showColon: true)
                }

                if let sortOrder = importRecord.sortOrder {
                    DetailRow(label: "Sort Order", value: ImportSortOrder(rawValue: sortOrder)?.displayName ?? sortOrder, labelWidth: 150, showColon: true)
                }

                DetailRow(label: "Status", value: importRecord.status.capitalized, labelWidth: 150, showColon: true)

                Divider()

                DetailRow(label: "Videos Found", value: "\(importRecord.videosFound)", labelWidth: 150, showColon: true)
                DetailRow(label: "Videos Imported", value: "\(importRecord.videosImported)", labelWidth: 150, showColon: true)
                DetailRow(label: "Videos Skipped", value: "\(importRecord.videosSkipped)", labelWidth: 150, showColon: true)
                DetailRow(label: "Videos Failed", value: "\(importRecord.videosFailed)", labelWidth: 150, showColon: true)

                if let matched = importRecord.patternMatchCount, importRecord.videosImported > 0 {
                    let percent = Int((Double(matched) / Double(importRecord.videosImported)) * 100)
                    DetailRow(label: "Pattern Matched", value: "\(matched) of \(importRecord.videosImported) (\(percent)%)", labelWidth: 150, showColon: true)
                }

                if importRecord.truncated == true {
                    DetailRow(label: "Truncated", value: "Stopped at safety cap — channel has more videos", labelWidth: 150, showColon: true)
                }

                if let autoEnriched = extras?.autoEnriched {
                    DetailRow(label: "Auto-enrich", value: autoEnriched ? "Enabled" : "Disabled", labelWidth: 150, showColon: true)
                }

                Divider()

                DetailRow(label: "Started At", value: formatDate(importRecord.startedAt), labelWidth: 150, showColon: true)

                if let completed = importRecord.completedAt {
                    DetailRow(label: "Completed At", value: formatDate(completed), labelWidth: 150, showColon: true)
                }

                if importRecord.durationSeconds != nil {
                    DetailRow(label: "Duration", value: importRecord.formattedDuration, labelWidth: 150, showColon: true)
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

                // Per-video failures (import_history.error_details)
                if let failures = extras?.errorDetails, !failures.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Per-Video Failures (\(failures.count))")
                            .font(.headline)
                            .foregroundColor(.red)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(failure.title ?? failure.videoId ?? "Unknown video")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)
                                        Text(failure.error ?? "Unknown error")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .textSelection(.enabled)
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.06))
                                    .cornerRadius(6)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }
            }

            Spacer()
        }
        .padding(30)
        .frame(width: 600, height: 640)
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
            hasMovies: true,
            hasSeries: false,
            hasKidsContent: false,
            patternSource: "title",
            createdAt: "",
            updatedAt: nil
        )
    )
}
