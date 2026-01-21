import SwiftUI

// MARK: - Netflix-Style Movie Detail View
// Shows comprehensive movie information similar to Netflix's detail screen

struct MovieDetailView: View {
    let movie: Movie
    @Environment(\.dismiss) private var dismiss
    @State private var showingVideoPlayer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header with backdrop and poster
                headerSection

                // Content section
                VStack(alignment: .leading, spacing: 24) {
                    // Play button and action buttons
                    actionButtons

                    // Movie metadata
                    metadataSection

                    // Description
                    descriptionSection

                    // Genres
                    if let genres = movie.genres, !genres.isEmpty {
                        genresSection(genres)
                    }

                    // Additional info
                    additionalInfoSection

                    // Channel info (YouTube compliance)
                    channelSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topLeading) {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding(.top, 50)
            .padding(.leading, 20)
        }
        .sheet(isPresented: $showingVideoPlayer) {
            VideoPlayerView(movie: movie)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image
            AsyncImage(url: movie.backdropURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(height: 350)
            .clipped()

            // Gradient overlay
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.black.opacity(0.4), location: 0.5),
                    .init(color: Color.black, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 350)

            // Poster and title overlay
            HStack(alignment: .bottom, spacing: 16) {
                // Movie poster
                AsyncImage(url: movie.posterURL) { image in
                    image
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "film.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        )
                        .aspectRatio(2/3, contentMode: .fill)
                }
                .frame(width: 120, height: 180)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.5), radius: 10)

                // Title and basic info
                VStack(alignment: .leading, spacing: 8) {
                    Text(movie.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(3)

                    if let originalTitle = movie.originalTitle, originalTitle != movie.title {
                        Text(originalTitle)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.bottom, 8)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Play button
            Button {
                showingVideoPlayer = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.title3)
                    Text("Play")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Secondary buttons
            HStack(spacing: 12) {
                // Add to Library button
                Button {
                    // TODO: Implement add to library
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.title2)
                        Text("My List")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                // Share button
                Button {
                    if let url = movie.youtubeURL {
                        let activityVC = UIActivityViewController(
                            activityItems: [url],
                            applicationActivities: nil
                        )

                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootVC = windowScene.windows.first?.rootViewController {
                            rootVC.present(activityVC, animated: true)
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                        Text("Share")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        HStack(spacing: 16) {
            // Rating
            if let rating = movie.voteAverage {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
            }

            // Year
            if let year = movie.formattedReleaseYear {
                Text(year)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }

            // Runtime
            if movie.runtimeMinutes != nil {
                Text(movie.formattedRuntime)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }

            // Quality badge
            if let quality = movie.quality {
                Text(quality)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(4)
            }

            Spacer()
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let description = movie.description {
                Text(description)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineSpacing(4)
            } else {
                Text("No description available")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.6))
                    .italic()
            }
        }
    }

    // MARK: - Genres Section

    private func genresSection(_ genres: [Genre]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genres")
                .font(.headline)
                .foregroundColor(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(genres) { genre in
                        Text(genre.name)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(16)
                    }
                }
            }
        }
    }

    // MARK: - Additional Info Section

    private var additionalInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Additional Information")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                // Views
                infoRow(label: "Views", value: movie.formattedViewCount)

                // Vote count
                if let voteCount = movie.voteCount {
                    infoRow(label: "Ratings", value: "\(voteCount) votes")
                }

                // TMDB ID
                if let tmdbId = movie.tmdbId {
                    infoRow(label: "TMDB ID", value: "#\(tmdbId)")
                }

                // IMDB ID
                if let imdbId = movie.imdbId {
                    infoRow(label: "IMDB ID", value: imdbId)
                }

                // Release date
                if let releaseDate = movie.releaseDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    infoRow(label: "Release Date", value: formatter.string(from: releaseDate))
                }
            }
        }
    }

    // MARK: - Channel Section (YouTube TOS Compliance)

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(Color.white.opacity(0.2))

            Text("Hosted on YouTube")
                .font(.headline)
                .foregroundColor(.white)

            HStack(spacing: 12) {
                // Channel thumbnail
                if let thumbnailURL = movie.channelThumbnail,
                   let url = URL(string: thumbnailURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(movie.channelTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text("YouTube Channel")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                // Visit channel button
                if let channelURL = movie.channelURL {
                    Link(destination: channelURL) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(.vertical, 8)

            // Attribution
            Text("This content is hosted on YouTube and subject to YouTube's Terms of Service. MovieBoxZ does not host any video content.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .lineSpacing(2)
        }
    }

    // MARK: - Helper Views

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleMovie = Movie(
        id: UUID().uuidString,
        youtubeVideoId: "FC6jFoYm3xs",
        title: "Nosferatu",
        originalTitle: "Nosferatu: A Symphony of Horror (1922)",
        description: "A vampire named Count Orlok (Max Schreck) becomes interested in the new residence of a man named Thomas Hutter (Gustav von Wangenheim), and his wife, Ellen (Greta Schröder). Hutter goes to work for the count and moves to Transylvania to close the deal. However, as soon as he crosses into Orlok's territory, he finds himself plagued by paranoia and nightmares. Meanwhile, Ellen becomes hypnotized by Orlok, who begins to exert his will over her.",
        releaseDate: Calendar.current.date(from: DateComponents(year: 1922, month: 3, day: 4)),
        runtimeMinutes: 94,
        channelId: "UCTimelessClassicMovie",
        channelTitle: "Timeless Classic Movies",
        channelThumbnail: "https://yt3.googleusercontent.com/example",
        viewCount: 850000,
        likeCount: 12500,
        commentCount: 1800,
        publishedAt: Date(),
        tmdbId: 616,
        imdbId: "tt0013442",
        posterPath: "/rRQ6mZfQRJFHZrJKgPgWH2nGNZM.jpg",
        backdropPath: "/2o7FAk6rZsS7bRnz5HlqMzQrDqQ.jpg",
        voteAverage: 7.9,
        voteCount: 1850,
        popularity: 95.8,
        category: "horror",
        quality: "HD",
        featured: true,
        trending: true,
        isAvailable: true,
        isEmbeddable: true,
        genres: [
            Genre(id: 27, name: "Horror"),
            Genre(id: 14, name: "Fantasy"),
            Genre(id: 18, name: "Drama")
        ],
        addedAt: Date(),
        lastValidated: Date()
    )

    return MovieDetailView(movie: sampleMovie)
        .preferredColorScheme(.dark)
}
