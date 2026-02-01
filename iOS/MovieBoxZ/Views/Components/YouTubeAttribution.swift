import SwiftUI

// MARK: - YouTube Attribution Component
// TOS-compliant YouTube attribution display

struct YouTubeAttribution: View {
    let movie: Movie
    let style: AttributionStyle

    enum AttributionStyle {
        case compact    // For movie cards
        case full       // For detail views
    }

    var body: some View {
        switch style {
        case .compact:
            compactAttribution
        case .full:
            fullAttribution
        }
    }

    // MARK: - Compact Attribution (Cards)

    private var compactAttribution: some View {
        HStack(spacing: 6) {
            // YouTube logo
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.red)

            // Channel name
            Text("on \(movie.channelTitle)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Full Attribution (Detail View)

    private var fullAttribution: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Text("YouTube Video")
                .font(.headline)
                .foregroundColor(.primary)

            // YouTube video card
            HStack(spacing: 12) {
                // YouTube thumbnail
                AsyncImage(url: movie.youtubeThumbURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    case .failure, .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(16/9, contentMode: .fill)
                            .overlay {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundColor(.red)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                #if os(tvOS)
                .frame(width: 240, height: 135)
                #else
                .frame(width: 120, height: 68)
                #endif
                .cornerRadius(8)

                // Video info
                VStack(alignment: .leading, spacing: 8) {
                    // YouTube video title (REQUIRED by TOS)
                    Text(movie.youtubeVideoTitle)
                        #if os(tvOS)
                        .font(.body)
                        #else
                        .font(.caption)
                        #endif
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    // Channel info (clickable)
                    Button(action: openChannel) {
                        HStack(spacing: 8) {
                            // Channel thumbnail
                            if let thumbURL = movie.channelThumbnail {
                                AsyncImage(url: URL(string: thumbURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                }
                                #if os(tvOS)
                                .frame(width: 32, height: 32)
                                #else
                                .frame(width: 20, height: 20)
                                #endif
                                .clipShape(Circle())
                            }

                            // Channel name
                            Text(movie.channelTitle)
                                #if os(tvOS)
                                .font(.callout)
                                #else
                                .font(.caption)
                                #endif
                                .foregroundColor(.primary)

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    // YouTube stats
                    HStack(spacing: 12) {
                        Label(movie.formattedViewCount, systemImage: "eye.fill")

                        if let likes = movie.likeCount {
                            Label("\(likes >= 1000 ? String(format: "%.1fK", Double(likes) / 1000) : "\(likes)")", systemImage: "hand.thumbsup.fill")
                        }
                    }
                    #if os(tvOS)
                    .font(.callout)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }

    // MARK: - Actions

    private func openChannel() {
        YouTubePlayerService.shared.openChannel(channelID: movie.channelId)
    }
}

// MARK: - Preview

#Preview("Compact") {
    VStack {
        YouTubeAttribution(
            movie: Movie(
                id: "1",
                youtubeVideoId: "test123",
                title: "The Matrix",
                originalTitle: nil,
                description: "A computer hacker learns from mysterious rebels about the true nature of his reality.",
                releaseDate: nil,
                runtimeMinutes: 136,
                youtubeVideoTitle: "FREE FULL MOVIE - The Matrix (1999) HD Quality",
                channelId: "UC123",
                channelTitle: "Paramount Movies",
                channelThumbnail: nil,
                viewCount: 12500000,
                likeCount: 45000,
                commentCount: 1200,
                publishedAt: nil,
                lastRefreshed: Date(),
                tmdbId: 603,
                imdbId: "tt0133093",
                posterPath: nil,
                backdropPath: nil,
                voteAverage: 8.7,
                voteCount: 25000,
                popularity: 100.0,
                imdbRating: nil,
                rated: nil,
                category: "action",
                quality: "HD",
                featured: true,
                trending: true,
                isAvailable: true,
                isEmbeddable: true,
                genres: nil,
                addedAt: Date(),
                lastValidated: Date()
            ),
            style: .compact
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Full") {
    ScrollView {
        YouTubeAttribution(
            movie: Movie(
                id: "1",
                youtubeVideoId: "test123",
                title: "The Matrix",
                originalTitle: nil,
                description: "A computer hacker learns from mysterious rebels about the true nature of his reality.",
                releaseDate: nil,
                runtimeMinutes: 136,
                youtubeVideoTitle: "FREE FULL MOVIE - The Matrix (1999) HD Quality",
                channelId: "UC123",
                channelTitle: "Paramount Movies",
                channelThumbnail: "https://example.com/thumb.jpg",
                viewCount: 12500000,
                likeCount: 45000,
                commentCount: 1200,
                publishedAt: nil,
                lastRefreshed: Date(),
                tmdbId: 603,
                imdbId: "tt0133093",
                posterPath: nil,
                backdropPath: nil,
                voteAverage: 8.7,
                voteCount: 25000,
                popularity: 100.0,
                imdbRating: nil,
                rated: nil,
                category: "action",
                quality: "HD",
                featured: true,
                trending: true,
                isAvailable: true,
                isEmbeddable: true,
                genres: nil,
                addedAt: Date(),
                lastValidated: Date()
            ),
            style: .full
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
