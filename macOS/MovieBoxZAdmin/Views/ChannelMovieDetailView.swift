import SwiftUI

struct ChannelMovieDetailView: View {
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

                // TMDB/IMDB Enrichment Data
                if movie.hasEnrichment {
                    GroupBox(label: Label("TMDB/IMDB Enrichment Data", systemImage: "film")) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                // TMDB Poster
                                if let posterPath = movie.posterPath {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("TMDB Poster")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                        AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                        } placeholder: {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.2))
                                                .overlay(ProgressView())
                                        }
                                        .frame(width: 150, height: 225)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }

                                // Enrichment Details
                                VStack(alignment: .leading, spacing: 12) {
                                    // Source and Confidence
                                    HStack(spacing: 16) {
                                        if let source = movie.enrichmentSource {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Source")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Text(source.uppercased())
                                                    .font(.headline)
                                                    .foregroundColor(.blue)
                                            }
                                        }

                                        if let confidence = movie.enrichmentConfidence {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Confidence")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Text(String(format: "%.0f%%", confidence * 100))
                                                    .font(.headline)
                                                    .foregroundColor(confidence > 0.8 ? .green : .orange)
                                            }
                                        }
                                    }

                                    Divider()

                                    // IDs and Links
                                    if let tmdbId = movie.tmdbId {
                                        HStack {
                                            Text("TMDB ID:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("\(tmdbId)")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Link(destination: URL(string: "https://www.themoviedb.org/movie/\(tmdbId)")!) {
                                                Image(systemName: "link")
                                                    .font(.caption)
                                            }
                                        }
                                    }

                                    if let imdbId = movie.imdbId {
                                        HStack {
                                            Text("IMDB ID:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(imdbId)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Link(destination: URL(string: "https://www.imdb.com/title/\(imdbId)")!) {
                                                Image(systemName: "link")
                                                    .font(.caption)
                                            }
                                        }
                                    }

                                    Divider()

                                    // Ratings
                                    HStack(spacing: 20) {
                                        if let tmdbRating = movie.voteAverage, let voteCount = movie.voteCount {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("TMDB Rating")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                HStack(spacing: 4) {
                                                    Image(systemName: "star.fill")
                                                        .foregroundColor(.yellow)
                                                        .font(.caption)
                                                    Text(String(format: "%.1f/10", tmdbRating))
                                                        .font(.body)
                                                        .fontWeight(.semibold)
                                                    Text("(\(voteCount) votes)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }

                                        if let imdbRating = movie.imdbRating, let imdbVotes = movie.imdbVotes {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("IMDB Rating")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                HStack(spacing: 4) {
                                                    Image(systemName: "star.fill")
                                                        .foregroundColor(.yellow)
                                                        .font(.caption)
                                                    Text(String(format: "%.1f/10", imdbRating))
                                                        .font(.body)
                                                        .fontWeight(.semibold)
                                                    Text("(\(imdbVotes) votes)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }

                                    // Additional Details
                                    if let rated = movie.rated {
                                        HStack {
                                            Text("Rated:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(rated)
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.2))
                                                .cornerRadius(4)
                                        }
                                    }

                                    if let director = movie.director {
                                        HStack {
                                            Text("Director:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(director)
                                                .font(.caption)
                                        }
                                    }

                                    if let runtime = movie.runtimeMinutes {
                                        HStack {
                                            Text("Runtime:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("\(runtime) minutes")
                                                .font(.caption)
                                        }
                                    }

                                    if let language = movie.language {
                                        HStack {
                                            Text("Language:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(language)
                                                .font(.caption)
                                        }
                                    }

                                    if let country = movie.country {
                                        HStack {
                                            Text("Country:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(country)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }

                            // Plot/Description from enrichment
                            if let description = movie.description, !description.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Plot")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    Text(description)
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                        }
                        .padding()
                    }
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
    ChannelMovieDetailView(
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
