import SwiftUI

struct MoviesView: View {
    @StateObject private var apiService = AdminAPIService()
    @State private var movies: [Movie] = []
    @State private var selectedMovie: Movie.ID?
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchText = ""
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var sortOrder = [KeyPathComparator(\Movie.title)]
    @State private var editingMovie: Movie?
    @State private var showEditSheet = false
    @State private var showColumnPicker = false
    @State private var visibleColumns = ColumnSet.default

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
            Divider()
            paginationView
        }
        .sheet(isPresented: $showEditSheet) {
            if let movie = editingMovie {
                MovieEditView(movie: movie, onSave: { _ in
                    showEditSheet = false
                })
            }
        }
        .task {
            await loadMovies()
        }
    }

    private var headerView: some View {
        HStack {
            TextField("Search movies...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .onSubmit {
                    Task {
                        currentPage = 1
                        await loadMovies()
                    }
                }

            Spacer()

            Button(action: { showColumnPicker.toggle() }) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text("Columns")
            }
            .popover(isPresented: $showColumnPicker) {
                ColumnPickerView(visibleColumns: $visibleColumns)
            }

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding()
    }

    private var contentView: some View {
        Group {
            if let error = error {
                errorView(error)
            } else if movies.isEmpty && !isLoading {
                emptyView
            } else {
                tableView
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack {
            Text("Error loading movies")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        Text("No movies found")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tableView: some View {
        Table(movies, selection: $selectedMovie, sortOrder: $sortOrder) {
            TableColumn("Title", value: \Movie.title) { movie in
                VStack(alignment: .leading, spacing: 4) {
                    Text(movie.displayTitle)
                        .font(.body)
                        .lineLimit(1)
                    if let channel = movie.channelTitle {
                        Text(channel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 200, ideal: 300)

            TableColumn("Channel") { movie in
                Text(movie.channelTitle ?? "Unknown")
                    .font(.caption)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Release") { movie in
                Text(movie.releaseYear.map { "\($0)" } ?? "—")
                    .foregroundColor(movie.releaseYear == nil ? .secondary : .primary)
            }
            .width(min: 70, ideal: 80)

            TableColumn("Runtime") { movie in
                Text(movie.runtime.map { "\($0) min" } ?? "—")
                    .foregroundColor(movie.runtime == nil ? .secondary : .primary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Rating") { movie in
                if let rating = movie.rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text(String(format: "%.1f", rating))
                    }
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 70, ideal: 90)

            TableColumn("Genres") { movie in
                Text(movie.genres.map { $0.name }.joined(separator: ", "))
                    .font(.caption)
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 200)

            TableColumn("Status") { movie in
                Text(movie.status)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor(for: movie.status).opacity(0.2))
                    .cornerRadius(4)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Views") { movie in
                Text("\(movie.viewCount)")
                    .font(.caption)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Likes") { movie in
                Text("\(movie.likeCount)")
                    .font(.caption)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Actions") { movie in
                HStack(spacing: 8) {
                    if let url = movie.youtubeURL {
                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Open on YouTube")
                    }

                    Button(action: {
                        editingMovie = movie
                        showEditSheet = true
                    }) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("Edit movie")
                }
            }
            .width(min: 80, ideal: 100)
        }
        .onChange(of: sortOrder) { _, newOrder in
            movies.sort(using: newOrder)
        }
    }

    private var paginationView: some View {
        HStack {
            Text("Page \(currentPage) of \(totalPages)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("Previous") {
                if currentPage > 1 {
                    currentPage -= 1
                    Task { await loadMovies() }
                }
            }
            .disabled(currentPage <= 1)

            Button("Next") {
                if currentPage < totalPages {
                    currentPage += 1
                    Task { await loadMovies() }
                }
            }
            .disabled(currentPage >= totalPages)
        }
        .padding()
    }

    private func loadMovies() async {
        isLoading = true
        error = nil

        do {
            let data = try await apiService.getMovies(
                page: currentPage,
                limit: 50,
                search: searchText.isEmpty ? nil : searchText
            )
            movies = data.movies
            totalPages = data.pagination.pages ?? 1
            movies.sort(using: sortOrder)
        } catch {
            self.error = error.localizedDescription
            print("Error loading movies: \(error)")
        }

        isLoading = false
    }

    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "available":
            return .green
        case "unavailable":
            return .red
        case "processing":
            return .orange
        default:
            return .gray
        }
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

// MARK: - Column Visibility
struct ColumnSet {
    var title = true
    var originalTitle = false
    var channel = true
    var release = true
    var runtime = true
    var rating = true
    var imdbVotes = false
    var genres = true
    var category = false
    var quality = false
    var language = false
    var rated = false
    var director = false
    var actors = false
    var country = false
    var tmdb = false
    var imdb = true
    var status = true
    var views = true
    var likes = true
    var comments = false
    var isTvShow = false
    var featured = false
    var trending = false
    var staffPick = false
    var published = false
    var added = false
    var validated = false
    var description = false
    var actions = true

    static var `default`: ColumnSet {
        ColumnSet()
    }
}

// MARK: - Column Picker
struct ColumnPickerView: View {
    @Binding var visibleColumns: ColumnSet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Show/Hide Columns")
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Title", isOn: $visibleColumns.title)
                    Toggle("Original Title", isOn: $visibleColumns.originalTitle)
                    Toggle("Channel", isOn: $visibleColumns.channel)
                    Toggle("Release Year", isOn: $visibleColumns.release)
                    Toggle("Runtime", isOn: $visibleColumns.runtime)
                    Toggle("Rating", isOn: $visibleColumns.rating)
                    Toggle("IMDB Votes", isOn: $visibleColumns.imdbVotes)
                    Toggle("Genres", isOn: $visibleColumns.genres)
                    Toggle("Category", isOn: $visibleColumns.category)
                    Toggle("Quality", isOn: $visibleColumns.quality)
                    Toggle("Language", isOn: $visibleColumns.language)
                    Toggle("Rated", isOn: $visibleColumns.rated)
                    Toggle("Director", isOn: $visibleColumns.director)
                    Toggle("Actors", isOn: $visibleColumns.actors)
                    Toggle("Country", isOn: $visibleColumns.country)
                    Toggle("TMDB ID", isOn: $visibleColumns.tmdb)
                    Toggle("IMDB ID", isOn: $visibleColumns.imdb)
                    Toggle("Status", isOn: $visibleColumns.status)
                    Toggle("Views", isOn: $visibleColumns.views)
                    Toggle("Likes", isOn: $visibleColumns.likes)
                    Toggle("Comments", isOn: $visibleColumns.comments)
                    Toggle("Type (Movie/TV)", isOn: $visibleColumns.isTvShow)
                    Toggle("Featured", isOn: $visibleColumns.featured)
                    Toggle("Trending", isOn: $visibleColumns.trending)
                    Toggle("Staff Pick", isOn: $visibleColumns.staffPick)
                    Toggle("Published Date", isOn: $visibleColumns.published)
                    Toggle("Added Date", isOn: $visibleColumns.added)
                    Toggle("Validated Date", isOn: $visibleColumns.validated)
                    Toggle("Description", isOn: $visibleColumns.description)
                    Toggle("Actions", isOn: $visibleColumns.actions)
                }
                .padding()
            }
        }
        .frame(width: 300, height: 500)
    }
}

// MARK: - Movie Edit View
struct MovieEditView: View {
    let movie: Movie
    let onSave: (Movie) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var title: String
    @State private var description: String

    init(movie: Movie, onSave: @escaping (Movie) -> Void) {
        self.movie = movie
        self.onSave = onSave
        _title = State(initialValue: movie.title)
        _description = State(initialValue: movie.description ?? "")
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Movie")
                .font(.headline)

            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(5...10)
            }
            .padding()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    // TODO: Implement save to API
                    onSave(movie)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 300)
        .padding()
    }
}

#Preview {
    MoviesView()
}
