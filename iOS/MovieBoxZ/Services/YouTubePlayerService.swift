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
        guard let youtubeURL = URL(string: "youtube://") else {
            #if DEBUG
            print("❌ Failed to create youtube:// URL")
            #endif
            return false
        }
        let canOpen = UIApplication.shared.canOpenURL(youtubeURL)
        #if DEBUG
        #if os(tvOS)
        print("🔍 [tvOS] canOpenURL(youtube://) = \(canOpen)")
        #else
        print("🔍 [iOS] canOpenURL(youtube://) = \(canOpen)")
        #endif
        #endif
        return canOpen
    }

    // MARK: - Video Playback

    /// Play a YouTube video by opening it in the YouTube app or web browser
    /// - Parameters:
    ///   - videoID: The YouTube video ID
    ///   - completion: Called with true if successfully opened, false otherwise
    func playVideo(videoID: String, completion: @escaping (Bool) -> Void = { _ in }) {
        #if os(tvOS)
        // tvOS YouTube app uses proper URL scheme with path structure
        // Format: youtube:///watch?v=VIDEO_ID (triple slash = no host, just path+query)
        let youtubeAppURL = URL(string: "youtube:///watch?v=\(videoID)")
        #if DEBUG
        print("📺 [tvOS] Attempting to open YouTube app with URL: \(youtubeAppURL?.absoluteString ?? "nil")")
        if let baseURL = URL(string: "youtube://") {
            let canOpenBase = UIApplication.shared.canOpenURL(baseURL)
            print("🔍 [tvOS] canOpenURL(youtube://) = \(canOpenBase)")
        }
        #endif

        if let url = youtubeAppURL {
            let canOpenFull = UIApplication.shared.canOpenURL(url)
            #if DEBUG
            print("🔍 [tvOS] canOpenURL(\(url.absoluteString)) = \(canOpenFull)")
            #endif

            if canOpenFull {
                #if DEBUG
                print("📺 [tvOS] YouTube app is available, opening video")
                #endif
                UIApplication.shared.open(url, options: [:]) { success in
                    #if DEBUG
                    if success {
                        print("✅ [tvOS] YouTube app opened successfully to video")
                    } else {
                        print("❌ [tvOS] YouTube app failed to open")
                    }
                    #endif
                    completion(success)
                }
            } else {
                #if DEBUG
                print("❌ [tvOS] canOpenURL returned false — YouTube app may not be installed")
                print("   OR LSApplicationQueriesSchemes not configured properly")
                #endif
                completion(false)
            }
        } else {
            #if DEBUG
            print("❌ [tvOS] Failed to create YouTube URL")
            #endif
            completion(false)
        }
        #else
        // iOS: youtube:///watch?v=VIDEO_ID (triple slash = no host, just path+query)
        if let youtubeAppURL = URL(string: "youtube:///watch?v=\(videoID)"),
           UIApplication.shared.canOpenURL(youtubeAppURL) {
            #if DEBUG
            print("📺 Opening in YouTube app: \(youtubeAppURL.absoluteString)")
            #endif
            UIApplication.shared.open(youtubeAppURL, options: [:]) { success in
                #if DEBUG
                if success {
                    print("✅ YouTube app opened successfully")
                } else {
                    print("❌ YouTube app failed to open, trying web fallback")
                }
                #endif
                if !success {
                    self.openInWeb(videoID: videoID, completion: completion)
                } else {
                    completion(success)
                }
            }
            return
        }

        #if DEBUG
        print("📱 YouTube app not available, opening in Safari")
        #endif
        openInWeb(videoID: videoID, completion: completion)
        #endif
    }

    /// Opens video in Safari or default browser
    private func openInWeb(videoID: String, completion: @escaping (Bool) -> Void) {
        guard let webURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else {
            #if DEBUG
            print("❌ Failed to create web URL")
            #endif
            completion(false)
            return
        }

        #if DEBUG
        print("🌐 Opening in browser: \(webURL.absoluteString)")
        #endif
        UIApplication.shared.open(webURL, options: [:]) { success in
            #if DEBUG
            print(success ? "✅ Browser opened" : "❌ Browser failed")
            #endif
            completion(success)
        }
    }

    /// Play a YouTube video using a Movie object
    func playMovie(_ movie: Movie, completion: @escaping (Bool) -> Void = { _ in }) {
        // Record the watch HERE — the single point where a movie is actually
        // handed off to YouTube. Opening a movie's detail card must NOT count
        // as watched; only pressing "Watch on YouTube" (which routes here) does.
        LibraryManager.shared.trackWatch(
            movieId: movie.id,
            movieTitle: movie.displayTitle,
            posterURL: movie.posterURL
        )
        playVideo(videoID: movie.youtubeVideoId, completion: completion)
    }

    // MARK: - Channel Navigation

    /// Open a YouTube channel in the YouTube app or web browser
    func openChannel(channelID: String, completion: @escaping (Bool) -> Void = { _ in }) {
        #if os(tvOS)
        // tvOS: Channel deep linking not well supported, use web
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

    /// Open the App Store to install the YouTube app (iOS only)
    func promptInstallYouTubeApp(completion: @escaping (Bool) -> Void = { _ in }) {
        #if os(iOS)
        if let appStoreURL = URL(string: "https://apps.apple.com/app/youtube-watch-listen-stream/id544007664") {
            UIApplication.shared.open(appStoreURL, options: [:]) { success in
                completion(success)
            }
        } else {
            completion(false)
        }
        #elseif os(tvOS)
        // tvOS users install from their own App Store
        completion(false)
        #endif
    }

    // MARK: - URL Helpers

    func getYouTubeAppURL(for videoID: String) -> URL? {
        URL(string: "youtube:///watch?v=\(videoID)")
    }

    func getYouTubeWebURL(for videoID: String) -> URL? {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    func getChannelAppURL(for channelID: String) -> URL? {
        #if os(tvOS)
        return nil
        #else
        return URL(string: "youtube://channel/\(channelID)")
        #endif
    }

    func getChannelWebURL(for channelID: String) -> URL? {
        URL(string: "https://www.youtube.com/channel/\(channelID)")
    }
}
