import SwiftUI

struct ChannelMovieDetailView: View {
    let movie: StagedMovie
    let onUpdate: (() -> Void)?
    @StateObject private var apiService = AdminAPIService()
    @Environment(\.dismiss) private var dismiss

    @State private var editedTitle: String
    @State private var editedActors: String
    @State private var editedCategory: String
    @State private var editedReleaseDate: String
    @State private var editedDescription: String
    @State private var manualImdbId: String

    @State private var isSaving = false
    @State private var isEnrichingFromIMDB = false
    @State private var isClearingEnrichment = false
    @State private var error: String?
    @State private var successMessage: String?
    @State private var changesSaved = false

    init(movie: StagedMovie, onUpdate: (() -> Void)? = nil) {
        self.movie = movie
        self.onUpdate = onUpdate
        _editedTitle = State(initialValue: movie.title)
        _editedActors = State(initialValue: movie.actors ?? "")
        _editedCategory = State(initialValue: movie.category ?? "")
        _editedReleaseDate = State(initialValue: movie.releaseDate ?? "")
        _editedDescription = State(initialValue: movie.description ?? "")
        _manualImdbId = State(initialValue: movie.manualImdbId ?? movie.imdbId ?? "")
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
                        // Pattern match status
                        HStack {
                            Text("Pattern Matched:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            if movie.patternMatched == true {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Yes")
                                    .foregroundColor(.green)
                                if let confidence = movie.patternConfidence {
                                    Text("(\(Int(confidence * 100))% confidence)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.orange)
                                Text("No (fallback used)")
                                    .foregroundColor(.orange)
                            }
                        }

                        Divider()

                        Text("Values extracted from YouTube title:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Extracted Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Title")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Text(movie.title)
                                .font(.body)
                                .textSelection(.enabled)
                        }

                        // Extracted Actor
                        if let actor = movie.extractedActor {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Actor (from pattern)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(actor)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Actor (from pattern)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text("Not extracted")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        }

                        // Extracted Genre
                        if let genre = movie.extractedGenre {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Genre (from pattern)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(genre)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Genre (from pattern)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text("Not extracted")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        }

                        // Extracted Year
                        if let year = movie.extractedYear {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Year (from pattern)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(String(year))
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Year (from pattern)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text("Not extracted")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        }
                    }
                    .padding()
                }

                // TMDB/IMDB Enrichment Data
                GroupBox(label: Label("TMDB/IMDB Enrichment Data", systemImage: "film")) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                // Movie Poster (TMDB or OMDB)
                                if let posterPath = movie.posterPath {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Movie Poster")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                        // Handle both full URLs (OMDB) and paths (TMDB)
                                        let posterURL: URL? = {
                                            if posterPath.hasPrefix("http") {
                                                // Full URL from OMDB/IMDB
                                                return URL(string: posterPath)
                                            } else {
                                                // TMDB path - prepend CDN URL
                                                return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
                                            }
                                        }()

                                        AsyncImage(url: posterURL) { image in
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
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Source")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(movie.enrichmentSource?.uppercased() ?? "Not enriched")
                                                .font(.headline)
                                                .foregroundColor(movie.enrichmentSource != nil ? .blue : .secondary)
                                                .italic(movie.enrichmentSource == nil)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Confidence")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if let confidence = movie.enrichmentConfidence {
                                                Text(String(format: "%.0f%%", confidence * 100))
                                                    .font(.headline)
                                                    .foregroundColor(confidence > 0.8 ? .green : .orange)
                                            } else {
                                                Text("N/A")
                                                    .font(.headline)
                                                    .foregroundColor(.secondary)
                                                    .italic()
                                            }
                                        }
                                    }

                                    Divider()

                                    // IDs and Links
                                    HStack {
                                        Text("TMDB ID:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let tmdbId = movie.tmdbId {
                                            Text("\(tmdbId)")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Link(destination: URL(string: "https://www.themoviedb.org/movie/\(tmdbId)")!) {
                                                Image(systemName: "link")
                                                    .font(.caption)
                                            }
                                        } else {
                                            Text("Not available")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        // Manual IMDB Override - Always available
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Manual IMDB Override:")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)

                                            Text("Enter any IMDB ID to manually enrich this movie (works even if not yet enriched)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .italic()

                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("IMDB ID:")
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.secondary)
                                                    TextField("Enter IMDB ID (e.g., tt1234567)", text: $manualImdbId)
                                                        .textFieldStyle(.roundedBorder)
                                                        .font(.body)
                                                        .frame(width: 200)
                                                        .onChange(of: manualImdbId) { oldValue, newValue in
                                                            print("🎯 IMDB ID changed to: \(newValue)")
                                                            // Auto-enrich when user enters valid IMDB ID
                                                            if newValue.count >= 9 && newValue.hasPrefix("tt") && newValue.dropFirst(2).allSatisfy({ $0.isNumber }) {
                                                                print("✅ Valid IMDB ID detected, will enrich in 1 second...")
                                                                // Debounce: wait 1 second after user stops typing
                                                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                                    if manualImdbId == newValue && !isEnrichingFromIMDB {
                                                                        print("🚀 Triggering manual enrichment...")
                                                                        enrichFromManualIMDB()
                                                                    }
                                                                }
                                                            }
                                                        }
                                                }

                                            if !manualImdbId.isEmpty {
                                                Link(destination: URL(string: "https://www.imdb.com/title/\(manualImdbId)")!) {
                                                    Image(systemName: "link")
                                                        .font(.caption)
                                                }
                                            }

                                            Spacer()

                                            // Clear enrichment button
                                            Button(action: clearEnrichment) {
                                                HStack {
                                                    if isClearingEnrichment {
                                                        ProgressView()
                                                            .scaleEffect(0.8)
                                                    } else {
                                                        Image(systemName: "trash")
                                                    }
                                                    Text("Clear")
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .foregroundColor(.red)
                                            .disabled(isClearingEnrichment || !movie.hasEnrichment)
                                            .help("Remove incorrect enrichment data")

                                            // Status indicator
                                            if isEnrichingFromIMDB {
                                                HStack {
                                                    ProgressView()
                                                        .scaleEffect(0.8)
                                                    Text("Enriching...")
                                                        .font(.caption)
                                                        .foregroundColor(.blue)
                                                }
                                            } else if manualImdbId.count >= 9 && manualImdbId.hasPrefix("tt") {
                                                Text("Auto-enriches on save")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        }

                                        // Show verification status
                                        if movie.manuallyVerified == true {
                                            HStack {
                                                Image(systemName: "checkmark.seal.fill")
                                                    .foregroundColor(.green)
                                                Text("Manually verified")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                                if let verifiedBy = movie.verifiedBy {
                                                    Text("by \(verifiedBy)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }

                                    Divider()

                                    // Ratings
                                    HStack(spacing: 20) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("TMDB Rating")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if let tmdbRating = movie.voteAverage, let voteCount = movie.voteCount {
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
                                            } else {
                                                Text("Not available")
                                                    .font(.body)
                                                    .foregroundColor(.secondary)
                                                    .italic()
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("IMDB Rating")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if let imdbRating = movie.imdbRating, let imdbVotes = movie.imdbVotes {
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
                                            } else {
                                                Text("Not available")
                                                    .font(.body)
                                                    .foregroundColor(.secondary)
                                                    .italic()
                                            }
                                        }
                                    }

                                    Divider()

                                    // Additional Details
                                    HStack {
                                        Text("Rated:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let rated = movie.rated {
                                            Text(rated)
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.2))
                                                .cornerRadius(4)
                                        } else {
                                            Text("Not available")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        }
                                    }

                                    HStack {
                                        Text("Director:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(movie.director ?? "Not available")
                                            .font(.caption)
                                            .foregroundColor(movie.director != nil ? .primary : .secondary)
                                            .italic(movie.director == nil)
                                    }

                                    HStack {
                                        Text("Runtime:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let runtime = movie.runtimeMinutes {
                                            Text("\(runtime) minutes")
                                                .font(.caption)
                                        } else {
                                            Text("Not available")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        }
                                    }

                                    HStack {
                                        Text("Language:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(movie.language ?? "Not available")
                                            .font(.caption)
                                            .foregroundColor(movie.language != nil ? .primary : .secondary)
                                            .italic(movie.language == nil)
                                    }

                                    HStack {
                                        Text("Country:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(movie.country ?? "Not available")
                                            .font(.caption)
                                            .foregroundColor(movie.country != nil ? .primary : .secondary)
                                            .italic(movie.country == nil)
                                    }
                                }
                            }

                            // Plot/Description from enrichment
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Plot")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                if let description = movie.description, !description.isEmpty {
                                    Text(description)
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(6)
                                } else {
                                    Text("Not available")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .italic()
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.gray.opacity(0.05))
                                        .cornerRadius(6)
                                }
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
                    changesSaved = true

                    // Notify parent to refresh
                    onUpdate?()
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

    func enrichFromManualIMDB() {
        Task {
            isEnrichingFromIMDB = true
            error = nil
            successMessage = nil

            do {
                print("🎯 Enriching movie \(movie.id) from manual IMDB ID: \(manualImdbId)")

                // Call API to enrich from manual IMDB ID
                let updatedMovie = try await apiService.enrichFromManualIMDB(
                    movieId: movie.id,
                    imdbId: manualImdbId
                )

                successMessage = "✅ Movie enriched from IMDB \(manualImdbId) and marked as verified!"

                print("✅ Manual enrichment successful: \(updatedMovie.title)")

                // Update local fields with enriched data
                editedTitle = updatedMovie.title
                editedActors = updatedMovie.actors ?? ""
                editedCategory = updatedMovie.category ?? ""
                editedReleaseDate = updatedMovie.releaseDate ?? ""
                editedDescription = updatedMovie.description ?? ""

                // Notify parent to refresh
                onUpdate?()

                // Clear success message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    successMessage = nil
                }

            } catch {
                self.error = "Failed to enrich from IMDB: \(error.localizedDescription)"
                print("❌ Manual enrichment error: \(error)")
            }

            isEnrichingFromIMDB = false
        }
    }

    func clearEnrichment() {
        Task {
            isClearingEnrichment = true
            error = nil
            successMessage = nil

            do {
                print("🗑️ Clearing enrichment for movie \(movie.id)")

                // Call API to clear enrichment
                let updatedMovie = try await apiService.clearEnrichment(movieId: movie.id)

                successMessage = "✅ Enrichment cleared - movie reset to unenriched state"

                print("✅ Clear enrichment successful")

                // Clear local IMDB field
                manualImdbId = ""

                // Reset edited fields to show cleared state
                editedDescription = ""
                editedActors = updatedMovie.actors ?? ""
                editedCategory = updatedMovie.category ?? ""
                editedReleaseDate = updatedMovie.releaseDate ?? ""

                // Notify parent to refresh
                onUpdate?()

                // Clear success message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    successMessage = nil
                }

            } catch {
                self.error = "Failed to clear enrichment: \(error.localizedDescription)"
                print("❌ Clear enrichment error: \(error)")
            }

            isClearingEnrichment = false
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
            manualImdbId: nil,
            manuallyVerified: false,
            verifiedBy: nil,
            verifiedAt: nil,
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
            updatedAt: nil,
            patternMatched: true,
            patternConfidence: 0.95,
            extractedActor: "Rick Astley",
            extractedGenre: "Music",
            extractedYear: 1987,
            importSortOrder: "latest",
            importIndex: 0,
            channelTag: "music"
        )
    )
}
