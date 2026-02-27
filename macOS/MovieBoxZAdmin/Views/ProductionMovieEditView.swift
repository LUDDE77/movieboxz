import SwiftUI

struct ProductionMovieEditView: View {
    let movie: Movie
    let onSave: (Movie) -> Void
    let onCancel: () -> Void

    @StateObject private var apiService = AdminAPIService()
    @State private var allGenres: [Genre] = []

    // Editable fields
    @State private var title: String
    @State private var description: String
    @State private var releaseDate: String
    @State private var director: String
    @State private var actors: String
    @State private var runtime: String
    @State private var imdbRating: String
    @State private var imdbVotes: String
    @State private var isTvSeries: Bool
    @State private var isKidsContent: Bool
    @State private var selectedGenreIds: Set<Int>

    // Manual IMDB enrichment
    @State private var manualImdbId: String
    @State private var isEnrichingWithIMDB: Bool = false

    // Loading/error states
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    init(movie: Movie, onSave: @escaping (Movie) -> Void, onCancel: @escaping () -> Void) {
        self.movie = movie
        self.onSave = onSave
        self.onCancel = onCancel

        _title = State(initialValue: movie.title)
        _description = State(initialValue: movie.description ?? "")
        _releaseDate = State(initialValue: movie.releaseDate ?? "")
        _director = State(initialValue: movie.director ?? "")
        _actors = State(initialValue: movie.actors ?? "")
        _runtime = State(initialValue: movie.runtime.map { String($0) } ?? "")
        _imdbRating = State(initialValue: movie.imdbRating.map { String(format: "%.1f", $0) } ?? "")
        _imdbVotes = State(initialValue: movie.imdbVotes.map { String($0) } ?? "")
        _isTvSeries = State(initialValue: movie.isTvSeries ?? false)
        _isKidsContent = State(initialValue: movie.isKidsContent ?? false)
        _selectedGenreIds = State(initialValue: Set(movie.genres.map { $0.id }))
        _manualImdbId = State(initialValue: movie.imdbId ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Production Movie")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Original YouTube Title
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Original YouTube Title", systemImage: "play.rectangle")
                                .font(.headline)
                            Text(movie.youtubeVideoTitle)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    // Poster preview
                    if let posterPath = movie.posterPath {
                        HStack {
                            Spacer()
                            AsyncImage(url: posterURL(posterPath)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 150)
                            .cornerRadius(8)
                            Spacer()
                        }
                    }

                    // Basic Information
                    GroupBox("Basic Information") {
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Title")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Title", text: $title)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextEditor(text: $description)
                                    .frame(height: 120)
                                    .border(Color.gray.opacity(0.2))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Release Date (YYYY-MM-DD)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Release Date", text: $releaseDate)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(8)
                    }

                    // Manual IMDB Enrichment
                    GroupBox("Manual IMDB Enrichment") {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("IMDB ID (e.g., tt1234567)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("tt0000000", text: $manualImdbId)
                                        .textFieldStyle(.roundedBorder)
                                }

                                Button(action: {
                                    Task {
                                        await enrichWithManualIMDB()
                                    }
                                }) {
                                    if isEnrichingWithIMDB {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Label("Enrich", systemImage: "sparkles")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isEnrichingWithIMDB || !manualImdbId.starts(with: "tt"))
                            }

                            Text("⚠️ This will re-enrich the movie using the IMDB ID you provide")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(8)
                    }

                    // Genre Selection
                    GroupBox("Genres") {
                        if allGenres.isEmpty {
                            ProgressView("Loading genres...")
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(allGenres) { genre in
                                    Toggle(isOn: Binding(
                                        get: { selectedGenreIds.contains(genre.id) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedGenreIds.insert(genre.id)
                                            } else {
                                                selectedGenreIds.remove(genre.id)
                                            }
                                        }
                                    )) {
                                        Text(genre.name)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }

                    // Credits
                    GroupBox("Credits") {
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Director")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Director", text: $director)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Actors (comma-separated)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Actors", text: $actors)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(8)
                    }

                    // Movie Details
                    GroupBox("Movie Details") {
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Runtime (minutes)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Runtime", text: $runtime)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("IMDB Rating (0.0-10.0)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("Rating", text: $imdbRating)
                                        .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("IMDB Votes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("Votes", text: $imdbVotes)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        .padding(8)
                    }

                    // Classification
                    GroupBox("Classification") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $isTvSeries) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("TV Series")
                                        .font(.body)
                                    Text("Mark this video as a TV series instead of a movie")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Toggle(isOn: $isKidsContent) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Kids Content")
                                        .font(.body)
                                    Text("Mark this as appropriate for children")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(8)
                    }

                    // Metadata (Read-only)
                    GroupBox("Metadata (Read-only)") {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "YouTube ID", value: movie.youtubeVideoId)
                            if let tmdbId = movie.tmdbId {
                                InfoRow(label: "TMDB ID", value: String(tmdbId))
                            }
                            if let imdbId = movie.imdbId {
                                InfoRow(label: "Current IMDB ID", value: imdbId)
                            }
                            if let channelTitle = movie.channelTitle {
                                InfoRow(label: "Channel", value: channelTitle)
                            }
                        }
                        .padding(8)
                    }

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Save All Changes") {
                    Task {
                        await saveChanges()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || title.isEmpty)

                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.leading, 8)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 750, height: 900)
        .task {
            await loadGenres()
        }
    }

    func posterURL(_ path: String) -> URL? {
        if path.hasPrefix("http") {
            return URL(string: path)
        } else {
            return URL(string: "https://image.tmdb.org/t/p/w300\(path)")
        }
    }

    func loadGenres() async {
        print("📚 [ProductionMovieEditView] Loading genres...")
        do {
            let genresData = try await apiService.getGenres()
            allGenres = genresData.genres
            print("✅ [ProductionMovieEditView] Loaded \(allGenres.count) genres")
            print("📚 [ProductionMovieEditView] Genres: \(allGenres.map { $0.name }.joined(separator: ", "))")
        } catch {
            print("❌ [ProductionMovieEditView] Failed to load genres: \(error)")
        }
    }

    func enrichWithManualIMDB() async {
        guard manualImdbId.starts(with: "tt") else {
            errorMessage = "IMDB ID must start with 'tt'"
            return
        }

        print("🎯 [ProductionMovieEditView] Starting manual IMDB enrichment")
        print("🎯 [ProductionMovieEditView] Movie ID: \(movie.id)")
        print("🎯 [ProductionMovieEditView] IMDB ID: \(manualImdbId)")

        isEnrichingWithIMDB = true
        errorMessage = nil

        do {
            let updatedMovie = try await apiService.enrichProductionMovieWithManualIMDB(
                movieId: movie.id,
                imdbId: manualImdbId
            )

            print("✅ [ProductionMovieEditView] Enrichment successful")
            print("📊 [ProductionMovieEditView] Updated movie title: \(updatedMovie.title)")
            print("📊 [ProductionMovieEditView] Updated movie genres count: \(updatedMovie.genres.count)")
            print("📊 [ProductionMovieEditView] Genres: \(updatedMovie.genres.map { $0.name }.joined(separator: ", "))")

            // Update local fields with enriched data
            title = updatedMovie.title
            description = updatedMovie.description ?? ""
            releaseDate = updatedMovie.releaseDate ?? ""
            director = updatedMovie.director ?? ""
            actors = updatedMovie.actors ?? ""
            runtime = updatedMovie.runtime.map { String($0) } ?? ""
            imdbRating = updatedMovie.imdbRating.map { String(format: "%.1f", $0) } ?? ""
            imdbVotes = updatedMovie.imdbVotes.map { String($0) } ?? ""
            selectedGenreIds = Set(updatedMovie.genres.map { $0.id })

            print("✅ [ProductionMovieEditView] Local fields updated")

            // Call onSave with updated movie
            onSave(updatedMovie)
            onCancel()

        } catch {
            print("❌ [ProductionMovieEditView] Enrichment failed: \(error)")
            print("❌ [ProductionMovieEditView] Error details: \(error.localizedDescription)")
            errorMessage = "Failed to enrich: \(error.localizedDescription)"
        }

        isEnrichingWithIMDB = false
    }

    func saveChanges() async {
        isSaving = true
        errorMessage = nil

        do {
            // Step 1: Update basic fields
            var updates: [String: Any] = [:]

            if title != movie.title {
                updates["title"] = title
            }
            if description != (movie.description ?? "") {
                updates["description"] = description
            }
            if releaseDate != (movie.releaseDate ?? "") {
                updates["release_date"] = releaseDate
            }
            if director != (movie.director ?? "") {
                updates["director"] = director
            }
            if actors != (movie.actors ?? "") {
                updates["actors"] = actors
            }
            if isTvSeries != (movie.isTvSeries ?? false) {
                updates["is_tv_series"] = isTvSeries
            }
            if isKidsContent != (movie.isKidsContent ?? false) {
                updates["is_kids_content"] = isKidsContent
            }

            var updatedMovie = movie

            if !updates.isEmpty {
                updatedMovie = try await apiService.updateProductionMovie(movieId: movie.id, updates: updates)
            }

            // Step 2: Update genres if changed
            let currentGenreIds = Set(movie.genres.map { $0.id })
            if selectedGenreIds != currentGenreIds {
                updatedMovie = try await apiService.updateProductionMovieGenres(
                    movieId: movie.id,
                    genreIds: selectedGenreIds.map { String($0) }
                )
            }

            onSave(updatedMovie)
            onCancel()

        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
