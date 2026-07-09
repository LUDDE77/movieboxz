import SwiftUI

// MARK: - TV Series Filter

enum TVSeriesFilter: String, CaseIterable {
    case all = "All"
    case tvSeries = "TV Series"
    case miniSeries = "Mini-Series"
    case unassigned = "Unassigned"
}

// MARK: - Group model

struct TVShowGroup: Identifiable {
    let title: String
    var movies: [Movie]

    var id: String { title }

    var episodeCount: Int { movies.count }

    var seriesTypeBadge: String {
        // Determine predominant series type
        let types = movies.compactMap { $0.seriesType }
        if types.isEmpty { return "Unset" }
        let tvCount = types.filter { $0 == "tv_series" }.count
        let miniCount = types.filter { $0 == "mini_series" }.count
        if tvCount >= miniCount { return "TV Series" }
        return "Mini-Series"
    }

    var badgeColor: Color {
        switch seriesTypeBadge {
        case "TV Series": return .blue
        case "Mini-Series": return .purple
        default: return .gray
        }
    }
}

// MARK: - TVSeriesView

struct TVSeriesView: View {
    @StateObject private var apiService = AdminAPIService()

    @State private var tvMovies: [Movie] = []
    @State private var seriesList: [TvSeries] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedFilter: TVSeriesFilter = .all
    @State private var selectedMovie: Movie?
    @State private var expandedGroups: Set<String> = []

    // Detail panel state
    @State private var editSeason: Int = 1
    @State private var editEpisode: Int = 1
    @State private var editSeriesType: String = ""
    @State private var editTvSeriesId: String = ""
    @State private var editIsTvShow: Bool = false
    @State private var editIsTvSeries: Bool = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saveSuccess = false

    // Create series sheet
    @State private var showCreateSeriesSheet = false
    @State private var newSeriesTitle = ""
    @State private var newSeriesImdbId = ""
    @State private var newSeriesDescription = ""
    @State private var isCreatingSeries = false
    @State private var createSeriesError: String?

    var filteredGroups: [TVShowGroup] {
        let grouped = Dictionary(grouping: tvMovies, by: { $0.title })
        var groups = grouped.map { title, movies -> TVShowGroup in
            TVShowGroup(title: title, movies: movies.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) })
        }
        .sorted { $0.title < $1.title }

        switch selectedFilter {
        case .all:
            return groups
        case .tvSeries:
            return groups.filter { group in
                group.movies.contains { $0.seriesType == "tv_series" }
            }
        case .miniSeries:
            return groups.filter { group in
                group.movies.contains { $0.seriesType == "mini_series" }
            }
        case .unassigned:
            return groups.filter { group in
                group.movies.contains { $0.seriesType == nil || $0.seriesType?.isEmpty == true }
            }
        }
    }

    var body: some View {
        HSplitView {
            // Left panel: grouped list
            leftPanel
                .frame(minWidth: 280, maxWidth: 380)

            // Right panel: detail editor
            rightPanel
                .frame(minWidth: 400)
        }
        .navigationTitle("TV Series")
        .task {
            await loadData()
        }
        .sheet(isPresented: $showCreateSeriesSheet) {
            createSeriesSheet
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Filter picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(TVSeriesFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            if isLoading {
                ProgressView("Loading TV content...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack(spacing: 8) {
                    Text("Error loading TV content")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await loadData() }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredGroups.isEmpty {
                Text("No TV content found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { selectedMovie?.id },
                    set: { id in
                        if let id = id {
                            selectedMovie = tvMovies.first { $0.id == id }
                            if let movie = selectedMovie {
                                populateEditFields(from: movie)
                            }
                        }
                    }
                )) {
                    ForEach(filteredGroups) { group in
                        Section {
                            if expandedGroups.contains(group.id) {
                                ForEach(group.movies) { movie in
                                    episodeRow(movie: movie)
                                        .tag(movie.id)
                                }
                            }
                        } header: {
                            groupHeader(group: group)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func groupHeader(group: TVShowGroup) -> some View {
        Button(action: {
            if expandedGroups.contains(group.id) {
                expandedGroups.remove(group.id)
            } else {
                expandedGroups.insert(group.id)
            }
        }) {
            HStack {
                Image(systemName: expandedGroups.contains(group.id) ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(group.episodeCount) episode\(group.episodeCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(group.seriesTypeBadge)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(group.badgeColor.opacity(0.15))
                    .foregroundColor(group.badgeColor)
                    .cornerRadius(4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private func episodeRow(movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(movie.youtubeVideoTitle)
                .font(.subheadline)
                .lineLimit(2)

            HStack(spacing: 6) {
                if let season = movie.seasonNumber {
                    Text("S\(season)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let episode = movie.episodeNumber {
                    Text("E\(episode)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let seriesType = movie.seriesType {
                    Text(seriesType == "tv_series" ? "TV" : "Mini")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(3)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        Group {
            if let movie = selectedMovie {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Movie info header
                        movieInfoHeader(movie: movie)

                        Divider()

                        // TV Series assignment
                        tvSeriesAssignmentSection

                        Divider()

                        // Episode metadata
                        episodeMetadataSection

                        Divider()

                        // Flags
                        flagsSection(movie: movie)

                        Divider()

                        // Save button
                        saveSection
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "tv.and.mediabox")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select an episode to edit its TV series info")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Expand a show group in the left panel and click an episode.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func movieInfoHeader(movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(movie.title)
                .font(.title2)
                .fontWeight(.bold)

            Text(movie.youtubeVideoTitle)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let imdbId = movie.imdbId {
                HStack(spacing: 4) {
                    Text("IMDB:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(imdbId)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            if let channelTitle = movie.channelTitle {
                HStack(spacing: 4) {
                    Text("Channel:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(channelTitle)
                        .font(.caption)
                }
            }
        }
    }

    private var tvSeriesAssignmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TV Series Assignment")
                .font(.headline)

            HStack {
                Picker("Assign to Series", selection: $editTvSeriesId) {
                    Text("None").tag("")
                    ForEach(seriesList) { series in
                        Text(series.title).tag(series.id)
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: { showCreateSeriesSheet = true }) {
                    Label("Create New Series", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var episodeMetadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Episode Metadata")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Season")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Stepper("", value: $editSeason, in: 1...99)
                            .labelsHidden()
                        TextField("Season", value: $editSeason, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Episode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Stepper("", value: $editEpisode, in: 1...999)
                            .labelsHidden()
                        TextField("Episode", value: $editEpisode, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Series Type")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Series Type", selection: $editSeriesType) {
                    Text("Not Set").tag("")
                    Text("TV Series").tag("tv_series")
                    Text("Mini-Series").tag("mini_series")
                }
                .pickerStyle(.radioGroup)
            }
        }
    }

    private func flagsSection(movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Flags")
                .font(.headline)

            Toggle("Is TV Show", isOn: $editIsTvShow)
            Toggle("Is TV Series", isOn: $editIsTvSeries)
        }
    }

    private var saveSection: some View {
        VStack(spacing: 8) {
            if let saveError = saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if saveSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved successfully")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            HStack {
                Spacer()
                Button(action: {
                    if let movie = selectedMovie {
                        populateEditFields(from: movie)
                    }
                }) {
                    Text("Reset")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    Task { await saveChanges() }
                }) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 80)
                    } else {
                        Text("Save Changes")
                            .frame(width: 80)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
    }

    // MARK: - Create Series Sheet

    private var createSeriesSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New TV Series")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Title *")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Series title", text: $newSeriesTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("IMDB ID (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. tt1234567", text: $newSeriesImdbId)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $newSeriesDescription)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            if let createSeriesError = createSeriesError {
                Text(createSeriesError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Button("Cancel") {
                    showCreateSeriesSheet = false
                    clearCreateSeriesForm()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    Task { await createNewSeries() }
                }) {
                    if isCreatingSeries {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Create Series")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newSeriesTitle.trimmingCharacters(in: .whitespaces).isEmpty || isCreatingSeries)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        error = nil

        do {
            async let moviesTask = apiService.getTVContent()
            async let seriesTask = apiService.getAdminTVSeriesList()

            let (movies, series) = try await (moviesTask, seriesTask)
            tvMovies = movies
            seriesList = series
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Edit Helpers

    private func populateEditFields(from movie: Movie) {
        editSeason = movie.seasonNumber ?? 1
        editEpisode = movie.episodeNumber ?? 1
        editSeriesType = movie.seriesType ?? ""
        editTvSeriesId = movie.tvSeriesId ?? ""
        editIsTvShow = movie.isTvShow ?? false
        editIsTvSeries = movie.isTvSeries ?? false
        saveError = nil
        saveSuccess = false
    }

    private func saveChanges() async {
        guard let movie = selectedMovie else { return }

        isSaving = true
        saveError = nil
        saveSuccess = false

        do {
            let tvSeriesIdToSend: String? = editTvSeriesId.isEmpty ? nil : editTvSeriesId
            let seriesTypeToSend: String? = editSeriesType.isEmpty ? nil : editSeriesType

            let updatedMovie = try await apiService.updateMovieTVInfo(
                movieId: movie.id,
                seasonNumber: editSeason,
                episodeNumber: editEpisode,
                seriesType: seriesTypeToSend,
                tvSeriesId: tvSeriesIdToSend,
                isTvShow: editIsTvShow,
                isTvSeries: editIsTvSeries
            )

            // Update local state
            if let idx = tvMovies.firstIndex(where: { $0.id == updatedMovie.id }) {
                tvMovies[idx] = updatedMovie
            }
            selectedMovie = updatedMovie
            saveSuccess = true

            // Auto-clear success after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveSuccess = false
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }

    private func createNewSeries() async {
        isCreatingSeries = true
        createSeriesError = nil

        do {
            let newSeries = try await apiService.createAdminTVSeries(
                title: newSeriesTitle.trimmingCharacters(in: .whitespaces),
                imdbId: newSeriesImdbId.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newSeriesImdbId.trimmingCharacters(in: .whitespaces),
                description: newSeriesDescription.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newSeriesDescription.trimmingCharacters(in: .whitespaces)
            )

            seriesList.append(newSeries)
            seriesList.sort { $0.title < $1.title }

            // Auto-assign the new series to the selected movie
            editTvSeriesId = newSeries.id

            showCreateSeriesSheet = false
            clearCreateSeriesForm()
        } catch {
            createSeriesError = error.localizedDescription
        }

        isCreatingSeries = false
    }

    private func clearCreateSeriesForm() {
        newSeriesTitle = ""
        newSeriesImdbId = ""
        newSeriesDescription = ""
        createSeriesError = nil
    }
}

#Preview {
    TVSeriesView()
}
