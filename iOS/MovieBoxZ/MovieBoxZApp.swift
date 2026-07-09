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

    // One MovieService instance for the whole app lifetime. Injected via
    // .environmentObject so every screen (and everything it presents in a
    // .sheet/.fullScreenCover, which inherits the environment) shares the
    // same connection state and cached Browse data instead of each view
    // creating its own instance (which re-fired /health checks and
    // refetched everything on every tab switch).
    @StateObject private var movieService = MovieService()

    private var isUITesting: Bool {
        CommandLine.arguments.contains("UI_TESTING_SKIP_WELCOME")
    }

    var body: some Scene {
        WindowGroup {
            if hasSeenWelcome || isUITesting {
                SplashScreenView()
                    #if os(iOS)
                    .ignoresSafeArea()
                    #endif
            } else {
                WelcomeView(hasSeenWelcome: $hasSeenWelcome)
            }
        }
        .environmentObject(movieService)
    }
}
