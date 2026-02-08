import SwiftUI

struct ChannelMoviesView: View {
    let channel: ChannelWithPattern
    @StateObject private var apiService = AdminAPIService()

    @State private var source = "staging,production"
    @State private var searchText = ""
    @State private var moviesData: ChannelMoviesData?
    @State private var isLoading = false
    @State private var error: String?
    @State private var successMessage: String?

    // Batch operations
    @State private var selectedMovieIds: Set<String> = []
    @State private var showDeleteConfirm = false
    @State private var showReimportConfirm = false
    @State private var isPerformingBatchAction = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with filters and stats
            VStack(spacing: 12) {
                HStack {
                    Text("Channel Movies")
                        .font(.title)
                        .fontWeight(.bold)

                    Spacer()

                    // Stats
                    if let data = moviesData {
                        HStack(spacing: 20) {
                            if let staging = data.staging {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(staging.total)")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Text("Staging")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if let production = data.production {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(production.total)")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                    Text("Production")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Button {
                        Task { await loadMovies() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }

                // Filters
                HStack {
                    // Source filter
                    Picker("Source", selection: $source) {
                        Text("All").tag("staging,production")
                        Text("Staging Only").tag("staging")
                        Text("Production Only").tag("production")
                    }
                    .frame(width: 200)
                    .onChange(of: source) { _, _ in
                        Task { await loadMovies() }
                    }

                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search movies...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))

            // Batch Actions Bar
            if !selectedMovieIds.isEmpty {
                HStack {
                    Text("\(selectedMovieIds.count) selected")
                        .font(.headline)

                    Spacer()

                    Button(action: { /* batch enrich */ }) {
                        Label("Enrich Selected", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPerformingBatchAction)

                    Button(action: { /* batch approve */ }) {
                        Label("Approve Selected", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPerformingBatchAction)

                    Button(role: .destructive, action: { /* batch delete */ }) {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .disabled(isPerformingBatchAction)

                    Button("Clear Selection") {
                        selectedMovieIds.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
            }

            Divider()

            // Channel-wide Actions
            HStack {
                Button(action: { showReimportConfirm = true }) {
                    Label("Re-import Channel", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingBatchAction)

                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Label("Delete All Movies", systemImage: "trash.circle")
                }
                .disabled(isPerformingBatchAction)

                Spacer()
            }
            .padding()

            Divider()

            // Messages
            if let success = successMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(success)
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
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
            }

            // Movie Lists
            if isLoading {
                ProgressView("Loading movies...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Staging Movies
                        if let staging = moviesData?.staging, !staging.movies.isEmpty {
                            MovieSection(
                                title: "Staging (\(staging.total))",
                                movies: staging.movies,
                                selectedIds: $selectedMovieIds,
                                color: .orange
                            )
                        }

                        // Production Movies
                        if let production = moviesData?.production, !production.movies.isEmpty {
                            MovieSection(
                                title: "Production (\(production.total))",
                                movies: production.movies,
                                selectedIds: $selectedMovieIds,
                                color: .green
                            )
                        }

                        if moviesData?.staging?.movies.isEmpty == true && moviesData?.production?.movies.isEmpty == true {
                            VStack(spacing: 12) {
                                Image(systemName: "film")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                Text("No movies found")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Import videos from this channel to see them here")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(60)
                        }
                    }
                    .padding()
                }
            }
        }
        .confirmationDialog("Delete All Movies", isPresented: $showDeleteConfirm) {
            Button("Delete from Staging Only", role: .destructive) {
                deleteAllMovies(from: "staging")
            }
            Button("Delete from Production Only", role: .destructive) {
                deleteAllMovies(from: "production")
            }
            Button("Delete from Both", role: .destructive) {
                deleteAllMovies(from: "staging,production")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all movies from this channel. This action cannot be undone.")
        }
        .confirmationDialog("Re-import Channel", isPresented: $showReimportConfirm) {
            Button("Re-import (Keep Existing)") {
                reimportChannel(deleteExisting: false)
            }
            Button("Re-import (Delete & Re-import)", role: .destructive) {
                reimportChannel(deleteExisting: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether to keep existing movies or delete and re-import everything.")
        }
        .task {
            await loadMovies()
        }
    }

    // MARK: - Actions

    func loadMovies() async {
        isLoading = true
        error = nil

        do {
            let data = try await apiService.getChannelMovies(
                channelId: channel.id,
                source: source,
                page: 1,
                limit: 50
            )
            moviesData = data
        } catch {
            self.error = "Failed to load movies: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func deleteAllMovies(from source: String) {
        Task {
            isPerformingBatchAction = true
            error = nil
            successMessage = nil

            do {
                let result = try await apiService.deleteChannelMovies(
                    channelId: channel.id,
                    deleteFrom: source
                )

                let total = result.deletedFromStaging + result.deletedFromProduction
                successMessage = "Deleted \(total) movies (\(result.deletedFromStaging) from staging, \(result.deletedFromProduction) from production)"

                await loadMovies()

                // Clear success message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    successMessage = nil
                }
            } catch {
                self.error = "Failed to delete movies: \(error.localizedDescription)"
            }

            isPerformingBatchAction = false
        }
    }

    func reimportChannel(deleteExisting: Bool) {
        Task {
            isPerformingBatchAction = true
            error = nil
            successMessage = nil

            do {
                let response = try await apiService.reimportChannel(
                    channelId: channel.id,
                    deleteExisting: deleteExisting,
                    limit: nil,
                    applySettings: true
                )

                successMessage = "Re-import started (Batch ID: \(response.batchId)). Check Import History for progress."

                if deleteExisting {
                    await loadMovies()
                }

                // Clear success message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    successMessage = nil
                }
            } catch {
                self.error = "Failed to start re-import: \(error.localizedDescription)"
            }

            isPerformingBatchAction = false
        }
    }
}

// MARK: - Movie Section

struct MovieSection: View {
    let title: String
    let movies: [StagedMovie]
    @Binding var selectedIds: Set<String>
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "film")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)

                Spacer()

                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        movies.forEach { selectedIds.remove($0.id) }
                    } else {
                        movies.forEach { selectedIds.insert($0.id) }
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }

            ForEach(movies) { movie in
                ChannelMovieRow(
                    movie: movie,
                    isSelected: selectedIds.contains(movie.id),
                    onToggleSelection: {
                        if selectedIds.contains(movie.id) {
                            selectedIds.remove(movie.id)
                        } else {
                            selectedIds.insert(movie.id)
                        }
                    }
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    var allSelected: Bool {
        !movies.isEmpty && movies.allSatisfy { selectedIds.contains($0.id) }
    }
}

// MARK: - Channel Movie Row

struct ChannelMovieRow: View {
    let movie: StagedMovie
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            // Poster
            if let posterPath = movie.posterPath {
                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w92\(posterPath)")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 90)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }

            // Movie Info
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)

                if let releaseDate = movie.releaseDate {
                    let year = String(releaseDate.prefix(4))
                    Text("Year: \(year)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let category = movie.category {
                    Text("Category: \(category)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let actors = movie.actors {
                    let actorList = actors.split(separator: ",").prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }
                    Text("Actors: \(actorList.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Status badge
                Text(movie.approvalStatus.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor(movie.approvalStatus.rawValue))
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }

            Spacer()

            // Enrichment indicator
            if movie.enrichmentSource != nil {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "approved": return .green
        case "rejected": return .red
        case "pending": return .orange
        default: return .gray
        }
    }
}

#Preview {
    ChannelMoviesView(
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
