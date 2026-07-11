import SwiftUI

struct MovieDetailView: View {
    let movie: Movie
    @Environment(\.dismiss) private var dismiss
    @State private var showPlayer = false

    // Fixed landscape header — app is landscape-only
    private let headerH: CGFloat = 200
    private let posterW: CGFloat = 90
    private let posterH: CGFloat = 135

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    FavoriteButton(movieId: movie.id, movieTitle: movie.displayTitle, posterURL: movie.posterURL?.absoluteString)
                        .padding(.top, 12)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.9))
                            .background(Circle().fill(Color.black.opacity(0.4)).frame(width: 40, height: 40))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                }
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
        }
        .sheet(isPresented: $showPlayer) {
            VideoPlayerView(movie: movie)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop
            AsyncImage(url: movie.backdropURL) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: headerH)
            .clipped()

            // Gradient
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: headerH)

            // Poster + title
            HStack(alignment: .bottom, spacing: 14) {
                AsyncImage(url: movie.posterURL) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.4)
                    }
                }
                .frame(width: posterW, height: posterH)
                .cornerRadius(8)
                .shadow(radius: 8)
                .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(movie.displayTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .shadow(radius: 4)
                }
                .padding(.bottom, 16)

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .frame(height: headerH)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Play button
            Button {
                LibraryManager.shared.trackWatch(movieId: movie.id, movieTitle: movie.displayTitle, posterURL: movie.posterURL)
                showPlayer = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill").foregroundColor(.red)
                    Text("Watch on YouTube").fontWeight(.semibold)
                }
                .font(.system(size: 16))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            // Secondary actions
            HStack(spacing: 12) {
                ActionButton(icon: "bookmark", label: "Save") {
                    LibraryManager.shared.toggleFavorite(movie.id)
                }
                ActionButton(icon: "square.and.arrow.up", label: "Share") {
                    shareMovie()
                }
            }

            // Metadata
            HStack(spacing: 10) {
                if let rt = movie.runtimeMinutes, rt > 0 {
                    Text(movie.formattedRuntime).metaStyle()
                }
                if let r = movie.voteAverage ?? movie.imdbRating {
                    Text("★ \(String(format: "%.1f", r))").metaStyle()
                }
                if let yr = movie.formattedReleaseYear {
                    Text(yr).metaStyle()
                }
                if let q = movie.quality {
                    Text(q).metaStyle(highlight: true)
                }
                Spacer()
            }

            // Description
            if let desc = movie.description {
                Text(desc)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(4)
            }

            // Genres
            if let genres = movie.genres, !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres) { g in
                            Text(g.name)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(LinearGradient(colors: [.red.opacity(0.4), .purple.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(16)
                        }
                    }
                }
            }

            // YouTube attribution
            Divider().background(Color.white.opacity(0.2))
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Powered by YouTube")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Channel: \(movie.channelTitle)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)

            // TOS notice
            Text("This content is hosted on YouTube. MovieBoxZ does not host or stream any video content.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 60)
    }

    private func shareMovie() {
        guard let url = movie.youtubeURL else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(vc, animated: true)
        }
    }
}

// MARK: - Helpers

private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.15))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

private extension Text {
    func metaStyle(highlight: Bool = false) -> some View {
        self
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(highlight ? .green : .white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.12))
            .cornerRadius(5)
    }
}
