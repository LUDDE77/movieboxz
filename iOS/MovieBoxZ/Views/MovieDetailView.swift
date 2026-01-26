import SwiftUI

// MARK: - Enhanced Movie Detail View
// Netflix-style detail screen with YouTube TOS compliance

struct MovieDetailView: View {
    let movie: Movie
    @Environment(\.dismiss) private var dismiss
    @State private var showingVideoPlayer = false

    // Platform-specific sizes
    #if os(tvOS)
    private let titleSize: CGFloat = 48
    private let headlineSize: CGFloat = 31
    private let bodySize: CGFloat = 29
    private let captionSize: CGFloat = 25
    #else
    private let titleSize: CGFloat = 32
    private let headlineSize: CGFloat = 20
    private let bodySize: CGFloat = 17
    private let captionSize: CGFloat = 14
    #endif

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
                #if os(tvOS)
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
                #else
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                #endif
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topLeading) {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.8))
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 44, height: 44)
                    )
            }
            .accessibilityLabel("Close")
            #if os(tvOS)
            .padding(.top, 60)
            .padding(.leading, 80)
            #else
            .padding(.top, 50)
            .padding(.leading, 20)
            #endif
        }
        .sheet(isPresented: $showingVideoPlayer) {
            VideoPlayerView(movie: movie)
        }
        #if os(tvOS)
        .onExitCommand {
            dismiss()
        }
        #endif
    }

    // MARK: - Header Section

    private var headerSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image with shimmer
            AsyncImage(url: movie.backdropURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .shimmer()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                @unknown default:
                    EmptyView()
                }
            }
            #if os(tvOS)
            .frame(height: 500)
            #else
            .frame(height: 350)
            #endif
            .clipped()

            // Gradient overlay (ensures readability)
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.black.opacity(0.4), location: 0.5),
                    .init(color: Color.black, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            #if os(tvOS)
            .frame(height: 500)
            #else
            .frame(height: 350)
            #endif

            // Poster and title overlay
            HStack(alignment: .bottom, spacing: 20) {
                // Movie poster with shimmer
                AsyncImage(url: movie.posterURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(2/3, contentMode: .fill)
                            .shimmer()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(2/3, contentMode: .fill)
                    case .failure:
                        // Fallback to YouTube thumbnail if poster fails to load
                        AsyncImage(url: movie.youtubeThumbURL) { fallbackPhase in
                            switch fallbackPhase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(2/3, contentMode: .fill)
                            default:
                                // If YouTube thumbnail also fails, show placeholder
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .aspectRatio(2/3, contentMode: .fill)
                                    Image(systemName: "film.fill")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                #if os(tvOS)
                .frame(width: 250, height: 375)
                .cornerRadius(16)
                #else
                .frame(width: 150, height: 225)
                .cornerRadius(12)
                #endif
                .shadow(color: .black.opacity(0.5), radius: 20)
                .overlay(alignment: .topTrailing) {
                    // Favorite button overlay
                    FavoriteButton(movieId: movie.id)
                        .padding(8)
                }

                // Title and rating
                VStack(alignment: .leading, spacing: 12) {
                    Text(movie.displayTitle)
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .shadow(radius: 10)

                    // Rating badges
                    HStack(spacing: 10) {
                        // Display rating: prefer TMDB, fallback to IMDB
                        if let rating = movie.voteAverage ?? movie.imdbRating {
                            HStack(spacing: 6) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .fontWeight(.bold)
                            }
                            .font(.system(size: headlineSize))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                        }

                        if let year = movie.formattedReleaseYear {
                            Text(year)
                                .font(.system(size: headlineSize))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                        }
                    }

                    Spacer()
                }
                .padding(.bottom, 12)

                Spacer()
            }
            #if os(tvOS)
            .padding(.horizontal, 80)
            .padding(.bottom, 40)
            #else
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            #endif
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 16) {
            // Primary: Watch on YouTube button
            Button {
                // Track watch in LibraryManager
                LibraryManager.shared.trackWatch(
                    movieId: movie.id,
                    movieTitle: movie.displayTitle,
                    posterURL: movie.posterURL
                )
                showingVideoPlayer = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: headlineSize))
                    Text("Watch on YouTube")
                        .font(.system(size: headlineSize, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                #if os(tvOS)
                .padding(.vertical, 20)
                #else
                .padding(.vertical, 16)
                #endif
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .shadow(radius: 8)
            .accessibilityLabel("Watch \(movie.displayTitle) on YouTube")
            .accessibilityHint("Opens video in YouTube app")

            // Secondary actions
            #if os(iOS)
            HStack(spacing: 16) {
                // Add to Library
                Button {
                    // TODO: Implement
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "bookmark")
                            .font(.title2)
                        Text("Save")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(10)
                }

                // Share
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
                    VStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                        Text("Share")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(10)
                }
            }
            #endif
        }
        .padding(.top, 20)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        HStack(spacing: 12) {
            // Runtime
            if movie.runtimeMinutes != nil {
                Text(movie.formattedRuntime)
                    .font(.system(size: bodySize))
                    .foregroundColor(.white.opacity(0.8))
            }

            if movie.runtimeMinutes != nil && movie.voteCount != nil {
                Text("•")
                    .foregroundColor(.white.opacity(0.5))
            }

            // Vote count
            if let voteCount = movie.voteCount {
                Text("\(voteCount) ratings")
                    .font(.system(size: bodySize))
                    .foregroundColor(.white.opacity(0.8))
            }

            if movie.voteCount != nil && movie.quality != nil {
                Text("•")
                    .foregroundColor(.white.opacity(0.5))
            }

            // Quality
            if let quality = movie.quality {
                Text(quality)
                    .font(.system(size: captionSize, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.3))
                    .cornerRadius(6)
            }

            Spacer()
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let description = movie.description {
                Text(description)
                    .font(.system(size: bodySize))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(6)
            } else {
                Text("No description available")
                    .font(.system(size: bodySize))
                    .foregroundColor(.white.opacity(0.6))
                    .italic()
            }
        }
    }

    // MARK: - Genres Section

    private func genresSection(_ genres: [Genre]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genres")
                .font(.system(size: headlineSize, weight: .bold))
                .foregroundColor(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(genres) { genre in
                        Text(genre.name)
                            .font(.system(size: bodySize))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.red.opacity(0.3),
                                        Color.purple.opacity(0.3)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                            .accessibilityLabel("Genre: \(genre.name)")
                    }
                }
            }
        }
    }

    // MARK: - Additional Info Section

    private var additionalInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Additional Information")
                .font(.system(size: headlineSize, weight: .bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 10) {
                infoRow(label: "Views", value: movie.formattedViewCount)

                if let releaseDate = movie.releaseDate {
                    infoRow(label: "Release Date", value: formatDate(releaseDate))
                }

                if let tmdbId = movie.tmdbId {
                    infoRow(label: "TMDB ID", value: "#\(tmdbId)")
                }
            }
        }
    }

    // MARK: - Channel Section (YouTube TOS Compliance)

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 8)

            // TOS-compliant YouTube attribution (full style)
            YouTubeAttribution(movie: movie, style: .full)

            // Attribution notice
            Text("This content is hosted on YouTube and subject to YouTube's Terms of Service. MovieBoxZ does not host or stream any video content.")
                .font(.system(size: captionSize - 2))
                .foregroundColor(.white.opacity(0.5))
                .lineSpacing(4)
                .padding(.top, 8)
        }
    }

    // MARK: - Helper Views

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: bodySize))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: bodySize))
                .foregroundColor(.white)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let sampleMovie = Movie(
        id: UUID().uuidString,
        youtubeVideoId: "FC6jFoYm3xs",
        title: "Nosferatu",
        originalTitle: "Nosferatu: A Symphony of Horror (1922)",
        description: "A vampire named Count Orlok becomes interested in the new residence of a man named Thomas Hutter and his wife, Ellen. Hutter goes to work for the count and moves to Transylvania to close the deal.",
        releaseDate: Calendar.current.date(from: DateComponents(year: 1922, month: 3, day: 4)),
        runtimeMinutes: 94,
        youtubeVideoTitle: "FREE CLASSIC HORROR MOVIE - Nosferatu (1922) Full Length Silent Film",
        channelId: "UCTimelessClassicMovie",
        channelTitle: "Timeless Classic Movies",
        channelThumbnail: "https://yt3.googleusercontent.com/example",
        viewCount: 850000,
        likeCount: 12500,
        commentCount: 1800,
        publishedAt: Date(),
        lastRefreshed: Date(),
        tmdbId: 616,
        imdbId: "tt0013442",
        posterPath: "/rRQ6mZfQRJFHZrJKgPgWH2nGNZM.jpg",
        backdropPath: "/2o7FAk6rZsS7bRnz5HlqMzQrDqQ.jpg",
        voteAverage: 7.9,
        voteCount: 1850,
        popularity: 95.8,
        imdbRating: nil,
        rated: nil,
        category: "horror",
        quality: "HD",
        featured: true,
        trending: true,
        isAvailable: true,
        isEmbeddable: true,
        genres: [
            Genre(id: 27, name: "Horror", tmdbId: nil, movieCount: nil),
            Genre(id: 14, name: "Fantasy", tmdbId: nil, movieCount: nil),
            Genre(id: 18, name: "Drama", tmdbId: nil, movieCount: nil)
        ],
        addedAt: Date(),
        lastValidated: Date()
    )

    MovieDetailView(movie: sampleMovie)
        .preferredColorScheme(.dark)
}
