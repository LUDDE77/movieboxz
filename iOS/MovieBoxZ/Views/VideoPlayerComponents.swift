import SwiftUI
#if os(iOS)
import SafariServices
#endif

// MARK: - Video Player View for YouTube Integration
// IMPORTANT: This implementation is YouTube TOS-compliant
//
// HYBRID APPROACH:
// - iOS: Uses SFSafariViewController (in-app browser, TOS compliant, no embed errors)
// - tvOS: Uses deep linking (WKWebView not available on tvOS)
//
// Why SFSafariViewController instead of WKWebView?
// - Many videos return error 152-4 (not embeddable in mobile apps)
// - Safari view stays in app while showing full YouTube interface
// - Fully TOS compliant with proper YouTube branding and attribution
// - All YouTube features work (ads, comments, quality selection)

struct VideoPlayerView: View {
    let movie: Movie
    @Environment(\.dismiss) private var dismiss
    @State private var showingSafariPlayer = false
    @State private var showYouTubeAppPrompt = false

    var body: some View {
        #if os(iOS)
        // iOS: Use Safari View Controller (in-app browser, no embedding restrictions)
        safariPlayerView
        #elseif os(tvOS)
        // tvOS: Use deep linking (Safari not available)
        deepLinkPlayerView
        #endif
    }

    // MARK: - iOS Safari View Player (In-App Browser)

    #if os(iOS)
    private var safariPlayerView: some View {
        ZStack {
            // Background - Movie backdrop/poster
            AsyncImage(url: movie.backdropURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.black
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()

            // Dark gradient overlay
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.7),
                    Color.black.opacity(0.4)
                ]),
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()

            // Content
            VStack(spacing: 30) {
                Spacer()

                // Movie Info
                VStack(spacing: 12) {
                    Text(movie.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Hosted on \(movie.channelTitle)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }

                // Play Button
                Button {
                    showingSafariPlayer = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.title3)
                        Text("Watch on YouTube")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .fullScreenCover(isPresented: $showingSafariPlayer) {
            SafariPlayerView(
                url: URL(string: "https://www.youtube.com/watch?v=\(movie.youtubeVideoId)")!,
                onDismiss: { showingSafariPlayer = false }
            )
            .ignoresSafeArea()
        }
    }
    #endif

    // MARK: - Deep Link Player View (tvOS only)

    private var deepLinkPlayerView: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 40) {
                    // YouTube Logo + Attribution (REQUIRED by TOS)
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.red)

                        Text("Watch on YouTube")
                            .font(.title2)
                            .foregroundColor(.white)

                        Text("Hosted on \(movie.channelTitle)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Movie Info
                    VStack(spacing: 8) {
                        Text(movie.title)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if let year = movie.formattedReleaseYear {
                            Text(year)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let description = movie.description {
                            Text(description)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal)
                        }
                    }

                    // Play Button
                    Button {
                        openInYouTubeApp()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play Movie")
                        }
                        .font(.headline)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 20)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #endif

                    // Warning if YouTube app not installed
                    if !YouTubePlayerService.shared.isYouTubeAppInstalled() {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text("YouTube App Required")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.yellow)

                            Text("Please install the YouTube app from the App Store to watch movies")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .alert("YouTube App Required", isPresented: $showYouTubeAppPrompt) {
            #if os(iOS)
            Button("Install YouTube App") {
                YouTubePlayerService.shared.promptInstallYouTubeApp()
                dismiss()
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            #else
            Button("OK", role: .cancel) {
                dismiss()
            }
            #endif
        } message: {
            Text("MovieBoxZ requires the YouTube app to watch movies. Videos cannot play in Safari/web browser.\n\nPlease install the YouTube app from the App Store.")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Helper Methods

    private func openInYouTubeApp() {
        YouTubePlayerService.shared.playMovie(movie) { success in
            if !success {
                showYouTubeAppPrompt = true
            }
        }
    }
}

// MARK: - Previews

#if os(iOS)
#Preview("iOS Embedded Player") {
    let sampleMovie = Movie(
        id: UUID().uuidString,
        youtubeVideoId: "FC6jFoYm3xs",
        title: "Nosferatu",
        originalTitle: "Nosferatu (1922)",
        description: "A classic silent horror film",
        releaseDate: Date(),
        runtimeMinutes: 94,
        channelId: "UCTimelessClassicMovie",
        channelTitle: "Timeless Classic Movies",
        channelThumbnail: nil,
        viewCount: 850000,
        likeCount: 12500,
        commentCount: 1800,
        publishedAt: Date(),
        tmdbId: 616,
        imdbId: "tt0013442",
        posterPath: nil,
        backdropPath: nil,
        voteAverage: 7.9,
        voteCount: 1850,
        popularity: 95.8,
        category: "horror",
        quality: "HD",
        featured: true,
        trending: true,
        isAvailable: true,
        isEmbeddable: true,
        genres: nil,
        addedAt: Date(),
        lastValidated: Date()
    )

    return VideoPlayerView(movie: sampleMovie)
        .preferredColorScheme(.dark)
}
#endif

#Preview("Deep Link Player (tvOS)") {
    let sampleMovie = Movie(
        id: UUID().uuidString,
        youtubeVideoId: "GVKmHbJc7lo",
        title: "One Body Too Many",
        originalTitle: "One Body Too Many (1944)",
        description: "A classic mystery comedy",
        releaseDate: Date(),
        runtimeMinutes: 75,
        channelId: "UCu5qcR-xv4qyGVmqkf3v2jw",
        channelTitle: "Classic Hollywood TV",
        channelThumbnail: nil,
        viewCount: 180691,
        likeCount: 2500,
        commentCount: 180,
        publishedAt: Date(),
        tmdbId: nil,
        imdbId: nil,
        posterPath: nil,
        backdropPath: nil,
        voteAverage: 7.2,
        voteCount: 850,
        popularity: 85.3,
        category: "mystery",
        quality: "HD",
        featured: true,
        trending: true,
        isAvailable: true,
        isEmbeddable: true,
        genres: nil,
        addedAt: Date(),
        lastValidated: Date()
    )

    return VideoPlayerView(movie: sampleMovie)
        .preferredColorScheme(.dark)
}

// MARK: - Safari View Controller (iOS only)

#if os(iOS)
/// UIViewControllerRepresentable wrapper for SFSafariViewController
/// Shows full YouTube web interface in an in-app browser
/// This avoids error 152-4 and is fully YouTube TOS compliant
struct SafariPlayerView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredControlTintColor = .systemRed
        safari.preferredBarTintColor = .black
        safari.dismissButtonStyle = .close
        safari.delegate = context.coordinator

        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }
    }
}
#endif
