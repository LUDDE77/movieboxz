import SwiftUI

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .landscape
    }
}
#endif

@main
struct MovieBoxZApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    // Records the LegalContent.termsVersion the user accepted on the Welcome
    // screen. A future version bump makes this < current and re-shows Welcome.
    @AppStorage("acceptedTermsVersion") private var acceptedTermsVersion = 0

    // One MovieService instance for the whole app lifetime. Injected via
    // .environmentObject so every screen (and everything it presents in a
    // .sheet/.fullScreenCover, which inherits the environment) shares the
    // same connection state and cached Browse data instead of each view
    // creating its own instance (which re-fired /health checks and
    // refetched everything on every tab switch).
    @StateObject private var movieService = MovieService()

    #if os(iOS)
    @State private var safeInsets = EdgeInsets()
    #endif

    private var isUITesting: Bool {
        // Compiled out of Release: the legal-acceptance gate can never be
        // skipped via a launch argument in a shipping build.
        #if DEBUG
        return CommandLine.arguments.contains("UI_TESTING_SKIP_WELCOME")
        #else
        return false
        #endif
    }

    init() {
        // Large shared cache so AsyncImage (which uses URLSession.shared)
        // caches posters/backdrops across focus/scroll instead of refetching
        // and redecoding on every card re-instantiation.
        URLCache.shared = URLCache(memoryCapacity: 100_000_000, diskCapacity: 500_000_000)
    }

    var body: some Scene {
        WindowGroup {
            if isUITesting || (hasSeenWelcome && acceptedTermsVersion >= LegalContent.termsVersion) {
                #if os(iOS)
                // Read the REAL safe-area insets via a BACKGROUND reader (which
                // doesn't bound the content — a GeometryReader wrapper would clip
                // the fullscreen backdrop to the safe area and leave a black
                // strip). Inject them so content clears the notch in landscape
                // while backdrops still bleed edge-to-edge.
                SplashScreenView()
                    // .background BEFORE .ignoresSafeArea so the reader still
                    // sees the REAL insets (they get zeroed after ignore). The
                    // background doesn't constrain the content, so the backdrop
                    // still bleeds to every edge — no black strip.
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SafeInsetsPreferenceKey.self,
                                value: proxy.safeAreaInsets
                            )
                        }
                    )
                    .ignoresSafeArea()
                    .onPreferenceChange(SafeInsetsPreferenceKey.self) { safeInsets = $0 }
                    .environment(\.contentSafeInsets, safeInsets)
                #else
                SplashScreenView()
                #endif
            } else {
                WelcomeView(hasSeenWelcome: $hasSeenWelcome)
            }
        }
        .environmentObject(movieService)
    }
}

// MARK: - MovieBoxZ brand palette
// Marquee gold leads the identity; cinema red is reserved for play/live.
extension Color {
    static let mbzInk    = Color(red: 0.055, green: 0.043, blue: 0.063) // #0E0B10 Projection Black
    static let mbzSlate  = Color(red: 0.118, green: 0.090, blue: 0.133) // #1E1722 Reel Slate
    static let mbzGold   = Color(red: 0.910, green: 0.698, blue: 0.290) // #E8B24A Marquee Gold
    static let mbzGoldHi = Color(red: 0.965, green: 0.831, blue: 0.533) // #F6D488 Gold highlight
    static let mbzRed    = Color(red: 0.886, green: 0.227, blue: 0.180) // #E23A2E Cinema Red
    static let mbzScreen = Color(red: 0.953, green: 0.929, blue: 0.886) // #F3EDE2 Screen White
    static let mbzMuted  = Color(red: 0.663, green: 0.624, blue: 0.690) // #A99FB0 Plum Grey
}
