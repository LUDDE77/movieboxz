import SwiftUI
import UIKit

/// Presents the branded pre-roll (`WatchInterstitialView`) over whatever is on
/// screen, then hands off to YouTube — used by the "watch" paths that aren't the
/// main detail button (card context menu, video-player component). It presents
/// from the top-most view controller the same way an ad SDK does, so it works
/// over sheets/covers and on both iOS and tvOS. This is also the seam a Google
/// AdMob interstitial (iOS) drops into later: swap what's presented, keep the
/// `openYouTube` hand-off.
@MainActor
final class WatchCoordinator {
    static let shared = WatchCoordinator()
    private init() {}

    private weak var presented: UIViewController?

    /// Show the pre-roll for `movie`, then deep-link to YouTube when it finishes.
    func requestWatch(_ movie: Movie) {
        guard presented == nil, let top = Self.topViewController() else {
            openYouTube(movie)   // no host available — just play
            return
        }

        let interstitial = WatchInterstitialView(
            onComplete: { [weak self] in self?.dismiss { self?.openYouTube(movie) } },
            onCancel:   { [weak self] in self?.dismiss(nil) }
        )
        let host = UIHostingController(rootView: interstitial)
        host.modalPresentationStyle = .fullScreen
        #if os(iOS)
        host.modalTransitionStyle = .crossDissolve
        #endif
        presented = host
        top.present(host, animated: true)
    }

    private func dismiss(_ then: (() -> Void)?) {
        guard let host = presented else { then?(); return }
        presented = nil
        host.dismiss(animated: true) { then?() }
    }

    private func openYouTube(_ movie: Movie) {
        YouTubePlayerService.shared.playMovie(movie) { _ in }
    }

    /// Walk the presentation/navigation/tab hierarchy to the front-most controller.
    static func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        if let nav = root as? UINavigationController {
            return topViewController(nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(presented)
        }
        return root
    }
}
