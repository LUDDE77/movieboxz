import SwiftUI

struct AdminView: View {
    @StateObject private var apiService = AdminAPIService()
    @State private var stats: AdminStats?
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
                Label("Channel Setup", systemImage: "tv.fill")
                    .tag(2)
                Label("Genres", systemImage: "theatermasks.fill")
                    .tag(3)
                Label("TV Series", systemImage: "tv.and.mediabox")
                    .tag(4)
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
                    DashboardView(stats: stats, isLoading: isLoadingStats, error: statsError)
                case 1:
                    MoviesView()
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
            await loadStats()
        }
    }

    private func loadStats() async {
        isLoadingStats = true
        statsError = nil

        do {
            stats = try await apiService.getStats()
        } catch {
            statsError = error.localizedDescription
            print("Error loading stats: \(error)")
        }

        isLoadingStats = false
    }
}

struct DashboardView: View {
    let stats: AdminStats?
    let isLoading: Bool
    let error: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading statistics...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack {
                    Text("Failed to load statistics")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let stats = stats {
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
                .padding()
            } else {
                Text("No statistics available")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Dashboard")
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
