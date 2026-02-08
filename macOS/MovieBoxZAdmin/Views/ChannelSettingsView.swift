import SwiftUI

struct ChannelSettingsView: View {
    let channel: ChannelWithPattern
    @StateObject private var apiService = AdminAPIService()

    @State private var settings: ChannelSettings?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var successMessage: String?

    // Form fields
    @State private var autoImportEnabled = false
    @State private var autoImportSchedule = "manual"
    @State private var importLimit: String = "50"
    @State private var importSortOrder = "latest"
    @State private var defaultEnrichmentPriority = "standard"
    @State private var autoEnrichOnImport = false
    @State private var autoApproveThreshold: String = ""
    @State private var requireManualReview = true
    @State private var channelTag: String = ""
    @State private var isFeatured = false
    @State private var qualityTier = "standard"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Channel Settings")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Configure import defaults and channel behavior")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                if isLoading {
                    ProgressView("Loading settings...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Import Configuration
                    GroupBox(label: Label("Import Configuration", systemImage: "arrow.down.circle")) {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle("Auto-import enabled", isOn: $autoImportEnabled)
                                .help("Automatically import new videos from this channel")

                            HStack {
                                Text("Auto-import schedule:")
                                    .frame(width: 180, alignment: .leading)
                                Picker("", selection: $autoImportSchedule) {
                                    Text("Manual").tag("manual")
                                    Text("Daily").tag("daily")
                                    Text("Weekly").tag("weekly")
                                }
                                .frame(width: 150)
                            }

                            HStack {
                                Text("Default import limit:")
                                    .frame(width: 180, alignment: .leading)
                                TextField("50", text: $importLimit)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                Text("videos")
                                    .foregroundColor(.secondary)
                            }
                            .help("Maximum number of videos to import per batch (leave empty for unlimited)")

                            HStack {
                                Text("Default sort order:")
                                    .frame(width: 180, alignment: .leading)
                                Picker("", selection: $importSortOrder) {
                                    ForEach(ImportSortOrder.allCases, id: \.rawValue) { order in
                                        Text(order.displayName).tag(order.rawValue)
                                    }
                                }
                                .frame(width: 250)
                            }
                        }
                        .padding()
                    }

                    // Enrichment Defaults
                    GroupBox(label: Label("Enrichment Defaults", systemImage: "sparkles")) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Default priority:")
                                    .frame(width: 180, alignment: .leading)
                                Picker("", selection: $defaultEnrichmentPriority) {
                                    ForEach(EnrichmentPriority.allCases, id: \.rawValue) { priority in
                                        Text(priority.displayName).tag(priority.rawValue)
                                    }
                                }
                                .frame(width: 150)
                            }
                            .help("Default enrichment level for movies from this channel")

                            Toggle("Auto-enrich on import", isOn: $autoEnrichOnImport)
                                .help("Automatically enrich movies after importing")
                        }
                        .padding()
                    }

                    // Approval Settings
                    GroupBox(label: Label("Approval Settings", systemImage: "checkmark.circle")) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Auto-approve threshold:")
                                    .frame(width: 180, alignment: .leading)
                                TextField("0.85", text: $autoApproveThreshold)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                Text("(0.0 - 1.0)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .help("Movies with enrichment confidence above this threshold will be auto-approved (leave empty to disable)")

                            Toggle("Require manual review", isOn: $requireManualReview)
                                .help("Always require manual review before publishing")
                        }
                        .padding()
                    }

                    // Channel Metadata
                    GroupBox(label: Label("Channel Metadata", systemImage: "tag")) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Channel tag:")
                                    .frame(width: 180, alignment: .leading)
                                TextField("e.g., classic-horror", text: $channelTag)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                            }
                            .help("Tag applied to all movies from this channel for filtering")

                            HStack {
                                Text("Quality tier:")
                                    .frame(width: 180, alignment: .leading)
                                Picker("", selection: $qualityTier) {
                                    ForEach(QualityTier.allCases, id: \.rawValue) { tier in
                                        Text(tier.displayName).tag(tier.rawValue)
                                    }
                                }
                                .frame(width: 150)
                            }

                            Toggle("Featured channel", isOn: $isFeatured)
                                .help("Mark this channel as featured in the app")
                        }
                        .padding()
                    }

                    // Statistics (read-only)
                    if let settings = settings {
                        GroupBox(label: Label("Statistics", systemImage: "chart.bar")) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Total imported:")
                                    Spacer()
                                    Text("\(settings.totalImported)")
                                        .fontWeight(.semibold)
                                }

                                HStack {
                                    Text("Total published:")
                                    Spacer()
                                    Text("\(settings.totalPublished)")
                                        .fontWeight(.semibold)
                                }

                                if let lastImport = settings.lastImportAt {
                                    HStack {
                                        Text("Last import:")
                                        Spacer()
                                        Text(formatDate(lastImport))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding()
                        }
                    }

                    // Success/Error Messages
                    if let success = successMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(success)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
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
                        .cornerRadius(8)
                    }

                    // Save Button
                    HStack {
                        Spacer()
                        Button(action: saveSettings) {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.horizontal, 8)
                            } else {
                                Text("Save Settings")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                        .controlSize(.large)
                        Spacer()
                    }
                    .padding(.top)
                }
            }
            .padding()
        }
        .task {
            await loadSettings()
        }
    }

    // MARK: - Actions

    func loadSettings() async {
        isLoading = true
        error = nil

        do {
            let loadedSettings = try await apiService.getChannelSettings(channelId: channel.id)
            settings = loadedSettings

            // Populate form fields
            autoImportEnabled = loadedSettings.autoImportEnabled
            autoImportSchedule = loadedSettings.autoImportSchedule
            importLimit = loadedSettings.importLimit.map(String.init) ?? ""
            importSortOrder = loadedSettings.importSortOrder
            defaultEnrichmentPriority = loadedSettings.defaultEnrichmentPriority
            autoEnrichOnImport = loadedSettings.autoEnrichOnImport
            autoApproveThreshold = loadedSettings.autoApproveThreshold.map { String($0) } ?? ""
            requireManualReview = loadedSettings.requireManualReview
            channelTag = loadedSettings.channelTag ?? ""
            isFeatured = loadedSettings.isFeatured
            qualityTier = loadedSettings.qualityTier
        } catch {
            self.error = "Failed to load settings: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func saveSettings() {
        Task {
            isSaving = true
            error = nil
            successMessage = nil

            do {
                // Build updated settings
                guard var updatedSettings = settings else { return }

                updatedSettings.autoImportEnabled = autoImportEnabled
                updatedSettings.autoImportSchedule = autoImportSchedule
                updatedSettings.importLimit = importLimit.isEmpty ? nil : Int(importLimit)
                updatedSettings.importSortOrder = importSortOrder
                updatedSettings.defaultEnrichmentPriority = defaultEnrichmentPriority
                updatedSettings.autoEnrichOnImport = autoEnrichOnImport
                updatedSettings.autoApproveThreshold = autoApproveThreshold.isEmpty ? nil : Double(autoApproveThreshold)
                updatedSettings.requireManualReview = requireManualReview
                updatedSettings.channelTag = channelTag.isEmpty ? nil : channelTag
                updatedSettings.isFeatured = isFeatured
                updatedSettings.qualityTier = qualityTier

                let savedSettings = try await apiService.updateChannelSettings(
                    channelId: channel.id,
                    settings: updatedSettings
                )

                settings = savedSettings
                successMessage = "Settings saved successfully"

                // Clear success message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    successMessage = nil
                }
            } catch {
                self.error = "Failed to save settings: \(error.localizedDescription)"
            }

            isSaving = false
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

#Preview {
    ChannelSettingsView(
        channel: ChannelWithPattern(
            id: "UC123",
            title: "Test Channel",
            description: "A test channel",
            customUrl: nil,
            thumbnailUrl: nil,
            publishedAt: "",
            subscriberCount: 1000,
            videoCount: 100,
            viewCount: 50000,
            createdAt: "",
            lastSyncAt: nil,
            pattern: nil,
            hasPattern: false
        )
    )
}
