import SwiftUI

struct MovieDetailView: View {
    let movie: StagedMovie
    @StateObject private var apiService = AdminAPIService()
    @Environment(\.dismiss) private var dismiss

    @State private var editedTitle: String
    @State private var editedActors: String
    @State private var editedCategory: String
    @State private var editedReleaseDate: String
    @State private var editedDescription: String

    @State private var isSaving = false
    @State private var error: String?
    @State private var successMessage: String?

    init(movie: StagedMovie) {
        self.movie = movie
        _editedTitle = State(initialValue: movie.title)
        _editedActors = State(initialValue: movie.actors ?? "")
        _editedCategory = State(initialValue: movie.category ?? "")
        _editedReleaseDate = State(initialValue: movie.releaseDate ?? "")
        _editedDescription = State(initialValue: movie.description ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    Text("Movie Details")
                        .font(.title)
                        .fontWeight(.bold)

                    Spacer()

                    Button("Close") {
                        dismiss()
                    }
                }

                Divider()

                // YouTube Original Info
                GroupBox(label: Label("YouTube Original", systemImage: "play.rectangle.fill")) {
                    VStack(alignment: .leading, spacing: 16) {
                        // YouTube Thumbnail
                        if let thumbnailURL = movie.youtubeThumbnailURL {
                            AsyncImage(url: thumbnailURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .overlay(ProgressView())
                            }
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Original YouTube Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Original YouTube Title:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Text(movie.youtubeVideoTitle)
                                .font(.body)
                                .textSelection(.enabled)
                        }

                        // YouTube Video Link
                        if let youtubeURL = movie.youtubeURL {
                            Link(destination: youtubeURL) {
                                Label("Open in YouTube", systemImage: "play.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }

                // Pattern Extraction Results
                GroupBox(label: Label("Pattern Extraction", systemImage: "wand.and.stars")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("These values were extracted from the YouTube title using the channel's pattern:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        // Show what pattern extraction found vs current values
                        ExtractionComparisonRow(
                            label: "Title",
                            extracted: movie.title,
                            current: movie.title
                        )

                        if let actors = movie.actors {
                            ExtractionComparisonRow(
                                label: "Actors",
                                extracted: actors,
                                current: actors
                            )
                        }

                        if let category = movie.category {
                            ExtractionComparisonRow(
                                label: "Category/Genre",
                                extracted: category,
                                current: category
                            )
                        }

                        if let releaseDate = movie.releaseDate {
                            let year = String(releaseDate.prefix(4))
                            ExtractionComparisonRow(
                                label: "Year",
                                extracted: year,
                                current: year
                            )
                        }
                    }
                    .padding()
                }

                // Manual Edit Section
                GroupBox(label: Label("Edit Movie Information", systemImage: "pencil.circle")) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Title")
                                .font(.caption)
                                .fontWeight(.semibold)
                            TextField("Movie title", text: $editedTitle)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Actors
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Actors (comma separated)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            TextField("e.g., Tom Hanks, Meg Ryan", text: $editedActors)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Category/Genre
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Category/Genre")
                                .font(.caption)
                                .fontWeight(.semibold)
                            TextField("e.g., Horror, Action", text: $editedCategory)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Release Date
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Release Date (YYYY-MM-DD)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            TextField("e.g., 1995-01-15", text: $editedReleaseDate)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Description
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption)
                                .fontWeight(.semibold)
                            TextEditor(text: $editedDescription)
                                .frame(height: 100)
                                .border(Color.gray.opacity(0.3))
                        }
                    }
                    .padding()
                }

                // Enrichment Status
                if movie.hasEnrichment {
                    GroupBox(label: Label("Enrichment Status", systemImage: "sparkles")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Source:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(movie.enrichmentStatus)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }

                            if let tmdbId = movie.tmdbId {
                                HStack {
                                    Text("TMDB ID:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(tmdbId)")
                                        .font(.caption)
                                }
                            }

                            if let imdbId = movie.imdbId {
                                HStack {
                                    Text("IMDB ID:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(imdbId)
                                        .font(.caption)
                                }
                            }

                            if let confidence = movie.enrichmentConfidence {
                                HStack {
                                    Text("Confidence:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.0f%%", confidence * 100))
                                        .font(.caption)
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
                    Button(action: saveChanges) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.horizontal, 8)
                        } else {
                            Text("Save Changes")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || !hasChanges)
                    .controlSize(.large)
                    Spacer()
                }
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 800)
    }

    var hasChanges: Bool {
        editedTitle != movie.title ||
        editedActors != (movie.actors ?? "") ||
        editedCategory != (movie.category ?? "") ||
        editedReleaseDate != (movie.releaseDate ?? "") ||
        editedDescription != (movie.description ?? "")
    }

    func saveChanges() {
        Task {
            isSaving = true
            error = nil
            successMessage = nil

            do {
                // Build updates dictionary
                var updates: [String: Any] = [:]

                if editedTitle != movie.title {
                    updates["title"] = editedTitle
                }
                if editedActors != (movie.actors ?? "") {
                    updates["actors"] = editedActors.isEmpty ? nil : editedActors
                }
                if editedCategory != (movie.category ?? "") {
                    updates["category"] = editedCategory.isEmpty ? nil : editedCategory
                }
                if editedReleaseDate != (movie.releaseDate ?? "") {
                    updates["release_date"] = editedReleaseDate.isEmpty ? nil : editedReleaseDate
                }
                if editedDescription != (movie.description ?? "") {
                    updates["description"] = editedDescription.isEmpty ? nil : editedDescription
                }

                if updates.isEmpty {
                    successMessage = "No changes to save"
                } else {
                    _ = try await apiService.updateStagedMovie(movieId: movie.id, updates: updates)
                    successMessage = "Changes saved successfully (\(updates.count) fields updated)"
                }

                // Clear success message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    successMessage = nil
                }
            } catch {
                self.error = "Failed to save changes: \(error.localizedDescription)"
            }

            isSaving = false
        }
    }
}

// MARK: - Extraction Comparison Row

struct ExtractionComparisonRow: View {
    let label: String
    let extracted: String
    let current: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extracted:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(extracted)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)

                if extracted != current {
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(current)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
    }
}

#Preview {
    MovieDetailView(
        movie: StagedMovie(
            id: "1",
            youtubeVideoId: "dQw4w9WgXcQ",
            youtubeVideoTitle: "Rick Astley - Never Gonna Give You Up (Official Music Video)",
            title: "Never Gonna Give You Up",
            originalTitle: nil,
            description: "The official video for Rick Astley",
            releaseDate: "1987-07-27",
            runtimeMinutes: 213,
            channelId: "UC123",
            channelTitle: "Test Channel",
            viewCount: 1000000,
            likeCount: 50000,
            commentCount: 1000,
            publishedAt: "2020-01-01T00:00:00Z",
            tmdbId: 12345,
            imdbId: "tt1234567",
            posterPath: "/path/to/poster.jpg",
            backdropPath: nil,
            voteAverage: 8.5,
            voteCount: 1000,
            popularity: 100.0,
            imdbRating: 8.0,
            imdbVotes: 5000,
            rated: "PG-13",
            director: "Test Director",
            actors: "Rick Astley, Test Actor",
            language: "English",
            country: "USA",
            isTvShow: false,
            category: "Music",
            enrichmentSource: "tmdb",
            enrichmentConfidence: 0.95,
            enrichmentPreview: nil,
            manualChanges: nil,
            approvalStatus: .pending,
            approvedBy: nil,
            approvedAt: nil,
            rejectedReason: nil,
            notes: nil,
            importBatchId: nil,
            publishedMovieId: nil,
            createdAt: "2024-01-01T00:00:00Z",
            updatedAt: nil
        )
    )
}
