import SwiftUI

struct FeaturedBanner: View {
    let movie: Movie
    let width: CGFloat
    let height: CGFloat
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear

            // Content overlay
            VStack(alignment: .leading, spacing: 10) {
                // Title
                Text(movie.displayTitle)
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)

                // Metadata pills
                HStack(spacing: 8) {
                    if let year = movie.formattedReleaseYear {
                        MetaPill(text: year)
                    }
                    if let rating = movie.voteAverage ?? movie.imdbRating {
                        MetaPill(text: "★ \(String(format: "%.1f", rating))", color: .yellow)
                    }
                    if let runtime = movie.runtimeMinutes, runtime > 0 {
                        MetaPill(text: movie.formattedRuntime)
                    }
                }

                // Description
                if let desc = movie.description {
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                }

                // Watch button
                Button(action: onPlay) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.red)
                        Text("Watch on YouTube")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: min(width * 0.6, 500), alignment: .leading)
        }
        .frame(width: width, height: height)
    }
}

private struct MetaPill: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.18))
            .cornerRadius(5)
    }
}
