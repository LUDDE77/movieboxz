import SwiftUI

struct SearchView: View {
    @StateObject private var service = MovieService()
    @State private var query = ""
    @State private var results: [Movie] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var selectedMovie: Movie?

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 14)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.5))

                    TextField("Search movies...", text: $query)
                        .foregroundColor(.white)
                        .tint(.red)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }

                    if !query.isEmpty {
                        Button { query = ""; results = []; hasSearched = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)

                // Results
                if isSearching {
                    Spacer()
                    ProgressView().tint(.white).scaleEffect(1.5)
                    Spacer()
                } else if !hasSearched {
                    emptyState(icon: "magnifyingglass", title: "Search Movies", subtitle: "Type a title to find movies")
                } else if results.isEmpty {
                    emptyState(icon: "magnifyingglass", title: "No Results", subtitle: "Try a different search term")
                } else {
                    Text("\(results.count) results for \"\(query)\"")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(results) { movie in
                                MovieCard(movie: movie, onTap: { selectedMovie = movie })
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 60)
                    }
                }
            }
        }
        .sheet(item: $selectedMovie) { MovieDetailView(movie: $0) }
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        hasSearched = true
        results = (try? await service.searchMovies(query: query)) ?? []
        isSearching = false
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon).font(.system(size: 60)).foregroundColor(.white.opacity(0.3))
            Text(title).font(.title3).fontWeight(.semibold).foregroundColor(.white.opacity(0.6))
            Text(subtitle).font(.subheadline).foregroundColor(.white.opacity(0.4))
            Spacer()
        }
    }
}
