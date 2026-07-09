import SwiftUI

// MARK: - Enhanced Movie Detail View
// Netflix-style detail screen with YouTube TOS compliance

struct MovieDetailView: View {
    let movie: Movie
    @Environment(\.dismiss) private var dismiss
    @State private var showYouTubeUnavailableAlert = false

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
                // Header with backdrop and poster (buttons overlaid inside on tvOS)
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
        #if !os(tvOS)
        .overlay(alignment: .top) {
            // Top bar: close (left) and favourite (right)
            HStack {
                Spacer()

                FavoriteButton(movieId: movie.id)
                    .scaleEffect(1.2)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 44, height: 44)
                    )

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.9))
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 44, height: 44)
                        )
                }
                .accessibilityLabel("Close")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 50)
            .ignoresSafeArea(edges: .top)
        }
        #endif
        #if os(tvOS)
        .onExitCommand {
            dismiss()
        }
        #endif
        .alert("YouTube Unavailable", isPresented: $showYouTubeUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Unable to open this video right now. Please make sure the YouTube app is installed, or try again later.")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        #if os(tvOS)
        ZStack(alignment: .bottomLeading) {
            Color.clear
            AsyncImage(url: movie.backdropURL) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(Color.gray.opacity(0.2)).shimmer()
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle().fill(Color.gray.opacity(0.3))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 580)
            .clipped()

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.black.opacity(0.4), location: 0.55),
                    .init(color: Color.black, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: 580)

            // Close + Favourite — overlaid at the top of the backdrop
            VStack(spacing: 0) {
                HStack(spacing: 32) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(20)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .shadow(color: .black.opacity(0.3), radius: 8)
                            )
                    }
                    .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 100)))
                    .accessibilityLabel("Close")

                    FavoriteButton(movieId: movie.id)

                    Spacer()
                }
                .padding(.top, 60)
                .padding(.horizontal, 80)

                Spacer()
            }
            .frame(height: 580)

            // Poster + title at the bottom of the backdrop
            HStack(alignment: .bottom, spacing: 20) {
                AsyncImage(url: movie.posterURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(Color.gray.opacity(0.2)).aspectRatio(2/3, contentMode: .fill).shimmer()
                    case .success(let image):
                        image.resizable().aspectRatio(2/3, contentMode: .fill)
                    case .failure:
                        AsyncImage(url: movie.youtubeThumbURL) { fallbackPhase in
                            switch fallbackPhase {
                            case .success(let image):
                                image.resizable().aspectRatio(2/3, contentMode: .fill)
                            default:
                                ZStack {
                                    Rectangle().fill(Color.gray.opacity(0.3)).aspectRatio(2/3, contentMode: .fill)
                                    Image(systemName: "film.fill").font(.largeTitle).foregroundColor(.gray)
                                }
                            }
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 250, height: 375)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.5), radius: 20)

                VStack(alignment: .leading, spacing: 12) {
                    Spacer().frame(height: 40)
                    Text(movie.displayTitle)
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .shadow(radius: 10)
                }
                .padding(.bottom, 12)

                Spacer()
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        #else
        // iOS landscape-optimized header
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let headerHeight: CGFloat = isLandscape ? 180 : 350
            let posterWidth: CGFloat = isLandscape ? 80 : 150
            let posterHeight: CGFloat = isLandscape ? 120 : 225
            let displayTitleSize: CGFloat = isLandscape ? 22 : titleSize

            ZStack(alignment: .bottomLeading) {
                Color.clear
                AsyncImage(url: movie.backdropURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(Color.gray.opacity(0.2)).shimmer()
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle().fill(Color.gray.opacity(0.3))
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: headerHeight)
                .clipped()

                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.black.opacity(0.4), location: 0.5),
                        .init(color: Color.black, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity)
                .frame(height: headerHeight)

                HStack(alignment: .bottom, spacing: 16) {
                    AsyncImage(url: movie.posterURL) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(Color.gray.opacity(0.2)).aspectRatio(2/3, contentMode: .fill).shimmer()
                        case .success(let image):
                            image.resizable().aspectRatio(2/3, contentMode: .fill)
                        case .failure:
                            AsyncImage(url: movie.youtubeThumbURL) { fallbackPhase in
                                switch fallbackPhase {
                                case .success(let image):
                                    image.resizable().aspectRatio(2/3, contentMode: .fill)
                                default:
                                    ZStack {
                                        Rectangle().fill(Color.gray.opacity(0.3)).aspectRatio(2/3, contentMode: .fill)
                                        Image(systemName: "film.fill").font(.largeTitle).foregroundColor(.gray)
                                    }
                                }
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: posterWidth, height: posterHeight)
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.5), radius: 10)

                    VStack(alignment: .leading, spacing: 8) {
                        Spacer()
                        Text(movie.displayTitle)
                            .font(.system(size: displayTitleSize, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(isLandscape ? 2 : 3)
                            .shadow(radius: 10)
                    }
                    .padding(.bottom, 12)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, isLandscape ? 12 : 30)
            }
            .frame(maxWidth: .infinity)
            .frame(height: headerHeight)
        }
        .frame(height: 180)
        .ignoresSafeArea(edges: .top)
        #endif
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 16) {
            // Primary: Watch on YouTube button — one tap, deep links straight
            // into the YouTube app (falling back to the web/Safari if it
            // isn't installed), using the same YouTubePlayerService call as
            // the hero banner's context menu.
            Button {
                watchOnYouTube()
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
            #if os(tvOS)
            .buttonStyle(FocusBorderButtonStyle(variant: .action(cornerRadius: 12)))
            #else
            .buttonStyle(.plain)
            .shadow(radius: 8)
            #endif
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

            // Quality
            if movie.quality != nil {
                Text("•")
                    .foregroundColor(.white.opacity(0.5))

                Text(movie.quality!)
                    .font(.system(size: captionSize, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.3))
                    .cornerRadius(6)
            }

            // Rating badge
            if let rating = movie.voteAverage ?? movie.imdbRating {
                Text("•")
                    .foregroundColor(.white.opacity(0.5))

                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating))
                        .fontWeight(.bold)
                }
                .font(.system(size: bodySize))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }

            // Year badge
            if let year = movie.formattedReleaseYear {
                Text("•")
                    .foregroundColor(.white.opacity(0.5))

                Text(year)
                    .font(.system(size: bodySize))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
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

    // MARK: - Playback

    private func watchOnYouTube() {
        #if os(iOS)
        HapticFeedback.medium()
        #endif

        // Track watch in LibraryManager
        LibraryManager.shared.trackWatch(
            movieId: movie.id,
            movieTitle: movie.displayTitle,
            posterURL: movie.posterURL
        )

        // Same service call used by the hero banner and card context menu:
        // deep-links into the native YouTube app first, falls back to the
        // web browser if it isn't installed.
        YouTubePlayerService.shared.playMovie(movie) { success in
            if !success {
                showYouTubeUnavailableAlert = true
            }
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
