import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        #if os(tvOS)
        TabView(selection: $selectedTab) {
            MainBrowseView()
                .tabItem {
                    Image(systemName: "tv.fill")
                    Text("Browse")
                }
                .tag(0)

            TVSeriesView()
                .tabItem {
                    Image(systemName: "tv")
                    Text("Series")
                }
                .tag(1)

            KidsView()
                .tabItem {
                    Image(systemName: "star.circle.fill")
                    Text("Kids")
                }
                .tag(2)

            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
                .tag(3)

            LibraryView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Library")
                }
                .tag(4)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(5)
        }
        .accentColor(.red)
        .tabViewStyle(.automatic)
        #else
        iOSLayout
        #endif
    }

    #if os(iOS)
    private var iOSLayout: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Full-screen black base
                Color.black

                // Tab content fills the full screen so its own
                // internal .ignoresSafeArea() calls work correctly
                tabContent
                    .frame(width: geo.size.width, height: geo.size.height)

                // Tab bar: fixed height, anchored to the bottom of the screen.
                // It renders over the content (higher z-order in the ZStack).
                CustomTabBar(selectedTab: $selectedTab)
                    .frame(width: geo.size.width)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // The GeometryReader must see the full screen dimensions so that
        // geo.size matches the physical screen (landscape: 852 x 393).
        .ignoresSafeArea()
        .statusBarHidden()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: MainBrowseView()
        case 1: TVSeriesView()
        case 2: KidsView()
        case 3: SearchView()
        case 4: LibraryView()
        default: SettingsView()
        }
    }
    #endif
}

#if os(iOS)
private struct CustomTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(icon: String, label: String)] = [
        ("tv.fill",          "Browse"),
        ("tv",               "TV Series"),
        ("star.circle.fill", "Kids"),
        ("magnifyingglass",  "Search"),
        ("heart.fill",       "Library"),
        ("gearshape.fill",   "Settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                Button {
                    if selectedTab != index {
                        HapticFeedback.selection()
                    }
                    selectedTab = index
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 20))
                        Text(tabs[index].label)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(selectedTab == index ? .red : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.black.opacity(0.85))
    }
}
#endif

#Preview {
    ContentView()
        .environmentObject(MovieService())
}
