import SwiftUI

struct AdminView: View {
    @StateObject private var apiService = AdminAPIService()
    @State private var stats: AdminStats?
    @State private var stagingStats: StagingStats?
    @State private var quota: QuotaInfo?
    @State private var isLoadingStats = false
    @State private var statsError: String?
    @State private var selectedTab = 0

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Dashboard", systemImage: "chart.bar.fill")
                    .tag(0)
                Label("Movies", systemImage: "film.fill")
                    .tag(1)
                Label("Staging", systemImage: "tray.full.fill")
                    .tag(7)
                Label("Verification", systemImage: "checkmark.seal.fill")
                    .tag(8)
                Label("Duplicates", systemImage: "square.on.square")
                    .tag(9)
                Label("Channel Setup", systemImage: "tv.fill")
                    .tag(2)
                Label("Genres", systemImage: "theatermasks.fill")
                    .tag(3)
                Label("TV Series", systemImage: "tv.and.mediabox")
                    .tag(4)
                Label("Series Matching", systemImage: "link")
                    .tag(10)
                Label("Featured", systemImage: "star.fill")
                    .tag(5)
                Label("Settings", systemImage: "gearshape.fill")
                    .tag(6)
            }
            .navigationTitle("Admin")
            .frame(minWidth: 200)
        } detail: {
            Group {
                switch selectedTab {
                case 0:
                    DashboardView(
                        stats: stats,
                        stagingStats: stagingStats,
                        quota: quota,
                        isLoading: isLoadingStats,
                        error: statsError,
                        onRefresh: { await loadDashboard() }
                    )
                case 1:
                    MoviesView()
                case 7:
                    StagingView()
                case 8:
                    VerificationQueueView()
                case 9:
                    DuplicateManagerView()
                case 10:
                    SeriesMatchingView()
                case 2:
                    ChannelManagementView()
                case 3:
                    GenresView()
                case 4:
                    TVSeriesView()
                case 5:
                    FeaturedMoviesView()
                case 6:
                    AppSettingsView()
                default:
                    Text("Select a section")
                }
            }
        }
        .task {
            await loadDashboard()
        }
        .onChange(of: selectedTab) { _, newValue in
            // Reload the dashboard whenever the user navigates back to it.
            if newValue == 0 {
                Task { await loadDashboard() }
            }
        }
    }

    private func loadDashboard() async {
        isLoadingStats = true
        statsError = nil

        // Load the core stats (funnel + quota are best-effort so a missing
        // endpoint never blanks the whole dashboard).
        async let statsTask = try? await apiService.getStats()
        async let stagingTask = try? await apiService.getStagingStats()
        async let quotaTask = try? await apiService.getQuota()

        let loadedStats = await statsTask
        stagingStats = await stagingTask
        quota = await quotaTask

        if let loadedStats {
            stats = loadedStats
        } else if stats == nil {
            statsError = "Failed to load statistics"
        }

        isLoadingStats = false
    }
}

struct DashboardView: View {
    let stats: AdminStats?
    let stagingStats: StagingStats?
    let quota: QuotaInfo?
    let isLoading: Bool
    let error: String?
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView {
            if isLoading && stats == nil {
                ProgressView("Loading statistics...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 80)
            } else if let error = error, stats == nil {
                VStack {
                    Text("Failed to load statistics")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    if let quota = quota {
                        QuotaGaugeCard(quota: quota)
                    }

                    if let staging = stagingStats {
                        PipelineFunnelView(staging: staging, publishedTotal: stats?.totalMovies)
                    }

                    if let stats = stats {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 20) {
                            StatCard(title: "Total Movies", value: "\(stats.totalMovies)", icon: "film.fill", color: .blue)
                            StatCard(title: "Available Movies", value: "\(stats.availableMovies)", icon: "checkmark.circle.fill", color: .green)
                            StatCard(title: "Total Channels", value: "\(stats.totalChannels)", icon: "tv.fill", color: .purple)
                            StatCard(title: "Total Genres", value: "\(stats.totalGenres)", icon: "theatermasks.fill", color: .orange)
                            StatCard(title: "Enriched Movies", value: "\(stats.enrichedMovies)", icon: "sparkles", color: .yellow)
                            StatCard(title: "Pending Enrichment", value: "\(stats.pendingEnrichment)", icon: "clock.fill", color: .red)
                            StatCard(title: "Recently Added", value: "\(stats.recentlyAdded)", icon: "plus.circle.fill", color: .cyan)
                            StatCard(title: "Last Curation", value: formatDate(stats.lastCuration), icon: "calendar", color: .gray)
                        }
                    }
                }
                .padding()
            }
        }
        .refreshable { await onRefresh() }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await onRefresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    private func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "Never" }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Quota Gauge Card

struct QuotaGaugeCard: View {
    let quota: QuotaInfo

    private var fraction: Double {
        guard quota.budget > 0 else { return 0 }
        return min(1.0, Double(quota.used) / Double(quota.budget))
    }

    private var color: Color {
        switch fraction {
        case ..<0.7: return .green
        case ..<0.9: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("YouTube API Quota", systemImage: "bolt.fill")
                    .font(.headline)
                Spacer()
                Text(quota.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Gauge(value: fraction) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(fraction * 100))%")
                        .font(.caption2)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(color)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(quota.used) / \(quota.budget) units")
                        .font(.system(size: 22, weight: .bold))
                    Text("\(quota.remaining) remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Pipeline Funnel

struct PipelineFunnelView: View {
    let staging: StagingStats
    let publishedTotal: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Staging Pipeline")
                .font(.headline)

            HStack(spacing: 12) {
                FunnelStage(title: "Pending", value: staging.pending, color: .orange, icon: "clock.fill")
                FunnelArrow()
                FunnelStage(title: "Enriched", value: staging.enriched, color: .yellow, icon: "sparkles")
                FunnelArrow()
                FunnelStage(title: "Approved", value: staging.approved, color: .green, icon: "checkmark.seal.fill")
                FunnelArrow()
                FunnelStage(title: "Published", value: publishedTotal ?? 0, color: .blue, icon: "arrow.up.circle.fill")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct FunnelStage: View {
    let title: String
    let value: Int
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            Text("\(value)")
                .font(.system(size: 24, weight: .bold))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct FunnelArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .foregroundColor(.secondary)
            .font(.caption)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Spacer()
            }

            Text(value)
                .font(.system(size: 32, weight: .bold))

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct ChannelsView: View {
    @StateObject private var apiService = AdminAPIService()
    @State private var channels: [ChannelWithPattern] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading channels...")
            } else if let error = error {
                VStack {
                    Text("Error loading channels")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if channels.isEmpty {
                Text("No channels found")
                    .foregroundColor(.secondary)
            } else {
                List(channels) { channel in
                    VStack(alignment: .leading) {
                        Text(channel.title)
                            .font(.headline)
                        HStack {
                            if let videoCount = channel.videoCount {
                                Text("\(videoCount) videos")
                                    .font(.caption)
                            }
                            if let subscriberCount = channel.subscriberCount {
                                Text("• \(formatNumber(subscriberCount)) subscribers")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if channel.hasPattern == true {
                                Text("• Has pattern")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Channels")
        .task {
            await loadChannels()
        }
    }

    private func loadChannels() async {
        isLoading = true
        error = nil

        do {
            let data = try await apiService.getChannelsWithPatterns()
            channels = data.channels
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct GenresView: View {
    @StateObject private var apiService = AdminAPIService()
    @State private var genres: [Genre] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading genres...")
            } else if let error = error {
                VStack {
                    Text("Error loading genres")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if genres.isEmpty {
                Text("No genres found")
                    .foregroundColor(.secondary)
            } else {
                List(genres) { genre in
                    HStack {
                        Text(genre.name)
                            .font(.body)
                        Spacer()
                        if let movieCount = genre.movieCount {
                            Text("\(movieCount) movies")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Genres")
        .task {
            await loadGenres()
        }
    }

    private func loadGenres() async {
        isLoading = true
        error = nil

        do {
            let data = try await apiService.getGenres()
            genres = data.genres
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    AdminView()
}
