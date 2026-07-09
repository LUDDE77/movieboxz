import SwiftUI

@main
struct MovieBoxZAdminApp: App {
    init() {
        // Set default backend URL if not already configured.
        // Each team member sets their own API key in Preferences (Cmd+,).
        // Never hardcode credentials here — they end up in git history.
        if UserDefaults.standard.string(forKey: "apiBaseURL") == nil {
            UserDefaults.standard.set("https://movieboxz-backend-production.up.railway.app", forKey: "apiBaseURL")
        }
    }

    var body: some Scene {
        WindowGroup {
            AdminView()
                .frame(minWidth: 1200, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            AppSettingsView()
        }
    }
}
