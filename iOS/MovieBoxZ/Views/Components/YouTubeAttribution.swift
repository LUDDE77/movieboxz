import SwiftUI

// MARK: - YouTube Attribution Component
// TOS-compliant attribution for YouTube content

struct YouTubeAttribution: View {
    let movie: Movie
    let style: AttributionStyle
    
    enum AttributionStyle {
        case compact  // Single line with channel name
        case full     // Multi-line with channel thumbnail and link
    }
    
    var body: some View {
        switch style {
        case .compact:
            compactView
        case .full:
            fullView
        }
    }
    
    // MARK: - Compact View
    
    private var compactView: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.rectangle.fill")
                .foregroundColor(.red)
                .font(.caption)
            
            Text("on ")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(movie.channelTitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .accessibilityLabel("Hosted on \(movie.channelTitle) YouTube channel")
    }
    
    // MARK: - Full View
    
    #if os(tvOS)
    private let channelImageSize: CGFloat = 80
    private let titleSize: CGFloat = 29
    private let bodySize: CGFloat = 25
    #else
    private let channelImageSize: CGFloat = 50
    private let titleSize: CGFloat = 17
    private let bodySize: CGFloat = 14
    #endif
    
    private var fullView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section title
            Text("YouTube Channel")
                .font(.system(size: titleSize, weight: .bold))
                .foregroundColor(.white)
            
            // Channel info
            HStack(spacing: 16) {
                // Channel thumbnail
                AsyncImage(url: URL(string: movie.channelThumbnail ?? "")) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: channelImageSize, height: channelImageSize)
                            .shimmer()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: channelImageSize, height: channelImageSize)
                            .clipShape(Circle())
                    case .failure:
                        // Fallback: YouTube icon
                        Circle()
                            .fill(Color.red)
                            .frame(width: channelImageSize, height: channelImageSize)
                            .overlay {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: channelImageSize * 0.4))
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                .accessibilityLabel("\(movie.channelTitle) channel thumbnail")
                
                VStack(alignment: .leading, spacing: 6) {
                    // Channel name
                    Text(movie.channelTitle)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    // Channel link button
                    Button {
                        if let channelURL = movie.channelURL {
                            #if os(iOS)
                            UIApplication.shared.open(channelURL)
                            #else
                            // tvOS: Open in YouTube app
                            if let youtubeAppURL = URL(string: "youtube://channel/\(movie.channelId)") {
                                UIApplication.shared.open(youtubeAppURL)
                            }
                            #endif
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Visit Channel")
                        }
                        .font(.system(size: bodySize))
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Visit \(movie.channelTitle) on YouTube")
                }
                
                Spacer()
            }
            
            // Video metadata
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .background(Color.white.opacity(0.2))
                
                HStack {
                    Text("Original Video:")
                        .font(.system(size: bodySize))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
                
                Text(movie.youtubeVideoTitle)
                    .font(.system(size: bodySize))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Watch on YouTube button
                Button {
                    YouTubePlayerService.shared.playMovie(movie) { success in
                        if !success {
                            print("Failed to open YouTube app")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.red)
                        Text("Watch on YouTube")
                    }
                    .font(.system(size: bodySize, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Watch \(movie.displayTitle) on YouTube")
                .accessibilityHint("Opens video in YouTube app")
            }
        }
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
