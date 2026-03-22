import SwiftUI

@main
struct MovieBoxZApp: App {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    private var isUITesting: Bool {
        CommandLine.arguments.contains("UI_TESTING_SKIP_WELCOME")
    }

    var body: some Scene {
        WindowGroup {
            if hasSeenWelcome || isUITesting {
                SplashScreenView()
            } else {
                WelcomeView(hasSeenWelcome: $hasSeenWelcome)
            }
        }
    }
}
