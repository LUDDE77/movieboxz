import SwiftUI

@main
struct MovieBoxZApp: App {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some Scene {
        WindowGroup {
            if hasSeenWelcome {
                SplashScreenView()
            } else {
                WelcomeView(hasSeenWelcome: $hasSeenWelcome)
            }
        }
    }
}
