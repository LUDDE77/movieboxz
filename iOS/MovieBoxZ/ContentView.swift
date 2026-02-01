import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MainBrowseView()
                .tabItem {
                    Image(systemName: "tv.fill")
                    Text("Browse")
                }
                .tag(0)

            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
                .tag(1)

            LibraryView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Library")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(3)
        }
        .accentColor(.red)
        #if os(tvOS)
        .tabViewStyle(.automatic)
        #endif
    }
}

#Preview {
    ContentView()
}