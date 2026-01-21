import Foundation
import UIKit

/// Service for handling YouTube video playback through deep linking
/// This is the TOS-compliant way to play YouTube videos on iOS and tvOS
@MainActor
class YouTubePlayerService {

    static let shared = YouTubePlayerService()

    private init() {}

    // MARK: - YouTube App Detection

    /// Check if YouTube app is installed on the device
    func isYouTubeAppInstalled() -> Bool {
        #if os(tvOS)
        // tvOS uses vnd.youtube:// URL scheme
        guard let youtubeURL = URL(string: "vnd.youtube://") else { return false }
        #else
        // iOS uses youtube:// URL scheme
        guard let youtubeURL = URL(string: "youtube://") else { return false }
        #endif
        return UIApplication.shared.canOpenURL(youtubeURL)
    }

    // MARK: - Video Playback

    /// Play a YouTube video by opening it in the YouTube app or web browser
    /// - Parameters:
    ///   - videoID: The YouTube video ID
    ///   - completion: Called with true if successfully opened, false otherwise
    func playVideo(videoID: String, completion: @escaping (Bool) -> Void = { _ in }) {
        #if os(tvOS)
        // tvOS YouTube app uses vnd.youtube:// URL scheme
        // Format: vnd.youtube://VIDEO_ID
        let youtubeAppURL = URL(string: "vnd.youtube://\(videoID)")
        print("📺 [tvOS] Attempting to open YouTube app with URL: \(youtubeAppURL?.absoluteString ?? "nil")")

        if let url = youtubeAppURL, UIApplication.shared.canOpenURL(url) {
            print("📺 [tvOS] YouTube app is available, opening video")
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    print("✅ [tvOS] YouTube app opened successfully")
                    completion(true)
                } else {
                    print("❌ [tvOS] YouTube app failed to open")
                    completion(false)
                }
            }
        } else {
            print("❌ [tvOS] YouTube app not installed or URL cannot be opened")
            print("   Make sure YouTube app is installed from tvOS App Store")
            completion(false)
        }
        #else
        // iOS YouTube app uses youtube:// URL scheme
        // Format: youtube://www.youtube.com/watch?v=VIDEO_ID
        if let youtubeAppURL = URL(string: "youtube://www.youtube.com/watch?v=\(videoID)"),
           UIApplication.shared.canOpenURL(youtubeAppURL) {
            print("📺 Opening in YouTube app: \(youtubeAppURL.absoluteString)")
            UIApplication.shared.open(youtubeAppURL, options: [:]) { success in
                if success {
                    print("✅ YouTube app opened successfully")
                } else {
                    print("❌ YouTube app failed to open, trying web fallback")
                    // Try web fallback if YouTube app fails
                    self.openInWeb(videoID: videoID, completion: completion)
                    return
                }
                completion(success)
            }
            return
        }

        // Fallback to web URL if YouTube app not available
        print("📱 YouTube app not available, opening in Safari")
        openInWeb(videoID: videoID, completion: completion)
        #endif
    }

    /// Opens video in Safari or default browser
    private func openInWeb(videoID: String, completion: @escaping (Bool) -> Void) {
        guard let webURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else {
            print("❌ Failed to create web URL")
            completion(false)
            return
        }

        print("🌐 Opening in browser: \(webURL.absoluteString)")
        UIApplication.shared.open(webURL, options: [:]) { success in
            print(success ? "✅ Browser opened" : "❌ Browser failed")
            completion(success)
        }
    }

    /// Play a YouTube video using a Movie object
    /// - Parameters:
    ///   - movie: The movie containing YouTube video information
    ///   - completion: Called with true if successfully opened, false otherwise
    func playMovie(_ movie: Movie, completion: @escaping (Bool) -> Void = { _ in }) {
        playVideo(videoID: movie.youtubeVideoId, completion: completion)
    }

    // MARK: - Channel Navigation

    /// Open a YouTube channel in the YouTube app or web browser
    /// - Parameters:
    ///   - channelID: The YouTube channel ID
    ///   - completion: Called with true if successfully opened, false otherwise
    func openChannel(channelID: String, completion: @escaping (Bool) -> Void = { _ in }) {
        #if os(tvOS)
        // tvOS: Channel deep linking not well supported, skip to web
        if let webURL = URL(string: "https://www.youtube.com/channel/\(channelID)") {
            UIApplication.shared.open(webURL, options: [:]) { success in
                completion(success)
            }
        } else {
            completion(false)
        }
        #else
        // iOS: Try YouTube app first
        if let youtubeAppURL = URL(string: "youtube://channel/\(channelID)"),
           UIApplication.shared.canOpenURL(youtubeAppURL) {
            UIApplication.shared.open(youtubeAppURL, options: [:]) { success in
                completion(success)
            }
            return
        }

        // Fallback to web URL
        if let webURL = URL(string: "https://www.youtube.com/channel/\(channelID)") {
            UIApplication.shared.open(webURL, options: [:]) { success in
                completion(success)
            }
        } else {
            completion(false)
        }
        #endif
    }

    // MARK: - YouTube App Install

    /// Open the App Store to install the YouTube app
    /// Only works on iOS, not tvOS (tvOS users can install from their App Store)
    func promptInstallYouTubeApp(completion: @escaping (Bool) -> Void = { _ in }) {
        #if os(iOS)
        // YouTube App Store URL
        if let appStoreURL = URL(string: "https://apps.apple.com/app/youtube-watch-listen-stream/id544007664") {
            UIApplication.shared.open(appStoreURL, options: [:]) { success in
                completion(success)
            }
        } else {
            completion(false)
        }
        #elseif os(tvOS)
        // On tvOS, users need to manually install from App Store
        // We can't programmatically open App Store to a specific app
        completion(false)
        #endif
    }

    // MARK: - URL Helpers

    /// Get the YouTube app URL for a video
    func getYouTubeAppURL(for videoID: String) -> URL? {
        #if os(tvOS)
        return URL(string: "vnd.youtube://\(videoID)")
        #else
        return URL(string: "youtube://www.youtube.com/watch?v=\(videoID)")
        #endif
    }

    /// Get the YouTube web URL for a video
    func getYouTubeWebURL(for videoID: String) -> URL? {
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    /// Get the YouTube app URL for a channel
    func getChannelAppURL(for channelID: String) -> URL? {
        #if os(tvOS)
        // tvOS doesn't support channel deep linking well
        return nil
        #else
        return URL(string: "youtube://channel/\(channelID)")
        #endif
    }

    /// Get the YouTube web URL for a channel
    func getChannelWebURL(for channelID: String) -> URL? {
        return URL(string: "https://www.youtube.com/channel/\(channelID)")
    }
}
