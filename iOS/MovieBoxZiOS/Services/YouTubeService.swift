import UIKit
import SafariServices

// MARK: - YouTubeService

@MainActor
class YouTubeService {
    static let shared = YouTubeService()
    private init() {}

    // MARK: - Playback

    func playMovie(_ movie: Movie) {
        // Try YouTube app first (deep link)
        if let appURL = movie.youtubeAppURL, UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
            return
        }
        // Fallback: open in Safari
        if let webURL = movie.youtubeURL {
            UIApplication.shared.open(webURL)
        }
    }

    func openChannel(channelId: String) {
        let appURL = URL(string: "youtube://channel/\(channelId)")
        let webURL = URL(string: "https://www.youtube.com/channel/\(channelId)")
        if let url = appURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = webURL {
            UIApplication.shared.open(url)
        }
    }

    var isYouTubeInstalled: Bool {
        guard let url = URL(string: "youtube://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func promptInstallYouTube() {
        if let url = URL(string: "https://apps.apple.com/app/youtube-watch-listen-stream/id544007664") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Safari Player

    func makeSafariController(for movie: Movie) -> UIViewController? {
        guard let url = movie.youtubeURL else { return nil }
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = .red
        vc.preferredBarTintColor = .black
        vc.dismissButtonStyle = .close
        return vc
    }
}
