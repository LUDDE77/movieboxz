import SwiftUI

struct MovieCard: View {
    let movie: Movie
    let onTap: () -> Void

    private let cardW: CGFloat = 110
    private let cardH: CGFloat = 165

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                // Poster
                AsyncImage(url: movie.posterURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    case .empty:
                        Color.gray.opacity(0.3).shimmer()
                    default:
                        // YouTube thumbnail fallback
                        AsyncImage(url: movie.youtubeThumbURL) { p in
                            if case .success(let img) = p {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                posterPlaceholder
                            }
                        }
                    }
                }
                .frame(width: cardW, height: cardH)
                .cornerRadius(7)
                .clipped()

                // Title
                Text(movie.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(width: cardW, alignment: .leading)

                // Rating + year
                HStack(spacing: 4) {
                    if let r = movie.voteAverage ?? movie.imdbRating {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", r))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    if let yr = movie.formattedReleaseYear {
                        Text("•")
                            .foregroundColor(.white.opacity(0.4))
                            .font(.system(size: 10))
                        Text(yr)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(width: cardW, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .frame(width: cardW)
        .contextMenu {
            Button {
                LibraryManager.shared.toggleFavorite(movie.id)
            } label: {
                Label(LibraryManager.shared.isFavorite(movie.id) ? "Remove from Favourites" : "Add to Favourites",
                      systemImage: LibraryManager.shared.isFavorite(movie.id) ? "heart.slash" : "heart")
            }
            Button {
                YouTubeService.shared.playMovie(movie)
            } label: {
                Label("Watch on YouTube", systemImage: "play.rectangle")
            }
        }
    }

    private var posterPlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "film")
                .font(.title2)
                .foregroundColor(.gray)
        }
    }
}
