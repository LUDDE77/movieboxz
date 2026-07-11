import SwiftUI

struct TVSeriesView: View {
    @StateObject private var movieService = MovieService()
    @State private var movies: [Movie] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedMovie: Movie?

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 14)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "tv")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TV Series")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        if !isLoading && error == nil {
                            Text("\(movies.count) \(movies.count == 1 ? "series" : "series")")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if isLoading {
                    Spacer()
                    ProgressView().tint(.white).scaleEffect(1.5)
                    Spacer()
                } else if let err = error {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50)).foregroundColor(.red)
                        Text(err).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await load() } }
                            .foregroundColor(.white).padding(.horizontal, 24).padding(.vertical, 10)
                            .background(Color.red).cornerRadius(8)
                    }
                    .padding()
                    Spacer()
                } else if movies.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "tv")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No TV Series Yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(movies) { movie in
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
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            movies = try await movieService.fetchTVSeries()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
